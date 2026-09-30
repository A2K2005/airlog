// Overnight signals: a Today vital tile opens its own 30-night band chart,
// with what the usual range is and where the reading came from.

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/day_key.dart';
import '../../../domain/engine/engine.dart' show EngineConfig;
import '../../../domain/engine/health_monitor.dart';
import '../../../domain/engine/recovery.dart' show RecoveryEngine;
import '../../../domain/results.dart';
import '../today_view_model.dart';

const _window = EngineConfig();
final _sd = numText(HealthMonitor.bandSd);
final _spo2Floor = numText(HealthMonitor.spo2HardFloor);
const _nights = RecoveryEngine.reliableNights;

String _axisFor(HealthMetricKind k, double v) => switch (k) {
  HealthMetricKind.respiratoryRate || HealthMetricKind.skinTemp => axisFixed(v),
  _ => axisInt(v),
};

/// "96%" and "54 bpm": percent sits on the number.
String _withUnit(String value, HealthMetricKind k) =>
    k.displayUnit == '%' ? '$value%' : '$value ${k.displayUnit}';

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
  final value = v == null ? null : _withUnit(TodayMapper.metricValue(k, v), k);
  final range = s.lower == null
      ? null
      : s.upper == null
      ? 'at or above ${_withUnit(TodayMapper.metricValue(k, s.lower!), k)}'
      : '${TodayMapper.metricValue(k, s.lower!)}–'
            '${_withUnit(TodayMapper.metricValue(k, s.upper!), k)}';
  final lede = switch (s.state) {
    BandState.noData => 'No reading for this night.',
    BandState.calibrating =>
      'Last night: $value. Your usual range shows up after $_nights '
          'nights. You have ${s.baseline?.count ?? 0} so far.',
    BandState.inRange => 'Last night: $value. That’s in your usual range '
        '($range).',
    BandState.above => 'Last night: $value. That’s above your usual range '
        '($range).',
    BandState.below => 'Last night: $value. That’s below your usual range '
        '($range).',
  };
  final rule = k == HealthMetricKind.spo2
      ? 'For blood oxygen, only a low reading matters. The range has a '
            'floor, and the floor is never below $_spo2Floor%.'
      : 'Your usual range is where about 9 in 10 of your last '
            '${_window.baselineWindowDays} nights fall. It’s never narrower '
            'than ± $floorText ${k.displayUnit}, so tiny changes don’t count.';
  return showExplainSheet<void>(
    context,
    title: k.title,
    lede: lede,
    children: [
      ExplainSection(
        title: 'Last $n nights',
        child: BaselineBandChart(
          title: k.title,
          unit: k.unit,
          values: t.series,
          color: DomainColors.health,
          mean: s.baseline?.mean,
          lower: s.lower,
          // SpO₂ has only a floor: a one-sided band (upper is null).
          upper: s.upper,
          xLabels: labels,
          format: (x) => _axisFor(k, x),
          footnote: range == null ? null : 'Shaded: your usual range, $range',
        ),
      ),
      ExplainSection(
        title: 'How the range works',
        body:
            '$rule One night outside it is a prompt to check your other '
            'signals. It’s not a diagnosis.',
        formula: k == HealthMetricKind.spo2
            ? 'floor = max($_spo2Floor, mean − max($_sd × SD, $floorText))'
            : 'range = mean ± max($_sd × SD, $floorText ${k.unit})',
      ),
      if (s.provenance != null)
        ExplainSection(
          title: 'Source',
          body:
              'If this starts coming from a different app, Airlog learns your '
              'usual again instead of mixing the two.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: ProvenanceChip.of(s.provenance!),
          ),
        ),
    ],
  );
}
