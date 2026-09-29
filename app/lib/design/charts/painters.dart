// Adapted from OpenStrap/edge lib/ui2/charts.dart (MIT, see third_party/edge/LICENSE).
// Changes: Airlog pigments via P.mark (3:1 non-text floor) instead of P.on;
// no gradient fills or gradient arcs (flat data-ink only); Hypnogram takes the
// domain's time-stamped StageSpans and positions them by TIME across the night
// (Edge used fixed epochs and its own SleepStage enum), draws `unknown` as a
// gap, and keeps awake on top; ZoneBar uses the HR-zone ramp 1–5; Poincaré,
// Spectrum and MacroRing were not ported (no RR / nutrition surfaces).
//
// Every painter here takes the data it draws and draws NOTHING for an empty or
// non-finite series. Wrap them in a ChartFrame (or use the widget charts in
// this folder) so they carry an axis, a key and a spoken summary.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/models.dart' show SleepStage, StageSpan;
import '../tokens/tokens.dart';
import 'axis.dart';

/// Smoothing is only honest below this many points.
const _kSmoothMax = 120;

Path _polyline(List<Offset> pts, {required bool smooth}) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    if (smooth) {
      final m = (a.dx + b.dx) / 2;
      p.cubicTo(m, a.dy, m, b.dy, b.dx, b.dy);
    } else {
      p.lineTo(b.dx, b.dy);
    }
  }
  return p;
}

/// Column maxima over a series with holes: a column of nothing stays nothing.
List<double?> nullableColumns(List<double?> d, int cols) {
  final n = d.length;
  if (cols <= 0 || n <= cols) return d;
  return [
    for (var c = 0; c < cols; c++)
      () {
        final lo = (c * n / cols).floor();
        final hi = ((c + 1) * n / cols).ceil().clamp(lo + 1, n);
        double? m;
        for (var i = lo; i < hi; i++) {
          final v = d[i];
          if (v == null || !v.isFinite) continue;
          if (m == null || v > m) m = v;
        }
        return m;
      }(),
  ];
}

/// The trend line. [d] is DENSE and index-ordered, `null` where nothing was
/// measured; gaps break the line. [t] is draw-in progress (pass
/// `animate(context, t)`).
class LineChart extends CustomPainter {
  final List<double?> d;
  final Color color;
  final bool dots;
  final double t;

  /// A flat wash under the line. Only drawn with an [axis] (a fill reads as a
  /// quantity from a baseline, and without an axis there is no baseline).
  final bool fill;

  /// Knockout at the centre of the head dot: pass the surface colour.
  final Color? dotInk;
  final AxisSpec? axis;
  final double strokeWidth;

  LineChart(
    this.d,
    this.color, {
    bool fill = false,
    this.dots = false,
    this.t = 1,
    this.dotInk,
    this.axis,
    this.strokeWidth = 2,
  }) : fill = fill && axis != null;

  @override
  void paint(Canvas cv, Size s) {
    if (d.isEmpty || s.width <= 0 || s.height <= 0) return;
    final a = axis;
    final e = a == null ? autoExtent(d) : null;
    if (a == null && e == null) return;
    final pad = s.height * .14;
    double y(double v) => a != null
        ? s.height - a.t(v) * s.height
        : s.height - pad - (v - e!.min) / e.range * (s.height - pad * 2);

    final runs = minMaxRuns(d, s.width, y);
    var left = runs.fold<int>(0, (n, r) => n + r.length);
    left = (left * t.clamp(0, 1)).round();
    final smooth = d.length <= _kSmoothMax;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    Offset? head;
    for (final run in runs) {
      if (left <= 0) break;
      final pts = run.length <= left ? run : run.sublist(0, left);
      left -= pts.length;
      head = pts.last;
      if (pts.length == 1) {
        cv.drawCircle(pts.first, strokeWidth, Paint()..color = color);
        continue;
      }
      final path = _polyline(pts, smooth: smooth);
      if (fill) {
        final f = Path.from(path)
          ..lineTo(pts.last.dx, s.height)
          ..lineTo(pts.first.dx, s.height)
          ..close();
        cv.drawPath(f, Paint()..color = color.withValues(alpha: .10));
      }
      cv.drawPath(path, stroke);
    }

    if (dots && head != null) {
      cv.drawCircle(head, 4.5, Paint()..color = color);
      if (dotInk != null) cv.drawCircle(head, 2, Paint()..color = dotInk!);
    }
  }

