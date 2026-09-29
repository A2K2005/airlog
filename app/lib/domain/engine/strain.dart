// Ported from Luraxx/pulse Core/Metrics/StrainEngine.swift (Apache-2.0, see
// third_party/pulse/NOTICE). Changes: Dart port; English zone labels; the
// accumulator also bins the same samples into the contract's five DISPLAY
// zones (50/60/70/80/90 % HRR, results.dart) next to Pulse's six LOAD zones
// (which alone drive the strain number); a configurable first-sample dt for
// 1 Hz live data; guards against a non-positive heart-rate reserve; runs on
// column arrays (hr_series.dart) for speed — same arithmetic.
//
// Pulse's own day/workout functions are kept verbatim in behaviour
// ([dayStrain], [workoutStrain]); our sparse-HR fallback, MET table and TRIMP
// cross-check are layered on top in strain_fallback.dart.

import 'dart:math' as math;
import 'dart:typed_data';

import '../models.dart';
import '../results.dart';
import 'hr_series.dart';
import 'inputs.dart';
import 'stats.dart';

/// Pulse StrainEngine.swift:3-19.
class StrainConfig {
  const StrainConfig({this.age = 30, this.maxHrOverride, this.tau = 450});
  final int age;
  final double? maxHrOverride;

  /// Time constant of the logarithmic 0–21 scale.
  final double tau;

  /// Override or Tanaka (208 − 0.7 × age). Pulse StrainEngine.swift:16-18.
  double get maxHr =>
      maxHrOverride ??
      (StrainEngine.tanakaIntercept - StrainEngine.tanakaSlope * age);
}

/// Result of [StrainEngine.accumulate].
class StrainAccumulation {
  const StrainAccumulation({
    required this.raw,
    required this.zones,
    required this.restMin,
    required this.displayZones,
    required this.displayRestMin,
    this.avgHr,
    this.peakHr,
  });

  /// Weighted load (Σ zoneWeight · minutes).
  final double raw;

  /// Minutes in Pulse's six load zones (index 0 = very light … 5 = max).
  final List<double> zones;

  /// Minutes below load zone 0 (< 20 % HRR).
  final double restMin;

  /// Minutes in the five display zones (50-60 … 90-100 % HRR).
  final List<double> displayZones;

  /// Minutes below display zone 1 (< 50 % HRR).
  final double displayRestMin;
  final double? avgHr;
  final double? peakHr;

  static StrainAccumulation empty() => StrainAccumulation(
    raw: 0,
    zones: List<double>.filled(StrainEngine.zoneWeights.length, 0),
    restMin: 0,
    displayZones: List<double>.filled(
      StrainEngine.displayZoneLowerBounds.length,
      0,
    ),
    displayRestMin: 0,
  );
}

abstract final class StrainEngine {
  /// Zone lower bounds as a fraction of heart-rate reserve (Karvonen).
  /// Pulse StrainEngine.swift:56.
  static const List<double> zoneLowerBounds = [
    0.20,
    0.30,
    0.45,
    0.60,
    0.72,
    0.85,
  ];

  /// Pulse StrainEngine.swift:57.
  static const List<double> zoneWeights = [0.5, 1.0, 2.5, 5.0, 8.0, 11.0];

  /// Pulse Language.swift:100 (English zone labels).
  static const List<String> zoneLabels = [
    'Very light',
    'Light',
    'Moderate',
    'Demanding',
    'Hard',
    'Max',
  ];

  /// [ours] Display zones promised by results.dart (StrainResult.zoneMinutes,
  /// Engine.zoneFor): 50-60, 60-70, 70-80, 80-90, 90-100 % HRR.
  static const List<double> displayZoneLowerBounds = [0.5, 0.6, 0.7, 0.8, 0.9];

  /// Top of the strain scale. Pulse StrainEngine.swift:60-63.
  static const double scaleMax = 21;

  /// Tanaka (2001) age-predicted max HR: intercept − slope × age.
  /// Pulse StrainEngine.swift:16-18.
  static const double tanakaIntercept = 208;
  static const double tanakaSlope = 0.7;

  /// Daily target = factor × recovery, clamped to [targetMin, targetMax].
  /// Pulse StrainEngine.swift:70-72.
  static const double targetFactor = 0.2;
  static const double targetMin = 3;
  static const double targetMax = 18.5;

  /// `21·(1 − e^(−raw/τ))`. Pulse StrainEngine.swift:60-63.
  static double strainFromRaw(double raw, {double tau = 450}) {
    if (!(raw > 0) || !(tau > 0)) return 0;
    final s = scaleMax * (1 - math.exp(-raw / tau));
    return s.isFinite ? s : scaleMax;
  }

