// Ported from Luraxx/pulse App/AppModel.swift (recomputeAll and friends)
// (Apache-2.0, see third_party/pulse/NOTICE). Changes: per-day instead of
// whole-store recompute (debt carried via the previous DayResult); the
// deliberate differences listed below; caching of per-record derived data.
//
// The per-day pipeline behind Engine.computeDay / computeRange.
//
// Wiring follows Pulse's App/AppModel.swift (recomputeAll, :373-460;
// bedtimeTonight, :337-353; healthStatuses, :360-364; robustMaxHR, :466-470):
//   sleep (debt carried from the previous result) → recovery (uses tonight's
//   sleep performance) → strain (target from recovery) → bedtime → health
//   monitor → Plews readiness → Pulse Age → calibration → notes.
// Differences from AppModel, all deliberate:
//   * no sleep data ⇒ sleepPerformance null (re-weighted) instead of 0,
//     which Pulse scores as a 0.1 sleep component;
//   * the health alert is built from the SAME segment-baseline statuses the
//     cards show (Pulse rebuilds baselines from its 10-day alert window), so
//     an alert can never contradict the bands on screen;
//   * Pulse Age is not computed in v1 (it estimated VO₂max from a heart-rate
//     ratio; product-critic review 2026-09-29). AgeEngine stays for v2;
//   * max HR from the override, else the birth year, else the observed
//     maximum (labelled); never an assumed age of 30 as Pulse does;
//   * no strain score without heart rate (strain_fallback.dart);
//   * baselines are keyed by definition@origin#device (baselines.dart).

import 'dart:math' as math;

import '../models.dart';
import '../results.dart';
import 'baselines.dart';
import 'engine.dart';
import 'health_monitor.dart';
import 'hr_series.dart';
import 'inputs.dart';
import 'notes.dart';
import 'readiness.dart';
import 'recovery.dart';
import 'sleep.dart';
import 'stats.dart';
import 'strain.dart';
import 'strain_fallback.dart';

/// Per-record derived data, computed once per engine call.
class _Prepared {
  _Prepared(this.record, this._midnights);
  final DayRecord record;
  final Map<String, int> _midnights;
  List<HrSample>? _hr;
  HrSeries? _series;
  List<double>? _sortedBpm;

  List<HrSample> get hr => _hr ??= Inputs.hr(record);
  HrSeries get series => _series ??= HrSeries.of(hr);
  List<double> get sortedBpm =>
      _sortedBpm ??= Stats.sortedCopy([for (final s in hr) s.bpm]);

  /// The day's robust peak heart rate: the [DayEngine.observedPeakRank]-th
  /// highest 1-minute value (so one or two artefact minutes don't set it),
  /// or null with fewer than [DayEngine.observedPeakMinSamples] samples.
  double? get peak {
    final b = sortedBpm;
    if (b.length < DayEngine.observedPeakMinSamples) return null;
    return b[b.length - DayEngine.observedPeakRank];
  }

  (int, int)? _bounds;
  (int, int) get bounds => _bounds ??= _boundsNow();

  (int, int) _boundsNow() {
    final s = _midnights[record.date];
    final e = _midnights[Civil.add(record.date, 1)];
    return (s != null && e != null) ? (s, e) : StrainDay.boundsUs(record.date);
  }

  bool _bwDone = false;
  BedWake? _bw;

  /// Main sleep bed/wake on Pulse's shifted clock (null without one).
  BedWake? get bedWake {
    if (!_bwDone) {
      final m = Inputs.mainSleep(record);
      _bw = m == null
          ? null
          : BedWake(
              SleepEngine.shiftedMinutes(m.start),
              SleepEngine.shiftedMinutes(m.end),
            );
      _bwDone = true;
    }
    return _bw;
  }

  /// Wake clock time, minutes since midnight.
  double? get wakeClock {
    final bw = bedWake;
    return bw == null ? null : (bw.wake + 720) % 1440;
  }
}

class _Cache {
  final Map<DayRecord, _Prepared> _m = Map.identity();

  /// Precomputed local midnights (computeRange), keyed by date.
  final Map<String, int> midnights = {};
  _Prepared of(DayRecord r) => _m[r] ??= _Prepared(r, midnights);
}