  @override
  bool shouldRepaint(covariant LineChart o) =>
      o.d != d ||
      o.t != t ||
      o.color != color ||
      o.axis != axis ||
      o.fill != fill ||
      o.dots != dots;
}

/// Discrete buckets. [d] is dense; a `null` bucket draws nothing (a hole, not
/// a zero); a real zero draws a 2 px floor. [colors] (optional, same length)
/// colours each bar individually, e.g. recovery by zone.
class Bars extends CustomPainter {
  final List<double?> d;
  final Color color;
  final List<Color>? colors;
  final int highlight;
  final double t;
  final AxisSpec? axis;

  /// Bar width as a share of its slot.
  final double widthFactor;

  Bars(
    this.d,
    this.color, {
    this.colors,
    this.highlight = -1,
    this.t = 1,
    this.axis,
    this.widthFactor = .6,
  });

  @override
  void paint(Canvas cv, Size s) {
    if (d.isEmpty || s.width <= 0 || s.height <= 0) return;
    final cols = (s.width / 3).floor().clamp(1, d.length);
    final v = nullableColumns(d, cols);
    final a = axis;
    var mx = 0.0;
    if (a == null) {
      for (final x in v) {
        if (x != null && x.isFinite && x > mx) mx = x;
      }
      if (mx <= 0) return;
    }
    final bw = s.width / v.length;
    final same = v.length == d.length;
    final hl = same ? highlight : -1;
    final wf = widthFactor.clamp(.1, 1.0);
    for (var i = 0; i < v.length; i++) {
      final value = v[i];
      if (value == null || !value.isFinite) continue;
      final h =
          (a == null ? value / mx : a.t(value)) * s.height * t.clamp(0, 1);
      if (!h.isFinite) continue;
      final bh = max(h, 2.0);
      final base = same && colors != null && i < colors!.length
          ? colors![i]
          : color;
      cv.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(i * bw + bw * (1 - wf) / 2, s.height - bh, bw * wf, bh),
          topLeft: R.bar,
          topRight: R.bar,
        ),
        Paint()
          ..color = (hl < 0 || i == hl) ? base : base.withValues(alpha: .35),
      );
    }
  }

  @override
  bool shouldRepaint(covariant Bars o) =>
      o.d != d ||
      o.t != t ||
      o.highlight != highlight ||
      o.axis != axis ||
      o.color != color ||
      o.colors != colors;
}

/// The score dial: one value 0…1, one flat arc from 12 o'clock.
class Ring extends CustomPainter {
  final double v;
  final Color color, track;
  final double stroke, t;

  Ring(this.v, this.color, this.track, {this.stroke = 10, this.t = 1});

  @override
  void paint(Canvas cv, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = min(s.width, s.height) / 2 - stroke / 2;
    if (r <= 0) return;
    cv.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    final value = v.isFinite ? v.clamp(0.0, 1.0) : 0.0;
    final sweep = 2 * pi * value * t.clamp(0, 1);
    if (sweep <= 0) return;
    cv.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant Ring o) =>
      o.v != v || o.t != t || o.color != color || o.track != track;
}

/// A ring of discrete beads: a value that is still FILLING (a baseline
/// calibrating night by night, a provisional score). "Not solid yet" is true
/// of the shape itself, not only of a softer tint.
class DashedRing extends CustomPainter {
  final double v;
  final Color color, track;
  final double stroke;
  final int segments;

  DashedRing(
    this.v,
    this.color,
    this.track, {
    this.stroke = 10,
    this.segments = 28,
  });

