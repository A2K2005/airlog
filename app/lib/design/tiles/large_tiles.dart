// The large tiles. Geometry measured on the PNGs; every label a parameter.
//
//   SleepSummaryTile    Large/1  "Sleep"            three stats, a stage chart
//                                                   on a plate, stage minutes
//   ArcStateTile        Large/6  "Current State"    a big arc gauge and two
//                                                   sub-tiles
//   WeeklyBarsTile      Large/7  "Weekly Progress"  two totals and a week of
//                                                   bars, one highlighted
//   WorkoutSummaryTile  Large/8  "Workout Summary"  three dot-numeral rows,
//                                                   each with a reference

import 'dart:math' show cos, sin, max;

import 'package:flutter/material.dart';

import '../components/tile.dart';
import '../tokens/tokens.dart';
import 'baseline_tiles.dart' show DotValue;
import 'gauge_tiles.dart' show CenteredDotValue;
import 'marks.dart';

/// A tile pictogram: a Material icon of [size] centred on [center].
class TileIcon extends StatelessWidget {
  const TileIcon(
    this.icon, {
    super.key,
    required this.center,
    this.size = 20,
    this.color = TileInk.primary,
  });

  final IconData icon;
  final Offset center;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Positioned(
    left: center.dx - size / 2,
    top: center.dy - size / 2,
    width: size,
    height: size,
    child: ExcludeSemantics(
      child: Icon(icon, size: size, color: color),
    ),
  );
}

// ── Large/1 ──────────────────────────────────────────────────────────────

/// One stage lane of the sleep chart.
enum SleepLane { awake, rem, core, deep }

/// One block of the stage chart: a lane and its span as fractions (0…1) of
/// the night.
class SleepBlock {
  const SleepBlock(this.lane, this.start, this.end);
  final SleepLane lane;
  final double start, end;
}

/// One stage's legend entry and its time asleep, e.g. ("REM", "1", "h",
/// " 4", "min"): numbers and units alternate so each is set in its size.
class SleepStageTotal {
  const SleepStageTotal(this.label, this.parts);
  final String label;

  /// Number, unit, number, unit… ("14", "min").
  final List<String> parts;
}

class SleepSummaryTile extends StatelessWidget {
  const SleepSummaryTile({
    super.key,
    required this.title,
    required this.stats,
    required this.blocks,
    required this.startLabel,
    required this.endLabel,
    required this.totals,
    this.deltaColor = C.recGreen,
    this.glow = GlowRecipes.l1,
    this.onTap,
    this.semanticLabel,
  });

  final String title;

  /// Three (value, label) pairs; the third value is the delta, in green.
  final List<(String, String)> stats;
  final List<SleepBlock> blocks;
  final String startLabel, endLabel;

  /// Four totals: awake, REM, core, deep.
  final List<SleepStageTotal> totals;
  final Color deltaColor;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const laneColors = [C.orange, C.sky, C.sleep, C.indigo];

