// Resolver: raw rows → one DayRecord per day, picking ONE source per metric
// by priority and, within Health Connect, ONE origin app per metric
// (source_choice.dart; never summing or averaging across apps), and
// stamping Provenance (source, definition, origin, device).
//
// Pure Dart (no Flutter, no plugins, no I/O) so it runs identically on the
// sqlite path, in memory and in tests.
//
// Day assignment:
//   * sleep sessions → the day they END on (wake day);
//   * nightly scalars (resp, skin temp, SpO2, GHAPI HRV) → the wake day of
//     the sleep session that contains them, else nightKey(t) (18:00 cut);
//   * Health Connect SpO2 samples count only INSIDE a sleep session
//     (daytime spot checks are dropped), so HC SpO2 stays nightly;
//   * daily scalars (RHR, VO2 max, steps, weight) → their civil day;
//   * nightly HRV = mean of RMSSD samples inside the MAIN sleep
//     (hc_sleep_mean_rmssd) unless a Google Health deep-sleep value exists.

import 'dart:math' as math;

import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../common/time.dart';
import '../db/raw_rows.dart';
import 'definitions.dart';
import 'sleep_dedup.dart';
import 'source_choice.dart';

class ResolverConfig {
  const ResolverConfig({
    required this.mode,
    required this.now,
    this.enabled = const {
      SourceKind.healthConnect,
      SourceKind.googleHealthApi,
      SourceKind.ble,
      SourceKind.takeout,
      SourceKind.context,
    },
    this.minHrvSamples = 3,
    this.origins = const {},
  });

  final DataMode mode;
  final DateTime now;

  /// The persisted origin app per metric (Health Connect and context rows).
  /// A metric without a plan gets one computed from the rows at hand, so
  /// apps are never mixed either way.
  final Map<Metric, OriginPlan> origins;

  ResolverConfig withOrigins(Map<Metric, OriginPlan> plans) => ResolverConfig(
    mode: mode,
    now: now,
    enabled: enabled,
    minHrvSamples: minHrvSamples,
    origins: plans,
  );

  /// Live-mode sources the user has switched on.
  final Set<SourceKind> enabled;
  final int minHrvSamples;

  Set<SourceKind> get allowed => mode == DataMode.demo
      ? const {SourceKind.demo}
      : (enabled.difference(const {SourceKind.demo}));

  List<SourceKind> priority(Metric m) => mode == DataMode.demo
      ? const [SourceKind.demo]
      : [
          for (final s in kLivePriority[m] ?? const <SourceKind>[])
            if (allowed.contains(s)) s,
        ];

  /// Sources whose raw RMSSD samples may define nightly HRV.
  List<SourceKind> get hrvSampleSources => mode == DataMode.demo
      ? const [SourceKind.demo]
      : [
          for (final s in kHrvSamplePriority)
            if (allowed.contains(s)) s,
        ];
}

class Resolver {
  const Resolver();

  /// Sources that must be loaded for [cfg].
  static Set<SourceKind> sourcesFor(ResolverConfig cfg) => cfg.allowed;

