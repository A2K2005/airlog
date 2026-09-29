// The Health Monitor: last night's nightly metrics against the personal band,
// two tiles per row, each with a 14-night sparkline. A tile opens its own
// 30-night band chart; the section header explains the band and the alert.

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/day_key.dart';
import '../../../domain/engine/engine.dart' show EngineConfig;
import '../../../domain/engine/health_monitor.dart';
import '../../../domain/engine/recovery.dart' show RecoveryEngine;
import '../../../domain/results.dart';
import '../today_view_model.dart';

class HealthMonitorSection extends StatelessWidget {
  const HealthMonitorSection({
    super.key,
    required this.tiles,
    required this.date,
  });

  final List<HealthTileVm> tiles;

  /// The focused day (last slot of every series).
  final String date;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final a = _tile(context, tiles[i]);
      final b = i + 1 < tiles.length ? _tile(context, tiles[i + 1]) : null;
      rows.add(
        b == null
            ? a
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: S.x3),
                    Expanded(child: b),
                  ],
                ),
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Health monitor',
          subtitle: _subtitle(),
          actionLabel: 'How it works',
          onAction: () => showHealthMonitorSheet(context),
        ),
        const SizedBox(height: S.x3),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: S.x3),
          rows[i],
        ],
      ],
    );
  }

  /// "Last night · 5 of 5 in your usual range".
  String _subtitle() {
    final judged = tiles.where(
      (t) => switch (t.status.state) {
        BandState.inRange || BandState.above || BandState.below => true,
        _ => false,
      },
    );
    final inRange = judged.where((t) => t.status.state == BandState.inRange);
    if (judged.isEmpty) return 'Last night · your usual range is still forming';
    return 'Last night · ${inRange.length} of ${judged.length} in your usual '
        'range';
  }

  Widget _tile(BuildContext context, HealthTileVm t) {
    final s = t.status;
    final spark = t.tail(14);
    final hasSpark = spark.where((v) => v != null).length >= 2;
    return MetricTile.health(
      s,
      onTap: () => showMetricSheet(context, t, date),
      chart: hasSpark
          ? Sparkline(
              values: spark,
              color: DomainColors.band(s.state),
              lower: s.lower,
              upper: s.upper,
              height: 26,
              semanticsLabel:
                  '${s.kind.label}, last 14 nights. '
                  '${denseSummary(spark, unit: s.kind.unit) ?? ''}',
            )
          : null,
    );
  }
}

const _window = EngineConfig();
final _sd = numText(HealthMonitor.bandSd);
final _spo2Floor = numText(HealthMonitor.spo2HardFloor);
const _nights = RecoveryEngine.reliableNights;

/// "± 3 bpm resting HR, ± 10 ms HRV, …" from the engine's own floors.
String _floors() => [
  for (final (k, name) in const [
    (HealthMetricKind.restingHr, 'resting HR'),
    (HealthMetricKind.hrv, 'HRV'),
    (HealthMetricKind.respiratoryRate, 'respiratory rate'),
    (HealthMetricKind.skinTemp, 'skin temperature'),
  ])
    '± ${numText(HealthMonitor.minimumHalfWidth(k))} ${k.unit} $name',
].join(', ');

String _axisFor(HealthMetricKind k, double v) => switch (k) {
  HealthMetricKind.respiratoryRate || HealthMetricKind.skinTemp => axisFixed(v),
  _ => axisInt(v),
};

