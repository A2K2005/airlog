// Insight cards: the coach's short notes on the detail screens (Recovery,
// Sleep, Strain, a workout), never on Today.
//
// Shared kit for features/: imports no feature. A detail screen drops in
//
//   InsightFeed(date: day, kinds: {InsightKind.sleep})
//
// which lists at most one card by default and renders NOTHING while it
// loads, when there is no card, on an error, when the coach is not wired
// (a screen test without coach overrides), when "Coach messages" is Off, and
// when the "Show coach" master switch is off. No spinner, no error card.
//
// InsightCard is one note: the kind chip (and "AI summary" on an AI-reworded
// note, which v1 never makes; no data-mode tag), the headline,
// body, labelled bullets and metric chips, "Discuss" (opens the chat seeded
// with the card; nothing is sent until the user asks), and ⋮ (Hide this
// card, Why am I seeing this?, Coach messages settings). A note that used a memory says so, and the chip
// opens "What Coach knows". Tapping the text opens the card's screen with
// its day selected. Screen readers hear one summary for the text, and each
// action on its own.
//
// Motion: press feedback only (a card is seen every day); sheets use
// sheetMotion.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/design.dart';
import '../domain/coach/coach_contracts.dart';
import '../domain/coach/insight_contracts.dart';
import '../domain/repositories.dart' show DataMode;
import 'ask_entry.dart';
import 'copy.dart';
import 'providers.dart';
import 'route_names.dart';

Duration? _noRetry(int count, Object error) => null;

/// The cards for one day (yyyy-MM-dd), newest first, from the
/// InsightService. Emits an empty list when the service is not wired.
final insightsForDayProvider = StreamProvider.autoDispose
    .family<List<Insight>, String>((ref, date) {
      final InsightService service;
      try {
        service = ref.watch(insightServiceProvider);
      } catch (_) {
        return Stream.value(const <Insight>[]);
      }
      return service.watchDay(date);
    }, retry: _noRetry);

/// Settings → Coach → "Coach messages". Null when the service is not
/// wired; Basic (the default) if reading it fails.
final insightLevelProvider = FutureProvider.autoDispose<InsightLevel?>((
  ref,
) async {
  final InsightService service;
  try {
    service = ref.watch(insightServiceProvider);
  } catch (_) {
    return null;
  }
  try {
    return await service.level();
  } catch (_) {
    return InsightLevel.basic;
  }
}, retry: _noRetry);

/// The confirmed memories, for "Using what you told me". Empty when the
/// coach is not wired or its storage fails.
final insightMemoriesProvider = FutureProvider.autoDispose<List<MemoryFact>>((
  ref,
) async {
  try {
    return await ref.watch(coachRepositoryProvider).memories();
  } catch (_) {
    return const [];
  }
}, retry: _noRetry);

// ── the feed ──────────────────────────────────────────────────────────────

/// The day's insight cards, or nothing.
class InsightFeed extends ConsumerStatefulWidget {
  const InsightFeed({
    super.key,
    required this.date,
    this.kinds,
    this.max = 1,
    this.padding,
    this.hostRoute,
  });

  /// The day (yyyy-MM-dd).
  final String date;

  /// Only these kinds (null = all).
  final Set<InsightKind>? kinds;

  /// At most this many cards, newest first (null = no limit).
  final int? max;

  /// Around the cards; not applied when there is nothing to show.
  final EdgeInsets? padding;

  /// The route of the screen showing the feed ('/sleep'): a card whose
  /// route is this screen does not open it again.
  final String? hostRoute;

  @override
  ConsumerState<InsightFeed> createState() => _InsightFeedState();
}

class _InsightFeedState extends ConsumerState<InsightFeed> {
  /// Hidden in this session, before the stream catches up.
  final _hidden = <String>{};

