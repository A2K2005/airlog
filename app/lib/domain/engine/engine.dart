// Engine facade — the ONLY entry point data/ calls.
//
// CONTRACT FILE (signatures). The engine owner implements the bodies; the
// signatures below must not change without updating data/.
// Pure Dart: no Flutter or plugin imports anywhere under lib/domain/.
//
// Implementation map (all pure Dart, lib/domain/engine/):
//   day_engine.dart       per-day pipeline + computeRange/computeDay
//   recovery.dart         Pulse RecoveryEngine          (Apache-2.0 port)
//   strain.dart           Pulse StrainEngine            (Apache-2.0 port)
//   strain_fallback.dart  sparse-HR fallback, MET table [ours]
//   trimp.dart            Banister TRIMP                [ours]
//   sleep.dart            Pulse SleepEngine             (Apache-2.0 port)
//   health_monitor.dart   Pulse HealthMonitor           (Apache-2.0 port)
//   pulse_age.dart        Pulse AgeEngine + AgeNorms    (Apache-2.0 port)
//   journal.dart          Pulse JournalEngine           (Apache-2.0 port)
//   baselines.dart        definition-keyed baselines    [ours]
//   readiness.dart        Plews lnRMSSD SWC             [ours]
//   hrv_tools.dart        RR artefacts, RMSSD, Baevsky, HRR-60 [ours]
//   load_and_trends.dart  ACWR, Mann-Kendall/Sen, TrendMath (Pulse port)
//   notes.dart            StatusNote texts              [ours]
//   today_planner.dart    TodayPlan rules ("the one job") [ours]
//   source_apps.dart      HC origin package → app name  [ours]
//   stats.dart / inputs.dart  statistics, sanitised input reads

import '../models.dart';
import '../repositories.dart';
import '../results.dart';
import '../today_plan.dart';
import 'day_engine.dart';
import 'hrv_tools.dart';
import 'inputs.dart';
import 'journal.dart';
import 'load_and_trends.dart';
import 'stats.dart';
import 'strain.dart';
import 'today_planner.dart';
import 'trimp.dart';

class SleepConfig {
  const SleepConfig({
    this.baselineNeedMinutes = 456,
    this.debtRepayFraction = 0.30,
    this.maxDebtMinutes = 300,
    this.maxDebtGainPerNightMinutes = 180,
    this.strainNeedBoostMaxMinutes = 45,
  });
  final double baselineNeedMinutes;
  final double debtRepayFraction;
  final double maxDebtMinutes;
  final double maxDebtGainPerNightMinutes;
  final double strainNeedBoostMaxMinutes;
}

class EngineConfig {
  const EngineConfig({
    this.profile = const UserProfile(),
    this.sleep = const SleepConfig(),
    this.strainTau = 450,
    this.baselineWindowDays = 30,
    this.calibrationNeedNights = 14,
    this.appNames = const {},
    this.notShared = const {},
  });
  final UserProfile profile;
  final SleepConfig sleep;
  final double strainTau;
  final int baselineWindowDays;
  final int calibrationNeedNights;

  /// [ours, additive 2026-09-29] Display names for Health Connect origin
  /// packages that the known-app table (source_apps.dart) lacks, e.g. the
  /// platform app label. Used only in StatusNote copy; never in scoring.
  final Map<String, String> appNames;

  /// [ours, additive 2026-09-29] Metric code ('hrv' | 'rhr') → origin
  /// packages persisted with that metric's source choice as never sharing
  /// it (OriginPlan.notShared: observed from the raw rows, never a package
  /// list). Such an app counts as "doesn't share" from its first night, so
  /// after a switch to it the sleeping-HR stand-in applies at once instead
  /// of after [DayEngine.notSharedNights] nights. Empty = observe from the
  /// records alone.
  final Map<String, Set<String>> notShared;
}

abstract final class Engine {
  /// Computes every day in [records] in date order, carrying sleep debt and
  /// baselines forward. [records] may be unsorted and may have gaps; each
  /// day only sees days strictly before it as history.
  ///
  /// [now] is injected for testability (age, "today is partial").
  ///
  /// Duplicate dates: the last record for a date (in input order) wins.
  /// Records whose date is not a valid "yyyy-MM-dd" key are skipped.
  static List<DayResult> computeRange(
    List<DayRecord> records, {
    EngineConfig config = const EngineConfig(),
    DateTime? now,
  }) {
    return DayEngine.computeRange(records, config, now ?? DateTime.now());
  }

  /// Computes one day given its history (days strictly before it, any
  /// order) and the previous day's result (for sleep-debt carry; null on the
  /// first day).
  ///
  /// [historyResults] (optional, additive): already computed results of
  /// history days. Only Pulse Age reads them (30 days of sleep performance);
  /// without them it approximates those nights against the baseline need.
  /// Passing them makes `computeDay` identical to the matching day of
  /// [computeRange].
  static DayResult computeDay(
    DayRecord today, {
    required List<DayRecord> history,
    DayResult? previous,
    EngineConfig config = const EngineConfig(),
    DateTime? now,
    List<DayResult> historyResults = const [],
  }) {
    return DayEngine.computeDay(
      today,
      history,
      previous,
      config,
      now ?? DateTime.now(),
      historyResults,
    );
  }