  @override
  void paint(Canvas cv, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = min(s.width, s.height) / 2 - stroke / 2;
    if (r <= 0 || segments <= 0) return;
    final value = v.isFinite ? v.clamp(0.0, 1.0) : 0.0;
    final filled = (segments * value).round();
    final step = 2 * pi / segments;
    // Segments with a fixed ~3.5 px gap between them (butt caps): reads as a
    // ring that is "not solid yet" without turning into a bead necklace.
    final gapAngle = min(3.5 / r, step * .5);
    final dashSweep = step - gapAngle;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < segments; i++) {
      cv.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -pi / 2 + step * i + gapAngle / 2,
        dashSweep,
        false,
        paint..color = i < filled ? color : track,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DashedRing o) =>
      o.v != v ||
      o.color != color ||
      o.track != track ||
      o.segments != segments ||
      o.stroke != stroke;
}

/// Hypnogram — four lanes top to bottom: Awake, REM, Light, Deep.
///
/// [spans] are positioned by TIME between [start] and [end] (default: the
/// first span's start and the last span's end), so a missing stretch of the
/// night is a visible gap. `SleepStage.unknown` is drawn as nothing.
class Hypnogram extends CustomPainter {
  final List<StageSpan> spans;
  final P p;
  final DateTime? start, end;
  final double t;

  Hypnogram(this.spans, this.p, {this.start, this.end, this.t = 1});

  /// Lane order, top to bottom.
  static const lanes = [
    SleepStage.awake,
    SleepStage.rem,
    SleepStage.light,
    SleepStage.deep,
  ];

  static String label(SleepStage s) => switch (s) {
    SleepStage.awake => 'Awake',
    SleepStage.rem => 'REM',
    SleepStage.light => 'Light',
    SleepStage.deep => 'Deep',
    SleepStage.unknown => 'Unknown',
  };

  /// Lane colours as drawn (solved marks).
  static Map<SleepStage, Color> cols(P p) => {
    for (final s in lanes) s: p.mark(DomainColors.sleepStage(s)),
  };

  /// Hand straight to `ChartFrame.legend`; derived from [cols].
  static List<(String, Color)> legend(P p) => [
    for (final s in lanes) (label(s), cols(p)[s]!),
  ];

  /// The time window the painter uses for [spans]; null when there is none.
  static (DateTime, DateTime)? window(
    List<StageSpan> spans, {
    DateTime? start,
    DateTime? end,
  }) {
    DateTime? a = start, b = end;
    for (final s in spans) {
      if (start == null && (a == null || s.start.isBefore(a))) a = s.start;
      if (end == null && (b == null || s.end.isAfter(b))) b = s.end;
    }
    if (a == null || b == null || !b.isAfter(a)) return null;
    return (a, b);
  }

  @override
  void paint(Canvas cv, Size s) {
    if (spans.isEmpty || s.width <= 0 || s.height <= 0) return;
    final w = window(spans, start: start, end: end);
    if (w == null) return;
    final (t0, t1) = w;
    final total = t1.difference(t0).inSeconds.toDouble();
    double x(DateTime at) =>
        (at.difference(t0).inSeconds / total).clamp(0.0, 1.0) * s.width;
    final lane = s.height / lanes.length;
    final limit = s.width * t.clamp(0.0, 1.0);
    final ink = cols(p);
    final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
    final riser = Paint()
      ..color = p.line
      ..strokeWidth = 1;

    double laneMid(int i) => i * lane + lane / 2;

    // Risers first so blocks sit on top of them.
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i], b = sorted[i + 1];
      final la = lanes.indexOf(a.stage), lb = lanes.indexOf(b.stage);
      if (la < 0 || lb < 0 || la == lb) continue;
      if (b.start.difference(a.end).inSeconds.abs() > 90) continue;
      final xx = x(b.start);
      if (xx > limit) continue;
      cv.drawLine(
        Offset(xx, laneMid(min(la, lb))),
        Offset(xx, laneMid(max(la, lb))),
        riser,
      );
    }

    // Awake last: the shortest events are the ones worth keeping on top.
    for (final pass in [false, true]) {
      for (final sp in sorted) {
        final li = lanes.indexOf(sp.stage);
        if (li < 0) continue;
        if ((sp.stage == SleepStage.awake) != pass) continue;
        final x0 = x(sp.start);
        if (x0 > limit) continue;
        final x1 = min(x(sp.end), limit);
        final bw = max(x1 - x0, 1.5);
        final y = li * lane + lane * .18, h = lane * .64;
        cv.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x0, y, bw, h), R.bar),
          Paint()..color = ink[sp.stage]!,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant Hypnogram o) =>
      o.t != t ||
      o.spans != spans ||
      o.p.dark != p.dark ||
      o.start != start ||
      o.end != end;
}