  /// Daily strain target from the morning recovery: 0.2 × recovery,
  /// clamped to 3…18.5. Pulse StrainEngine.swift:70-72.
  static double targetStrain(int recovery) =>
      Stats.clamp(targetFactor * recovery, targetMin, targetMax);

  /// [ours] Without a resting HR, zones use % of max HR placed on the
  /// reserve scale by Swain et al. 1994 (Med Sci Sports Exerc 26:112):
  /// %HRmax = 0.64 × %HRR + 37. Accumulating against a pseudo resting HR of
  /// [swainIntercept]·max and a pseudo max of (0.37 + 0.64)·max gives
  /// exactly that conversion; never an assumed resting HR (Pulse used 62).
  static const double swainSlope = 0.64;
  static const double swainIntercept = 0.37;

  /// The (restingHr, maxHr) pair the accumulator uses for %HRmax zones.
  static (double, double) maxHrZoneAnchors(double maxHr) =>
      (swainIntercept * maxHr, (swainIntercept + swainSlope) * maxHr);

  /// [ours] Half-width of the effort RANGE that TodayPlan shows around
  /// [targetStrain] (Pulse gives one number; a range reads as guidance, not
  /// precision). The range is target ± this, rounded to whole strain points
  /// and kept within 0…[scaleMax], e.g. target 7.4 → "strain 6–9". It is
  /// the only number TodayPlan derives rather than copies.
  static const double targetBand = 1.5;

  /// Whole-number effort range around [target] (see [targetBand]).
  static (int, int) targetRange(double target) {
    final lo = Stats.clamp(target - targetBand, 0, scaleMax).round();
    final hi = Stats.clamp(target + targetBand, 0, scaleMax).round();
    return (lo, hi);
  }

  /// Highest load zone whose lower bound [fraction] reaches, or null below
  /// zone 0. Pulse StrainEngine.swift:74-80.
  static int? zoneIndex(double fraction) {
    int? index;
    for (var i = 0; i < zoneLowerBounds.length; i++) {
      if (fraction >= zoneLowerBounds[i]) index = i;
    }
    return index;
  }

  /// [ours] Display zone 1..5 for [fraction] of HRR, 0 below 50 %.
  static int displayZone(double fraction) {
    var z = 0;
    for (var i = 0; i < displayZoneLowerBounds.length; i++) {
      if (fraction >= displayZoneLowerBounds[i]) z = i + 1;
    }
    return z;
  }

  /// HRR fraction, or null when the reserve is not positive.
  static double? hrrFraction(double bpm, double restingHr, double maxHr) {
    final reserve = maxHr - restingHr;
    if (!(reserve > 0)) return null;
    final f = (bpm - restingHr) / reserve;
    return f.isFinite ? f : null;
  }

  /// Weighted load over HR samples (minute resolution).
  /// Pulse StrainEngine.swift:82-118: dt = minutes since the previous sample,
  /// clamped to 0..5, first sample counts [firstDt] (Pulse: 1 minute).
  static StrainAccumulation accumulate(
    List<HrSample> samples, {
    required double restingHr,
    required double maxHr,
    double firstDt = 1,
  }) => accumulateSeries(
    HrSeries.of(samples),
    restingHr: restingHr,
    maxHr: maxHr,
    firstDt: firstDt,
  );

  /// [accumulate] over samples [from, to) of a series.
  static StrainAccumulation accumulateSeries(
    HrSeries s, {
    int from = 0,
    int? to,
    required double restingHr,
    required double maxHr,
    double firstDt = 1,
  }) {
    final end = to ?? s.length;
    // Pulse :89 — needs a usable reserve.
    if (end <= from || !(maxHr > restingHr + 20)) {
      return StrainAccumulation.empty();
    }
    final reserve = maxHr - restingHr;
    var raw = 0.0;
    // Typed accumulators (no boxed-double allocation per sample).
    final zones = Float64List(zoneWeights.length);
    final display = Float64List(displayZoneLowerBounds.length);
    var restMin = 0.0;
    var displayRest = 0.0;
    var sum = 0.0;
    var peak = 0.0;
    final t = s.m;
    final bpms = s.bpm;
    final lb = Float64List.fromList(zoneLowerBounds);
    final w = Float64List.fromList(zoneWeights);
    final db = Float64List.fromList(displayZoneLowerBounds);

    for (var i = from; i < end; i++) {
      var dt = firstDt;
      if (i > from) {
        final d = t[i] - t[i - 1];
        dt = d < 0 ? 0 : (d > 5 ? 5 : d); // Pulse :103
      }
      final bpm = bpms[i];
      sum += bpm;
      if (bpm > peak) peak = bpm;

      final fraction = (bpm - restingHr) / reserve;
      var dz = 0;
      for (var k = 0; k < 5; k++) {
        if (fraction >= db[k]) dz = k + 1;
      }
      if (dz == 0) {
        displayRest += dt;
      } else {
        display[dz - 1] += dt;
      }
      // Highest load zone reached (Pulse zoneIndex, :74-80).
      var zone = -1;
      for (var k = 0; k < 6; k++) {
        if (fraction >= lb[k]) zone = k;
      }
      if (zone < 0) {
        restMin += dt; // below zone 0 → rest / daily life, no strain
        continue;
      }
      raw += w[zone] * dt;
      zones[zone] += dt;
    }
    return StrainAccumulation(
      raw: raw,
      zones: List<double>.of(zones),
      restMin: restMin,
      displayZones: List<double>.of(display),
      displayRestMin: displayRest,
      avgHr: sum / (end - from),
      peakHr: peak,
    );
  }

