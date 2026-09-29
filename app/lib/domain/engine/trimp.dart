// Banister TRIMP (training impulse). [ours, method cited by OpenStrap/edge]
//
// Banister EW (1991) "Modeling elite athletic performance"; weighting from
// Morton, Fitz-Clarke & Banister (1990):
//   TRIMP = Σ Δt[min] · x · y(x),  x = (HR − HRrest) / (HRmax − HRrest) ∈ [0,1]
//   y(x)  = 0.64·e^(1.92x) (male) | 0.86·e^(1.67x) (female)
// `Sex.unspecified` uses the mean of the two weighting curves.
//
// Used as a cross-check next to Pulse's zone-weighted load, never as the
// headline strain. Δt follows the Pulse accumulator (minutes since previous
// sample clamped to 0..5, first sample = [firstDt]) so both see the same time.

import 'dart:math' as math;

import '../models.dart';
import 'hr_series.dart';
import 'stats.dart';

abstract final class Trimp {
  /// y(x) = a·e^(b·x): Morton, Fitz-Clarke & Banister (1990).
  static const double maleA = 0.64, maleB = 1.92;
  static const double femaleA = 0.86, femaleB = 1.67;

  /// y(x): the sex-specific exponential weighting.
  static double weighting(double x, Sex sex) => switch (sex) {
    Sex.male => maleA * math.exp(maleB * x),
    Sex.female => femaleA * math.exp(femaleB * x),
    Sex.unspecified =>
      (maleA * math.exp(maleB * x) + femaleA * math.exp(femaleB * x)) / 2,
  };

  /// Per-minute TRIMP rate at [bpm].
  static double rate(
    double bpm, {
    required double restingHr,
    required double maxHr,
    required Sex sex,
  }) {
    final reserve = maxHr - restingHr;
    if (!(reserve > 0)) return 0;
    final x = Stats.clamp((bpm - restingHr) / reserve, 0, 1);
    if (!x.isFinite || x == 0) return 0;
    return x * weighting(x, sex);
  }

  /// TRIMP over [samples]. [exclude] (sorted, merged µs intervals, e.g.
  /// sleep) masks samples out while their Δt still separates neighbours.
  /// Null when there is no usable reserve or no samples.
  static double? fromSamples(
    List<HrSample> samples, {
    required double restingHr,
    required double maxHr,
    required Sex sex,
    double firstDt = 1,
  }) => fromSeries(
    HrSeries.of(samples),
    restingHr: restingHr,
    maxHr: maxHr,
    sex: sex,
    firstDt: firstDt,
  );

  static double? fromSeries(
    HrSeries s, {
    int from = 0,
    int? to,
    required double restingHr,
    required double maxHr,
    required Sex sex,
    UsIntervals exclude = const [],
    double firstDt = 1,
  }) {
    final end = to ?? s.length;
    if (end <= from || !(maxHr > restingHr + 20)) return null;
    final cursor = IntervalCursor(s, exclude);
    final reserve = maxHr - restingHr;
    final m = s.m;
    final bpm = s.bpm;
    var total = 0.0;
    for (var i = from; i < end; i++) {
      var dt = firstDt;
      if (i > from) {
        final d = m[i] - m[i - 1];
        dt = d < 0 ? 0 : (d > 5 ? 5 : d);
      }
      if (exclude.isNotEmpty && cursor.inside(m[i])) continue;
      final x0 = (bpm[i] - restingHr) / reserve;
      if (!(x0 > 0)) continue; // at or below rest: no impulse
      final x = x0 > 1 ? 1.0 : x0;
      total += dt * x * weighting(x, sex);
    }
    return total.isFinite ? total : null;
  }

  /// TRIMP of [minutes] at a constant [avgHr] (workout without samples).
  static double? fromAverage(
    double avgHr,
    double minutes, {
    required double restingHr,
    required double maxHr,
    required Sex sex,
  }) {
    if (!(maxHr > restingHr + 20) || !avgHr.isFinite || !(minutes > 0)) {
      return null;
    }
    final t =
        minutes * rate(avgHr, restingHr: restingHr, maxHr: maxHr, sex: sex);
    return t.isFinite ? t : null;
  }
}
