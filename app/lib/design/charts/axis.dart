// Adapted from OpenStrap/edge lib/ui2/charts.dart (MIT, see third_party/edge/LICENSE).
// Changes: split out of the painter file; `axisClock` for time-of-day axes;
// `finiteOnly` / `denseSummary` helpers shared by every chart's spoken
// summary; otherwise AxisSpec and the down-sampling helpers are unchanged.
//
// Rules carried over from Edge, and not negotiable:
//   1. NOTHING HERE INVENTS DATA. A painter given an empty series draws nothing.
//   2. A CHART WITHOUT AN AXIS IS A SHAPE. The same AxisSpec goes to the frame
//      that labels it and the painter that draws against it.
//   3. A GAP IS A GAP. `null` or non-finite breaks the line; x is the INDEX, so
//      callers hand over DENSE series (one slot per day/minute, null in holes).
//   4. LONG SERIES ARE DOWN-SAMPLED to ≤ 2 points per pixel (min + max), so
//      spikes survive and a 30 000-point night costs what 700 points do.

import 'dart:math';

import 'package:flutter/painting.dart';

/// Reduce [d] to at most two points per horizontal pixel: each column's
/// minimum and maximum, in time order. Short series come back untouched.
List<Offset> minMaxColumns(
  List<double> d,
  double width,
  double Function(double value) y,
) {
  final n = d.length;
  if (n == 0 || width <= 0) return const [];
  if (n == 1) return [Offset(0, y(d[0]))];

  double x(int i) => i / (n - 1) * width;

  final cols = width.floor().clamp(1, n);
  if (n <= cols * 2) {
    return [for (var i = 0; i < n; i++) Offset(x(i), y(d[i]))];
  }

  final out = <Offset>[];
  for (var c = 0; c < cols; c++) {
    final lo = (c * n / cols).floor();
    final hi = ((c + 1) * n / cols).ceil().clamp(lo + 1, n);
    var loI = lo, hiI = lo;
    for (var i = lo + 1; i < hi; i++) {
      if (d[i] < d[loI]) loI = i;
      if (d[i] > d[hiI]) hiI = i;
    }
    final first = loI < hiI ? loI : hiI;
    final second = loI < hiI ? hiI : loI;
    out.add(Offset(x(first), y(d[first])));
    if (second != first) out.add(Offset(x(second), y(d[second])));
  }
  return out;
}

/// [minMaxColumns] for a series with holes: one run of points per unbroken
/// stretch, x measured across the WHOLE series so gaps keep their width.
/// A run of one is an isolated sample; painters draw it as a dot.
List<List<Offset>> minMaxRuns(
  List<double?> d,
  double width,
  double Function(double value) y,
) {
  final n = d.length;
  if (n == 0 || width <= 0) return const [];
  bool real(int i) {
    final v = d[i];
    return v != null && v.isFinite;
  }

  final runs = <List<Offset>>[];
  var i = 0;
  while (i < n) {
    if (!real(i)) {
      i++;
      continue;
    }
    var j = i;
    while (j < n && real(j)) {
      j++;
    }
    final x0 = n == 1 ? width / 2 : i / (n - 1) * width;
    if (j - i == 1) {
      runs.add([Offset(x0, y(d[i]!))]);
    } else {
      final w = (j - i - 1) / (n - 1) * width;
      final seg = [for (var k = i; k < j; k++) d[k]!];
      runs.add([
        for (final o in minMaxColumns(seg, w, y)) Offset(x0 + o.dx, o.dy),
      ]);
    }
    i = j;
  }
  return runs;
}

/// Column maxima for bar charts (a PEAK per column — right for rates).
List<double> maxColumns(List<double> d, int cols) {
  final n = d.length;
  if (n == 0 || cols <= 0 || n <= cols) return d;
  return [
    for (var c = 0; c < cols; c++)
      d
          .sublist(
            (c * n / cols).floor(),
            ((c + 1) * n / cols).ceil().clamp((c * n / cols).floor() + 1, n),
          )
          .reduce(max),
  ];
}

/// The finite values of [d], in order.
List<double> finiteOnly(Iterable<double?> d) => [
  for (final v in d)
    if (v != null && v.isFinite) v,
];

/// ── THE Y AXIS ────────────────────────────────────────────────────────────
///
/// Shared by the painter that draws the curve and the frame that prints the
/// numbers beside it. Passing it to only one of the two is the bug it exists
/// to prevent.
class AxisSpec {
  final double min, max;

  /// Gridline count, INCLUDING both ends.
  final int ticks;

  final String Function(double) format;

  const AxisSpec({
    required this.min,
    required this.max,
    this.ticks = 3,
    required this.format,
  });

  /// 0 at [min], 1 at [max], clamped (and 0 for a non-finite value).
  double t(double v) {
    if (!v.isFinite || max - min <= 0) return 0;
    return ((v - min) / (max - min)).clamp(0.0, 1.0);
  }

  /// Tick values, top first.
  List<double> get tickValues {
    final n = ticks < 2 ? 2 : ticks;
    return [for (var i = 0; i < n; i++) max - (max - min) * i / (n - 1)];
  }

