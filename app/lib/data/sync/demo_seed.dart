// First-launch demo seed, computed off the UI isolate.
//
// [buildDemoSeed] is a pure function of plain values (seed, days, now,
// profile): generate the synthetic band → 1-minute HR buckets → resolver →
// Engine.computeRange, the same pipeline InMemoryHealthRepository.demo runs
// through its memory store, with identical scores
// (test/data/demo_seed_test.dart). For
// the sqlite app it also builds the whole write payload (multi-row INSERTs,
// hr_day blobs, JSON), so the UI isolate only does one transaction of I/O
// instead of ~30 000 per-row inserts plus read-backs.

import 'dart:isolate';

import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../db/hr_buckets.dart';
import '../db/raw_rows.dart';
import '../db/schema.dart';
import '../db/sql_rows.dart';
import '../db/stores.dart';
import '../resolver/resolver.dart';
import '../services/demo/demo_generator.dart';
import 'score_pipeline.dart';

/// Plain, sendable inputs of one seed.
class DemoSeedRequest {
  const DemoSeedRequest({
    required this.seed,
    required this.days,
    required this.now,
    this.profile = const UserProfile(),
    this.forSqlite = false,
  });
  final int seed;
  final int days;
  final DateTime now;
  final UserProfile profile;

  /// Build the sqlite payload ([DemoSeedResult.ops]) instead of handing the
  /// raw rows back.
  final bool forSqlite;
}

class DemoSeedResult {
  DemoSeedResult({
    required this.outcome,
    this.dataset,
    this.ops = const [],
    this.timingsMs = const {},
  });

  /// Resolved records + scores (days of the seed window).
  final ComputeOutcome outcome;

  /// The generated rows + journal (in-memory path only; null for sqlite).
  final DemoDataset? dataset;

  /// Statements for one sqlite transaction (sqlite path only).
  final List<SqlOp> ops;

  /// Per-phase wall time inside the worker, for the timing marks.
  final Map<String, int> timingsMs;
}

/// Runs [buildDemoSeed] somewhere: inline (tests, in-memory stores; an
/// isolate would never complete under testWidgets' fake async) or in a
/// worker isolate (the app).
typedef DemoSeedRunner = Future<DemoSeedResult> Function(
  DemoSeedRequest request,
);

/// Executes a seed payload in one transaction.
typedef DemoSeedWriter = Future<void> Function(List<SqlOp> ops);

Future<DemoSeedResult> runDemoSeedInline(DemoSeedRequest request) async =>
    buildDemoSeed(request);

/// Top-level so the closure captures only [request] (never a store, clock
/// or database handle). Isolate.run returns the result by transfer.
Future<DemoSeedResult> runDemoSeedInIsolate(DemoSeedRequest request) =>
    Isolate.run(() => buildDemoSeed(request), debugName: 'airlog-demo-seed');

DemoSeedResult buildDemoSeed(DemoSeedRequest q) {
  final timings = <String, int>{};
  final sw = Stopwatch()..start();
  void lap(String name) {
    timings[name] = sw.elapsedMilliseconds;
    sw.reset();
  }

  final ds = DemoGenerator(seed: q.seed, days: q.days, now: q.now).generate();
  lap('generate');
  final today = DayKey.of(q.now);
  final first = DayKey.add(today, -(q.days - 1));
  final rows = resolverInput(ds.rows);
  lap('bucket');
  final out = computeDays(
    rows,
    computeFrom: first,
    keepFrom: first,
    to: today,
    cfg: ResolverConfig(mode: DataMode.demo, now: q.now),
    profile: q.profile,
    // Only the engine (instant-based) and the blob encoder see these
    // samples on the sqlite path; UTC skips a time-zone lookup per sample.
    utcHr: q.forSqlite,
  );
  lap('resolve+engine');
  if (!q.forSqlite) {
    return DemoSeedResult(outcome: out, dataset: ds, timingsMs: timings);
  }
  final ops = demoSeedSql(ds, rows.hrDays, out, q.now);
  lap('encode');
  return DemoSeedResult(outcome: out, ops: ops, timingsMs: timings);
}

/// What a store's load() returns for freshly generated demo rows: 1-minute
/// HR buckets instead of raw samples, every other kind sorted by time.
/// (Same as MemoryRawStore upsert + load — demo record ids are unique, see
/// test/data/demo_seed_test.dart — without indexing 120 000 HR rows.)
RawRows resolverInput(RawRows generated) {
  int byT<T extends RawRow>(T a, T b) => a.start.compareTo(b.start);
  return RawRows(
    hrDays: bucketHr(generated.hr).values.toList()
      ..sort((a, b) => a.date.compareTo(b.date)),
    hrv: [...generated.hrv]..sort(byT),
    sleep: [...generated.sleep]..sort(byT),
    workouts: [...generated.workouts]..sort(byT),
    scalars: [...generated.scalars]..sort(byT),
  );
}

/// The sqlite statements that replace every demo row: wipe demo raw rows,
/// journal and day rows, then insert raw rows (raw HR only inside the
/// retention window, as SqliteRawStore.upsert keeps it), the 1-minute HR
/// buckets, journal, resolved records and results.
List<SqlOp> demoSeedSql(
  DemoDataset ds,
  List<HrDay> hrDays,
  ComputeOutcome out,
  DateTime now,
) {
  const src = SourceKind.demo, mode = DataMode.demo;
  final nowMs = now.millisecondsSinceEpoch;
  final retention = DayKey.start(DayKey.of(now.subtract(kRawHrRetention)))
      .millisecondsSinceEpoch;
  final r = ds.rows;
  return [
    for (final t in kRawTables)
      SqlOp('DELETE FROM $t WHERE source = ?', [src.code]),
    for (final t in const ['journal', 'day_record', 'day_result'])
      SqlOp('DELETE FROM $t WHERE mode = ?', [mode.name]),
    ...SqlRows.insertAll('raw_hr', [
      for (final h in r.hr)
        if (h.t.millisecondsSinceEpoch >= retention) SqlRows.raw(h),
    ]),
    ...SqlRows.insertAll('hr_day', [
      for (final d in hrDays) SqlRows.hrDay(d, nowMs),
    ], maxRows: 30),
    ...SqlRows.insertAll('raw_hrv', [for (final x in r.hrv) SqlRows.raw(x)]),
    ...SqlRows.insertAll('raw_sleep', [
      for (final x in r.sleep) SqlRows.raw(x),
    ]),
    ...SqlRows.insertAll('raw_sleep_stage', [
      for (final x in r.sleep) ...SqlRows.stages(x),
    ]),
    ...SqlRows.insertAll('raw_workout', [
      for (final x in r.workouts) SqlRows.raw(x),
    ]),
    ...SqlRows.insertAll('raw_scalar', [
      for (final x in r.scalars) SqlRows.raw(x),
    ]),
    ...SqlRows.insertAll('journal', [
      for (final j in ds.journal) SqlRows.journal(mode, j, nowMs),
    ]),
    ...SqlRows.insertAll('day_record', [
      for (final d in out.records) SqlRows.dayRecord(mode, d, nowMs),
    ], maxRows: 30),
    ...SqlRows.insertAll('day_result', [
      for (final d in out.results) SqlRows.dayResult(mode, d),
    ], maxRows: 30),
  ];
}
