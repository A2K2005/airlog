// Sparkline — a word-sized trend (Tufte). The one chart without printed
// axes, by design: it sits beside a number that already states the value, and
// its spoken summary carries latest / range / direction. Never use it where a
// reader is meant to read a value off the picture — use a ChartFrame chart.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'axis.dart';

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 28,
    this.width,
    this.lower,
    this.upper,
    this.showLast = true,
    this.semanticsLabel,
    this.format = axisFixedOrInt,
  });

  /// DENSE, oldest first, null in gaps.
  final List<double?> values;

  /// Pigment (solved internally).
  final Color color;
  final double height;
  final double? width;

  /// Optional baseline band drawn as a faint strip. Either edge may be null
  /// on its own (a one-sided band, e.g. the SpO₂ floor): the strip then runs
  /// from the bound to the open edge.
  final double? lower, upper;
  final bool showLast;
  final String? semanticsLabel;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final label =
        semanticsLabel ??
        (denseSummary(values, format: format) ?? 'No readings yet');
    return Semantics(
      label: 'Trend. $label',
      child: SizedBox(
        height: height,
        width: width,
        child: CustomPaint(
          size: Size.infinite,
          painter: SparklinePainter(
            values: values,
            color: p.mark(color),
            band: p.wash(color, strength: .7),
            knockout: p.card,
            lower: lower,
            upper: upper,
            showLast: showLast,
          ),
        ),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  SparklinePainter({
    required this.values,
    required this.color,
    required this.band,
    required this.knockout,
    this.lower,
    this.upper,
    this.showLast = true,
  });

  final List<double?> values;
  final Color color, band, knockout;
  final double? lower, upper;
  final bool showLast;

  @override
  void paint(Canvas cv, Size s) {
    if (values.isEmpty || s.width <= 0 || s.height <= 0) return;
    final lo = lower != null && lower!.isFinite ? lower : null;
    final up = upper != null && upper!.isFinite ? upper : null;
    final e = autoExtent([...values, ?lo, ?up]);
    if (e == null) return;
    const pad = 3.5;
    final h = s.height - pad * 2;
    final w = s.width - pad * 2;
    double y(double v) => pad + h - (v - e.min) / e.range * h;
    if (lo != null || up != null) {
      // Open side runs to the plot edge; a one-sided band keeps a firm edge.
      final a = up == null ? 0.0 : y(up), b = lo == null ? s.height : y(lo);
      cv.drawRect(
        Rect.fromLTRB(0, a, s.width, b < a + 1 ? a + 1 : b),
        Paint()..color = band,
      );
      if (lo == null || up == null) {
        final edge = lo == null ? a : b;
        cv.drawLine(
          Offset(0, edge),
          Offset(s.width, edge),
          Paint()
            ..color = color.withValues(alpha: .5)
            ..strokeWidth = 1,
        );
      }
    }
    final runs = minMaxRuns(values, w, y);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    Offset? last;
    for (final run in runs) {
      final pts = [for (final o in run) o.translate(pad, 0)];
      last = pts.last;
      if (pts.length == 1) {
        cv.drawCircle(pts.first, 1.6, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      cv.drawPath(path, stroke);
    }
    // Only mark the head when the newest slot really is a reading.
    final tail = values.last;
    if (showLast && last != null && tail != null && tail.isFinite) {
      cv.drawCircle(last, 3.2, Paint()..color = knockout);
      cv.drawCircle(last, 2.4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant SparklinePainter o) =>
      o.values != values ||
      o.color != color ||
      o.lower != lower ||
      o.upper != upper;
}
