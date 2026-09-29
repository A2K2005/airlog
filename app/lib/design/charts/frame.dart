// Adapted from OpenStrap/edge lib/ui2/grammar.dart — ChartFrame, _Gridlines,
// _XMarks, NoData (MIT, see third_party/edge/LICENSE).
// Changes: an optional RIGHT axis (dual-unit charts), an explicit
// [semanticsLabel] override for the spoken summary, a [trailing] header slot,
// [showUnit] (hide the printed unit when [trailing] already states it),
// Material icons instead of Lucide, Airlog tokens.
//
// A painter draws a shape; a shape is not information. Every chart someone is
// meant to read a number off goes in a ChartFrame, which supplies the unit,
// the y scale in real numbers, the x range, a key for every colour, and one
// sentence for a screen reader.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'axis.dart';

class ChartFrame extends StatelessWidget {
  /// 'Resting heart rate'. Empty string hides the header row.
  final String title;

  /// 'bpm', 'ms', '%'. Printed in the header when [title] is and
  /// [showUnit] is true; always part of the spoken label.
  final String unit;

  /// False hides the printed unit, e.g. when [trailing] is a value readout
  /// that already carries it ("54 bpm"). The spoken label still says it.
  final bool showUnit;

  /// The plot: normally `CustomPaint(size: Size.infinite, painter: …)`.
  final Widget child;

  /// Plot height. Text scale does not stretch it; tick labels thin instead.
  final double height;

  /// Left axis (gridlines + labels). Pass the SAME spec to the painter.
  final AxisSpec? yAxis;

  /// Optional right axis for a second unit (labels only; gridlines follow
  /// [yAxis]). Pass the same spec to the painter that uses it.
  final AxisSpec? yAxisRight;

  /// Unit printed above the right axis, e.g. 'strain'.
  final String? unitRight;

  /// Evenly spaced x labels: first flush left, last flush right.
  final List<String> xLabels;
  final List<(String, Color)> legend;
  final String? footnote;

  /// The series behind the picture, for the spoken summary.
  final List<double?> series;

  /// Replaces the generated spoken summary.
  final String? semanticsLabel;

  /// Non-null MEANS NO DATA: rendered in place of plot, axes and x labels.
  final Widget? empty;

  /// 0…1 provenance marks (NOT data); always explain them in [footnote].
  final List<double> xMarks;

  /// Header trailing slot (e.g. a value readout).
  final Widget? trailing;

  const ChartFrame({
    super.key,
    required this.title,
    required this.unit,
    required this.child,
    this.height = 120,
    this.yAxis,
    this.yAxisRight,
    this.unitRight,
    this.xLabels = const [],
    this.legend = const [],
    this.footnote,
    this.series = const [],
    this.semanticsLabel,
    this.empty,
    this.xMarks = const [],
    this.trailing,
    this.showUnit = true,
  });

