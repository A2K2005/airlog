// Strain view-model: the focused day's StrainResult, mapped for the screen.
//
// Every number shown comes from the engine's StrainResult. The only thing
// derived here is the zone floors in bpm for the timeline, computed from the
// SAME resting / max HR the engine used and the engine's own display-zone
// bounds, so the chart's colours agree with the engine's minutes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/day_key.dart';
import '../../domain/engine/strain.dart' show StrainEngine;
import '../../domain/models.dart';
import '../../domain/results.dart';
import '../../app/platform_services.dart';

/// One workout row: the recorded session joined with its computed strain.
class StrainWorkoutRow {
  const StrainWorkoutRow({required this.workout, this.strain});
  final Workout workout;
  final WorkoutStrain? strain;

  /// Strain for this workout was estimated from recorded average HR,
  /// not measured from heart-rate samples inside it.
  bool get estimated => strain?.method == StrainMethod.fallback;
}

enum TargetVerdict { none, under, onTarget, over }

class StrainView {
  const StrainView({
    required this.date,
    required this.latest,
    required this.today,
    required this.hasData,
    this.strain,
    this.recovery,
    this.zoneFloors = const [],
    this.samples = const [],
    this.windowStart,
    this.windowEnd,
    this.workoutSpans = const [],
    this.sleepSpans = const [],
    this.workouts = const [],
    this.notes = const [],
    this.profile = const UserProfile(),
  });

  final String date;
  final String latest;
  final String today;

  /// False when the store has nothing for [date].
  final bool hasData;
  final StrainResult? strain;
  final int? recovery;

  /// bpm where display zones 1…5 begin (Karvonen, engine's HR values).
  final List<double> zoneFloors;
  final List<HrSample> samples;
  final DateTime? windowStart, windowEnd;
  final List<(DateTime, DateTime)> workoutSpans, sleepSpans;
  final List<StrainWorkoutRow> workouts;

  /// Engine notes about strain / heart rate / steps for this day.
  final List<StatusNote> notes;
  final UserProfile profile;

  bool get isToday => date == today;

  /// Strain without heart rate: what was measured ("2 workouts · 8,400
  /// steps"), never a 0–21 number. [redesign]
  String get activityFacts {
    final w = workouts.length;
    final st = strain?.steps;
    final parts = [
      if (w > 0) '$w ${w == 1 ? 'workout' : 'workouts'}',
      if (st != null && st > 0) '$st steps',
    ];
    return parts.isEmpty
        ? samples.isEmpty
              ? 'No heart rate or activity'
              : 'Heart rate recorded; score unavailable'
        : parts.join(' · ');
  }

  StrainMethod get method => strain?.method ?? StrainMethod.none;
  bool get noInput => strain == null || method == StrainMethod.none;

  double get strainValue => strain?.strain ?? 0;
  double? get target => strain?.targetStrain;

  TargetVerdict get verdict {
    final t = target;
    if (t == null || noInput) return TargetVerdict.none;
    final d = t - strainValue;
    if (d.abs() <= 1) return TargetVerdict.onTarget;
    return d > 0 ? TargetVerdict.under : TargetVerdict.over;
  }

  /// The one-line recommendation under the ring.
  String get recommendation {
    final t = target;
    if (noInput) return 'Nothing to score for this day yet.';
    if (t == null) {
      return 'Recovery does not support an effort target for this day.';
    }
    final d = (t - strainValue).abs().toStringAsFixed(1);
    final tt = t.toStringAsFixed(1);
    final rec = recovery == null ? '' : ' for a $recovery % recovery';
    if (isToday) {
      return switch (verdict) {
        TargetVerdict.under => 'Room for about $d more strain today$rec.',
        TargetVerdict.onTarget => 'On target$rec. Anything more is extra.',
        TargetVerdict.over =>
          '$d over today’s target of $tt. An easy evening leaves room to '
              'recover.',
        TargetVerdict.none => '',
      };
    }
    return switch (verdict) {
      TargetVerdict.under => 'Finished $d under the target of $tt.',
      TargetVerdict.onTarget => 'Finished on target ($tt).',
      TargetVerdict.over => 'Finished $d over the target of $tt.',
      TargetVerdict.none => '',
    };
  }
}

/// Zone floors (bpm) for display zones 1…5 from the engine's own bounds.
List<double> zoneFloorsFor(double restingHr, double maxHr) => [
  for (final f in StrainEngine.displayZoneLowerBounds)
    restingHr + f * (maxHr - restingHr),
];

final strainViewProvider = FutureProvider<StrainView?>((ref) async {
  ref.watch(revisionProvider.select((r) => r.value));
  final date = await ref.watch(focusedDateProvider.future);
  final latest = await ref.watch(latestDateProvider.future);
  if (date == null || latest == null) return null;
  final repo = ref.watch(healthRepositoryProvider);
  final now = ref.watch(currentTimeProvider);
  final today = DayKey.of(now);
  final bundle = await repo.day(date);
  UserProfile profile;
  try {
    profile = await repo.profile();
  } catch (_) {
    profile = const UserProfile();
  }
  if (bundle == null) {
    return StrainView(
      date: date,
      latest: latest,
      today: today,
      hasData: false,
      profile: profile,
    );
  }
  final rec = bundle.record;
  final s = bundle.result.strain;
  final rhr = s?.restingHrUsed;
  final maxHr = s?.maxHrUsed;
  // The whole calendar day, also for today: the empty right-hand side is
  // honest (the day is not over), and the axis stays the same every day.
  final start = DayKey.start(date);
  final end = DayKey.end(date);
  final byId = {
    for (final w in s?.workouts ?? const <WorkoutStrain>[]) w.workoutId: w,
  };
  final workouts = [
    for (final w in [
      ...rec.workouts,
    ]..sort((a, b) => a.start.compareTo(b.start)))
      StrainWorkoutRow(workout: w, strain: byId[w.id]),
  ];
  const strainNoteMetrics = {'strain', 'hr', 'steps'};
  return StrainView(
    date: date,
    latest: latest,
    today: today,
    hasData: true,
    strain: s,
    recovery: bundle.result.recovery?.score,
    zoneFloors: StrainEngine.displayFloors(restingHr: rhr, maxHr: maxHr),
    samples: rec.hrSamples,
    windowStart: start,
    windowEnd: end,
    workoutSpans: [for (final w in rec.workouts) (w.start, w.end)],
    sleepSpans: [
      for (final sl in rec.sleepSessions)
        (
          sl.start.isBefore(start) ? start : sl.start,
          sl.end.isAfter(end) ? end : sl.end,
        ),
    ],
    workouts: workouts,
    notes: [
      for (final n in bundle.result.notes)
        if (strainNoteMetrics.contains(n.metric)) n,
    ],
    profile: profile,
  );
}, retry: noRetry);

/// Day stepping for the DaySwitcher (shares Today/Sleep's selected date).
void shiftStrainDay(WidgetRef ref, int by, String latest) =>
    ref.read(selectedDateProvider.notifier).shift(by, latest: latest);
