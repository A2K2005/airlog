// BaselineBandChart — a metric over time inside the user's personal band.
//
// The chart the product is built around (PRODUCT_PLAN §2.4: "a shaded
// personal-baseline band with today's value plotted inside it"). The band and
// the mean come from the domain (Baseline / HealthMetricStatus lower–upper);
// this widget never computes a baseline of its own.
//
// The band may be ONE-SIDED: SpO₂ has only a floor (lower, no upper), so the
// shade runs from the floor to the top of the plot and fades out towards the
// open side, with a solid edge where the bound is.

import 'dart:math';

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'axis.dart';
import 'frame.dart';

class BaselineBandChart extends StatelessWidget {
  const BaselineBandChart({
    super.key,
    required this.title,
    required this.unit,
    required this.values,
    required this.color,
    this.mean,
    this.lower,
    this.upper,
    this.highlightIndex,
    this.xLabels = const [],
    this.axis,
    this.format = axisInt,
    this.height = 132,
    this.footnote,
    this.semanticsLabel,
    this.emptyMessage = 'Not enough nights yet',
    this.trailing,
    this.showUnit = true,
    this.xMarks = const [],
  });

  final String title;
  final String unit;

  /// DENSE, oldest first, one slot per day; `null` where nothing was measured.
  /// The last slot is "today" unless [highlightIndex] says otherwise.
  final List<double?> values;

  /// Accent pigment (raw); solved for the surface internally.
  final Color color;

  /// Baseline mean and band edges in the same units as [values]. Either edge
  /// may be null on its own: a one-sided band (SpO₂ has only a floor).
  final double? mean, lower, upper;

  /// The slot drawn emphasised. Default: the last slot, if it has a value.
  final int? highlightIndex;
  final List<String> xLabels;

  /// Pin a scale; otherwise one is derived from values + band.
  final AxisSpec? axis;
  final String Function(double) format;
  final double height;

  /// Default: "Band: your usual range {lower}–{upper} {unit}" (or "at or
  /// above {lower}" for a one-sided band).
  final String? footnote;
  final String? semanticsLabel;
  final String emptyMessage;
  final Widget? trailing;

  /// See [ChartFrame.showUnit]: false when [trailing] already prints it.
  final bool showUnit;

  /// Dotted vertical marks (e.g. a change of source), as fractions 0…1 of the
  /// series span: slot i of n is `i / (n − 1)`. Drawn on the data's own x
  /// positions. Explain them in [footnote].
  final List<double> xMarks;

  static bool _ok(double? v) => v != null && v.isFinite;

  bool get _hasLower => _ok(lower);
  bool get _hasUpper => _ok(upper);
  bool get _hasBand => _hasLower || _hasUpper;

  /// "52–58", "at or above 94", "at or below 3".
  String _range() {
    if (_hasLower && _hasUpper) return '${format(lower!)}–${format(upper!)}';
    if (_hasLower) return 'at or above ${format(lower!)}';
    return 'at or below ${format(upper!)}';
  }

  String _spokenRange() {
    if (_hasLower && _hasUpper) {
      return 'usual range ${format(lower!)} to ${format(upper!)}';
    }
    return 'usual range ${_range()}';
  }

  String _spoken() {
    if (semanticsLabel != null) return semanticsLabel!;
    final s = denseSummary(values, format: format, unit: unit);
    final parts = <String>[
      title.isEmpty ? unit : '$title, $unit',
      if (s != null) s else emptyMessage,
      if (_hasBand) _spokenRange(),
    ];
    final hi = _highlight();
    if (hi != null && _hasBand) {
      final v = values[hi]!;
      parts.add(
        _hasUpper && v > upper!
            ? 'latest is above the usual range'
            : _hasLower && v < lower!
            ? 'latest is below the usual range'
            : 'latest is inside the usual range',
      );
    }
    return parts.join('. ');
  }

  int? _highlight() {
    final i = highlightIndex ?? values.length - 1;
    if (i < 0 || i >= values.length) return null;
    final v = values[i];
    return v != null && v.isFinite ? i : null;
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final pts = finiteOnly(values);
    final a =
        axis ??
        AxisSpec.of([
          ...pts,
          if (_hasLower) lower,
          if (_hasUpper) upper,
          if (mean != null && pts.isNotEmpty) mean,
        ], format: format);
    final empty = pts.isEmpty || a == null;
    return ChartFrame(
      title: title,
      unit: unit,
      showUnit: showUnit,
      height: height,
      yAxis: empty ? null : a,
      xLabels: xLabels,
      series: values,
      trailing: trailing,
      semanticsLabel: _spoken(),
      footnote:
          footnote ??
          (_hasBand && !empty
              ? 'Shaded: your usual range, ${_range()} $unit'
              : null),
      empty: empty ? NoData(message: emptyMessage) : null,
      child: empty
          ? const SizedBox.shrink()
          : CustomPaint(
              size: Size.infinite,
              painter: BaselineBandPainter(
                values: values,
                axis: a,
                line: p.mark(color),
                band: p.wash(color, strength: .9),
                bandEdge: p.mark(color).withValues(alpha: .55),
                meanInk: p.ink3,
                markInk: p.ink3,
                knockout: p.card,
                lower: _hasLower ? lower : null,
                upper: _hasUpper ? upper : null,
                mean: mean,
                highlight: _highlight(),
                marks: xMarks,
              ),
            ),
    );
  }
}

