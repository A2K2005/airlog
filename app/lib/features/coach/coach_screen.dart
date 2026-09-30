// Coach: the chat (pushed; owns its Scaffold). It opens straight away:
// there is no setup screen and no wall, and the coach answers on this phone
// by default (Claude or Gemini is connected in Settings → Coach).
//
//  * Header: the title, Conversations and New chat. Nothing else (no
//    data-mode label: only the data-mode screens label it).
//  * Empty: "Ask about your data", what the engine can do, the starters,
//    and one dismissible card nudging towards Claude or Gemini.
//  * Messages: questions; answers as a short reply in plain text (the
//    verifier's proof sits behind ⋯ → "Checked against your data"), metric
//    cards, today's plan actions, "What your data shows" for the facts-only
//    fallback, "Remember this?" and status toasts, and a ⋯ menu (engine,
//    data, checked numbers, what was shared, ask again, report); the calm
//    safety answer; errors with their fix.
//  * Composer: follow-up chips over one input pill, and one quiet line.
//  * A cloud session opens with the one-line AI disclosure.
//
// The list is reversed, so the newest message sits on the composer and a new
// one never makes the page jump. Only messages added in this session enter
// with motion.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart' show coachEnabledProvider;
import '../../app/copy.dart';
import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart';
import 'coach_history_screen.dart' show CoachHistoryArgs;
import 'coach_providers.dart';
import 'coach_view_model.dart';
import 'widgets/answer_block.dart';
import 'widgets/answer_text.dart';
import 'widgets/coach_sheets.dart';
import 'widgets/composer.dart';
import 'widgets/connect_card.dart';
import 'widgets/message_widgets.dart';
import 'widgets/thinking_row.dart';