/// Per-call constants (the profile max HR needs a local-time lookup; once).
class _Ctx {
  _Ctx(this.config, this.now)
    : profileMaxHr = DayEngine.profileMaxHr(config.profile, now),
      window = config.baselineWindowDays > 0 ? config.baselineWindowDays : 30;
  final EngineConfig config;
  final DateTime now;

  /// Override or birth-year max HR; null → observed per day.
  final ({double value, MaxHrSource source})? profileMaxHr;
  final int window;
}

abstract final class DayEngine {
  static bool validDate(String d) => Civil.valid(d);

  /// Override (if plausible), else Tanaka 208 − 0.7·age as Pulse
  /// (StrainEngine.swift:16-18) with age from the profile at [now].
  /// (Engine.maxHrFor contract; without a birth year this is Pulse's age-30
  /// default, which the day engine no longer uses; see [profileMaxHr].)
  static double maxHrFor(UserProfile p, DateTime now) =>
      Inputs.maxHrOverride(p) ??
      (StrainEngine.tanakaIntercept - StrainEngine.tanakaSlope * p.ageAt(now));

  /// [ours] The profile's max HR: the plausible override, else Tanaka from
  /// the birth year, else null (the day engine then uses the observed max).
  static ({double value, MaxHrSource source})? profileMaxHr(
    UserProfile p,
    DateTime now,
  ) {
    final o = Inputs.maxHrOverride(p);
    if (o != null) return (value: o, source: MaxHrSource.override);
    if (!p.hasAge) return null;
    return (
      value:
          StrainEngine.tanakaIntercept -
          StrainEngine.tanakaSlope * p.ageAt(now),
      source: MaxHrSource.birthYear,
    );
  }

  /// [ours] Without a birth year, max HR = the highest daily robust peak
  /// over this many calendar days (today included).
  static const int observedMaxDays = 90;

  /// [ours] Robust daily peak = the 3rd-highest 1-minute HR of the day.
  static const int observedPeakRank = 3;

  /// [ours] A day needs this many 1-minute samples to contribute a peak.
  static const int observedPeakMinSamples = 60;

  static List<DayResult> computeRange(
    List<DayRecord> records,
    EngineConfig config,
    DateTime now,
  ) {
    // Duplicates: the LAST record for a date wins (input order).
    final byDate = <String, DayRecord>{};
    for (final r in records) {
      if (validDate(r.date)) byDate[r.date] = r;
    }
    final sorted = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final cache = _Cache()
      ..midnights.addAll(
        LocalMidnights.forKeys([for (final r in sorted) r.date]),
      );
    final ctx = _Ctx(config, now);
    final known = <String, DayResult>{};
    final out = <DayResult>[];
    DayResult? previous;
    for (var i = 0; i < sorted.length; i++) {
      final res = _core(
        sorted[i],
        sorted.sublist(0, i),
        previous,
        ctx,
        known,
        cache,
      );
      out.add(res);
      known[res.date] = res;
      previous = res;
    }
    return out;
  }

  static DayResult computeDay(
    DayRecord today,
    List<DayRecord> history,
    DayResult? previous,
    EngineConfig config,
    DateTime now,
    List<DayResult> historyResults,
  ) {
    if (!validDate(today.date)) {
      throw ArgumentError.value(
        today.date,
        'today.date',
        'expected yyyy-MM-dd',
      );
    }
    final byDate = <String, DayRecord>{};
    for (final r in history) {
      if (validDate(r.date) && r.date.compareTo(today.date) < 0) {
        byDate[r.date] = r;
      }
    }
    final sorted = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final known = {for (final r in historyResults) r.date: r};
    return _core(today, sorted, previous, _Ctx(config, now), known, _Cache());
  }

