// Feature-private widgets for the Strain tab. Plain values in, no providers.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/engine/strain.dart' show StrainEngine;
import '../../../domain/results.dart';
import '../strain_view_model.dart';

String strain1(double v) => v.toStringAsFixed(1);

/// Target basis and guidance beneath the screen's single primary score tile.
class StrainHeroCard extends StatelessWidget {
  const StrainHeroCard({super.key, required this.view, this.onExplain});
  final StrainView view;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final v = view;
    final s = v.strain;
    final t = v.target;
    final targetBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t == null ? 'No effort target' : 'Target basis',
          style: F.head.copyWith(color: p.ink),
        ),
        const SizedBox(height: S.x1),
        Text(
          t == null && v.recovery != null
              ? 'Recovery does not support an effort target for this day'
              : v.recovery == null
              ? 'No recovery this morning'
              : 'from ${v.recovery} % recovery',
          style: F.tab(F.cap).copyWith(color: p.ink3),
        ),
        const SizedBox(height: S.x3),
        if (!v.noInput)
          StatePill(
            label: switch (v.method) {
              StrainMethod.fallback => 'Estimated',
              _ => 'From heart rate',
            },
            color: v.method == StrainMethod.fallback ? C.amber : C.health,
            icon: v.method == StrainMethod.fallback
                ? Icons.timelapse_rounded
                : Icons.favorite_rounded,
          ),
      ],
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          targetBlock,
          if (!v.noInput && t != null) ...[
            const SizedBox(height: S.x5),
            TargetBar(strain: v.strainValue, target: t),
          ],
          const SizedBox(height: S.x4),
          Text(
            v.recommendation,
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
          if (v.method == StrainMethod.fallback) ...[
            const SizedBox(height: S.x2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.timelapse_rounded,
                    size: 15,
                    color: p.on(C.amber),
                  ),
                ),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(
                    'This stored score used an older estimation method.',
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                ),
              ],
            ),
          ],
          if (s != null && s.trimp != null && !v.noInput) ...[
            const SizedBox(height: S.x2),
            Text(
              'Cross-check: TRIMP ${s.trimp!.round()} (Banister)',
              style: F.tab(F.cap).copyWith(color: p.ink3),
            ),
          ],
        ],
      ),
    );
  }
}

/// Strain on the 0–21 scale with a tick at the target.
class TargetBar extends StatelessWidget {
  const TargetBar({super.key, required this.strain, this.target});
  final double strain;
  final double? target;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final t = target;
    final tick = F.tab(F.over).copyWith(color: p.ink3, letterSpacing: .2);
    return Semantics(
      label: t == null
          ? 'Strain ${strain1(strain)} on a 0 to 21 scale'
          : 'Strain ${strain1(strain)} against a target of ${strain1(t)}, '
                'on a 0 to 21 scale',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 18,
              child: CustomPaint(
                size: Size.infinite,
                painter: _TargetBarPainter(
                  strain: strain,
                  target: t,
                  track: p.track,
                  fill: p.mark(DomainColors.strain),
                  tick: p.ink,
                  knockout: p.card,
                ),
              ),
            ),
            const SizedBox(height: S.x1 + 2),
            LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth.isFinite ? box.maxWidth : 0.0;
                final label = t == null ? null : 'Target ${strain1(t)}';
                return SizedBox(
                  height: 16,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(left: 0, child: Text('0', style: tick)),
                      Positioned(right: 0, child: Text('21', style: tick)),
                      if (label != null)
                        Positioned(
                          left: (t! / 21 * w - 36).clamp(
                            18.0,
                            math.max(18.0, w - 90),
                          ),
                          width: 72,
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            softWrap: false,
                            style: tick.copyWith(color: p.ink2),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetBarPainter extends CustomPainter {
  _TargetBarPainter({
    required this.strain,
    required this.target,
    required this.track,
    required this.fill,
    required this.tick,
    required this.knockout,
  });
  final double strain;
  final double? target;
  final Color track, fill, tick, knockout;

  @override
  void paint(Canvas cv, Size s) {
    if (s.width <= 0) return;
    const barH = 8.0;
    final top = (s.height - barH) / 2;
    final r = const Radius.circular(barH / 2);
    cv.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, top, s.width, barH), r),
      Paint()..color = track,
    );
    final f = (strain / 21).clamp(0.0, 1.0);
    if (f > 0) {
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, math.max(barH, f * s.width), barH),
          r,
        ),
        Paint()..color = fill,
      );
    }
    final t = target;
    if (t != null && t.isFinite) {
      final x = (t / 21).clamp(0.0, 1.0) * s.width;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, s.height / 2),
          width: 3,
          height: s.height,
        ),
        const Radius.circular(1.5),
      );
      cv.drawRRect(rect.inflate(1.5), Paint()..color = knockout);
      cv.drawRRect(rect, Paint()..color = tick);
    }
  }

  @override
  bool shouldRepaint(covariant _TargetBarPainter o) =>
      o.strain != strain ||
      o.target != target ||
      o.fill != fill ||
      o.track != track;
}

/// Minutes in display zones 1–5, the bpm each zone spans, and time below.
class ZoneMinutesCard extends StatelessWidget {
  const ZoneMinutesCard({
    super.key,
    required this.strain,
    required this.floors,
  });
  final StrainResult strain;
  final List<double> floors;

