// Home-screen widget bridge. The repository pushes the newest day after
// every recompute; the Android providers (AirlogWidgetProvider.kt: Today,
// RecoveryWidgetProvider.kt, PlanWidgetProvider.kt) draw the snapshot
// natively without running Dart. See docs/WIDGETS_PLAN.md.

import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../../../domain/engine/today_planner.dart';
import '../../../domain/repositories.dart';
import '../../../domain/results.dart';
import '../../../domain/today_plan.dart';

/// The plan widget's slice of [TodayPlan]: the eyebrow (basis), headline
/// and the first action. Every string comes from the planner; the widget
/// writes none of its own here.
class WidgetPlan {
  const WidgetPlan({
    required this.state,
    required this.headline,
    required this.until,
    this.eyebrow = const [],
    this.action,
    this.why,
    this.stale = false,
    this.phase = PlanPhase.today,
  });

  final DayState state;
  final String headline;
  final List<String> eyebrow;

  /// The first action's title and why; null when the plan has no action.
  final String? action;
  final String? why;
  final bool stale;
  final PlanPhase phase;

  /// The next planner phase boundary (05:00 or 18:00). After it, the
  /// action was advice for the other phase: the widget drops it.
  final DateTime until;

  factory WidgetPlan.of(TodayPlan p, {required DateTime now}) {
    final first = p.actions.isEmpty ? null : p.actions.first;
    return WidgetPlan(
      state: p.state,
      headline: p.headline,
      eyebrow: basis(p),
      action: first?.title,
      why: first?.why,
      stale: p.stale,
      phase: p.phase,
      until: nextBoundary(now),
    );
  }

  /// The plan's basis line, the same words and order as PlanTile.basis
  /// (lib/design/tiles/plan_tile.dart; test/data/widget_sink_test.dart
  /// checks they match; data/ may not import design/).
  static List<String> basis(TodayPlan p) => [
    if (p.relearningSource != null && !p.summaryNamesRelearning)
      'Learning your ${p.relearningSource} data',
    if (p.phase == PlanPhase.tonight) 'Tonight',
    if (p.stale) 'Your data may be out of date',
    if (p.provisional) 'Early estimate',
    for (final g in p.missingInputs) gapLabel(g),
  ];

  static String gapLabel(InputGap g) => switch (g) {
    InputGap.hrv => 'without HRV',
    InputGap.heartRate => 'without heart rate',
    InputGap.sleep => 'without sleep data',
    InputGap.respiratoryRate => 'without breathing rate',
    InputGap.skinTemp => 'without skin temperature',
    InputGap.spo2 => 'without blood oxygen',
  };

  /// The first planner phase boundary after [now]: 05:00
  /// (TodayPlanner.tonightUntilHour) or 18:00 (tonightFromHour), local.
  static DateTime nextBoundary(DateTime now) {
    final l = now.toLocal();
    for (final day in [0, 1]) {
      for (final h in [
        TodayPlanner.tonightUntilHour,
        TodayPlanner.tonightFromHour,
      ]) {
        final t = DateTime(l.year, l.month, l.day + day, h);
        if (t.isAfter(l)) return t;
      }
    }
    return DateTime(l.year, l.month, l.day + 1, TodayPlanner.tonightUntilHour);
  }

  Map<String, Object?> toJson() => {
    'state': state.name,
    'headline': headline,
    'eyebrow': eyebrow.join(' · '),
    'action': action,
    'why': why,
    'stale': stale,
    'phase': phase.name,
    'until': until.millisecondsSinceEpoch,
  };
}

/// What the widgets show: the SAME day Today shows (the newest day with
/// data; QA-08), marked [stale] when that day isn't today, so a widget
/// never shows yesterday's numbers as today's.
class WidgetSnapshot {
  const WidgetSnapshot({
    this.date,
    this.recovery,
    this.zone,
    this.strain,
    this.sleepMinutes,
    this.demo = false,
    this.stale = false,
    this.quality = const [],
    this.recoveryStatus = noData,
    this.recoveryBasis = const [],
    this.strainTarget,
    this.strainEstimated = false,
    this.sleepPerformance,
    this.plan,
  });
  final String? date;
  final int? recovery;
  final String? zone;
  final double? strain;
  final double? sleepMinutes;
  final bool demo;
  final List<String> quality;

  /// The day shown is not [today] (no data for today yet).
  final bool stale;

  /// Today's Recovery tile status word: Good / Fair / Low, Learning,
  /// No score (features/today/today_screen.dart _recoveryTile).
  final String recoveryStatus;

  /// "without HRV", "early estimate" or "learning" (one at most): the
  /// score's basis, as Today's Recovery title writes it.
  final List<String> recoveryBasis;

  /// StrainResult.targetStrain and whether the score is an estimate
  /// (StrainMethod.fallback), as Today's Strain caption.
  final double? strainTarget;
  final bool strainEstimated;

  /// SleepAnalysis.performance (Today's Sleep ring value).
  final double? sleepPerformance;

  /// The plan for the plan widget (null without a day).
  final WidgetPlan? plan;

  static const noData = 'No score';

  /// What a dot-matrix slot shows without a number. The dot face has no en
  /// dash (DotMatrixNumber.missing).
  static const missingDots = '--';