/// Time-in-zone as one stacked bar. [z] is five fractions (zones 1–5)
/// summing to ≤ 1. Bands also step up in height so the ordinal survives
/// colour-vision deficiency (adjacent zone hues can be close).
class ZoneBar extends CustomPainter {
  final List<double> z;
  final P p;

  ZoneBar(this.z, this.p);

  static List<Color> cols(P p) => [
    for (var i = 1; i <= 5; i++) p.mark(DomainColors.hrZone(i)),
  ];

  static List<(String, Color)> legend(P p) => [
    for (var i = 0; i < 5; i++) ('Zone ${i + 1}', cols(p)[i]),
  ];

  static const _floor = .6;

  @override
  void paint(Canvas cv, Size s) {
    if (s.width <= 0 || s.height <= 0) return;
    var x = 0.0;
    final ink = cols(p);
    const n = 5;
    for (var i = 0; i < z.length && i < n; i++) {
      final f = z[i];
      if (!f.isFinite || f <= 0) continue;
      final w = f.clamp(0.0, 1.0) * s.width;
      x += w;
      if (w <= .5) continue;
      final h = s.height * (_floor + (1 - _floor) * i / (n - 1));
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - w, s.height - h, max(w - 2, 1), h),
          R.bar,
        ),
        Paint()..color = ink[i],
      );
    }
  }

  @override
  bool shouldRepaint(covariant ZoneBar o) => o.z != z || o.p.dark != p.dark;
}

/// Actogram — hour of day (rows, 0 at the bottom) × date (columns).
/// [days]: one 24-slot 0…1 list per day, null where nothing was recorded.
class Actogram extends CustomPainter {
  final List<List<double>?> days;
  final Color color;

  Actogram(this.days, this.color);

