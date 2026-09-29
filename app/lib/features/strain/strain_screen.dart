// Strain tab: how hard the heart worked on the focused day, against the
// target this morning's recovery suggests; the day's heart rate by zone; time
// in each zone; and every workout with its own strain.
//
// View only: everything comes from strainViewProvider (StrainResult).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart';
import '../../app/insight_card.dart';
import '../../app/note_card.dart';
import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/coach/insight_contracts.dart' show InsightKind;
import '../../domain/repositories.dart' show DataMode;
import '../../domain/results.dart' show NoteSeverity, StrainResult;
import 'strain_view_model.dart';
import 'widgets/strain_explain.dart';
import 'widgets/strain_widgets.dart';

/// Tab body (the shell provides the Scaffold and NavigationBar).
class StrainScreen extends ConsumerWidget {
  const StrainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(strainViewProvider);
    final v = async.value;
    final p = P.of(context);
    final sync = ref.watch(syncStatusProvider).value;
    // First launch: seeding, and nothing stored yet (the provider is still
    // waiting, or it answered "no data" while the sync runs).
    final preparing = PreparingNote.shows(sync, hasData: v != null);
    final waiting = async.isLoading && v == null || preparing;

    final List<Widget> body;
    if (waiting) {
      // The content's own shape: the hero tile first.
      body = [
        const Padding(
          padding: EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
          child: Center(child: TileSkeleton(size: TileSize.large)),
        ),
        if (preparing)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
            child: PreparingNote.fromStatus(sync!, demo: _demo(ref)),
          ),
      ];
    } else if (v != null) {
      body = _content(context, ref, v);
    } else if (async.hasError) {
      body = [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: S.gutter),
          child: StatusCard(
            title: 'Strain could not load',
            body:
                'The data store did not answer. Pull down on Today to sync, '
                'or check Settings → Sync log.',
            tone: StatusTone.warning,
          ),
        ),
      ];
    } else {
      body = [
        EmptyState(
          icon: Icons.bolt_rounded,
          title: 'No strain yet',
          body:
              'Strain needs heart-rate measurements and usable heart-rate '
              'anchors. Workouts and steps alone provide activity context.',
          actionLabel: 'Open data sources',
          onAction: () => Navigator.of(context).pushNamed(Routes.sources),
        ),
      ];
    }

    return SafeArea(
      bottom: false,
      child: ColoredBox(
        color: p.bg,
        child: RefreshIndicator(
          onRefresh: () => ref.read(healthRepositoryProvider).syncNow(),
          child: ListView(
            key: const PageStorageKey('strain'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: S.x10),
            children: [
              ScreenHeader(
                title: 'Strain',
                actions: [
                  AppIconButton(
                    icon: Icons.info_outline_rounded,
                    semanticLabel: 'How strain is calculated',
                    onTap: v == null || !v.hasData
                        ? null
                        : () => showStrainExplain(context, v),
                  ),
                ],
                below: waiting
                    ? const DaySwitcherSkeleton()
                    : v == null
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: DaySwitcher(
                          date: v.date,
                          latest: v.latest,
                          today: v.today,
                          onShift: (d) => shiftStrainDay(ref, d, v.latest),
                        ),
                      ),
              ),
              ...body,
            ],
          ),
        ),
      ),
    );
  }

  static bool _demo(WidgetRef ref) {
    try {
      return ref.watch(dataModeProvider) == DataMode.demo;
    } catch (_) {
      return true;
    }
  }

  List<Widget> _content(BuildContext context, WidgetRef ref, StrainView v) {
    Widget pad(Widget w) => Padding(
      padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
      child: w,
    );
    if (!v.hasData) {
      return [
        const EmptyState(
          icon: Icons.event_busy_rounded,
          title: 'Nothing recorded this day',
          body:
              'Your tracker sent no heart rate, workouts or steps for this '
              'date. Step to another day.',
        ),
      ];
    }
    final s = v.strain;
    return [
      InsightFeed(
        date: v.date,
        kinds: const {InsightKind.strain},
        hostRoute: Routes.strain,
        padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x4),
      ),
      pad(
        Center(child: strainStateTile(v, () => showStrainExplain(context, v))),
      ),
      for (final n in v.notes)
        if (n.severity == NoteSeverity.warning) pad(noteCard(context, n)),
      pad(
        StrainHeroCard(
          key: ValueKey('strain-hero-${v.date}'),
          view: v,
          onExplain: () => showStrainExplain(context, v),
        ),
      ),
      if (s != null && !v.noInput) pad(Center(child: zoneTile(s))),
      pad(
        Align(
          alignment: Alignment.centerLeft,
          child: AskAboutThis(screen: 'strain', date: v.date),
        ),
      ),
      if (s != null && !v.noInput) ...[
        pad(
          AppCard(
            child: ZoneTimeline(
              title: 'Heart rate by zone',
              samples: v.samples,
              start: v.windowStart!,
              end: v.windowEnd!,
              zoneFloors: v.zoneFloors,
              workouts: v.workoutSpans,
              rest: v.sleepSpans,
              emptyMessage: 'No heart-rate samples for this day',
            ),
          ),
        ),
        pad(ZoneMinutesCard(strain: s, floors: v.zoneFloors)),
      ],
      if (v.workouts.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x3),
          child: SectionHeader(title: 'Workouts'),
        ),
        for (final w in v.workouts) pad(WorkoutCard(row: w)),
      ] else if (!v.noInput)
        pad(const AppCard(tone: CardTone.inset, child: _NoWorkouts())),
      for (final n in v.notes)
        if (n.severity != NoteSeverity.warning) pad(noteCard(context, n)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.gutter),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'How strain is calculated',
            kind: AppButtonKind.quiet,
            icon: Icons.functions_rounded,
            onTap: () => showStrainExplain(context, v),
          ),
        ),
      ),
    ];
  }
}

