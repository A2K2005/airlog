// Ported from Luraxx/pulse Core/Metrics/Stats.swift (Apache-2.0, see
// third_party/pulse/NOTICE). Changes: Dart port; the Baseline type lives in
// results.dart (contract); added median, percentileOfSorted and an exact
// percentile over several pre-sorted lists (used by Pulse Age so a 30-day,
// 1-sample-per-minute window never has to be re-sorted every day).

import 'dart:math' as math;
import 'dart:typed_data';

import '../results.dart';

abstract final class Stats {
  /// Pulse Stats.swift:24-27 (0 for an empty list).
  static double mean(Iterable<double> values) {
    var n = 0;
    var sum = 0.0;
    for (final v in values) {
      sum += v;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  /// Sample standard deviation (n − 1). Pulse Stats.swift:29-34.
  static double standardDeviation(List<double> values) {
    if (values.length <= 1) return 0;
    final m = mean(values);
    var acc = 0.0;
    for (final v in values) {
      acc += (v - m) * (v - m);
    }
    return math.sqrt(acc / (values.length - 1));
  }

  /// Percentile with linear interpolation, p in 0..1. Pulse Stats.swift:36-47.
  static double? percentile(List<double> values, double p) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    return percentileOfSorted(sorted, p);
  }

  /// Same as [percentile] for an already ascending, non-empty list.
  static double percentileOfSorted(List<double> sorted, double p) {
    final position = clamp(p, 0, 1) * (sorted.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    final fraction = position - lower;
    return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
  }

  /// Pulse AgeEngine.swift:374-376 (`percentile(values, 0.5)`).
  static double? median(List<double> values) => percentile(values, 0.5);

  /// Fewest values a baseline is built from. Pulse Stats.swift:50.
  static const int minBaselineValues = 3;

  /// Baseline from a value list; null below 3 points. Pulse Stats.swift:49-53.
  static Baseline? baseline(List<double> values) {
    if (values.length < minBaselineValues) return null;
    return Baseline(
      mean: mean(values),
      sd: standardDeviation(values),
      count: values.length,
    );
  }

  /// Pulse Stats.swift:55-57.
  static double logistic(double x) => 1 / (1 + math.exp(-x));

  /// Pulse Stats.swift:59-61.
  static double clamp(double value, double lower, double upper) =>
      math.min(math.max(value, lower), upper);

  /// [ours] Ascending copy of [values]. Bucket sort over [min, max] with one
  /// bucket per value, then an insertion pass (nearly sorted input): O(n)
  /// for heart-rate data, where the default comparator sort is ~7× slower.
  /// Exact for any input; non-finite values fall back to List.sort.
  static Float64List sortedCopy(List<double> values) {
    final n = values.length;
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final v in values) {
      if (!v.isFinite) return Float64List.fromList([...values]..sort());
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final out = Float64List(n);
    final span = hi - lo;
    if (n < 64 || !(span > 0)) {
      out.setAll(0, values);
      if (n > 1 && span > 0) out.sort();
      return out;
    }
    final scale = (n - 1) / span;
    final start = Int32List(n + 1);
    final idx = Int32List(n);
    for (var i = 0; i < n; i++) {
      final b = ((values[i] - lo) * scale).floor();
      idx[i] = b;
      start[b + 1]++;
    }
    for (var b = 0; b < n; b++) {
      start[b + 1] += start[b];
    }
    final fill = Int32List.fromList(start);
    for (var i = 0; i < n; i++) {
      out[fill[idx[i]]++] = values[i];
    }
    for (var i = 1; i < n; i++) {
      final v = out[i];
      var j = i - 1;
      while (j >= 0 && out[j] > v) {
        out[j + 1] = out[j];
        j--;
      }
      out[j + 1] = v;
    }
    return out;
  }

  /// [ours] Exact [percentile] of the union of several ascending lists,
  /// without concatenating and sorting them. Walks a k-way heap merge from
  /// whichever end of the distribution is closer to [p], so p = 0.975 over
  /// 30 × 1440 values touches ~1 100 elements instead of sorting 43 200.
  static double? percentileOfSortedLists(List<List<double>> lists, double p) {
    var n = 0;
    for (final l in lists) {
      n += l.length;
    }
    if (n == 0) return null;
    final position = clamp(p, 0, 1) * (n - 1);
    final lower = position.floor();
    final upper = position.ceil();
    final fraction = position - lower;
    final fromTop = (n - 1 - lower) < lower;
    final (lo, hi) = fromTop
        ? _ranks(lists, n - 1 - upper, n - 1 - lower, descending: true).swap
        : _ranks(lists, lower, upper, descending: false);
    if (lower == upper) return lo;
    return lo * (1 - fraction) + hi * fraction;
  }

  /// Values at merged ranks [ra] ≤ [rb] (0 = smallest, or largest when
  /// [descending]) of the union of ascending [lists].
  static (double, double) _ranks(
    List<List<double>> lists,
    int ra,
    int rb, {
    required bool descending,
  }) {
    final m = lists.length;
    final key = Float64List(m);
    final who = Int32List(m);
    final cur = Int32List(m);
    var size = 0;
    for (var li = 0; li < m; li++) {
      final l = lists[li];
      if (l.isEmpty) continue;
      cur[li] = descending ? l.length - 1 : 0;
      final k = descending ? -l[cur[li]] : l[cur[li]];
      var i = size++;
      while (i > 0) {
        final parent = (i - 1) >> 1;
        if (key[parent] <= k) break;
        key[i] = key[parent];
        who[i] = who[parent];
        i = parent;
      }
      key[i] = k;
      who[i] = li;
    }
    var rank = 0;
    var a = 0.0;
    var b = 0.0;
    while (size > 0) {
      final li = who[0];
      final l = lists[li];
      final v = l[cur[li]];
      if (rank == ra) a = v;
      if (rank == rb) {
        b = v;
        break;
      }
      rank++;
      // Replace the root with the list's next value, or with the last entry.
      final next = cur[li] + (descending ? -1 : 1);
      double k;
      int w;
      if (next < 0 || next >= l.length) {
        size--;
        if (size == 0) break;
        k = key[size];
        w = who[size];
      } else {
        cur[li] = next;
        k = descending ? -l[next] : l[next];
        w = li;
      }
      var i = 0;
      while (true) {
        final c1 = 2 * i + 1;
        if (c1 >= size) break;
        final c2 = c1 + 1;
        final c = (c2 < size && key[c2] < key[c1]) ? c2 : c1;
        if (key[c] >= k) break;
        key[i] = key[c];
        who[i] = who[c];
        i = c;
      }
      key[i] = k;
      who[i] = w;
    }
    return (a, b);
  }
}

/// [ours] Student's t distribution (journal insights): two-sided p-value
/// and quantiles, via the regularised incomplete beta function (Numerical
/// Recipes §6.4 continued fraction). Accurate to ~1e-10 for df ≥ 1.
abstract final class StudentT {
  /// P(|T| ≥ |t|) for [df] degrees of freedom.
  static double twoSidedP(double t, double df) {
    if (!t.isFinite) return 0;
    if (!(df > 0)) return 1;
    final x = df / (df + t * t);
    return Stats.clamp(_betai(df / 2, 0.5, x), 0, 1);
  }

  /// The value q with P(T ≤ q) = [p] (0 < p < 1), by bisection.
  static double quantile(double p, double df) {
    if (!(p > 0 && p < 1)) return double.nan;
    if (p == 0.5) return 0;
    final upper = p > 0.5;
    final tail = upper ? 1 - p : p; // one-sided tail
    var lo = 0.0, hi = 1.0;
    while (twoSidedP(hi, df) / 2 > tail && hi < 1e6) {
      hi *= 2;
    }
    for (var i = 0; i < 200; i++) {
      final mid = (lo + hi) / 2;
      if (twoSidedP(mid, df) / 2 > tail) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final q = (lo + hi) / 2;
    return upper ? q : -q;
  }

  static double _betai(double a, double b, double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    final lbt =
        _lgamma(a + b) -
        _lgamma(a) -
        _lgamma(b) +
        a * math.log(x) +
        b * math.log(1 - x);
    final bt = math.exp(lbt);
    if (x < (a + 1) / (a + b + 2)) return bt * _betacf(a, b, x) / a;
    return 1 - bt * _betacf(b, a, 1 - x) / b;
  }

  static double _betacf(double a, double b, double x) {
    const maxIt = 300, eps = 3e-14, fpMin = 1e-300;
    final qab = a + b, qap = a + 1, qam = a - 1;
    var c = 1.0;
    var d = 1 - qab * x / qap;
    if (d.abs() < fpMin) d = fpMin;
    d = 1 / d;
    var h = d;
    for (var m = 1; m <= maxIt; m++) {
      final m2 = 2 * m;
      var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
      d = 1 + aa * d;
      if (d.abs() < fpMin) d = fpMin;
      c = 1 + aa / c;
      if (c.abs() < fpMin) c = fpMin;
      d = 1 / d;
      h *= d * c;
      aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
      d = 1 + aa * d;
      if (d.abs() < fpMin) d = fpMin;
      c = 1 + aa / c;
      if (c.abs() < fpMin) c = fpMin;
      d = 1 / d;
      final del = d * c;
      h *= del;
      if ((del - 1).abs() < eps) break;
    }
    return h;
  }

  /// Lanczos log-gamma (g = 7, n = 9).
  static double _lgamma(double x) {
    const g = 7.0;
    const c = [
      0.99999999999980993,
      676.5203681218851,
      -1259.1392167224028,
      771.32342877765313,
      -176.61502916214059,
      12.507343278686905,
      -0.13857109526572012,
      9.9843695780195716e-6,
      1.5056327351493116e-7,
    ];
    if (x < 0.5) {
      return math.log(math.pi / math.sin(math.pi * x).abs()) - _lgamma(1 - x);
    }
    final xx = x - 1;
    var a = c[0];
    final t = xx + g + 0.5;
    for (var i = 1; i < 9; i++) {
      a += c[i] / (xx + i);
    }
    return 0.5 * math.log(2 * math.pi) +
        (xx + 0.5) * math.log(t) -
        t +
        math.log(a);
  }
}

extension on (double, double) {
  (double, double) get swap => ($2, $1);
}

/// [ours] Null unless [x] is a finite number.
double? finiteOrNull(double? x) => (x == null || !x.isFinite) ? null : x;

/// [ours] [x] if finite, else [fallback].
double finiteOr(double x, double fallback) => x.isFinite ? x : fallback;
