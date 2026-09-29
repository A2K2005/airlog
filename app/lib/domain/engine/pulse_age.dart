// Ported from Luraxx/pulse Core/Metrics/AgeEngine.swift (Apache-2.0, see
// third_party/pulse/NOTICE). Changes: Dart port; English labels/details
// only; returns the contract's PulseAgeResult; sanitises the median inputs.
// Constants, norms, weights, caps and the calibration gates are unchanged
// (value shown from 14 valid days, `calibrating` until 30 — AgeEngine.swift
// :215-216, :289-291).
//
// Norm sources (as cited by Pulse): FRIEND registry 50th percentile,
// treadmill (Kaminsky et al., Mayo Clin Proc 2015); Mandsager et al., JAMA
// Netw Open 2018; RMSSD decline (Shaffer & Ginsberg 2017); resting HR
// +10 bpm ≈ HR 1.09 all-cause mortality (Zhang et al., CMAJ 2016); VO₂max
// heart-rate-ratio method (Uth et al. 2004); Nes/HUNT HRmax 211 − 0.64·age.

import '../models.dart';
import '../results.dart';
import 'stats.dart';

/// One norm-curve support point.
typedef AgePoint = ({double age, double value});

abstract final class AgeNorms {
  /// VO₂max median (ml/kg/min) at decade mid-points. AgeEngine.swift:21-24.
  static const List<AgePoint> vo2maxMale = [
    (age: 25, value: 48.0),
    (age: 35, value: 44.6),
    (age: 45, value: 40.3),
    (age: 55, value: 35.0),
    (age: 65, value: 29.4),
    (age: 75, value: 24.4),
  ];
  static const List<AgePoint> vo2maxFemale = [
    (age: 25, value: 37.6),
    (age: 35, value: 34.1),
    (age: 45, value: 30.9),
    (age: 55, value: 27.1),
    (age: 65, value: 22.6),
    (age: 75, value: 18.3),
  ];

  /// RMSSD reference (ms), sex-agnostic. AgeEngine.swift:28-29.
  static const List<AgePoint> rmssdRef = [
    (age: 25, value: 60),
    (age: 35, value: 46),
    (age: 45, value: 36),
    (age: 55, value: 29),
    (age: 65, value: 23),
  ];

  /// AgeEngine.swift:31-38 (unspecified = mean of both curves).
  static List<AgePoint> vo2maxCurve(Sex sex) => switch (sex) {
    Sex.male => vo2maxMale,
    Sex.female => vo2maxFemale,
    Sex.unspecified => [
      for (var i = 0; i < vo2maxMale.length; i++)
        (
          age: vo2maxMale[i].age,
          value: (vo2maxMale[i].value + vo2maxFemale[i].value) / 2,
        ),
    ],
  };

  /// AgeEngine.swift:41-47.
  static double restingHrRef(Sex sex) => switch (sex) {
    Sex.male => 60,
    Sex.female => 63,
    Sex.unspecified => 61,
  };

  /// AgeEngine.swift:50-52.
  static double vo2max(double age, Sex sex) =>
      interpolate(vo2maxCurve(sex), age);

  /// Fitness age, clamped to 20…90. AgeEngine.swift:57-59.
  static double fitnessAge(double vo2max, Sex sex) =>
      invertDecreasing(vo2maxCurve(sex), vo2max, 20, 90);

  /// HRV-equivalent age, clamped to 18…85. AgeEngine.swift:62-64.
  static double hrvAge(double rmssd) =>
      invertDecreasing(rmssdRef, rmssd, 18, 85);

  /// AgeEngine.swift:69-83 (edge slopes extrapolate).
  static double interpolate(List<AgePoint> points, double x) {
    if (points.isEmpty) return 0;
    if (x <= points.first.age) return _lerp(points[0], points[1], x);
    if (x >= points.last.age) {
      return _lerp(points[points.length - 2], points[points.length - 1], x);
    }
    for (var i = 1; i < points.length; i++) {
      if (x <= points[i].age) return _lerp(points[i - 1], points[i], x);
    }
    return points.last.value;
  }

  static double _lerp(AgePoint a, AgePoint b, double x) {
    final t = (x - a.age) / (b.age - a.age);
    return a.value + t * (b.value - a.value);
  }