  Future<void> _hide(Insight i) async {
    setState(() => _hidden.add(i.id));
    snack(context, InsightCopy.hidden);
    try {
      await ref
          .read(insightServiceProvider)
          .setFeedback(i.id, InsightFeedback.hidden);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const nothing = SizedBox.shrink();
    if (ref.watch(coachEnabledProvider).value != true) return nothing;
    final level = ref.watch(insightLevelProvider);
    if (!level.hasValue || level.value == InsightLevel.off) return nothing;
    final all = ref.watch(insightsForDayProvider(widget.date)).value;
    if (all == null) return nothing;
    final kinds = widget.kinds;
    var cards = [
      for (final i in all)
        if (i.feedback != InsightFeedback.hidden &&
            !_hidden.contains(i.id) &&
            (kinds == null || kinds.contains(i.kind)))
          i,
    ];
    final max = widget.max;
    if (max != null && cards.length > max) cards = cards.sublist(0, max);
    if (cards.isEmpty) return nothing;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 0; n < cards.length; n++) ...[
          if (n > 0) const SizedBox(height: S.x3),
          InsightCard(
            key: ValueKey('insight-${cards[n].id}'),
            insight: cards[n],
            hostRoute: widget.hostRoute,
            onHide: () => _hide(cards[n]),
          ),
        ],
      ],
    );
    final pad = widget.padding;
    return pad == null ? column : Padding(padding: pad, child: column);
  }
}

// ── one card ──────────────────────────────────────────────────────────────

/// The accent of a card's kind.
Color insightColor(InsightKind k) => switch (k) {
  InsightKind.sleep => C.sleep,
  InsightKind.recovery => C.recGreen,
  InsightKind.strain => C.strain,
  InsightKind.workout => C.strain,
  InsightKind.healthMonitor => C.health,
  InsightKind.weekly => C.lavender,
};

IconData insightIcon(InsightKind k) => switch (k) {
  InsightKind.sleep => Icons.bedtime_outlined,
  InsightKind.recovery => Icons.battery_charging_full_rounded,
  InsightKind.strain => Icons.local_fire_department_outlined,
  InsightKind.workout => Icons.fitness_center_rounded,
  InsightKind.healthMonitor => Icons.monitor_heart_outlined,
  InsightKind.weekly => Icons.calendar_view_week_rounded,
};

/// A source's value as a chip prints it: "64 %", "52 ms", "6h 40m",
/// "11.2". Null when the source carries no number.
String? sourceValue(SourceRef r) {
  final v = r.value;
  if (v == null) return null;
  final unit = r.unit?.trim() ?? '';
  if (unit == 'min' || unit == 'minutes') return durationWords(v);
  var n = v.toStringAsFixed(v.abs() >= 10 ? 1 : 2);
  if (n.contains('.')) n = n.replaceFirst(RegExp(r'\.?0+$'), '');
  return unit.isEmpty ? n : '$n $unit';
}

/// "Recovery · Mon 28 Sep 64 %": a source as one line of text.
String sourceText(SourceRef r) {
  final v = sourceValue(r);
  return v == null ? r.label : '${r.label} $v';
}

/// The route a card or source opens ('sleep' → '/sleep'), or null.
String? _route(String? raw) {
  final r = raw?.trim();
  if (r == null || r.isEmpty) return null;
  return r.startsWith('/') ? r : '/$r';
}

/// Opens [route] with [date] selected (the day screens read it), the way
/// the chat's source chips do.
Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  String route,
  String? date,
) async {
  if (date != null) {
    try {
      final latest = ref.read(latestDateProvider).value;
      ref
          .read(selectedDateProvider.notifier)
          .select(latest != null && date.compareTo(latest) >= 0 ? null : date);
    } catch (_) {}
  }
  await Navigator.of(context).pushNamed(route);
}

/// True in demo mode. Cards carry no data-mode tag (only the data-mode
/// screens label it). False when the data layer is not wired.
bool isSampleData(WidgetRef ref) {
  try {
    return ref.watch(dataModeProvider) == DataMode.demo;
  } catch (_) {
    return false;
  }
}

