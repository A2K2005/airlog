// Sleep (tab body; the shell owns the Scaffold). The focused night: slept
// against need and what the need was made of, the hypnogram, stages, naps,
// debt; bed/wake consistency; tonight's bedtime. A dumb view over SleepState.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart';
import '../../app/insight_card.dart';
import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/day_key.dart';
import '../../domain/results.dart' show SleepAnalysis;
import '../../domain/coach/insight_contracts.dart' show InsightKind;
import '../../domain/models.dart' show SleepStage;
import '../../domain/repositories.dart' show DataMode;
import 'sleep_view_model.dart';
import 'widgets/sleep_widgets.dart';

/// Tab body (the shell provides the Scaffold and NavigationBar).
class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sleepViewModelProvider);
    final vm = ref.read(sleepViewModelProvider.notifier);
    final s = async.value;
    final sync = ref.watch(syncStatusProvider).value;
    // First launch: seeding, and nothing stored yet.
    final preparing = PreparingNote.shows(
      sync,
      hasData: s != null && s.content != SleepContent.noData,
    );
    final waiting = (s == null && !async.hasError) || preparing;

    final header = ScreenHeader(
      title: 'Sleep',
      actions: [
        AppIconButton(
          icon: Icons.info_outline_rounded,
          semanticLabel: 'How your sleep goal works',
          onTap: () => showSleepNeedExplain(context, s?.analysis),
        ),
      ],
      below: waiting
          ? const DaySwitcherSkeleton()
          : s?.date == null
          ? null
          : Row(
              children: [
                Flexible(
                  child: DaySwitcher(
                    date: s!.date!,
                    latest: s.latest,
                    earliest: s.earliest,
                    today: s.today,
                    onShift: vm.shift,
                  ),
                ),
                if (!s.isLatest) ...[
                  const SizedBox(width: S.x2),
                  AppButton(
                    label: 'Latest',
                    kind: AppButtonKind.quiet,
                    compact: true,
                    icon: Icons.keyboard_double_arrow_right_rounded,
                    onTap: vm.showLatest,
                  ),
                ],
              ],
            ),
    );

    final List<Widget> body;
    if (waiting) {
      body = _loading(
        preparing ? PreparingNote.fromStatus(sync!, demo: _demo(ref)) : null,
      );
    } else if (s != null) {
      body = _content(context, s, vm);
    } else if (async.hasError) {
      body = [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Couldn’t load this night',
          body: 'Airlog couldn’t open your saved data. Nothing was changed.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(sleepViewModelProvider),
        ),
      ];
    } else {
      body = _loading(null);
    }

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: vm.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: S.x10),
          children: [
            header,
            for (final w in body)
              Padding(
                padding: const EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, 0),
                child: w,
              ),
          ],
        ),
      ),
    );
  }

  static bool _demo(WidgetRef ref) {
    try {
      return ref.watch(dataModeProvider) == DataMode.demo;
    } catch (_) {
      return true;
    }
  }

  /// The hero's skeleton in the hero's slot (the ring where the ring will
  /// be), then the first-launch note or a skeleton card.
  static List<Widget> _loading(Widget? preparing) => [
    const Center(child: TileSkeleton(size: TileSize.large)),
    ?preparing,
    const AppCard(child: SizedBox(height: 180, child: SkeletonLines(lines: 4))),
  ];

  List<Widget> _content(BuildContext context, SleepState s, SleepViewModel vm) {
    void sources() => Navigator.of(context).pushNamed(Routes.sources);
    switch (s.content) {
      case SleepContent.noData:
        return [
          EmptyState(
            icon: Icons.bedtime_outlined,
            title: 'No sleep yet',
            body:
                'Wear your tracker to bed. Your night shows up here in the '
                'morning, after its app syncs.',
            actionLabel: 'Check data sources',
            onAction: sources,
          ),
        ];
      case SleepContent.emptyDay:
        return [
          EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'Nothing recorded',
            body: 'No data came in for ${longDay(s.date!)}.',
          ),
          ..._consistency(context, s, vm),
        ];
      case SleepContent.noSleep:
        return [
          for (final n in s.notes)
            StatusCard.fromNote(
              n,
              actionLabel: 'Check data sources',
              onAction: sources,
            ),
          if (s.notes.isEmpty)
            const EmptyState(
              icon: Icons.bedtime_outlined,
              title: 'No sleep recorded',
              body: 'No sleep was recorded for this night.',
            ),
          if (s.analysis != null) _DebtLine(debt: s.analysis!.debtAfterMinutes),
          if (s.bedtime != null)
            BedtimeCard(
              bedtime: s.bedtime!,
              onExplain: () => showSleepNeedExplain(context, s.analysis),
            ),
          ..._consistency(context, s, vm),
        ];
      case SleepContent.ready:
        break;
    }
    final a = s.analysis!;
    final p = P.of(context);
    return [
      InsightFeed(
        date: s.date!,
        kinds: const {InsightKind.sleep},
        hostRoute: Routes.sleep,
      ),
      Center(
        child: sleepSummaryTile(
          s,
          a,
          onTap: () => showSleepNeedExplain(context, a),
          use24h: MediaQuery.alwaysUse24HourFormatOf(context),
        ),
      ),
      SleepHero(
        key: ValueKey('sleep-hero-${s.date}'),
        analysis: a,
        debtChange: s.debtChange,
        onExplain: () => showSleepNeedExplain(context, a),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: AskAboutThis(screen: 'sleep', date: s.date),
      ),
      if (s.bedtime != null)
        BedtimeCard(
          bedtime: s.bedtime!,
          onExplain: () => showSleepNeedExplain(context, a),
        ),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HypnogramChart(
              stages: s.stages,
              start: s.start,
              end: s.end,
              title: 'Main sleep',
            ),
            const SizedBox(height: S.x4),
            Divider(height: 1, color: p.line),
            const SizedBox(height: S.x4),
            StageStats(analysis: a, restorativePct: s.restorativePct),
          ],
        ),
      ),
      if (s.naps.isNotEmpty) NapsCard(naps: s.naps),
      ..._consistency(context, s, vm),
      for (final n in s.notes) StatusCard.fromNote(n),
    ];
  }

  List<Widget> _consistency(
    BuildContext context,
    SleepState s,
    SleepViewModel vm,
  ) {
    final shown = s.shownNights;
    final c = s.analysis?.consistency;
    final n = shown.length;
    final first = DayKey.add(s.date!, -(n - 1));
    return [
      Padding(
        padding: const EdgeInsets.only(top: S.x4),
        child: SectionHeader(
          title: 'Consistency',
          subtitle: c == null
              ? 'Bed and wake times, last $n nights'
              : '${c.round()}% · compared with your last 4 nights',
          trailing: SizedBox(
            width: 116,
            child: SegmentedRange(
              days: s.rangeDays,
              options: const [14, 30],
              onChanged: vm.setRange,
            ),
          ),
        ),
      ),
      AppCard(
        child: ScatterConsistency(
          nights: shown,
          xLabels: [
            dayMonth(first),
            dayMonth(DayKey.add(first, n ~/ 2)),
            dayMonth(s.date!),
          ],
        ),
      ),
    ];
  }
}

