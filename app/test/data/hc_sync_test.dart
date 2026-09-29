import 'package:airlog/data/db/memory_stores.dart';
import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/services/health_connect/hc_mapper.dart';
import 'package:airlog/data/services/health_connect/hc_types.dart';
import 'package:airlog/data/sync/hc_sync.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final now = DateTime(2026, 9, 28, 12);
DateTime ago(Duration d) => now.subtract(d);

void main() {
  late FakeHealthConnect hc;
  late MemoryRawStore raw;
  late MemoryAppStore app;
  HcSync sync({bool context = false}) => HcSync(
    hc: hc,
    raw: raw,
    app: app,
    clock: () => now,
    contextEnabled: context,
  );

  Future<RawRows> all() async => raw.load(
    DateTime(2000),
    DateTime(2100),
    sources: const {SourceKind.healthConnect, SourceKind.context},
    includeRawHr: true,
  );

  setUp(() {
    hc = FakeHealthConnect();
    raw = MemoryRawStore();
    app = MemoryAppStore();
    final t = ago(const Duration(hours: 5));
    hc.put([
      hr('hr1', t, 60),
      hr('hr1', t.add(const Duration(minutes: 1)), 62),
      hr('hr1', t.add(const Duration(minutes: 2)), 64),
      hr('foreign', t, 99, origin: 'com.other.app'),
      hrv('v1', ago(const Duration(hours: 8)), 48),
      scalar(HcType.restingHr, 'r1', ago(const Duration(hours: 6)), 54),
      // Future-dated "projection" (ends after now) must be dropped.
      scalar(
        HcType.steps,
        'proj',
        ago(const Duration(hours: 1)),
        9000,
        end: now.add(const Duration(hours: 12)),
      ),
      scalar(
        HcType.steps,
        's1',
        ago(const Duration(hours: 3)),
        1200,
        end: ago(const Duration(hours: 2)),
      ),
      scalar(
        HcType.steps,
        'phone',
        ago(const Duration(hours: 3)),
        500,
        origin: 'com.google.android.apps.fitness',
        end: ago(const Duration(hours: 2)),
      ),
      ...night(
        'n1',
        ago(const Duration(hours: 13)),
        ago(const Duration(hours: 5)),
      ),
    ], asChange: false);
  });

  test('first sync: backfill reads EVERY origin (tagged), drops future, stores token', () async {
    final log = <SyncLogEntry>[];
    final dirty = await sync().run(log);
    expect(dirty, isNotEmpty);
    final rows = await all();
    expect(rows.hr.map((r) => r.bpm), unorderedEquals([60, 62, 64, 99]));
    expect(
      {for (final r in rows.hr) r.originPackage},
      {'com.fitbit.FitbitMobile', 'com.other.app'},
    );
    // Two apps' HR are bucketed apart, never averaged into one minute.
    expect(rows.hrDays.map((d) => d.origin).toSet(), {
      'com.fitbit.FitbitMobile',
      'com.other.app',
    });
    final steps = rows.scalars.where((s) => s.scalar == ScalarKind.steps);
    expect(steps.map((s) => s.value), unorderedEquals([1200, 500]));
    expect(steps.every((s) => s.source == SourceKind.healthConnect), isTrue);
    expect(rows.sleep.single.stages, hasLength(3));
    expect(await app.token(SourceKind.healthConnect, kHcTokenScope), isNotNull);
    final hrLog = log.firstWhere((e) => e.dataType == 'HEART_RATE');
    expect(hrLog.status, 'ok');
    final stepLog = log.firstWhere((e) => e.dataType == 'STEPS');
    expect(stepLog.message, contains('future-dated'));
  });

  test('weight takes the context-only path (stored only when enabled, as '
      'context rows)', () async {
    hc.put([
      scalar(
        HcType.weight,
        'w1',
        ago(const Duration(hours: 4)),
        71.5,
        origin: 'com.withings.wiscale2',
      ),
    ], asChange: false);
    await sync().run([]);
    expect(
      (await all()).scalars.where((s) => s.scalar == ScalarKind.weight),
      isEmpty,
    );
    await sync(context: true).run([]);
    await app.setToken(SourceKind.healthConnect, kHcTokenScope, null);
    await sync(context: true).run([]);
    final w = (await all()).scalars.where((s) => s.scalar == ScalarKind.weight);
    expect(w.single.source, SourceKind.context);
    expect(w.single.originPackage, 'com.withings.wiscale2');
  });

  test('incremental: upserts + deletions (by record id, any table)', () async {
    await sync().run([]);
    hc.put([hr('hr2', ago(const Duration(minutes: 30)), 70)]);
    hc.delete('v1');
    hc.delete('r1');
    final log = <SyncLogEntry>[];
    final dirty = await sync().run(log);
    expect(dirty, isNotEmpty);
    final rows = await all();
    expect(rows.hr.map((r) => r.bpm), contains(70));
    expect(rows.hrv, isEmpty);
    expect(rows.scalars.where((s) => s.scalar == ScalarKind.rhr), isEmpty);
    expect(
      log.firstWhere((e) => e.dataType == 'changes').message,
      contains('2 deleted'),
    );
  });

  test('an upsert replaces the whole record (shortened HR record)', () async {
    await sync().run([]);
    hc.put([hr('hr1', ago(const Duration(hours: 5)), 61)]);
    await sync().run([]);
    final rows = await all();
    expect(
      rows.hr
          .where((r) => r.originPackage == 'com.fitbit.FitbitMobile')
          .map((r) => r.bpm),
      [61],
    );
  });

  test('sleep upsert (session only) triggers a re-read with stages', () async {
    await sync().run([]);
    hc.reads.clear();
    hc.put(
      night(
        'n2',
        ago(const Duration(hours: 37)),
        ago(const Duration(hours: 29)),
      ),
    );
    await sync().run([]);
    expect(hc.reads.any((r) => r.$1 == HcType.sleep), isTrue);
    final n2 = (await all()).sleep.firstWhere((s) => s.recordId == 'n2');
    expect(n2.stages, hasLength(3));
  });

  test(
    'expired token → full re-read, which also catches missed deletions',
    () async {
      await sync().run([]);
      // Deleted upstream but the delete event was lost.
      hc.store.remove('v1');
      hc.expireNext = true;
      final log = <SyncLogEntry>[];
      await sync().run(log);
      expect(
        log.any(
          (e) =>
              e.dataType == 'changes_token' && e.message!.contains('expired'),
        ),
        isTrue,
      );
      expect((await all()).hrv, isEmpty);
      expect(
        await app.token(SourceKind.healthConnect, kHcTokenScope),
        isNotNull,
      );
    },
  );

  test('a null changes response is treated like an expired token', () async {
    await sync().run([]);
    hc.failChangesNext = true;
    hc.reads.clear();
    await sync().run([]);
    expect(hc.reads.where((r) => r.$1 == HcType.heartRate), isNotEmpty);
  });

  test('denied and failing types are logged; the rest still sync', () async {
    hc.granted = HcType.values.toSet()..remove(HcType.hrv);
    hc.failingTypes.add(HcType.restingHr);
    final log = <SyncLogEntry>[];
    await sync().run(log);
    expect(
      log
          .firstWhere((e) => e.dataType == 'HEART_RATE_VARIABILITY_RMSSD')
          .status,
      'denied',
    );
    expect(
      log.firstWhere((e) => e.dataType == 'RESTING_HEART_RATE').status,
      'error',
    );
    expect((await all()).hr, isNotEmpty);
  });

  test(
    'background sync without the background permission does nothing',
    () async {
      hc.background = false;
      final log = <SyncLogEntry>[];
      final dirty = await sync().run(log, background: true);
      expect(dirty, isEmpty);
      expect(log.single.status, 'denied');
    },
  );

  test('mapper: future-dated records are dropped at ingest', () {
    final m = mapHcRecords(
      [
        scalar(
          HcType.steps,
          'x',
          now.subtract(const Duration(hours: 1)),
          5,
          end: now.add(const Duration(hours: 3)),
        ),
        scalar(HcType.restingHr, 'y', now.add(const Duration(days: 1)), 50),
        scalar(
          HcType.restingHr,
          'z',
          now.subtract(const Duration(hours: 1)),
          50,
        ),
      ],
      now: now,
      ingestedAt: now,
    );
    expect(m.future, 2);
    expect(m.rows.scalars.single.sourceRecordId, 'z');
  });

  test(
    'mapper: BLOOD_OXYGEN → one spo2Avg + one spo2Min row per sample, in %',
    () {
      final t = ago(const Duration(hours: 6));
      final m = mapHcRecords(
        [
          scalar(HcType.spo2, 'pct', t, 96),
          scalar(HcType.spo2, 'frac', t.add(const Duration(minutes: 5)), 0.94),
          scalar(HcType.spo2, 'low', t.add(const Duration(minutes: 10)), 42),
          scalar(HcType.spo2, 'high', t.add(const Duration(minutes: 15)), 101),
          scalar(HcType.spo2, 'other', t, 97, origin: 'com.other.app'),
        ],
        now: now,
        ingestedAt: now,
      );
      final s = m.rows.scalars
          .where((r) => r.originPackage != 'com.other.app')
          .toList();
      expect(s.map((r) => r.sourceRecordId), [
        'pct:avg',
        'pct:min',
        'frac:avg',
        'frac:min',
      ]);
      expect(s.map((r) => r.scalar), [
        ScalarKind.spo2Avg,
        ScalarKind.spo2Min,
        ScalarKind.spo2Avg,
        ScalarKind.spo2Min,
      ]);
      expect(s.map((r) => r.recordId), ['pct', 'pct', 'frac', 'frac']);
      expect(s[0].value, 96);
      expect(s[1].value, 96);
      expect(
        s[2].value,
        closeTo(94, 1e-9),
        reason: 'a fraction is scaled to %',
      );
      expect(
        s.every((r) => r.source == SourceKind.healthConnect && r.day == null),
        isTrue,
      );
      expect(s.first.start, t);
      // Another app's SpO₂ is kept, tagged with its origin (any app).
      expect(
        m.rows.scalars.where((r) => r.originPackage == 'com.other.app'),
        hasLength(2),
      );
      expect(m.foreign, 0);
    },
  );

  test(
    'sync: SpO2 keeps mean + min rows through backfill, upserts and deletions',
    () async {
      hc.put([
        scalar(HcType.spo2, 'o1', ago(const Duration(hours: 9)), 95),
        scalar(HcType.spo2, 'o2', ago(const Duration(hours: 7)), 0.97),
      ], asChange: false);
      final log = <SyncLogEntry>[];
      await sync().run(log);
      List<double> vals(RawRows r, ScalarKind k) => [
        for (final s in r.scalars)
          if (s.scalar == k) s.value,
      ]..sort();
      var rows = await all();
      expect(vals(rows, ScalarKind.spo2Avg), [95, closeTo(97, 1e-9)]);
      expect(vals(rows, ScalarKind.spo2Min), [95, closeTo(97, 1e-9)]);
      final spo2Log = log.firstWhere((e) => e.dataType == 'BLOOD_OXYGEN');
      expect(spo2Log.status, 'ok');
      expect(spo2Log.records, 2, reason: 'samples, not rows');

      hc.put([scalar(HcType.spo2, 'o1', ago(const Duration(hours: 9)), 91)]);
      hc.delete('o2');
      await sync().run([]);
      rows = await all();
      expect(vals(rows, ScalarKind.spo2Avg), [91]);
      expect(vals(rows, ScalarKind.spo2Min), [91]);
    },
  );

  test('mapper: HC origin comes from the record, not the (empty) sourceId', () {
    final m = mapHcRecords(
      [hr('a', now, 60, origin: 'com.fitbit.FitbitMobile')],
      now: now,
      ingestedAt: now,
    );
    expect(m.rows.hr.single.originPackage, 'com.fitbit.FitbitMobile');
    expect(m.rows.hr.single.recordId, 'a');
  });
}
