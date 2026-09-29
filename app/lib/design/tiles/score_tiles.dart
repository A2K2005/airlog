// Score and progress tiles. Geometry measured on the PNGs.
//
//   ArcScoreTile     Small/2    "Water"          an arc from the left edge
//                                                 to a knob, value in dots
//   RingScoreTile    Small/5    "Sleep Quality"  a ring, centred value
//   ProgressTile     Medium/12  "Wellness Score" value and a gradient bar
//   HealthAlertTile  Medium/5   "Health Alert"   three readings over a
//                                                 segmented bar and a
//                                                 time axis

import 'dart:math' show cos, sin, pi;

import 'package:flutter/material.dart';

import '../components/tile.dart';
import '../tokens/tokens.dart';
import 'baseline_tiles.dart' show DotValue;
import 'gauge_tiles.dart' show CenteredDotValue;
import 'glyphs.dart';
import 'marks.dart';

/// Small/2: a lime arc sweeping in from the left edge to a knob with a soft
/// spotlight under it, the value in dots and a unit line. [progress] 0…1
/// runs the knob along the arc; null = no value yet (track only).
class ArcScoreTile extends StatelessWidget {
  const ArcScoreTile({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    this.progress,
    this.color = C.limeSoft,
    this.glow = GlowRecipes.s2,
    this.onTap,
    this.semanticLabel,
  });

  final String title, value, unit;
  final double? progress;
  final Color color;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.tall,
    glow: glow,
    onTap: onTap,
    semanticLabel: semanticLabel ?? '$title, $value $unit',
    children: [
      TileText(title, x: S.tilePad, baseline: 36.75, style: F.tileTitle),
      const TileBadge(center: Offset(131.5, 32), diameter: 24),
      const TileGlyph(TileGlyphKind.chevronRight, center: Offset(132, 31.5)),
      Positioned.fill(
        child: CustomPaint(painter: _ArcScorePainter(progress, color)),
      ),
      DotValue(x: S.tilePad, baseline: 174, value: value),
      TileText(
        unit,
        x: S.tilePad,
        baseline: 196.25,
        style: F.tileLabel,
        color: TileInk.unitSoft,
      ),
    ],
  );
}

class _ArcScorePainter extends CustomPainter {
  const _ArcScorePainter(this.progress, this.color);
  final double? progress;
  final Color color;

  static const _c = Offset(82, 157);
  static const _r = 95.5;

  /// The arc runs from the left edge (−149.1°) to the right edge (−30.9°).
  static const _from = -149.1, _to = -30.9;

  static double angleOf(double p) => _from + (_to - _from) * p.clamp(0.0, 1.0);

  /// The arc meets the tile edge at 0 and 1, where the knob would be cut in
  /// half, so the knob (halo 8) and the fill stop 9 px inside the edge. The
  /// number beside it stays exact.
  static const _knobFrom = -139.8, _knobTo = -40.2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: _c, radius: _r);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      rad(_from - 10),
      rad(_to - _from + 10),
      false,
      stroke..color = C.track,
    );
    if (progress == null) return;
    final a = angleOf(progress!);
    final ka = a.clamp(_knobFrom, _knobTo);
    final k = _c + Offset(cos(rad(ka)), sin(rad(ka))) * _r;
    // The spotlight: a soft column falling from the knob.
    canvas.drawRect(
      Rect.fromLTWH(k.dx - 12, k.dy + 9, 24, 24),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [C.spotlight, C.clear],
        ).createShader(Rect.fromLTWH(k.dx - 12, k.dy + 9, 24, 24)),
    );
    canvas.drawArc(
      rect,
      rad(_from - 10),
      rad(ka - _from + 10),
      false,
      stroke..color = color,
    );
    paintKnob(canvas, k, radius: 5.6, haloRadius: 8);
  }

  @override
  bool shouldRepaint(_ArcScorePainter o) =>
      o.progress != progress || o.color != color;
}

