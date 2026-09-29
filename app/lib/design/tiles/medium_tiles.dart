// The medium tiles. Geometry measured on the PNGs; every label a parameter.
//
//   ZoneBarTile       Medium/16  "Heart Rate Zone"  a four-part bar and four
//                                                   value columns
//   HeartRateTile     Medium/10  "Heart Rate"       the live number and a
//                                                   waveform plate with a badge
//   WeekDotsTile      Medium/14  "Your Streak"      seven day circles
//   BandMediumTile    Medium/7   "VO2Max"           value, word and a range
//                                                   stripe chart
//   SegmentScaleTile  Medium/20  "Your BMI"         value, sentence and a
//                                                   four-band scale

import 'package:flutter/material.dart';

import '../components/tile.dart';
import '../tokens/tokens.dart';
import 'baseline_tiles.dart' show DotValue;
import 'large_tiles.dart' show TileIcon;
import 'glyphs.dart';
import 'marks.dart';

// ── Medium/16 ────────────────────────────────────────────────────────────

class ZoneColumn {
  const ZoneColumn(this.value, this.label, this.fraction);
  final String value, label;

  /// This zone's share of the bar (the four are normalised).
  final double fraction;
}

class ZoneBarTile extends StatelessWidget {
  const ZoneBarTile({
    super.key,
    required this.title,
    required this.columns,
    this.colors = const [C.recRed, C.red600, C.red700, C.red800],
    this.glow = GlowRecipes.m16,
    this.onTap,
    this.semanticLabel,
  });

  final String title;

  /// Four columns, left to right.
  final List<ZoneColumn> columns;
  final List<Color> colors;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.medium,
    glow: glow,
    onTap: onTap,
    semanticLabel:
        semanticLabel ??
        '$title. ${columns.map((c) => '${c.label} ${c.value}').join(', ')}',
    children: [
      const TileGlyph(TileGlyphKind.activity, center: Offset(29.5, 30)),
      TileText(title, x: 48, baseline: 36, style: F.tileTitle),
      Positioned.fill(
        child: CustomPaint(
          painter: _ZoneBar([for (final c in columns) c.fraction], colors),
        ),
      ),
      for (var i = 0; i < columns.length && i < 4; i++) ...[
        TileText(
          columns[i].value,
          centerX: 55 + 79.2 * i,
          baseline: 124,
          style: F.tileNumber.copyWith(letterSpacing: 0),
        ),
        TileText(
          columns[i].label,
          centerX: 55 + 79.2 * i,
          baseline: 140,
          style: F.tileLabel,
          color: TileInk.secondary,
        ),
      ],
    ],
  );
}

class _ZoneBar extends CustomPainter {
  const _ZoneBar(this.fractions, this.colors);
  final List<double> fractions;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const bar = RRect.fromLTRBXY(20, 64.5, 328, 82.5, 9, 9);
    final total = fractions.fold<double>(0, (a, b) => a + b);
    canvas.save();
    canvas.clipRRect(bar);
    if (total <= 0) {
      canvas.drawRRect(bar, Paint()..color = C.barTrack);
    } else {
      var x = 20.0;
      for (var i = 0; i < fractions.length && i < colors.length; i++) {
        final w = 308 * fractions[i] / total;
        canvas.drawRect(
          Rect.fromLTWH(x, 64.5, w, 18),
          Paint()..color = colors[i],
        );
        x += w;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ZoneBar o) => o.fractions != fractions;
}

// ── Medium/10 ────────────────────────────────────────────────────────────

class HeartRateTile extends StatelessWidget {
  const HeartRateTile({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.samples,
    this.badgeValue,
    this.badgeUnit,
    this.glow = GlowRecipes.m10,
    this.semanticLabel,
  });

  final String title, value, unit;

  /// The waveform: recent readings, oldest first (normalised to the plate).
  final List<double> samples;

  /// The blue badge's number and unit (the latest reading).
  final String? badgeValue, badgeUnit;
  final GlowRecipe glow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.medium,
    glow: glow,
    semanticLabel: semanticLabel ?? '$title, $value $unit',
    children: [
      const TileIcon(Icons.favorite_border, center: Offset(28.5, 31), size: 18),
      TileText(title, x: 46.25, baseline: 36, style: F.tileTitle),
      DotValue(x: 214, baseline: 50, value: value),
      TileText(
        unit,
        x: 302,
        baseline: 50,
        style: F.tileLabel.copyWith(fontWeight: FontWeight.w400),
      ),
      Positioned.fill(child: CustomPaint(painter: _Wave(samples))),
      if (badgeValue != null) ...[
        const Positioned(
          left: 282,
          top: 70,
          width: 42,
          height: 70,
          child: DecoratedBox(
            decoration: BoxDecoration(color: C.liveBlue, borderRadius: R.rSm),
          ),
        ),
        TileText(
          badgeValue!,
          centerX: 303,
          baseline: 102.5,
          style: F.tileMicro,
        ),
        TileText(
          badgeUnit ?? '',
          centerX: 303,
          baseline: 113.5,
          style: F.tileMicro,
          color: TileInk.secondary,
        ),
      ],
    ],
  );
}

