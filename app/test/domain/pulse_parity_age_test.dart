// Parity with Luraxx/pulse SelfTest main.swift (Apache-2.0, see
// third_party/pulse/NOTICE): "Alters-Normen" (:363-375), "Alters-Engine"
// (:377-461) and the English-component check of "Sprachen" (:172-184). Same
// fixtures, same checks, against engine/pulse_age.dart.
//
// V2 CANDIDATE: Pulse Age is not computed in v1 (product-critic review,
// 2026-09-29: it estimated VO₂max from a heart-rate ratio, principle 6).
// The module and these parity tests stay for v2, which must require a
// MEASURED VO₂max (Health Connect Vo2MaxRecord) instead of the estimate.

import 'package:airlog/domain/engine/pulse_age.dart';
import 'package:airlog/domain/engine/sleep.dart';
import 'package:airlog/domain/engine/strain.dart';
import 'package:airlog/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/pulse_demo_data.dart';

void main() {
  group('Alters-Normen (main.swift:363-375)', () {
    test('inversion hits the support points', () {
      expect((AgeNorms.fitnessAge(48.0, Sex.male) - 25).abs() < 1.0, isTrue);
      expect((AgeNorms.fitnessAge(40.3, Sex.male) - 45).abs() < 1.0, isTrue);
      expect((AgeNorms.fitnessAge(30.9, Sex.female) - 45).abs() < 1.0, isTrue);
    });
    test('fitter ⇒ younger fitness age', () {
      expect(
        AgeNorms.fitnessAge(55, Sex.male) < AgeNorms.fitnessAge(35, Sex.male),
        isTrue,
      );
    });
    test('very high VO₂max clamped to ≥ 20', () {
      final a = AgeNorms.fitnessAge(65, Sex.male);
      expect(a >= 20 && a <= 25, isTrue, reason: '$a');
    });
    test('RMSSD 46 → HRV age ≈ 35', () {
      expect((AgeNorms.hrvAge(46) - 35).abs() < 1.5, isTrue);
    });
    test('higher HRV ⇒ younger HRV age', () {
      expect(AgeNorms.hrvAge(60) < AgeNorms.hrvAge(25), isTrue);
    });
    test('VO₂max norm: men > women at the same age', () {
      expect(
        AgeNorms.vo2max(40, Sex.male) > AgeNorms.vo2max(40, Sex.female),
        isTrue,
      );
    });
  });

  group('Alters-Engine (main.swift:377-438)', () {
    const fit = AgeInputs(
      chronoAge: 30,
      sex: Sex.male,
      vo2maxValues: [52, 51, 53, 52, 54],
      rmssdValues: [57, 57, 57, 57, 57, 57, 57, 57, 57, 57],
      restingHrValues: [51, 51, 51, 51, 51, 51, 51, 51, 51, 51],
      sleepPerformances: [88, 90, 87, 91],
      stepsValues: [12000, 11500, 12500],
      validDayCount: 30,
    );
    final fitResult = AgeEngine.compute(fit);
    test('fit 30-year-old: Pulse Age in bounds, younger, measured VO₂max', () {
      expect(fitResult.pulseAge, isNotNull);
      final p = fitResult.pulseAge!;
      expect(p >= 15 && p <= 95, isTrue, reason: '$p');
      expect(
        fitResult.deltaYears! < 0,
        isTrue,
        reason: '${fitResult.deltaYears}',
      );
      expect(fitResult.vo2maxEstimated, isFalse);
    });

    const unfit = AgeInputs(
      chronoAge: 30,
      sex: Sex.male,
      vo2maxValues: [30, 30, 30, 30, 30],
      rmssdValues: [25, 25, 25, 25, 25, 25, 25, 25, 25, 25],
      restingHrValues: [72, 72, 72, 72, 72, 72, 72, 72, 72, 72],
      sleepPerformances: [60, 63, 58],
      stepsValues: [3000, 2800, 3200],
      validDayCount: 30,
    );
    final unfitResult = AgeEngine.compute(unfit);
    test('unfit person is biologically older', () {
      expect((unfitResult.deltaYears ?? 0) > 0, isTrue);
    });
    test('fit < unfit in Pulse Age', () {
      expect((fitResult.pulseAge ?? 0) < (unfitResult.pulseAge ?? 0), isTrue);
    });

    test('calibration gate: under 14 valid days → no value', () {
      final early = AgeEngine.compute(
        const AgeInputs(
          chronoAge: 30,
          sex: Sex.male,
          vo2maxValues: [50, 51, 52],
          rmssdValues: [55, 55, 55, 55, 55, 55, 55, 55],
          restingHrValues: [52, 52, 52, 52, 52, 52, 52, 52],
          validDayCount: 10,
        ),
      );
      expect(early.pulseAge, isNull);
      expect(early.calibrating, isTrue);
      expect(early.calibrationHave, 10);
    });

    test(
      'double-count guard: estimated VO₂max → no separate RHR adjustment',
      () {
        final est = AgeEngine.compute(
          const AgeInputs(
            chronoAge: 40,
            sex: Sex.male,
            rmssdValues: [40, 40, 40, 40, 40, 40, 40, 40, 40, 40],
            restingHrValues: [58, 58, 58, 58, 58, 58, 58, 58, 58, 58, 58, 58],
            observedMaxHr: 185,
            sleepPerformances: [80, 82],
            stepsValues: [9000, 8500],
            validDayCount: 30,
          ),
        );
        expect(est.vo2maxEstimated, isTrue);
        expect(est.vo2max, isNotNull);
        expect(est.components.any((c) => c.key == 'rhr'), isFalse);
        expect(est.components.any((c) => c.key == 'fitness'), isTrue);
      },
    );
  });

  test(
    'Demo end-to-end: VO₂max present, Pulse Age plausible (main.swift:440-461)',
    () {
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
      final windowKeys = keys.sublist(keys.length - 30);
      final window = [for (final k in windowKeys) demo[k]!];
      final result = AgeEngine.compute(
        AgeInputs(
          chronoAge: 30,
          sex: Sex.male,
          vo2maxValues: [for (final r in window) ?r.vo2max],
          rmssdValues: [for (final r in window) ?r.hrvRmssd],
          restingHrValues: [for (final r in window) ?r.restingHr],
          sleepPerformances: [
            for (final k in windowKeys)
              if (sleep[k] case final a? when a.hasData) a.performance,
          ],
          stepsValues: [
            for (final r in window)
              if (r.steps case final s?) s.toDouble(),
          ],
          validDayCount: window
              .where((r) => r.hrvRmssd != null || r.restingHr != null)
              .length,
        ),
      );
      expect(result.vo2max, isNotNull);
      expect(result.pulseAge, isNotNull);
      expect(
        result.pulseAge! >= 15 && result.pulseAge! <= 45,
        isTrue,
        reason: '${result.pulseAge}',
      );
    },
  );

  test('Sprachen: AgeEngine components in English (main.swift:172-184)', () {
    final r = AgeEngine.compute(
      const AgeInputs(
        chronoAge: 30,
        sex: Sex.male,
        vo2maxValues: [52, 51, 53, 52, 54],
        rmssdValues: [57, 57, 57, 57, 57, 57, 57, 57, 57, 57],
        restingHrValues: [51, 51, 51, 51, 51, 51, 51, 51, 51, 51],
        sleepPerformances: [88, 90, 87, 91],
        stepsValues: [12000, 11500, 12500],
        validDayCount: 30,
      ),
    );
    expect(
      r.components.any(
        (c) =>
            c.label == 'Resting HR' ||
            c.label == 'Sleep' ||
            c.label == 'Activity',
      ),
      isTrue,
    );
  });
}
