// The design's gauge small tiles: a vital against its usual range drawn as
// an arc or a stack of range stripes. Geometry measured on the PNGs.
//
//   ArcBaselineTile   Small/6  "RHR Baseline"  a bottom arc with ticks
//   BandBaselineTile  Small/7  "Vo2Max"        range stripes and a line
//   TopArcTile        Small/9  "Body Fat"      a gradient arc on top

import 'dart:math' show cos, sin;

import 'package:flutter/material.dart';

import '../components/tile.dart';
import '../tokens/tokens.dart';
import 'baseline_tiles.dart' show DotValue;
import 'marks.dart';

/// An arc of the circle ([center], [radius]) from [start] to [end] degrees
/// (0° = east, clockwise), with round caps, a faint track [from]…[to], outer
/// ticks every [tickStep]° and a knob at [end].
class GaugeArcPainter extends CustomPainter {
  const GaugeArcPainter({
    required this.center,
    required this.radius,
    required this.width,
    required this.from,
    required this.start,
    required this.end,
    required this.to,
    required this.colors,
    this.tickInner = 0,
    this.tickOuter = 0,
    this.tickStep = 5.625,
    this.tickSpan = 51,
    this.knobRadius = 5,
    this.knob = true,
    this.track = C.track,
  });

  final Offset center;
  final double radius, width;
  final double from, start, end, to;

  /// The value arc's colours along its sweep (one colour = solid).
  final List<Color> colors;
  final double tickInner, tickOuter, tickStep, tickSpan;
  final double knobRadius;
  final bool knob;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      rad(from),
      rad(to - from),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = track,
    );
    if (tickOuter > 0) {
      for (var k = -40; k <= 40; k++) {
        final a = -90 + k * tickStep;
        if ((a + 90).abs() > tickSpan) continue;
        final inside = knob && a >= start - .01 && a <= end + .01;
        final t = colors.length == 1 || end <= start
            ? 0.0
            : ((a - start) / (end - start)).clamp(0.0, 1.0);
        final c = inside
            ? Color.lerp(colors.first, colors.last, t)!.withValues(alpha: .7)
            : C.tick;
        final u = Offset(cos(rad(a)), sin(rad(a)));
        canvas.drawLine(
          center + u * tickInner,
          center + u * tickOuter,
          Paint()
            ..color = c
            ..strokeWidth = 1.5,
        );
      }
    }
    if (!knob) return;
    if (end > start) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      if (colors.length == 1) {
        p.color = colors.first;
      } else {
        p.shader = SweepGradient(
          endAngle: rad(end - start),
          colors: colors,
          transform: GradientRotation(rad(start)),
        ).createShader(rect);
      }
      canvas.drawArc(rect, rad(start), rad(end - start), false, p);
    }
    paintKnob(
      canvas,
      center + Offset(cos(rad(end)), sin(rad(end))) * radius,
      radius: knobRadius,
      haloRadius: knobRadius + 2,
    );
  }

  @override
  bool shouldRepaint(GaugeArcPainter o) =>
      o.end != end || o.start != start || o.colors != colors || o.knob != knob;
}

/// Small/6, "RHR Baseline": the value and unit in dots at the top, a status
/// word, and a gauge arc along the bottom edge whose knob places today in
/// the usual range. [position] 0…1 runs the arc; null = no value yet.
class ArcBaselineTile extends StatelessWidget {
  const ArcBaselineTile({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    this.position,
    this.statusColor = C.recGreen,
    this.arcColors = const [C.recGreenArc, C.recGreenArcEnd],
    this.glow = GlowRecipes.s6,
    this.onTap,
    this.semanticLabel,
  });

  final String title, value, unit, status;
  final double? position;
  final Color statusColor;
  final List<Color> arcColors;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const _start = -127.3, _sweep = 74.6;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.tall,
    glow: glow,
    onTap: onTap,
    semanticLabel: semanticLabel ?? '$title, $value $unit, $status',
    children: [
      TileText(title, x: S.tilePad, baseline: 36, style: F.tileTitle),
      DotValue(
        x: S.tilePad,
        baseline: 84,
        value: value,
        unit: unit,
        unitStyle: F.tileLabel.copyWith(fontWeight: FontWeight.w400),
        unitColor: TileInk.primary,
        unitGap: -.44,
      ),
      TileText(
        status,
        x: S.tilePad,
        baseline: 120,
        style: F.tileStatus,
        color: statusColor,
      ),
      Positioned.fill(
        child: CustomPaint(
          painter: GaugeArcPainter(
            center: const Offset(82, 241.3),
            radius: 89.3,
            width: 8,
            from: -200,
            to: 20,
            start: _start,
            end: _start + _sweep * (position ?? 0).clamp(0.0, 1.0),
            knob: position != null,
            colors: arcColors,
            tickInner: 96.5,
            tickOuter: 100.5,
          ),
        ),
      ),
    ],
  );
}

