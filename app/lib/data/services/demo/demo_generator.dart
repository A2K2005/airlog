// Seeded synthetic "Fitbit Air" source for demo mode.
//
// Idea ported from Pulse `Core/Demo/DemoData.swift` (Luraxx/pulse @ 1f8975c,
// Apache-2.0, see third_party/pulse/NOTICE): a deterministic xorshift RNG,
// a weekly training rhythm, recovery dips after hard days and occasional bad
// nights. Rewritten and extended here to emit RAW rows (the same shape Health
// Connect gives us) instead of finished day records, so demo data goes
// through the real resolver + engine pipeline:
//   * circadian HR at 1/min with a sleep curve, stage offsets, walking bursts,
//     workouts (runs, strength, cycling) with warm-up/cool-down and EPOC,
//   * wear gaps: a ~2 h charging gap most days and one day with a 6 h gap,
//   * HRV (RMSSD) samples every ~5 min during sleep,
//   * nightly RHR / respiratory rate / skin-temperature delta / SpO2,
//   * sleep sessions built from ~90-min cycles (light/deep/REM/awake) + naps,
//   * hourly steps and occasional VO2 max,
//   * PLANTED: an illness episode on days −24..−21 (RHR +6, HRV −30 %,
//     resp +1.5, skin temp +0.6), a few poor-sleep nights, and journal
//     entries where alcohol precedes lower next-day recovery.
// Same seed + same `now` ⇒ identical output.

import 'dart:math' as math;

import '../../../domain/day_key.dart';
import '../../../domain/models.dart';
import '../../db/raw_rows.dart';

const String kDemoOrigin = 'app.airlog.demo';
// Display name only; no "(demo)": the data mode is labelled only on the
// data-mode screens (PRODUCT_PLAN §7, 2026-10-01).
const String kDemoDevice = 'Fitbit Air';

/// Bump when the generator changes so stored demo data is re-seeded.
const int kDemoGeneratorVersion = 2;

/// xorshift64 seeded through splitmix64 (so small seeds are well mixed).
class SeededRng {
  SeededRng(int seed) {
    var z = seed + 0x1E3779B97F4A7C15;
    z = (z ^ (z >>> 30)) * 0x3F58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x14D049BB133111EB;
    z = z ^ (z >>> 31);
    _s = z == 0 ? 0x2545F4914F6CDD1D : z;
  }

  late int _s;
  double? _spare;

  int nextInt64() {
    var x = _s;
    x ^= x << 13;
    x ^= x >>> 7;
    x ^= x << 17;
    _s = x;
    return x;
  }

  /// Uniform in [0, 1).
  double next() => (nextInt64() >>> 11) / 9007199254740992.0;
  double range(double a, double b) => a + (b - a) * next();
  int intRange(int a, int bExclusive) =>
      a + ((nextInt64() >>> 1) % (bExclusive - a));
  bool chance(double p) => next() < p;

  double gauss([double mean = 0, double sd = 1]) {
    final s = _spare;
    if (s != null) {
      _spare = null;
      return mean + sd * s;
    }
    double u, v, r;
    do {
      u = next() * 2 - 1;
      v = next() * 2 - 1;
      r = u * u + v * v;
    } while (r >= 1 || r == 0);
    final f = math.sqrt(-2 * math.log(r) / r);
    _spare = v * f;
    return mean + sd * u * f;
  }
}

enum _WType { intervals, tempo, easyRun, strength, ride, longRide }

class _PlannedWorkout {
  _PlannedWorkout(this.type, this.start, this.end);
  final _WType type;
  final DateTime start;
  final DateTime end;
  String get name => switch (type) {
    _WType.intervals || _WType.tempo || _WType.easyRun => 'Run',
    _WType.strength => 'Strength training',
    _WType.ride || _WType.longRide => 'Cycling',
  };
  String get activityType => switch (type) {
    _WType.intervals || _WType.tempo || _WType.easyRun => 'RUNNING',
    _WType.strength => 'STRENGTH_TRAINING',
    _WType.ride || _WType.longRide => 'BIKING',
  };