  /// [days] newest first; [today] is the phone's current day key. [plan] is
  /// the planner's plan for the same day (the repository builds it).
  factory WidgetSnapshot.fromDays(
    List<DayBundle> days, {
    required bool demo,
    String? today,
    TodayPlan? plan,
    DateTime? now,
  }) {
    final widgetPlan = plan == null || now == null
        ? null
        : WidgetPlan.of(plan, now: now);
    if (days.isEmpty) return WidgetSnapshot(demo: demo, plan: widgetPlan);
    final d = days.first;
    final r = d.result;
    final strain = r.strain;
    final recovery = r.recovery;
    final sleep = r.sleep;
    final calibrating = recovery?.calibrating == true;
    final scored = strain != null && strain.method != StrainMethod.none;
    return WidgetSnapshot(
      date: d.date,
      recovery: calibrating ? null : recovery?.score,
      zone: calibrating ? null : recovery?.zone.name,
      strain: scored ? strain.strain : null,
      sleepMinutes: sleep?.hasData == true && sleep!.sleptMinutes > 0
          ? sleep.sleptMinutes
          : null,
      quality: [
        if (calibrating)
          'learning'
        else if (recovery != null &&
            (!r.calibration.established ||
                recovery.confidence != RecoveryConfidence.high))
          'provisional recovery',
        if (scored && strain.partial) 'partial strain',
      ],
      demo: demo,
      stale: today != null && d.date != today,
      recoveryStatus: recovery == null
          ? noData
          : calibrating
          ? 'Learning'
          : switch (recovery.zone) {
              RecoveryZone.green => 'Good',
              RecoveryZone.yellow => 'Fair',
              RecoveryZone.red => 'Low',
            },
      // One tag at most, by priority, as Today's Recovery tile.
      recoveryBasis: [
        if (recovery?.withoutHrv == true)
          'without HRV'
        else if (recovery != null &&
            ((!calibrating && !r.calibration.established) ||
                recovery.confidence == RecoveryConfidence.low))
          'early estimate'
        else if (plan?.relearningSource != null)
          'learning',
      ],
      strainTarget: scored ? strain.targetStrain : null,
      strainEstimated: scored && strain.method == StrainMethod.fallback,
      sleepPerformance: sleep?.hasData == true ? sleep!.performance : null,
      plan: widgetPlan,
    );
  }

  /// One payload keeps date, mode and values from different updates unmixed.
  Map<String, Object?> toJson({required DateTime updatedAt}) {
    final minutes = sleepMinutes?.round();
    final perf = sleepPerformance?.round();
    return {
      'v': 2,
      'date': date ?? '',
      'recovery': recovery,
      'zone': zone ?? 'none',
      'strain': strain?.toStringAsFixed(1) ?? '–',
      'sleep': minutes == null || minutes <= 0
          ? '–'
          : PlanFormat.hm(minutes.toDouble()),
      'demo': demo,
      'stale': stale,
      'quality': quality.join(' · '),
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      // v2 (additive): the widgets' own slots.
      'recStatus': recoveryStatus,
      'recBasis': recoveryBasis.join(' · '),
      'strainTarget': strainTarget?.toStringAsFixed(1),
      'strainEst': strainEstimated,
      'sleepPerf': perf,
      // Dot-matrix slots: '--' when missing, never an en dash.
      'dots': {
        'recovery': recovery == null ? missingDots : '$recovery',
        'strain': strain == null ? missingDots : strain!.toStringAsFixed(1),
        'sleep': perf == null ? missingDots : '$perf',
      },
      'plan': plan?.toJson(),
    };
  }
}

abstract class WidgetSink {
  Future<void> push(WidgetSnapshot snapshot);
}

class NoopWidgetSink implements WidgetSink {
  const NoopWidgetSink();
  @override
  Future<void> push(WidgetSnapshot snapshot) async {}
}

/// Keys shared with android/app/src/main/kotlin/.../AirlogWidgetRender.kt.
abstract final class WidgetKeys {
  static const snapshot = 'airlog_snapshot_v1'; // atomic JSON snapshot
  static const recovery = 'airlog_recovery'; // int 1..99 or -1
  static const zone = 'airlog_zone'; // green|yellow|red|none
  static const strain = 'airlog_strain'; // String "12.4" or "–"
  static const sleepHours = 'airlog_sleep'; // String "7h 12m" or "–"
  static const date = 'airlog_date'; // yyyy-MM-dd
  static const demo = 'airlog_demo'; // bool
  static const stale = 'airlog_stale'; // bool: the day shown isn't today
  static const updatedAt = 'airlog_updated_at'; // epoch ms
}

class HomeWidgetSink implements WidgetSink {
  const HomeWidgetSink();

  /// The migrated original widget (Today: Recovery, Strain, Sleep). Its
  /// class name is kept so widgets pinned before the upgrade keep working.
  static const String androidProvider =
      'app.airlog.airlog.AirlogWidgetProvider';

  /// Every provider that draws the snapshot; each push updates them all.
  static const List<String> androidProviders = [
    androidProvider,
    'app.airlog.airlog.RecoveryWidgetProvider',
    'app.airlog.airlog.PlanWidgetProvider',
  ];

  @override
  Future<void> push(WidgetSnapshot s) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        WidgetKeys.snapshot,
        jsonEncode(s.toJson(updatedAt: DateTime.now())),
      );
      // Retire pre-upgrade values even when no launcher widget is pinned.
      // The renderer reads only the atomic payload above.
      for (final key in const [
        WidgetKeys.recovery,
        WidgetKeys.zone,
        WidgetKeys.strain,
        WidgetKeys.sleepHours,
        WidgetKeys.date,
        WidgetKeys.demo,
        WidgetKeys.stale,
        WidgetKeys.updatedAt,
      ]) {
        await HomeWidget.saveWidgetData<Object>(key, null, deleteFile: false);
      }
      for (final provider in androidProviders) {
        await HomeWidget.updateWidget(qualifiedAndroidName: provider);
      }
    } catch (_) {
      // No widget host (tests, desktop) or plugin missing in this isolate.
    }
  }
}
