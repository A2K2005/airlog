import 'dart:io';

import 'package:airlog/data/db/hr_buckets.dart';
import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/db/schema.dart';
import 'package:airlog/data/db/sqlite_stores.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final now = DateTime(2026, 9, 28, 12);

RawHrRow hrRow(String id, DateTime t, double bpm, {String rec = 'rec'}) =>
    RawHrRow(
      source: SourceKind.healthConnect,
      sourceRecordId: id,
      recordId: rec,
      originPackage: 'com.fitbit.FitbitMobile',
      ingestedAt: now,
      t: t,
      bpm: bpm,
    );

RawScalarRow rhrRow(String id, DateTime t, double v) => RawScalarRow(
  source: SourceKind.healthConnect,
  sourceRecordId: id,
  recordId: id,
  ingestedAt: now,
  scalar: ScalarKind.rhr,
  start: t,
  value: v,
);

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  late Database db;
  late SqliteRawStore raw;
  late SqliteAppStore app;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('airlog_db_test');
    db = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(tmp.path, 'a.db'),
    );
    raw = SqliteRawStore(db, clock: () => now);
    app = SqliteAppStore(db, clock: () => now);
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('schema: every table exists at the current version', () async {
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name']).toSet();
    for (final t in [...kRawTables, ...kAppTables]) {
      expect(tables, contains(t));
    }
    expect(await db.getVersion(), kSchemaVersion);
  });

  test('migration round-trip: v1 data survives an upgrade step', () async {
    final path = p.join(tmp.path, 'm.db');
    var d = await AirlogDatabase.open(factory: databaseFactoryFfi, path: path);
    await SqliteRawStore(
      d,
      clock: () => now,
    ).upsert(RawRows(scalars: [rhrRow('a', now, 55)]));
    await d.close();
    d = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
      version: kSchemaVersion + 1,
      migrations: [
        ...kMigrations,
        ['ALTER TABLE raw_scalar ADD COLUMN quality REAL'],
      ],
    );
    expect(await d.getVersion(), kSchemaVersion + 1);
    final cols = (await d.rawQuery('PRAGMA table_info(raw_scalar)'))
        .map((r) => r['name']);
    expect(cols, contains('quality'));
    final rows = await SqliteRawStore(
      d,
      clock: () => now,
    ).load(DateTime(2000), DateTime(2100));
    expect(rows.scalars.single.value, 55);
    await d.close();
  });

  test('upsert is idempotent (same batch twice = same rows)', () async {
    final t = now.subtract(const Duration(hours: 2));
    final batch = RawRows(
      hr: [
        hrRow('h1', t, 60),
        hrRow('h2', t.add(const Duration(seconds: 30)), 64),
      ],
      scalars: [rhrRow('r1', t, 52)],
    );
    await raw.upsert(batch);
    await raw.upsert(batch);
    final c = await raw.counts();
    expect(c['raw_hr'], 2);
    expect(c['raw_scalar'], 1);
    expect(c['hr_day'], 1);
    final rows = await raw.load(DayKey.start(DayKey.of(t)), now);
    // Two samples in the same minute are averaged into one bucket.
    expect(rows.hrDays.single.toSamples().single.bpm, 62);
  });

  test('replaceWindow deletes rows missing from a full re-read', () async {
    final t = now.subtract(const Duration(hours: 3));
    await raw.upsert(
      RawRows(scalars: [rhrRow('keep', t, 50), rhrRow('gone', t, 51)]),
    );
    await raw.replaceWindow(
      SourceKind.healthConnect,
      RawKind.scalar,
      now.subtract(const Duration(days: 1)),
      now,
      RawRows(scalars: [rhrRow('keep', t, 50)]),
      scalar: ScalarKind.rhr,
    );
    final rows = await raw.load(DateTime(2000), DateTime(2100));
    expect(rows.scalars.map((s) => s.sourceRecordId), ['keep']);
  });

  test(
    'deleteRecords removes every sample of a record and rebuilds HR buckets',
    () async {
      final t = now.subtract(const Duration(hours: 2));
      await raw.upsert(
        RawRows(
          hr: [
            hrRow('a1', t, 60, rec: 'A'),
            hrRow('a2', t.add(const Duration(minutes: 1)), 61, rec: 'A'),
            hrRow('b1', t.add(const Duration(minutes: 5)), 70, rec: 'B'),
          ],
        ),
      );
      final days = await raw.deleteRecords(SourceKind.healthConnect, ['A']);
      expect(days, contains(DayKey.of(t)));
      final rows = await raw.load(
        DayKey.start(DayKey.of(t)),
        now,
        includeRawHr: true,
      );
      expect(rows.hr.map((r) => r.sourceRecordId), ['b1']);
      expect(rows.hrDays.single.toSamples().map((s) => s.bpm), [70]);
    },
  );

  test(
    'HR older than the raw retention window lives on as minute buckets',
    () async {
      final old = now.subtract(const Duration(days: 40));
      await raw.upsert(RawRows(hr: [hrRow('o1', old, 58)]));
      final rows = await raw.load(
        DayKey.start(DayKey.of(old)),
        DayKey.end(DayKey.of(old)),
        includeRawHr: true,
      );
      expect(
        rows.hr,
        isEmpty,
        reason: 'raw samples are not kept beyond 14 days',
      );
      expect(rows.hrDays.single.toSamples().single.bpm, 58);
    },
  );

  test('HR minute blob round-trips (DST-safe slot count)', () {
    const date = '2026-09-27';
    final start = DayKey.start(date);
    final samples = [
      HrSample(start.add(const Duration(minutes: 3)), 61.2),
      HrSample(start.add(const Duration(hours: 23, minutes: 59)), 99.9),
    ];
    final back = decodeSamples(date, encodeSamples(date, samples));
    expect(back.map((s) => s.bpm), [61.2, 99.9]);
    expect(back.first.t, samples.first.t);
    expect(minutesInDay(date), 1440);
  });

  test('AppStore: day record + result round trip keeps HR samples', () async {
    const date = '2026-09-27';
    final start = DayKey.start(date);
    final rec = DayRecord(
      date: date,
      restingHr: 52,
      hrSamples: [
        for (var i = 0; i < 10; i++)
          HrSample(start.add(Duration(minutes: i)), 60.0 + i),
      ],
      provenance: {
        Metric.restingHr: const Provenance(
          SourceKind.healthConnect,
          'hc_daily_rhr',
        ),
      },
    );
    final res = DayResult(
      date: date,
      algoVersion: kAlgoVersion,
      computedAt: now,
      health: const HealthMonitorResult(metrics: [], alert: false),
      calibration: const Calibration(haveNights: 3),
    );
    await app.putDays(DataMode.live, [rec], [res]);
    final r2 = (await app.record(DataMode.live, date))!;
    expect(r2.hrSamples, hasLength(10));
    expect(r2.hrSamples.last.bpm, 69);
    expect(r2.definitionOf(Metric.restingHr), 'hc_daily_rhr');
    expect((await app.result(DataMode.live, date))!.algoVersion, kAlgoVersion);
    expect(
      await app.record(DataMode.demo, date),
      isNull,
      reason: 'modes are separate',
    );
    expect(await app.latestDate(DataMode.live), date);
    expect(await app.hasStaleResults(DataMode.live, kAlgoVersion), isFalse);
  });

  test('AppStore: journal, settings, tokens, sync log', () async {
    await app.putJournal(
      DataMode.demo,
      const JournalEntry(date: '2026-09-27', factors: {JournalFactor.alcohol}),
    );
    expect((await app.journal(DataMode.demo, '2026-09-27'))!.factors, {
      JournalFactor.alcohol,
    });
    expect(await app.journal(DataMode.live, '2026-09-27'), isNull);
    await app.setSetting('k', 'v');
    expect(await app.getSetting('k'), 'v');
    await app.setToken(SourceKind.healthConnect, 'changes', 't1');
    expect(await app.token(SourceKind.healthConnect, 'changes'), 't1');
    await app.addLog([
      SyncLogEntry(
        at: now,
        source: SourceKind.healthConnect,
        dataType: 'HEART_RATE',
        status: 'ok',
        records: 3,
      ),
    ]);
    expect((await app.logs()).single.records, 3);
    await app.wipe();
    expect(await app.getSetting('k'), 'v', reason: 'wipe keeps settings');
    expect(await app.token(SourceKind.healthConnect, 'changes'), isNull);
  });
}