  static Size _measure(String s, TextStyle st, TextScaler sc, TextDirection d) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: d,
      textScaler: sc,
      maxLines: 1,
    )..layout();
    return tp.size;
  }

  String? _spoken() {
    if (empty != null) return null;
    return denseSummary(series, format: yAxis?.format);
  }

  /// The full spoken sentence (exposed for tests).
  String spokenLabel() {
    if (semanticsLabel != null) return semanticsLabel!;
    return [
      if (title.isNotEmpty) title,
      if (unit.isNotEmpty) 'measured in $unit',
      ?_spoken(),
      if (empty == null && xLabels.length > 1)
        'from ${xLabels.first} to ${xLabels.last}',
      if (legend.isNotEmpty)
        'Key: ${[for (final (l, _) in legend) l].join(', ')}',
      ?footnote,
    ].join('. ');
  }

  Widget _header(P p, bool stacked) {
    final name = Text(
      title,
      style: F.bodySm.copyWith(color: p.ink, fontWeight: FontWeight.w700),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final measure = Text(unit, style: F.cap.copyWith(color: p.ink3));
    final printUnit = showUnit && unit.isNotEmpty;
    if (!stacked) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: name),
          if (printUnit) ...[const SizedBox(width: S.x2), measure],
          if (trailing != null) ...[const SizedBox(width: S.x2), trailing!],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        name,
        if (printUnit || trailing != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (printUnit) measure,
              if (printUnit && trailing != null) const SizedBox(width: S.x2),
              ?trailing,
            ],
          ),
      ],
    );
  }

  List<String> _labels(AxisSpec a, double lineH) {
    final fits = (height / (lineH * 1.35)).floor();
    final n = a.ticks.clamp(2, fits < 2 ? 2 : fits);
    return [
      for (final v in AxisSpec(
        min: a.min,
        max: a.max,
        ticks: n,
        format: a.format,
      ).tickValues)
        a.format(v),
    ];
  }

  Widget _gutter(
    List<String> labels,
    double width,
    double lineH,
    TextStyle tick,
    TextAlign align,
  ) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        child: Stack(
          children: [
            for (var i = 0; i < labels.length; i++)
              Positioned(
                left: 0,
                right: 0,
                top:
                    (labels.length < 2
                            ? 0.0
                            : i / (labels.length - 1) * height - lineH / 2)
                        .clamp(0.0, (height - lineH).clamp(0.0, height)),
                child: Text(
                  labels[i],
                  style: tick,
                  textAlign: align,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final scaler = MediaQuery.textScalerOf(c);
    final dir = Directionality.of(c);
    final tick = F.tab(F.over).copyWith(color: p.ink3, letterSpacing: .2);

    final a = empty == null ? yAxis : null;
    final ar = empty == null ? yAxisRight : null;
    final lineH = _measure('0', tick, scaler, dir).height;
    var labels = const <String>[], labelsR = const <String>[];
    var gutter = 0.0, gutterR = 0.0;
    if (a != null) {
      labels = _labels(a, lineH);
      for (final s in labels) {
        final w = _measure(s, tick, scaler, dir).width;
        if (w > gutter) gutter = w;
      }
    }
    if (ar != null) {
      labelsR = _labels(ar, lineH);
      for (final s in labelsR) {
        final w = _measure(s, tick, scaler, dir).width;
        if (w > gutterR) gutterR = w;
      }
    }
    final inset = a == null ? 0.0 : gutter + S.x2;
    final insetR = ar == null ? 0.0 : gutterR + S.x2;
    final gridN = labels.isNotEmpty ? labels.length : labelsR.length;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: spokenLabel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty) ...[
            ExcludeSemantics(child: _header(p, bigText(c))),
            const SizedBox(height: S.x3),
          ],
          if (empty != null)
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Center(child: empty),
            )
          else
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (a != null) ...[
                    _gutter(labels, gutter, lineH, tick, TextAlign.right),
                    const SizedBox(width: S.x2),
                  ],
                  // The plot is NOT excluded from semantics: an interactive
                  // child (a scrubber) must stay reachable. Painters carry no
                  // semantics of their own; the frame's sentence speaks.
                  Expanded(
                    child: Stack(
                      children: [
                        if (gridN > 0)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _Gridlines(gridN, p.line),
                            ),
                          ),
                        Positioned.fill(child: child),
                        if (xMarks.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _XMarks(xMarks, p.ink3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (ar != null) ...[
                    const SizedBox(width: S.x2),
                    _gutter(labelsR, gutterR, lineH, tick, TextAlign.left),
                  ],
                ],
              ),
            ),
          if (empty == null && xLabels.isNotEmpty)
            ExcludeSemantics(
              child: Padding(
                padding: EdgeInsets.only(top: S.x2, left: inset, right: insetR),
                child: Row(
                  children: [
                    for (var i = 0; i < xLabels.length; i++)
                      Expanded(
                        child: Text(
                          xLabels[i],
                          style: tick,
                          textAlign: xLabels.length == 1
                              ? TextAlign.center
                              : i == 0
                              ? TextAlign.start
                              : i == xLabels.length - 1
                              ? TextAlign.end
                              : TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (legend.isNotEmpty)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: S.x3),
                child: Wrap(
                  spacing: S.x4,
                  runSpacing: S.x1,
                  children: [
                    for (final (label, colour) in legend)
                      LegendSwatch(label: label, color: colour),
                  ],
                ),
              ),
            ),
          if (footnote != null)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: S.x2),
                child: Text(footnote!, style: F.cap.copyWith(color: p.ink3)),
              ),
            ),
        ],
      ),
    );
  }
}

/// One legend entry: a swatch in the mark's real colour and its name.
class LegendSwatch extends StatelessWidget {
  const LegendSwatch({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: S.x1 + 2),
        Flexible(
          // Legends often carry numbers ("Green 15", "Baseline 7h 36m").
          child: Text(label, style: F.tab(F.cap).copyWith(color: p.ink2)),
        ),
      ],
    );
  }
}

class _Gridlines extends CustomPainter {
  final int n;
  final Color color;
  const _Gridlines(this.n, this.color);

  @override
  void paint(Canvas cv, Size s) {
    if (n < 2 || s.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      final y = (i / (n - 1) * s.height).clamp(.5, s.height - .5);
      cv.drawLine(Offset(0, y), Offset(s.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Gridlines o) => o.n != n || o.color != color;
}

class _XMarks extends CustomPainter {
  final List<double> at;
  final Color color;
  const _XMarks(this.at, this.color);

  @override
  void paint(Canvas cv, Size s) {
    if (s.width <= 0 || s.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final f in at) {
      if (!f.isFinite) continue;
      final x = (f.clamp(0.0, 1.0) * s.width).clamp(.5, s.width - .5);
      for (var y = 0.0; y < s.height; y += 6) {
        final end = y + 3 > s.height ? s.height : y + 3;
        cv.drawLine(Offset(x, y), Offset(x, end), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _XMarks o) => o.color != color || o.at != at;
}

/// The body of an empty ChartFrame: says what is missing, in words.
class NoData extends StatelessWidget {
  final String message;
  const NoData({super.key, this.message = 'No data yet'});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.show_chart_rounded, size: 16, color: p.ink3),
        const SizedBox(width: S.x2),
        Flexible(
          child: Text(
            message,
            style: F.cap.copyWith(color: p.ink3),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
