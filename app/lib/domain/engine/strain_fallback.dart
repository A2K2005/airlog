// Day strain as the Engine reports it. [ours]
//
// Principle 6 ("derived, never invented", product-critic review 2026-09-29):
// a 0–21 strain is only ever computed from measured heart rate.
//   * Any HR samples → Pulse's zone accumulator over every sample (method
//     hrZones). Sparse HR (fewer than 300 samples, or < 60 % of AWAKE
//     minutes up to `now`) is still scored from the samples it has, and
//     flagged partial: it likely under-counts the day.
//   * No HR, or no max HR to build zones from → method none: no score. The
//     day's activity facts (workouts, steps) are still reported.
//   * A workout is scored from the HR inside it (≥ 3 samples, Pulse
//     :172-176), else from its own measured average HR (Pulse :177-181,
//     method fallback), else not at all (method none). The old estimate
//     from step counts and a MET-by-activity table against a population
//     VO₂max is gone.
// Banister TRIMP is attached as a cross-check (trimp.dart); on the day it
// excludes samples inside sleep sessions (waking span, as Edge does).

import '../day_key.dart';
import '../models.dart';
import '../results.dart';
import 'hr_series.dart';
import 'inputs.dart';
import 'stats.dart';
import 'strain.dart';
import 'trimp.dart';

class DayStrain {
  const DayStrain({
    required this.result,
    required this.coverage,
    required this.samples,
    required this.sparse,
    required this.partialHr,
  });
  final StrainResult result;

  /// Share of awake minutes that contain ≥ 1 HR sample (0..1).
  final double coverage;
  final int samples;
  final bool sparse;

  /// HR was sparse but there was nothing else to estimate from.
  final bool partialHr;
}

typedef _WorkoutLoad = ({
  WorkoutStrain strain,
  double raw,
  List<double> loadZones,
  List<double> displayZones,
});

abstract final class StrainDay {
  static const double minCoverage = 0.6;
  static const int minSamples = 300;

  /// RETIRED in algo v2 (steps are never turned into strain). Not read by
  /// the engine; kept only so the Methodology screen compiles until its
  /// copy is updated.
  static const double stepsPer = 1000;
  static const double stepsLoad = 2.0;

