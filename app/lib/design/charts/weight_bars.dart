// Explanatory bars for "how a score is built" (How scores work). Static by
// design: no draw-in, so the picture reads at once and goldens stay exact.
//
//   * InputWeightBar  one 8 px bar split into parts by share (Recovery's
//                     input weights) or by amount (the sleep goal's minutes;
//                     "up to" parts are hatched). A legend names each part.
//   * WeightStepBars  columns whose heights are multipliers (Strain's
//                     harder minutes count more). Rows at large text.
//   * BandScale       equal bands with their ranges (Recovery levels,
//                     training load, learning stages): the Medium/20 scale
//                     without a marker.
//
// Every number shown is passed in (from the engine's named constants).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tiles/medium_tiles.dart' show ScaleBand;
import '../tokens/tokens.dart';

/// One part of an [InputWeightBar].
class WeightPart {
  const WeightPart(
    this.label,
    this.value,
    this.color, {
    this.valueText,
    this.hatched = false,
  });

  final String label;

  /// Relative size (a share, or minutes).
  final double value;
  final Color color;

  /// Printed after the label ("40%", "up to 45 min").
  final String? valueText;

  /// An "up to" amount: drawn as stripes.
  final bool hatched;
}

class InputWeightBar extends StatelessWidget {
  const InputWeightBar({super.key, required this.parts, this.semanticsLabel});

  final List<WeightPart> parts;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final spoken =
        semanticsLabel ??
        parts
            .map((w) => [w.label, ?w.valueText].join(' '))
            .join(', ');
    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 8,
              child: CustomPaint(
                painter: _PartsPainter(
                  [for (final w in parts) w.value],
                  [for (final w in parts) p.mark(w.color)],
                  [for (final w in parts) w.hatched],
                ),
              ),
            ),
            const SizedBox(height: S.x3),
            Wrap(
              spacing: S.x4,
              runSpacing: S.x2,
              children: [
                for (final w in parts)
                  _LegendItem(
                    color: p.mark(w.color),
                    label: w.label,
                    value: w.valueText,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, this.value});
  final Color color;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: S.x1 + 2),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                if (value != null)
                  TextSpan(
                    text: ' $value',
                    style: F.tab(F.cap).copyWith(color: p.ink2),
                  ),
              ],
            ),
            style: F.cap.copyWith(color: p.ink),
          ),
        ),
      ],
    );
  }
}

class _PartsPainter extends CustomPainter {
  const _PartsPainter(this.values, this.colors, this.hatched);
  final List<double> values;
  final List<Color> colors;
  final List<bool> hatched;

  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final total = values.fold<double>(0, (a, b) => a + math.max(0, b));
    if (n == 0 || total <= 0) return;
    final usable = size.width - _gap * (n - 1);
    var x = 0.0;
    for (var i = 0; i < n; i++) {
      final w = usable * math.max(0, values[i]) / total;
      if (w <= 0) continue;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 0, w, size.height),
        R.bar,
      );
      if (hatched[i]) {
        canvas.drawRRect(
          r,
          Paint()..color = colors[i].withValues(alpha: .4),
        );
        canvas.save();
        canvas.clipRRect(r);
        final stripe = Paint()
          ..color = colors[i]
          ..strokeWidth = 2;
        for (var s = x - size.height; s < x + w; s += 5) {
          canvas.drawLine(
            Offset(s, size.height),
            Offset(s + size.height, 0),
            stripe,
          );
        }
        canvas.restore();
      } else {
        canvas.drawRRect(r, Paint()..color = colors[i]);
      }
      x += w + _gap;
    }
  }

  @override
  bool shouldRepaint(_PartsPainter o) =>
      o.values != values || o.colors != colors || o.hatched != hatched;
}

/// Columns whose heights are multipliers: ([label], [from], weight).
class WeightStepBars extends StatelessWidget {
  const WeightStepBars({
    super.key,
    required this.steps,
    required this.color,
    this.weightText,
    this.semanticsLabel,
  });

  final List<(String label, String from, double weight)> steps;
  final Color color;

  /// How a weight is printed; "×{w}" by default.
  final String Function(double w)? weightText;
  final String? semanticsLabel;

  static const _maxBar = 56.0;
  static const _minBar = 4.0;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final ink = p.mark(color);
    String fmt(double w) =>
        weightText?.call(w) ??
        '×${w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toString()}';
    final maxW = steps.fold<double>(0, (a, s) => math.max(a, s.$3));
    double h(double w) =>
        maxW <= 0 ? _minBar : math.max(_minBar, _maxBar * w / maxW);
    final spoken =
        semanticsLabel ??
        steps.map((s) => '${s.$1} ${s.$2}, ${fmt(s.$3)}').join('; ');
    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, c) {
            if (bigText(context) || c.maxWidth < 280) {
              return Column(
                children: [
                  for (final s in steps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.x1),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              s.$1,
                              style: F.cap.copyWith(color: p.ink),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: FractionallySizedBox(
                                widthFactor: maxW <= 0
                                    ? .05
                                    : math.max(.05, s.$3 / maxW),
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: ink,
                                    borderRadius: const BorderRadius.all(
                                      R.bar,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: S.x2),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '${fmt(s.$3)} · ${s.$2}',
                              textAlign: TextAlign.end,
                              style: F.tab(F.cap).copyWith(color: p.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: S.x1 + 2),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fmt(steps[i].$3),
                          style: F.tab(F.micro).copyWith(color: p.ink),
                        ),
                        const SizedBox(height: S.x1),
                        Container(
                          height: h(steps[i].$3),
                          decoration: BoxDecoration(
                            color: ink,
                            borderRadius: const BorderRadius.vertical(
                              top: R.bar,
                            ),
                          ),
                        ),
                        const SizedBox(height: S.x1 + 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            steps[i].$1,
                            maxLines: 1,
                            style: F.micro.copyWith(color: p.ink),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            steps[i].$2,
                            maxLines: 1,
                            style: F.tab(F.micro).copyWith(color: p.ink3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Equal-width bands with their ranges underneath (no marker).
class BandScale extends StatelessWidget {
  const BandScale({super.key, required this.bands, this.semanticsLabel});

  final List<ScaleBand> bands;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final spoken =
        semanticsLabel ?? bands.map((b) => '${b.label} ${b.range}').join(', ');
    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 8,
              child: CustomPaint(
                painter: _PartsPainter(
                  [for (final _ in bands) 1],
                  [for (final b in bands) p.mark(b.color)],
                  [for (final _ in bands) false],
                ),
              ),
            ),
            const SizedBox(height: S.x3),
            Wrap(
              spacing: S.x4,
              runSpacing: S.x2,
              children: [
                for (final b in bands)
                  _LegendItem(
                    color: p.mark(b.color),
                    label: b.label,
                    value: b.range,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