/// One insight card. Every callback has a working default (the card talks
/// to the InsightService itself); pass one to take over.
class InsightCard extends ConsumerStatefulWidget {
  const InsightCard({
    super.key,
    required this.insight,
    this.onDiscuss,
    this.onHide,
    this.onOpen,
    this.hostRoute,
  });

  final Insight insight;

  /// Default: opens the chat with `insight.toAskContext()`.
  final VoidCallback? onDiscuss;

  /// Default: `setFeedback(hidden)`.
  final VoidCallback? onHide;

  /// Default: opens `insight.route` with the card's day selected.
  final VoidCallback? onOpen;

  /// The hosting screen's route: a card for that same screen does not
  /// open it again.
  final String? hostRoute;

  /// What a screen reader hears for the card's text.
  static String summary(Insight i) {
    final b = StringBuffer(InsightCopy.kind(i.kind));
    if (i.source == InsightSource.llm) b.write(', ${InsightCopy.aiSummary}');
    b.write('. ${_stop(i.headline)} ${_stop(i.body)}');
    for (final x in i.bullets) {
      b.write(' ${x.label}: ${_stop(x.text)}');
    }
    for (final m in i.metrics) {
      b.write(' ${_stop(sourceText(m))}');
    }
    return b.toString();
  }

  static String _stop(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return RegExp(r'[.!?…]$').hasMatch(t) ? t : '$t.';
  }

  @override
  ConsumerState<InsightCard> createState() => _InsightCardState();
}

enum _Option { hide, why, settings }

class _InsightCardState extends ConsumerState<InsightCard> {
  Insight get _i => widget.insight;

  String? get _openRoute {
    final r = _route(_i.route);
    if (r == null || r == _route(widget.hostRoute)) return null;
    return r;
  }

  VoidCallback? get _onOpen {
    if (widget.onOpen != null) return widget.onOpen;
    final r = _openRoute;
    if (r == null) return null;
    return () => _open(context, ref, r, _i.date);
  }

  void _discuss() {
    final own = widget.onDiscuss;
    if (own != null) return own();
    openCoach(context, _i.toAskContext());
  }

  Future<void> _hide() async {
    final own = widget.onHide;
    if (own != null) return own();
    try {
      await ref
          .read(insightServiceProvider)
          .setFeedback(_i.id, InsightFeedback.hidden);
    } catch (_) {}
  }

  Future<void> _options() async {
    final choice = await _optionsSheet(context);
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Option.hide:
        await _hide();
      case _Option.why:
        await _whySheet(context, _i);
      case _Option.settings:
        await Navigator.of(context).pushNamed(Routes.settingsCoach);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(coachEnabledProvider).value != true) {
      return const SizedBox.shrink();
    }
    final p = P.of(context);
    final i = _i;
    final accent = insightColor(i.kind);
    final facts = i.usedMemoryIds.isEmpty
        ? const <MemoryFact>[]
        : _used(ref.watch(insightMemoriesProvider).value, i.usedMemoryIds);

