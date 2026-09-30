// PR #1 data integrity, which the PR shipped without tests:
//   * write_guard: generation-fenced writes. A mutation takes the next
//     generation; a write from an older one is refused (SupersededMutation)
//     and nothing it wrote lands. Writes outside any mutation are unfenced.
//   * pending recompute: a mutation for a mode leaves a durable marker that
//     survives an interrupted writer (and a reopen) until a complete result
//     write clears it.
//   * schema v3 → v4 on a v3-shaped database built by the real pipeline:
//     hr_record_day is backfilled from raw_hr (record id, origin, local
//     day), the derived day_record / day_result rows are dropped and then
//     rebuilt from raw on the next start, and the Health Connect change
//     token is cleared (other sources' tokens stay).

import 'dart:async';
import 'dart:io';

import 'package:airlog/data/db/schema.dart';
import 'package:airlog/data/db/sqlite_stores.dart';
import 'package:airlog/data/db/write_guard.dart';
import 'package:airlog/data/repositories/health_repository_impl.dart';
import 'package:airlog/data/services/health_connect/hc_types.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

final now = DateTime(2026, 9, 28, 10);

Future<int> count(Database db, String table, [String where = '1']) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM $table WHERE $where'))
            .first['n']
        as int;

/// 10 nights of Fitbit data in [hc].
void seedHc(FakeHealthConnect hc) {
  for (var d = 1; d <= 10; d++) {
    final wakeDay = DayKey.add(DayKey.of(now), -d + 1);
    final wake = DayKey.start(wakeDay).add(const Duration(hours: 7));
    final bed = wake.subtract(const Duration(hours: 8));
    hc.put([
      ...night('n$d', bed, wake),
      for (var i = 0; i < 12; i++)
        hrv('v$d-$i', bed.add(Duration(minutes: 20 + i * 30)), 45.0 + d % 5),
      scalar(HcType.restingHr, 'r$d', wake, 54.0 + d % 3),
      for (var m = 0; m < 240; m++)
        hr(
          'hr$d-${m ~/ 60}',
          wake.add(Duration(minutes: 60 + m)),
          70.0 + m % 30,
        ),
    ], asChange: false);
  }
}

