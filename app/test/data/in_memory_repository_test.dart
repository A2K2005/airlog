import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/data/services/widget/widget_sink.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

// End-to-end demo pipeline in memory: generator → resolver → engine.
// (Engine-dependent assertions: these need lib/domain/engine implemented.)

final now = DateTime(2026, 9, 28, 9, 30);

void main() {
  late InMemoryHealthRepository repo;
  setUpAll(() => repo = InMemoryHealthRepository.demo(now: now));

  test('engine ran without error', () {
    expect(repo.engineError, isNull, reason: '${repo.engineError}');
  });

  test('latest date is today and range covers ~90 days', () async {
    expect(repo.mode, DataMode.demo);
    final latest = await repo.latestDate();
    expect(latest, DayKey.of(now));
    final all = await repo.range(DayKey.add(latest!, -89), latest);
    expect(all.length, greaterThanOrEqualTo(85));
  });

  test('recovery is non-null on most days once calibrated', () async {
    final latest = (await repo.latestDate())!;
    final days = await repo.range(DayKey.add(latest, -75), latest);
    final withRecovery = days.where((d) => d.result.recovery != null).length;
    expect(withRecovery / days.length, greaterThan(0.8));
    for (final d in days) {
      expect(d.result.algoVersion, kAlgoVersion);
      expect(
        d.record.provenance[Metric.hrv]?.definition,
        anyOf(isNull, 'demo_sleep_mean_rmssd'),
      );
    }
  });

  test('demo HR is dense enough for zone-based strain on most days', () async {
    final latest = (await repo.latestDate())!;
    final days = await repo.range(
      DayKey.add(latest, -60),
      DayKey.add(latest, -1),
    );
    final zones = days
        .where((d) => d.result.strain?.method == StrainMethod.hrZones)
        .length;
    expect(
      zones / days.length,
      greaterThan(0.9),
      reason: days
          .where((d) => d.result.strain?.method != StrainMethod.hrZones)
          .map((d) => '${d.date}: ${d.result.strain?.method}')
          .join(', '),
    );
    final strains = days.map((d) => d.result.strain!.strain).toList();
    expect(strains.reduce((a, b) => a > b ? a : b), greaterThan(10));
  });

  test('day bundle carries 1-minute HR, sleep and provenance', () async {
    final d = (await repo.day(DayKey.add(DayKey.of(now), -3)))!;
    expect(d.record.hrSamples.length, greaterThan(1000));
    expect(d.record.mainSleep, isNotNull);
    expect(d.record.provenance[Metric.restingHr]!.definition, 'demo_daily_rhr');
    expect(d.record.provenance[Metric.sleep]!.source, SourceKind.demo);
    expect(d.record.lastDataAt, isNotNull);
  });

  test('planted illness makes the health monitor alert', () async {
    final today = DayKey.of(now);
    final ill = await repo.range(
      DayKey.add(today, -24),
      DayKey.add(today, -21),
    );
    expect(ill, isNotEmpty);
    expect(
      ill.any((d) => d.result.health.alert),
      isTrue,
      reason: ill
          .map((d) => '${d.date}: ${d.result.health.alertReason}')
          .join('\n'),
    );
  });

  test('alcohol shows up as a negative journal insight', () async {
    final insights = await repo.journalInsights();
    final alcohol = insights
        .where((i) => i.factor == JournalFactor.alcohol)
        .toList();
    expect(alcohol, hasLength(1));
    expect(alcohol.single.delta, lessThan(0));
  });

  test('widget snapshot shows the same day as Today, marked stale when it '
      "isn't today (QA-08)", () async {
    final early = InMemoryHealthRepository.demo(
      now: DateTime(2026, 9, 28, 1, 30),
      days: 40,
    );
    final latest = (await early.latestDate())!;
    final days = (await early.range(
      DayKey.add(latest, -1),
      latest,
    )).reversed.toList();
    expect(
      days.first.result.recovery,
      isNull,
      reason: 'before wake-up today has no recovery',
    );
    final s = WidgetSnapshot.fromDays(days, demo: true, today: latest);
    expect(s.date, latest);
    expect(s.recovery, isNull, reason: "never yesterday's recovery as today's");
    expect(s.stale, isFalse);
    final old = WidgetSnapshot.fromDays(
      days.sublist(1),
      demo: true,
      today: latest,
    );
    expect(old.stale, isTrue);
    expect(old.recovery, isNotNull);
  });

  test(
    'demo opened early in the morning still has last night + a recovery',
    () async {
      final r = InMemoryHealthRepository.demo(
        now: DateTime(2026, 9, 28, 5, 10),
        days: 40,
      );
      final d = (await r.day('2026-09-28'))!;
      expect(d.record.mainSleep, isNotNull);
      expect(
        d.record.mainSleep!.end.isBefore(DateTime(2026, 9, 28, 5, 10)),
        isTrue,
      );
      expect(d.result.recovery, isNotNull);
      expect(r.syncStatus.lastSyncAt, isNull, reason: 'pre-seeded in memory');
    },
  );

  test('journal round trip (separate from sync)', () async {
    final date = DayKey.of(now);
    final e = (await repo.journal(date)).toggle(JournalFactor.meditation);
    await repo.saveJournal(e);
    expect(
      (await repo.journal(date)).factors,
      contains(JournalFactor.meditation),
    );
  });

  test('demo diagnostics describe the synthetic source', () async {
    final r = await repo.diagnostics(windowDays: 3);
    final hr = r.types.firstWhere((t) => t.dataType == 'HEART_RATE');
    expect(hr.records, greaterThan(2000));
    expect(hr.medianSpacingSec, closeTo(60, 5));
    expect(r.verdicts.first, contains('full zone-based strain'));
    expect(r.rawJsonPath, isNotNull);
  });

  test('sources list demo as active', () async {
    final s = await repo.sources();
    expect(s.firstWhere((x) => x.kind == SourceKind.demo).enabled, isTrue);
    final gh = s.firstWhere((x) => x.kind == SourceKind.googleHealthApi);
    expect(gh.available, isFalse);
    expect(gh.detail, contains('Not configured'));
  });

  test('export writes CSV + JSON', () async {
    final r = await repo.exportAll();
    expect(r.files.where((f) => f.endsWith('.csv')), isNotEmpty);
    expect(r.files.where((f) => f.endsWith('.json')), hasLength(1));
  });

  test('live mode is empty and separate; switching back keeps demo', () async {
    final r2 = InMemoryHealthRepository.demo(now: now, days: 40);
    await r2.setMode(DataMode.live);
    expect(await r2.latestDate(), isNull);
    await r2.setMode(DataMode.demo);
    expect(await r2.latestDate(), DayKey.of(now));
  });

  test('saved live workout appears in the demo day', () async {
    final r3 = InMemoryHealthRepository.demo(now: now, days: 40);
    final t0 = now.subtract(const Duration(hours: 1));
    await r3.liveHr.saveSession(
      kind: 'workout',
      name: 'Live test',
      samples: [
        for (var i = 0; i < 600; i++)
          LiveHrSample(t0.add(Duration(seconds: i)), 140 + i % 10),
      ],
    );
    final d = (await r3.day(DayKey.of(now)))!;
    expect(d.record.workouts.any((w) => w.name == 'Live test'), isTrue);
  });
}
