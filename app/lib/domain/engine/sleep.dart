// Ported from Luraxx/pulse Core/Metrics/SleepEngine.swift (Apache-2.0, see
// third_party/pulse/NOTICE). Changes: Dart port; the per-night step of
// `analyze` is factored out ([SleepEngine.analyzeNight]) so the Engine can
// carry debt day by day via the previous DayResult; SleepConfig comes from
// engine.dart; adds the need breakdown (baseline / debt share / strain
// boost, summing to the clamped need); corrupt minute values read as 0.

import 'dart:math' as math;

import '../day_key.dart';
import '../models.dart';
import '../results.dart';
import 'engine.dart';
import 'hr_series.dart';
import 'inputs.dart';
import 'stats.dart';

/// Bed and wake clock times of one main sleep, in minutes since 12:00
/// (Pulse's shifted clock, SleepEngine.swift:191-196).
class BedWake {
  const BedWake(this.bed, this.wake);
  final double bed;
  final double wake;
}

/// One night's analysis plus what the next night needs.
class SleepNight {
  const SleepNight(this.analysis, this.bedWake);
  final SleepAnalysis analysis;

  /// This night's bed/wake (null without a main sleep), to append to the
  /// consistency window.
  final BedWake? bedWake;
}

abstract final class SleepEngine {
  /// Consistency window length (Pulse SleepEngine.swift:163).
  static const int consistencyWindow = 4;

  /// Strain above which the next night needs more sleep, and the span over
  /// which the boost ramps to its maximum: clamp((strain − from) / span, 0,
  /// 1). Pulse SleepEngine.swift:132-135.
  static const double strainBoostFrom = 8;
  static const double strainBoostSpan = 13;

  /// The need is kept within [baseline − below, baseline + above] minutes.
  /// Pulse SleepEngine.swift:76-78.
  static const double needBelowBaselineMinutes = 30;
  static const double needAboveBaselineMinutes = 150;

  /// Average bed/wake shift (minutes) at which consistency reaches 0 %.
  /// Pulse SleepEngine.swift:160.
  static const double consistencyZeroMinutes = 90;

  /// Calendar days of wake times behind tonight's bedtime (AppModel.swift
  /// :337-353; used by DayEngine).
  static const int bedtimeWakeDays = 7;

  /// clamp((strain − [strainBoostFrom]) / [strainBoostSpan], 0, 1) × max.
  static double strainBoost(double strain, SleepConfig config) =>
      Stats.clamp((strain - strainBoostFrom) / strainBoostSpan, 0, 1) *
      config.strainNeedBoostMaxMinutes;

  /// Need before debt and strain. Pulse SleepEngine.swift:76-78 / :132-135:
  /// need = baseline + debt · repayFraction + strainBoost, clamped to
  /// [baseline − 30, baseline + 150]; strainBoost = clamp((strain − 8)/13,
  /// 0, 1) · 45.
  static SleepNeedBreakdown need(
    double debtMinutes,
    double strain,
    SleepConfig config,
  ) {
    final strainBoost = SleepEngine.strainBoost(strain, config);
    final debtShare = debtMinutes * config.debtRepayFraction;
    final base = config.baselineNeedMinutes;
    final total = Stats.clamp(
      base + debtShare + strainBoost,
      base - needBelowBaselineMinutes,
      base + needAboveBaselineMinutes,
    );
    // [ours] Parts that sum to the clamped total (trim debt, then strain).
    var extra = total - base;
    final debtPart = math.min(debtShare, math.max(0, extra)).toDouble();
    extra -= debtPart;
    final strainPart = math.min(strainBoost, math.max(0, extra)).toDouble();
    return SleepNeedBreakdown(
      baselineMinutes: total - debtPart - strainPart,
      debtMinutes: debtPart,
      strainMinutes: strainPart,
    );
  }

  static double needTotal(SleepNeedBreakdown b) =>
      b.baselineMinutes + b.debtMinutes + b.strainMinutes;

  /// Recommendation for the coming night. Pulse SleepEngine.swift:70-101.
  static BedtimeRecommendation bedtimeRecommendation({
    required double currentDebtMinutes,
    required double strainToday,
    required List<DateTime> recentWakeTimes,
    SleepConfig config = const SleepConfig(),
  }) => bedtimeFromWakeMinutes(
    currentDebtMinutes: currentDebtMinutes,
    strainToday: strainToday,
    wakeMinutes: [for (final t in recentWakeTimes) clockMinutes(t)],
    config: config,
  );

  /// [bedtimeRecommendation] with wake clock times already in minutes.
  static BedtimeRecommendation bedtimeFromWakeMinutes({
    required double currentDebtMinutes,
    required double strainToday,
    required List<double> wakeMinutes,
    SleepConfig config = const SleepConfig(),
  }) {
    final projected = needTotal(need(currentDebtMinutes, strainToday, config));
    if (wakeMinutes.isEmpty) {
      return BedtimeRecommendation(
        projectedNeedMinutes: projected,
        debtMinutes: currentDebtMinutes,
      );
    }
    // Wake times are mornings (no midnight wrap) → plain mean (Pulse :89-93).
    final habitualWake = Stats.mean(wakeMinutes);
    final bedtime = ((habitualWake - projected) % 1440 + 1440) % 1440;
    return BedtimeRecommendation(
      projectedNeedMinutes: projected,
      debtMinutes: currentDebtMinutes,
      habitualWakeMinutes: habitualWake,
      recommendedBedtimeMinutes: bedtime,
    );
  }

