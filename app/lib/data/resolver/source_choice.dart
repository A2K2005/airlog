// One origin app per metric (decision "Any app", 2026-09-29).
//
// Health Connect carries data from every app on the phone (Google Health /
// Fitbit, Samsung Health, WHOOP, Oura, Garmin, …). For each metric Airlog
// uses ONE app at a time, never a sum or an average of two, and the choice
// is persisted as dated segments so baselines never flip-flop:
//   * automatic: the app with the best 14-day coverage (days with data);
//   * it moves to another app ONLY after [kSustainedAbsenceDays] complete
//     days in a row without a single datum from the chosen app while
//     another app has data; the new segment starts on the first absent day,
//     so nothing from those days is lost (they are re-resolved);
//   * a user pin (setSourceChoice) applies to all history and never moves;
//   * when another app has fresher data, [OriginPlan.suggested] is set so
//     the UI can ask once instead of waiting out the absence silently;
//   * HRV and resting HR plans also persist [OriginPlan.notShared]: the
//     apps that track sleep but never write that metric (observed from the
//     raw rows, never a package list), so after a switch to such an app the
//     engine treats it as "doesn't share" from its first night
//     (EngineConfig.notShared).
//
// Pure Dart (no I/O): the repository persists [OriginPlan.toJson].

import '../../domain/day_key.dart';
import '../../domain/engine/day_engine.dart' show DayEngine;
import '../../domain/models.dart';
import '../common/time.dart';
import '../db/raw_rows.dart';

/// Complete days in a row without data from the chosen app before the
/// automatic choice moves. Normal gaps (charging, a forgotten night, a long
/// weekend without the tracker) last 1–3 days; 4 full days of silence while
/// another app keeps writing means the user changed device. The switch is
/// backdated to the first silent day, so waiting costs nothing.
const int kSustainedAbsenceDays = 4;

/// Coverage window for the automatic pick.
const int kCoverageWindowDays = 14;

/// Metric → origin package → days ("yyyy-MM-dd") with data from it.
typedef OriginDays = Map<String, Set<String>>;

class OriginSegment {
  const OriginSegment(this.origin, this.from);
  final String origin;

  /// First day ("yyyy-MM-dd") this origin is used.
  final String from;

  Map<String, dynamic> toJson() => {'origin': origin, 'from': from};
  factory OriginSegment.fromJson(Map<String, dynamic> j) =>
      OriginSegment(j['origin'] as String, j['from'] as String);
}

class OriginPlan {
  const OriginPlan({
    required this.metric,
    required this.segments,
    this.automatic = true,
    this.evaluatedThrough,
    this.suggested,
    this.shape,
    this.notShared = const [],
  });
  final Metric metric;

  /// HRV only: how the chosen app writes nightly HRV, 'samples' (a series
  /// inside sleep → N2 mean) or 'single' (1–2 nightly records → N3).
  /// Persisted with hysteresis ([SourceChooser.updateShape]).
  final String? shape;

  /// Ascending by [OriginSegment.from]; never empty.
  final List<OriginSegment> segments;

  /// false = pinned by the user.
  final bool automatic;

  /// Last complete day the absence rule has looked at.
  final String? evaluatedThrough;

  /// Another app with fresher data (the UI may offer to switch).
  final String? suggested;

  /// HRV and resting HR only: origin packages that have tracked sleep on
  /// at least [DayEngine.notSharedNights] days and never written this
  /// metric, sorted ([SourceChooser.notSharedBy]). [additive; a plan saved
  /// before it reads as empty]
  final List<String> notShared;

  String get current => segments.last.origin;
  String get since => segments.last.from;

  /// The origin used on [day] (days before the first segment use it too).
  String originOn(String day) {
    for (var i = segments.length - 1; i >= 0; i--) {
      if (segments[i].from.compareTo(day) <= 0) return segments[i].origin;
    }
    return segments.first.origin;
  }

  /// The first day on which this plan and [other] pick different origins,
  /// among [days]; null when they agree on all of them.
  String? firstDifference(OriginPlan? other, Iterable<String> days) {
    String? first;
    for (final d in days) {
      if (other == null || originOn(d) != other.originOn(d)) {
        if (first == null || d.compareTo(first) < 0) first = d;
      }
    }
    return first;
  }