void main() {
  sqfliteFfiInit();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('airlog_integrity_test');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('write guard', () {
    late Database db;
    late SqliteAppStore app;
    setUp(() async {
      db = await AirlogDatabase.open(
        factory: databaseFactoryFfi,
        path: p.join(tmp.path, 'g.db'),
      );
      app = SqliteAppStore(db, clock: () => now);
    });
    tearDown(() => db.close());

    test('each mutation takes the next generation', () async {
      expect(await app.getSetting(mutationGenerationKey), isNull);
      await app.mutate(() async {});
      await app.mutate(() async {});
      expect(await app.getSetting(mutationGenerationKey), '2');
    });

    test('a write from a superseded mutation is refused; the newer one '
        'lands', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final older = app.mutate(() async {
        entered.complete();
        await release.future;
        await app.setSetting('k', 'old');
      });
      await entered.future; // the older mutation holds generation 1
      await app.mutate(() => app.setSetting('k', 'new'));
      release.complete();
      await expectLater(older, throwsA(isA<SupersededMutation>()));
      expect(await app.getSetting('k'), 'new');
    });

    test('a nested mutation inherits the generation (no bump) and still '
        'marks its mode pending', () async {
      await app.mutate(() async {
        await app.mutate(() => app.setSetting('k', 'v'), mode: DataMode.live);
      });
      expect(await app.getSetting(mutationGenerationKey), '1');
      expect(await app.getSetting('k'), 'v');
      expect(await app.getSetting(pendingRecomputeKey('live')), 'true');
    });

    test('writes outside any mutation are not fenced', () async {
      await app.mutate(() async {});
      await app.setSetting('k', 'v');
      expect(await app.getSetting('k'), 'v');
    });
  });

  group('pending recompute', () {
    test('an interrupted writer leaves the marker, it survives a reopen, and '
        'only a complete result write clears it', () async {
      final path = p.join(tmp.path, 'p.db');
      var db = await AirlogDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      var app = SqliteAppStore(db, clock: () => now);
      await expectLater(
        app.mutate(
          () async => throw StateError('process killed'),
          mode: DataMode.live,
        ),
        throwsStateError,
      );
      expect(await app.getSetting(pendingRecomputeKey('live')), 'true');
      expect(await app.getSetting(pendingRecomputeKey('demo')), isNull);
      await db.close();

      db = await AirlogDatabase.open(factory: databaseFactoryFfi, path: path);
      app = SqliteAppStore(db, clock: () => now);
      expect(
        await app.getSetting(pendingRecomputeKey('live')),
        'true',
        reason: 'durable across a restart',
      );
      await app.putDays(DataMode.live, const [], const []);
      expect(await app.getSetting(pendingRecomputeKey('live')), isNull);
      await db.close();
    });
  });

  test('schema v3 → v4: hr_record_day backfill, derived rows dropped then '
      'rebuilt from raw, the Health Connect change token cleared', () async {
    final path = p.join(tmp.path, 'm.db');
    final hc = FakeHealthConnect(history: false);
    seedHc(hc);

    // 1. Real data through the real pipeline.
    var db = await AirlogDatabase.open(factory: databaseFactoryFfi, path: path);
    var repo = HealthRepositoryImpl(
      raw: SqliteRawStore(db, clock: () => now),
      app: SqliteAppStore(db, clock: () => now),
      clock: () => now,
      hc: hc,
      directories: (purpose) async => Directory(p.join(tmp.path, purpose)),
    );
    await repo.requestHealthConnectPermissions();
    await repo.syncNow();
    expect(await repo.latestDate(), DayKey.of(now));
    await repo.dispose();
    await db.close();

    // 2. Back to the v3 shape: no hr_record_day, no day_record.hr_start,
    //    user_version 3. raw_hr rows: two samples of one record on one
    //    day, one without a record id, one with no origin package.
    final noon = DayKey.start(DayKey.of(now)).add(const Duration(hours: 12));
    final yesterdayNoon = noon.subtract(const Duration(days: 1));
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.execute('DROP TABLE hr_record_day');
    await raw.execute('ALTER TABLE day_record DROP COLUMN hr_start');
    for (final (id, rec, origin, t) in [
      ('m1', 'recA', 'com.fitbit.FitbitMobile', noon),
      (
        'm2',
        'recA',
        'com.fitbit.FitbitMobile',
        noon.add(const Duration(minutes: 1)),
      ),
      ('m3', null, 'com.fitbit.FitbitMobile', noon),
      ('m4', 'recB', null, yesterdayNoon),
    ]) {
      await raw.insert('raw_hr', {
        'source': 'hc',
        'source_record_id': 'mig-$id',
        'record_id': rec,
        'origin_package': origin,
        't': t.millisecondsSinceEpoch,
        'bpm': 60.0,
        'ingested_at': now.millisecondsSinceEpoch,
      });
    }
    await raw.insert('change_tokens', {
      'source': 'hc',
      'scope': 'mig',
      'token': 't1',
      'created_at': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await raw.insert('change_tokens', {
      'source': 'ghapi',
      'scope': 'mig',
      'token': 't2',
      'created_at': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    expect(await count(raw, 'day_record'), greaterThan(0));
    expect(await count(raw, 'day_result'), greaterThan(0));
    await raw.setVersion(3);
    await raw.close();

    // 3. Open at the current version: the v4 step runs.
    db = await AirlogDatabase.open(factory: databaseFactoryFfi, path: path);
    expect(await db.getVersion(), kSchemaVersion);
    expect(kSchemaVersion, 4);
    final cols = [
      for (final r in await db.rawQuery('PRAGMA table_info(day_record)'))
        r['name'],
    ];
    expect(cols, contains('hr_start'));
    final days = await db.query(
      'hr_record_day',
      where: "record_id IN ('recA', 'recB')",
      orderBy: 'record_id',
    );
    expect(days, [
      {
        'source': 'hc',
        'record_id': 'recA',
        'origin': 'com.fitbit.FitbitMobile',
        'date': DayKey.of(noon),
      },
      {
        'source': 'hc',
        'record_id': 'recB',
        'origin': '',
        'date': DayKey.of(yesterdayNoon),
      },
    ], reason: 'one row per record and local day; no id, no row');
    expect(await count(db, 'day_record'), 0);
    expect(await count(db, 'day_result'), 0);
    expect(await count(db, 'change_tokens', "source = 'hc'"), 0);
    expect(await count(db, 'change_tokens', "source = 'ghapi'"), 1);

    // 4. The next start rebuilds the derived rows from raw.
    final app = SqliteAppStore(db, clock: () => now);
    repo = HealthRepositoryImpl(
      raw: SqliteRawStore(db, clock: () => now),
      app: app,
      clock: () => now,
      hc: hc,
      directories: (purpose) async => Directory(p.join(tmp.path, purpose)),
    );
    final latest = await repo.latestDate();
    expect(latest, DayKey.of(now));
    expect(await app.result(DataMode.live, latest!), isNotNull);
    expect(await count(db, 'day_result', "mode = 'live'"), greaterThan(5));
    expect(await app.hasStaleResults(DataMode.live, kAlgoVersion), isFalse);
    await repo.dispose();
    await db.close();
  });
}
