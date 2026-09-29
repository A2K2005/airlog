// Ask: the coach chat (pushed; owns its Scaffold).
//
//  * Header: the engine chip ("On-device" / "Claude · Opus 5.5") and the
//    mode chip ("Uses your data" / "General only"), both into setup; History
//    and New chat.
//  * Empty: the suggested starters and one line on what the engine can do.
//  * Messages: questions, answers with citations, Sources, the verification
//    pill, "What was sent" for cloud answers, Report, "Remember this?"; the
//    calm safety answer; errors with their fix.
//  * Composer: the question, Brief / Detailed, "Wellness info, not medical
//    advice."
//  * A cloud session starts with the AI disclosure.
//
// The list is reversed, so the newest message sits on the composer and a new
// one never makes the page jump. Only messages added in this session enter
// with motion.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart' show coachEnabledProvider;
import '../../app/copy.dart';
import '../../app/insight_card.dart' show isSampleData;
import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart';
import 'coach_history_screen.dart' show CoachHistoryArgs;
import 'coach_providers.dart';
import 'coach_view_model.dart';
import 'widgets/answer_text.dart';
import 'widgets/coach_sheets.dart';
import 'widgets/composer.dart';
import 'widgets/message_widgets.dart';

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

  /// Back to the newest message, eased, only when scrolled away.
  void _toLatest() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    final d = motion(context, Motion.slow);
    if (d == Duration.zero) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(0, duration: d, curve: Motion.move);
    }
  }

  Future<void> _setup() async {
    await Navigator.of(context).pushNamed(Routes.coachSetup);
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

  Future<void> _report(CoachChatState s, ChatMessage m, CoachConfig cfg) async {
    final ok = await showReportSheet(
      context,
      onFlag: () async {
        await Clipboard.setData(ClipboardData(text: _reportText(s, m, cfg)));
        _vm.report(m.id);
      },
    );
    if (ok && mounted) {
      snack(context, 'Flagged on this phone. Details copied.');
    }
  }

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

  Future<void> _pickCategory(ChatMessage m, int i, MemoryCategory cur) async {
    final c = await showCategorySheet(context, cur);
    if (c != null) _vm.pickCategory(m.id, i, c);
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
      body = s.isEmpty ? _empty(s, cfg, spent) : _messages(s, cfg, spent);
    } else if (async.hasError || cfgAsync.hasError) {
      body = ListView(
        padding: const EdgeInsets.all(S.gutter),
        children: [
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Coach could not start',
            body:
                'Its storage on this phone did not answer. Nothing was '
                'sent anywhere.',
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
        title: const Text('Ask'),
        actions: [
          ...SampleDataChip.action(context),
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
          _Header(config: cfg, onTap: _setup),
          Expanded(child: body),
          Composer(
            controller: _input,
            focusNode: _focus,
            note: cfg.cloud ? CoachCopy.aiDisclaimer : CoachCopy.notMedical,
            sending: s?.sending ?? false,
            enabled: s != null && cfgAsync.hasValue && cfg.ready && !spent,
            length: cfg.settings.length,
            onLength: cfgAsync.hasValue && !(s?.sending ?? false)
                ? (l) async {
                    await saveLength(ref.read(coachRepositoryProvider), l);
                    ref.invalidate(coachConfigProvider);
                  }
                : null,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  /// Why the engine cannot answer yet, with the fix.
  Widget? _notReady(CoachConfig cfg) {
    if (!cfg.settings.enabled) {
      return StatusCard(
        title: 'Ask is turned off',
        body: 'Turn it back on to ask about your data.',
        actionLabel: 'Turn on',
        onAction: () async {
          final repo = ref.read(coachRepositoryProvider);
          await repo.saveSettings(cfg.settings.copyWith(enabled: true));
          ref.invalidate(coachConfigProvider);
          ref.invalidate(coachEnabledProvider);
        },
      );
    }
    if (cfg.cloud && !cfg.cloudReady) {
      final name = CoachCopy.providerName(cfg.provider);
      return StatusCard(
        title: 'Finish setting up $name',
        body: !cfg.hasKey
            ? 'Add your API key, or switch back to on-device.'
            : 'Confirm what $name may receive before the first question.',
        actionLabel: 'Open setup',
        onAction: _setup,
      );
    }
    return null;
  }

  /// The calm note when today's cloud budget is used up.
  Widget _spentBanner() => StatusCard(
    key: const ValueKey('usage-spent'),
    title: 'Today’s limit reached',
    body: CoachCopy.usageSpent,
    icon: Icons.hourglass_empty_rounded,
    actionLabel: 'Open setup',
    onAction: _setup,
  );

  /// The card a "Discuss" chat is about, or null.
  Widget? _pin(CoachChatState s) {
    final h = launch.discussHeadline;
    if (!s.discussing || h == null) return null;
    return DiscussPin(headline: h, body: launch.discussBody);
  }

  Widget _empty(CoachChatState s, CoachConfig cfg, bool spent) {
    final p = P.of(context);
    final general = cfg.settings.mode == CoachMode.generalOnly;
    final line = !cfg.cloud
        ? CoachCopy.onDeviceCan
        : general
        ? '${CoachCopy.providerName(cfg.provider)} answers from general sleep '
              'and training science, without your data.'
        : '${CoachCopy.providerName(cfg.provider)} looks up the numbers it '
              'needs on this phone, and every number it quotes is checked.';
    final notReady = _notReady(cfg);
    final pin = _pin(s);
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, S.x6),
      children: [
        if (cfg.cloud) ...[
          DisclosureCard(provider: cfg.provider),
          const SizedBox(height: S.x4),
        ],
        if (notReady != null) ...[notReady, const SizedBox(height: S.x4)],
        if (spent) ...[_spentBanner(), const SizedBox(height: S.x4)],
        if (pin != null) ...[
          pin,
          if (s.suggestions.isNotEmpty) ...[
            const SizedBox(height: S.x6),
            const OverLabel('Ask about this card'),
            const SizedBox(height: S.x2),
            FollowUpChips(items: s.suggestions, onPick: _fill),
          ],
        ] else ...[
          Semantics(
            header: true,
            child: Text(
              'Ask about your data',
              style: F.t1.copyWith(color: p.ink),
            ),
          ),
          const SizedBox(height: S.x2),
          Text(line, style: F.bodySm.copyWith(color: p.ink2)),
          if (s.suggestions.isNotEmpty) ...[
            const SizedBox(height: S.x6),
            const OverLabel('Try asking'),
            const SizedBox(height: S.x2),
            for (final q in s.suggestions) ...[
              AppCard(
                key: ValueKey('suggestion-$q'),
                onTap: cfg.ready && !spent ? () => _send(q) : null,
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
        ],
      ],
    );
  }

  Widget _messages(CoachChatState s, CoachConfig cfg, bool spent) {
    final notReady = _notReady(cfg);
    final pin = _pin(s);
    final last = s.messages.isEmpty ? null : s.messages.last;
    final followUps =
        !s.sending &&
            !spent &&
            cfg.ready &&
            last != null &&
            last.role == ChatRole.assistant &&
            errorKindOf(last) == null &&
            !last.safety
        ? answerFollowUps(last, asked: s.questionFor(last.id))
        : const <String>[];
    // Bottom-up: the waiting row or the follow-ups, the newest message …
    // the oldest, then the discussed card and the session's disclosure at
    // the top.
    final items = <(String, Widget)>[
      if (s.sending)
        (
          'waiting',
          WaitingRow(generalOnly: cfg.settings.mode == CoachMode.generalOnly),
        ),
      if (followUps.isNotEmpty)
        (
          'follow-ups-${last!.id}',
          CoachEnter(
            play:
                s.fresh.contains(last.id) && !_played.contains('fu-${last.id}'),
            child: _followUps(last.id, followUps),
          ),
        ),
      for (var i = s.messages.length - 1; i >= 0; i--)
        (
          s.messages[i].id,
          _row(s, cfg, s.messages[i], i == s.messages.length - 1),
        ),
      if (spent) ('usage-spent', _spentBanner()),
      if (notReady != null) ('not-ready', notReady),
      if (pin != null) ('discuss-pin', pin),
      if (cfg.cloud) ('disclosure', DisclosureCard(provider: cfg.provider)),
    ];
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x4, S.gutter, S.x4),
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
          padding: const EdgeInsets.only(bottom: S.x4),
          child: w,
        );
      },
    );
  }

  Widget _followUps(String answerId, List<String> items) {
    _played.add('fu-$answerId');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OverLabel('Follow up'),
        const SizedBox(height: S.x1),
        FollowUpChips(items: items, onPick: _fill),
      ],
    );
  }

  Widget _row(CoachChatState s, CoachConfig cfg, ChatMessage m, bool last) {
    final play = s.fresh.contains(m.id) && !_played.contains(m.id);
    _played.add(m.id);
    final Widget child;
    final kind = errorKindOf(m);
    if (m.role == ChatRole.user) {
      child = UserBubble(text: m.text);
    } else if (kind != null) {
      child = ErrorAnswer(
        kind: kind,
        provider: m.sent?.provider ?? cfg.provider,
        message: m.text,
        onSetup: last ? _setup : null,
        onRetry: last ? () => _vm.retry() : null,
      );
    } else if (m.safety) {
      child = SafetyAnswer(text: m.text);
    } else {
      child = AnswerView(
        message: m,
        sample: isSampleData(ref),
        reported: s.reported.contains(m.id),
        memoryOn: cfg.memoryOn,
        onOpenRef: (r) => openRef(context, ref, r),
        onShowSent: m.sent == null
            ? null
            : () => showSentSheet(context, m.sent!),
        onReport: () => _report(s, m, cfg),
        choiceOf: (i) => s.choiceOf(m.id, i),
        categoryOf: (i) => s.categoryOf(m.id, i, m.proposedMemories[i]),
        onPickCategory: (i) =>
            _pickCategory(m, i, s.categoryOf(m.id, i, m.proposedMemories[i])),
        onRemember: (i) async {
          final text = m.proposedMemories[i];
          // Health history and mood: a second, explicit confirm.
          final cur = ref.read(coachChatProvider(launch)).value ?? s;
          final cat = cur.categoryOf(m.id, i, text);
          if (cat.needsExplicitConfirm && !await _confirmSensitive(cat, text)) {
            return;
          }
          final ok = await _vm.saveMemory(m.id, i, text);
          if (!ok && mounted) snack(context, 'Could not save. Try again.');
        },
        onDismissMemory: (i) => _vm.dismissMemory(m.id, i),
        onOpenMemory: () => Navigator.of(context).pushNamed(Routes.coachMemory),
      );
    }
    return CoachEnter(play: play, child: child);
  }
}

/// The engine and mode chips under the app bar. Both open setup.
class _Header extends StatelessWidget {
  const _Header({required this.config, required this.onTap});
  final CoachConfig config;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cloud = config.cloud;
    final general = config.settings.mode == CoachMode.generalOnly;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.gutter - S.x1, 0, S.gutter, S.x1),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: S.x2,
          children: [
            _Chip(
              key: const ValueKey('engine-chip'),
              icon: cloud ? Icons.cloud_outlined : Icons.phone_android_rounded,
              label: config.engineLabel,
              semantic: 'Engine: ${config.engineLabel}. Change in setup',
              onTap: onTap,
            ),
            _Chip(
              key: const ValueKey('mode-chip'),
              icon: general ? Icons.menu_book_outlined : Icons.insights_rounded,
              label: config.modeLabel,
              semantic: 'Mode: ${config.modeLabel}. Change in setup',
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.icon,
    required this.label,
    required this.semantic,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: semantic,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(S.x3, S.x1 + 2, S.x2, S.x1 + 2),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rPill),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: p.ink2),
              const SizedBox(width: S.x1 + 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.cap.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded, size: 16, color: p.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
