// Large/5, "Readiness": the Recovery tile. The score in coarse dots with its
// status word, two side stats split by a hairline, and a step chart of the
// recent days (each day a translucent block carrying its value, a bar and
// the change from the day before). Every label is a parameter.
//
// The chart is a true linear scale: the lowest day's bar sits at the
// design's lowest bar (y 313), the highest at its highest (y 208). Bar
// height encodes the score, which is content (PRODUCT_PLAN §7: 1:1 sets the
// form, the principles set what fills it). The design places its sample
// bars by eye (80 sits 32 px above 79), so its two "80" blocks cannot be
// reproduced by any linear scale; see DESIGN_REVIEW.md.

import 'package:flutter/material.dart';

import '../components/tile.dart';
import '../tokens/tokens.dart';
import 'baseline_tiles.dart' show DotValue;
import 'glyphs.dart';
import 'marks.dart';

/// One day of the step chart.
class ReadinessStep {
  const ReadinessStep({required this.value, required this.label, this.delta});

  /// The score that places the block (0–100).
  final double value;

  /// Printed on the block ("77").
  final String label;

  /// The change from the day before ("+5%", "−3%"); null for none. A rising
  /// (or unchanged) day draws its bar in orange, a falling one in white.
  final String? delta;

  bool get falling =>
      delta != null && (delta!.startsWith('-') || delta!.startsWith('−'));
}

class ReadinessTile extends StatelessWidget {
  const ReadinessTile({
    super.key,
    required this.title,
    required this.score,
    required this.status,
    required this.statA,
    required this.valueA,
    required this.statB,
    required this.valueB,
    this.steps = const [],
    this.usual,
    this.statusColor = TileInk.primary,
    this.glow = GlowRecipes.l5,
    this.onTap,
    this.semanticLabel,
  });

  final String title;

  /// Dot text ("92"; "--" while calibrating or missing).
  final String score;

  /// The status word beside the score ("Good", "Calibrating").
  final String status;
  final Color statusColor;

  /// The two side stats: a small label over a value.
  final String statA, valueA, statB, valueB;

  /// Up to six days, oldest first.
  final List<ReadinessStep> steps;

  /// The user's usual score: drawn as the chart's track line when known.
  final double? usual;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.large,
    glow: glow,
    onTap: onTap,
    semanticLabel:
        semanticLabel ??
        '$title, $score, $status. $statA $valueA. $statB $valueB.',
    children: [
      TileText(title, x: S.tilePad, baseline: 41, style: F.tileTitle),
      const TileBadge(center: Offset(312, 36)),
      const TileGlyph(TileGlyphKind.arrowUpRight, center: Offset(311.5, 35.5)),
      DotValue(
        x: S.tilePad,
        baseline: 141,
        value: score,
        style: F.dot72,
        unit: status,
        unitStyle: F.tileStatus.copyWith(fontWeight: FontWeight.w400),
        unitColor: statusColor,
        unitGap: -1.55,
      ),
      TileText(
        statA,
        x: 206,
        baseline: 80,
        style: F.tileTiny,
        color: TileInk.secondary,
        maxWidth: 122,
      ),
      TileText(valueA, x: 206, baseline: 97, style: F.tileBody, maxWidth: 122),
      const Positioned(
        left: 206,
        top: 109.5,
        width: 122,
        height: 1,
        child: ColoredBox(color: C.divider),
      ),
      TileText(
        statB,
        x: 206,
        baseline: 126,
        style: F.tileTiny,
        color: TileInk.secondary,
        maxWidth: 122,
      ),
      TileText(valueB, x: 206, baseline: 143, style: F.tileBody, maxWidth: 122),
      if (steps.isNotEmpty) ..._chart(),
    ],
  );

  static const _left = S.tilePad;
  static const _right = S.tileWideW - S.tilePad;
  static const _barLow = 313.0;
  static const _barHigh = 208.0;

  List<Widget> _chart() {
    final shown = steps.length > 6 ? steps.sublist(steps.length - 6) : steps;
    // A true linear scale: bar height encodes the score (PRODUCT_PLAN §7:
    // the design sets the form, the principles set the content).
    final vals = [for (final s in shown) s.value];
    var lo = vals.reduce((a, b) => a < b ? a : b);
    var hi = vals.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    double barY(double v) =>
        (_barLow + (v.clamp(lo, hi) - lo) / (hi - lo) * (_barHigh - _barLow))
            .roundToDouble();

    final n = shown.length;
    double edge(int i) => (_left + i * (_right - _left) / 6).roundToDouble();
    final track = usual == null ? null : barY(usual!);
    final blocks = <Rect>[];
    final out = <Widget>[];
    for (var i = 0; i < n; i++) {
      final slot = 6 - n + i;
      final x0 = edge(slot), x1 = edge(slot + 1);
      final bar = barY(shown[i].value);
      final top = bar - 28;
      blocks.add(Rect.fromLTRB(x0, top, x1, top + 60));
      out.add(
        TileText(shown[i].label, x: x0, baseline: top + 22, style: F.tileTiny),
      );
      if (shown[i].delta != null) {
        out.add(
          TileText(
            shown[i].delta!,
            x: x0,
            baseline: top + 44,
            style: F.tileTiny,
            color: shown[i].falling ? TileInk.primary : C.orangeText,
          ),
        );
      }
    }
    return [
      Positioned.fill(
        child: CustomPaint(
          painter: _StepsPainter(
            blocks: blocks,
            track: track == null
                ? null
                : Rect.fromLTRB(_left, track, _right, track + 4),
            falling: [for (final s in shown) s.falling],
          ),
        ),
      ),
      ...out,
    ];
  }
}

class _StepsPainter extends CustomPainter {
  const _StepsPainter({
    required this.blocks,
    required this.track,
    required this.falling,
  });

  final List<Rect> blocks;
  final Rect? track;
  final List<bool> falling;

  @override
  void paint(Canvas canvas, Size size) {
    // Blocks and the track are one translucent shape: where they overlap
    // the design does not double the white.
    var shape = Path();
    for (final b in blocks) {
      shape = Path.combine(PathOperation.union, shape, Path()..addRect(b));
    }
    if (track != null) {
      shape = Path.combine(PathOperation.union, shape, Path()..addRect(track!));
    }
    canvas.drawPath(shape, Paint()..color = C.divider);
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      canvas.drawRect(
        Rect.fromLTWH(b.left, b.top + 28, b.width, 4),
        Paint()..color = falling[i] ? C.white : C.orangeLight,
      );
    }
  }

  @override
  bool shouldRepaint(_StepsPainter o) =>
      o.blocks != blocks || o.track != track || o.falling != falling;
}