  /// Fraction of heart-rate reserve at minute [m].
  double intensity(int m) {
    final total = end.difference(start).inMinutes;
    return switch (type) {
      _WType.intervals =>
        (m >= 10 && m < total - 8 && (m ~/ 4).isEven) ? 0.88 : 0.66,
      _WType.tempo => 0.74 + 0.05 * m / total,
      _WType.easyRun => 0.64,
      _WType.strength => (m % 5) < 2 ? 0.63 : 0.47,
      _WType.ride => 0.58 + 0.07 * math.sin(m / 9),
      _WType.longRide => 0.55 + 0.06 * math.sin(m / 13),
    };
  }

  double get load => switch (type) {
    _WType.intervals => 0.9,
    _WType.tempo => 0.75,
    _WType.easyRun => 0.45,
    _WType.strength => 0.5,
    _WType.ride => 0.55,
    _WType.longRide => 0.85,
  };
}

class _Night {
  _Night(this.bed, this.wake, this.stages);
  final DateTime bed;
  final DateTime wake;
  final List<StageSpan> stages;

  SleepStage? stageAt(DateTime t) {
    for (final s in stages) {
      if (!t.isBefore(s.start) && t.isBefore(s.end)) return s.stage;
    }
    return null;
  }
}

class _Day {
  _Day(this.index, this.date);
  final int index;
  final String date;
  late DateTime start;
  late DateTime end;
  late int weekday;
  late int offset; // days before today
  double ill = 0; // 0..1 illness factor for this WAKE day
  bool poorSleep = false;
  bool longGap = false;
  final Set<JournalFactor> evening = {};
  final List<_PlannedWorkout> workouts = [];
  (DateTime, DateTime)? gap;
  (DateTime, DateTime)? nap;
  _Night? night; // night ending on this day's morning
  double hrv = 0, rhr = 0, resp = 0, skin = 0, spo2 = 0, spo2Min = 0;
  double get load => workouts.fold(0.0, (a, w) => math.max(a, w.load));
}

/// What the generator planted (for tests and the demo diagnostics text).
class DemoPlan {
  const DemoPlan({
    required this.illnessDays,
    required this.poorSleepDays,
    required this.longGapDay,
    required this.alcoholEvenings,
  });
  final List<String> illnessDays;
  final List<String> poorSleepDays;
  final String? longGapDay;
  final List<String> alcoholEvenings;
}

class DemoDataset {
  DemoDataset(this.rows, this.journal, this.plan);
  final RawRows rows;
  final List<JournalEntry> journal;
  final DemoPlan plan;
}

class DemoGenerator {
  DemoGenerator({this.seed = 42, this.days = 90, DateTime? now})
    : now = now ?? DateTime.now();

  final int seed;
  final int days;
  final DateTime now;

  late SeededRng _r;
  late double _baseHrv, _baseRhr, _baseResp, _maxHr, _vo2Base, _sleepH;

  /// The generator's own running sleep debt (minutes): a short night is
  /// followed by longer ones (sleep homeostasis), so the engine's debt
  /// varies instead of pinning at its cap.
  double _debt = 0;

  DemoDataset generate() {
    _r = SeededRng(seed);
    _baseHrv = _r.range(44, 58);
    _baseRhr = _r.range(50, 57);
    _baseResp = _r.range(13.6, 15.0);
    _maxHr = 191 - _r.range(0, 6);
    _vo2Base = _r.range(44, 48.5);
    // Habitual time ASLEEP. Slightly above the engine's structural need
    // (456 min + a strain boost of up to 45 min), as for a healthy sleeper
    // whose debt mostly stays small.
    _sleepH = _r.range(7.65, 7.9);
    _debt = 0;

    final today = DayKey.of(now);
    final first = DayKey.add(today, -(days - 1));
    final ds = <_Day>[];
    for (var i = 0; i < days; i++) {
      final d = _Day(i, DayKey.add(first, i));
      d.start = DayKey.start(d.date);
      d.end = DayKey.end(d.date);
      d.weekday = d.start.weekday;
      d.offset = days - 1 - i;
      ds.add(d);
    }
    _plantEpisodes(ds);
    for (final d in ds) {
      _planDay(d);
    }
    _ensureAlcohol(ds);
    for (var i = 0; i < ds.length; i++) {
      _planNight(ds[i], i > 0 ? ds[i - 1] : null);
    }
    for (final d in ds) {
      _planGap(d);
    }

    final rows = RawRows();
    for (var i = 0; i < ds.length; i++) {
      _emitDay(ds[i], i + 1 < ds.length ? ds[i + 1] : null, rows);
    }

    final journal = <JournalEntry>[];
    for (final d in ds) {
      final eveningOver = d.offset > 0 || now.hour >= 21;
      if (!eveningOver) continue;
      final factors = {...d.evening};
      if (d.workouts.isNotEmpty) factors.add(JournalFactor.exercised);
      final important =
          factors.contains(JournalFactor.alcohol) ||
          factors.contains(JournalFactor.sick);
      if (!important && !_r.chance(0.85)) continue;
      journal.add(JournalEntry(date: d.date, factors: factors));
    }

    return DemoDataset(
      rows,
      journal,
      DemoPlan(
        illnessDays: [
          for (final d in ds)
            if (d.ill >= 1) d.date,
        ],
        poorSleepDays: [
          for (final d in ds)
            if (d.poorSleep) d.date,
        ],
        longGapDay: ds.where((d) => d.longGap).map((d) => d.date).firstOrNull,
        alcoholEvenings: [
          for (final d in ds)
            if (d.evening.contains(JournalFactor.alcohol)) d.date,
        ],
      ),
    );
  }

