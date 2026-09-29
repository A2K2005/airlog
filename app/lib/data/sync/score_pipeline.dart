// Raw rows → resolver → Engine.computeRange → day_record + day_result.
//
// Recompute runs from the earliest dirty day onward (sleep debt carries
// forward). Days before it are clean, so their STORED resolved records are
// handed to the engine as history (the engine uses all of it: baselines,
// calibration night count, Pulse Age); only the dirty range is re-resolved
// from raw rows, and only days >= the dirty day are written back. This makes
// an incremental recompute identical to a full one
// (test/data/recompute_window_test.dart).

import 'dart:convert';

import '../../domain/day_key.dart';
import '../../domain/engine/engine.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import '../db/raw_rows.dart';
import '../db/stores.dart';
import '../resolver/resolver.dart';
import '../resolver/source_choice.dart';

/// Birth year of the synthetic demo person (age 30 in 2026: Tanaka max HR
/// 187 bpm, matching the generator's heart-rate model).
const int kDemoBirthYear = 1996;

/// Settings key of the persisted origin plan of [m] (source_choice.dart).
String originPlanKey(Metric m) => 'origin_plan.${m.code}';

/// Settings key of a cached platform app label for [package].
String appLabelKey(String package) => 'app_label.$package';

class ComputeOutcome {
  ComputeOutcome(this.records, this.results, this.engineError);
  final List<DayRecord> records;
  final List<DayResult> results;

  /// Non-null when the engine threw (e.g. still UnimplementedError): records
  /// are stored anyway, scores are not.
  final Object? engineError;
}

/// Pure resolve + score. [rows] are resolved for [computeFrom]..[to];
/// [history] (already-resolved earlier days) is prepended for the engine.
/// Returns days >= [keepFrom].
ComputeOutcome computeDays(
  RawRows rows, {
  required String computeFrom,
  required String keepFrom,
  required String to,
  required ResolverConfig cfg,
  required UserProfile profile,
  List<DayRecord> history = const [],
  bool utcHr = false,
  Map<String, String> appNames = const {},
  Map<String, Set<String>> notShared = const {},
}) {
  // The sample person has a known age: demo scores use it unless the user
  // set their own (no observed-max fallback for synthetic data).
  if (cfg.mode == DataMode.demo && !profile.hasAge) {
    profile = profile.copyWith(birthYear: kDemoBirthYear);
  }
  final records = [
    for (final h in history)
      if (h.date.compareTo(computeFrom) < 0) h,
    ...const Resolver().resolve(rows, computeFrom, to, cfg, utcHr: utcHr),
  ];
  List<DayResult> results = const [];
  Object? err;
  try {
    results = Engine.computeRange(
      records,
      config: EngineConfig(
        profile: profile,
        appNames: appNames,
        notShared: notShared,
      ),
      now: cfg.now,
    );
  } catch (e) {
    err = e;
  }
  return ComputeOutcome(
    [
      for (final r in records)
        if (r.date.compareTo(keepFrom) >= 0) r,
    ],
    [
      for (final r in results)
        if (r.date.compareTo(keepFrom) >= 0) r,
    ],
    err,
  );
}

class ScorePipeline {
  ScorePipeline({required this.raw, required this.app, this.utcHr = false});

  final RawStore raw;
  final AppStore app;

  /// Resolve intraday HR as UTC instants (see Resolver.resolve). Only for
  /// an [app] store that persists them as a blob and re-reads them as
  /// local (sqlite); an in-memory store hands records to the UI as-is.
  final bool utcHr;

  /// The persisted origin plan per metric (live mode).
  Future<Map<Metric, OriginPlan>> loadPlans() async {
    final out = <Metric, OriginPlan>{};
    for (final m in Metric.values) {
      final j = await app.getSetting(originPlanKey(m));
      if (j == null) continue;
      try {
        out[m] = OriginPlan.fromJson(jsonDecode(j) as Map<String, dynamic>);
      } catch (_) {}
    }
    return out;
  }

  Future<void> savePlan(OriginPlan? plan, Metric m) => app.setSetting(
    originPlanKey(m),
    plan == null ? null : jsonEncode(plan.toJson()),
  );