/// The chat screen's own words (docs/COPY_REVIEW.md §3.6).
abstract final class ChatCopy {
  static const title = 'Coach';
  static const cantStart = 'Coach couldn’t start';
  static const cantStartBody =
      'Airlog couldn’t open Coach’s saved data. Nothing was sent.';
  static const off = 'Coach is turned off';
  static const offBody = 'Turn it on to ask about your data.';
  static const heading = 'Ask about your data';
  static const tryAsking = 'Try asking';
  static String general(String name) =>
      '$name answers from general sleep and training science, without your '
      'data.';
  static String withData(String name) =>
      '$name looks up the numbers it needs, and Airlog checks every number '
      'it quotes.';
}

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  CoachLaunch? _launch;

  /// Message ids whose entrance already played (never twice).
  final _played = <String>{};
  bool _prefilled = false;

  /// The connect card was dismissed in this session.
  bool _hintGone = false;

  CoachLaunch get launch => _launch!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _launch ??= CoachLaunch.from(ModalRoute.of(context)?.settings.arguments);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  CoachChatViewModel get _vm => ref.read(coachChatProvider(launch).notifier);

  Future<void> _send([String? text]) async {
    if (ref.read(coachChatProvider(launch)).value?.sending ?? true) return;
    final q = (text ?? _input.text).trim();
    if (q.isEmpty) return;
    final sent = _vm.send(q);
    _input.clear();
    _toLatest();
    await sent;
    if (!mounted) return;
    _toLatest();
    ref.invalidate(coachUsageProvider);
  }

  /// A suggestion tap: puts [q] in the composer. Nothing is sent until the
  /// user taps send.
  void _fill(String q) {
    _input.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    _focus.requestFocus();
  }

  /// Back to the newest message, eased out, only when scrolled away.
  void _toLatest() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    final d = motion(context, Motion.slow);
    if (d == Duration.zero) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(0, duration: d, curve: Motion.enter);
    }
  }

  /// Settings → Coach (the fix for a key or a spent account, and the
  /// connect card's "Open Settings").
  Future<void> _settings() async {
    await Navigator.of(context).pushNamed(Routes.settingsCoach);
    if (!mounted) return;
    ref.invalidate(coachConfigProvider);
    ref.invalidate(coachUsageProvider);
  }

  Future<void> _dismissHint(CoachConfig cfg) async {
    // Gone at once (it fades and folds away); saved for later launches.
    setState(() => _hintGone = true);
    try {
      final repo = ref.read(coachRepositoryProvider);
      await repo.saveSettings(
        (await repo.settings()).copyWith(cloudHintDismissed: true),
      );
    } catch (_) {}
    if (mounted) ref.invalidate(coachConfigProvider);
  }

  Future<void> _history() async {
    final id = await Navigator.of(context)
        .pushNamed(Routes.coachHistory, arguments: CoachHistoryArgs.pick);
    if (!mounted) return;
    if (id is String) {
      _played.clear();
      await _vm.openConversation(id);
    }
  }

  Future<void> _report(CoachChatState s, ChatMessage m, CoachConfig cfg) =>
      showReportSheet(
        context,
        onFlag: () async {
          await Clipboard.setData(ClipboardData(text: _reportText(s, m, cfg)));
          _vm.report(m.id);
        },
      );

  String _reportText(CoachChatState s, ChatMessage m, CoachConfig cfg) {
    final b = StringBuffer()
      ..writeln('Airlog coach report')
      ..writeln('Engine: ${cfg.engineLabel} · ${cfg.modeLabel}')
      ..writeln('Question: ${s.questionFor(m.id) ?? '(none)'}')
      ..writeln('Answer: ${plainAnswer(m.text, m.refs)}');
    for (var i = 0; i < m.refs.length; i++) {
      final r = m.refs[i];
      final v = refValue(r);
      b.writeln('Source ${i + 1}: ${r.label}${v == null ? '' : ' = $v'}');
    }
    final v = m.verification;
    if (v != null) {
      b.writeln(
        'Verification: ${v.checkedNumbers} checked, '
        '${v.unsupported.isEmpty ? 'none unsupported' : 'unsupported: ${v.unsupported.join('; ')}'}',
      );
    }
    return b.toString();
  }

  /// The second confirm before Coach remembers health history or mood.
  Future<bool> _confirmSensitive(MemoryCategory cat, String text) async {
    final yes = await showDialog<bool>(
      context: context,
      animationStyle: dialogMotion(context),
      builder: (d) => AlertDialog(
        title: Text(
          cat == MemoryCategory.mood
              ? 'Remember how you feel?'
              : 'Remember this health detail?',
        ),
        content: Text(
          '“$text” is ${cat.label.toLowerCase()}. Coach keeps it on this '
          'phone and may use it in later answers. You can delete it any '
          'time in What Coach knows.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Yes, remember'),
          ),
        ],
      ),
    );
    return yes == true;
  }

  /// "Ask (provider) again" for an answer written on this phone as the
  /// fallback, once the chosen model is no longer known to be down and
  /// today's budget is not spent.
  VoidCallback? _askAgainFor(
    CoachChatState s,
    CoachConfig cfg,
    ChatMessage m, {
    required bool spent,
  }) {
    final from = m.fallbackFrom;
    if (m.answeredBy != ChatMessage.onDevice || from == null) return null;
    if (!cfg.cloud || !cfg.ready || s.sending || spent) return null;
    final down = ref.watch(coachModelDownProvider(from));
    if (down.isLoading || down.value != null) return null;
    return () {
      _toLatest();
      _vm.askAgain(m.id);
    };
  }

  Future<void> _pickCategory(ChatMessage m, int i, MemoryCategory cur) async {
    final c = await showCategorySheet(context, cur);
    if (c != null) _vm.pickCategory(m.id, i, c);
  }

  /// One cited number's sheet, from a card, a facts tile or a row of
  /// "Checked against your data".
  void _openCite(ChatMessage m, int i) {
    if (i < 0 || i >= m.refs.length) return;
    final r = m.refs[i];
    AnswerVisual? visual;
    for (final v in m.visuals) {
      if (v.refId == r.id) visual = v;
    }
    final route = refRoute(r);
    showMetricSheet(
      context,
      ref: r,
      visual: visual,
      checked: isChecked(m),
      screenName: route == null ? null : _screenName(route),
      onOpenScreen: route == null ? null : () => openRef(context, ref, r),
    );
  }

  static String _screenName(String route) => switch (route) {
    Routes.recovery => 'Recovery',
    Routes.sleep => 'Sleep',
    Routes.strain => 'Strain',
    Routes.trends => 'Trends',
    Routes.journal => 'Journal',
    _ => 'Today',
  };

  /// Which engine wrote [m], for its ⋯ menu.
  String _engineOf(ChatMessage m, CoachConfig cfg) {
    final by = m.answeredBy;
    if (by == ChatMessage.onDevice) return AnswerCopy.onThisPhone;
    final sent = m.sent;
    final p = sent?.provider ?? cfg.provider;
    final model = by ?? sent?.model;
    if (model == null || p == CoachProvider.offline) {
      return AnswerCopy.onThisPhone;
    }
    return 'Answered by ${CoachCopy.providerName(p)} · '
        '${CoachCopy.modelName(p, model)}';
  }

  /// [ask] is "Ask again", worked out while building (it watches whether
  /// the chosen model is known to be down).
  void _menu(
    CoachChatState s,
    CoachConfig cfg,
    ChatMessage m,
    VoidCallback? ask,
  ) {
    final provider = m.sent?.provider ?? cfg.provider;
    final checked = isChecked(m);
    showAnswerMenu(
      context,
      engine: _engineOf(m, cfg),
      engineNote: CoachCopy.answeredByNote(provider, m),
      mode: m.sent?.mode == null ? null : CoachCopy.modeLabel(m.sent!.mode!),
      checked: checked,
      sources: m.refs.length,
      onSources: () => showSourcesSheet(
        context,
        message: m,
        title: checked ? AnswerCopy.checkedTitle : 'Sources',
        lede: checked ? AnswerCopy.checkedWhy : AnswerCopy.sourcesWhy,
        checked: checked,
        onOpen: (i) => _openCite(m, i),
      ),
      onShared: m.sent == null ? null : () => showSentSheet(context, m.sent!),
      askAgainLabel: CoachCopy.askAgain(provider),
      onAskAgain: ask,
      reported: s.reported.contains(m.id),
      onReport: () => _report(s, m, cfg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final async = ref.watch(coachChatProvider(launch));
    final cfgAsync = ref.watch(coachConfigProvider);
    final cfg = cfgAsync.value ?? const CoachConfig();
    final usage = cfg.cloud ? ref.watch(coachUsageProvider).value : null;
    final spent = usage?.exhausted ?? false;
    final s = async.value;
    final prefill = s?.prefill;
    if (!_prefilled && s != null) {
      _prefilled = true;
      if (prefill != null && _input.text.isEmpty) _input.text = prefill;
    }

    final Widget body;
    if (s != null) {
      body = s.isEmpty
          ? _empty(s, cfg, loaded: cfgAsync.hasValue)
          : _messages(s, cfg, spent);
    } else if (async.hasError || cfgAsync.hasError) {
      body = ListView(
        padding: const EdgeInsets.all(S.gutter),
        children: [
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: ChatCopy.cantStart,
            body: ChatCopy.cantStartBody,
            actionLabel: 'Try again',
            onAction: () {
              ref.invalidate(coachChatProvider(launch));
              ref.invalidate(coachConfigProvider);
            },
          ),
        ],
      );
    } else {
      body = const Padding(
        padding: EdgeInsets.all(S.gutter),
        child: SkeletonLines(lines: 3),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text(ChatCopy.title),
        // No data-mode label in the chat: only the data-mode screens
        // (onboarding choice, Settings, Data sources) label it.
        actions: [
          AppIconButton(
            icon: Icons.history_rounded,
            semanticLabel: 'Conversations',
            onTap: s == null || s.sending ? null : _history,
          ),
          AppIconButton(
            icon: Icons.add_comment_outlined,
            semanticLabel: 'New chat',
            onTap: s == null || s.sending || s.isEmpty
                ? null
                : () {
                    _played.clear();
                    _input.clear();
                    _vm.newChat();
                  },
          ),
          const SizedBox(width: S.x2),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: body),
          Composer(
            controller: _input,
            focusNode: _focus,
            note: cfg.cloud ? CoachCopy.aiDisclaimer : CoachCopy.notMedical,
            sending: s?.sending ?? false,
            enabled: s != null && cfgAsync.hasValue && cfg.settings.enabled,
            chips: s == null ? const [] : _chips(s, cfg),
            onChip: _fill,
            playChips:
                s != null && s.messages.isNotEmpty &&
                s.fresh.contains(s.messages.last.id),
            onSend: _send,
          ),
        ],
      ),
    );
  }

  /// The chips above the composer: a Discuss chat's questions before its
  /// first answer, then follow-ups under the latest answer.
  List<String> _chips(CoachChatState s, CoachConfig cfg) {
    if (s.sending || !cfg.settings.enabled) return const [];
    if (s.isEmpty) return s.discussing ? s.suggestions : const [];
    final last = s.messages.last;
    if (last.role != ChatRole.assistant ||
        errorKindOf(last) != null ||
        last.safety) {
      return const [];
    }
    return answerFollowUps(last, asked: s.questionFor(last.id));
  }

  /// Coach switched off (a deep link can still land here).
  Widget? _off(CoachConfig cfg) {
    if (cfg.settings.enabled) return null;
    return StatusCard(
      title: ChatCopy.off,
      body: ChatCopy.offBody,
      actionLabel: 'Turn on',
      onAction: () async {
        final repo = ref.read(coachRepositoryProvider);
        await repo.saveSettings(cfg.settings.copyWith(enabled: true));
        ref.invalidate(coachConfigProvider);
        ref.invalidate(coachEnabledProvider);
      },
    );
  }

  /// The card a "Discuss" chat is about, or null.
  Widget? _pin(CoachChatState s) {
    final h = launch.discussHeadline;
    if (!s.discussing || h == null) return null;
    return DiscussPin(headline: h, body: launch.discussBody);
  }

  /// [loaded]: the stored settings are read, so the connect card never
  /// flashes before a dismissal is known.
  Widget _empty(CoachChatState s, CoachConfig cfg, {required bool loaded}) {
    final p = P.of(context);
    final general = cfg.settings.mode == CoachMode.generalOnly;
    final name = CoachCopy.providerName(cfg.provider);
    final line = !cfg.cloud
        ? CoachCopy.onDeviceCan
        : general
        ? ChatCopy.general(name)
        : ChatCopy.withData(name);
    final off = _off(cfg);
    final pin = _pin(s);
    final hint =
        loaded &&
        !_hintGone &&
        !cfg.cloud &&
        !cfg.settings.cloudHintDismissed &&
        !s.discussing &&
        cfg.settings.enabled;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, S.x6),
      children: [
        if (cfg.cloud) ...[
          DisclosureLine(
            key: const ValueKey('disclosure'),
            provider: cfg.provider,
          ),
          const SizedBox(height: S.x5),
        ],
        if (off != null) ...[off, const SizedBox(height: S.x4)],
        if (pin != null)
          pin
        else ...[
          Semantics(
            header: true,
            child: Text(
              ChatCopy.heading,
              style: F.t1.copyWith(color: p.ink),
            ),
          ),
          const SizedBox(height: S.x2),
          Text(line, style: F.bodySm.copyWith(color: p.ink2)),
          if (s.suggestions.isNotEmpty) ...[
            const SizedBox(height: S.x6),
            const OverLabel(ChatCopy.tryAsking),
            const SizedBox(height: S.x2),
            for (final q in s.suggestions) ...[
              AppCard(
                key: ValueKey('suggestion-$q'),
                onTap: cfg.settings.enabled ? () => _send(q) : null,
                semanticLabel: 'Ask: $q',
                padding: const EdgeInsets.symmetric(
                  horizontal: S.x4,
                  vertical: S.x3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(q, style: F.body.copyWith(color: p.ink)),
                    ),
                    Icon(Icons.north_east_rounded, size: 18, color: p.ink3),
                  ],
                ),
              ),
              const SizedBox(height: S.x2),
            ],
          ],
          // It fades in once the settings are read, and on ×, fades out
          // (180 ms) while the space folds away (200 ms, ease-out).
          AnimatedSize(
            duration: motion(context, Motion.base),
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: motion(context, Motion.base, fade: true),
              reverseDuration: motion(context, Motion.exit, fade: true),
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.enter.flipped,
              child: hint
                  ? Padding(
                      key: const ValueKey('connect-hint-slot'),
                      padding: const EdgeInsets.only(top: S.x4),
                      child: ConnectHintCard(
                        onOpen: _settings,
                        onDismiss: () => _dismissHint(cfg),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ],
    );
  }

  Widget _messages(CoachChatState s, CoachConfig cfg, bool spent) {
    final off = _off(cfg);
    final pin = _pin(s);
    // Bottom-up: the thinking row, the newest message … the oldest, then
    // the discussed card and the session's disclosure at the top.
    final items = <(String, Widget)>[
      if (s.sending) ('thinking', const ThinkingRow()),
      for (var i = s.messages.length - 1; i >= 0; i--)
        (
          s.messages[i].id,
          _row(s, cfg, s.messages[i], i == s.messages.length - 1, spent),
        ),
      if (off != null) ('off', off),
      if (pin != null) ('discuss-pin', pin),
      if (cfg.cloud)
        ('disclosure', DisclosureLine(provider: cfg.provider)),
    ];
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x4, S.gutter, S.x2),
      itemCount: items.length,
      findChildIndexCallback: (key) {
        final k = (key as ValueKey<String>).value;
        final i = items.indexWhere((e) => e.$1 == k);
        return i < 0 ? null : i;
      },
      itemBuilder: (context, i) {
        final (id, w) = items[i];
        return Padding(
          key: ValueKey(id),
          padding: const EdgeInsets.only(bottom: S.x5),
          child: w,
        );
      },
    );
  }

  Widget _row(
    CoachChatState s,
    CoachConfig cfg,
    ChatMessage m,
    bool last,
    bool spent,
  ) {
    final play = s.fresh.contains(m.id) && !_played.contains(m.id);
    _played.add(m.id);
    final kind = errorKindOf(m);
    if (m.role == ChatRole.user) {
      return CoachEnter(play: play, child: UserBubble(text: m.text));
    }
    if (kind != null) {
      return CoachEnter(
        play: play,
        child: ErrorAnswer(
          kind: kind,
          provider: m.sent?.provider ?? cfg.provider,
          message: m.text,
          onSettings: last ? _settings : null,
          onRetry: last ? () => _vm.retry() : null,
        ),
      );
    }
    if (m.safety) {
      return CoachEnter(play: play, child: SafetyAnswer(text: m.text));
    }
    final provider = m.sent?.provider ?? cfg.provider;
    final ask = _askAgainFor(s, cfg, m, spent: spent);
    return AnswerBlock(
      key: ValueKey('answer-${m.id}'),
      message: m,
      play: play,
      engineGlyph: m.fellBack
          ? CoachCopy.answeredByNote(provider, m)
          : null,
      flagged: s.reported.contains(m.id),
      onCite: (i) => _openCite(m, i),
      onOpenCard: (r, _) => _openCite(m, m.refs.indexOf(r)),
      onOpenAction: (route) => Navigator.of(context).pushNamed(route),
      onMenu: () => _menu(s, cfg, m, ask),
      proposals: [
        for (var i = 0; i < m.proposedMemories.length; i++)
          if (cfg.memoryOn) ?_proposal(s, m, i),
      ],
    );
  }

  /// "Remember this?" for proposal [i], its "Saved" toast, or nothing once
  /// dismissed.
  Widget? _proposal(CoachChatState s, ChatMessage m, int i) {
    final choice = s.choiceOf(m.id, i);
    if (choice == MemoryChoice.dismissed) return null;
    // Remember turns the card into its toast: a 200 ms crossfade while the
    // height eases to the toast's (fade only, size snaps, under reduced
    // motion).
    return AnimatedSize(
      key: ValueKey('proposal-${m.id}-$i'),
      duration: motion(context, Motion.base),
      curve: Motion.enter,
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: motion(context, Motion.base, fade: true),
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.enter.flipped,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          fit: StackFit.passthrough,
          children: [...previous, ?current],
        ),
        child: choice == MemoryChoice.saved
            ? StatusToast(
                key: ValueKey('saved-${m.id}-$i'),
                icon: Icons.check_circle_outline_rounded,
                text: AnswerCopy.saved,
                actionLabel: 'View',
                onAction: () =>
                    Navigator.of(context).pushNamed(Routes.coachMemory),
              )
            : _rememberCard(s, m, i),
      ),
    );
  }

  Widget _rememberCard(CoachChatState s, ChatMessage m, int i) {
    final text = m.proposedMemories[i];
    return RememberCard(
      key: ValueKey('remember-${m.id}-$i'),
      text: text,
      expiresOn: m.proposedExpiry(i),
      category: s.categoryOf(m.id, i, text),
      onPickCategory: () =>
          _pickCategory(m, i, s.categoryOf(m.id, i, text)),
      onRemember: () async {
        // Health history and mood: a second, explicit confirm.
        final cur = ref.read(coachChatProvider(launch)).value ?? s;
        final cat = cur.categoryOf(m.id, i, text);
        if (cat.needsExplicitConfirm && !await _confirmSensitive(cat, text)) {
          return;
        }
        final ok = await _vm.saveMemory(m.id, i, text);
        if (!ok && mounted) snack(context, 'Couldn’t save. Try again.');
      },
      onDismiss: () => _vm.dismissMemory(m.id, i),
    );
  }
}
