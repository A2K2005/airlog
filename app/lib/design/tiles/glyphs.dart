// The design's small line glyphs, drawn as the PNGs draw them: 1 px white
// strokes on the pixel grid (the corner badge's arrow and chevron). Larger
// pictograms (bed, heart, dumbbell…) use Material icons at the measured size.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

enum TileGlyphKind {
  /// ↗, Large/5's corner badge (a 10 × 10 box).
  arrowUpRight,

  /// ›, Small/2 and Medium/5's corner badge (6 × 11).
  chevronRight,

  /// A pulse line, Heart Rate Zone's title glyph (18 × 15).
  activity,
}

/// A line glyph centred on [center] (tile pixels).
class TileGlyph extends StatelessWidget {
  const TileGlyph(this.kind, {super.key, required this.center});
  final TileGlyphKind kind;
  final Offset center;

  @override
  Widget build(BuildContext context) => Positioned(
    left: center.dx - 10,
    top: center.dy - 10,
    width: 20,
    height: 20,
    child: CustomPaint(painter: _GlyphPainter(kind)),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind);
  final TileGlyphKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = C.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    // Box origin: the glyph's centre is (10, 10).
    canvas.translate(2, 2);
    switch (kind) {
      case TileGlyphKind.arrowUpRight:
        canvas
          ..drawLine(const Offset(4, 12), const Offset(11.5, 4.5), p)
          ..drawLine(const Offset(5.5, 4.5), const Offset(12, 4.5), p)
          ..drawLine(const Offset(12.5, 4.5), const Offset(12.5, 11), p);
      case TileGlyphKind.chevronRight:
        final path = Path()
          ..moveTo(5.5, 2.5)
          ..lineTo(10.5, 8)
          ..lineTo(5.5, 13.5);
        canvas.drawPath(path, p..strokeCap = StrokeCap.round);
      case TileGlyphKind.activity:
        // Untitled-style "activity": 24-unit path scaled to 18 px.
        canvas.translate(-1, -1);
        canvas.scale(.75);
        final path = Path()
          ..moveTo(22, 12)
          ..lineTo(18, 12)
          ..lineTo(15, 21)
          ..lineTo(9, 3)
          ..lineTo(6, 12)
          ..lineTo(2, 12);
        canvas.drawPath(
          path,
          p
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter o) => o.kind != kind;
}
