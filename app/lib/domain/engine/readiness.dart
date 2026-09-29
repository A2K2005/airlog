// Plews lnRMSSD readiness. [ours, method cited by OpenStrap/edge]
//
// Plews et al. (2012, 2013): judge the 7-day ROLLING MEAN of ln(RMSSD), not a
// single night, against the individual's smallest worthwhile change (Hopkins)
// = baseline mean ± 0.5·SD of ln(RMSSD). Weekly CV of lnRMSSD is reported
// alongside (a rising CV flags instability even when the mean is normal).
//
// Our choices: the 7-day window is calendar days D−6…D and needs ≥ 3 nights
// (Plews: ≥ 3 values per week keep the rolling mean valid); the baseline is
// the definition-keyed segment (≤ 30 most recent nights before today, see
// baselines.dart) and needs ≥ 7 nights.

import 'dart:math' as math;

import '../results.dart';
import 'stats.dart';

abstract final class Readiness {
  static const int minWindowNights = 3;
  static const int minBaselineNights = 7;
  static const double swcFactor = 0.5;

  /// Calendar nights in the rolling window (D−6…D).
  static const int windowNights = 7;

  /// [lnWindow]: ln(RMSSD) of the nights in the 7-day window.
  /// [lnBaseline]: ln(RMSSD) of the baseline segment.
  static ReadinessSwc? compute({
    required List<double> lnWindow,
    required List<double> lnBaseline,
  }) {
    if (lnWindow.length < minWindowNights ||
        lnBaseline.length < minBaselineNights) {
      return null;
    }
    final rolling = Stats.mean(lnWindow);
    final mean = Stats.mean(lnBaseline);
    final sd = Stats.standardDeviation(lnBaseline);
    final lower = mean - swcFactor * sd;
    final upper = mean + swcFactor * sd;
    final state = rolling < lower
        ? SwcState.below
        : rolling > upper
        ? SwcState.above
        : SwcState.within;
    final windowMean = rolling.abs();
    final cv = windowMean < 1e-9
        ? 0.0
        : Stats.standardDeviation(lnWindow) / windowMean * 100;
    if (![rolling, mean, lower, upper, cv].every((v) => v.isFinite)) {
      return null;
    }
    return ReadinessSwc(
      lnRmssd7d: rolling,
      baselineMean: mean,
      swcLower: lower,
      swcUpper: upper,
      state: state,
      cv7d: math.max(0, cv).toDouble(),
    );
  }
}
