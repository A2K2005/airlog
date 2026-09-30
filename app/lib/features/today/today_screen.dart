// Today (tab body; the shell owns the Scaffold and the NavigationBar).
//
// The app's one job, "How am I + what to do" (PRODUCT_PLAN §3, principle 3,
// and §7): the day's plan first, then the three scores, then the vitals,
// the calibration progress while it runs, and one collapsed row of data
// notes. Everything else (Coach, Journal, Live workout, Settings) is one tap
// away in More. Today always shows the newest day: history lives on the
// detail screens and Trends.
//
// Motion: the tiles paint once; no entrance plays on a tab switch or a
// reload. Loading keeps the content's shape (tile skeletons), and a pull
// refreshes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart';
import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/day_key.dart';
import '../../domain/repositories.dart' show DataMode;
import '../../domain/results.dart';
import '../../domain/today_plan.dart';
import 'today_view_model.dart';
import 'widgets/health_monitor.dart';
import 'widgets/today_cards.dart';

/// Tab body (the shell provides the Scaffold and NavigationBar).
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(todayViewModelProvider);
    final vm = ref.read(todayViewModelProvider.notifier);
    final now = ref.watch(currentTimeProvider);
    final sync = ref.watch(syncStatusProvider).value;
    final plan = ref.watch(todayPlanProvider);
    final s = async.value;
    final preparing = PreparingNote.shows(
      sync,
      hasData: s != null && s.content != TodayContent.noData,
    );
    final waiting = (s == null && !async.hasError) || preparing;

    void push(String route) => Navigator.of(context).pushNamed(route);
    void open(String route) {
      // The plan names routes; the day tabs switch the shell instead.
      if (route == Routes.sleep) {
        ref.read(tabRequestProvider.notifier).go(ShellTabs.sleep);
      } else if (route == Routes.strain) {
        ref.read(tabRequestProvider.notifier).go(ShellTabs.strain);
      } else if (route == Routes.trends) {
        ref.read(tabRequestProvider.notifier).go(ShellTabs.trends);
      } else {
        push(route);
      }
    }

    final header = ScreenHeader(
      title: longDay(DayKey.of(now)),
      actions: [
        AppIconButton(
          icon: Icons.more_horiz_rounded,
          semanticLabel: 'More',
          onTap: () => showTodayMore(context, ref),
        ),
      ],
      below: sync == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: FreshnessLine.perApp(sync, now: now, onTap: vm.refresh),
            ),
    );

    final List<Widget> tiles;
    if (waiting) {
      tiles = _loading(
        preparing ? PreparingNote.fromStatus(sync!, demo: _demo(ref)) : null,
      );
    } else if (s != null) {
      tiles = _content(context, ref, s, plan, open);
    } else {
      tiles = [
        _wide(
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Couldn’t load today',
            body: 'Airlog couldn’t open your saved data. Nothing was changed.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(todayViewModelProvider),
          ),
        ),
      ];
    }

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: vm.refresh,
        child: ListView(
          key: const PageStorageKey('today'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: S.x10),
          children: [
            header,
            const SizedBox(height: S.x2),
            BentoGrid(children: tiles),
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

  static Widget _wide(Widget child) =>
      SizedBox(width: S.tileWideW, child: child);

  /// The content's own shapes: the plan panel, the Recovery tile, the two
  /// score tiles and a row of vitals.
  static List<Widget> _loading(Widget? preparing) => [
    if (preparing != null) _wide(preparing),
    const TileSkeleton(size: TileSize.large, height: 180),
    const TileSkeleton(size: TileSize.large),
    const TileSkeleton(size: TileSize.tall),
    const TileSkeleton(size: TileSize.tall),
    const TileSkeleton(size: TileSize.tall),
    const TileSkeleton(size: TileSize.tall),
  ];

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    TodayState s,
    TodayPlan? plan,
    void Function(String) open,
  ) {
    switch (s.content) {
      case TodayContent.noData:
        return [
          _wide(
            EmptyState(
              icon: Icons.wb_twilight_rounded,
              title: 'No data yet',
              body:
                  'Wear your tracker to bed tonight. Your scores show up here '
                  'in the morning.',
              actionLabel: 'Check data sources',
              onAction: () => open(Routes.sources),
            ),
          ),
        ];
      case TodayContent.emptyDay:
        return [
          if (plan != null) PlanTile(plan: plan, onOpen: open),
          _wide(
            const EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'Nothing yet for today',
              body: 'Today’s data shows up after your tracker’s app syncs.',
            ),
          ),
        ];
      case TodayContent.ready:
        break;
    }
    final r = s.bundle?.result;
    final notes = [...s.warnings, ...s.infoNotes];
    return [
      if (plan != null) PlanTile(plan: plan, onOpen: open),
      _recoveryTile(s, plan, () => open(Routes.recovery)),
      _strainTile(s, () => open(Routes.strain)),
      _sleepTile(s, () => open(Routes.sleep)),
      for (final t in s.health) _vitalTile(context, t, s.date!),
      if (s.alert != null) _alertTile(context, s),
      if (s.calibration != null && r != null)
        ProgressTile(
          title: 'Learning your usual',
          value: '${s.calibration!.haveNights}',
          unit: 'of ${s.calibration!.needNights} nights',
          progress: s.calibration!.progress,
          onTap: () => open(Routes.recovery),
          semanticLabel:
              'Learning your usual: ${s.calibration!.haveNights} of '
              '${s.calibration!.needNights} nights. ${s.calibrationBody ?? ''}',
        ),
      if (notes.isNotEmpty)
        _wide(
          MoreNotes(
            key: ValueKey('notes-${s.date}'),
            notes: notes,
            title: 'About today’s data',
          ),
        ),
    ];
  }

  static Widget _recoveryTile(
    TodayState s,
    TodayPlan? plan,
    VoidCallback onTap,
  ) {
    final rec = s.recovery;
    final result = s.bundle?.result.recovery;
    // The basis of the score, from the engine (RecoveryResult.withoutHrv and
    // confidence) and the plan's re-learning state. One tag at most, by
    // priority: the tile is fixed-width and single-line.
    final tag = result?.withoutHrv == true
        ? 'without HRV'
        : rec.state == RingState.provisional ||
              result?.confidence == RecoveryConfidence.low
        ? 'early estimate'
        : plan?.relearningSource != null
        ? 'learning'
        : null;
    final title = tag == null ? 'Recovery' : 'Recovery · $tag';
    final scored =
        rec.state == RingState.measured || rec.state == RingState.provisional;
    final score = scored ? '${rec.value!.round()}' : DotMatrixNumber.missing;
    final status = switch (rec.state) {
      RingState.calibrating => 'Learning',
      RingState.noData || RingState.loading => 'No score',
      _ => switch (rec.zone) {
        RecoveryZone.green => 'Good',
        RecoveryZone.yellow => 'Fair',
        RecoveryZone.red => 'Low',
        null => '',
      },
    };
    final rhrName = s.rhrLabel.startsWith('Sleeping')
        ? 'Sleeping heart rate'
        : 'Resting heart rate';
    return ReadinessTile(
      title: title,
      score: score,
      status: status,
      statA: 'HRV vs usual',
      valueA: s.hrvVsUsual ?? '--',
      statB: s.rhrLabel,
      valueB: s.rhrVsUsual ?? '--',
      steps: s.steps,
      usual: s.usualRecovery,
      onTap: onTap,
      semanticLabel: scored
          ? 'Recovery $score%, $status${tag == null ? '' : ', $tag'}. '
                'HRV ${TodayMapper.spokenVsUsual(s.hrvVsUsual)}. '
                '$rhrName ${TodayMapper.spokenVsUsual(s.rhrVsUsual)}. '
                'Tap for details.'
          : rec.state == RingState.calibrating
          ? 'Recovery: still learning your usual. Tap for details.'
          : 'Recovery: no score today. Tap for details.',
    );
  }

  static Widget _strainTile(TodayState s, VoidCallback onTap) {
    final st = s.strain;
    final measured =
        st.state == RingState.measured || st.state == RingState.provisional;
    final value = measured ? st.valueText ?? '--' : DotMatrixNumber.missing;
    final unit = measured
        ? (st.caption?.isNotEmpty == true ? st.caption! : 'out of 21')
        : (s.strainFacts ?? 'No heart rate yet');
    return ArcScoreTile(
      title: 'Strain',
      value: value,
      unit: unit,
      progress: measured ? (st.value! / 21).clamp(0.0, 1.0) : null,
      color: C.limeSoft,
      onTap: onTap,
      semanticLabel: measured
          ? 'Strain $value out of 21. $unit. Tap for details.'
          : 'No Strain score yet: no heart rate. $unit. Tap for details.',
    );
  }

  static Widget _sleepTile(TodayState s, VoidCallback onTap) {
    final sl = s.sleep;
    final has = sl.state == RingState.measured && sl.value != null;
    final pct = has ? '${sl.value!.round()}' : DotMatrixNumber.missing;
    return RingScoreTile(
      title: 'Sleep',
      value: pct,
      caption: has ? (sl.caption ?? '') : 'No sleep recorded',
      progress: has ? (sl.value! / 100).clamp(0.0, 1.0) : null,
      onTap: onTap,
      semanticLabel: has
          ? 'Sleep $pct% of your goal, ${sl.caption} asleep. Tap for details.'
          : 'Sleep: no sleep recorded. Tap for details.',
    );
  }

  /// Where today sits in the usual band, 0…1: the band's edges at 0.15 and
  /// 0.85, the middle at 0.5.
  static double? bandPosition(HealthMetricStatus st) {
    final v = st.value, lo = st.lower, hi = st.upper;
    if (v == null) return null;
    // An unknown or one-sided range has no defensible normalized position.
    // Keep its measured text/status, but do not invent a centred marker.
    if (lo == null || hi == null || hi <= lo) return null;
    return (.15 + .7 * (v - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  static (String, Color) statusOf(BandState b) => switch (b) {
    BandState.inRange => ('In range', C.recGreen),
    BandState.above => ('Above usual', C.amber),
    BandState.below => ('Below usual', C.amber),
    BandState.calibrating => ('Learning', TileInk.secondary),
    BandState.noData => ('No reading', TileInk.secondary),
  };

  /// The vital tiles' short titles (they must fit a 164 px tile).
  static String tileName(HealthMetricKind k) => switch (k) {
    HealthMetricKind.hrv => 'HRV',
    HealthMetricKind.restingHr => 'Resting HR',
    HealthMetricKind.respiratoryRate => 'Breathing',
    HealthMetricKind.spo2 => 'Blood oxygen',
    HealthMetricKind.skinTemp => 'Skin temp',
  };

  /// The spoken state of a vital: "in your usual range" and friends.
  static String spokenState(BandState b) => switch (b) {
    BandState.inRange => 'in your usual range',
    BandState.above => 'above your usual range',
    BandState.below => 'below your usual range',
    BandState.calibrating => 'still learning',
    BandState.noData => 'no reading',
  };

  static Widget _vitalTile(BuildContext context, HealthTileVm t, String date) {
    final st = t.status;
    final value = st.value == null
        ? DotMatrixNumber.missing
        : MetricTile.valueText(st.kind, st.value!);
    final (word, color) = statusOf(st.state);
    final pos = st.state == BandState.noData ? null : bandPosition(st);
    final unit = st.kind.displayUnit;
    final reading = st.value == null
        ? ''
        : unit == '%'
        ? ' $value%'
        : ' $value $unit';
    final label =
        '${st.kind.title}$reading, ${spokenState(st.state)}. Tap to see 30 '
        'nights.';
    void onTap() => showMetricSheet(context, t, date);
    return switch (st.kind) {
      HealthMetricKind.hrv => LineBaselineTile(
        title: 'HRV',
        value: value,
        unit: st.kind.unit,
        status: word,
        statusColor: color,
        position: pos,
        onTap: onTap,
        semanticLabel: label,
      ),
      HealthMetricKind.restingHr => ArcBaselineTile(
        title: 'Resting HR',
        value: value,
        unit: st.kind.unit,
        status: word,
        statusColor: color,
        position: pos,
        onTap: onTap,
        semanticLabel: label,
      ),
      HealthMetricKind.skinTemp => TopArcTile(
        title: 'Skin temp',
        value: value,
        unit: st.kind.unit,
        status: word,
        position: pos,
        onTap: onTap,
        semanticLabel: label,
      ),
      _ => BandBaselineTile(
        title: tileName(st.kind),
        value: value,
        unit: st.kind.unit,
        status: word,
        statusColor: color,
        position: pos,
        onTap: onTap,
        semanticLabel: label,
      ),
    };
  }

  static Widget _alertTile(BuildContext context, TodayState s) {
    final a = s.alert!;
    final out = [
      for (final t in s.health)
        if (t.status.state == BandState.above ||
            t.status.state == BandState.below)
          t.status,
    ];
    final judged = s.health
        .where(
          (t) => switch (t.status.state) {
            BandState.inRange || BandState.above || BandState.below => true,
            _ => false,
          },
        )
        .length;
    return HealthAlertTile(
      title: 'Worth a look',
      readings: [
        for (final m in out.take(3))
          AlertReading(
            MetricTile.valueText(m.kind, m.value!),
            '${tileName(m.kind)} · '
            '${m.state == BandState.above ? 'higher' : 'lower'}',
          ),
      ],
      lowLabel: '${out.length} outside your usual range',
      highLabel: '${judged - out.length} in range',
      segments: [
        AlertSegment(out.length.toDouble(), C.amber),
        AlertSegment((judged - out.length).toDouble(), C.recGreen),
      ],
      // This bar counts judged metrics by status; it is not a time series
      // or an axis locating each vital. Individual readings are above it.
      onTap: () => showExplainSheet<void>(
        context,
        title: a.title,
        lede: a.body,
        children: [ExplainSection(title: 'What to do', body: a.fix)],
      ),
      semanticLabel: '${a.title}. ${a.body}',
    );
  }
}

/// Today's ⋯ More: Coach (hidden when "Show coach" is off), Journal, Live
/// workout and Settings.
Future<void> showTodayMore(BuildContext context, WidgetRef ref) {
  final coachOn = ref.read(coachEnabledProvider).value != false;
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: sheetMotion(context),
    builder: (sheet) {
      void go(VoidCallback f) {
        Navigator.of(sheet).pop();
        f();
      }

      Widget row(IconData icon, String label, VoidCallback onTap) => Pressable(
        onTap: () => go(onTap),
        semanticLabel: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: S.gutter,
            vertical: S.x3,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: P.of(sheet).ink2),
              const SizedBox(width: S.x4),
              Expanded(
                child: Text(
                  label,
                  style: F.head.copyWith(color: P.of(sheet).ink),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: P.of(sheet).ink3),
            ],
          ),
        ),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (coachOn)
                row(askIcon, 'Coach', () => openCoach(context, null)),
              row(
                Icons.edit_note_rounded,
                'Journal',
                () => Navigator.of(context).pushNamed(Routes.journal),
              ),
              row(
                Icons.monitor_heart_outlined,
                'Live workout',
                () => Navigator.of(context).pushNamed(Routes.live),
              ),
              row(
                Icons.settings_outlined,
                'Settings',
                () => Navigator.of(context).pushNamed(Routes.settings),
              ),
            ],
          ),
        ),
      );
    },
  );
}
