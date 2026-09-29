// Desktop benchmark of the first-launch demo seed on the real sqlite stores
// (sqflite_common_ffi: no Android platform channel, so it UNDER-states the
// cost of many small writes). Prints per-phase timings of
//   before: per-row store writes + read-back + resolve/engine on the caller,
//   after:  worker isolate (generate/resolve/engine/encode) + one bulk
//           transaction,
// and the size of what each would marshal over the sqflite channel.

import 'dart:io';

import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/db/sql_rows.dart';
import 'package:airlog/data/db/sqlite_stores.dart';
import 'package:airlog/data/db/stores.dart';
import 'package:airlog/data/resolver/resolver.dart';
import 'package:airlog/data/services/demo/demo_generator.dart';
import 'package:airlog/data/sync/demo_seed.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final now = DateTime(2026, 9, 28, 9, 30);

/// Bytes + encode time of a sqflite `batch` call carrying [ops].
(int, int) channelCost(List<SqlOp> ops) {
  final sw = Stopwatch()..start();
  final bytes = const StandardMethodCodec()
      .encodeMethodCall(
        MethodCall('batch', {
          'operations': [
            for (final o in ops)
              {'method': 'insert', 'sql': o.sql, 'arguments': o.args},
          ],
          'noResult': true,
        }),
      )
      .lengthInBytes;
  return (bytes, sw.elapsedMilliseconds);
}

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  setUp(
    () async => tmp = await Directory.systemTemp.createTemp('airlog_bench'),
  );
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('seed phases: before vs after', () async {
    // ── before ──
    final db = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(tmp.path, 'before.db'),
    );
    final raw = SqliteRawStore(db, clock: () => now);
    final app = SqliteAppStore(db, clock: () => now);
    final sw = Stopwatch()..start();
    int lap() {
      final e = sw.elapsedMilliseconds;
      sw.reset();
      return e;
    }

    final ds = DemoGenerator(seed: 42, now: now).generate();
    final tGen = lap();
    await raw.wipe(sources: const {SourceKind.demo});
    await raw.upsert(ds.rows);
    final tWrite = lap();
    await app.clearJournal(DataMode.demo);
    for (final j in ds.journal) {
      await app.putJournal(DataMode.demo, j);
    }
    final tJournal = lap();
    final today = DayKey.of(now);
    final first = DayKey.add(today, -89);
    final cfg = ResolverConfig(mode: DataMode.demo, now: now);
    final rows = await raw.load(
      DayKey.start(first).subtract(const Duration(days: 1)),
      DayKey.end(today),
      sources: const {SourceKind.demo},
    );
    final tLoad = lap();
    final records = const Resolver().resolve(rows, first, today, cfg);
    final tResolve = lap();
    final results = Engine.computeRange(records, now: now);
    final tEngine = lap();
    await app.putDays(DataMode.demo, records, results, clearFrom: '0000-00-00');
    final tPut = lap();
    await db.close();
    final before = tGen + tWrite + tJournal + tLoad + tResolve + tEngine + tPut;

    // Per-row ops the old path sent (raw tables only), for the channel cost.
    final retention = DayKey.start(DayKey.of(now.subtract(kRawHrRetention)))
        .millisecondsSinceEpoch;
    final perRow = <SqlOp>[
      for (final r in ds.rows.all)
        if (r is! RawHrRow || r.t.millisecondsSinceEpoch >= retention)
          ...SqlRows.insertAll(SqlRows.rawTables[r.kind]!, [SqlRows.raw(r)]),
      for (final s in ds.rows.sleep)
        for (final st in SqlRows.stages(s))
          ...SqlRows.insertAll('raw_sleep_stage', [st]),
    ];
    final (perRowBytes, perRowEnc) = channelCost(perRow);

    // ── after ──
    final db2 = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(tmp.path, 'after.db'),
    );
    final total = Stopwatch()..start();
    final res = await runDemoSeedInIsolate(
      DemoSeedRequest(seed: 42, days: 90, now: now, forSqlite: true),
    );
    final tWorker = total.elapsedMilliseconds;
    final w = Stopwatch()..start();
    await runSqlOps(db2, res.ops);
    final tBulk = w.elapsedMilliseconds;
    final after = total.elapsedMilliseconds;
    await db2.close();
    final (bulkBytes, bulkEnc) = channelCost(res.ops);

    // ignore: avoid_print
    print(
      'rows: hr ${ds.rows.hr.length} hrv ${ds.rows.hrv.length} sleep ${ds.rows.sleep.length} '
      'stages ${ds.rows.sleep.fold(0, (a, s) => a + s.stages.length)} '
      'workouts ${ds.rows.workouts.length} scalars ${ds.rows.scalars.length} '
      'journal ${ds.journal.length}\n'
      'BEFORE total $before ms: generate $tGen | write raw $tWrite | journal $tJournal | '
      'load $tLoad | resolve $tResolve | engine $tEngine | write results $tPut\n'
      '  raw-table channel payload: ${perRow.length} ops, ${(perRowBytes / 1024).round()} KB '
      '(encode $perRowEnc ms)\n'
      'AFTER total $after ms: worker isolate $tWorker ms (${res.timingsMs}) | '
      'bulk transaction $tBulk ms\n'
      '  whole-seed channel payload: ${res.ops.length} ops, ${(bulkBytes / 1024).round()} KB '
      '(encode $bulkEnc ms)',
    );
    expect(res.outcome.results, hasLength(90));
    expect(res.ops.length, lessThan(perRow.length ~/ 50));
  });
}