/// Small/5: a faint ring with a lime squiggle marking the value's end, the
/// value centred in dots and a caption at the foot.
class RingScoreTile extends StatelessWidget {
  const RingScoreTile({
    super.key,
    required this.title,
    required this.value,
    required this.caption,
    this.progress,
    this.color = C.lime,
    this.glow = GlowRecipes.s5,
    this.onTap,
    this.semanticLabel,
  });

  final String title, value, caption;

  /// 0…1 around the ring from the top, clockwise; the squiggle sits there.
  final double? progress;
  final Color color;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.tall,
    glow: glow,
    onTap: onTap,
    semanticLabel: semanticLabel ?? '$title, $value, $caption',
    children: [
      TileText(title, centerX: 82, baseline: 36, style: F.tileTitle),
      Positioned.fill(
        child: CustomPaint(painter: _RingPainter(progress, color)),
      ),
      CenteredDotValue(baseline: 130, value: value, style: F.dot40),
      TileText(
        caption,
        centerX: 82,
        baseline: 194.75,
        style: F.tileMicro,
        color: TileInk.tertiary,
      ),
    ],
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress, this.color);
  final double? progress;
  final Color color;

  static const _c = Offset(82.5, 113.5);
  static const _r = 59.2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      _c,
      _r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = C.ring,
    );
    if (progress == null) return;
    // A short wave riding the ring, ending at the value.
    final end = -90 + 360 * progress!.clamp(0.0, 1.0);
    final path = Path();
    const span = 34.0;
    for (var i = 0; i <= 24; i++) {
      final t = i / 24;
      final a = rad(end - span + span * t);
      final off = 4.5 * sin(t * 2 * pi);
      final r = _r + off;
      final p = _c + Offset(cos(a), sin(a)) * r;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.color != color;
}

/// Medium/12: a value in dots with its unit, and a gradient bar that fills
/// to a knob. [progress] 0…1; null = empty track.
class ProgressTile extends StatelessWidget {
  const ProgressTile({
    super.key,
    required this.title,
    required this.value,
    this.unit,
    this.progress,
    this.colors = const [C.recGreen, C.lime, C.limePale],
    this.glow = GlowRecipes.m12,
    this.onTap,
    this.semanticLabel,
  });

  final String title, value;
  final String? unit;
  final double? progress;
  final List<Color> colors;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.medium,
    glow: glow,
    onTap: onTap,
    semanticLabel: semanticLabel ?? '$title, $value ${unit ?? ''}',
    children: [
      TileText(title, x: S.tilePad, baseline: 36, style: F.tileTitle),
      DotValue(
        x: S.tilePad,
        baseline: 103,
        value: value,
        style: F.dot40,
        unit: unit,
        unitStyle: F.tileLabel.copyWith(fontWeight: FontWeight.w400),
        unitGap: -.61,
      ),
      Positioned.fill(
        child: CustomPaint(painter: _BarPainter(progress, colors)),
      ),
    ],
  );
}

class _BarPainter extends CustomPainter {
  const _BarPainter(this.progress, this.colors);
  final double? progress;
  final List<Color> colors;

  static const _bar = Rect.fromLTRB(20, 136, 328, 144);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(_bar, const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = C.barTrack);
    if (progress == null) return;
    final x = _bar.left + _bar.width * progress!.clamp(0.0, 1.0);
    final fill = Rect.fromLTRB(_bar.left, _bar.top, x, _bar.bottom);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(colors: colors)
            .createShader(Rect.fromLTRB(_bar.left, 0, x, 1)),
    );
    paintKnob(canvas, Offset(x, _bar.center.dy), radius: 6.4, haloRadius: 8.4);
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.progress != progress || o.colors != colors;
}

/// One reading of the Health Alert tile.
class AlertReading {
  const AlertReading(this.value, this.label);
  final String value, label;
}

/// One segment of the Health Alert bar.
class AlertSegment {
  const AlertSegment(this.fraction, this.color);
  final double fraction;
  final Color color;
}