  /// An axis over real data rounded out to steps a human would choose.
  /// Null for a series with nothing finite in it — the signal to render the
  /// frame's empty state instead of an empty axis.
  static AxisSpec? of(
    Iterable<double?> d, {
    int ticks = 3,
    String Function(double) format = axisInt,
    double? floor,
    double? ceil,
    double? step,
  }) {
    final v = finiteOnly(d);
    if (v.isEmpty) return null;
    final n = ticks < 2 ? 2 : ticks;
    var lo = v.reduce((a, b) => a < b ? a : b),
        hi = v.reduce((a, b) => a > b ? a : b);
    if (floor != null && floor.isFinite && floor < lo) lo = floor;
    if (ceil != null && ceil.isFinite && ceil > hi) hi = ceil;
    if (hi - lo < 1e-9) {
      if (hi.abs() < 1e-9) {
        lo = 0;
        hi = 1;
      } else {
        final pad = hi.abs() * .1;
        lo -= pad;
        hi += pad;
      }
    }
    var s = step != null && step > 0 && step.isFinite
        ? step
        : _niceStep((hi - lo) / (n - 1));
    final q = _labelStep(format);
    for (var i = 0; i < 8 && q > 0 && !_multiple(s, q); i++) {
      s = _niceStep(s * 1.0001);
    }
    final base = (lo / s).floorToDouble() * s;
    var grow = ((hi - base) / s - 1e-9).ceil();
    final gap = n - 1;
    if (grow < gap) grow = gap;
    grow = ((grow + gap - 1) ~/ gap) * gap;
    return AxisSpec(min: base, max: base + grow * s, ticks: n, format: format);
  }

  static bool _multiple(double a, double b) =>
      ((a / b) - (a / b).roundToDouble()).abs() < 1e-9;

  static double _labelStep(String Function(double) f) =>
      f == axisInt || f == axisHm
      ? 1
      : (f == axisFixed || f == axisFixedOrInt ? .1 : 0);

  static double _niceStep(double raw) {
    if (raw <= 0 || !raw.isFinite) return 1;
    final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 2.5, 5.0]) {
      if (raw <= m * mag) return m * mag;
    }
    return 10 * mag;
  }

  @override
  bool operator ==(Object other) =>
      other is AxisSpec &&
      other.min == min &&
      other.max == max &&
      other.ticks == ticks &&
      other.format == format;

  @override
  int get hashCode => Object.hash(min, max, ticks, format);
}

/// `56`, `-3`. The default.
String axisInt(double v) => v.isFinite ? v.round().toString() : '';

/// `7h 30m`, `45m`, `8h` — an axis measured in MINUTES.
String axisHm(double minutes) {
  if (!minutes.isFinite) return '';
  final t = minutes.round(), h = t ~/ 60, m = t % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// One decimal: skin temperature, strain, ACWR.
String axisFixed(double v) => v.isFinite ? v.toStringAsFixed(1) : '';

/// [axisInt] when whole, [axisFixed] otherwise (spoken summaries).
String axisFixedOrInt(double v) =>
    (v - v.roundToDouble()).abs() < .05 ? axisInt(v) : axisFixed(v);

/// 24 h clock for a value in minutes since local midnight (wraps): `23:30`.
String clockHm(double minutesOfDay) {
  if (!minutesOfDay.isFinite) return '';
  final t = minutesOfDay.round() % 1440;
  final m = t < 0 ? t + 1440 : t;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// `HH:mm` of a DateTime (local).
String clockOf(DateTime t) => clockHm((t.hour * 60 + t.minute).toDouble());

/// An axis tick the way the phone is set: `23:00` (24-hour), or `11 pm`
/// (12-hour, minutes only when they aren't :00) so five ticks still fit.
String axisClock(double minutesOfDay, {required bool use24h}) {
  if (use24h) return clockHm(minutesOfDay);
  if (!minutesOfDay.isFinite) return '';
  final t = (minutesOfDay.round() % 1440 + 1440) % 1440;
  final h = t ~/ 60, m = t % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final mm = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
  return '$h12$mm ${h < 12 ? 'am' : 'pm'}';
}

/// [axisClock] of a DateTime (local).
String axisClockOf(DateTime t, {required bool use24h}) =>
    axisClock((t.hour * 60 + t.minute).toDouble(), use24h: use24h);

/// The axis-less fallback extent, shared by every painter that has one.
({double min, double range})? autoExtent(List<double?> d) {
  double? mn, mx;
  for (final v in d) {
    if (v == null || !v.isFinite) continue;
    if (mn == null || v < mn) mn = v;
    if (mx == null || v > mx) mx = v;
  }
  if (mn == null) return null;
  if ((mx! - mn).abs() >= 1e-6) return (min: mn, range: mx - mn);
  if (mn.abs() < 1e-9) return (min: 0.0, range: 1.0);
  final pad = mn.abs() * .1;
  return (min: mn - pad, range: pad * 2);
}

/// A one-sentence spoken summary of a dense series: latest, range, direction.
/// Null when nothing finite is in it. Shared so every chart speaks alike.
String? denseSummary(
  List<double?> series, {
  String Function(double)? format,
  String unit = '',
}) {
  final v = finiteOnly(series);
  if (v.isEmpty) return null;
  final fmt = format ?? axisFixedOrInt;
  final u = unit.isEmpty ? '' : ' $unit';
  var lo = v.first, hi = v.first;
  for (final x in v) {
    if (x < lo) lo = x;
    if (x > hi) hi = x;
  }
  final parts = ['Latest ${fmt(v.last)}$u'];
  if (v.length > 1) {
    if (hi > lo) parts.add('ranging ${fmt(lo)} to ${fmt(hi)}');
    final delta = v.last - v.first;
    final noise = (hi - lo) / 20;
    parts.add(
      delta.abs() <= noise
          ? 'roughly level across ${v.length} readings'
          : '${delta > 0 ? 'up' : 'down'} ${fmt(delta.abs())} '
                'across ${v.length} readings',
    );
  }
  return parts.join(', ');
}