class _DebtLine extends StatelessWidget {
  const _DebtLine({required this.debt});
  final double debt;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      tone: CardTone.inset,
      child: Text(
        'No sleep data for this night, so your missed sleep stays at '
        '${sleepHm(debt)}.',
        style: F.tab(F.bodySm).copyWith(color: p.ink2),
      ),
    );
  }
}

/// Large/1 filled from the night: time asleep, % of the sleep goal and the
/// goal; the stages on the plate; minutes per stage. [use24h]: the phone's
/// clock setting for the plate's start and end times.
SleepSummaryTile sleepSummaryTile(
  SleepState s,
  SleepAnalysis a, {
  VoidCallback? onTap,
  bool use24h = true,
}) {
  // Durations never use clock format ("7:01" reads as a time of day).
  String hmm(double m) => sleepHm(m);

  final start = s.start, end = s.end;
  final span = start == null || end == null
      ? 0
      : end.difference(start).inSeconds;
  SleepLane? lane(SleepStage st) => switch (st) {
    SleepStage.awake => SleepLane.awake,
    SleepStage.rem => SleepLane.rem,
    SleepStage.light => SleepLane.core,
    SleepStage.deep => SleepLane.deep,
    SleepStage.unknown => null,
  };
  List<String> parts(double? minutes) {
    if (!a.hasStageData) return ['—', ''];
    final m = (minutes ?? 0).round();
    if (m < 60) return ['$m', ' min'];
    return ['${m ~/ 60}', 'h', ' ${m % 60}', 'min'];
  }

  // The plate's labels sit between fixed icons (moon at the start, sun at
  // the end), so the 12-hour form drops "am"/"pm": "11:10", "6:35".
  String clock(DateTime? t) {
    if (t == null) return '--:--';
    if (use24h) return clockTextOf(t, use24h: true);
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')}';
  }
  return SleepSummaryTile(
    title: 'Sleep',
    stats: [
      (hmm(a.sleptMinutes), 'Asleep'),
      ('${a.performance.round()}%', 'Of your goal'),
      (hmm(a.needMinutes), 'Sleep goal'),
    ],
    deltaColor: TileInk.primary,
    blocks: [
      if (span > 0)
        for (final g in s.stages)
          if (lane(g.stage) != null)
            SleepBlock(
              lane(g.stage)!,
              g.start.difference(start!).inSeconds / span,
              g.end.difference(start).inSeconds / span,
            ),
    ],
    startLabel: clock(start),
    endLabel: clock(end),
    totals: [
      SleepStageTotal('Awake', parts(a.stageMinutes[SleepStage.awake])),
      SleepStageTotal('REM', parts(a.stageMinutes[SleepStage.rem])),
      SleepStageTotal('Light', parts(a.stageMinutes[SleepStage.light])),
      SleepStageTotal('Deep', parts(a.stageMinutes[SleepStage.deep])),
    ],
    onTap: onTap,
    semanticLabel:
        'Asleep ${durationWords(a.sleptMinutes)}, '
        '${a.performance.round()} percent of your '
        '${durationWords(a.needMinutes)} sleep goal. '
        '${a.hasStageData ? '' : 'No sleep stages for this night. '}'
        'Tap for how the goal works.',
  );
}