  /// Inverts a monotonically DECREASING curve (value → age), clamped.
  /// AgeEngine.swift:92-106.
  static double invertDecreasing(
    List<AgePoint> points,
    double v,
    double lo,
    double hi,
  ) {
    if (v >= points.first.value) {
      return Stats.clamp(_invLerp(points[0], points[1], v), lo, hi);
    }
    if (v <= points.last.value) {
      return Stats.clamp(
        _invLerp(points[points.length - 2], points[points.length - 1], v),
        lo,
        hi,
      );
    }
    for (var i = 1; i < points.length; i++) {
      if (v >= points[i].value) {
        return Stats.clamp(_invLerp(points[i - 1], points[i], v), lo, hi);
      }
    }
    return Stats.clamp(points.last.age, lo, hi);
  }

  static double _invLerp(AgePoint a, AgePoint b, double v) {
    final denom = b.value - a.value;
    if (denom.abs() <= 1e-9) return a.age;
    final t = (v - a.value) / denom;
    return a.age + t * (b.age - a.age);
  }
}

/// Pre-aggregated inputs. AgeEngine.swift:120-160.
class AgeInputs {
  const AgeInputs({
    required this.chronoAge,
    required this.sex,
    this.vo2maxValues = const [],
    this.rmssdValues = const [],
    this.restingHrValues = const [],
    this.observedMaxHr,
    this.maxHrOverride,
    this.sleepPerformances = const [],
    this.stepsValues = const [],
    this.validDayCount = 0,
  });
  final int chronoAge;
  final Sex sex;
  final List<double> vo2maxValues;
  final List<double> rmssdValues;
  final List<double> restingHrValues;

  /// Robust observed max HR (p97.5 of intraday HR) or null.
  final double? observedMaxHr;
  final double? maxHrOverride;

  /// Sleep performance per day (0–100).
  final List<double> sleepPerformances;
  final List<double> stepsValues;

  /// Days in the window with at least one recovery input (HRV or RHR).
  final int validDayCount;
}

abstract final class AgeEngine {
  static const double fitnessWeight = 0.7; // AgeEngine.swift:213
  static const double hrvWeight = 0.3; // :214
  static const int calibrationNeed = 30; // :215
  static const int minProvisionalDays = 14; // :216
  static const double uthFactor = 15.3; // :219