  /// Live strain for an in-progress workout (BLE HR at ~1 Hz). Returns the
  /// 0..21 strain accumulated so far and minutes per zone.
  ///
  /// Pulse's accumulator (dt clamped 0..5 min) with the first sample counted
  /// for its own spacing instead of a full minute; samples after [now] are
  /// ignored.
  ///
  /// [restingHr] null (or not finite): %HRmax zones (Swain 1994), never an
  /// assumed resting HR. [additive 2026-09-29: was a non-null double]
  static WorkoutStrain liveWorkoutStrain(
    List<HrSample> samples, {
    required double? restingHr,
    double? maxHr,
    EngineConfig config = const EngineConfig(),
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final clean = [
      for (final s in Inputs.cleanHr(samples))
        if (!s.t.isAfter(at)) s,
    ];
    final trueMax = maxHr ?? DayEngine.profileMaxHr(config.profile, at)?.value;
    final anchors = StrainEngine.zoneAnchors(
      restingHr: restingHr,
      maxHr: trueMax,
    );
    final minor =
        config.profile.birthYear != null &&
        at.year - config.profile.birthYear! < 18;
    if (anchors == null || clean.isEmpty || minor) {
      return const WorkoutStrain(
        workoutId: 'live',
        strain: 0,
        zoneMinutes: [0, 0, 0, 0, 0],
        method: StrainMethod.none,
      );
    }
    final known =
        restingHr != null &&
        restingHr.isFinite &&
        restingHr >= 25 &&
        restingHr <= 150;
    final rhr = anchors.$1;
    final zoneMax = anchors.$2;
    final firstDt = clean.length >= 2
        ? Stats.clamp(
            clean[1].t.difference(clean[0].t).inMicroseconds / 6e7,
            0,
            1,
          )
        : 0.0;
    final acc = StrainEngine.accumulate(
      clean,
      restingHr: rhr,
      maxHr: zoneMax,
      firstDt: firstDt,
    );
    return WorkoutStrain(
      workoutId: 'live',
      strain: StrainEngine.strainFromRaw(acc.raw, tau: config.strainTau),
      zoneMinutes: acc.displayZones,
      avgHr: acc.avgHr,
      peakHr: acc.peakHr,
      // TRIMP is defined on heart-rate reserve: none without a resting HR.
      trimp: known
          ? Trimp.fromSamples(
              clean,
              restingHr: rhr,
              maxHr: zoneMax,
              sex: config.profile.sex,
              firstDt: firstDt,
            )
          : null,
      method: StrainMethod.hrZones,
    );
  }

  /// Heart-rate recovery: bpm drop 60 s after [workoutEnd] (Cole 1999).
  /// Null if there is no sample within ±10 s of end and end+60 s.
  static double? hrr60(List<HrSample> samples, DateTime workoutEnd) {
    return HrvTools.hrr60(samples, workoutEnd);
  }

  /// RMSSD (ms) from RR intervals (ms) of an on-demand HRV check, after
  /// artefact filtering. Null if fewer than 30 clean intervals.
  static double? rmssdFromRr(List<double> rrMs) {
    return HrvTools.rmssd(rrMs);
  }

  /// Baevsky stress index from RR intervals (ms). Null if < 60 intervals.
  /// (Counted after the same artefact filter as [rmssdFromRr].)
  static double? baevskyStress(List<double> rrMs) {
    return HrvTools.baevsky(rrMs);
  }

  /// Karvonen zone (1..5) for [bpm], or 0 for below zone 1 (rest).
  /// Zones are 50-60 / 60-70 / 70-80 / 80-90 / 90-100 % of heart-rate
  /// reserve; 0 also when the reserve is not positive.
  static int zoneFor(
    double bpm, {
    required double restingHr,
    required double maxHr,
  }) {
    final f = StrainEngine.hrrFraction(bpm, restingHr, maxHr);
    return f == null ? 0 : StrainEngine.displayZone(f);
  }

  /// Age-predicted max HR used when no override is set.
  /// Override if plausible (100–240 bpm), else Tanaka 208 − 0.7·age.
  static double maxHrFor(UserProfile p, DateTime now) {
    return DayEngine.maxHrFor(p, now);
  }

  /// A declared profile anchor, without the legacy age-30 default.
  static double? knownMaxHrFor(UserProfile p, DateTime now) =>
      DayEngine.profileMaxHr(p, now)?.value;

  /// Journal factor → next-day recovery correlations (Pulse JournalEngine):
  /// ≥5 days with and ≥5 without; Welch SE; strongest |delta| first.
  static List<FactorInsight> journalInsights(
    Map<String, JournalEntry> entries,
    Map<String, int> recoveryByDay,
  ) {
    return JournalEngine.insights(entries, recoveryByDay);
  }

  /// Acute:chronic workload ratio from daily strain (7 d / 28 d means).
  /// Null with < 14 days of strain history.
  static TrainingLoad? trainingLoad(
    Map<String, double> strainByDay,
    String asOf,
  ) {
    return TrainingLoadEngine.compute(strainByDay, asOf);
  }

  /// Significance-tested trend over [values] (oldest first, nulls = gaps).
  static TrendResult trend(List<double?> values) {
    return TrendEngine.compute(values);
  }

  /// [additive 2026-09-29] "How am I + what to do" for the newest day:
  /// the state in plain words, one sentence of why and 0–3 actions. See
  /// today_planner.dart for the rules. [now] comes from clockProvider.
  static TodayPlan planToday(
    DayBundle today, {
    SyncStatus? sync,
    required DateTime now,
    Map<String, String> appNames = const {},
    bool use24h = true,
  }) {
    return TodayPlanner.plan(
      today: today,
      sync: sync,
      now: now,
      appNames: appNames,
      use24h: use24h,
    );
  }
}
