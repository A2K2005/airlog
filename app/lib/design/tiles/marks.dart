// Small marks the design tiles share: the knob (a white dot in a faint
// halo), the circular chevron button, and the painters for lines and arcs.
// Geometry and alpha are the PNGs' own (see the tile files for where each
// was measured).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

/// A knob: a white dot of radius [radius] inside a halo of radius
/// [haloRadius] at [C.knobHalo]. Paint it last so it sits on the line.
void paintKnob(
  Canvas canvas,
  Offset c, {
  double radius = 4,
  double haloRadius = 6,
  Color color = C.white,
  Color? ring,
  double ringWidth = 0,
}) {
  canvas.drawCircle(c, haloRadius, Paint()..color = C.knobHalo);
  canvas.drawCircle(c, radius, Paint()..color = color);
  if (ring != null && ringWidth > 0) {
    canvas.drawCircle(
      c,
      radius - ringWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..color = ring,
    );
  }
}

/// The faint disc behind a tile's corner glyph (white 9 %, 32 px in the
/// design). Decorative: the whole tile is the tap target.
class TileBadge extends StatelessWidget {
  const TileBadge({super.key, required this.center, this.diameter = 32});

  final Offset center;
  final double diameter;

  @override
  Widget build(BuildContext context) => Positioned(
    left: center.dx - diameter / 2,
    top: center.dy - diameter / 2,
    width: diameter,
    height: diameter,
    child: const DecoratedBox(
      decoration: BoxDecoration(color: C.badge, shape: BoxShape.circle),
    ),
  );
}

/// A straight line from [from] to [to] with a round knob at [to].
class KnobLinePainter extends CustomPainter {
  const KnobLinePainter({
    required this.from,
    required this.to,
    required this.color,
    this.width = 2,
    this.knob = true,
  });

  final Offset from, to;
  final Color color;
  final double width;
  final bool knob;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTRB(from.dx, from.dy - width / 2, to.dx, to.dy + width / 2),
      Paint()..color = color,
    );
    if (knob) paintKnob(canvas, to);
  }

  @override
  bool shouldRepaint(KnobLinePainter o) =>
      o.from != from || o.to != to || o.color != color || o.width != width;
}

/// Degrees to radians, for arc geometry measured in degrees.
double rad(double deg) => deg * math.pi / 180;