  OriginPlan copyWith({
    List<OriginSegment>? segments,
    bool? automatic,
    String? evaluatedThrough,
    String? suggested,
    bool clearSuggested = false,
    String? shape,
    List<String>? notShared,
  }) => OriginPlan(
    metric: metric,
    segments: segments ?? this.segments,
    automatic: automatic ?? this.automatic,
    evaluatedThrough: evaluatedThrough ?? this.evaluatedThrough,
    suggested: clearSuggested ? null : (suggested ?? this.suggested),
    shape: shape ?? this.shape,
    notShared: notShared ?? this.notShared,
  );

  Map<String, dynamic> toJson() => {
    'metric': metric.code,
    'segments': [for (final s in segments) s.toJson()],
    'automatic': automatic,
    if (evaluatedThrough != null) 'evaluatedThrough': evaluatedThrough,
    if (suggested != null) 'suggested': suggested,
    if (shape != null) 'shape': shape,
    if (notShared.isNotEmpty) 'notShared': notShared,
  };

  factory OriginPlan.fromJson(Map<String, dynamic> j) => OriginPlan(
    metric: Metric.fromCode(j['metric'] as String),
    segments: [
      for (final s in j['segments'] as List)
        OriginSegment.fromJson(s as Map<String, dynamic>),
    ],
    automatic: j['automatic'] as bool? ?? true,
    evaluatedThrough: j['evaluatedThrough'] as String?,
    suggested: j['suggested'] as String?,
    shape: j['shape'] as String?,
    notShared: [for (final o in (j['notShared'] as List?) ?? const []) '$o'],
  );
}