  // ── Planning ───────────────────────────────────────────────────────────

  void _plantEpisodes(List<_Day> ds) {
    for (final d in ds) {
      if (d.offset >= 21 && d.offset <= 24) d.ill = 1;
      if (d.offset == 20) d.ill = 0.4;
    }
    final poor = <int>{
      for (final base in [9, 30, 47, 63, 80]) base + _r.intRange(0, 3),
    };
    for (final d in ds) {
      if (poor.contains(d.offset) && d.ill == 0 && d.offset > 0) {
        d.poorSleep = true;
      }
    }
    final gapOffset = days > 45 ? 40 : days ~/ 2;
    for (final d in ds) {
      if (d.offset == gapOffset && d.offset > 0) d.longGap = true;
    }
  }

  DateTime _at(_Day d, double hour) =>
      d.start.add(Duration(seconds: (hour * 3600).round()));

  void _planDay(_Day d) {
    final sickEvening = d.offset >= 20 && d.offset <= 25;
    final weekend =
        d.weekday == DateTime.friday || d.weekday == DateTime.saturday;
    if (sickEvening) {
      d.evening.add(JournalFactor.sick);
    } else {
      if (_r.chance(weekend ? 0.5 : 0.05)) d.evening.add(JournalFactor.alcohol);
      if (_r.chance(0.1)) d.evening.add(JournalFactor.lateCaffeine);
      if (_r.chance(0.12)) d.evening.add(JournalFactor.lateMeal);
      if (!weekend && _r.chance(0.15)) d.evening.add(JournalFactor.stress);
      if (_r.chance(0.3)) d.evening.add(JournalFactor.screenBeforeBed);
      if (_r.chance(0.18)) d.evening.add(JournalFactor.meditation);
    }
    if (d.ill > 0 || sickEvening) return;

    void add(_WType t, double startH, double minutes) {
      final s = _at(d, startH);
      d.workouts.add(
        _PlannedWorkout(t, s, s.add(Duration(minutes: minutes.round()))),
      );
    }

    final evening = _r.range(17.6, 18.8);
    switch (d.weekday) {
      case DateTime.monday:
        if (_r.chance(0.85)) add(_WType.intervals, evening, _r.range(45, 55));
      case DateTime.tuesday:
        if (_r.chance(0.8)) add(_WType.strength, evening, _r.range(48, 62));
      case DateTime.wednesday:
        if (_r.chance(0.35)) add(_WType.ride, evening, _r.range(40, 55));
      case DateTime.thursday:
        if (_r.chance(0.85)) add(_WType.tempo, evening, _r.range(38, 50));
      case DateTime.friday:
        if (_r.chance(0.55)) {
          add(_WType.strength, _r.range(7.8, 8.4), _r.range(45, 55));
        }
      case DateTime.saturday:
        if (_r.chance(0.8)) {
          add(_WType.longRide, _r.range(9.2, 10.0), _r.range(85, 120));
        }
      case DateTime.sunday:
        if (_r.chance(0.3)) {
          add(_WType.easyRun, _r.range(9.5, 10.5), _r.range(40, 52));
        }
    }
    if (d.longGap) {
      // Workouts on the 6-hour-gap day happen after the gap.
      d.workouts.removeWhere((w) => w.start.hour < 16);
    }
    if (_r.chance(0.08)) {
      final s = _at(d, _r.range(14.0, 15.5));
      d.nap = (s, s.add(Duration(minutes: _r.range(20, 40).round())));
    }
  }