/// Painter behind [BaselineBandChart]: band → mean → marks → line → dots →
/// today.
class BaselineBandPainter extends CustomPainter {
  BaselineBandPainter({
    required this.values,
    required this.axis,
    required this.line,
    required this.band,
    required this.meanInk,
    required this.knockout,
    Color? bandEdge,
    Color? markInk,
    this.lower,
    this.upper,
    this.mean,
    this.highlight,
    this.marks = const [],
  }) : bandEdge = bandEdge ?? line,
       markInk = markInk ?? meanInk;

  final List<double?> values;
  final AxisSpec axis;
  final Color line, band, meanInk, knockout, bandEdge, markInk;
  final double? lower, upper, mean;
  final int? highlight;

  /// 0…1 of the series span (see [BaselineBandChart.xMarks]).
  final List<double> marks;

  /// Inset so the emphasised dot at either end is not clipped.
  static const inset = 6.0;

  @override
  void paint(Canvas cv, Size s) {
    if (values.isEmpty || s.width <= 0 || s.height <= 0) return;
    double y(double v) => s.height - axis.t(v) * s.height;
    final n = values.length;
    final w = max(s.width - inset * 2, 1.0);
    double xf(double f) => n == 1 ? s.width / 2 : inset + f * w;
    double x(int i) => n == 1 ? s.width / 2 : xf(i / (n - 1));

    final lo = lower, up = upper;
    if (lo != null && up != null) {
      final top = y(max(lo, up)), bottom = y(min(lo, up));
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, top, s.width, max(bottom, top + 1)),
          R.bar,
        ),
        Paint()..color = band,
      );
    } else if (lo != null || up != null) {
      // One-sided: shade from the bound to the open edge, fading out, and
      // draw the bound itself as a solid edge.
      final edge = y(lo ?? up!).clamp(0.0, s.height);
      final rect = lo != null
          ? Rect.fromLTRB(0, 0, s.width, max(edge, 1))
          : Rect.fromLTRB(0, min(edge, s.height - 1), s.width, s.height);
      final open = band.withValues(alpha: band.a * .2);
      cv.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: lo != null ? Alignment.bottomCenter : Alignment.topCenter,
            end: lo != null ? Alignment.topCenter : Alignment.bottomCenter,
            colors: [band, open],
          ).createShader(rect),
      );
      cv.drawLine(
        Offset(0, edge),
        Offset(s.width, edge),
        Paint()
          ..color = bandEdge
          ..strokeWidth = 1.2,
      );
    }
    final m = mean;
    if (m != null && m.isFinite) {
      final my = y(m);
      final dash = Paint()
        ..color = meanInk
        ..strokeWidth = 1;
      for (var xx = 0.0; xx < s.width; xx += 7) {
        cv.drawLine(Offset(xx, my), Offset(min(xx + 3.5, s.width), my), dash);
      }
    }

    // Provenance marks: dotted verticals on the data's own x positions.
    if (marks.isNotEmpty) {
      final dot = Paint()
        ..color = markInk
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      for (final f in marks) {
        if (!f.isFinite) continue;
        final mx = xf(f.clamp(0.0, 1.0));
        for (var yy = 1.5; yy < s.height; yy += 5) {
          cv.drawLine(Offset(mx, yy), Offset(mx, min(yy + .5, s.height)), dot);
        }
      }
    }

    // The line, broken at gaps.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = line;
    Path? path;
    final dotPaint = Paint()..color = line;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null || !v.isFinite) {
        if (path != null) cv.drawPath(path, stroke);
        path = null;
        continue;
      }
      final o = Offset(x(i), y(v));
      if (path == null) {
        path = Path()..moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    if (path != null) cv.drawPath(path, stroke);
    // Small dots mark each real reading (and keep isolated ones visible).
    final r = n > 45 ? 1.2 : 1.8;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null || !v.isFinite || i == highlight) continue;
      cv.drawCircle(Offset(x(i), y(v)), r, dotPaint);
    }

    final h = highlight;
    if (h != null && h >= 0 && h < n) {
      final v = values[h];
      if (v != null && v.isFinite) {
        final o = Offset(x(h), y(v));
        cv.drawCircle(o, 9, Paint()..color = line.withValues(alpha: .18));
        cv.drawCircle(o, 5.5, Paint()..color = knockout);
        cv.drawCircle(o, 4, Paint()..color = line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BaselineBandPainter o) =>
      o.values != values ||
      o.axis != axis ||
      o.line != line ||
      o.band != band ||
      o.lower != lower ||
      o.upper != upper ||
      o.mean != mean ||
      o.highlight != highlight ||
      o.marks != marks;
}