    final text = ExcludeSemantics(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i.headline, style: F.t2.copyWith(color: p.ink)),
            if (i.body.trim().isNotEmpty) ...[
              const SizedBox(height: S.x2),
              Text(i.body, style: F.body.copyWith(color: p.ink2)),
            ],
            if (i.bullets.isNotEmpty) ...[
              const SizedBox(height: S.x2),
              for (final b in i.bullets) BulletLine(b.text, strong: b.label),
            ],
            if (i.metrics.isNotEmpty) ...[
              const SizedBox(height: S.x3),
              Wrap(
                spacing: S.x2,
                runSpacing: S.x2,
                children: [for (final m in i.metrics) _MetricChip(m)],
              ),
            ],
          ],
        ),
      ),
    );
    final summary = InsightCard.summary(i);
    final onOpen = _onOpen;
    final Widget body = onOpen == null
        ? Semantics(container: true, label: summary, child: text)
        : Pressable(
            key: const ValueKey('insight-open'),
            onTap: onOpen,
            semanticLabel: '$summary Opens the screen.',
            scale: .98,
            child: text,
          );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(S.card, S.x1, S.x1, S.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Wrap(
                    spacing: S.x3,
                    runSpacing: S.x1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatePill(
                        label: InsightCopy.kind(i.kind),
                        color: accent,
                        icon: insightIcon(i.kind),
                      ),
                      if (i.source == InsightSource.llm)
                        const StatePill(
                          key: ValueKey('insight-ai-label'),
                          label: InsightCopy.aiSummary,
                          color: C.neutral,
                          icon: Icons.auto_awesome_outlined,
                          tinted: false,
                        ),
                    ],
                  ),
                ),
              ),
              AppIconButton(
                key: const ValueKey('insight-options'),
                icon: Icons.more_vert_rounded,
                semanticLabel: InsightCopy.options,
                size: 20,
                onTap: _options,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: S.card - S.x1),
            child: body,
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: S.x2),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(right: S.card - S.x1),
                child: _MemoryChip(
                  facts: facts,
                  onTap: () =>
                      Navigator.of(context).pushNamed(Routes.coachMemory),
                ),
              ),
            ),
          ],
          const SizedBox(height: S.x1),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              key: const ValueKey('insight-discuss'),
              label: InsightCopy.discuss,
              kind: AppButtonKind.secondary,
              compact: true,
              icon: askIcon,
              onTap: _discuss,
            ),
          ),
        ],
      ),
    );
  }
}

/// The memories [ids] names that still exist, in [ids] order.
List<MemoryFact> _used(List<MemoryFact>? all, List<String> ids) {
  if (all == null || all.isEmpty) return const [];
  return [
    for (final id in ids)
      for (final m in all)
        if (m.id == id) m,
  ];
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.source);
  final SourceRef source;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final value = sourceValue(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1 + 2),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rPill),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: source.label),
            if (value != null)
              TextSpan(
                text: '  $value',
                style: F
                    .tab(F.cap)
                    .copyWith(color: p.ink, fontWeight: FontWeight.w700),
              ),
          ],
        ),
        style: F.cap.copyWith(color: p.ink2),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// "Using what you told me: training for a half marathon". Opens the
/// memory screen.
class _MemoryChip extends StatelessWidget {
  const _MemoryChip({required this.facts, required this.onTap});
  final List<MemoryFact> facts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final more = facts.length > 1 ? ' and ${facts.length - 1} more' : '';
    final line = '${InsightCopy.usingMemory}: ${facts.first.text}$more';
    return Pressable(
      key: const ValueKey('insight-memory'),
      onTap: onTap,
      semanticLabel: '$line. Opens What Coach knows.',
      scale: .98,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            S.x2 + 2,
            S.x1 + 2,
            S.x3,
            S.x1 + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: R.rPill,
            border: Border.all(color: p.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_outline_rounded, size: 14, color: p.ink2),
              const SizedBox(width: S.x1 + 2),
              Flexible(
                child: Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── sheets ────────────────────────────────────────────────────────────────

Future<T?> _sheet<T>(
  BuildContext context,
  WidgetBuilder builder,
) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: sheetMotion(context),
  builder: (c) {
    final p = P.of(c);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, S.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: p.line, borderRadius: R.rPill),
              ),
            ),
            const SizedBox(height: S.x3),
            builder(c),
          ],
        ),
      ),
    );
  },
);