  /// Day strain from intraday HR; fallback via workout average HR and steps
  /// when there are NO samples. Pulse StrainEngine.swift:122-162, faithful
  /// (used by the parity tests ONLY; the app's day strain is
  /// strain_fallback.dart, which never assumes Pulse's 62 bpm resting HR).
  static StrainResult dayStrain(
    DayRecord record, {
    double? restingHr,
    StrainConfig config = const StrainConfig(),
  }) {
    final rhr = restingHr ?? 62;
    final maxHr = config.maxHr;
    final samples = Inputs.hr(record);

    if (samples.isNotEmpty) {
      final acc = accumulate(samples, restingHr: rhr, maxHr: maxHr);
      return StrainResult(
        strain: strainFromRaw(acc.raw, tau: config.tau),
        rawLoad: acc.raw,
        zoneMinutes: acc.displayZones,
        loadZoneMinutes: acc.zones,
        restMinutes: acc.displayRestMin,
        method: StrainMethod.hrZones,
        avgHr: acc.avgHr,
        peakHr: acc.peakHr,
        maxHrUsed: maxHr,
        restingHrUsed: rhr,
      );
    }

    // Pulse :142-161 — fallback without intraday data.
    var raw = 0.0;
    final zones = List<double>.filled(zoneWeights.length, 0);
    final display = List<double>.filled(displayZoneLowerBounds.length, 0);
    for (final w in record.workouts) {
      final avg = finiteOrNull(w.averageHr);
      if (avg == null) continue;
      final fraction = hrrFraction(avg, rhr, maxHr);
      if (fraction == null) continue;
      final zone = zoneIndex(fraction);
      if (zone == null) continue;
      final minutes = Inputs.minutes(w.durationMinutes);
      raw += zoneWeights[zone] * minutes;
      zones[zone] += minutes;
      final dz = displayZone(fraction);
      if (dz > 0) display[dz - 1] += minutes;
    }
    final steps = Inputs.steps(record);
    if (steps != null && steps > 0) {
      raw += steps / 1000 * 2.0;
    }
    return StrainResult(
      strain: strainFromRaw(raw, tau: config.tau),
      rawLoad: raw,
      zoneMinutes: display,
      loadZoneMinutes: zones,
      method: StrainMethod.fallback,
      maxHrUsed: maxHr,
      restingHrUsed: rhr,
    );
  }

  /// Strain of one workout on its own 0–21 scale.
  /// Pulse StrainEngine.swift:165-182: HR slice if ≥ 3 samples, else the
  /// workout's average HR mapped to one zone × duration, else null.
  static double? workoutStrain(
    Workout workout,
    List<HrSample> daySamples, {
    double? restingHr,
    StrainConfig config = const StrainConfig(),
  }) {
    final rhr = restingHr ?? 62;
    final series = HrSeries.of(Inputs.cleanHr(daySamples));
    final (from, to) = series.closedRange(workout.start, workout.end);
    if (to - from >= 3) {
      final acc = accumulateSeries(
        series,
        from: from,
        to: to,
        restingHr: rhr,
        maxHr: config.maxHr,
      );
      return strainFromRaw(acc.raw, tau: config.tau);
    }
    final avg = finiteOrNull(workout.averageHr);
    if (avg == null) return null;
    final fraction = hrrFraction(avg, rhr, config.maxHr);
    if (fraction == null) return 0;
    final zone = zoneIndex(fraction);
    if (zone == null) return 0;
    final raw = zoneWeights[zone] * Inputs.minutes(workout.durationMinutes);
    return strainFromRaw(raw, tau: config.tau);
  }
}