  /// [utcHr]: emit intraday HR samples as UTC instants (see
  /// [HrDay.toSamples]); only for callers that persist or score them, never
  /// for records the UI reads directly.
  List<DayRecord> resolve(
    RawRows rows,
    String from,
    String to,
    ResolverConfig cfg, {
    bool utcHr = false,
  }) {
    final allowed = cfg.allowed;
    final cutoff = cfg.now.add(const Duration(minutes: 5));
    bool ok(RawRow r) => allowed.contains(r.source) && !r.end.isAfter(cutoff);

    // One origin app per metric and day (Health Connect / context rows).
    final plans = {
      ...plansFor(rows, today: DayKey.of(cfg.now)),
      ...cfg.origins,
    };
    bool hasOrigins(SourceKind s) =>
        s == SourceKind.healthConnect || s == SourceKind.context;
    bool chosen(Metric m, RawRow r, String day) {
      if (!hasOrigins(r.source)) return true;
      final plan = plans[m];
      return plan == null || (r.originPackage ?? '') == plan.originOn(day);
    }

    String? originFor(Metric m, SourceKind src, String day) =>
        hasOrigins(src) ? plans[m]?.originOn(day) : null;

    // ── Pre-group ────────────────────────────────────────────────────────
    final sleep = dedupSleep([
      for (final r in rows.sleep)
        if (ok(r) && chosen(Metric.sleep, r, dayKeyOf(r.end))) r,
    ]);
    final sleepByDay = <String, Map<SourceKind, List<RawSleepRow>>>{};
    for (final s in sleep) {
      sleepByDay
          .putIfAbsent(dayKeyOf(s.end), () => {})
          .putIfAbsent(s.source, () => [])
          .add(s);
    }

    // Sessions as sorted int intervals (±1 h) for fast containment lookups.
    const hourMs = 3600000;
    final sStart = [
      for (final s in sleep) s.start.millisecondsSinceEpoch - hourMs,
    ];
    final sEnd = [for (final s in sleep) s.end.millisecondsSinceEpoch + hourMs];
    final sKey = [for (final s in sleep) dayKeyOf(s.end)];
    // Number of sessions whose (padded) start is at or before m.
    int startsUpTo(int m) {
      var lo = 0, hi = sStart.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (sStart[mid] <= m) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    String nightDay(DateTime t) {
      final m = t.millisecondsSinceEpoch;
      // Last session starting at or before m.
      final lo = startsUpTo(m);
      for (var i = lo - 1; i >= 0 && i >= lo - 3; i--) {
        if (m <= sEnd[i]) return sKey[i];
      }
      return nightKey(t);
    }

    // Strictly inside a sleep session (the exact bounds, without the pad).
    bool inSleep(DateTime t) {
      final m = t.millisecondsSinceEpoch;
      final lo = startsUpTo(m - hourMs);
      for (var i = lo - 1; i >= 0 && i >= lo - 3; i--) {
        if (m <= sEnd[i] - hourMs) return true;
      }
      return false;
    }

    final scalarByDay =
        <String, Map<ScalarKind, Map<SourceKind, List<RawScalarRow>>>>{};
    for (final r in rows.scalars.where(ok)) {
      // Health Connect SpO2 is nightly: drop samples outside every sleep
      // session (daytime spot checks). GHAPI rows are nightly values already.
      if (r.source == SourceKind.healthConnect &&
          (r.scalar == ScalarKind.spo2Avg || r.scalar == ScalarKind.spo2Min) &&
          !inSleep(r.start)) {
        continue;
      }
      final day =
          r.day ??
          switch (r.scalar) {
            ScalarKind.resp ||
            ScalarKind.skinTempDelta ||
            ScalarKind.spo2Avg ||
            ScalarKind.spo2Min ||
            ScalarKind.hrvDaily ||
            ScalarKind.hrvDeepSleep => nightDay(r.start),
            _ => dayKeyOf(r.start),
          };
      final metric = switch (r.scalar) {
        ScalarKind.rhr => Metric.restingHr,
        ScalarKind.resp => Metric.respiratoryRate,
        ScalarKind.skinTempDelta => Metric.skinTemp,
        ScalarKind.spo2Avg || ScalarKind.spo2Min => Metric.spo2,
        ScalarKind.vo2max => Metric.vo2max,
        ScalarKind.steps => Metric.steps,
        ScalarKind.weight => Metric.weight,
        _ => null,
      };
      if (metric != null && !chosen(metric, r, day)) continue;
      scalarByDay
          .putIfAbsent(day, () => {})
          .putIfAbsent(r.scalar, () => {})
          .putIfAbsent(r.source, () => [])
          .add(r);
    }

    // Every origin's HR by day (sleeping HR reads the SLEEP's own app).
    final allHrDays = <String, List<HrDay>>{};
    for (final d in rows.hrDays) {
      if (allowed.contains(d.source)) {
        allHrDays.putIfAbsent(d.date, () => []).add(d);
      }
    }
    final hrDays = <String, Map<SourceKind, HrDay>>{};
    for (final d in rows.hrDays) {
      if (!allowed.contains(d.source)) continue;
      if (hasOrigins(d.source)) {
        final want = plans[Metric.hr]?.originOn(d.date);
        if (want != null && d.origin != want) continue;
      }
      hrDays.putIfAbsent(d.date, () => {})[d.source] = d;
    }

    final hrvBySource = <SourceKind, List<RawHrvRow>>{};
    for (final r in rows.hrv.where(ok)) {
      // ACTIVE / MANUAL readings are spot checks: never nightly HRV.
      if (r.isSpot) continue;
      if (!chosen(Metric.hrv, r, nightDay(r.t))) continue;
      hrvBySource.putIfAbsent(r.source, () => []).add(r);
    }
    final hrvMs = <SourceKind, List<int>>{};
    for (final e in hrvBySource.entries) {
      e.value.sort((a, b) => a.t.compareTo(b.t));
      hrvMs[e.key] = [for (final r in e.value) r.t.millisecondsSinceEpoch];
    }

    final workoutsByDay = <String, Map<SourceKind, List<RawWorkoutRow>>>{};
    for (final w in rows.workouts.where(ok)) {
      if (!chosen(Metric.workouts, w, dayKeyOf(w.start))) continue;
      workoutsByDay
          .putIfAbsent(dayKeyOf(w.start), () => {})
          .putIfAbsent(w.source, () => [])
          .add(w);
    }

    final lastByDay = <String, DateTime>{};
    void seen(String day, DateTime t) {
      final cur = lastByDay[day];
      if (cur == null || t.isAfter(cur)) lastByDay[day] = t;
    }

    for (final e in sleepByDay.entries) {
      for (final l in e.value.values) {
        for (final s in l) {
          seen(e.key, s.end);
        }
      }
    }
    for (final e in scalarByDay.entries) {
      for (final m in e.value.values) {
        for (final l in m.values) {
          for (final s in l) {
            seen(e.key, s.end);
          }
        }
      }
    }
    for (final e in hrDays.entries) {
      for (final d in e.value.values) {
        if (d.lastT != null) seen(e.key, d.lastT!);
      }
    }
    for (final e in workoutsByDay.entries) {
      for (final l in e.value.values) {
        for (final w in l) {
          seen(e.key, w.end);
        }
      }
    }
    for (final l in hrvBySource.values) {
      for (final r in l) {
        seen(nightDay(r.t), r.t);
      }
    }

    // ── Per day ──────────────────────────────────────────────────────────
    final out = <DayRecord>[];
    for (final date in DayKey.range(from, to)) {
      final rec = DayRecord(date: date);
      final prov = rec.provenance;

      // Sleep.
      final daySleep = sleepByDay[date] ?? const {};
      SleepSession? main;
      for (final src in cfg.priority(Metric.sleep)) {
        final list = daySleep[src];
        if (list == null || list.isEmpty) continue;
        final sessions = _sessions(list);
        rec.sleepSessions.addAll(sessions);
        prov[Metric.sleep] = Provenance(
          src,
          Definitions.sleep(src),
          device: _device(list),
          origin: originFor(Metric.sleep, src, date),
        );
        main = rec.mainSleep;
        break;
      }

      // HRV.
      final scal = scalarByDay[date] ?? const {};
      final ghOk =
          cfg.mode == DataMode.live &&
          cfg.allowed.contains(SourceKind.googleHealthApi);
      List<RawScalarRow>? ghScalar(ScalarKind k) {
        if (!ghOk) return null;
        final m = scal[k];
        return m == null ? null : m[SourceKind.googleHealthApi];
      }

      final deep = ghScalar(ScalarKind.hrvDeepSleep);
      List<RawHrvRow> inMain(SourceKind s) {
        final l = hrvBySource[s];
        final ms = hrvMs[s];
        if (l == null || ms == null || main == null) return const [];
        final a = main.start.millisecondsSinceEpoch;
        final b = main.end.millisecondsSinceEpoch;
        var lo = 0, hi = ms.length;
        while (lo < hi) {
          final mid = (lo + hi) >> 1;
          if (ms[mid] < a) {
            lo = mid + 1;
          } else {
            hi = mid;
          }
        }
        final out = <RawHrvRow>[];
        for (var i = lo; i < ms.length && ms[i] <= b; i++) {
          out.add(l[i]);
        }
        return out;
      }

      if (deep != null && deep.isNotEmpty) {
        rec.hrvRmssd = _latest(deep).value;
        prov[Metric.hrv] = Provenance(
          SourceKind.googleHealthApi,
          Definitions.hrvDeepSleep,
          device: _device(deep),
        );
        for (final s in cfg.hrvSampleSources) {
          final xs = inMain(s);
          if (xs.isNotEmpty) {
            rec.hrvSamples.addAll(xs.map((x) => HrvSample(x.t, x.rmssd)));
            break;
          }
        }
      } else {
        final single = plans[Metric.hrv]?.shape == 'single';
        for (final s in cfg.hrvSampleSources) {
          if (single && hasOrigins(s)) {
            // N3: 1–2 nightly records of a "single"-shape app, assigned to
            // the wake day; UNKNOWN only inside the main sleep (so daytime
            // spot checks can't leak in). Mean.
            final ms = main == null ? null : (main.start, main.end);
            final xs = [
              for (final x in hrvBySource[s] ?? const <RawHrvRow>[])
                if (nightDay(x.t) == date &&
                    (x.recordingMethod == 'automatic' ||
                        (ms != null &&
                            !x.t.isBefore(ms.$1) &&
                            !x.t.isAfter(ms.$2))))
                  x,
            ];
            if (xs.isEmpty) continue;
            rec.hrvRmssd = mean(xs.map((x) => x.rmssd));
            rec.hrvSamples.addAll(xs.map((x) => HrvSample(x.t, x.rmssd)));
            prov[Metric.hrv] = Provenance(
              s,
              Definitions.hrvNightly,
              device: _device(xs),
              origin: originFor(Metric.hrv, s, date),
            );
            break;
          }
          final xs = inMain(s);
          if (xs.length < cfg.minHrvSamples) continue;
          rec.hrvRmssd = mean(xs.map((x) => x.rmssd));
          rec.hrvSamples.addAll(xs.map((x) => HrvSample(x.t, x.rmssd)));
          prov[Metric.hrv] = Provenance(
            s,
            Definitions.hrvSleepMean(s),
            device: _device(xs),
            origin: originFor(Metric.hrv, s, date),
          );
          break;
        }
        final daily = ghScalar(ScalarKind.hrvDaily);
        if (rec.hrvRmssd == null && daily != null && daily.isNotEmpty) {
          rec.hrvRmssd = _latest(daily).value;
          prov[Metric.hrv] = Provenance(
            SourceKind.googleHealthApi,
            Definitions.hrvGhapiDaily,
            device: _device(daily),
          );
        }
      }

      // Scalars.
      ({SourceKind src, List<RawScalarRow> rows})? pick(
        Metric m,
        ScalarKind k,
      ) {
        final bySrc = scal[k];
        if (bySrc == null) return null;
        for (final s in cfg.priority(m)) {
          final l = bySrc[s];
          if (l != null && l.isNotEmpty) return (src: s, rows: l);
        }
        return null;
      }

      final rhr = pick(Metric.restingHr, ScalarKind.rhr);
      if (rhr != null) {
        rec.restingHr = _latest(rhr.rows).value;
        prov[Metric.restingHr] = Provenance(
          rhr.src,
          Definitions.rhr(rhr.src),
          device: _device(rhr.rows),
          origin: originFor(Metric.restingHr, rhr.src, date),
        );
      }
      final resp = pick(Metric.respiratoryRate, ScalarKind.resp);
      if (resp != null) {
        rec.respiratoryRate = mean(resp.rows.map((r) => r.value));
        prov[Metric.respiratoryRate] = Provenance(
          resp.src,
          Definitions.resp(resp.src),
          device: _device(resp.rows),
          origin: originFor(Metric.respiratoryRate, resp.src, date),
        );
      }
      final skin = pick(Metric.skinTemp, ScalarKind.skinTempDelta);
      if (skin != null) {
        rec.skinTempDelta = mean(skin.rows.map((r) => r.value));
        prov[Metric.skinTemp] = Provenance(
          skin.src,
          Definitions.skinTemp(skin.src),
          device: _device(skin.rows),
          origin: originFor(Metric.skinTemp, skin.src, date),
        );
      }
      final spo2 = pick(Metric.spo2, ScalarKind.spo2Avg);
      if (spo2 != null) {
        rec.spo2Avg = mean(spo2.rows.map((r) => r.value));
        final mins = scal[ScalarKind.spo2Min]?[spo2.src];
        if (mins != null && mins.isNotEmpty) {
          rec.spo2Min = mins.map((r) => r.value).reduce(math.min);
        }
        prov[Metric.spo2] = Provenance(
          spo2.src,
          Definitions.spo2(spo2.src),
          device: _device(spo2.rows),
          origin: originFor(Metric.spo2, spo2.src, date),
        );
      }
      final vo2 = pick(Metric.vo2max, ScalarKind.vo2max);
      if (vo2 != null) {
        rec.vo2max = _latest(vo2.rows).value;
        prov[Metric.vo2max] = Provenance(
          vo2.src,
          Definitions.vo2max(vo2.src),
          device: _device(vo2.rows),
          origin: originFor(Metric.vo2max, vo2.src, date),
        );
      }
      final steps = pick(Metric.steps, ScalarKind.steps);
      if (steps != null) {
        // One app's own step records (never topped up from another app:
        // the phone-steps gap fill was cut, it mixed origins).
        final total = steps.rows.fold<double>(0, (a, r) => a + r.value);
        rec.steps = total.round();
        prov[Metric.steps] = Provenance(
          steps.src,
          Definitions.steps(steps.src),
          device: _device(steps.rows),
          origin: originFor(Metric.steps, steps.src, date),
        );
      }
      final weight = pick(Metric.weight, ScalarKind.weight);
      if (weight != null) {
        rec.weightKg = _latest(weight.rows).value;
        prov[Metric.weight] = Provenance(
          weight.src,
          Definitions.weight(weight.src),
          device: _device(weight.rows),
          origin: originFor(Metric.weight, weight.src, date),
        );
      }

      // Heart rate (1-minute buckets).
      HrDay? hrDay;
      final hd = hrDays[date] ?? const {};
      for (final s in cfg.priority(Metric.hr)) {
        final d = hd[s];
        if (d == null || d.minutesWithData == 0) continue;
        hrDay = d;
        rec.hrSamples.addAll(d.toSamples(utc: utcHr));
        prov[Metric.hr] = Provenance(
          s,
          Definitions.hr(s),
          device: d.device,
          origin: originFor(Metric.hr, s, date),
        );
        break;
      }

      // Workouts: primary source by priority + non-overlapping BLE sessions
      // recorded on the live screen (sessions are unioned, never averaged).
      final dw = workoutsByDay[date] ?? const {};
      final picked = <RawWorkoutRow>[];
      SourceKind? wSrc;
      for (final s in cfg.priority(Metric.workouts)) {
        final l = dw[s];
        if (l == null || l.isEmpty) continue;
        picked.addAll(l);
        wSrc = s;
        break;
      }
      if (cfg.mode == DataMode.live && allowed.contains(SourceKind.ble)) {
        for (final b in dw[SourceKind.ble] ?? const <RawWorkoutRow>[]) {
          final clash = picked.any(
            (p) =>
                overlapMs(p.start, p.end, b.start, b.end) >
                0.5 * b.end.difference(b.start).inMilliseconds,
          );
          if (!clash) picked.add(b);
        }
        wSrc ??= picked.isEmpty ? null : SourceKind.ble;
      }
      picked.sort((a, b) => a.start.compareTo(b.start));
      for (final w in picked) {
        rec.workouts.add(
          Workout(
            id: '${w.source.code}:${w.sourceRecordId}',
            name: w.name,
            start: w.start,
            end: w.end,
            averageHr: w.avgHr ?? _avgHr(hrDay, w.start, w.end),
            calories: w.calories,
            distanceM: w.distanceM,
          ),
        );
      }
      if (wSrc != null) {
        prov[Metric.workouts] = Provenance(
          wSrc,
          Definitions.workouts(wSrc),
          device: _device(picked),
          origin: originFor(Metric.workouts, wSrc, date),
        );
      }

      // Sleeping HR (HRV ladder S1): 4 h from main-sleep start + 30 min,
      // HR from the sleep's own app, only when the gate passes. Never
      // copied into restingHr.
      final sp = prov[Metric.sleep];
      if (main != null && sp != null && hasOrigins(sp.source)) {
        final v = sleepingHr4h(main, [
          for (final day in {dayKeyOf(main.start), dayKeyOf(main.end)})
            for (final d in allHrDays[day] ?? const <HrDay>[])
              if (d.source == sp.source && d.origin == (sp.origin ?? '')) d,
        ]);
        if (v != null) {
          rec.sleepingHr4h = v;
          prov[Metric.sleepingHr] = Provenance(
            sp.source,
            Definitions.sleepingHr4h,
            device: sp.device,
            origin: sp.origin,
          );
        }
      }

      rec.lastDataAt = lastByDay[date];
      if (prov.isEmpty) continue; // days without data are omitted
      out.add(rec);
    }
    return out;
  }

  static List<SleepSession> _sessions(List<RawSleepRow> rows) {
    final sessions = <SleepSession>[];
    for (final r in rows) {
      final stages = [...r.stages]..sort((a, b) => a.start.compareTo(b.start));
      double asleep = 0, awake = 0;
      for (final s in stages) {
        if (s.stage == SleepStage.awake) {
          awake += s.minutes;
        } else if (s.stage.isAsleep || s.stage == SleepStage.unknown) {
          // unknown = Health Connect "asleep, stage not specified"
          asleep += s.minutes;
        }
      }
      final inBed = r.end.difference(r.start).inSeconds / 60.0;
      if (stages.isEmpty) asleep = inBed;
      sessions.add(
        SleepSession(
          id: '${r.source.code}:${r.sourceRecordId}',
          start: r.start,
          end: r.end,
          minutesAsleep: r.minutesAsleep ?? asleep,
          minutesAwake: r.minutesAwake ?? awake,
          stages: stages,
          isMainSleep: false,
        ),
      );
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));
    // Main sleep: upstream flag if the source has one, else the longest.
    var mainIdx = -1;
    for (var i = 0; i < rows.length && mainIdx < 0; i++) {
      if (rows[i].isMain == true) {
        final id = '${rows[i].source.code}:${rows[i].sourceRecordId}';
        mainIdx = sessions.indexWhere((s) => s.id == id);
      }
    }
    if (mainIdx < 0) {
      var best = 0.0;
      for (var i = 0; i < sessions.length; i++) {
        if (sessions[i].minutesAsleep > best || mainIdx < 0) {
          best = sessions[i].minutesAsleep;
          mainIdx = i;
        }
      }
    }
    return [
      for (var i = 0; i < sessions.length; i++)
        SleepSession(
          id: sessions[i].id,
          start: sessions[i].start,
          end: sessions[i].end,
          minutesAsleep: sessions[i].minutesAsleep,
          minutesAwake: sessions[i].minutesAwake,
          stages: sessions[i].stages,
          isMainSleep: i == mainIdx,
        ),
    ];
  }

