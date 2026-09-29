// Parity with Luraxx/pulse SelfTest main.swift (Apache-2.0, see
// third_party/pulse/NOTICE): the sleep part of "Demo-Daten & Engines"
// (:286-305), "Schlafschuld" (:518-537) and "Zubettgeh-Empfehlung"
// (:567-581). Same fixtures, same checks, against engine/sleep.dart.

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/sleep.dart';
import 'package:airlog/domain/engine/strain.dart';
import 'package:airlog/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/pulse_demo_data.dart';

DayRecord debtNight(String key, double minutes) {
  final wake = DayKey.start(key).add(const Duration(hours: 7));
  final bed = wake.subtract(Duration(seconds: (minutes * 60).round()));
  return DayRecord(
    date: key,
    sleepSessions: [
      SleepSession(
        id: 'debt-$key',
        start: bed,
        end: wake,
        minutesAsleep: minutes,
        minutesAwake: 0,
      ),
    ],
  );
}

void main() {
  group('Demo-Daten & Engines: sleep (main.swift:286-305)', () {
    final demo = pulseDemo();
    const strainConfig = StrainConfig(age: 30);
    final strainByDay = {
      for (final e in demo.entries)
        e.key: StrainEngine.dayStrain(
          e.value,
          restingHr: e.value.restingHr,
          config: strainConfig,
        ).strain,
    };
    const config = SleepConfig();
    final analyses = SleepEngine.analyze(
      demo,
      config: config,
      strainByDay: strainByDay,
    );
    test('sleep analysis for every day', () {
      expect(analyses.length, 120);
    });
    test('need / debt / consistency / performance in valid ranges', () {
      for (final e in analyses.entries) {
        final a = e.value;
        expect(
          a.needMinutes >= 300 && a.needMinutes <= 620,
          isTrue,
          reason: 'need ${e.key}: ${a.needMinutes}',
        );
        expect(
          a.debtAfterMinutes >= 0 &&
              a.debtAfterMinutes <= config.maxDebtMinutes,
          isTrue,
          reason: 'debt ${e.key}',
        );
        final c = a.consistency;
        if (c != null) {
          expect(c >= 0 && c <= 100, isTrue, reason: 'consistency ${e.key}');
        }
        expect(
          a.performance >= 0 && a.performance <= 100,
          isTrue,
          reason: 'performance ${e.key}',
        );
      }
    });
    test('every night has stage minutes', () {
      expect(
        analyses.values.where((a) => a.stageMinutes.isNotEmpty).length,
        120,
      );
    });
  });

  group('Schlafschuld (main.swift:518-537)', () {
    // Baseline 456, no strain: 1st night a disaster (60 min), then exactly
    // the baseline, then baseline + 60.
    final a = SleepEngine.analyze({
      '2026-06-01': debtNight('2026-06-01', 60),
      '2026-06-02': debtNight('2026-06-02', 456),
      '2026-06-03': debtNight('2026-06-03', 516),
    });
    test('disaster night: gain capped at 180 min per night', () {
      expect((a['2026-06-01']!.debtAfterMinutes - 180).abs() < 0.01, isTrue);
    });
    test('exactly baseline slept → debt constant (no compounding)', () {
      expect((a['2026-06-02']!.debtAfterMinutes - 180).abs() < 0.01, isTrue);
    });
    test('60 min oversleep → debt drops by 60', () {
      expect((a['2026-06-03']!.debtAfterMinutes - 120).abs() < 0.01, isTrue);
    });
    test('displayed need still contains the repayment', () {
      expect(a['2026-06-02']!.needMinutes > 456, isTrue);
    });
  });

  group('Zubettgeh-Empfehlung (main.swift:567-581)', () {
    final wake645 = DateTime(2026, 6, 10, 6, 45);
    final rec = SleepEngine.bedtimeRecommendation(
      currentDebtMinutes: 0,
      strainToday: 3,
      recentWakeTimes: [wake645, wake645, wake645],
    );
    test('no debt / strain ≈ baseline need', () {
      expect(
        (rec.projectedNeedMinutes - 456).abs() < 5,
        isTrue,
        reason: '${rec.projectedNeedMinutes}',
      );
    });
    test('bedtime = wake time − need', () {
      final bed = rec.recommendedBedtimeMinutes;
      expect(bed, isNotNull);
      expect((bed! - 1389).abs() < 3, isTrue, reason: '$bed');
    });
    test('debt + hard day raise the need', () {
      final hard = SleepEngine.bedtimeRecommendation(
        currentDebtMinutes: 120,
        strainToday: 16,
        recentWakeTimes: [wake645],
      );
      expect(hard.projectedNeedMinutes > rec.projectedNeedMinutes, isTrue);
    });
  });
}
