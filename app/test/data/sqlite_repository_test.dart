// HealthRepositoryImpl on the real sqlite stores (sqflite_common_ffi):
// demo seeding through the same pipeline as live data, then a live sync
// from a fake Health Connect, mode separation, profile + wipe.

import 'dart:io';

import 'package:airlog/data/db/sqlite_stores.dart';
import 'package:airlog/data/repositories/health_repository_impl.dart';
import 'package:airlog/data/resolver/definitions.dart';
import 'package:airlog/data/services/health_connect/hc_types.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

final now = DateTime(2026, 9, 28, 10);

Future<int> raw(Database db, String where) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM raw_scalar WHERE $where'))
            .first['n']
        as int;

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  late Database db;
  late FakeHealthConnect hc;
  late HealthRepositoryImpl repo;

  /// 20 nights of Fitbit data in the fake Health Connect.
  void seedHc() {
    for (var d = 1; d <= 20; d++) {
      final wakeDay = DayKey.add(DayKey.of(now), -d + 1);
      final wake = DayKey.start(wakeDay).add(const Duration(hours: 7));
      final bed = wake.subtract(const Duration(hours: 8));
      hc.put([
        ...night('n$d', bed, wake),
        for (var i = 0; i < 20; i++)
          hrv(
            'v$d-$i',
            bed.add(Duration(minutes: 20 + i * 20)),
            45.0 + (d % 5),
          ),
        scalar(HcType.restingHr, 'r$d', wake, 54.0 + (d % 3)),
        scalar(
          HcType.respiratoryRate,
          'b$d',
          wake.subtract(const Duration(hours: 2)),
          14.5,
        ),
        for (var m = 0; m < 600; m++)
          hr(
            'hr$d-${m ~/ 60}',
            wake.add(Duration(minutes: 60 + m)),
            70.0 + (m % 30),
          ),
      ], asChange: false);
    }
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('airlog_repo_test');
    db = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(tmp.path, 'r.db'),
    );
    hc = FakeHealthConnect(history: false);
    repo = HealthRepositoryImpl(
      raw: SqliteRawStore(db, clock: () => now),
      app: SqliteAppStore(db, clock: () => now),
      clock: () => now,
      hc: hc,
      demoDays: 30,
      directories: (purpose) async => Directory(p.join(tmp.path, purpose)),
    );
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
    await tmp.delete(recursive: true);
  });

  test(
    'first launch is LIVE with an honest empty state; nothing seeded',
    () async {
      hc.granted = {};
      expect(await repo.latestDate(), isNull);
      expect(repo.mode, DataMode.live);
      expect(
        await raw(db, "source = 'demo'"),
        0,
        reason: 'no demo before the choice',
      );
      final sources = await repo.sources();
      expect(
        sources.firstWhere((s) => s.kind == SourceKind.healthConnect).detail,
        'Connect Health Connect to see your data',
      );
    },
  );

  test(
    'fresh install: the first grant syncs by itself (no manual sync)',
    () async {
      seedHc();
      hc.granted = {};
      expect(await repo.latestDate(), isNull);
      await repo.requestHealthConnectPermissions();
      final done = repo.syncStatusChanges.firstWhere(
        (s) => s.phase == SyncPhase.idle && s.lastDataAt != null,
      );
      await done.timeout(const Duration(seconds: 20));
      expect(await repo.latestDate(), DayKey.of(now));
      expect(repo.mode, DataMode.live);
    },
  );

  test(
    '"Try with sample data" seeds demo through sqlite, explicitly',
    () async {
      await repo.setMode(DataMode.demo);
      final latest = await repo.latestDate();
      expect(repo.mode, DataMode.demo);
      expect(latest, DayKey.of(now));
      final d = (await repo.day(DayKey.add(latest!, -1)))!;
      expect(d.record.definitionOf(Metric.hrv), 'demo_sleep_mean_rmssd');
      expect(d.record.hrSamples.length, greaterThan(1000));
      expect(d.result.sleep, isNotNull);
      final log = await repo.syncLog();
      expect(log.first.source, SourceKind.demo);
    },
  );

  test(
    'connecting Health Connect switches to live and syncs Fitbit data',
    () async {
      seedHc();
      await repo.setMode(DataMode.demo); // tried the sample data first
      await repo.latestDate();
      final st = await repo.requestHealthConnectPermissions();
      expect(st.allGranted, isTrue);
      expect(repo.mode, DataMode.live);
      await repo.syncNow();
      final latest = await repo.latestDate();
      expect(latest, DayKey.of(now));
      final days = await repo.range(DayKey.add(latest!, -19), latest);
      expect(days.length, greaterThanOrEqualTo(19));
      final last = days.last;
      expect(last.record.definitionOf(Metric.hrv), 'hc_sleep_mean_rmssd');
      expect(last.record.definitionOf(Metric.restingHr), 'hc_daily_rhr');
      expect(last.result.recovery, isNotNull);
      expect(last.record.provenance[Metric.hrv]!.origin, kFitbitOrigin);
      final choices = await repo.sourceChoices();
      expect(choices[Metric.hrv]!.origin, kFitbitOrigin);
      expect(choices[Metric.hrv]!.displayName, 'Google Health (Fitbit)');
      expect(choices[Metric.hrv]!.automatic, isTrue);
      final apps = await repo.detectedSources();
      expect(apps.single.origin, kFitbitOrigin);
      expect(apps.single.daysWithData[Metric.restingHr], 14);
      expect(repo.syncStatus.lastDataByApp.keys, ['Google Health (Fitbit)']);
      expect(repo.syncStatus.phase, SyncPhase.idle);
      final log = await repo.syncLog();
      expect(
        log.any(
          (e) =>
              e.source == SourceKind.healthConnect &&
              e.dataType == 'HEART_RATE',
        ),
        isTrue,
      );

      // Demo data is still there, separately.
      await repo.setMode(DataMode.demo);
      expect(
        (await repo.day(DayKey.add(DayKey.of(now), -1)))!.record
            .definitionOf(Metric.hrv),
        'demo_sleep_mean_rmssd',
      );
    },
  );

  test(
    'a deletion arriving via the changes token removes the day\'s value',
    () async {
      seedHc();
      await repo.requestHealthConnectPermissions();
      await repo.syncNow();
      final today = DayKey.of(now);
      expect((await repo.day(today))!.record.restingHr, isNotNull);
      hc.delete('r1');
      await repo.syncNow();
      expect((await repo.day(today))?.record.restingHr, isNull);
    },
  );

  test('saving the profile recomputes and bumps the revision', () async {
    await repo.setMode(DataMode.demo);
    await repo.latestDate();
    final rev = repo.revision;
    await repo.saveProfile(const UserProfile(birthYear: 1990, sex: Sex.male));
    expect(repo.revision, greaterThan(rev));
    expect((await repo.profile()).birthYear, 1990);
  });

  test('wipeData deletes rows but keeps settings; demo re-seeds', () async {
    await repo.setMode(DataMode.demo);
    await repo.saveProfile(const UserProfile(birthYear: 1985));
    await repo.wipeData();
    expect((await repo.profile()).birthYear, 1985);
    expect(await repo.latestDate(), DayKey.of(now));
  });

  test('diagnostics in live mode probe Health Connect', () async {
    seedHc();
    await repo.requestHealthConnectPermissions();
    final r = await repo.diagnostics(windowDays: 3);
    final hrStat = r.types.firstWhere((t) => t.dataType == 'HEART_RATE');
    expect(hrStat.origins['com.fitbit.FitbitMobile'], greaterThan(0));
    expect(hrStat.medianSpacingSec, 60);
    expect(r.verdicts.first, contains('full zone-based strain'));
    expect(r.verdicts.any((v) => v.contains('No history permission')), isTrue);
    expect(File(r.rawJsonPath!).existsSync(), isTrue);
  });
}