  static final pct = zoneRanges(StrainEngine.displayZoneLowerBounds);

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final z = strain.zoneMinutes;
    final total = z.fold(0.0, (a, b) => a + b);
    final maxHr = strain.maxHrUsed;
    String range(int i) {
      if (floors.length < 5) return '';
      final lo = floors[i].round();
      final hi = i < 4 ? floors[i + 1].round() - 1 : maxHr?.round();
      return hi == null ? '$lo+ bpm' : '$lo–$hi bpm';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChartFrame(
            title: 'Time in zones',
            unit: 'min',
            height: 22,
            series: z,
            semanticsLabel: total <= 0
                ? 'Time in zones: no minutes above zone 1'
                : 'Time in zones. ${[for (var i = 0; i < z.length && i < 5; i++) 'Zone ${i + 1} ${z[i].round()} minutes'].join(', ')}',
            empty: total <= 0
                ? const NoData(message: 'No recorded minutes in zones 1–5')
                : null,
            child: CustomPaint(
              size: Size.infinite,
              painter: ZoneBar([
                for (final m in z) total <= 0 ? 0 : m / total,
              ], p),
            ),
          ),
          const SizedBox(height: S.x4),
          for (var i = 4; i >= 0; i--)
            if (i < z.length)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: p.mark(DomainColors.hrZone(i + 1)),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: S.x3),
                    SizedBox(
                      width: 56,
                      child: Text(
                        'Zone ${i + 1}',
                        style: F.bodySm.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${strain.zonesFromMaxHr ? '' : '${pct[i]} · '}${range(i)}',
                        style: F.tab(F.cap).copyWith(color: p.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      durationWords(z[i]),
                      style: F
                          .tab(F.bodySm)
                          .copyWith(
                            color: z[i] >= .5 ? p.ink : p.ink3,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: S.x2),
          Text(
            'Below zone 1: ${durationWords(strain.restMinutes)}, sleep '
            'included. ${strain.zonesFromMaxHr ? 'Zones use estimated fractions of maximum heart rate' : 'Zones are shares of your heart-rate reserve'}'
            '${strain.restingHrUsed == null || maxHr == null ? '' : ' (resting ${strain.restingHrUsed!.round()}, max ${maxHr.round()} bpm)'}.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}

IconData workoutIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('run')) return Icons.directions_run_rounded;
  if (n.contains('cycl') || n.contains('bike') || n.contains('ride')) {
    return Icons.directions_bike_rounded;
  }
  if (n.contains('walk') || n.contains('hike')) {
    return Icons.directions_walk_rounded;
  }
  if (n.contains('swim')) return Icons.pool_rounded;
  if (n.contains('strength') || n.contains('weight')) {
    return Icons.fitness_center_rounded;
  }
  if (n.contains('yoga')) return Icons.self_improvement_rounded;
  if (n.contains('live')) return Icons.monitor_heart_outlined;
  return Icons.sports_rounded;
}

class WorkoutCard extends StatelessWidget {
  const WorkoutCard({super.key, required this.row});
  final StrainWorkoutRow row;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final w = row.workout;
    final ws = row.strain;
    final zones = ws?.zoneMinutes ?? const <double>[];
    final zt = zones.fold(0.0, (a, b) => a + b);
    // Distance and calories come with the exercise session itself (Health
    // Connect); shown only when the band recorded them.
    final distance = distanceText(w.distanceM);
    final kcal = kcalText(w.calories);
    Widget stat(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: 3),
        Text(value, style: F.n18.copyWith(color: p.ink)),
      ],
    );
    return AppCard(
      semanticLabel: [
        w.name,
        '${clockOf(w.start)} to ${clockOf(w.end)}, ${durationWords(w.durationMinutes)}',
        if (ws != null) 'strain ${strain1(ws.strain)}',
        if (ws?.avgHr != null) 'average ${ws!.avgHr!.round()} bpm',
        if (ws?.peakHr != null) 'peak ${ws!.peakHr!.round()} bpm',
        if (ws?.trimp != null) 'TRIMP ${ws!.trimp!.round()}',
        if (distance != null) 'distance $distance',
        if (kcal != null) '${w.calories!.round()} calories',
        if (row.estimated) 'estimated',
      ].join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: p.wash(DomainColors.strain),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    workoutIcon(w.name),
                    size: 20,
                    color: p.on(DomainColors.strain),
                  ),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.name,
                        style: F.head.copyWith(color: p.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${clockOf(w.start)}–${clockOf(w.end)} · ${durationWords(w.durationMinutes)}',
                        style: F.tab(F.cap).copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                ),
                if (ws != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        strain1(ws.strain),
                        style: F.n32.copyWith(color: p.on(DomainColors.strain)),
                      ),
                      Text('STRAIN', style: F.over.copyWith(color: p.ink3)),
                    ],
                  ),
              ],
            ),
            if (ws != null || distance != null || kcal != null) ...[
              const SizedBox(height: S.x4),
              Wrap(
                spacing: S.x6,
                runSpacing: S.x3,
                children: [
                  if (ws?.avgHr != null)
                    stat('Avg HR', '${ws!.avgHr!.round()}'),
                  if (ws?.peakHr != null)
                    stat('Peak HR', '${ws!.peakHr!.round()}'),
                  if (ws?.trimp != null) stat('TRIMP', '${ws!.trimp!.round()}'),
                  if (distance != null) stat('Distance', distance),
                  if (kcal != null) stat('Calories', kcal),
                ],
              ),
            ],
            if (ws != null) ...[
              if (zt > 0) ...[
                const SizedBox(height: S.x3),
                SizedBox(
                  height: 10,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: ZoneBar([for (final m in zones) m / zt], p),
                  ),
                ),
              ],
            ],
            if (row.estimated) ...[
              const SizedBox(height: S.x3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StatePill(label: 'Estimated', color: C.amber),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: Text(
                      'Too little heart rate inside this workout, so its '
                      'strain comes from its recorded average HR.',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The hero's skeleton in the hero's slot (a loading ring where the ring