  @override
  void paint(Canvas cv, Size s) {
    if (days.isEmpty || s.width <= 0 || s.height <= 0) return;
    final cw = s.width / days.length, ch = s.height / 24;
    for (var d = 0; d < days.length; d++) {
      final day = days[d];
      if (day == null) continue;
      for (var h = 0; h < 24 && h < day.length; h++) {
        final raw = day[h];
        if (!(raw > 0)) continue; // NaN fails this too
        final v = raw.clamp(0.0, 1.0);
        cv.drawRect(
          Rect.fromLTWH(d * cw, s.height - (h + 1) * ch, cw + .4, ch),
          Paint()..color = color.withValues(alpha: .22 + v * .68),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant Actogram o) =>
      o.days != days || o.color != color;
}

/// Column-major grid; null = no data, drawn as an OUTLINE (a shape
/// difference), never as a faint fill that reads like a low value.
class HeatMap extends CustomPainter {
  final List<List<double?>> weeks;
  final Color color, track;

  HeatMap(this.weeks, this.color, this.track);

  @override
  void paint(Canvas cv, Size s) {
    if (weeks.isEmpty || s.width <= 0 || s.height <= 0) return;
    var rows = 0;
    for (final w in weeks) {
      if (w.length > rows) rows = w.length;
    }
    if (rows == 0) return;
    final cw = s.width / weeks.length, ch = s.height / rows;
    for (var w = 0; w < weeks.length; w++) {
      for (var d = 0; d < weeks[w].length; d++) {
        final v = weeks[w][d];
        final empty = v == null || !v.isFinite;
        cv.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              w * cw + 1,
              d * ch + 1,
              max(cw - 2.5, .5),
              max(ch - 2.5, .5),
            ),
            R.bar,
          ),
          empty
              ? (Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1
                  ..color = track)
              : (Paint()
                  ..color = color.withValues(
                    alpha: .3 + v.clamp(0.0, 1.0) * .62,
                  )),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant HeatMap o) =>
      o.weeks != weeks || o.color != color;
}

/// Several signals stacked over ONE shared timeline; each lane independently
/// scaled (different units). Every lane must be the same length (index i is
/// the same instant in all of them); a lane of another length is not drawn.
class NightStack extends CustomPainter {
  final List<List<double?>> series;
  final List<Color> colors;
  final List<AxisSpec?>? axes;

  NightStack(this.series, this.colors, {this.axes});

  @override
  void paint(Canvas cv, Size s) {
    if (series.isEmpty || colors.isEmpty || s.width <= 0 || s.height <= 0) {
      return;
    }
    final span = series.fold<int>(0, (n, l) => l.length > n ? l.length : n);
    final h = s.height / series.length;
    for (var k = 0; k < series.length; k++) {
      final d = series[k];
      if (d.length != span || d.length < 2) continue;
      final a = (axes != null && k < axes!.length) ? axes![k] : null;
      final e = a == null ? autoExtent(d) : null;
      if (a == null && e == null) continue;
      double y(double v) => a != null
          ? k * h + h - 6 - a.t(v) * max(h - 14, 1)
          : k * h + h - 6 - (v - e!.min) / e.range * max(h - 14, 1);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = colors[k % colors.length];
      for (final run in minMaxRuns(d, s.width, y)) {
        if (run.length == 1) {
          cv.drawCircle(run.first, 1.2, Paint()..color = paint.color);
          continue;
        }
        cv.drawPath(_polyline(run, smooth: false), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant NightStack o) =>
      o.series != series || o.axes != axes || o.colors != colors;
}

/// The context behind a day's curve: gaps (nothing recorded), rest (asleep),
/// workouts (a block on the top edge) and a movement strip. Positions are
/// FRACTIONS of the plot's x range, so it shares the curve's time base.
class DayLanes extends CustomPainter {
  final List<(double, double)> gaps;
  final List<(double, double, Color)> rest;
  final List<(double, double, Color)> work;
  final List<double?> movement;
  final P p;

  DayLanes({
    required this.p,
    this.gaps = const [],
    this.rest = const [],
    this.work = const [],
    this.movement = const [],
  });

  static const _strip = 16.0, _block = 5.0;

  @override
  void paint(Canvas cv, Size s) {
    if (s.width <= 0 || s.height <= 0) return;
    double x(double f) => (f.isFinite ? f.clamp(0.0, 1.0) : 0.0) * s.width;

    for (final (a, b) in gaps) {
      final l = x(a), r = x(b);
      if (r - l < .5) continue;
      cv.drawRect(Rect.fromLTRB(l, 0, r, s.height), Paint()..color = p.card2);
    }
    for (final (a, b, col) in rest) {
      final l = x(a), r = x(b);
      if (r - l < .5) continue;
      cv.drawRect(
        Rect.fromLTRB(l, 0, r, s.height),
        Paint()..color = col.withValues(alpha: p.dark ? .16 : .11),
      );
    }

    if (movement.isNotEmpty) {
      final v = nullableColumns(
        movement,
        (s.width / 2.5).floor().clamp(1, movement.length),
      );
      final cw = s.width / v.length;
      final ink = p.mark(DomainColors.strain);
      final watched = Paint()..color = ink.withValues(alpha: .40);
      for (var i = 0; i < v.length; i++) {
        final m = v[i];
        if (m == null || !m.isFinite) continue;
        cv.drawRect(Rect.fromLTWH(i * cw, s.height - 1, cw + .5, 1), watched);
        final h = m.clamp(0.0, 1.0) * _strip;
        if (h <= 0) continue;
        cv.drawRect(
          Rect.fromLTWH(i * cw, s.height - h, max(cw - .5, 1), h),
          Paint()..color = ink,
        );
      }
    }

    for (final (a, b, col) in work) {
      final l = x(a), r = x(b);
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(l, 0, max(r - l, 2), _block),
          R.bar,
        ),
        Paint()..color = col,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DayLanes o) =>
      o.gaps != gaps ||
      o.rest != rest ||
      o.work != work ||
      o.movement != movement ||
      o.p.dark != p.dark;
}
