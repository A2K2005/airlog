// Feature-private widgets for the Trends tab. Plain values in, no providers.

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/engine/engine.dart' show EngineConfig;
import '../../../domain/engine/health_monitor.dart' show HealthMonitor;
import '../../../domain/engine/load_and_trends.dart'
    show TrainingLoadEngine, TrendEngine;
import '../../../domain/results.dart';
import '../trends_view_model.dart';

String _avg(List<double?> xs, String Function(double) f) {
  var s = 0.0, n = 0;
  for (final x in xs) {
    if (x == null || !x.isFinite) continue;
    s += x;
    n++;
  }
  return n == 0 ? 'no data' : f(s / n);
}

class RecoveryStrainCard extends StatelessWidget {
  const RecoveryStrainCard({super.key, required this.view});
  final TrendsView view;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final v = view;
    final arrows = [
      if (TrendArrow.visible(v.recoveryTrend))
        ('Recovery', v.recoveryTrend, true),
      if (TrendArrow.visible(v.strainTrend)) ('Strain', v.strainTrend, null),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DualAxisChart.recoveryStrain(
            recovery: v.recovery,
            strain: v.strain,
            xLabels: v.xLabels,
          ),
          const SizedBox(height: S.x3),
          Text(
            'Average recovery ${_avg(v.recovery, axisInt)}'
            '${_avg(v.recovery, axisInt) == 'no data' ? '' : ' %'}'
            ' · average strain ${_avg(v.strain, axisFixed)}',
            style: F.tab(F.cap).copyWith(color: p.ink2),
          ),
          for (final (name, trend, good) in arrows)
            Padding(
              padding: const EdgeInsets.only(top: S.x2),
              child: Row(
                children: [
                  Text('$name ', style: F.cap.copyWith(color: p.ink2)),
                  TrendArrow(
                    trend: trend,
                    upIsGood: good,
                    metric: name,
                    size: 15,
                    showLabel: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class LoadCard extends StatelessWidget {
  const LoadCard({super.key, this.load});
  final TrainingLoad? load;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final l = load;
    final line = l == null
        ? 'Needs at least ${TrainingLoadEngine.minDays} days of strain in the '
              'last ${TrainingLoadEngine.chronicDays} days.'
        : switch (l.state) {
            LoadState.detraining =>
              'This week is lighter than your last four. Fine for a rest '
                  'week; fitness fades if it stays here.',
            LoadState.optimal =>
              'This week matches what your body is used to: load is '
                  'building without a spike.',
            LoadState.elevated =>
              'This week is noticeably harder than your recent normal. '
                  'Watch recovery for the next few days.',
            LoadState.high =>
              'This week is much harder than your last four. Spikes like '
                  'this are when overreaching tends to start.',
          };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AcwrGauge.fromLoad(l),
          const SizedBox(height: S.x3),
          Text(line, style: F.bodySm.copyWith(color: p.ink)),
          const SizedBox(height: S.x2),
          Text(
            'Acute:chronic ratio: mean daily strain over the last '
            '${TrainingLoadEngine.acuteDays} days ÷ the last '
            '${TrainingLoadEngine.chronicDays} (Gabbett 2016). '
            '${numText(TrainingLoadEngine.optimalFrom)}–'
            '${numText(TrainingLoadEngine.optimalTo)} is the steady zone.'
            '${l == null ? '' : ' Based on ${l.daysOfHistory} days.'}',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}

class MetricTrendCard extends StatelessWidget {
  const MetricTrendCard({
    super.key,
    required this.metric,
    required this.xLabels,
  });
  final MetricTrend metric;
  final List<String> xLabels;

  @override
  Widget build(BuildContext context) {
    final m = metric;
    final changes = m.sourceChanges;
    String? foot = m.footnote;
    final hasBand = m.lower != null && m.upper != null;
    if (foot == null && hasBand && m.hasValues) {
      foot =
          'Band: your usual range ${m.format(m.lower!)}–${m.format(m.upper!)} ${m.unit}';
    }
    if (changes.isNotEmpty) {
      foot =
          '${foot == null ? '' : '$foot. '}Dotted line: the source changed '
          'on ${changes.map(dayMonth).join(', ')}, so a new baseline starts '
          'there.';
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BaselineBandChart(
            title: m.title,
            unit: m.unit,
            values: m.values,
            color: m.color,
            mean: m.mean,
            lower: m.lower,
            upper: m.upper,
            xLabels: xLabels,
            format: m.format,
            axis: m.axis,
            footnote: foot,
            xMarks: m.sourceChangeMarks,
            emptyMessage: 'Nothing measured in this range',
            // Only a real arrow: an empty trailing slot would still push
            // the unit off the card's edge by its spacer.
            trailing: TrendArrow.visible(m.trend)
                ? TrendArrow(
                    trend: m.trend,
                    upIsGood: m.upIsGood,
                    metric: m.metricName,
                  )
                : null,
          ),
          if (m.provenance != null) ...[
            const SizedBox(height: S.x3),
            ProvenanceChip.of(m.provenance!),
          ],
        ],
      ),
    );
  }
}

class AveragesCard extends StatelessWidget {
  const AveragesCard({super.key, required this.rows});
  final List<AverageRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final head = F.over.copyWith(color: p.ink3);
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(flex: 5, child: SizedBox.shrink()),
              for (final h in const ['7D', '30D', '90D'])
                Expanded(
                  flex: 3,
                  child: Text(h, style: head, textAlign: TextAlign.right),
                ),
            ],
          ),
          const SizedBox(height: S.x2),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      r.unit.isEmpty ? r.label : '${r.label} (${r.unit})',
                      style: F.bodySm.copyWith(color: p.ink2),
                    ),
                  ),
                  for (final c in r.cells)
                    Expanded(
                      flex: 3,
                      child: Text(
                        c ?? 'none',
                        textAlign: TextAlign.right,
                        style: F
                            .tab(F.bodySm)
                            .copyWith(
                              color: c == null ? p.ink3 : p.ink,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ArrowsFootnote extends StatelessWidget {
  const ArrowsFootnote({super.key, required this.anyArrow, required this.days});
  final bool anyArrow;
  final int days;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      tone: CardTone.inset,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.north_east_rounded, size: 16, color: p.ink2),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(
              '${anyArrow ? 'Arrows mark' : 'No arrows here: nothing in these $days days is'} '
              'a statistically significant change (Mann–Kendall test, '
              'p < 0.05, at least ${TrendEngine.minN} days). '
              '${anyArrow ? 'No arrow means no reliable change yet, not no change.' : 'Day-to-day wobble is not a trend.'}',
              style: F.cap.copyWith(color: p.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showTrendsExplain(BuildContext context) => showExplainSheet<void>(
  context,
  title: 'How trends are tested',
  lede:
      'A line that drifts is not a trend until the drift is bigger than '
      'the day-to-day noise. Airlog only draws an arrow when it is.',
  children: [
    ExplainSection(
      title: 'The test',
      body:
          'Mann–Kendall: for every pair of days, does the later one sit '
          'above or below the earlier one? If far more pairs go one way '
          'than chance allows (two-sided p < 0.05), the change is real. '
          'Needs at least ${TrendEngine.minN} measured days; missing days '
          'are skipped, never filled in.',
      formula:
          '|Z| > ${TrendEngine.zCritical.toStringAsFixed(2)}   '
          '(p < 0.05)',
    ),
    const ExplainSection(
      title: 'The size',
      body:
          'The slope is Sen’s estimator: the median of every pairwise '
          'slope, so one odd night cannot swing it.',
    ),
    ExplainSection(
      title: 'Bands',
      body:
          'The shaded band is your usual range from the Health '
          'Monitor: your ${const EngineConfig().baselineWindowDays}-night '
          'baseline ± ${numText(HealthMonitor.bandSd)} SD, with a minimum '
          'width so a very steady metric is not over-sensitive.',
    ),
    const ExplainSection(
      title: 'New baselines',
      body:
          'If a metric starts coming from a different source (say, '
          'deep-sleep HRV from the Google Health API instead of all-night '
          'HRV from Health Connect), the old and new values are not '
          'mixed: a new baseline starts, and the chart marks the day '
          'with a dotted line.',
    ),
  ],
);

/// The first cards' skeletons in their slots; on first launch the
/// PreparingNote leads.
class TrendsSkeleton extends StatelessWidget {
  const TrendsSkeleton({super.key, this.preparing});

  /// First launch: shown above the skeleton cards.
  final Widget? preparing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: S.gutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preparing != null) ...[preparing!, const SizedBox(height: S.x4)],
        const AppCard(child: SkeletonLines(lines: 6)),
        const SizedBox(height: S.x4),
        const AppCard(child: SkeletonLines(lines: 3)),
        const SizedBox(height: S.x4),
        const AppCard(child: SkeletonLines(lines: 5)),
      ],
    ),
  );
}
