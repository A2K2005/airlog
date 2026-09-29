// Any app at repository level: detectedSources / sourceChoices /
// setSourceChoice over a fake Health Connect with two apps, the planner's
// number check on real-app-shaped days, and the diagnostics rows.

import 'dart:convert';

import 'package:airlog/data/db/memory_stores.dart';
import 'package:airlog/data/repositories/health_repository_impl.dart';
import 'package:airlog/data/resolver/source_choice.dart';
import 'package:airlog/data/sync/score_pipeline.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/source_apps.dart';
import 'package:airlog/domain/engine/today_planner.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/features/diagnostics/diagnostics_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fixtures/plan_numbers.dart';
import 'fakes.dart';
import 'fixtures/hc_apps.dart';

final now = DateTime(2026, 9, 28, 21);
const today = '2026-09-28';

Future<HealthRepositoryImpl> repoWith(FakeHealthConnect hc) async {
  final repo = HealthRepositoryImpl(
    raw: MemoryRawStore(),
    app: MemoryAppStore(),
    clock: () => now,
    hc: hc..history = true,
  );
  await repo.requestHealthConnectPermissions();
  await repo.syncAgain();
  return repo;
}

void main() {
  test('two apps: detected, one chosen per metric, pin and unpin', () async {
    final hc = FakeHealthConnect();
    hc.put([
      for (var i = 0; i < 20; i++)
        ...appDay(AppShape.fitbit, DayKey.add(today, -i)),
      for (var i = 0; i < 6; i++)
        ...appDay(AppShape.oura, DayKey.add(today, -i)),
    ], asChange: false);
    final repo = await repoWith(hc);

    final apps = await repo.detectedSources();
    expect(apps.map((a) => a.displayName), ['Google Health (Fitbit)', 'Oura']);
    final oura = apps.firstWhere((a) => a.origin == SourceApps.oura);
    expect(oura.daysWithData[Metric.hrv], 6);

    var choices = await repo.sourceChoices();
    expect(choices[Metric.hrv]!.origin, SourceApps.fitbit);
    expect(choices[Metric.hrv]!.automatic, isTrue);
    expect(
      (await repo.day(today))!.record.provenance[Metric.hrv]!.origin,
      SourceApps.fitbit,
    );

    await repo.setSourceChoice(Metric.hrv, SourceApps.oura);
    choices = await repo.sourceChoices();
    expect(choices[Metric.hrv]!.origin, SourceApps.oura);
    expect(choices[Metric.hrv]!.automatic, isFalse);
    final d = (await repo.day(today))!;
    expect(d.record.provenance[Metric.hrv]!.origin, SourceApps.oura);
    expect(d.record.hrvRmssd, greaterThanOrEqualTo(60));
    // The first Oura night started a new HRV baseline.
    final first = (await repo.day(DayKey.add(today, -5)))!;
    expect(
      first.result.notes.any((n) => n.title == 'New HRV baseline'),
      isTrue,
    );
    // Nights before Oura existed keep Fitbit (the pin starts at Oura's first
    // night); the two are never pooled.
    final before = (await repo.day(DayKey.add(today, -10)))!;
    expect(before.record.provenance[Metric.hrv]!.origin, SourceApps.fitbit);
    final hrvC = d.result.recovery!.components.firstWhere(
      (c) => c.key == 'hrv',
    );
    expect(hrvC.baseline?.count ?? 0, lessThanOrEqualTo(5));

    await repo.setSourceChoice(Metric.hrv, null);
    choices = await repo.sourceChoices();
    expect(choices[Metric.hrv]!.automatic, isTrue);
    expect(
      (await repo.day(DayKey.add(today, -10)))!
          .record
          .provenance[Metric.hrv]!
          .origin,
      SourceApps.fitbit,
    );

    // Diagnostics rows (J): chosen app, coverage, alternatives.
    final rows = metricSourceRows(choices, apps);
    final hrv = rows.firstWhere((r) => r.metric == Metric.hrv);
    expect(hrv.chosen, 'Google Health (Fitbit)');
    expect(hrv.chosenDays, 14);
    expect(hrv.alternatives, {'Oura': 6});
    await repo.dispose();
  });

  test('Fitbit → Samsung Health: the saved source choice records that '
      'Samsung Health shares neither HRV nor resting HR, so Recovery '
      '(sleeping HR) starts on the first night after the switch', () async {
    final hc = FakeHealthConnect();
    hc.put([
      for (var i = 6; i < 30; i++)
        ...appDay(AppShape.fitbit, DayKey.add(today, -i), seed: i),
      for (var i = 0; i < 6; i++)
        ...appDay(AppShape.samsung, DayKey.add(today, -i), seed: i),
    ], asChange: false);
    final app = MemoryAppStore();
    final repo = HealthRepositoryImpl(
      raw: MemoryRawStore(),
      app: app,
      clock: () => now,
      hc: hc..history = true,
    );
    await repo.requestHealthConnectPermissions();
    await repo.syncAgain();

    Future<OriginPlan> saved(Metric m) async => OriginPlan.fromJson(
      jsonDecode((await app.getSetting(originPlanKey(m)))!)
          as Map<String, dynamic>,
    );
    expect((await saved(Metric.restingHr)).notShared, [
      SourceApps.samsungHealth,
    ]);
    expect((await saved(Metric.hrv)).notShared, [SourceApps.samsungHealth]);
    expect((await saved(Metric.sleep)).current, SourceApps.samsungHealth);

    final first = (await repo.day(DayKey.add(today, -5)))!;
    expect(
      first.record.provenance[Metric.sleep]!.origin,
      SourceApps.samsungHealth,
    );
    expect(
      first.result.recovery?.components.any((c) => c.key == 'sleep_hr'),
      isTrue,
      reason: 'first night after the switch',
    );
    expect(first.result.sourceChange?.to?.origin, SourceApps.samsungHealth);
    final plan = Engine.planToday(
      (await repo.day(today))!,
      now: DateTime(2026, 9, 28, 10),
    );
    expect(plan.relearningSource, 'Samsung Health');

    // Pinning keeps what is known about the apps.
    await repo.setSourceChoice(Metric.restingHr, SourceApps.fitbit);
    expect((await saved(Metric.restingHr)).notShared, [
      SourceApps.samsungHealth,
    ]);
    await repo.dispose();
  });

  test('a fresher app is suggested before the absence rule switches', () async {
    final hc = FakeHealthConnect();
    hc.put([
      for (var i = 2; i < 20; i++)
        ...appDay(AppShape.fitbit, DayKey.add(today, -i)),
      for (var i = 0; i < 3; i++)
        ...appDay(AppShape.oura, DayKey.add(today, -i)),
    ], asChange: false);
    final repo = await repoWith(hc);
    final c = (await repo.sourceChoices())[Metric.hrv]!;
    expect(c.origin, SourceApps.fitbit);
    expect(c.suggestedOrigin, SourceApps.oura);
    expect(c.suggestedDisplayName, 'Oura');
    await repo.dispose();
  });

  test('planner number check on real-app-shaped days (Samsung, WHOOP, '
      'Oura, a mid-window switch)', () async {
    for (final shape in AppShape.values) {
      final hc = FakeHealthConnect();
      hc.put([
        for (var i = 0; i < 16; i++)
          ...appDay(
            i < 5 && shape == AppShape.fitbit ? AppShape.oura : shape,
            DayKey.add(today, -i),
            seed: i,
          ),
      ], asChange: false);
      final repo = await repoWith(hc);
      final days = await repo.range(DayKey.add(today, -15), today);
      expect(days, isNotEmpty, reason: shape.name);
      for (final b in days) {
        for (final at in [
          DayKey.start(b.date).add(const Duration(hours: 10)),
          DayKey.start(b.date).add(const Duration(hours: 21)),
        ]) {
          final p = Engine.planToday(b, now: at);
          expect(p.actions.length, lessThanOrEqualTo(3));
          expect(
            unsupportedNumbers(p, allowedNumbers(b, now: at)),
            isEmpty,
            reason: '${shape.name} ${b.date}',
          );
          if (shape == AppShape.samsung &&
              b.result.recovery == null &&
              b.result.notShared.isNotEmpty) {
            expect(p.summary, contains('Samsung Health'));
          }
        }
      }
      final lastPlan = TodayPlanner.plan(today: days.last, now: now);
      expect(lastPlan.sources, isNotEmpty);
      await repo.dispose();
    }
  });
}