  void _ensureAlcohol(List<_Day> ds) {
    // Journal correlations need >= 5 days with and >= 5 without.
    var n = ds.where((d) => d.evening.contains(JournalFactor.alcohol)).length;
    for (final d in ds.reversed) {
      if (n >= 7 || ds.length < 30) break;
      if (d.weekday == DateTime.saturday &&
          d.ill == 0 &&
          !d.evening.contains(JournalFactor.sick) &&
          !d.evening.contains(JournalFactor.alcohol)) {
        d.evening.add(JournalFactor.alcohol);
        n++;
      }
    }
  }

  void _planNight(_Day d, _Day? prev) {
    final alcohol = prev?.evening.contains(JournalFactor.alcohol) ?? false;
    final caffeine =
        prev?.evening.contains(JournalFactor.lateCaffeine) ?? false;
    final meditation =
        prev?.evening.contains(JournalFactor.meditation) ?? false;
    final stress = prev?.evening.contains(JournalFactor.stress) ?? false;
    final loadPrev = prev?.load ?? 0.3;
    final weekendNight =
        prev != null &&
        (prev.weekday == DateTime.friday || prev.weekday == DateTime.saturday);

    // Nightly physiology for wake day d.
    final i = d.index.toDouble();
    final week = math.sin(2 * math.pi * i / 7 + seed % 7);
    final slow = math.sin(2 * math.pi * i / 29 + seed % 5);
    d.hrv =
        _baseHrv *
        (1 + 0.06 * week + 0.07 * slow) *
        (1 - 0.14 * loadPrev) *
        (alcohol ? 0.78 : 1) *
        (meditation ? 1.04 : 1) *
        (stress ? 0.94 : 1) *
        (d.poorSleep ? 0.85 : 1) *
        math.exp(_r.gauss(0, 0.06)) *
        (1 - 0.30 * d.ill);
    d.rhr =
        _baseRhr -
        1.2 * slow +
        2.5 * loadPrev +
        (alcohol ? 4 : 0) +
        (d.poorSleep ? 1.5 : 0) +
        _r.gauss(0, 0.8) +
        6 * d.ill;
    d.resp = _baseResp + _r.gauss(0, 0.18) + (alcohol ? 0.6 : 0) + 1.5 * d.ill;
    d.skin = _r.gauss(0, 0.1) + (alcohol ? 0.25 : 0) + 0.6 * d.ill;
    d.spo2 = 96.4 + _r.gauss(0, 0.4) - 1.2 * d.ill;
    d.spo2Min = d.spo2 - _r.range(1.5, 3.5) - 1.5 * d.ill;

    // Timing.
    final bedClock =
        22.9 +
        _r.gauss(0, 0.35) +
        (weekendNight ? 0.7 : 0) +
        (alcohol ? 0.4 : 0) +
        (caffeine ? 0.3 : 0) -
        (d.ill > 0 ? 0.5 : 0);
    // In bed = time asleep + ~20 min awake (latency, brief wakes).
    var inBed =
        _sleepH * 60 +
        20 +
        _r.gauss(0, 24) +
        (weekendNight ? 30 : 0) -
        (alcohol ? 30 : 0) -
        (stress ? 15 : 0) +
        math.min(60.0, 0.35 * _debt) +
        (d.ill > 0 ? 55 : 0);
    if (d.poorSleep) inBed = _r.range(275, 315);
    final bed = _at(d, bedClock - 24);
    var wake = bed.add(Duration(minutes: inBed.round()));
    final latest = _at(d, 10.5), earliest = _at(d, 5.2);
    if (wake.isAfter(latest)) wake = latest;
    if (wake.isBefore(earliest)) wake = earliest;
    // Demo nicety: if the app is opened before today's planned wake-up but
    // after >= 4 h in bed, end the demo night just before "now" so today
    // already has a recovery (a real band would still be mid-night).
    if (d.offset == 0 &&
        wake.isAfter(now) &&
        now.difference(bed).inHours >= 4) {
      wake = now.subtract(Duration(minutes: 5 + _r.intRange(0, 10)));
    }
    d.night = _Night(
      bed,
      wake,
      _stages(
        bed,
        wake,
        alcohol: alcohol,
        caffeine: caffeine,
        poor: d.poorSleep,
        ill: d.ill,
      ),
    );
    final asleep = d.night!.stages
        .where((s) => s.stage.isAsleep)
        .fold(0.0, (a, s) => a + s.minutes);
    final need = 456 + 45 * ((loadPrev - 0.3) / 0.6).clamp(0.0, 1.0) * 0.6;
    _debt = (_debt + math.min(180.0, need - asleep)).clamp(0.0, 300.0);
  }