class _NoWorkouts extends StatelessWidget {
  const _NoWorkouts();

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Row(
      children: [
        Icon(Icons.directions_run_rounded, size: 18, color: p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child: Text(
            'No workouts recorded. Strain still counts every minute your '
            'heart rate was up.',
            style: F.bodySm.copyWith(color: p.ink2),
          ),
        ),
      ],
    );
  }
}

/// Large/6 filled from the day: the strain arc to 21 with its knob, the
/// target under the number, and the day's calories and active minutes. With
/// no heart rate there is no score: the arc stays empty and the caption
/// lists what was measured.
ArcStateTile strainStateTile(StrainView v, VoidCallback onTap) {
  final s = v.strain;
  final scored = !v.noInput;
  final kcal = v.workouts.fold<double>(
    0,
    (a, w) => a + (w.workout.calories ?? 0),
  );
  final active = s == null
      ? 0.0
      : s.zoneMinutes.skip(1).fold<double>(0, (a, m) => a + m);
  final t = v.target;
  final caption = scored
      ? (t == null ? 'Strain today' : 'Target ${t.toStringAsFixed(1)}')
      : v.activityFacts;
  return ArcStateTile(
    title: 'Strain',
    trailing: longDay(v.date),
    value: scored ? v.strainValue.toStringAsFixed(1) : DotMatrixNumber.missing,
    unit: '',
    caption: caption,
    progress: scored ? (v.strainValue / 21).clamp(0.0, 1.0) : null,
    panels: [
      StatePanel(
        icon: Icons.local_fire_department,
        label: 'Calories',
        value: kcal > 0 ? '${kcal.round()}' : DotMatrixNumber.missing,
        unit: 'kcal',
      ),
      StatePanel(
        icon: Icons.timer_outlined,
        label: 'Active',
        value: scored ? '${active.round()}' : DotMatrixNumber.missing,
        unit: 'min',
      ),
    ],
    onTap: onTap,
    semanticLabel: scored
        ? 'Strain ${v.strainValue.toStringAsFixed(1)} of 21. $caption. '
              'Workout calories ${kcal.round()}, active ${active.round()} '
              'minutes. Opens how strain is calculated.'
        : 'Strain score unavailable. $caption.',
  );
}

/// Medium/16 filled with the day's minutes in four zone groups.
ZoneBarTile zoneTile(StrainResult s) {
  final z = s.zoneMinutes;
  double at(int i) => i < z.length ? z[i] : 0;
  final groups = [
    ('Light', at(0) + at(1)),
    ('Moderate', at(2)),
    ('Hard', at(3)),
    ('Max', at(4)),
  ];
  return ZoneBarTile(
    title: 'Heart rate zones',
    columns: [
      for (final (label, m) in groups) ZoneColumn('${m.round()}', label, m),
    ],
    semanticLabel:
        'Minutes in heart-rate zones: '
        '${groups.map((g) => '${g.$1} ${g.$2.round()}').join(', ')}.',
  );
}
