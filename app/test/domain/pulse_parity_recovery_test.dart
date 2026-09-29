// Parity with Luraxx/pulse SelfTest main.swift (Apache-2.0, see
// third_party/pulse/NOTICE): the recovery part of "Demo-Daten & Engines"
// (:307-336) and "Recovery-Kalibrierung" (:541-563). Same fixtures, same
// checks, against engine/recovery.dart.

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/recovery.dart';
import 'package:airlog/domain/engine/sleep.dart';
import 'package:airlog/domain/engine/strain.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/pulse_demo_data.dart';

DayRecord rhrOnly(String key, double rhr) =>
    DayRecord(date: key, restingHr: rhr);

void main() {
  group('Demo-Daten & Engines: recovery (main.swift:307-336)', () {
    final demo = pulseDemo();
    final keys = demo.keys.toList()..sort();
    final strainByDay = {
      for (final e in demo.entries)
        e.key: StrainEngine.dayStrain(
          e.value,
          restingHr: e.value.restingHr,
          config: const StrainConfig(age: 30),
        ).strain,
    };
    final sleep = SleepEngine.analyze(demo, strainByDay: strainByDay);
    final scores = <int>[];
    final results = <String, RecoveryResult?>{};
    for (final key in keys.sublist(keys.length - 60)) {
      final history = [
        for (final k in keys)
          if (k.compareTo(key) < 0) demo[k]!,
      ];
      final r = RecoveryEngine.compute(
        today: demo[key]!,
        history: history,
        sleepPerformance: sleep[key]?.performance,
      );
      results[key] = r;
      if (r != null) scores.add(r.score);
    }

    test(
      'recovery never null with data, 1–99, zone mapping, weights sum 1',
      () {
        for (final e in results.entries) {
          final r = e.value;
          expect(
            r,
            isNotNull,
            reason: 'recovery null despite data at ${e.key}',
          );
          expect(r!.score >= 1 && r.score <= 99, isTrue, reason: e.key);
          final zone = r.score >= 67
              ? RecoveryZone.green
              : (r.score >= 34 ? RecoveryZone.yellow : RecoveryZone.red);
          expect(r.zone, zone, reason: e.key);
          final w = r.components.fold(0.0, (a, c) => a + c.weight);
          expect((w - 1).abs() <= 0.001, isTrue, reason: e.key);
        }
      },
    );
    test('recovery computed for the last 60 days', () {
      expect(scores.length, 60);
    });
    test('recovery spreads realistically (range ≥ 20)', () {
      final lo = scores.reduce((a, b) => a < b ? a : b);
      final hi = scores.reduce((a, b) => a > b ? a : b);
      expect(hi - lo >= 20, isTrue, reason: '$lo…$hi');
    });
  });

  group('Recovery-Kalibrierung (main.swift:541-563)', () {
    final history = [
      for (var i = 0; i < 10; i++)
        rhrOnly(DayKey.add('2026-06-01', i), 54 + (i % 3).toDouble()),
    ];
    test('recovery computable without HRV', () {
      final r = RecoveryEngine.compute(
        today: rhrOnly('2026-06-11', 55),
        history: history,
        sleepPerformance: 85,
      );
      expect(r, isNotNull);
    });
    test('missing HRV does not block calibration (10 RHR nights suffice)', () {
      final r = RecoveryEngine.compute(
        today: rhrOnly('2026-06-11', 55),
        history: history,
        sleepPerformance: 85,
      );
      expect(r?.calibrating, isFalse);
    });
    test('under 5 RHR nights still calibrating', () {
      final r = RecoveryEngine.compute(
        today: rhrOnly('2026-06-05', 55),
        history: history.sublist(0, 3),
        sleepPerformance: 85,
      );
      expect(r?.calibrating, isTrue);
    });
  });
}