class _Wave extends CustomPainter {
  const _Wave(this.samples);
  final List<double> samples;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromLTRBR(20, 68, 328, 144, const Radius.circular(R.sm)),
      Paint()..color = C.plateSoft,
    );
    if (samples.length < 2) return;
    final lo = samples.reduce((a, b) => a < b ? a : b);
    final hi = samples.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    const x0 = 24.0, x1 = 272.0, top = 84.0, bottom = 127.5;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = x0 + (x1 - x0) * i / (samples.length - 1);
      final y = bottom - (bottom - top) * (samples[i] - lo) / span;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = C.white,
    );
  }

  @override
  bool shouldRepaint(_Wave o) => o.samples != samples;
}

// ── Medium/14 ────────────────────────────────────────────────────────────

enum DayMark { done, doneDim, today, open }

class WeekDotsTile extends StatelessWidget {
  const WeekDotsTile({
    super.key,
    required this.title,
    required this.trailing,
    required this.letters,
    required this.numbers,
    required this.marks,
    this.page = 0,
    this.pages = 3,
    this.glow = GlowRecipes.m14,
    this.onTap,
    this.semanticLabel,
  });

  final String title, trailing;
  final List<String> letters, numbers;
  final List<DayMark> marks;
  final int page, pages;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static double cx(int i) => 34.5 + 46.25 * i;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.medium,
    glow: glow,
    onTap: onTap,
    semanticLabel: semanticLabel ?? '$title, $trailing',
    children: [
      TileText(title, x: 19.25, baseline: 36, style: F.tileTitle),
      TileText(
        trailing,
        right: 327.5,
        baseline: 35,
        style: F.tileLabel.copyWith(fontWeight: FontWeight.w400),
        color: TileInk.unit,
      ),
      for (var i = 0; i < letters.length && i < 7; i++)
        TileText(
          letters[i],
          centerX: cx(i),
          baseline: 76,
          style: F.tileLabel,
          color: TileInk.dim,
        ),
      Positioned.fill(child: CustomPaint(painter: _Days(marks, page, pages))),
      for (var i = 0; i < numbers.length && i < 7; i++)
        TileText(
          numbers[i],
          centerX: cx(i),
          baseline: 104,
          style: F.tileStatus,
          color:
              i < marks.length &&
                  (marks[i] == DayMark.done || marks[i] == DayMark.doneDim)
              ? C.inkOnLime
              : TileInk.primary,
        ),
    ],
  );
}

class _Days extends CustomPainter {
  const _Days(this.marks, this.page, this.pages);
  final List<DayMark> marks;
  final int page, pages;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < marks.length && i < 7; i++) {
      final c = Offset(WeekDotsTile.cx(i), 98.5);
      switch (marks[i]) {
        case DayMark.done:
          canvas.drawCircle(c, 15, Paint()..color = C.lime);
        case DayMark.doneDim:
          canvas.drawCircle(c, 15, Paint()..color = C.limeDeep);
        case DayMark.today:
          canvas.drawCircle(c, 15, Paint()..color = C.dayOpen);
          canvas.drawCircle(
            c,
            14.25,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = C.lime,
          );
        case DayMark.open:
          canvas.drawCircle(c, 15, Paint()..color = C.dayOpen);
      }
    }
    for (var i = 0; i < pages; i++) {
      canvas.drawCircle(
        Offset(161.5 + 12 * i, 139.5),
        4,
        Paint()..color = i == page ? C.recGreen : C.pageDot,
      );
    }
  }

  @override
  bool shouldRepaint(_Days o) => o.marks != marks || o.page != page;
}

// ── Medium/7 ─────────────────────────────────────────────────────────────

class BandMediumTile extends StatelessWidget {
  const BandMediumTile({
    super.key,
    required this.title,
    required this.value,
    required this.status,
    this.position,
    this.glow = GlowRecipes.m7,
    this.onTap,
    this.semanticLabel,
  });

  final String title, value, status;