  /// Minutes since local midnight (0…1439). Pulse SleepEngine.swift:104-107.
  static double clockMinutes(DateTime t) => Civil.clockMinutes(t);

  /// Minutes since 12:00 so times around midnight stay linear.
  /// Pulse SleepEngine.swift:192-196.
  static double shiftedMinutes(DateTime t) => (clockMinutes(t) + 720) % 1440;

  /// Pulse SleepEngine.swift:198-201.
  static double circularDiff(double a, double b) {
    final diff = (a - b).abs();
    return math.min(diff, 1440 - diff);
  }

  /// One night of Pulse's `analyze` loop (SleepEngine.swift:125-186).
  /// [debtBefore] is the debt after the previous analysed night,
  /// [previousStrain] the strain of the previous CALENDAR day (0 if none),
  /// [recent] the last ≤ 4 main-sleep bed/wake times, oldest first.
  static SleepNight analyzeNight(
    DayRecord? record, {
    required double debtBefore,
    required double previousStrain,
    required List<BedWake> recent,
    SleepConfig config = const SleepConfig(),
  }) {
    final sessions = record?.sleepSessions ?? const <SleepSession>[];
    final main = record == null ? null : Inputs.mainSleep(record);
    final slept = sessions.fold(0.0, (a, s) => a + Inputs.asleep(s));
    final napMinutes = slept - (main == null ? 0 : Inputs.asleep(main));
    final hasData = main != null && slept > 0;

    final breakdown = need(debtBefore, previousStrain, config);
    final needMinutes = needTotal(breakdown);
    final performance = !hasData
        ? 0.0
        : needMinutes > 0
        ? math.min(100, slept / needMinutes * 100).toDouble()
        : 100.0;

    var debt = debtBefore;
    if (hasData) {
      // Debt is booked against baseline + strain boost, NOT the displayed
      // need (which contains the repayment) — otherwise debt would compound.
      // Pulse SleepEngine.swift:139-149.
      final strainBoost = SleepEngine.strainBoost(previousStrain, config);
      final structuralNeed = config.baselineNeedMinutes + strainBoost;
      final delta = math.min(
        structuralNeed - slept,
        config.maxDebtGainPerNightMinutes,
      );
      debt = Stats.clamp(debt + delta, 0, config.maxDebtMinutes);
    }

    // Consistency vs the last 4 main sleeps. Pulse SleepEngine.swift:151-166.
    double? consistency;
    BedWake? bedWake;
    if (main != null) {
      final bed = shiftedMinutes(main.start);
      final wake = shiftedMinutes(main.end);
      if (recent.isNotEmpty) {
        final deviations = [
          for (final e in recent)
            (circularDiff(e.bed, bed) + circularDiff(e.wake, wake)) / 2,
        ];
        final avgDev = Stats.mean(deviations);
        consistency = Stats.clamp(
          100 - avgDev / consistencyZeroMinutes * 100,
          0,
          100,
        );
      }
      bedWake = BedWake(bed, wake);
    }

    // Pulse SleepEngine.swift:168-171.
    var stageMinutes = main?.stageMinutes ?? const <SleepStage, double>{};
    if (stageMinutes.isEmpty && main != null) {
      stageMinutes = {SleepStage.light: Inputs.asleep(main)};
    }
    final eff = main?.efficiency;

    return SleepNight(
      SleepAnalysis(
        sleptMinutes: slept,
        napMinutes: math.max(0, napMinutes).toDouble(),
        needMinutes: needMinutes,
        performance: performance,
        debtAfterMinutes: debt,
        consistency: consistency,
        efficiency: (eff != null && eff.isFinite) ? eff : null,
        stageMinutes: stageMinutes,
        bedTime: main?.start,
        wakeTime: main?.end,
        hasData: hasData,
        needBreakdown: breakdown,
      ),
      bedWake,
    );
  }

  /// Appends [bw] to the consistency window (keeps the last 4).
  static List<BedWake> push(List<BedWake> recent, BedWake? bw) {
    if (bw == null) return recent;
    final out = [...recent, bw];
    return out.length > consistencyWindow
        ? out.sublist(out.length - consistencyWindow)
        : out;
  }

  /// Whole-series analysis over every calendar day from the first to the
  /// last key, carrying debt and the consistency window.
  /// Pulse SleepEngine.swift:112-189 (used by the parity tests).
  static Map<String, SleepAnalysis> analyze(
    Map<String, DayRecord> days, {
    SleepConfig config = const SleepConfig(),
    Map<String, double> strainByDay = const {},
  }) {
    if (days.isEmpty) return {};
    final keys = days.keys.toList()..sort();
    final result = <String, SleepAnalysis>{};
    var debt = 0.0;
    var recent = <BedWake>[];
    for (final key in DayKey.range(keys.first, keys.last)) {
      final night = analyzeNight(
        days[key],
        debtBefore: debt,
        previousStrain: strainByDay[DayKey.add(key, -1)] ?? 0,
        recent: recent,
        config: config,
      );
      debt = night.analysis.debtAfterMinutes;
      recent = push(recent, night.bedWake);
      result[key] = night.analysis;
    }
    return result;
  }
}