  static DayResult _core(
    DayRecord today,
    List<DayRecord> history, // oldest first, strictly before today, deduped
    DayResult? previous,
    _Ctx ctx,
    Map<String, DayResult> known,
    _Cache cache,
  ) {
    final config = ctx.config;
    final now = ctx.now;
    final profile = config.profile;
    final window = ctx.window;
    final prep = cache.of(today);
    final maxHr = ctx.profileMaxHr ?? _observedMaxHr(today, history, cache);

    // ── Sleep (Pulse SleepEngine.analyze, one night; debt carried) ─────────
    final prevDebt = finiteOrNull(previous?.sleep?.debtAfterMinutes) ?? 0;
    final debtBefore = Stats.clamp(prevDebt, 0, config.sleep.maxDebtMinutes);
    final prevStrain =
        (previous != null && previous.date == Civil.add(today.date, -1))
        ? (finiteOrNull(previous.strain?.strain) ?? 0)
        : 0.0;
    final night = SleepEngine.analyzeNight(
      today,
      debtBefore: debtBefore,
      previousStrain: prevStrain,
      recent: _recentBedWake(history, cache),
      config: config.sleep,
    );
    final sleep = night.analysis;

    // ── Recovery ───────────────────────────────────────────────────────────
    // Inputs the source app never shares (observed from its data or
    // persisted with the source choice, never a package list): HRV →
    // "without HRV"; resting HR → sleeping HR may stand in (HRV ladder S1).
    final noHrvApp = Inputs.hrv(today) == null
        ? _notSharedBy(today, history, Metric.hrv, config.notShared)
        : null;
    final noRhrApp = Inputs.rhr(today) == null
        ? _notSharedBy(today, history, Metric.restingHr, config.notShared)
        : null;
    final noHrvFrom = noHrvApp == null
        ? null
        : Notes.appName(noHrvApp, config.appNames);
    final noRhrFrom = noRhrApp == null
        ? null
        : Notes.appName(noRhrApp, config.appNames);
    final recovery = RecoveryEngine.compute(
      today: today,
      history: history,
      sleepPerformance: sleep.hasData ? sleep.performance : null,
      window: window,
      sleepingHrForRhr: noRhrFrom != null,
    );

    // ── Strain ─────────────────────────────────────────────────────────────
    final dayStrain = StrainDay.compute(
      today,
      samples: prep.hr,
      series: prep.series,
      dayBoundsUs: prep.bounds,
      restingHr: Inputs.rhr(today),
      maxHr: maxHr?.value,
      maxHrSource: maxHr?.source,
      tau: config.strainTau,
      sex: profile.sex,
      now: now,
      recoveryScore: recovery?.score,
    );
    final strain = dayStrain.result;

    // ── Bedtime for the coming night (AppModel.swift:337-353) ─────────────
    final week = _window(history, today, SleepEngine.bedtimeWakeDays);
    final wakes = <double>[for (final r in week) ?cache.of(r).wakeClock];
    final bedtime = wakes.isEmpty
        ? null
        : SleepEngine.bedtimeFromWakeMinutes(
            currentDebtMinutes: sleep.debtAfterMinutes,
            strainToday: strain.method == StrainMethod.none ? 0 : strain.strain,
            wakeMinutes: wakes,
            config: config.sleep,
          );

    // ── Health monitor ─────────────────────────────────────────────────────
    final statuses = HealthMonitor.evaluate(today, history, window: window);
    final alert = _alert(today, history, statuses, window, known);
    final health = HealthMonitorResult(
      metrics: statuses,
      alert: alert != null,
      alertReason: alert?.message,
    );

    // ── Readiness, calibration, re-learning (no Pulse Age in v1) ─────────
    final readiness = _readiness(today, history, window);
    final calibration = Calibration(
      haveNights: Baselines.calibrationNights(today, history),
      needNights: config.calibrationNeedNights,
    );
    SourceChange? sourceChange;
    for (final m in const [Metric.hrv, Metric.restingHr]) {
      final sw = Baselines.recentSwitch(
        today,
        history,
        m,
        within: config.calibrationNeedNights,
      );
      if (sw == null) continue;
      sourceChange = SourceChange(
        metric: m.code,
        from: sw.from,
        to: sw.to,
        nights: sw.nights,
      );
      break;
    }
    // Sleeping HR standing in for resting HR (the new app never shares it,
    // e.g. Fitbit → Samsung Health) re-learns too: its segment is new after
    // a different app in resting HR's slot. A user who has only ever had
    // the new app has nothing to re-learn.
    final shrUsed =
        recovery?.components.any(
          (c) => c.key == RecoveryEngine.sleepingHrKey,
        ) ??
        false;
    if (sourceChange == null && shrUsed) {
      final shr = Baselines.segment(today, history, Metric.sleepingHr).seg;
      final nights = Baselines.values(
        history,
        Metric.sleepingHr,
        shr,
        window: config.calibrationNeedNights,
      ).length;
      final rhr = Baselines.segment(today, history, Metric.restingHr);
      final before = rhr.exists
          ? rhr.seg.prov
          : Baselines.recentSwitch(
              today,
              history,
              Metric.sleepingHr,
              within: config.calibrationNeedNights,
            )?.from;
      if (nights < config.calibrationNeedNights &&
          before != null &&
          before.origin != shr.prov?.origin) {
        sourceChange = SourceChange(
          metric: Metric.restingHr.code,
          from: before,
          to: shr.prov,
          nights: nights,
        );
      }
    }

    // ── Notes ──────────────────────────────────────────────────────────────
    final notes = <StatusNote>[];
    bool seen(Metric m) => Baselines.segment(today, history, m).exists;
    if (recovery == null) {
      notes.add(
        noHrvFrom != null && noHrvFrom == noRhrFrom
            ? Notes.recoveryNotShared(noHrvFrom, origin: noHrvApp!.origin)
            : Notes.recoveryUnavailable,
      );
    }
    if (Inputs.hrv(today) == null) {
      notes.add(
        noHrvFrom != null
            ? Notes.hrvNotShared(noHrvFrom, scored: recovery != null)
            : Notes.missingHrv(seenBefore: seen(Metric.hrv)),
      );
    }
    if (Inputs.rhr(today) == null) {
      notes.add(
        noRhrFrom != null
            ? Notes.rhrNotShared(noRhrFrom, sleepingHr: shrUsed)
            : Notes.missingRhr(seenBefore: seen(Metric.restingHr)),
      );
    }
    if (!sleep.hasData) {
      notes.add(
        Notes.missingSleep(
          seenBefore: history.any((r) => Inputs.mainSleep(r) != null),
        ),
      );
    }
    if (Inputs.resp(today) == null) notes.add(Notes.missingResp);
    if (Inputs.spo2Avg(today) == null && Inputs.spo2Min(today) == null) {
      notes.add(Notes.missingSpo2);
    }
    if (Inputs.skinTemp(today) == null) notes.add(Notes.missingSkinTemp);
    if (recovery != null && recovery.calibrating) {
      // Name the input that is still short of 5 baseline nights (Pulse's
      // per-metric rule), not the combined calibration count.
      final lagging = <(String, int)>[
        if (Inputs.hrv(today) != null)
          (
            'HRV',
            Baselines.segmentValues(
              today,
              history,
              Metric.hrv,
              window: window,
            ).length,
          ),
        if (Inputs.rhr(today) != null)
          (
            'resting HR',
            Baselines.segmentValues(
              today,
              history,
              Metric.restingHr,
              window: window,
            ).length,
          ),
        if (recovery.components.any(
          (c) => c.key == RecoveryEngine.sleepingHrKey,
        ))
          (
            'sleeping HR',
            Baselines.segmentValues(
              today,
              history,
              Metric.sleepingHr,
              window: window,
            ).length,
          ),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      if (lagging.isNotEmpty) {
        final (name, have) = lagging.first;
        notes.add(Notes.recoveryCalibrating(have, name));
      }
    }
    if (prep.hr.isEmpty) notes.add(Notes.missingHr);
    if (Inputs.steps(today) == null) notes.add(Notes.missingSteps);
    switch (strain.method) {
      case StrainMethod.none:
        notes.add(
          prep.hr.isNotEmpty && maxHr == null
              ? Notes.strainNeedsMaxHr
              : Notes.strainUnavailable,
        );
      case StrainMethod.fallback:
      case StrainMethod.hrZones:
        if (dayStrain.partialHr) {
          notes.add(Notes.strainPartialHr(dayStrain.coverage));
        }
    }
    if (strain.zonesFromMaxHr) notes.add(Notes.zonesFromMaxHr);
    if (maxHr != null && maxHr.source == MaxHrSource.observed) {
      notes.add(Notes.observedMaxHr(maxHr.value));
    }
    for (final m in const [
      Metric.hrv,
      Metric.restingHr,
      Metric.respiratoryRate,
      Metric.spo2,
      Metric.skinTemp,
    ]) {
      final before = Baselines.switchedFrom(today, history, m);
      if (before == null) continue;
      final nowProv =
          today.provenance[m] ?? const Provenance(SourceKind.demo, 'unknown');
      final nights = Baselines.values(
        history,
        m,
        Baselines.segment(today, history, m).seg,
        window: 1 << 30,
      ).length;
      notes.add(
        Notes.newBaseline(m, nowProv, before, nights, names: config.appNames),
      );
    }

    return DayResult(
      date: today.date,
      algoVersion: kAlgoVersion,
      computedAt: now,
      recovery: recovery,
      strain: strain,
      sleep: sleep,
      bedtime: bedtime,
      health: health,
      readiness: readiness,
      calibration: calibration,
      notes: notes,
      sourceChange: sourceChange,
      notShared: {
        Metric.hrv.code: ?noHrvFrom,
        Metric.restingHr.code: ?noRhrFrom,
      },
    );
  }

  /// [ours] Nights of other data from one app, never with [Metric] from
  /// it, before Airlog says that app doesn't share it (instead of "missing
  /// tonight").
  static const int notSharedNights = 3;

  /// [ours] The metric from any app within this many days means it normally
  /// arrives, so a missing night is a wear/sync gap, not a sharing limit.
  static const int sharedRecentDays = 14;

  /// The provenance (app) behind today's other nightly data (sleep, else
  /// resting HR, respiratory rate or heart rate) when that app never
  /// shares [metric]; null otherwise (including data without an origin:
  /// demo, older rows). E.g. WHOOP writes no HRV; Samsung Health no HRV or
  /// resting HR. "Never shares" is either
  ///   * persisted with the source choice ([persisted], EngineConfig.
  ///     notShared, observed from the raw rows): true from the app's first
  ///     night; or
  ///   * observed here: the app has written data for at least
  ///     [notSharedNights] nights and never [metric].
  /// Either way, [metric] from ANOTHER app within [sharedRecentDays] days
  /// means it normally arrives (a wear or sync gap, not a sharing limit),
  /// unless that app has gone quiet since today's app took over the nightly
  /// data: after a switch (Fitbit → Samsung Health) the old app's recent
  /// values say nothing about the new one, so the sleeping-HR stand-in is
  /// not held back for [sharedRecentDays] days.
  static Provenance? _notSharedBy(
    DayRecord today,
    List<DayRecord> history,
    Metric metric,
    Map<String, Set<String>> persisted,
  ) {
    Provenance? nightly;
    Metric? nightlyMetric;
    for (final m in const [
      Metric.sleep,
      Metric.restingHr,
      Metric.respiratoryRate,
      Metric.hr,
    ]) {
      if (m == metric) continue;
      final p = today.provenance[m];
      if (p?.origin != null) {
        nightly = p;
        nightlyMetric = m;
        break;
      }
    }
    final origin = nightly?.origin;
    if (nightly == null || nightlyMetric == null || origin == null) {
      return null;
    }
    final known = persisted[metric.code]?.contains(origin) ?? false;
    final active = _activeSince(today, history, nightlyMetric, origin);
    final read = valueReader(metric);
    final recentFrom = Civil.add(today.date, -sharedRecentDays);
    var nights = 1; // today
    for (final r in history) {
      if (read(r) != null) {
        final from = r.provenance[metric]?.origin;
        if (from == origin) return null;
        if (r.date.compareTo(recentFrom) >= 0 &&
            (from == null || active.contains(from))) {
          return null;
        }
      }
      for (final p in r.provenance.values) {
        if (p.origin == origin) {
          nights++;
          break;
        }
      }
    }
    if (!known && nights < notSharedNights) return null;
    return nightly;
  }

  /// Origins that wrote anything (any metric) today or on a history day
  /// since [origin] took over [metric] (the start of its current run of
  /// days reporting [metric]).
  static Set<String> _activeSince(
    DayRecord today,
    List<DayRecord> history,
    Metric metric,
    String origin,
  ) {
    var from = today.date;
    for (var i = history.length - 1; i >= 0; i--) {
      final p = history[i].provenance[metric];
      if (p == null) continue;
      if (p.origin != origin) break;
      from = history[i].date;
    }
    final out = <String>{};
    void add(DayRecord r) {
      for (final p in r.provenance.values) {
        if (p.origin != null) out.add(p.origin!);
      }
    }

    add(today);
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].date.compareTo(from) < 0) break;
      add(history[i]);
    }
    return out;
  }

  /// Max HR from the robust daily peaks of the last [observedMaxDays]
  /// calendar days (today included); null without enough heart rate.
  static ({double value, MaxHrSource source})? _observedMaxHr(
    DayRecord today,
    List<DayRecord> history,
    _Cache cache,
  ) {
    double? best;
    for (final r in _window(history, today, observedMaxDays)) {
      final p = cache.of(r).peak;
      if (p != null && (best == null || p > best)) best = p;
    }
    return best == null ? null : (value: best, source: MaxHrSource.observed);
  }

  /// Last ≤ 4 main sleeps before today, oldest first (Pulse's consistency
  /// window, SleepEngine.swift:122, :151-166).
  static List<BedWake> _recentBedWake(List<DayRecord> history, _Cache cache) {
    final out = <BedWake>[];
    for (
      var i = history.length - 1;
      i >= 0 && out.length < SleepEngine.consistencyWindow;
      i--
    ) {
      final bw = cache.of(history[i]).bedWake;
      if (bw != null) out.add(bw);
    }
    return out.reversed.toList();
  }

  /// Records of the calendar days D−(days−1)…D (history tail + today),
  /// oldest first — Pulse MetricsStore.chronological(upTo:count:).
  static List<DayRecord> _window(
    List<DayRecord> history,
    DayRecord today,
    int days,
  ) {
    final start = Civil.add(today.date, -(days - 1));
    final out = <DayRecord>[today];
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].date.compareTo(start) < 0) break;
      out.add(history[i]);
    }
    return out.reversed.toList();
  }

  /// Pulse's alert rules (HealthMonitor.swift:153-195) over the last 10
  /// calendar days (AppModel.swift:330-332), each day judged by its own
  /// segment-baseline statuses.
  static HealthAlert? _alert(
    DayRecord today,
    List<DayRecord> history,
    List<HealthMetricStatus> todayStatuses,
    int window,
    Map<String, DayResult> known,
  ) {
    final win = _window(history, today, 10);
    if (win.length < 6) return null;
    final n = win.length;
    final start = math.max(1, n - 4);
    final daily = <Set<HealthMetricKind>>[];
    for (var i = start; i < n; i++) {
      if (i == n - 1) {
        daily.add(HealthMonitor.concerningKinds(todayStatuses));
        continue;
      }
      final idx = history.length - (n - 1) + i;
      final rec = history[idx];
      // Reuse that day's own statuses when its result is known (identical
      // by construction: same history, same rules); else recompute.
      final statuses =
          known[rec.date]?.health.metrics ??
          HealthMonitor.evaluate(rec, history.sublist(0, idx), window: window);
      daily.add(HealthMonitor.concerningKinds(statuses));
    }
    return HealthMonitor.alertFrom(daily);
  }

  static ReadinessSwc? _readiness(
    DayRecord today,
    List<DayRecord> history,
    int window,
  ) {
    final seg = Baselines.segment(today, history, Metric.hrv);
    if (!seg.exists) return null;
    final lnWindow = <double>[
      for (final r in _window(history, today, Readiness.windowNights))
        if (Inputs.hrv(r) case final v?)
          if (seg.seg.matches(r.provenance[Metric.hrv])) math.log(v),
    ];
    final lnBaseline = [
      for (final v in Baselines.values(
        history,
        Metric.hrv,
        seg.seg,
        window: window,
      ))
        math.log(v),
    ];
    return Readiness.compute(lnWindow: lnWindow, lnBaseline: lnBaseline);
  }
}