  /// Brings every metric's origin plan up to date (sustained-absence rule;
  /// HRV and resting HR also their [OriginPlan.notShared]), persists it,
  /// and returns the plans plus the first day whose origin or not-shared
  /// apps changed (recompute from there; null = none).
  Future<({Map<Metric, OriginPlan> plans, String? changedFrom})> updatePlans(
    DateTime now,
  ) async {
    final prev = await loadPlans();
    final span = await raw.span(sources: _hcSources);
    if (span == null) return (plans: prev, changedFrom: null);
    final rows = await raw.load(span.$1, now, sources: _hcSources);
    final days = originDaysOf(rows);
    final today = DayKey.of(now);
    final plans = <Metric, OriginPlan>{};
    String? changed;
    for (final m in Metric.values) {
      final d = days[m];
      final old = prev[m];
      var next = d == null
          ? old
          : SourceChooser.update(m, d, old, today: today);
      if (next == null) continue;
      if (m == Metric.hrv) {
        next = SourceChooser.updateShape(
          next,
          hrvNightCounts(rows, next.current),
          today: today,
        );
      }
      if (SourceChooser.notSharedMetrics.contains(m)) {
        next = next.copyWith(notShared: SourceChooser.notSharedBy(m, days));
      }
      plans[m] = next;
      if (old == null ||
          jsonEncode(old.toJson()) != jsonEncode(next.toJson())) {
        await savePlan(next, m);
      }
      final all = {for (final x in (d ?? const {}).values) ...x};
      final diff = _earliest([
        next.firstDifference(old, all),
        // An app newly (or no longer) known not to share this metric:
        // rescore from its first night (the stand-in / "without" label).
        for (final o in _symmetricDifference(old?.notShared, next.notShared))
          _earliest(days[Metric.sleep]?[o] ?? const {}),
      ]);
      if (old != null && diff != null) {
        if (changed == null || diff.compareTo(changed) < 0) changed = diff;
      }
    }
    return (plans: plans, changedFrom: changed);
  }

  static Iterable<String> _symmetricDifference(
    List<String>? a,
    List<String> b,
  ) {
    final x = {...?a}, y = {...b};
    return {...x.difference(y), ...y.difference(x)};
  }

  static String? _earliest(Iterable<String?> days) {
    String? e;
    for (final d in days) {
      if (d != null && (e == null || d.compareTo(e) < 0)) e = d;
    }
    return e;
  }

  /// Metric code → origins persisted as never sharing it
  /// (EngineConfig.notShared).
  static Map<String, Set<String>> notSharedOf(
    Map<Metric, OriginPlan> plans,
  ) => {
    for (final e in plans.entries)
      if (e.value.notShared.isNotEmpty) e.key.code: e.value.notShared.toSet(),
  };

  static const _hcSources = {SourceKind.healthConnect, SourceKind.context};

  /// Cached platform labels for origin packages (EngineConfig.appNames).
  Future<Map<String, String>> appNames(Iterable<String> packages) async {
    final out = <String, String>{};
    for (final p in packages) {
      final l = await app.getSetting(appLabelKey(p));
      if (l != null && l.isNotEmpty) out[p] = l;
    }
    return out;
  }

  /// Recomputes [mode] from [fromDate] (null = everything) to today. In
  /// live mode the origin plans are brought up to date first, and a changed
  /// origin moves [fromDate] back to the first affected day.
  Future<ComputeOutcome> recompute(
    DataMode mode, {
    String? fromDate,
    required ResolverConfig cfg,
    required UserProfile profile,
  }) async {
    var appNames = const <String, String>{};
    var notShared = const <String, Set<String>>{};
    if (mode == DataMode.live) {
      final up = await updatePlans(cfg.now);
      if (fromDate != null &&
          up.changedFrom != null &&
          up.changedFrom!.compareTo(fromDate) < 0) {
        fromDate = up.changedFrom;
      }
      cfg = cfg.withOrigins(up.plans);
      notShared = notSharedOf(up.plans);
      appNames = await this.appNames({
        for (final p in up.plans.values)
          for (final s in p.segments) s.origin,
      });
    }
    final sources = Resolver.sourcesFor(cfg);
    final today = DayKey.of(cfg.now);
    final span = await raw.span(sources: sources);
    if (span == null) {
      if (fromDate == null) {
        await app.clearDays(mode);
      } else {
        await app.putDays(mode, const [], const [], clearFrom: fromDate);
      }
      return ComputeOutcome(const [], const [], null);
    }
    final earliest = DayKey.of(span.$1);
    var keepFrom = fromDate ?? earliest;
    if (keepFrom.compareTo(earliest) < 0) keepFrom = earliest;
    if (keepFrom.compareTo(today) > 0) keepFrom = today;
    // Clean earlier days come from the store (already resolved).
    final history = keepFrom == earliest
        ? const <DayRecord>[]
        : await app.records(mode, earliest, DayKey.add(keepFrom, -1));
    final rows = await raw.load(
      DayKey.start(keepFrom).subtract(const Duration(days: 1)),
      DayKey.end(today),
      sources: sources,
    );
    final out = computeDays(
      rows,
      computeFrom: keepFrom,
      keepFrom: keepFrom,
      to: today,
      cfg: cfg,
      profile: profile,
      history: history,
      utcHr: utcHr,
      appNames: appNames,
      notShared: notShared,
    );
    await app.putDays(
      mode,
      out.records,
      out.results,
      clearFrom: fromDate == null ? '0000-00-00' : keepFrom,
    );
    return out;
  }
}
