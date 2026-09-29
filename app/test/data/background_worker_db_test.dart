// QA-01 (P0): the workmanager worker runs in the app's process. With
// sqflite's default single-instance handle its close() closed the app's
// database too, and every screen failed until the process died. The worker
// now opens a private connection (DataModule.open(background: true) →
// AirlogDatabase.open(singleInstance: false)).

import 'dart:io';

import 'package:airlog/data/db/sqlite_stores.dart';
import 'package:airlog/data/repositories/health_repository_impl.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final now = DateTime(2026, 9, 28, 10);

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('airlog_qa01'));
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'the worker closing its own connection leaves the app readable',
    () async {
      final path = p.join(tmp.path, 'a.db');
      final appDb = await AirlogDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      final repo = HealthRepositoryImpl(
        raw: SqliteRawStore(appDb, clock: () => now),
        app: SqliteAppStore(appDb, clock: () => now),
        clock: () => now,
        demoDays: 10,
        initialMode: DataMode.demo,
      );
      expect(await repo.latestDate(), DayKey.of(now));

      // The background worker: its own connection, used, then closed.
      final worker = await AirlogDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        singleInstance: false,
      );
      expect(identical(worker, appDb), isFalse);
      await worker.rawQuery('SELECT COUNT(*) FROM settings');
      await worker.close();

      // The app keeps working.
      final days = await repo.range(
        DayKey.add(DayKey.of(now), -3),
        DayKey.of(now),
      );
      expect(days, isNotEmpty);
      await repo.dispose();
      await appDb.close();
    },
  );

  test('why: a second single-instance open is the SAME handle', () async {
    final path = p.join(tmp.path, 'b.db');
    final a = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final b = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    expect(identical(a, b), isTrue);
    await a.close();
  });

  test(
    'a closed store surfaces a typed error, never a raw DatabaseException',
    () async {
      final path = p.join(tmp.path, 'c.db');
      final db = await AirlogDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      final repo = HealthRepositoryImpl(
        raw: SqliteRawStore(db, clock: () => now),
        app: SqliteAppStore(db, clock: () => now),
        clock: () => now,
        demoDays: 10,
        initialMode: DataMode.demo,
      );
      await repo.latestDate();
      await db.close();
      await expectLater(
        repo.range(DayKey.add(DayKey.of(now), -3), DayKey.of(now)),
        throwsA(
          isA<DataUnavailableException>().having(
            (e) => e.kind,
            'kind',
            DataErrorKind.storage,
          ),
        ),
      );
      await repo.dispose();
    },
  );
}