  /// 0…1 across the chart; null hides the knob.
  final double? position;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => GlowTile(
    size: TileSize.medium,
    glow: glow,
    onTap: onTap,
    semanticLabel: semanticLabel ?? '$title, $value, $status',
    children: [
      TileText(title, x: 19.75, baseline: 36, style: F.tileTitle),
      DotValue(x: 19.75, baseline: 112, value: value),
      TileText(
        status,
        x: 20,
        baseline: 140,
        style: F.tileLabel.copyWith(fontWeight: FontWeight.w400),
      ),
      Positioned.fill(child: CustomPaint(painter: _MediumStripes(position))),
    ],
  );
}

class _MediumStripes extends CustomPainter {
  const _MediumStripes(this.position);
  final double? position;

  static const _x0 = 179.0, _x1 = 328.0;

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = C.stripe;
    for (final (a, b) in const [(60.0, 65.0), (66.0, 75.0), (126.0, 143.0)]) {
      canvas.drawRect(Rect.fromLTRB(_x0, a, _x1, b), white);
    }
    canvas.drawRect(
      const Rect.fromLTRB(_x0, 76, _x1, 125),
      Paint()..color = C.bandGood,
    );
    canvas.drawRect(
      const Rect.fromLTRB(_x0, 107, _x1, 109),
      Paint()..color = C.lineGreen,
    );
    if (position != null) {
      paintKnob(
        canvas,
        Offset(_x0 + (_x1 - _x0) * position!.clamp(0.0, 1.0), 104),
        radius: 3.75,
        haloRadius: 5.75,
      );
    }
  }

  @override
  bool shouldRepaint(_MediumStripes o) => o.position != position;
}

// ── Medium/20 ────────────────────────────────────────────────────────────

class ScaleBand {
  const ScaleBand(this.label, this.range, this.color);
  final String label, range;
  final Color color;
}

class SegmentScaleTile extends StatelessWidget {
  const SegmentScaleTile({
    super.key,
    required this.title,
    required this.value,
    required this.lead,
    required this.verdict,
    required this.bands,
    this.marker,
    this.glow = GlowRecipes.m20,
    this.onTap,
    this.semanticLabel,
  });

  final String title, value;

  /// "your weight is" and "Overweight".
  final String lead, verdict;

  /// Four bands, left to right.
  final List<ScaleBand> bands;

  /// 0…1 across the scale; null = no marker.
  final double? marker;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final label = F.tileLabel.copyWith(fontWeight: FontWeight.w400);
    return GlowTile(
      size: TileSize.medium,
      glow: glow,
      onTap: onTap,
      semanticLabel: semanticLabel ?? '$title, $value, $lead $verdict',
      children: [
        TileText(title, x: 18.75, baseline: 35.75, style: F.tileTitle),
        const TileIcon(
          Icons.info_outline,
          center: Offset(317.5, 30.5),
          size: 19,
        ),
        DotValue(x: 20, baseline: 82, value: value),
        TileText(
          lead,
          x: 103.5,
          baseline: 82,
          style: label,
          color: TileInk.secondary,
        ),
        TileText(verdict, x: 182.5, baseline: 82, style: label),
        Positioned.fill(
          child: CustomPaint(
            painter: _Scale([for (final b in bands) b.color], marker),
          ),
        ),
        for (var i = 0; i < bands.length && i < 4; i++) ...[
          Positioned(
            left: 21.0 + 80.75 * i,
            top: 130,
            width: 6,
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bands[i].color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          TileText(
            bands[i].label,
            x: 30.75 + 80.75 * i,
            baseline: 132,
            style: F.tileTiny,
            color: TileInk.unit,
          ),
          TileText(
            bands[i].range,
            x: 31.75 + 80.75 * i,
            baseline: 142,
            style: F.tileTiny.copyWith(fontWeight: FontWeight.w400),
            color: TileInk.soft,
          ),
        ],
      ],
    );
  }
}

class _Scale extends CustomPainter {
  const _Scale(this.colors, this.marker);
  final List<Color> colors;
  final double? marker;

  @override
  void paint(Canvas canvas, Size size) {
    const x0 = 20.0, x1 = 328.0, gap = 2.0;
    final n = colors.length;
    if (n == 0) return;
    final w = (x1 - x0 - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final l = x0 + i * (w + gap);
      canvas.drawRect(Rect.fromLTWH(l, 100, w, 8), Paint()..color = colors[i]);
    }
    if (marker != null) {
      final x = x0 + (x1 - x0) * marker!.clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(x - 1, 96, 2, 16),
        Paint()..color = C.markerGrey,
      );
    }
  }

  @override
  bool shouldRepaint(_Scale o) => o.colors != colors || o.marker != marker;
}