  /// Sleep intervals of [r] clipped to [fromUs, toUs), merged, in µs.
  static UsIntervals sleepIntervals(DayRecord r, int fromUs, int toUs) {
    final raw = <(int, int)>[];
    for (final s in r.sleepSessions) {
      var a = s.start.microsecondsSinceEpoch;
      var b = s.end.microsecondsSinceEpoch;
      if (a < fromUs) a = fromUs;
      if (b > toUs) b = toUs;
      if (b > a) raw.add((a, b));
    }
    raw.sort((x, y) => x.$1.compareTo(y.$1));
    final merged = <(int, int)>[];
    for (final iv in raw) {
      if (merged.isNotEmpty && iv.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, iv.$2 > last.$2 ? iv.$2 : last.$2));
      } else {
        merged.add(iv);
      }
    }
    return merged;
  }

  /// Share of awake minutes of [r]'s calendar day (up to [now]) that hold at
  /// least one sample.
  static double awakeCoverage(
    DayRecord r,
    List<HrSample> samples,
    DateTime now,
  ) => awakeCoverageSeries(r, HrSeries.of(samples), now);

  static double awakeCoverageSeries(
    DayRecord r,
    HrSeries s,
    DateTime now, {
    (int, int)? dayBoundsUs,
  }) {
    final (dayStart, dayEnd) = dayBoundsUs ?? boundsUs(r.date);
    final nowUs = now.microsecondsSinceEpoch;
    final end = nowUs < dayEnd ? nowUs : dayEnd;
    if (end <= dayStart) return s.isEmpty ? 0 : 1;
    final sleep = sleepIntervals(r, dayStart, end);
    var awake = (end - dayStart) / 6e7;
    for (final (a, b) in sleep) {
      awake -= (b - a) / 6e7;
    }
    if (awake <= 1) return s.isEmpty ? 0 : 1;
    final cursor = IntervalCursor(s, sleep);
    final startMin = s.toMin(dayStart);
    final endMin = s.toMin(end);
    var covered = 0;
    var lastMinute = -1;
    for (var i = s.lowerBound(startMin); i < s.length; i++) {
      final x = s.m[i];
      if (x >= endMin) break;
      if (cursor.inside(x)) continue;
      final minute = (x - startMin + 1e-6).floor(); // ε: float noise
      if (minute != lastMinute) {
        covered++;
        lastMinute = minute;
      }
    }
    return Stats.clamp(covered / awake, 0, 1);
  }

  /// Local midnight → next local midnight of [date], epoch µs.
  static (int, int) boundsUs(String date) => (
    DayKey.start(date).microsecondsSinceEpoch,
    DayKey.end(date).microsecondsSinceEpoch,
  );

  /// Strain for [record]'s day. [restingHr] is today's (sanitised) resting
  /// HR; Pulse falls back to 62 bpm without one (StrainEngine.swift:127).
  /// [maxHr] null = no max HR known: no score. [samples] must be clean and
  /// sorted; pass [series] to reuse columns.
  static DayStrain compute(
    DayRecord record, {
    required List<HrSample> samples,
    HrSeries? series,
    required double? restingHr,
    required double? maxHr,
    MaxHrSource? maxHrSource,
    required double tau,
    required Sex sex,
    required DateTime now,
    int? recoveryScore,
    (int, int)? dayBoundsUs,
  }) {
    final bounds = dayBoundsUs ?? boundsUs(record.date);
    final s = series ?? HrSeries.of(samples);
    // No resting HR: %HRmax zones (Swain), never an assumed 62 bpm.
    final fromMax = restingHr == null && maxHr != null;
    final anchors = fromMax ? StrainEngine.maxHrZoneAnchors(maxHr) : null;
    final rhr = anchors?.$1 ?? restingHr ?? 0;
    final zoneMax = anchors?.$2 ?? maxHr;
    final coverage = awakeCoverageSeries(record, s, now, dayBoundsUs: bounds);
    final sparse = s.length < minSamples || coverage < minCoverage;
    final steps = Inputs.steps(record);
    final target = recoveryScore == null
        ? null
        : StrainEngine.targetStrain(recoveryScore);
    final mh = zoneMax;
    final workouts = [
      for (final w in record.workouts)
        mh == null
            ? _unscored(w)
            : _workout(
                w,
                s,
                rhr: rhr,
                maxHr: mh,
                tau: tau,
                sex: sex,
                trimp: !fromMax,
              ).strain,
    ];

    if (!s.isEmpty && mh != null) {
      final acc = StrainEngine.accumulateSeries(s, restingHr: rhr, maxHr: mh);
      // Waking span: exclude sleep from the day before's evening onward.
      final sleep = sleepIntervals(
        record,
        bounds.$1 - const Duration(days: 1).inMicroseconds,
        bounds.$2,
      );
      final trimp = Trimp.fromSeries(
        s,
        restingHr: rhr,
        maxHr: mh,
        sex: sex,
        exclude: sleep,
      );
      return DayStrain(
        result: StrainResult(
          strain: StrainEngine.strainFromRaw(acc.raw, tau: tau),
          rawLoad: acc.raw,
          zoneMinutes: acc.displayZones,
          loadZoneMinutes: acc.zones,
          restMinutes: acc.displayRestMin,
          method: StrainMethod.hrZones,
          avgHr: acc.avgHr,
          peakHr: acc.peakHr,
          maxHrUsed: maxHr,
          maxHrSource: maxHrSource,
          restingHrUsed: fromMax ? null : rhr,
          trimp: fromMax ? null : trimp,
          targetStrain: target,
          workouts: workouts,
          steps: steps,
          zonesFromMaxHr: fromMax,
        ),
        coverage: coverage,
        samples: s.length,
        sparse: sparse,
        partialHr: sparse,
      );
    }

    return DayStrain(
      result: StrainResult(
        strain: 0,
        rawLoad: 0,
        zoneMinutes: List<double>.filled(
          StrainEngine.displayZoneLowerBounds.length,
          0,
        ),
        method: StrainMethod.none,
        maxHrUsed: maxHr,
        maxHrSource: maxHr == null ? null : maxHrSource,
        restingHrUsed: restingHr,
        targetStrain: target,
        workouts: workouts,
        steps: steps,
      ),
      coverage: coverage,
      samples: s.length,
      sparse: true,
      partialHr: false,
    );
  }

  /// A workout as an activity fact, without a strain score.
  static WorkoutStrain _unscored(Workout w) => WorkoutStrain(
    workoutId: w.id,
    strain: 0,
    zoneMinutes: List<double>.filled(
      StrainEngine.displayZoneLowerBounds.length,
      0,
    ),
    avgHr: finiteOrNull(w.averageHr),
    method: StrainMethod.none,
  );

  static _WorkoutLoad _workout(
    Workout w,
    HrSeries s, {
    required double rhr,
    required double maxHr,
    required double tau,
    required Sex sex,
    bool trimp = true,
  }) {
    final minutes = Inputs.minutes(w.durationMinutes);
    final (from, to) = s.closedRange(w.start, w.end);
    if (to - from >= 3) {
      final acc = StrainEngine.accumulateSeries(
        s,
        from: from,
        to: to,
        restingHr: rhr,
        maxHr: maxHr,
      );
      return (
        strain: WorkoutStrain(
          workoutId: w.id,
          strain: StrainEngine.strainFromRaw(acc.raw, tau: tau),
          zoneMinutes: acc.displayZones,
          avgHr: acc.avgHr,
          peakHr: acc.peakHr,
          trimp: trimp
              ? Trimp.fromSeries(
                  s,
                  from: from,
                  to: to,
                  restingHr: rhr,
                  maxHr: maxHr,
                  sex: sex,
                )
              : null,
          method: StrainMethod.hrZones,
        ),
        raw: acc.raw,
        loadZones: acc.zones,
        displayZones: acc.displayZones,
      );
    }
    final avg = finiteOrNull(w.averageHr);
    // No HR inside and no measured average: an activity fact, no score.
    if (avg == null) {
      final u = _unscored(w);
      return (
        strain: u,
        raw: 0.0,
        loadZones: List<double>.filled(StrainEngine.zoneWeights.length, 0),
        displayZones: u.zoneMinutes,
      );
    }
    final fraction = StrainEngine.hrrFraction(avg, rhr, maxHr);
    final zones = List<double>.filled(StrainEngine.zoneWeights.length, 0);
    final display = List<double>.filled(
      StrainEngine.displayZoneLowerBounds.length,
      0,
    );
    var raw = 0.0;
    if (fraction != null) {
      final zone = StrainEngine.zoneIndex(fraction);
      if (zone != null) {
        raw = StrainEngine.zoneWeights[zone] * minutes;
        zones[zone] = minutes;
      }
      final dz = StrainEngine.displayZone(fraction);
      if (dz > 0) display[dz - 1] = minutes;
    }
    return (
      strain: WorkoutStrain(
        workoutId: w.id,
        strain: StrainEngine.strainFromRaw(raw, tau: tau),
        zoneMinutes: display,
        avgHr: avg,
        trimp: trimp
            ? Trimp.fromAverage(
                avg,
                minutes,
                restingHr: rhr,
                maxHr: maxHr,
                sex: sex,
              )
            : null,
        method: StrainMethod.fallback,
      ),
      raw: raw,
      loadZones: zones,
      displayZones: display,
    );
  }
}
