// Our strain additions: no score without heart rate (algo v2), sparse HR,
// Banister TRIMP, display zones, max HR, live workout strain. [ours]

import 'dart:math' as math;

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/strain.dart';
import 'package:airlog/domain/engine/strain_fallback.dart';
import 'package:airlog/domain/engine/trimp.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/builders.dart';

DayStrain strainOf(DayRecord r, {DateTime? now, double? maxHr = 187}) =>
    StrainDay.compute(
      r,
      samples: r.hrSamples,
      restingHr: r.restingHr,
      maxHr: maxHr,
      tau: 450,
      sex: Sex.unspecified,
      now: now ?? DateTime(2026, 9, 1),
    );

void main() {
  group('heart rate only (principle 6)', () {
    test('1-min HR over the whole day → HR zones', () {
      final s = strainOf(denseDay('2026-08-10'));
      expect(s.result.method, StrainMethod.hrZones);
      expect(s.coverage > 0.95, isTrue, reason: '${s.coverage}');
      expect(s.result.trimp, isNotNull);
      expect(s.result.loadZoneMinutes, hasLength(6));
      expect(s.result.zoneMinutes, hasLength(5));
      expect(s.result.steps, 9000, reason: 'steps are a fact, not load');
    });

    test('sparse HR is scored from the samples it has, flagged partial; '
        'steps add nothing', () {
      final r = denseDay('2026-08-10', hrStepMinutes: 5, rhr: 60, steps: 8000);
      final withSteps = strainOf(r);
      expect(withSteps.sparse, isTrue);
      expect(withSteps.partialHr, isTrue);
      expect(withSteps.result.method, StrainMethod.hrZones);
      r.steps = 30000;
      expect(strainOf(r).result.rawLoad, withSteps.result.rawLoad);
    });

    test('a workout without samples inside uses its measured average HR', () {
      final r = denseDay('2026-08-10', hrStepMinutes: 5, rhr: 60);
      r.hrSamples.removeWhere(
        (s) =>
            !s.t.isBefore(r.workouts.first.start) &&
            !s.t.isAfter(r.workouts.first.end),
      );
      final w = strainOf(r).result.workouts.single;
      expect(w.method, StrainMethod.fallback);
      // maxHR 187, RHR 60 → (150-60)/127 = 0.709 → load zone 3 (w 5).
      expect(w.strain, closeTo(21 * (1 - math.exp(-5.0 * 45 / 450)), 1e-9));
    });

    test('sparse day: a workout WITH ≥ 3 samples uses its HR slice', () {
      final s = strainOf(denseDay('2026-08-10', hrStepMinutes: 5));
      expect(s.result.workouts.single.method, StrainMethod.hrZones);
    });

    test('no heart rate: no score, activity facts only (no MET estimate)', () {
      final day = DayKey.start('2026-08-10');
      final r = DayRecord(
        date: '2026-08-10',
        restingHr: 60,
        vo2max: 45,
        steps: 12000,
        workouts: [
          Workout(
            id: 'x',
            name: 'Morning run',
            start: day.add(const Duration(hours: 7)),
            end: day.add(const Duration(hours: 7, minutes: 30)),
          ),
        ],
      );
      final s = strainOf(r);
      expect(s.result.method, StrainMethod.none);
      expect(s.result.strain, 0);
      expect(s.result.rawLoad, 0);
      expect(s.result.steps, 12000);
      expect(s.result.workouts.single.method, StrainMethod.none);
      expect(s.result.workouts.single.strain, 0);
      expect(s.result.trimp, isNull);
    });

    test('heart rate but no max HR: no score', () {
      final s = strainOf(denseDay('2026-08-10'), maxHr: null);
      expect(s.result.method, StrainMethod.none);
      expect(s.result.maxHrUsed, isNull);
      expect(s.result.workouts.single.method, StrainMethod.none);
    });

    test(
      'no resting HR: %HRmax zones (Swain), flagged; never an assumed 62',
      () {
        final r = denseDay('2026-08-10', rhr: null);
        final s = strainOf(r);
        expect(s.result.method, StrainMethod.hrZones);
        expect(s.result.zonesFromMaxHr, isTrue);
        expect(s.result.restingHrUsed, isNull);
        expect(s.result.trimp, isNull, reason: 'TRIMP needs the reserve');
        expect(s.result.maxHrUsed, 187);
        // 150 bpm at max 187 = 80.2 % HRmax → (0.802 − 0.37) / 0.64 = 67.5 %
        // of reserve: the accumulator sees exactly Swain's conversion.
        final (lo, hi) = StrainEngine.maxHrZoneAnchors(187);
        expect(
          StrainEngine.hrrFraction(150, lo, hi),
          closeTo((150 / 187 - 0.37) / 0.64, 1e-12),
        );
        final withRhr = strainOf(denseDay('2026-08-10', rhr: 62));
        expect(withRhr.result.zonesFromMaxHr, isFalse);
        expect(s.result.strain, isNot(withRhr.result.strain));
      },
    );

    test('no input at all → method none, strain 0', () {
      final s = strainOf(DayRecord(date: '2026-08-10'));
      expect(s.result.method, StrainMethod.none);
      expect(s.result.strain, 0);
    });

    test('partial day: coverage counts awake minutes only up to now', () {
      final r = denseDay('2026-08-10', workout: false);
      r.hrSamples.removeWhere(
        (s) => s.t.isAfter(
          DayKey.start('2026-08-10').add(const Duration(hours: 12)),
        ),
      );
      final s = strainOf(r, now: DateTime(2026, 8, 10, 12));
      expect(s.coverage > 0.95, isTrue, reason: '${s.coverage}');
      expect(s.result.method, StrainMethod.hrZones);
    });

    test('target strain comes from the recovery score', () {
      final s = StrainDay.compute(
        denseDay('2026-08-10'),
        samples: denseDay('2026-08-10').hrSamples,
        restingHr: 55,
        maxHr: 187,
        tau: 450,
        sex: Sex.male,
        now: DateTime(2026, 9, 1),
        recoveryScore: 80,
      );
      expect(s.result.targetStrain, StrainEngine.targetStrain(80));
    });
  });

  group('Banister TRIMP', () {
    test('known value: 60 min at HRr 0.5', () {
      final male = 60 * 0.5 * 0.64 * math.exp(1.92 * 0.5);
      final female = 60 * 0.5 * 0.86 * math.exp(1.67 * 0.5);
      expect(male, closeTo(50.14, 0.01));
      expect(
        Trimp.fromAverage(120, 60, restingHr: 60, maxHr: 180, sex: Sex.male),
        closeTo(male, 1e-9),
      );
      expect(
        Trimp.fromAverage(120, 60, restingHr: 60, maxHr: 180, sex: Sex.female),
        closeTo(female, 1e-9),
      );
      expect(
        Trimp.fromAverage(
          120,
          60,
          restingHr: 60,
          maxHr: 180,
          sex: Sex.unspecified,
        ),
        closeTo((male + female) / 2, 1e-9),
      );
    });

    test('from samples: 60 one-minute samples = 60 minutes', () {
      final t0 = DateTime(2026, 8, 10, 18);
      final samples = [
        for (var i = 0; i < 60; i++)
          HrSample(t0.add(Duration(minutes: i)), 120),
      ];
      expect(
        Trimp.fromSamples(samples, restingHr: 60, maxHr: 180, sex: Sex.male),
        closeTo(60 * 0.5 * 0.64 * math.exp(0.96), 1e-9),
      );
    });

    test('HRr is clamped to [0, 1]', () {
      expect(Trimp.rate(40, restingHr: 60, maxHr: 180, sex: Sex.male), 0);
      expect(
        Trimp.rate(220, restingHr: 60, maxHr: 180, sex: Sex.male),
        closeTo(0.64 * math.exp(1.92), 1e-12),
      );
    });
  });

  group('zones and max HR', () {
    test('zoneFor: 50/60/70/80/90 % HRR display zones', () {
      int z(double bpm) => Engine.zoneFor(bpm, restingHr: 60, maxHr: 190);
      expect(z(120), 0); // 46 %
      expect(z(125), 1); // 50 %
      expect(z(139), 2); // 61 %
      expect(z(152), 3); // 71 %
      expect(z(165), 4); // 81 %
      expect(z(178), 5); // 91 %
      expect(z(205), 5);
      expect(Engine.zoneFor(150, restingHr: 190, maxHr: 180), 0);
    });

    test('maxHrFor: override, Tanaka with age, default age 30', () {
      final now = DateTime(2026, 9, 28);
      expect(Engine.maxHrFor(const UserProfile(maxHrOverride: 195), now), 195);
      expect(
        Engine.maxHrFor(const UserProfile(birthYear: 1990), now),
        closeTo(208 - 0.7 * 36, 1e-9),
      );
      expect(Engine.maxHrFor(const UserProfile(), now), closeTo(187, 1e-9));
      expect(
        Engine.maxHrFor(const UserProfile(maxHrOverride: 50), now),
        closeTo(187, 1e-9),
        reason: 'implausible override ignored',
      );
    });
  });

  group('live workout strain', () {
    final t0 = DateTime(2026, 8, 10, 18);
    test('1 Hz samples: minutes and strain accumulate per second', () {
      final samples = [
        for (var i = 0; i <= 600; i++)
          HrSample(t0.add(Duration(seconds: i)), 160),
      ];
      // PR #1: zones need a declared max-HR anchor (birth year or
      // override); without one the session is unavailable, not zero effort.
      final none = Engine.liveWorkoutStrain(
        samples,
        restingHr: 60,
        now: t0.add(const Duration(minutes: 20)),
      );
      expect(none.method, StrainMethod.none);
      expect(none.zoneMinutes.every((m) => m == 0), isTrue);
      final w = Engine.liveWorkoutStrain(
        samples,
        restingHr: 60,
        maxHr: 187,
        now: t0.add(const Duration(minutes: 20)),
      );
      final minutes = w.zoneMinutes.fold(0.0, (a, b) => a + b);
      expect(minutes, closeTo(10 + 1 / 60, 1e-6));
      // 160 bpm, RHR 60, max 187 → 78.7 % HRR → load zone 4 (w 8).
      expect(
        w.strain,
        closeTo(StrainEngine.strainFromRaw(8 * (10 + 1 / 60)), 1e-6),
      );
      expect(w.avgHr, 160);
      expect(w.trimp, isNotNull);
    });

    test('samples after now are ignored; empty input is safe', () {
      final w = Engine.liveWorkoutStrain(
        [HrSample(t0.add(const Duration(hours: 1)), 150)],
        restingHr: 60,
        now: t0,
      );
      expect(w.strain, 0);
      expect(Engine.liveWorkoutStrain(const [], restingHr: 60).strain, 0);
    });
  });
}
