// The day's plan: "How am I + what to do". The design has no PNG for it, so
// it is built from the tile vocabulary on a full-width glow panel: an
// eyebrow with the basis, the headline in large type, one sentence of why,
// the numbers behind it as chips, and up to three actions.
//
// It renders whatever the plan says (domain/today_plan.dart); no copy is
// written here except the basis labels and the empty-actions line.

import 'package:flutter/material.dart';

import '../../domain/today_plan.dart';
import '../components/bento.dart';
import '../components/pressable.dart';
import '../tokens/tokens.dart';

class PlanTile extends StatelessWidget {
  const PlanTile({super.key, required this.plan, this.onOpen});

  final TodayPlan plan;

  /// Opens a route named by an evidence chip or an action.
  final void Function(String route)? onOpen;

  /// The glow follows the day's state.
  static GlowRecipe glowFor(DayState s) => switch (s) {
    DayState.ready => GlowRecipes.l8,
    DayState.steady => GlowRecipes.l1,
    DayState.easy => GlowRecipes.l7,
    DayState.rest => GlowRecipes.l6,
    DayState.calibrating => GlowRecipes.m5,
    DayState.noData => GlowRecipes.m8,
  };

  /// "Learning your Oura data · Tonight · Early estimate · without HRV".
  /// Re-learning goes first; the rest keep their order.
  static List<String> basis(TodayPlan p) => [
    // The summary may already say it: show re-learning once.
    if (p.relearningSource != null && !p.summaryNamesRelearning)
      'Learning your ${p.relearningSource} data',
    if (p.phase == PlanPhase.tonight) 'Tonight',
    if (p.stale) 'Your data may be out of date',
    if (p.provisional) 'Early estimate',
    for (final g in p.missingInputs) gapLabel(g),
  ];

  /// "without HRV" and friends: the basis of today's scores.
  static String gapLabel(InputGap g) => switch (g) {
    InputGap.hrv => 'without HRV',
    InputGap.heartRate => 'without heart rate',
    InputGap.sleep => 'without sleep data',
    InputGap.respiratoryRate => 'without breathing rate',
    InputGap.skinTemp => 'without skin temperature',
    InputGap.spo2 => 'without blood oxygen',
  };

  static IconData iconFor(PlanActionKind k) => switch (k) {
    PlanActionKind.effort => Icons.bolt_rounded,
    PlanActionKind.sleep => Icons.bedtime_outlined,
    PlanActionKind.recover => Icons.spa_outlined,
    PlanActionKind.wear => Icons.watch_outlined,
    PlanActionKind.sync => Icons.sync_rounded,
    PlanActionKind.checkIn => Icons.favorite_border,
  };

  @override
  Widget build(BuildContext context) {
    final eyebrow = basis(plan);
    return GlowPanel(
      glow: glowFor(plan.state),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow.isNotEmpty) ...[
              Text(
                eyebrow.join(' · '),
                style: F.tileMicro.copyWith(color: TileInk.unit),
              ),
              const SizedBox(height: S.x2),
            ],
            Semantics(
              header: true,
              child: Text(
                plan.headline,
                style: F.tileHeadline.copyWith(color: TileInk.primary),
              ),
            ),
            const SizedBox(height: S.x2),
            Text(
              plan.summary,
              style: F.tileBody.copyWith(
                fontWeight: FontWeight.w400,
                color: TileInk.unit,
              ),
            ),
            if (plan.evidence.isNotEmpty) ...[
              const SizedBox(height: S.x3),
              Wrap(
                spacing: S.x2,
                runSpacing: 0,
                children: [for (final e in plan.evidence) _chip(e)],
              ),
            ],
            const SizedBox(height: S.x2),
            if (plan.actions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: S.x2),
                child: Text(
                  'Nothing to change today.',
                  style: F.tileLabel.copyWith(color: TileInk.secondary),
                ),
              )
            else
              for (final a in plan.actions) _action(a),
          ],
        ),
      ),
    );
  }

  /// [interactive] = false inside an action row: the row itself opens the
  /// route, so its chips are plain labels.
  Widget _chip(PlanEvidence e, {bool interactive = true}) {
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${e.label} ',
            style: F.tileLabel.copyWith(color: TileInk.secondary),
          ),
          TextSpan(
            text: e.value,
            style: F.tileLabel.copyWith(color: TileInk.primary),
          ),
          if (e.comparison != null)
            TextSpan(
              text: ' · ${e.comparison}',
              style: F.tileLabel.copyWith(color: TileInk.secondary),
            ),
        ],
      ),
    );
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: 6),
      decoration: const BoxDecoration(color: C.badge, borderRadius: R.rPill),
      child: text,
    );
    final route = e.route;
    if (!interactive) return pill;
    if (route == null || onOpen == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: pill,
      );
    }
    return Pressable(
      onTap: () => onOpen!(route),
      semanticLabel:
          '${e.label} ${e.value}${e.comparison == null ? '' : ', ${e.comparison}'}',
      child: pill,
    );
  }

  Widget _action(PlanAction a) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: C.badge,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(iconFor(a.kind), size: 18, color: TileInk.primary),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: F.tileBody.copyWith(color: TileInk.primary),
                ),
                const SizedBox(height: 2),
                Text(
                  a.why,
                  style: F.tileLabel.copyWith(
                    fontWeight: FontWeight.w400,
                    color: TileInk.secondary,
                  ),
                ),
                if (a.evidence.isNotEmpty) ...[
                  const SizedBox(height: S.x2),
                  Wrap(
                    spacing: S.x2,
                    runSpacing: S.x2,
                    children: [
                      for (final e in a.evidence) _chip(e, interactive: false),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (a.route != null && onOpen != null)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: S.x2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: TileInk.secondary,
              ),
            ),
        ],
      ),
    );
    final route = a.route;
    if (route == null || onOpen == null) {
      return MergeSemantics(child: row);
    }
    return Pressable(onTap: () => onOpen!(route), child: row);
  }
}