  @override
  Widget build(BuildContext context) {
    const xs = [19.75, 131.75, 242.5];
    final label = F.tileMicro;
    return GlowTile(
      size: TileSize.large,
      glow: glow,
      onTap: onTap,
      semanticLabel:
          semanticLabel ??
          '$title. ${stats.map((s) => '${s.$2} ${s.$1}').join(', ')}. '
              '${totals.map((t) => '${t.label} ${t.parts.join()}').join(', ')}',
      children: [
        const TileIcon(Icons.bed_outlined, center: Offset(30, 31)),
        TileText(title, x: 47.75, baseline: 36, style: F.tileTitle),
        for (var i = 0; i < stats.length && i < 3; i++) ...[
          TileText(
            stats[i].$1,
            x: xs[i],
            baseline: 81,
            style: F.tileNumber,
            color: i == 2 ? deltaColor : TileInk.primary,
          ),
          TileText(
            stats[i].$2,
            x: i == 0 ? 20 : xs[i],
            baseline: 97,
            style: label,
            color: TileInk.secondary,
          ),
        ],
        Positioned.fill(child: CustomPaint(painter: _SleepPlate(blocks))),
        const TileIcon(
          Icons.bedtime_outlined,
          center: Offset(41.5, 268.5),
          size: 11,
          color: TileInk.tertiary,
        ),
        TileText(
          startLabel,
          x: 52,
          baseline: 272.25,
          style: label,
          color: TileInk.faint,
        ),
        TileText(
          endLabel,
          x: 270,
          baseline: 272.25,
          style: label,
          color: TileInk.faint,
        ),
        const TileIcon(
          Icons.wb_sunny_outlined,
          center: Offset(305.5, 268.5),
          size: 11,
          color: TileInk.tertiary,
        ),
        for (var i = 0; i < totals.length && i < 4; i++) ...[
          Positioned(
            left: 20.0 + 79 * i,
            top: 310,
            width: 6,
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: laneColors[i],
                shape: BoxShape.circle,
              ),
            ),
          ),
          TileText(
            totals[i].label,
            x: 28.0 + 79 * i,
            baseline: 316,
            style: label,
            color: TileInk.secondary,
          ),
          Positioned(
            left: 21.0 + 79 * i,
            top: 0,
            child: Baseline(
              baseline: 339,
              baselineType: TextBaseline.alphabetic,
              child: Text.rich(
                TextSpan(
                  children: [
                    for (var k = 0; k < totals[i].parts.length; k++)
                      TextSpan(
                        text: totals[i].parts[k],
                        style: k.isEven
                            ? F.tileStatus.copyWith(color: TileInk.primary)
                            : F.tileMicro.copyWith(color: TileInk.unit),
                      ),
                  ],
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SleepPlate extends CustomPainter {
  const _SleepPlate(this.blocks);
  final List<SleepBlock> blocks;

  static const _x0 = 36.0, _x1 = 312.0;
  static const _lanes = [132.0, 165.0, 198.0, 231.0];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromLTRBR(20, 116, 328, 291, const Radius.circular(R.panel)),
      Paint()..color = C.plate,
    );
    for (final b in blocks) {
      final x0 = _x0 + (_x1 - _x0) * b.start.clamp(0.0, 1.0);
      final x1 = max(x0 + 4, _x0 + (_x1 - _x0) * b.end.clamp(0.0, 1.0));
      final top = _lanes[b.lane.index];
      final w = x1 - x0;
      canvas.drawRRect(
        RRect.fromLTRBR(
          x0,
          top,
          x1,
          top + 32,
          Radius.circular(w < 32 ? w / 2 : 16),
        ),
        Paint()..color = SleepSummaryTile.laneColors[b.lane.index],
      );
    }
    final tick = Paint()
      ..color = C.axisTick
      ..strokeWidth = 1;
    for (var i = 0; i < 10; i++) {
      final x = 95.5 + i * 17.44;
      canvas.drawLine(Offset(x, 266), Offset(x, 272), tick);
    }
  }

  @override
  bool shouldRepaint(_SleepPlate o) => o.blocks != blocks;
}

// ── Large/6 ──────────────────────────────────────────────────────────────

/// A sub-tile of [ArcStateTile]: an icon and label over a dot value.
class StatePanel {
  const StatePanel({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.iconColor = C.orange,
  });
  final IconData icon;
  final String label, value, unit;
  final Color iconColor;
}

class ArcStateTile extends StatelessWidget {
  const ArcStateTile({
    super.key,
    required this.title,
    required this.trailing,
    required this.value,
    required this.unit,
    required this.caption,
    required this.panels,
    this.progress,
    this.color = C.red600,
    this.glow = GlowRecipes.l6,
    this.onTap,
    this.semanticLabel,
  });

  final String title;

  /// Top-right text (a date).
  final String trailing;

  /// The gauge's number (dots) with its unit and a caption under it.
  final String value, unit, caption;

  /// 0…1 around the arc; null = track only.
  final double? progress;
  final List<StatePanel> panels;
  final Color color;
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
        '$title, $trailing. $caption $value $unit. '
            '${panels.map((p) => '${p.label} ${p.value} ${p.unit}').join(', ')}',
    children: [
      TileText(title, x: 20.25, baseline: 36, style: F.tileTitle),
      TileText(
        trailing,
        right: 328,
        baseline: 35,
        style: F.tileLabel.copyWith(fontWeight: FontWeight.w400),
        color: TileInk.unit,
      ),
      Positioned.fill(child: CustomPaint(painter: _BigArc(progress, color))),
      CenteredDotValue(
        baseline: 191,
        value: value,
        unit: unit,
        style: F.dot40,
        gap: 2,
      ),
      TileText(
        caption,
        centerX: 174,
        baseline: 212,
        style: F.tileLabel.copyWith(fontWeight: FontWeight.w400),
        color: TileInk.tertiary,
      ),
      for (var i = 0; i < panels.length && i < 2; i++) ..._panel(i, panels[i]),
    ],
  );

  List<Widget> _panel(int i, StatePanel p) {
    final x = i == 0 ? 20.0 : 178.0;
    return [
      Positioned(
        left: x,
        top: 243,
        width: 150,
        height: 106,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: C.panelStrong,
            borderRadius: R.rPanel,
          ),
        ),
      ),
      TileIcon(
        p.icon,
        center: Offset(x + 22.5, 267.5),
        size: 14,
        color: p.iconColor,
      ),
      TileText(
        p.label,
        x: x + 33.5,
        baseline: 274,
        style: F.tileBody.copyWith(fontWeight: FontWeight.w400),
      ),
      DotValue(
        x: x + 16,
        baseline: 325,
        value: p.value,
        unit: p.unit,
        unitStyle: F.tileLabel.copyWith(fontWeight: FontWeight.w400),
        unitGap: 2.5,
      ),
    ];
  }
}

class _BigArc extends CustomPainter {
  const _BigArc(this.progress, this.color);
  final double? progress;
  final Color color;

  static const _c = Offset(173.8, 214.2);
  static const _r = 137.0;
  static const _from = -175.4, _to = -4.6;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: _c, radius: _r);
    Paint stroke(double w, Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = c;
    canvas.drawArc(
      rect,
      rad(_from),
      rad(_to - _from),
      false,
      stroke(28, C.arcWell),
    );
    final end = progress == null
        ? _from
        : _from + (_to - _from) * progress!.clamp(0.0, 1.0);
    canvas.drawArc(
      rect,
      rad(end),
      rad(_to - end),
      false,
      stroke(12, C.arcRest),
    );
    if (progress == null) return;
    canvas.drawArc(
      rect,
      rad(_from),
      rad(end - _from),
      false,
      stroke(14, color),
    );
    final k = _c + Offset(cos(rad(end)), sin(rad(end))) * _r;
    canvas.drawCircle(k, 13.5, Paint()..color = C.white);
    canvas.drawCircle(k, 12, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BigArc o) => o.progress != progress || o.color != color;
}

// ── Large/7 ──────────────────────────────────────────────────────────────

class WeeklyBarsTile extends StatelessWidget {
  const WeeklyBarsTile({
    super.key,
    required this.title,
    required this.leadLabel,
    required this.leadValue,
    required this.totals,
    required this.values,
    required this.days,
    this.highlight,
    this.glow = GlowRecipes.l7,
    this.onTap,
    this.semanticLabel,
  });

  final String title;

  /// "Most Active Day:" and "Wednesday".
  final String leadLabel, leadValue;

  /// Two (label, dot value, unit) totals.
  final List<(String, String, String)> totals;

  /// Seven values, oldest first; null = no data that day.
  final List<double?> values;

  /// Seven single-letter labels.
  final List<String> days;

  /// The highlighted day (orange, hatched); null = none.
  final int? highlight;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const _cols = [
    (20.0, 61.0),
    (65.0, 105.0),
    (109.0, 150.0),
    (153.0, 195.0),
    (198.0, 239.0),
    (243.0, 283.0),
    (287.0, 328.0),
  ];

  @override
  Widget build(BuildContext context) {
    final label = F.tileLabel.copyWith(fontWeight: FontWeight.w400);
    return GlowTile(
      size: TileSize.large,
      glow: glow,
      onTap: onTap,
      semanticLabel:
          semanticLabel ??
          '$title. $leadLabel $leadValue. '
              '${totals.map((t) => '${t.$1} ${t.$2} ${t.$3}').join(', ')}',
      children: [
        TileText(title, x: 19.25, baseline: 36, style: F.tileTitle),
        const TileIcon(
          Icons.military_tech,
          center: Offset(25.5, 52.5),
          size: 13,
          color: C.recYellow,
        ),
        // One line, so a longer label pushes the value along.
        Positioned(
          left: 34.75,
          top: 0,
          child: Baseline(
            baseline: 58,
            baselineType: TextBaseline.alphabetic,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$leadLabel ',
                    style: label.copyWith(color: TileInk.secondary),
                  ),
                  TextSpan(
                    text: leadValue,
                    style: F.tileLabel.copyWith(color: TileInk.unit),
                  ),
                ],
              ),
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
        for (var i = 0; i < totals.length && i < 2; i++) ...[
          TileText(
            totals[i].$1,
            x: i == 0 ? 20 : 178,
            baseline: 94,
            style: label,
            color: TileInk.tertiary,
          ),
          DotValue(x: i == 0 ? 19.5 : 178, baseline: 136, value: totals[i].$2),
          TileText(
            totals[i].$3,
            x: i == 0 ? 19.75 : 178,
            baseline: 152,
            style: label,
            color: TileInk.tertiary,
          ),
        ],
        Positioned.fill(
          child: CustomPaint(painter: _WeekBars(values, highlight)),
        ),
        for (var i = 0; i < days.length && i < 7; i++)
          TileText(
            days[i],
            centerX: (_cols[i].$1 + _cols[i].$2) / 2,
            baseline: 341,
            style: F.tileLabel,
            color: TileInk.tertiary,
          ),
      ],
    );
  }
}

class _WeekBars extends CustomPainter {
  const _WeekBars(this.values, this.highlight);
  final List<double?> values;
  final int? highlight;

