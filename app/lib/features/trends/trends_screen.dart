// Trends tab: recovery against strain, training load, and each body signal
// inside its personal band over 7 / 30 / 90 days. Arrows appear only for a
// statistically significant change (Engine.trend), and the page says so.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../app/ask_entry.dart';
import '../../domain/day_key.dart';
import '../../domain/engine/load_and_trends.dart' show TrainingLoadEngine;
import '../../domain/results.dart' show TrainingLoad, LoadState;
import '../../design/design.dart';
import '../../domain/repositories.dart' show DataMode;
import 'trends_view_model.dart';
import 'widgets/trends_widgets.dart';

/// Tab body (the shell provides the Scaffold and NavigationBar).
class TrendsScreen extends ConsumerWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendsViewProvider);
    final range = ref.watch(trendsRangeProvider);
    final v = async.value;
    final p = P.of(context);
    final sync = ref.watch(syncStatusProvider).value;
    // First launch: seeding, and nothing stored yet.
    final preparing = PreparingNote.shows(sync, hasData: v != null);

    final List<Widget> body;
    if (preparing || (async.isLoading && v == null)) {
      body = [
        TrendsSkeleton(
          preparing: preparing
              ? PreparingNote.fromStatus(sync!, demo: _demo(ref))
              : null,
        ),
      ];
    } else if (v != null) {
      body = _content(context, v);
    } else if (async.hasError) {
      body = const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: S.gutter),
          child: StatusCard(
            title: 'Couldn’t load Trends',
            body:
                'Airlog couldn’t open your saved data. Try again after your '
                'next sync.',
            tone: StatusTone.warning,
          ),
        ),
      ];
    } else {
      body = [
        EmptyState(
          icon: Icons.insights_rounded,
          title: 'No trends yet',
          body:
              'Trends need a few days of data. Wear your tracker day and night; '
              'the first lines appear after two or three days.',
          actionLabel: 'Check data sources',
          onAction: () => Navigator.of(context).pushNamed(Routes.sources),
        ),
      ];
    }

    return SafeArea(
      bottom: false,
      child: ColoredBox(
        color: p.bg,
        child: RefreshIndicator(
          onRefresh: () => ref.read(healthRepositoryProvider).syncNow(),
          child: ListView(
            key: const PageStorageKey('trends'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: S.x10),
            children: [
              ScreenHeader(
                title: 'Trends',
                actions: [
                  AppIconButton(
                    icon: Icons.info_outline_rounded,
                    semanticLabel: 'How trends work',
                    onTap: () => showTrendsExplain(context),
                  ),
                ],
                below: SegmentedRange(
                  days: range,
                  onChanged: (d) =>
                      ref.read(trendsRangeProvider.notifier).set(d),
                ),
              ),
              const SizedBox(height: S.x2),
              ...body,
            ],
          ),
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

  List<Widget> _content(BuildContext context, TrendsView v) {
    Widget pad(Widget w) => Padding(
      padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
      child: w,
    );
    Widget header(String t, [String? sub]) => Padding(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x4, S.gutter, S.x3),
      child: SectionHeader(title: t, subtitle: sub),
    );
    final week = _week(v);
    final load = v.load;
    return [
      pad(RecoveryStrainCard(view: v)),
      if (week != null) pad(Center(child: week)),
      if (load != null && load.daysOfHistory >= 28)
        pad(Center(child: _loadTile(load)))
      else
        pad(LoadCard(load: load)),
      pad(
        const Align(
          alignment: Alignment.centerLeft,
          child: AskAboutThis(screen: 'trends'),
        ),
      ),
      header('Body', 'Shaded areas show your usual range'),
      for (final m in v.metrics)
        pad(MetricTrendCard(metric: m, xLabels: v.xLabels)),
      if (v.vo2 != null) ...[
        header('Fitness'),
        pad(MetricTrendCard(metric: v.vo2!, xLabels: v.xLabels)),
      ],
      header('Averages'),
      pad(AveragesCard(rows: v.averages)),
      pad(ArrowsFootnote(anyArrow: v.anyArrow, days: v.days)),
    ];
  }
}

/// Large/7 filled with the last seven days of strain: the most strained
/// day, the week's average and its highest, a bar per day.
WeeklyBarsTile? _week(TrendsView v) {
  final n = v.strain.length;
  if (n < 7) return null;
  final vals = v.strain.sublist(n - 7);
  final measured = [for (final x in vals) ?x];
  if (measured.isEmpty) return null;
  var hi = 0;
  for (var i = 1; i < 7; i++) {
    if ((vals[i] ?? -1) > (vals[hi] ?? -1)) hi = i;
  }
  final mean = measured.reduce((a, b) => a + b) / measured.length;
  final top = measured.reduce((a, b) => a > b ? a : b);
  final keys = [for (var i = 6; i >= 0; i--) DayKey.add(v.lastKey, -i)];
  const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  int wd(String k) => DayKey.start(k).weekday - 1;
  return WeeklyBarsTile(
    title: 'Last 7 days',
    leadLabel: 'Hardest day:',
    leadValue: names[wd(keys[hi])],
    totals: [
      ('Average strain', mean.toStringAsFixed(1), 'OUT OF 21'),
      ('Hardest', top.toStringAsFixed(1), 'STRAIN'),
    ],
    values: vals,
    days: [for (final k in keys) letters[wd(k)]],
    highlight: hi,
    semanticLabel:
        'Strain in the last 7 days: average ${mean.toStringAsFixed(1)}, '
        'hardest ${top.toStringAsFixed(1)} on ${names[wd(keys[hi])]}.',
  );
}

/// The training-load verdict in words (the same words as Methodology and
/// the coach): your last 7 days against your last 4 weeks.
String loadVerdict(LoadState s) => switch (s) {
  LoadState.detraining => 'Less than usual',
  LoadState.optimal => 'About usual',
  LoadState.elevated => 'More than usual',
  LoadState.high => 'Much more than usual',
};

/// Medium/20 filled with the training load: the acute:chronic ratio on the
/// engine's four bands.
SegmentScaleTile _loadTile(TrainingLoad l) {
  final label = switch (l.state) {
    LoadState.detraining => 'Less',
    LoadState.optimal => 'About usual',
    LoadState.elevated => 'More',
    LoadState.high => 'Much more',
  };
  String n(double x) => numText(x);
  return SegmentScaleTile(
    title: 'Training load',
    value: l.ratio.toStringAsFixed(2),
    lead: 'vs usual',
    verdict: label,
    marker: trainingLoadMarker(l.ratio),
    bands: [
      ScaleBand('Less', '<${n(TrainingLoadEngine.optimalFrom)}', C.green800),
      ScaleBand(
        'About usual',
        '${n(TrainingLoadEngine.optimalFrom)}–${n(TrainingLoadEngine.optimalTo)}',
        C.green600,
      ),
      ScaleBand(
        'More',
        '${n(TrainingLoadEngine.optimalTo)}–${n(TrainingLoadEngine.elevatedTo)}',
        C.green400,
      ),
      ScaleBand('Much more', '>${n(TrainingLoadEngine.elevatedTo)}', C.green200),
    ],
    semanticLabel:
        'Training load ${l.ratio.toStringAsFixed(2)}: '
        '${loadVerdict(l.state).toLowerCase()}. Your last 7 days compared '
        'with your last 4 weeks.',
  );
}

/// The tile paints four equal-width categorical bands, not a linear ratio
/// axis. Position within each band using the same cut-points as the engine.
double trainingLoadMarker(double ratio) {
  const a = TrainingLoadEngine.optimalFrom;
  const b = TrainingLoadEngine.optimalTo;
  const c = TrainingLoadEngine.elevatedTo;
  if (ratio < a) return .25 * (ratio / a).clamp(0.0, 1.0);
  if (ratio <= b) return .25 + .25 * ((ratio - a) / (b - a));
  if (ratio <= c) return .5 + .25 * ((ratio - b) / (c - b));
  return .75 + .25 * ((ratio - c) / c).clamp(0.0, 1.0);
}
