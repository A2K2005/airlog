// The design's "baseline" small tiles: one vital against the user's usual
// range. Each shows a title, the value in dot numerals with its unit, a
// status word and a mark that places today inside the range. Every label is
// a parameter; the geometry is the PNG's own (tile pixels).
//
//   LineBaselineTile  Small/8  "HRV Baseline"  a line that runs to a knob

import 'package:flutter/material.dart';

import '../components/tile.dart';
import '../tokens/tokens.dart';
import 'marks.dart';

/// A value in dots with its unit set right after it, baseline to baseline.
/// The unit tucks 0.75 px into the last glyph's trailing column, as drawn.
class DotValue extends StatelessWidget {
  const DotValue({
    super.key,
    required this.x,
    required this.baseline,
    required this.value,
    this.unit,
    this.style = F.dot32,
    this.unitStyle = F.tileLabel,
    this.unitColor = TileInk.unit,
    this.unitGap = 0,
    this.color = TileInk.primary,
  });

  final double x, baseline;
  final String value;
  final String? unit;
  final TextStyle style, unitStyle;
  final Color unitColor, color;

  /// Space between the number's advance and the unit (negative: tucked).
  final double unitGap;

  @override
  Widget build(BuildContext context) => Positioned(
    left: x,
    top: 0,
    child: Baseline(
      baseline: baseline,
      baselineType: TextBaseline.alphabetic,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: style.copyWith(color: color),
          ),
          if (unit != null)
            Transform.translate(
              offset: Offset(unitGap, 0),
              child: Text(
                unit!,
                maxLines: 1,
                softWrap: false,
                style: unitStyle.copyWith(color: unitColor),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Small/8, "HRV Baseline". [position] (0…1) places the knob along the
/// line; null draws no line (no value yet).
class LineBaselineTile extends StatelessWidget {
  const LineBaselineTile({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    this.position,
    this.statusColor = TileInk.primary,
    this.lineColor = C.lineBlue,
    this.glow = GlowRecipes.s8,
    this.onTap,
    this.semanticLabel,
  });

  final String title;

  /// Dot text, e.g. "56.7"; "--" while there is no value.
  final String value;
  final String unit;
  final String status;
  final double? position;
  final Color statusColor;
  final Color lineColor;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const _lineY = 86.0;
  static const _x0 = S.tilePad;
  static const _x1 = S.tileW - S.tilePad;

  @override
  Widget build(BuildContext context) {
    final pos = position?.clamp(0.0, 1.0);
    return GlowTile(
      size: TileSize.tall,
      glow: glow,
      onTap: onTap,
      semanticLabel: semanticLabel ?? '$title, $value $unit, $status',
      children: [
        TileText(title, x: S.tilePad, baseline: 36, style: F.tileTitle),
        if (pos != null)
          Positioned.fill(
            child: CustomPaint(
              painter: KnobLinePainter(
                from: const Offset(_x0, _lineY),
                to: Offset(_x0 + (_x1 - _x0) * pos, _lineY),
                color: lineColor,
              ),
            ),
          ),
        DotValue(x: S.tilePad, baseline: 160, value: value, unit: unit),
        TileText(
          status,
          x: S.tilePad,
          baseline: 192,
          style: F.tileStatus,
          color: statusColor,
        ),
      ],
    );
  }
}