/// A tile's detail: 30 nights inside the band, what the band is, the source.
Future<void> showMetricSheet(
  BuildContext context,
  HealthTileVm t,
  String date,
) {
  final s = t.status;
  final k = s.kind;
  final v = s.value;
  final floor = HealthMonitor.minimumHalfWidth(k);
  final floorText = floor.toStringAsFixed(floor % 1 == 0 ? 0 : 1);
  final n = t.series.length;
  final first = DayKey.add(date, -(n - 1));
  final labels = [
    dayMonth(first),
    dayMonth(DayKey.add(first, n ~/ 2)),
    dayMonth(date),
  ];
  final value = v == null ? null : TodayMapper.metricValue(k, v);
  final range = s.lower == null
      ? null
      : s.upper == null
      ? 'at or above ${TodayMapper.metricValue(k, s.lower!)} ${k.unit}'
      : '${TodayMapper.metricValue(k, s.lower!)}–'
            '${TodayMapper.metricValue(k, s.upper!)} ${k.unit}';
  final lede = switch (s.state) {
    BandState.noData => 'No reading for this night.',
    BandState.calibrating =>
      'Last night $value ${k.unit}. Your usual range appears after '
          '$_nights nights (${s.baseline?.count ?? 0} so far).',
    BandState.inRange =>
      'Last night $value ${k.unit}, inside your usual range '
          '($range).',
    BandState.above =>
      'Last night $value ${k.unit}, above your usual range '
          '($range).',
    BandState.below =>
      'Last night $value ${k.unit}, below your usual range '
          '($range).',
  };
  final rule = k == HealthMetricKind.spo2
      ? 'For SpO₂ only a low value matters: the range has a floor at your '
            'average minus the same margin, and never below $_spo2Floor %.'
      : 'Your usual range is the average of your last '
            '${_window.baselineWindowDays} nights (same source) ± $_sd '
            'standard deviations, which holds about 90 % of nights, and never '
            'narrower than ± $floorText ${k.unit}.';
  return showExplainSheet<void>(
    context,
    title: k.label,
    lede: lede,
    children: [
      ExplainSection(
        title: 'Last $n nights',
        child: BaselineBandChart(
          title: k.label,
          unit: k.unit,
          values: t.series,
          color: DomainColors.health,
          mean: s.baseline?.mean,
          lower: s.lower,
          // SpO₂ has only a floor: a one-sided band (upper is null).
          upper: s.upper,
          xLabels: labels,
          format: (x) => _axisFor(k, x),
          footnote: range == null ? null : 'Band: your usual range, $range',
        ),
      ),
      ExplainSection(
        title: 'How the range works',
        body:
            '$rule A night outside it is a prompt to look at the others, '
            'not a diagnosis.',
        formula: k == HealthMetricKind.spo2
            ? 'floor = max($_spo2Floor, mean − max($_sd × SD, $floorText))'
            : 'range = mean ± max($_sd × SD, $floorText ${k.unit})',
      ),
      if (s.provenance != null)
        ExplainSection(
          title: 'Source',
          body:
              'A change of source starts a new baseline, so two ways of '
              'measuring are never mixed.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: ProvenanceChip.of(s.provenance!),
          ),
        ),
    ],
  );
}

/// The section's "How it works".
Future<void> showHealthMonitorSheet(BuildContext context) =>
    showExplainSheet<void>(
      context,
      title: 'Health monitor',
      lede:
          'Five overnight signals, each compared with your own last '
          '${_window.baselineWindowDays} nights, not with population '
          'averages.',
      children: [
        ExplainSection(
          title: 'Your usual range',
          body:
              'For each metric the range is your average ± $_sd standard '
              'deviations (about 90 % of your nights), with a minimum width '
              'so a very steady metric does not flag tiny changes: '
              '${_floors()}. It appears after $_nights nights.',
          formula: 'range = mean ± max($_sd × SD, minimum)',
        ),
        const ExplainSection(
          title: 'When a card appears',
          body:
              'When two or more signals move the way that usually means extra '
              'load (HRV or SpO₂ lower, resting HR, respiratory rate or skin '
              'temperature higher), or one does so two days running. It is a '
              'pattern in your numbers, not a diagnosis.',
        ),
        const ExplainSection(
          title: 'Method',
          body:
              'Ported from Pulse (Luraxx/pulse, Apache-2.0) HealthMonitor. '
              'Skin temperature is your tracker\'s nightly change from its own '
              'baseline.',
        ),
      ],
    );