/// Small/7, "Vo2Max": value and status at the top, and a stack of range
/// stripes with the usual band tinted and a line whose knob places today.
/// [position] 0…1 runs the line left to right; null hides the knob.
class BandBaselineTile extends StatelessWidget {
  const BandBaselineTile({
    super.key,
    required this.title,
    required this.value,
    required this.status,
    this.unit,
    this.position,
    this.statusColor = C.recGreen,
    this.glow = GlowRecipes.s7,
    this.onTap,
    this.semanticLabel,
  });

  final String title, value, status;
  final String? unit;
  final double? position;
  final Color statusColor;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.tall,
    glow: glow,
    onTap: onTap,
    semanticLabel: semanticLabel ?? '$title, $value ${unit ?? ''}, $status',
    children: [
      TileText(title, x: S.tilePad, baseline: 36, style: F.tileTitle),
      DotValue(
        x: S.tilePad,
        baseline: 84,
        value: value,
        unit: unit,
        unitStyle: F.tileLabel.copyWith(fontWeight: FontWeight.w400),
        unitColor: TileInk.primary,
        unitGap: -.44,
      ),
      TileText(
        status,
        x: S.tilePad,
        baseline: 120,
        style: F.tileStatus,
        color: statusColor,
      ),
      Positioned.fill(child: CustomPaint(painter: _StripesPainter(position))),
    ],
  );
}

class _StripesPainter extends CustomPainter {
  const _StripesPainter(this.position);
  final double? position;

  static const _x0 = S.tilePad, _x1 = S.tileW - S.tilePad;

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = C.stripe;
    for (final (a, b) in const [
      (134.0, 142.0),
      (143.0, 151.0),
      (181.0, 189.0),
      (190.0, 198.0),
    ]) {
      canvas.drawRect(Rect.fromLTRB(_x0, a, _x1, b), white);
    }
    canvas.drawRect(
      const Rect.fromLTRB(_x0, 152, _x1, 180),
      Paint()..color = C.bandGood,
    );
    canvas.drawRect(
      const Rect.fromLTRB(_x0, 173, _x1, 175),
      Paint()..color = C.lineGreen,
    );
    if (position != null) {
      paintKnob(
        canvas,
        Offset(_x0 + (_x1 - _x0) * position!.clamp(0.0, 1.0), 174),
        radius: 3.75,
        haloRadius: 5.75,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter o) => o.position != position;
}

/// Small/9, "Body Fat": a gradient gauge arc across the top with ticks and a
/// knob, the value in dots centred below with its unit, and a status word.
class TopArcTile extends StatelessWidget {
  const TopArcTile({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    this.position,
    this.colors = const [C.violet, C.pink],
    this.glow = GlowRecipes.s9,
    this.onTap,
    this.semanticLabel,
  });

  final String title, value, unit, status;
  final double? position;
  final List<Color> colors;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const _start = -133.8, _sweep = 87.6;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.tall,
    glow: glow,
    onTap: onTap,
    semanticLabel: semanticLabel ?? '$title, $value $unit, $status',
    children: [
      TileText(title, centerX: 82, baseline: 36, style: F.tileTitle),
      Positioned.fill(
        child: CustomPaint(
          painter: GaugeArcPainter(
            center: const Offset(82.06, 163.79),
            radius: 104,
            width: 8,
            from: -170,
            to: -10,
            start: _start,
            end: _start + _sweep * (position ?? 0).clamp(0.0, 1.0),
            knob: position != null,
            colors: colors,
            tickInner: 111,
            tickOuter: 115,
          ),
        ),
      ),
      CenteredDotValue(baseline: 160, value: value, unit: unit, gap: 3.5),
      TileText(status, centerX: 82, baseline: 192, style: F.tileStatus),
    ],
  );
}

/// A dot value and its unit, centred as one group on the tile's width.
class CenteredDotValue extends StatelessWidget {
  const CenteredDotValue({
    super.key,
    required this.baseline,
    required this.value,
    this.unit,
    this.gap = 0,
    this.style = F.dot32,
    this.unitStyle = F.tileLabel,
    this.unitColor = TileInk.primary,
  });

  final double baseline;
  final String value;
  final String? unit;
  final double gap;
  final TextStyle style, unitStyle;
  final Color unitColor;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    top: 0,
    child: Baseline(
      baseline: baseline,
      baselineType: TextBaseline.alphabetic,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: style.copyWith(color: TileInk.primary)),
            if (unit != null) ...[
              SizedBox(width: gap),
              Text(
                unit!,
                style: unitStyle.copyWith(
                  fontWeight: FontWeight.w400,
                  color: unitColor,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
