// Any app through the REAL storage path: stored day_record JSON is read back
// as history by incremental recomputes, so every new field (origin, device,
// sleepingHr4h, notShared, sourceChange) must survive it. An incremental
// recompute from mid-window, a full one, and a pinned source must all agree.

import 'dart:convert';
import 'dart:io';

import 'package:airlog/data/db/sqlite_stores.dart';
import 'package:airlog/data/repositories/health_repository_impl.dart';
import 'package:airlog/data/resolver/resolver.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/source_apps.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';
import 'fixtures/hc_apps.dart';

final now = DateTime(2026, 9, 28, 21);
const today = '2026-09-28';

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('airlog_any'));
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('incremental == full recompute through sqlite; a pin too', () async {
    final db = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(tmp.path, 'a.db'),
    );
    final hc = FakeHealthConnect(history: true);
    hc.put([
      for (var i = 0; i < 16; i++) ...[
        // Fitbit until 6 days ago, then Oura (a device change).
        ...appDay(
          i >= 6 ? AppShape.fitbit : AppShape.oura,
          DayKey.add(today, -i),
          seed: i,
        ),
        // Samsung on the phone all along (sleep, HR, steps; no HRV/RHR).
        ...appDay(AppShape.samsung, DayKey.add(today, -i), seed: i),
      ],
    ], asChange: false);
    final repo = HealthRepositoryImpl(
      raw: SqliteRawStore(db, clock: () => now),
      app: SqliteAppStore(db, clock: () => now),
      clock: () => now,
      hc: hc,
      persistentStores: true,
    );
    await repo.requestHealthConnectPermissions();
    await repo.syncAgain();
    final from = DayKey.add(today, -15);

    Future<String> snapshot() async {
      final recs = await repo.app.records(DataMode.live, from, today);
      final res = await repo.app.results(DataMode.live, from, today);
      return jsonEncode({
        'records': [for (final r in recs) r.toJson()..remove('hrSamples')],
        'results': [for (final r in res) r.toJson()..remove('computedAt')],
      });
    }

    final cfg = ResolverConfig(
      mode: DataMode.live,
      now: now,
      enabled: const {SourceKind.healthConnect, SourceKind.ble},
    );
    final full = await snapshot();
    expect(full, contains(SourceApps.oura));
    expect(full, contains('"sleepingHr4h"'));

    // Incremental from mid-window: history comes from stored JSON.
    await repo.pipeline.recompute(
      DataMode.live,
      fromDate: DayKey.add(today, -4),
      cfg: cfg,
      profile: await repo.profile(),
    );
    expect(await snapshot(), full);

    // The switch day carries its re-learning state and the new baseline.
    final sw = (await repo.day(DayKey.add(today, -5)))!;
    expect(sw.record.provenance[Metric.hrv]!.origin, SourceApps.oura);
    expect(sw.result.sourceChange?.metric, 'hrv');
    expect(
      sw.result.notes.any((n) => n.title == 'Learning your HRV again'),
      isTrue,
    );

    // A pin, then a full recompute with it: identical.
    await repo.setSourceChoice(Metric.steps, SourceApps.oura);
    final pinned = await snapshot();
    expect(pinned, isNot(full));
    expect(
      (await repo.day(today))!.record.provenance[Metric.steps]!.origin,
      SourceApps.oura,
    );
    expect(
      (await repo.day(DayKey.add(today, -10)))!
          .record
          .provenance[Metric.steps]!
          .origin,
      SourceApps.samsungHealth,
      reason: 'days before the pinned app keep theirs',
    );
    await repo.pipeline.recompute(
      DataMode.live,
      cfg: cfg,
      profile: await repo.profile(),
    );
    expect(await snapshot(), pinned);
    await repo.dispose();
    await db.close();
  });
}