  List<StageSpan> _stages(
    DateTime bed,
    DateTime wake, {
    required bool alcohol,
    required bool caffeine,
    required bool poor,
    required double ill,
  }) {
    final raw = <StageSpan>[];
    var t = bed;
    void push(SleepStage s, double minutes) {
      if (!t.isBefore(wake) || minutes <= 0) return;
      var e = t.add(Duration(seconds: (minutes * 60).round()));
      if (e.isAfter(wake)) e = wake;
      raw.add(StageSpan(s, t, e));
      t = e;
    }

    push(SleepStage.awake, _r.range(5, 16) + (caffeine ? 12 : 0));
    final end = wake.subtract(Duration(minutes: _r.range(2, 8).round()));
    var k = 0;
    while (t.isBefore(end)) {
      final len = _r.range(84, 100);
      var deep = math.max(0.03, 0.34 - 0.1 * k) * (1 - 0.08 * ill);
      var rem = math.min(0.38, 0.1 + 0.07 * k);
      if (alcohol && k < 2) {
        deep *= 0.75;
        rem *= 0.5;
      }
      if (poor) deep *= 0.8;
      final light = 1 - deep - rem;
      push(SleepStage.light, len * light * 0.6);
      push(SleepStage.deep, len * deep);
      push(SleepStage.light, len * light * 0.4);
      push(SleepStage.rem, len * rem);
      final wakeP = poor ? 0.7 : (alcohol && k >= 2 ? 0.55 : 0.33);
      if (_r.chance(wakeP)) {
        push(SleepStage.awake, poor ? _r.range(5, 18) : _r.range(1.5, 6));
      }
      k++;
    }
    push(SleepStage.awake, wake.difference(t).inSeconds / 60.0);
    // Merge adjacent spans of the same stage.
    final out = <StageSpan>[];
    for (final s in raw) {
      if (out.isNotEmpty &&
          out.last.stage == s.stage &&
          out.last.end == s.start) {
        out[out.length - 1] = StageSpan(s.stage, out.last.start, s.end);
      } else {
        out.add(s);
      }
    }
    return out;
  }

