// Parity with Luraxx/pulse SelfTest main.swift (Apache-2.0, see
// third_party/pulse/NOTICE): the Health Monitor part of "Demo-Daten &
// Engines" (:338-345), "Health-Warnung" (:585-606) and the English alert /
// label checks of "Sprachen" (:168, :185-196). Same fixtures, same checks,
// against engine/health_monitor.dart. Pulse's bodyTemp (34 °C) is passed in
// skinTempDelta unchanged (the band rule is shift-invariant).

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/health_monitor.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/pulse_demo_data.dart';

DayRecord healthRecord(String key, double rhr, double resp) => DayRecord(
  date: key,
  restingHr: rhr,
  respiratoryRate: resp,
  hrvRmssd: 60,
  spo2Avg: 97,
  skinTempDelta: 34,
);

void main() {
  group('Demo-Daten & Engines: health monitor (main.swift:338-345)', () {
    final demo = pulseDemo();
    final keys = demo.keys.toList()..sort();
    final statuses = HealthMonitor.evaluate(demo[keys.last]!, [
      for (final k in keys.sublist(0, keys.length - 1)) demo[k]!,
    ]);
    test('health monitor reports every metric', () {
      expect(statuses.length, HealthMetricKind.values.length);
    });
    test('demo data: no metric without data', () {
      expect(statuses.every((s) => s.state != BandState.noData), isTrue);
    });
    test('resting HR has a baseline band', () {
      final rhr = statuses.firstWhere(
        (s) => s.kind == HealthMetricKind.restingHr,
      );
      expect(rhr.lower, isNotNull);
      expect(rhr.upper, isNotNull);
    });
  });

  group('Health-Warnung (main.swift:585-606)', () {
    final stable = [
      for (var i = 0; i < 8; i++)
        healthRecord(DayKey.add('2026-06-01', i), 55, 14),
    ];
    test('stable values → no warning', () {
      expect(HealthMonitor.alert(stable), isNull);
    });
    test('several concerning values → warning with ≥ 2 metrics', () {
      final records = [
        ...stable,
        healthRecord(DayKey.add('2026-06-01', 8), 70, 18),
      ];
      final a = HealthMonitor.alert(records);
      expect(a, isNotNull);
      expect(a!.kinds.length >= 2, isTrue);
    });
    test('one metric over 2 days → streak warning', () {
      final records = [
        for (var i = 0; i < 7; i++)
          healthRecord(DayKey.add('2026-07-01', i), 55, 14),
        healthRecord(DayKey.add('2026-07-01', 7), 68, 14),
        healthRecord(DayKey.add('2026-07-01', 8), 69, 14),
      ];
      final a = HealthMonitor.alert(records);
      expect(a, isNotNull);
      expect(a!.kinds, [HealthMetricKind.restingHr]);
    });
  });

  group('Sprachen: English texts (main.swift:168, :185-196)', () {
    test('HealthMetricKind English label incl. unit', () {
      expect(HealthMetricKind.restingHr.label, 'Resting HR');
      expect(HealthMetricKind.restingHr.unit, 'bpm');
    });
    test('health alert phrased in English', () {
      final records = [
        for (var i = 0; i < 8; i++)
          healthRecord(DayKey.add('2026-06-01', i), 55, 14),
        healthRecord(DayKey.add('2026-06-01', 8), 70, 18),
      ];
      final a = HealthMonitor.alert(records);
      expect(a, isNotNull);
      expect(
        a!.message.contains('outside your usual range'),
        isTrue,
        reason: a.message,
      );
    });
  });
}
