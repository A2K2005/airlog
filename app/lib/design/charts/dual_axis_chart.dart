// DualAxisChart — bars on the left axis, a line on the right axis, one time
// base. Built for Recovery (bars, %, coloured by zone) against Strain (line,
// 0–21), where a shared axis would be a lie: they are different units.
//
// Both scales are fixed by the caller (0–100 and 0–21 for the factory), so
// the picture of a quiet week can never rescale itself into a dramatic one.

import 'dart:math';

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'axis.dart';
import 'frame.dart';
import 'painters.dart';

class DualAxisChart extends StatelessWidget {
  const DualAxisChart({
    super.key,
    required this.title,
    required this.bars,
    required this.line,
    required this.barAxis,
    required this.lineAxis,
    required this.barLabel,
    required this.lineLabel,
    required this.barUnit,
    required this.lineUnit,
    required this.barColor,
    required this.lineColor,
    this.barColorOf,
    this.xLabels = const [],
    this.height = 150,
    this.semanticsLabel,
    this.emptyMessage = 'Nothing recorded in this period',
  });

  /// Recovery (bars, 0–100 %, coloured by zone) vs Strain (line, 0–21).
  factory DualAxisChart.recoveryStrain({
    Key? key,
    required List<double?> recovery,
    required List<double?> strain,
    List<String> xLabels = const [],
    double height = 150,
    String? semanticsLabel,
  }) => DualAxisChart(
    key: key,
    title: 'Recovery and strain',
    bars: recovery,
    line: strain,
    // Four gridlines: 0 / 33 / 67 / 100 sit on the recovery zone edges and
    // 0 / 7 / 14 / 21 are whole strain numbers on the same lines.
    barAxis: const AxisSpec(min: 0, max: 100, ticks: 4, format: axisInt),
    lineAxis: const AxisSpec(min: 0, max: 21, ticks: 4, format: _strainTick),
    barLabel: 'Recovery',
    lineLabel: 'Strain',
    barUnit: '%',
    lineUnit: 'strain',
    barColor: DomainColors.recovery(67),
    barColorOf: DomainColors.recovery,
    lineColor: DomainColors.strain,
    xLabels: xLabels,
    height: height,
    semanticsLabel: semanticsLabel,
  );

  static String _strainTick(double v) => (v - v.roundToDouble()).abs() < .05
      ? '${v.round()}'
      : v.toStringAsFixed(1);

  final String title;
  final List<double?> bars, line;
  final AxisSpec barAxis, lineAxis;
  final String barLabel, lineLabel, barUnit, lineUnit;

  /// Pigments (solved internally).
  final Color barColor, lineColor;

  /// Optional per-bar pigment from its value (e.g. recovery zone).
  final Color Function(double value)? barColorOf;
  final List<String> xLabels;
  final double height;
  final String? semanticsLabel;
  final String emptyMessage;

  String _spoken() {
    if (semanticsLabel != null) return semanticsLabel!;
    final b = denseSummary(bars, format: barAxis.format, unit: barUnit);
    final l = denseSummary(line, format: lineAxis.format);
    return [
      title,
      if (b != null) '$barLabel: $b' else '$barLabel: no readings',
      if (l != null) '$lineLabel: $l' else '$lineLabel: no readings',
      if (xLabels.length > 1) 'from ${xLabels.first} to ${xLabels.last}',
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final empty = finiteOnly(bars).isEmpty && finiteOnly(line).isEmpty;
    final n = max(bars.length, line.length);
    final barInks = barColorOf == null
        ? null
        : [
            for (var i = 0; i < n; i++)
              i < bars.length && bars[i] != null && bars[i]!.isFinite
                  ? p.mark(barColorOf!(bars[i]!))
                  : p.mark(barColor),
          ];
    final lineInk = p.mark(lineColor);
    return ChartFrame(
      title: title,
      unit: '',
      height: height,
      yAxis: empty ? null : barAxis,
      yAxisRight: empty ? null : lineAxis,
      xLabels: xLabels,
      semanticsLabel: _spoken(),
      legend: empty
          ? const []
          : [
              ('$barLabel $barUnit (left scale)', p.mark(barColor)),
              ('$lineLabel (right scale)', lineInk),
            ],
      empty: empty ? NoData(message: emptyMessage) : null,
      child: empty
          ? const SizedBox.shrink()
          : Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: Bars(
                      [
                        for (var i = 0; i < n; i++)
                          i < bars.length ? bars[i] : null,
                      ],
                      p.mark(barColor),
                      colors: barInks,
                      axis: barAxis,
                      widthFactor: .56,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CenteredLine(
                      [
                        for (var i = 0; i < n; i++)
                          i < line.length ? line[i] : null,
                      ],
                      lineInk,
                      lineAxis,
                      p.card,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A line whose points sit at bar CENTRES (slot midpoints), not the edges, so
/// the strain for a day is drawn over that day's recovery bar.
class _CenteredLine extends CustomPainter {
  _CenteredLine(this.d, this.color, this.axis, this.knockout);
  final List<double?> d;
  final Color color, knockout;
  final AxisSpec axis;

  @override
  void paint(Canvas cv, Size s) {
    if (d.isEmpty || s.width <= 0 || s.height <= 0) return;
    final slot = s.width / d.length;
    double x(int i) => slot * (i + .5);
    double y(double v) => s.height - axis.t(v) * s.height;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    Path? path;
    for (var i = 0; i < d.length; i++) {
      final v = d[i];
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
    final dotR = d.length > 40 ? 1.6 : 2.6;
    for (var i = 0; i < d.length; i++) {
      final v = d[i];
      if (v == null || !v.isFinite) continue;
      final o = Offset(x(i), y(v));
      cv.drawCircle(o, dotR + 1.2, Paint()..color = knockout);
      cv.drawCircle(o, dotR, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _CenteredLine o) =>
      o.d != d || o.color != color || o.axis != axis;
}