/// Medium/5: three readings (left, centre, right), two range labels, a
/// segmented bar and up to seven axis labels.
class HealthAlertTile extends StatelessWidget {
  const HealthAlertTile({
    super.key,
    required this.title,
    required this.readings,
    required this.lowLabel,
    required this.highLabel,
    required this.segments,
    this.axis = const [],
    this.glow = GlowRecipes.m5,
    this.onTap,
    this.semanticLabel,
  });

  final String title;

  /// Up to three, placed left, centre and right.
  final List<AlertReading> readings;
  final String lowLabel, highLabel;
  final List<AlertSegment> segments;
  final List<String> axis;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const _left = S.tilePad, _right = S.tileWideW - S.tilePad;

  @override
  Widget build(BuildContext context) {
    final cols = <Widget>[];
    for (var i = 0; i < readings.length && i < 3; i++) {
      final r = readings[i];
      final value = F.tileStatus.copyWith(fontWeight: FontWeight.w500);
      final label = F.tileMicro.copyWith(fontWeight: FontWeight.w400);
      if (i == 0) {
        cols
          ..add(TileText(r.value, x: 19.5, baseline: 68, style: value))
          ..add(TileText(r.label, x: 20, baseline: 85, style: label));
      } else if (i == 1) {
        cols
          ..add(TileText(r.value, x: 156, baseline: 68, style: value))
          ..add(TileText(r.label, x: 156, baseline: 85, style: label));
      } else {
        cols
          ..add(TileText(r.value, right: 328, baseline: 68, style: value))
          ..add(TileText(r.label, right: 328, baseline: 85, style: label));
      }
    }
    final axisStyle = F.tileMicro.copyWith(fontWeight: FontWeight.w400);
    return GlowTile(
      size: TileSize.medium,
      glow: glow,
      onTap: onTap,
      semanticLabel:
          semanticLabel ??
          '$title. ${readings.map((r) => '${r.label} ${r.value}').join(', ')}',
      children: [
        TileText(title, x: S.tilePad, baseline: 37, style: F.tileTitle),
        const TileBadge(center: Offset(316, 32), diameter: 24),
        const TileGlyph(TileGlyphKind.chevronRight, center: Offset(316, 31.5)),
        ...cols,
        TileText(
          lowLabel,
          x: S.tilePad,
          baseline: 105,
          style: F.tileMicro,
          color: TileInk.unit,
        ),
        TileText(
          highLabel,
          right: 328,
          baseline: 105,
          style: F.tileMicro,
          color: TileInk.unit,
        ),
        Positioned.fill(
          child: CustomPaint(painter: _SegmentsPainter(segments)),
        ),
        for (var i = 0; i < axis.length; i++)
          TileText(
            axis[i],
            centerX: axis.length == 1
                ? (_left + _right) / 2
                : 33 + i * (315 - 33) / (axis.length - 1),
            baseline: 141,
            style: axisStyle,
            color: TileInk.axis,
          ),
      ],
    );
  }
}

class _SegmentsPainter extends CustomPainter {
  const _SegmentsPainter(this.segments);
  final List<AlertSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    const x0 = 20.0, x1 = 328.0, top = 116.0, h = 8.0, gap = 1.0;
    final total = segments.fold<double>(0, (a, s) => a + s.fraction);
    if (total <= 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(x0, top, x1, top + h, const Radius.circular(4)),
        Paint()..color = C.barTrack,
      );
      return;
    }
    var x = x0;
    for (var i = 0; i < segments.length; i++) {
      final w =
          (x1 - x0 - gap * (segments.length - 1)) *
          segments[i].fraction /
          total;
      final r = RRect.fromLTRBR(
        x,
        top,
        x + w,
        top + h,
        const Radius.circular(4),
      );
      canvas.drawRRect(r, Paint()..color = segments[i].color);
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(_SegmentsPainter o) => o.segments != segments;
}