  /// AgeEngine.swift:221-364.
  static PulseAgeResult compute(AgeInputs inputs) {
    final chrono = inputs.chronoAge.toDouble();
    final have = inputs.validDayCount < calibrationNeed
        ? inputs.validDayCount
        : calibrationNeed;

    // Backbone: VO₂max measured (≥3 days, median) or estimated. :226-241
    double? vo2;
    var vo2Estimated = false;
    final measured = Stats.median(inputs.vo2maxValues);
    final rhrMedian = Stats.median(inputs.restingHrValues);
    if (measured != null && inputs.vo2maxValues.length >= 3) {
      vo2 = measured;
    } else if (rhrMedian != null && inputs.restingHrValues.length >= 5) {
      final hrMax =
          inputs.maxHrOverride ??
          trustworthyMaxHr(inputs.observedMaxHr) ??
          (211 - 0.64 * chrono);
      if (hrMax > rhrMedian + 20) {
        vo2 = Stats.clamp(uthFactor * hrMax / rhrMedian, 15, 80);
        vo2Estimated = true;
      }
    }

    final fitnessAge = vo2 == null
        ? null
        : AgeNorms.fitnessAge(vo2, inputs.sex);

    // HRV age (needs ≥7 readings). :245-249
    double? hrvAge;
    final rmssd = Stats.median(inputs.rmssdValues);
    if (inputs.rmssdValues.length >= 7 && rmssd != null) {
      hrvAge = AgeNorms.hrvAge(rmssd);
    }

    // Core = weighted mean of the available equivalent ages. :251-259
    double? core;
    final pairs = <(double, double)>[
      if (fitnessAge != null) (fitnessAge, fitnessWeight),
      if (hrvAge != null) (hrvAge, hrvWeight),
    ];
    if (pairs.isNotEmpty) {
      final wSum = pairs.fold(0.0, (a, p) => a + p.$2);
      core = pairs.fold(0.0, (a, p) => a + p.$1 * p.$2) / wSum;
    }

    // Capped adjustments. Resting HR only when VO₂max was MEASURED (the
    // estimate already carries RHR in its denominator). :261-271
    double? rhrDelta;
    if (!vo2Estimated &&
        rhrMedian != null &&
        inputs.restingHrValues.length >= 5) {
      final ref = AgeNorms.restingHrRef(inputs.sex);
      rhrDelta = Stats.clamp((rhrMedian - ref) / 10 * 2.5, -3, 3);
    }

    // Sleep vs ~78 % target corridor, ±1.5. :273-278
    double? sleepDelta;
    if (inputs.sleepPerformances.isNotEmpty) {
      final perf = Stats.mean(inputs.sleepPerformances);
      sleepDelta = Stats.clamp((78 - perf) / 12, -1.5, 1.5);
    }

    // Activity vs ~8000 steps/day, ±1.5. :280-286
    double? activityDelta;
    if (inputs.stepsValues.isNotEmpty) {
      final steps = Stats.mean(inputs.stepsValues);
      final ratio = Stats.clamp(steps / 8000, 0, 1.6);
      activityDelta = Stats.clamp((1 - ratio) * 1.5, -1.5, 1.5);
    }

    // Calibration. :288-291
    final backboneResolvable = vo2 != null;
    final hasEnoughDays = inputs.validDayCount >= minProvisionalDays;
    final calibrating =
        inputs.validDayCount < calibrationNeed || !backboneResolvable;

    final components = <AgeComponent>[];
    if (vo2 != null && fitnessAge != null) {
      final est = vo2Estimated ? ' (estimated)' : '';
      components.add(
        AgeComponent(
          key: 'fitness',
          label: 'Fitness (VO₂max)',
          detail:
              '${vo2.toStringAsFixed(0)} ml/kg/min$est · fitness age '
              '${fitnessAge.toStringAsFixed(0)}',
          deltaYears: fitnessAge - chrono,
          kind: AgeComponentKind.equivalent,
        ),
      );
    }
    if (hrvAge != null && rmssd != null) {
      components.add(
        AgeComponent(
          key: 'hrv',
          label: 'HRV',
          detail:
              '${rmssd.toStringAsFixed(0)} ms · HRV age '
              '${hrvAge.toStringAsFixed(0)}',
          deltaYears: hrvAge - chrono,
          kind: AgeComponentKind.equivalent,
        ),
      );
    }
    if (rhrDelta != null && rhrMedian != null) {
      components.add(
        AgeComponent(
          key: 'rhr',
          label: 'Resting HR',
          detail: '${rhrMedian.toStringAsFixed(0)} bpm',
          deltaYears: rhrDelta,
          kind: AgeComponentKind.adjustment,
        ),
      );
    }
    if (sleepDelta != null) {
      components.add(
        AgeComponent(
          key: 'sleep',
          label: 'Sleep',
          detail:
              'avg ${Stats.mean(inputs.sleepPerformances).toStringAsFixed(0)}'
              ' % performance',
          deltaYears: sleepDelta,
          kind: AgeComponentKind.adjustment,
        ),
      );
    }
    if (activityDelta != null) {
      components.add(
        AgeComponent(
          key: 'activity',
          label: 'Activity',
          detail:
              'avg ${Stats.mean(inputs.stepsValues).toStringAsFixed(0)}'
              ' steps/day',
          deltaYears: activityDelta,
          kind: AgeComponentKind.adjustment,
        ),
      );
    }

    // Only when the backbone resolves AND enough days. :342-350
    double? pulseAge;
    if (backboneResolvable && hasEnoughDays && core != null) {
      final offsets = Stats.clamp(
        (rhrDelta ?? 0) + (sleepDelta ?? 0) + (activityDelta ?? 0),
        -5,
        5,
      );
      pulseAge = Stats.clamp(core + offsets, 15, 95);
    }

    return PulseAgeResult(
      chronoAge: inputs.chronoAge,
      pulseAge: pulseAge,
      components: components,
      vo2max: vo2,
      vo2maxEstimated: vo2Estimated,
      fitnessAge: fitnessAge,
      calibrating: calibrating,
      calibrationHave: have,
      calibrationNeed: calibrationNeed,
    );
  }

  /// Observed max HR only if physiologically plausible. AgeEngine.swift:369-372.
  static double? trustworthyMaxHr(double? v) =>
      (v == null || !v.isFinite || v < 150 || v > 220) ? null : v;
}