abstract final class SourceChooser {
  /// Days with data from [days] in [from, to] (inclusive).
  static int coverage(Set<String> days, String from, String to) =>
      days.where((d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0).length;

  /// The best origin by coverage of the [kCoverageWindowDays] days ending
  /// [asOf]; ties → the most recent datum, then the package name (so the
  /// pick is deterministic). [among] restricts the candidates.
  static String? best(OriginDays d, String asOf, {Iterable<String>? among}) {
    final from = DayKey.add(asOf, -(kCoverageWindowDays - 1));
    String? pick;
    var pickCov = -1;
    String? pickLast;
    for (final o in (among ?? d.keys).toList()..sort()) {
      final days = d[o];
      if (days == null || days.isEmpty) continue;
      final cov = coverage(days, from, asOf);
      final last = _last(days, asOf);
      final better =
          cov > pickCov ||
          (cov == pickCov &&
              last != null &&
              (pickLast == null || last.compareTo(pickLast) > 0));
      if (better) {
        pick = o;
        pickCov = cov;
        pickLast = last;
      }
    }
    return pick;
  }

  static String? _last(Set<String> days, String asOf) {
    String? l;
    for (final d in days) {
      if (d.compareTo(asOf) > 0) continue;
      if (l == null || d.compareTo(l) > 0) l = d;
    }
    return l;
  }

  static String? _earliest(OriginDays d) {
    String? e;
    for (final days in d.values) {
      for (final x in days) {
        if (e == null || x.compareTo(e) < 0) e = x;
      }
    }
    return e;
  }

  /// Brings [prev] up to date for [today] (complete days end yesterday).
  /// Null when no app has ever written [metric].
  static OriginPlan? update(
    Metric metric,
    OriginDays days,
    OriginPlan? prev, {
    required String today,
  }) {
    final yesterday = DayKey.add(today, -1);
    var plan = prev;
    if (plan == null || plan.segments.isEmpty) {
      final start = _earliest(days);
      if (start == null) return null;
      // Best coverage over the first window of data.
      final first = best(days, DayKey.add(start, kCoverageWindowDays - 1))!;
      plan = OriginPlan(
        metric: metric,
        segments: [OriginSegment(first, start)],
        evaluatedThrough: DayKey.add(start, -1),
      );
    }
    if (plan.automatic) {
      final segs = [...plan.segments];
      var d = DayKey.add(
        plan.evaluatedThrough ?? DayKey.add(segs.last.from, -1),
        1,
      );
      while (d.compareTo(yesterday) <= 0) {
        final cur = segs.last;
        final runStart = DayKey.add(d, -(kSustainedAbsenceDays - 1));
        if (runStart.compareTo(cur.from) >= 0 &&
            coverage(days[cur.origin] ?? const {}, runStart, d) == 0) {
          final others = [
            for (final e in days.entries)
              if (e.key != cur.origin && coverage(e.value, runStart, d) > 0)
                e.key,
          ];
          if (others.isNotEmpty) {
            segs.add(OriginSegment(best(days, d, among: others)!, runStart));
          }
        }
        d = DayKey.add(d, 1);
      }
      plan = plan.copyWith(segments: segs, evaluatedThrough: yesterday);
    } else {
      plan = plan.copyWith(evaluatedThrough: yesterday);
    }
    final suggested = _suggest(days, plan, today);
    return plan.copyWith(
      suggested: suggested,
      clearSuggested: suggested == null,
    );
  }

  /// Another app whose newest datum is newer than the chosen app's, when
  /// the chosen app missed the last complete day.
  static String? _suggest(OriginDays days, OriginPlan plan, String today) {
    final yesterday = DayKey.add(today, -1);
    final cur = days[plan.current] ?? const <String>{};
    if (cur.contains(yesterday) || cur.contains(today)) return null;
    final curLast = _last(cur, today);
    String? pick;
    String? pickLast;
    for (final e in days.entries) {
      if (e.key == plan.current) continue;
      final l = _last(e.value, today);
      if (l == null || l.compareTo(yesterday) < 0) continue;
      if (curLast != null && l.compareTo(curLast) <= 0) continue;
      if (pickLast == null || l.compareTo(pickLast) > 0) {
        pick = e.key;
        pickLast = l;
      }
    }
    return pick;
  }

  /// HRV shape of the chosen app from its last [kCoverageWindowDays]
  /// nights ([counts]: wake day → in-sleep records), with hysteresis: a
  /// first decision by majority, then 'samples' → 'single' only when ≤ 25 %
  /// of nights have ≥ 3 records, and back only when ≥ 75 % do, so one odd
  /// night never flips the definition (which would split the baseline).
  static OriginPlan updateShape(
    OriginPlan plan,
    Map<String, int> counts, {
    required String today,
  }) {
    final to = DayKey.add(today, -1);
    final from = DayKey.add(to, -(kCoverageWindowDays - 1));
    var nights = 0, series = 0;
    for (final e in counts.entries) {
      if (e.key.compareTo(from) < 0 || e.key.compareTo(to) > 0) continue;
      if (e.value <= 0) continue;
      nights++;
      if (e.value >= 3) series++;
    }
    if (nights == 0) return plan;
    final share = series / nights;
    final cur = plan.shape;
    final String next;
    if (cur == null) {
      next = share >= 0.5 ? 'samples' : 'single';
    } else if (cur == 'samples') {
      next = share <= 0.25 ? 'single' : 'samples';
    } else {
      next = share >= 0.75 ? 'samples' : 'single';
    }
    return next == cur ? plan : plan.copyWith(shape: next);
  }

  /// Metrics whose plans carry [OriginPlan.notShared].
  static const notSharedMetrics = {Metric.hrv, Metric.restingHr};

  /// Origins that tracked sleep on at least [DayEngine.notSharedNights]
  /// days in [all] and never wrote [metric] at all: the apps that don't
  /// share it with Health Connect (Samsung Health: HRV and resting HR;
  /// WHOOP: HRV). Sorted, so the persisted plan only changes when the set
  /// does. Observed from the raw rows, never a package list.
  static List<String> notSharedBy(Metric metric, Map<Metric, OriginDays> all) {
    final writes = all[metric] ?? const <String, Set<String>>{};
    return [
      for (final e
          in (all[Metric.sleep] ?? const <String, Set<String>>{}).entries)
        if (e.key.isNotEmpty &&
            e.value.length >= DayEngine.notSharedNights &&
            (writes[e.key]?.isEmpty ?? true))
          e.key,
    ]..sort();
  }

  /// A user pin: [origin] from the first day it has data (or [today]),
  /// never moved automatically. Earlier days keep the app they had (the
  /// pinned app has nothing there), so past screens don't lose data; the
  /// pinned app starts its own baseline segment.
  static OriginPlan pin(
    Metric metric,
    String origin,
    OriginDays days, {
    OriginPlan? prev,
    required String today,
  }) {
    final own = days[origin];
    String first = today;
    if (own != null) {
      for (final d in own) {
        if (d.compareTo(first) < 0) first = d;
      }
    }
    final kept = [
      for (final s in prev?.segments ?? const <OriginSegment>[])
        if (s.from.compareTo(first) < 0) s,
    ];
    final segments = kept.isNotEmpty && kept.last.origin == origin
        ? kept
        : [
            ...kept,
            OriginSegment(
              origin,
              kept.isEmpty ? (_earliest(days) ?? first) : first,
            ),
          ];
    return OriginPlan(
      metric: metric,
      segments: segments,
      automatic: false,
      evaluatedThrough: DayKey.add(today, -1),
    );
  }
}

/// Which HC-origin metrics each raw row counts for, on which day (the same
/// day assignment as the resolver: nights → wake day, daily values → their
/// civil day). Only Health Connect and context rows (the sources that have
/// origin apps).
Map<Metric, OriginDays> originDaysOf(RawRows rows) {
  final out = <Metric, OriginDays>{};
  void add(Metric m, String? origin, String day) =>
      out.putIfAbsent(m, () => {}).putIfAbsent(origin ?? '', () => {}).add(day);
  bool hc(RawRow r) =>
      r.source == SourceKind.healthConnect || r.source == SourceKind.context;

  for (final d in rows.hrDays) {
    if ((d.source == SourceKind.healthConnect ||
            d.source == SourceKind.context) &&
        d.minutesWithData > 0) {
      add(Metric.hr, d.origin, d.date);
    }
  }
  for (final r in rows.hrv) {
    if (hc(r)) add(Metric.hrv, r.originPackage, nightKey(r.t));
  }
  for (final r in rows.sleep) {
    if (hc(r)) add(Metric.sleep, r.originPackage, dayKeyOf(r.end));
  }
  for (final r in rows.workouts) {
    if (hc(r)) add(Metric.workouts, r.originPackage, dayKeyOf(r.start));
  }
  for (final r in rows.scalars) {
    if (!hc(r)) continue;
    final (Metric? m, bool nightly) = switch (r.scalar) {
      ScalarKind.rhr => (Metric.restingHr, false),
      ScalarKind.resp => (Metric.respiratoryRate, true),
      ScalarKind.skinTempDelta => (Metric.skinTemp, true),
      ScalarKind.spo2Avg => (Metric.spo2, true),
      ScalarKind.vo2max => (Metric.vo2max, false),
      ScalarKind.steps => (Metric.steps, false),
      ScalarKind.weight => (Metric.weight, false),
      _ => (null, false),
    };
    if (m == null) continue;
    add(
      m,
      r.originPackage,
      r.day ?? (nightly ? nightKey(r.start) : dayKeyOf(r.start)),
    );
  }
  return out;
}

/// Nightly HRV records of [origin] inside that app's sleep sessions, per
/// wake day (spot readings excluded): the input of [SourceChooser.updateShape].
Map<String, int> hrvNightCounts(RawRows rows, String origin) {
  final sessions = [
    for (final s in rows.sleep)
      if (s.originPackage == origin) s,
  ];
  final out = <String, int>{};
  for (final r in rows.hrv) {
    if (r.originPackage != origin || r.isSpot) continue;
    for (final s in sessions) {
      if (!r.t.isBefore(s.start) && !r.t.isAfter(s.end)) {
        out.update(dayKeyOf(s.end), (v) => v + 1, ifAbsent: () => 1);
        break;
      }
    }
  }
  return out;
}

/// Plans for every metric in [rows] (no persisted state): what the resolver
/// uses when the caller has none, so it never mixes apps.
Map<Metric, OriginPlan> plansFor(RawRows rows, {required String today}) => {
  for (final e in originDaysOf(rows).entries)
    e.key: ?SourceChooser.update(e.key, e.value, null, today: today),
};