  /// Sleeping-HR window: from sleep start + [sleepHrOffsetMin] for
  /// [sleepHrWindowMin] minutes (Nuuttila 2024's "4H").
  static const int sleepHrOffsetMin = 30;
  static const int sleepHrWindowMin = 240;

  /// Gate: a main sleep of at least 4 h 30 min, and at least 80 % of the
  /// window's 5-minute bins holding a sample (research/09b §3; 80 % is ours).
  static const int sleepHrMinSleepMin = 270;
  static const int sleepHrBinMin = 5;
  static const double sleepHrMinBinShare = 0.8;

  /// Mean of the 5-minute bin means of [days]' HR inside the window, or null
  /// when the gate fails.
  static double? sleepingHr4h(SleepSession main, List<HrDay> days) {
    if (main.end.difference(main.start).inMinutes < sleepHrMinSleepMin) {
      return null;
    }
    final a = main.start.add(const Duration(minutes: sleepHrOffsetMin));
    final b = a.add(const Duration(minutes: sleepHrWindowMin));
    const bins = sleepHrWindowMin ~/ sleepHrBinMin;
    final sum = List<double>.filled(bins, 0);
    final cnt = List<int>.filled(bins, 0);
    for (final d in days) {
      for (final s in d.toSamples()) {
        if (s.t.isBefore(a) || !s.t.isBefore(b)) continue;
        final i = s.t.difference(a).inMinutes ~/ sleepHrBinMin;
        if (i < 0 || i >= bins) continue;
        sum[i] += s.bpm;
        cnt[i]++;
      }
    }
    var covered = 0;
    var acc = 0.0;
    for (var i = 0; i < bins; i++) {
      if (cnt[i] == 0) continue;
      covered++;
      acc += sum[i] / cnt[i];
    }
    if (covered < sleepHrMinBinShare * bins) return null;
    return acc / covered;
  }

  static T _latest<T extends RawRow>(List<T> rows) =>
      rows.reduce((a, b) => b.start.isAfter(a.start) ? b : a);

  static String? _device(Iterable<RawRow> rows) {
    for (final r in rows) {
      if (r.device != null && r.device!.isNotEmpty) return r.device;
    }
    return null;
  }

  static double? _avgHr(HrDay? day, DateTime start, DateTime end) {
    if (day == null) return null;
    final a = start.difference(day.dayStart).inMinutes;
    final b = end.difference(day.dayStart).inMinutes;
    var sum = 0, n = 0;
    for (var i = math.max(0, a); i < math.min(day.tenths.length, b); i++) {
      if (day.tenths[i] > 0) {
        sum += day.tenths[i];
        n++;
      }
    }
    return n < 3 ? null : sum / n / 10.0;
  }
}
