// The app's first-launch demo seed (worker isolate + one bulk sqlite
// transaction) must store exactly what the per-row store path stores and
// score exactly what InMemoryHealthRepository.demo (goldens) scores, and a
// later full recompute from the database (profile change, source toggle)
// must not shift any score.

import 'dart:convert';
import 'dart:io';

import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/db/sqlite_stores.dart';
import 'package:airlog/data/repositories/health_repository_impl.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/data/resolver/resolver.dart';
import 'package:airlog/data/services/demo/demo_generator.dart';
import 'package:airlog/data/sync/demo_seed.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final now = DateTime(2026, 9, 28, 9, 30);

Future<Database> openDb(Directory dir, String name) => AirlogDatabase.open(
  factory: databaseFactoryFfi,
  path: p.join(dir.path, name),
);

HealthRepositoryImpl sqliteRepo(Database db, {required bool bulk}) =>
    HealthRepositoryImpl(
      raw: SqliteRawStore(db, clock: () => now),
      app: SqliteAppStore(db, clock: () => now),
      clock: () => now,
      demoWriter: bulk ? (ops) => runSqlOps(db, ops) : null,
      demoRunner: bulk ? runDemoSeedInIsolate : runDemoSeedInline,
      persistentStores: bulk,
      initialMode: DataMode.demo, // the user chose "Try with sample data"
    );

String resultsJson(List<DayResult> rs) =>
    jsonEncode([for (final r in rs) r.toJson()]);

String recordsJson(List<DayRecord> rs) => jsonEncode([
  for (final r in rs)
    {
      ...(r.toJson()..remove('hrSamples')),
      'hr': [
        for (final s in r.hrSamples) '${s.t.millisecondsSinceEpoch}:${s.bpm}',
      ],
    },
]);

Future<Map<String, Object?>> tableDump(
  Database db,
  String table,
  String order,
) async {
  final rows = await db.query(table, where: "source = 'demo'", orderBy: order);
  return {
    'n': rows.length,
    'rows': jsonEncode(rows.map((r) => r.toString()).toList()),
  };
}

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  setUp(
    () async => tmp = await Directory.systemTemp.createTemp('airlog_seed_test'),
  );
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {} // a failed test may leave the file open (Windows)
  });

  test(
    'bulk isolate seed == in-memory demo == full recompute from the db',
    () async {
      final db = await openDb(tmp, 'bulk.db');
      final repo = sqliteRepo(db, bulk: true);
      final statuses = <SyncStatus>[];
      final sub = repo.syncStatusChanges.listen(statuses.add);
      await repo.start();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(statuses.first.phase, SyncPhase.syncing);
      expect(statuses.first.message, 'Preparing 90 days of sample data…');
      expect(repo.syncStatus.phase, SyncPhase.idle);

      final app = repo.app;
      final mem = InMemoryHealthRepository.demo(now: now);
      final memResults = await mem.app.results(
        DataMode.demo,
        '0000-00-00',
        '9999-12-31',
      );
      final memRecords = await mem.app.records(
        DataMode.demo,
        '0000-00-00',
        '9999-12-31',
      );
      expect(memResults, hasLength(90));

      final seeded = await app.results(
        DataMode.demo,
        '0000-00-00',
        '9999-12-31',
      );
      expect(resultsJson(seeded), resultsJson(memResults));
      expect(
        recordsJson(
          await app.records(DataMode.demo, '0000-00-00', '9999-12-31'),
        ),
        recordsJson(memRecords),
      );
      expect(
        (await app.journals(DataMode.demo)).length,
        (await mem.app.journals(DataMode.demo)).length,
      );

      await repo.pipeline.recompute(
        DataMode.demo,
        cfg: ResolverConfig(mode: DataMode.demo, now: now),
        profile: const UserProfile(),
      );
      expect(
        resultsJson(
          await app.results(DataMode.demo, '0000-00-00', '9999-12-31'),
        ),
        resultsJson(memResults),
      );

      // A second start on the same database finds fresh demo data: no reseed.
      final again = sqliteRepo(db, bulk: true);
      final st2 = <SyncStatus>[];
      final sub2 = again.syncStatusChanges.listen(st2.add);
      await again.start();
      await Future<void>.delayed(Duration.zero);
      await sub2.cancel();
      expect(st2.where((s) => s.phase == SyncPhase.syncing), isEmpty);
      await again.dispose();
      await repo.dispose();
      await db.close();
    },
  );

  test(
    'bulk seed stores the same raw rows as the per-row store path',
    () async {
      final a = await openDb(tmp, 'a.db');
      final b = await openDb(tmp, 'b.db');
      final bulk = sqliteRepo(a, bulk: true);
      final rows = sqliteRepo(b, bulk: false);
      await bulk.start();
      await rows.start();
      for (final (table, order) in [
        ('raw_hr', 'source_record_id'),
        ('hr_day', 'date'),
        ('raw_hrv', 'source_record_id'),
        ('raw_sleep', 'source_record_id'),
        ('raw_sleep_stage', 'session_id, start'),
        ('raw_workout', 'source_record_id'),
        ('raw_scalar', 'source_record_id'),
      ]) {
        final x = await tableDump(a, table, order);
        final y = await tableDump(b, table, order);
        expect(x['n'], y['n'], reason: table);
        // updated_at of hr_day is the write time (same clock here).
        expect(x['rows'], y['rows'], reason: table);
      }
      expect(
        resultsJson(
          await bulk.app.results(DataMode.demo, '0000-00-00', '9999-12-31'),
        ),
        resultsJson(
          await rows.app.results(DataMode.demo, '0000-00-00', '9999-12-31'),
        ),
      );
      await bulk.dispose();
      await rows.dispose();
      await a.close();
      await b.close();
    },
  );

  test(
    'demo record ids are unique per table (resolverInput skips store dedup)',
    () {
      final ds = DemoGenerator(seed: 42, now: now).generate();
      for (final kind in RawKind.values) {
        final ids = [for (final r in ds.rows.ofKind(kind)) r.sourceRecordId];
        expect(ids.toSet().length, ids.length, reason: kind.name);
      }
    },
  );

  test('a failing seed reports an error status and is retried', () async {
    final db = await openDb(tmp, 'fail.db');
    var fail = true;
    final repo = HealthRepositoryImpl(
      raw: SqliteRawStore(db, clock: () => now),
      app: SqliteAppStore(db, clock: () => now),
      clock: () => now,
      demoWriter: (ops) async {
        if (fail) throw StateError('disk full');
        await runSqlOps(db, ops);
      },
      persistentStores: true,
      initialMode: DataMode.demo,
    );
    await expectLater(repo.start(), throwsStateError);
    expect(repo.syncStatus.phase, SyncPhase.error);
    expect(repo.syncStatus.message, contains('disk full'));
    fail = false;
    expect(await repo.latestDate(), isNotNull);
    expect(repo.syncStatus.phase, SyncPhase.idle);
    await repo.dispose();
    await db.close();
  });
}
