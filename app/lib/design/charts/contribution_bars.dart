// ContributionBars — how a score was built, input by input.
//
// Each row's TRACK is as long as that input's weight (its maximum possible
// points), and the FILL is the points it actually earned today. So one glance
// answers both "what matters most" and "what pulled today down". Penalties
// are separate rows that subtract. Every number shown is the engine's; this
// widget only lays them out.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/results.dart';
import '../tokens/tokens.dart';

/// One input's contribution.
class Contribution {
  const Contribution({
    required this.label,
    required this.points,
    required this.maxPoints,
    this.detail,
    this.penalty = false,
  });

  final String label;

  /// Points earned (for a penalty: points subtracted, positive).
  final double points;

  /// Points available = weight × 100 (for a penalty: the same as [points]).
  final double maxPoints;

  /// "52 ms · baseline 47 ms".
  final String? detail;
  final bool penalty;
}

class ContributionBars extends StatelessWidget {
  const ContributionBars({
    super.key,
    required this.items,
    required this.color,
    this.total,
    this.totalLabel = 'Score',
    this.semanticsLabel,
  });

  /// From the engine's recovery breakdown (weights already re-normalised for
  /// missing inputs, points = score01 × weight × 100).
  factory ContributionBars.recovery({
    Key? key,
    required List<RecoveryComponent> components,
    List<RecoveryPenalty> penalties = const [],
    required Color color,
    int? score,
    String? semanticsLabel,
  }) => ContributionBars(
    key: key,
    color: color,
    total: score?.toDouble(),
    totalLabel: 'Recovery',
    semanticsLabel: semanticsLabel,
    items: [
      for (final c in components)
        Contribution(
          label: c.label,
          points: c.points,
          maxPoints: c.weight * 100,
          detail: c.detail,
        ),
      for (final p in penalties)
        Contribution(
          label: p.label,
          points: p.points,
          maxPoints: p.points,
          penalty: true,
        ),
    ],
  );

  final List<Contribution> items;

  /// Accent pigment for the fills.
  final Color color;

  /// The final score, shown as a sum line. Null hides it.
  final double? total;
  final String totalLabel;
  final String? semanticsLabel;

  static String _pts(double v) => v.isFinite ? v.round().toString() : '0';

  String _spoken() {
    if (semanticsLabel != null) return semanticsLabel!;
    if (items.isEmpty) return '$totalLabel breakdown: no inputs available';
    return [
      '$totalLabel breakdown',
      for (final i in items)
        i.penalty
            ? '${i.label}: minus ${_pts(i.points)} points'
            : '${i.label}: ${_pts(i.points)} of ${_pts(i.maxPoints)} points',
      if (total != null) 'Total ${_pts(total!)}',
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final widest = items.fold<double>(
      0,
      (m, i) => i.maxPoints.isFinite ? max(m, i.maxPoints) : m,
    );
    final fill = p.mark(color);
    final warn = p.mark(C.recRed);
    return Semantics(
      container: true,
      label: _spoken(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x4),
                child: Text(
                  'No signals came in for this day.',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ),
            for (var k = 0; k < items.length; k++) ...[
              if (k > 0) const SizedBox(height: S.x4),
              _Row(
                item: items[k],
                widest: widest <= 0 ? 1 : widest,
                fill: items[k].penalty ? warn : fill,
                p: p,
              ),
            ],
            if (total != null && items.isNotEmpty) ...[
              const SizedBox(height: S.x4),
              Divider(color: p.line, height: 1),
              const SizedBox(height: S.x3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      totalLabel,
                      style: F.bodySm.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(_pts(total!), style: F.n24.copyWith(color: p.ink)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.widest,
    required this.fill,
    required this.p,
  });
  final Contribution item;
  final double widest;
  final Color fill;
  final P p;

  @override
  Widget build(BuildContext context) {
    final pts = item.points.isFinite ? item.points : 0.0;
    final maxPts = item.maxPoints.isFinite && item.maxPoints > 0
        ? item.maxPoints
        : 1.0;
    final share = (maxPts / widest).clamp(.05, 1.0);
    final filled = (pts / maxPts).clamp(0.0, 1.0);
    final value = item.penalty
        ? '−${ContributionBars._pts(pts)}'
        : '+${ContributionBars._pts(pts)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                item.label,
                style: F.bodySm.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: S.x2),
            Text(
              value,
              style: F.n18.copyWith(color: item.penalty ? fill : p.ink),
            ),
            if (!item.penalty)
              Text(
                ' / ${ContributionBars._pts(maxPts)}',
                style: F.tab(F.cap).copyWith(color: p.ink3),
              ),
          ],
        ),
        const SizedBox(height: S.x2),
        LayoutBuilder(
          builder: (context, box) {
            final full = box.maxWidth.isFinite ? box.maxWidth : 0.0;
            final trackW = full * share;
            return Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: trackW,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.track,
                    borderRadius: R.rPill,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: item.penalty ? 1 : filled,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: R.rPill,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (item.detail != null) ...[
          const SizedBox(height: S.x1 + 2),
          Text(
            item.detail!,
            style: F.tab(F.cap).copyWith(color: p.ink2),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
