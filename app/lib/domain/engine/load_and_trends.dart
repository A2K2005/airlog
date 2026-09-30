// Ported from Luraxx/pulse Core/Metrics/Stats.swift (TrendMath, :64-96)
// (Apache-2.0, see third_party/pulse/NOTICE). Changes: Dart port; pairs are
// Dart records; calendar math via Civil (same results as DayKey, no local-
// time construction). Everything else in this file is ours:
//
// Training load (ACWR), significance-tested trends, and trend aggregation.
// * TrainingLoadEngine, TrendEngine: [ours].
//   - ACWR (Gabbett 2016, coupled): mean daily strain over the last 7 days ÷
//     mean over the last 28 days (both ending at `asOf`). Days without a
//     strain value are skipped, not counted as 0 (an unworn band is not a
//     rest day). Null with < 14 strain days in the 28-day window or a zero
//     chronic load. States: < 0.8 detraining, 0.8–1.3 optimal, 1.3–1.5
//     elevated, > 1.5 high.
//   - Trend: Mann-Kendall test with the tie-corrected variance and a
//     continuity correction, two-sided at p < 0.05 (|Z| > 1.959964), n ≥ 7;
//     slope = Sen's slope (median pairwise slope over the ORIGINAL indices,
//     so gaps count as elapsed days). Direction is flat unless significant.

import 'dart:math' as math;

import '../results.dart';
import 'hr_series.dart';
import 'stats.dart';

typedef KeyValue = ({String key, double value});

abstract final class TrendMath {
  /// Moving average over the last [window] calendar days; missing days are
  /// skipped, not counted as 0. Pulse Stats.swift:69-80.
  static List<KeyValue> movingAverage(List<KeyValue> pairs, int window) {
    if (window <= 1) return pairs;
    final byKey = <String, double>{};
    for (final p in pairs) {
      byKey.putIfAbsent(p.key, () => p.value);
    }
    return [
      for (final p in pairs)
        (
          key: p.key,
          value: Stats.mean([
            for (final k in Civil.range(Civil.add(p.key, -(window - 1)), p.key))
              if (byKey[k] != null) byKey[k]!,
          ]),
        ),
    ];
  }

  /// Mean per calendar week, keyed by that week's Monday.
  /// Pulse Stats.swift:83-95.
  static List<KeyValue> weeklyMean(List<KeyValue> pairs) {
    final buckets = <String, List<double>>{};
    for (final p in pairs) {
      final monday = Civil.add(
        p.key,
        -(Civil.weekday(p.key) - DateTime.monday),
      );
      (buckets[monday] ??= []).add(p.value);
    }
    final keys = buckets.keys.toList()..sort();
    return [for (final k in keys) (key: k, value: Stats.mean(buckets[k]!))];
  }
}

abstract final class TrainingLoadEngine {
  static const int minDays = 14;
  static const int minAcuteDays = 5;

  /// Acute and chronic windows (calendar days).
  static const int acuteDays = 7, chronicDays = 28;

  /// LoadState cut-points on the ratio (Gabbett 2016): below [optimalFrom]
  /// detraining, up to [optimalTo] optimal, up to [elevatedTo] elevated.
  static const double optimalFrom = 0.8, optimalTo = 1.3, elevatedTo = 1.5;

  static TrainingLoad? compute(Map<String, double> strainByDay, String asOf) {
    List<double> window(int days) => [
      for (final k in Civil.range(Civil.add(asOf, -(days - 1)), asOf))
        if (strainByDay[k] != null && strainByDay[k]!.isFinite) strainByDay[k]!,
    ];
    final acute = window(acuteDays);
    final chronic = window(chronicDays);
    if (chronic.length < minDays || acute.length < minAcuteDays) return null;
    final acute7 = Stats.mean(acute);
    final chronic28 = Stats.mean(chronic);
    if (!(chronic28 > 0)) return null;
    final ratio = acute7 / chronic28;
    if (!ratio.isFinite) return null;
    return TrainingLoad(
      acute7: acute7,
      chronic28: chronic28,
      ratio: ratio,
      state: stateFor(ratio),
      daysOfHistory: chronic.length,
    );
  }

  static LoadState stateFor(double ratio) => ratio < optimalFrom
      ? LoadState.detraining
      : ratio <= optimalTo
      ? LoadState.optimal
      : ratio <= elevatedTo
      ? LoadState.elevated
      : LoadState.high;
}

abstract final class TrendEngine {
  static const int minN = 7;
  static const double zCritical = 1.959964; // two-sided p = 0.05
  static const int recentWindow = 7;

  static TrendResult compute(List<double?> values) {
    final xs = <int>[];
    final ys = <double>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v != null && v.isFinite) {
        xs.add(i);
        ys.add(v);
      }
    }
    final n = ys.length;

    final split = math.max(0, values.length - recentWindow);
    final recent = [
      for (var i = split; i < values.length; i++)
        if (values[i] != null && values[i]!.isFinite) values[i]!,
    ];
    final prior = [
      for (var i = 0; i < split; i++)
        if (values[i] != null && values[i]!.isFinite) values[i]!,
    ];
    final recentMean = recent.isEmpty ? null : Stats.mean(recent);
    final priorMean = prior.isEmpty ? null : Stats.mean(prior);

    if (n < 2) {
      return TrendResult(
        direction: TrendDirection.flat,
        slopePerDay: 0,
        significant: false,
        n: n,
        recentMean: recentMean,
        priorMean: priorMean,
      );
    }

    var s = 0;
    final slopes = <double>[];
    for (var i = 0; i < n - 1; i++) {
      for (var j = i + 1; j < n; j++) {
        final d = ys[j] - ys[i];
        s += d > 0 ? 1 : (d < 0 ? -1 : 0);
        slopes.add(d / (xs[j] - xs[i]));
      }
    }
    final sen = Stats.median(slopes) ?? 0;

    // Tie correction: Σ t(t−1)(2t+5) over groups of equal values.
    final groups = <double, int>{};
    for (final y in ys) {
      groups[y] = (groups[y] ?? 0) + 1;
    }
    var tieSum = 0.0;
    for (final t in groups.values) {
      if (t > 1) tieSum += t * (t - 1) * (2 * t + 5);
    }
    final variance = (n * (n - 1) * (2 * n + 5) - tieSum) / 18;
    var z = 0.0;
    if (variance > 0) {
      if (s > 0) z = (s - 1) / math.sqrt(variance);
      if (s < 0) z = (s + 1) / math.sqrt(variance);
    }
    final significant = n >= minN && z.abs() > zCritical;
    return TrendResult(
      direction: !significant
          ? TrendDirection.flat
          : (s > 0 ? TrendDirection.up : TrendDirection.down),
      slopePerDay: sen.isFinite ? sen : 0,
      significant: significant,
      n: n,
      recentMean: recentMean,
      priorMean: priorMean,
    );
  }
}