  void _planGap(_Day d) {
    if (d.longGap) {
      d.gap = (_at(d, 9.5), _at(d, 15.5));
      return;
    }
    if (!_r.chance(0.85)) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      final s = _at(d, _r.range(9.5, 19.0));
      final e = s.add(Duration(minutes: _r.range(100, 130).round()));
      final clash =
          d.workouts.any(
            (w) =>
                s.isBefore(w.end.add(const Duration(minutes: 40))) &&
                e.isAfter(w.start),
          ) ||
          (d.nap != null && s.isBefore(d.nap!.$2) && e.isAfter(d.nap!.$1));
      if (!clash) {
        d.gap = (s, e);
        return;
      }
    }
  }

  // ── Emission ───────────────────────────────────────────────────────────

  RawScalarRow _scalar(
    ScalarKind k,
    String id,
    DateTime t,
    double v, {
    DateTime? end,
  }) => RawScalarRow(
    source: SourceKind.demo,
    sourceRecordId: id,
    recordId: id,
    originPackage: kDemoOrigin,
    device: kDemoDevice,
    ingestedAt: now,
    scalar: k,
    start: t,
    end: end,
    value: _round(v, 1000),
  );

  static double _round(double v, int scale) => (v * scale).round() / scale;

  void _emitDay(_Day d, _Day? next, RawRows rows) {
    final night = d.night!;
    final nightDone = !night.wake.isAfter(now);

    // Sleep session + nightly values (only once the night is over).
    if (nightDone) {
      final asleep = night.stages
          .where((s) => s.stage.isAsleep)
          .fold(0.0, (a, s) => a + s.minutes);
      final awake = night.stages
          .where((s) => s.stage == SleepStage.awake)
          .fold(0.0, (a, s) => a + s.minutes);
      final id = 'demo:sleep:${d.date}';
      rows.sleep.add(
        RawSleepRow(
          source: SourceKind.demo,
          sourceRecordId: id,
          recordId: id,
          originPackage: kDemoOrigin,
          device: kDemoDevice,
          ingestedAt: now,
          start: night.bed,
          end: night.wake,
          minutesAsleep: asleep,
          minutesAwake: awake,
          stages: night.stages,
        ),
      );
      final at = night.wake.subtract(const Duration(minutes: 1));
      rows.scalars
        ..add(_scalar(ScalarKind.rhr, 'demo:rhr:${d.date}', at, d.rhr))
        ..add(_scalar(ScalarKind.resp, 'demo:resp:${d.date}', at, d.resp))
        ..add(
          _scalar(ScalarKind.skinTempDelta, 'demo:skin:${d.date}', at, d.skin),
        )
        ..add(_scalar(ScalarKind.spo2Avg, 'demo:spo2:${d.date}', at, d.spo2))
        ..add(
          _scalar(ScalarKind.spo2Min, 'demo:spo2min:${d.date}', at, d.spo2Min),
        );

      // HRV samples every ~5 min, rescaled so their mean is the planted value.
      final samples = <(DateTime, double)>[];
      var t = night.bed.add(Duration(minutes: 12 + _r.intRange(0, 6)));
      final stop = night.wake.subtract(const Duration(minutes: 8));
      while (t.isBefore(stop)) {
        final st = night.stageAt(t) ?? SleepStage.light;
        final mod = switch (st) {
          SleepStage.deep => 1.12,
          SleepStage.rem => 0.9,
          SleepStage.awake => 0.85,
          _ => 1.0,
        };
        samples.add((t, d.hrv * mod * math.exp(_r.gauss(0, 0.16))));
        t = t.add(Duration(seconds: 300 + _r.intRange(-40, 41)));
      }
      if (samples.isNotEmpty) {
        final m = samples.fold(0.0, (a, s) => a + s.$2) / samples.length;
        final k = d.hrv / m;
        for (final (st, v) in samples) {
          final id = 'demo:hrv:${st.millisecondsSinceEpoch}';
          rows.hrv.add(
            RawHrvRow(
              source: SourceKind.demo,
              sourceRecordId: id,
              recordId: id,
              originPackage: kDemoOrigin,
              device: kDemoDevice,
              ingestedAt: now,
              t: st,
              rmssd: _round((v * k).clamp(8.0, 180.0), 100),
            ),
          );
        }
      }
    }

    // Nap.
    final nap = d.nap;
    if (nap != null && !nap.$2.isAfter(now)) {
      final id = 'demo:nap:${d.date}';
      final mins = nap.$2.difference(nap.$1).inSeconds / 60.0;
      rows.sleep.add(
        RawSleepRow(
          source: SourceKind.demo,
          sourceRecordId: id,
          recordId: id,
          originPackage: kDemoOrigin,
          device: kDemoDevice,
          ingestedAt: now,
          start: nap.$1,
          end: nap.$2,
          minutesAsleep: mins * 0.9,
          minutesAwake: mins * 0.1,
          stages: [
            StageSpan(
              SleepStage.awake,
              nap.$1,
              nap.$1.add(const Duration(minutes: 3)),
            ),
            StageSpan(
              SleepStage.light,
              nap.$1.add(const Duration(minutes: 3)),
              nap.$2,
            ),
          ],
        ),
      );
    }

    // Walking bursts for the waking day (commute, errands: ~95-115 bpm)
    // and longer on-your-feet blocks (chores, standing: ~85-95 bpm). They
    // give rest days a WHOOP-like strain of ~6-10 instead of ~2.
    final bursts = <(DateTime, DateTime, double)>[];
    final nb = d.ill > 0 ? 3 : _r.intRange(6, 10);
    for (var b = 0; b < nb; b++) {
      final s = _at(d, _r.range(7.5, 21.5));
      bursts.add((
        s,
        s.add(Duration(minutes: _r.range(6, 19).round())),
        d.ill > 0 ? _r.range(14, 24) : _r.range(32, 50),
      ));
    }
    final onFeet = <(int, int, double)>[];
    final nf = d.ill > 0 ? 1 : _r.intRange(3, 6);
    for (var b = 0; b < nf; b++) {
      final s = _at(d, _r.range(8.0, 20.5));
      onFeet.add((
        s.millisecondsSinceEpoch,
        s
            .add(Duration(minutes: _r.range(25, 70).round()))
            .millisecondsSinceEpoch,
        _r.range(16, 24),
      ));
    }

    // Minute HR from local midnight to min(end of day, now). Integer ms
    // comparisons keep this loop fast (it runs ~130 000 times for 90 days).
    final hrRecord = 'demo:hr:${d.date}';
    final wsum = <int, (double, int)>{};
    final nextNight = next?.night;
    final stepsByHour = <int, double>{};
    int m0(DateTime x) => x.millisecondsSinceEpoch;
    final dayStartMs = m0(d.start);
    final dayEndMs = math.min(m0(d.end), m0(now));
    final nowMs = m0(now);
    final gap = d.gap;
    final gapA = gap == null ? 0 : m0(gap.$1),
        gapB = gap == null ? 0 : m0(gap.$2);
    final napA = nap == null ? 0 : m0(nap.$1),
        napB = nap == null ? 0 : m0(nap.$2);
    final nights = [
      (
        night,
        m0(night.bed),
        m0(night.wake),
        d.rhr,
        [for (final s in night.stages) (m0(s.start), m0(s.end), s.stage)],
      ),
      if (nextNight != null)
        (
          nextNight,
          m0(nextNight.bed),
          m0(nextNight.wake),
          next!.rhr,
          [for (final s in nextNight.stages) (m0(s.start), m0(s.end), s.stage)],
        ),
    ];
    final wk = [for (final w in d.workouts) (m0(w.start), m0(w.end))];
    final bk = [for (final b in bursts) (m0(b.$1), m0(b.$2), b.$3)];
    final wakeMs = m0(night.wake);
    for (
      var tm = dayStartMs, minute = 0;
      tm < dayEndMs;
      tm += 60000, minute++
    ) {
      if (gap != null && tm >= gapA && tm < gapB) continue;
      final hour = minute ~/ 60;
      double bpm;
      var sleepIdx = -1;
      for (var i = 0; i < nights.length; i++) {
        if (tm >= nights[i].$2 && tm < nights[i].$3) sleepIdx = i;
      }
      var wIdx = -1;
      for (var i = 0; i < wk.length; i++) {
        if (tm >= wk[i].$1 && tm < wk[i].$2) wIdx = i;
      }
      if (sleepIdx >= 0) {
        final n = nights[sleepIdx];
        var st = SleepStage.light;
        for (final sp in n.$5) {
          if (tm >= sp.$1 && tm < sp.$2) {
            st = sp.$3;
            break;
          }
        }
        final p = (tm - n.$2) / (n.$3 - n.$2);
        final off = switch (st) {
          SleepStage.deep => -3.5,
          SleepStage.rem => 3.0,
          SleepStage.awake => 8.0,
          _ => -1.0,
        };
        bpm = n.$4 + 1.5 + off - 3.0 * math.sin(math.pi * p) + _r.gauss(0, 1.1);
      } else if (nap != null && tm >= napA && tm < napB) {
        bpm = d.rhr + 4 + _r.gauss(0, 1.5);
      } else if (wIdx >= 0) {
        final w = d.workouts[wIdx];
        final m = (tm - wk[wIdx].$1) ~/ 60000;
        final total = (wk[wIdx].$2 - wk[wIdx].$1) ~/ 60000;
        final ramp = math.min(1.0, math.min((m + 1) / 6.0, (total - m) / 5.0));
        final rest = d.rhr + 22;
        final target = d.rhr + (_maxHr - d.rhr) * w.intensity(m);
        bpm = rest + (target - rest) * ramp + _r.gauss(0, 2.5);
        final b0 = bpm;
        wsum.update(
          wIdx,
          (v) => (v.$1 + b0, v.$2 + 1),
          ifAbsent: () => (b0, 1),
        );
        final cadence = switch (w.type) {
          _WType.intervals || _WType.tempo || _WType.easyRun => 162.0,
          _WType.strength => 6.0,
          _ => 0.0,
        };
        stepsByHour.update(hour, (v) => v + cadence, ifAbsent: () => cadence);
      } else {
        final h = minute / 60.0;
        var base =
            d.rhr + 13 + 5 * math.sin(math.pi * ((h - 8) / 13).clamp(0.0, 1.0));
        if (h > 21.5) base -= 3;
        final sinceWake = (tm - wakeMs) ~/ 60000;
        if (tm >= wakeMs && sinceWake < 45) base -= 2;
        for (final w in wk) {
          if (tm >= w.$2) {
            final after = (tm - w.$2) ~/ 60000;
            if (after < 45) base += 24 * math.exp(-after / 9);
          }
        }
        var walking = false;
        for (final b in bk) {
          if (tm >= b.$1 && tm < b.$2) {
            base += b.$3;
            walking = true;
            stepsByHour.update(
              hour,
              (v) => v + _r.range(75, 100),
              ifAbsent: () => 88,
            );
          }
        }
        if (!walking) {
          for (final f in onFeet) {
            if (tm >= f.$1 && tm < f.$2) {
              base += f.$3;
              walking = true;
              stepsByHour.update(
                hour,
                (v) => v + _r.range(8, 22),
                ifAbsent: () => 15,
              );
              break;
            }
          }
        }
        if (!walking && h >= 7 && h < 22) {
          stepsByHour.update(
            hour,
            (v) => v + _r.range(1.0, 3.5),
            ifAbsent: () => 2,
          );
        }
        bpm = base + 5 * d.ill + _r.gauss(0, 2.4);
      }
      final tsMs = tm + _r.intRange(15, 46) * 1000;
      if (tsMs > nowMs) break;
      rows.hr.add(
        RawHrRow(
          source: SourceKind.demo,
          sourceRecordId: 'demo:hr:$tsMs',
          recordId: hrRecord,
          originPackage: kDemoOrigin,
          device: kDemoDevice,
          ingestedAt: now,
          // UTC instant: raw rows are compared by instant only, and local
          // DateTime construction is ~9 µs each on the Windows VM.
          t: DateTime.fromMillisecondsSinceEpoch(tsMs, isUtc: true),
          bpm: _round(bpm.clamp(38.0, 205.0), 10),
        ),
      );
    }

    // Workouts (finished ones only).
    for (var k = 0; k < d.workouts.length; k++) {
      final w = d.workouts[k];
      if (w.end.isAfter(now)) continue;
      final mins = w.end.difference(w.start).inMinutes;
      final avg = wsum[k] == null ? null : wsum[k]!.$1 / wsum[k]!.$2;
      final perMin = switch (w.type) {
        _WType.intervals || _WType.tempo => 11.5,
        _WType.easyRun => 9.5,
        _WType.strength => 6.0,
        _ => 9.0,
      };
      final dist = switch (w.type) {
        _WType.intervals || _WType.tempo || _WType.easyRun => mins / 5.6 * 1000,
        _WType.ride || _WType.longRide => mins / 60 * 26 * 1000,
        _ => null,
      };
      final id = 'demo:workout:${d.date}:$k';
      rows.workouts.add(
        RawWorkoutRow(
          source: SourceKind.demo,
          sourceRecordId: id,
          recordId: id,
          originPackage: kDemoOrigin,
          device: kDemoDevice,
          ingestedAt: now,
          start: w.start,
          end: w.end,
          name: w.name,
          activityType: w.activityType,
          avgHr: avg == null ? null : _round(avg, 10),
          calories: (mins * perMin).roundToDouble(),
          distanceM: dist?.roundToDouble(),
        ),
      );
      if (w.activityType == 'RUNNING' && _r.chance(0.35)) {
        rows.scalars.add(
          _scalar(
            ScalarKind.vo2max,
            'demo:vo2:${d.date}',
            w.end,
            _vo2Base + 0.015 * d.index + _r.gauss(0, 0.35),
          ),
        );
      }
    }

    // Hourly steps (charging gap already excluded above).
    for (final e
        in (stepsByHour.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))) {
      final hs = d.start.add(Duration(hours: e.key));
      if (!hs.isBefore(now)) continue;
      var he = hs.add(const Duration(hours: 1));
      if (he.isAfter(now)) he = now;
      rows.scalars.add(
        _scalar(
          ScalarKind.steps,
          'demo:steps:${d.date}:${e.key}',
          hs,
          e.value.roundToDouble(),
          end: he,
        ),
      );
    }
  }
}