  static const _bottom = 323.0, _tallest = 187.0;

  @override
  void paint(Canvas canvas, Size size) {
    final vs = values.nonNulls.toList();
    if (vs.isEmpty) return;
    final hi = vs.reduce(max);
    for (var i = 0; i < values.length && i < 7; i++) {
      final v = values[i];
      if (v == null) continue;
      final (x0, x1) = WeeklyBarsTile._cols[i];
      // Linear from the floor: the tallest day reaches y 187; a zero day
      // keeps a stub (the design's shortest bar, y 272, is its smallest day).
      final t = hi <= 0 ? 0.0 : (v / hi).clamp(0.0, 1.0);
      final top = _bottom - (_bottom - _tallest) * t;
      final r = RRect.fromLTRBAndCorners(
        x0,
        top.clamp(_tallest, _bottom - 8),
        x1,
        _bottom,
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      );
      final hot = i == highlight;
      canvas.drawRRect(r, Paint()..color = hot ? C.strain : C.barIdle);
      if (hot) {
        canvas.save();
        canvas.clipRRect(r);
        final hatch = Paint()
          ..color = C.hatch
          ..strokeWidth = 4;
        for (var x = x0 - 150; x < x1 + 10; x += 9) {
          canvas.drawLine(
            Offset(x, _bottom),
            Offset(x + 150, _bottom - 300),
            hatch,
          );
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_WeekBars o) =>
      o.values != values || o.highlight != highlight;
}

// ── Large/8 ──────────────────────────────────────────────────────────────

/// One row of [WorkoutSummaryTile].
class WorkoutRow {
  const WorkoutRow({
    required this.value,
    required this.label,
    this.unit,
    this.refLabel,
    this.refValue,
    this.refUnit,
  });

  /// Dot numerals ("1.820") and the caption under them.
  final String value, label;

  /// A unit set beside the number ("MIN").
  final String? unit;

  /// The right-hand reference: "Target" / "2000" / "Kcal".
  final String? refLabel, refValue, refUnit;
}

class WorkoutSummaryTile extends StatelessWidget {
  const WorkoutSummaryTile({
    super.key,
    required this.title,
    required this.rows,
    this.glow = GlowRecipes.l8,
    this.onTap,
    this.semanticLabel,
  });

  final String title;

  /// Up to three rows.
  final List<WorkoutRow> rows;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final body = F.tileLabel.copyWith(fontWeight: FontWeight.w400);
    const numBase = [107.0, 200.5, 295.0];
    const labBase = [132.0, 226.0, 320.0];
    const refTop = [74.0, 168.0];
    final kids = <Widget>[];
    for (var i = 0; i < rows.length && i < 3; i++) {
      final r = rows[i];
      kids
        ..add(
          DotValue(x: 20, baseline: numBase[i], value: r.value, style: F.dot48),
        )
        ..add(TileText(r.label, x: 20, baseline: labBase[i], style: body));
      if (r.unit != null) {
        kids.add(
          TileText(r.unit!, x: 113.75, baseline: numBase[i], style: body),
        );
      }
      if (r.refLabel != null && i < 2) {
        kids
          ..add(
            Positioned(
              left: 284,
              top: refTop[i] - 7.5,
              width: 6,
              height: 6,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: C.orange,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          )
          ..add(
            TileText(r.refLabel!, right: 328, baseline: refTop[i], style: body),
          )
          ..add(
            TileText(
              r.refValue ?? '',
              right: 328,
              baseline: refTop[i] + 20.75,
              style: body,
            ),
          )
          ..add(
            TileText(
              r.refUnit ?? '',
              right: 328,
              baseline: refTop[i] + 37,
              style: body,
            ),
          );
      }
    }
    return GlowTile(
      size: TileSize.large,
      glow: glow,
      onTap: onTap,
      semanticLabel:
          semanticLabel ??
          '$title. ${rows.map((r) => '${r.label} ${r.value} ${r.unit ?? ''}').join(', ')}',
      children: [
        const TileIcon(Icons.fitness_center, center: Offset(29.5, 30.5)),
        TileText(title, x: 46.75, baseline: 36, style: F.tileTitle),
        ...kids,
      ],
    );
  }
}