Future<_Option?> _optionsSheet(BuildContext context) => _sheet<_Option>(
  context,
  (c) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _OptionRow(
        icon: Icons.visibility_off_outlined,
        label: InsightCopy.hide,
        onTap: () => Navigator.of(c).pop(_Option.hide),
      ),
      _OptionRow(
        icon: Icons.help_outline_rounded,
        label: InsightCopy.why,
        onTap: () => Navigator.of(c).pop(_Option.why),
      ),
      _OptionRow(
        icon: Icons.tune_rounded,
        label: InsightCopy.settings,
        onTap: () => Navigator.of(c).pop(_Option.settings),
      ),
    ],
  ),
);

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Pressable(
      onTap: onTap,
      scale: .985,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Icon(icon, size: 20, color: p.ink2),
            const SizedBox(width: S.x4),
            Expanded(
              child: Text(label, style: F.head.copyWith(color: p.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Why am I seeing this?": the numbers behind the card (each opens its
/// screen), who wrote the words, and the memories used (each deletable).
Future<void> _whySheet(BuildContext context, Insight insight) =>
    _sheet<void>(context, (c) => _WhyBody(insight: insight));

class _WhyBody extends ConsumerWidget {
  const _WhyBody({required this.insight});
  final Insight insight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = P.of(context);
    final i = insight;
    final facts = i.usedMemoryIds.isEmpty
        ? const <MemoryFact>[]
        : _used(ref.watch(insightMemoriesProvider).value, i.usedMemoryIds);
    final ai = i.source == InsightSource.llm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(InsightCopy.why, style: F.t1.copyWith(color: p.ink)),
        ),
        const SizedBox(height: S.x2),
        Text(InsightCopy.whyLede, style: F.body.copyWith(color: p.ink2)),
        if (i.refs.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          Wrap(
            spacing: S.x2,
            runSpacing: 0,
            children: [
              for (final r in i.refs)
                _RefChip(
                  key: ValueKey('why-ref-${r.id}'),
                  source: r,
                  onTap: _route(r.route) == null
                      ? null
                      : () {
                          final nav = Navigator.of(context);
                          nav.pop();
                          _open(nav.context, ref, _route(r.route)!, r.date);
                        },
                ),
            ],
          ),
        ],
        const SizedBox(height: S.x5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ai ? Icons.auto_awesome_outlined : Icons.phone_android_rounded,
              size: 18,
              color: p.ink2,
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Text(
                ai ? InsightCopy.writtenByAi : InsightCopy.writtenOnDevice,
                style: F.bodySm.copyWith(color: p.ink),
              ),
            ),
          ],
        ),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: S.x5),
          const OverLabel(InsightCopy.memoriesUsed),
          const SizedBox(height: S.x1),
          for (final m in facts)
            Row(
              key: ValueKey('why-memory-${m.id}'),
              children: [
                Expanded(
                  child: Text(m.text, style: F.body.copyWith(color: p.ink)),
                ),
                AppIconButton(
                  icon: Icons.delete_outline_rounded,
                  semanticLabel: 'Delete memory: ${m.text}',
                  size: 20,
                  onTap: () async {
                    try {
                      await ref
                          .read(coachRepositoryProvider)
                          .deleteMemory(m.id);
                    } catch (_) {}
                    ref.invalidate(insightMemoriesProvider);
                  },
                ),
              ],
            ),
        ],
        const SizedBox(height: S.x4),
        Text(
          ai ? CoachCopy.aiDisclaimer : CoachCopy.notMedical,
          style: F.cap.copyWith(color: p.ink3),
        ),
      ],
    );
  }
}

class _RefChip extends StatelessWidget {
  const _RefChip({super.key, required this.source, this.onTap});
  final SourceRef source;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final value = sourceValue(source);
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(S.x3, S.x2, S.x2, S.x2),
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: R.rMd,
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: source.label),
                  if (value != null)
                    TextSpan(
                      text: '  $value',
                      style: F
                          .tab(F.cap)
                          .copyWith(color: p.ink, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              style: F.cap.copyWith(color: p.ink2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: S.x1),
            Icon(Icons.chevron_right_rounded, size: 16, color: p.ink3),
          ],
        ],
      ),
    );
    final spoken = sourceText(source);
    if (onTap == null) {
      return Semantics(
        label: spoken,
        child: ExcludeSemantics(child: chip),
      );
    }
    return Pressable(
      onTap: onTap,
      semanticLabel: '$spoken. Opens the screen.',
      scale: .96,
      child: ExcludeSemantics(child: chip),
    );
  }
}
