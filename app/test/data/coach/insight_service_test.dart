// InsightServiceImpl: templates, the master switch and levels, caching,
// feedback, memory use; and a run against the Coach UI's fake repository
// contract (test/support/coach_fixtures.dart).

import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/data/coach/coach_store.dart';
import 'package:airlog/data/coach/insight_service_impl.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/coach_service.dart';
import 'package:airlog/domain/coach/insight_contracts.dart';
import 'package:airlog/domain/coach/safety.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/coach_fixtures.dart';

final now = DateTime(2026, 9, 29, 9);
const day = '2026-09-28';

void main() {
  late InMemoryHealthRepository health;
  late CoachModule m;
  setUp(() {
    health = InMemoryHealthRepository.demo(now: now);
    m = CoachModule.inMemory(health, clock: () => now);
  });

  test('basic cards: one per kind, one per workout, detail routes', () async {
    final cards = await m.insights.cards(day);
    final kinds = [for (final c in cards) c.kind];
    expect(kinds.where((k) => k == InsightKind.sleep), hasLength(1));
    expect(kinds.where((k) => k == InsightKind.recovery), hasLength(1));
    expect(kinds.where((k) => k == InsightKind.strain), hasLength(1));
    final b = await health.day(day);
    expect(
      kinds.where((k) => k == InsightKind.workout),
      hasLength(b!.record.workouts.length),
    );
    for (final c in cards) {
      expect(c.source, InsightSource.template);
      expect(c.route, isNotNull);
      expect(c.metrics, isNotEmpty);
      expect(c.refs, containsAll(c.metrics));
    }
    final sleep = cards.firstWhere((c) => c.kind == InsightKind.sleep);
    expect(sleep.metrics.first.label, startsWith('Asleep'));
    final rec = cards.firstWhere((c) => c.kind == InsightKind.recovery);
    expect(rec.headline, contains('made the biggest difference'));
  });

  test('"Show coach" off or level off → no cards', () async {
    await m.repository.saveSettings(const CoachSettings(enabled: false));
    expect(await m.insights.cards(day), isEmpty);
    await m.repository.saveSettings(const CoachSettings());
    await m.insights.setLevel(InsightLevel.off);
    expect(await m.insights.cards(day), isEmpty);
    expect(await m.insights.level(), InsightLevel.off);
  });

  test('hidden cards are filtered and feedback persists', () async {
    final first = await m.insights.cards(day);
    final id = first.first.id;
    await m.insights.setFeedback(id, InsightFeedback.hidden);
    final after = await m.insights.cards(day);
    expect(after.map((c) => c.id), isNot(contains(id)));
    await m.insights.setFeedback(first[1].id, InsightFeedback.helpful);
    expect(
      (await m.insights.cards(day))
          .firstWhere((c) => c.id == first[1].id)
          .feedback,
      InsightFeedback.helpful,
    );
  });

  test('cards are cached per id, revision, algoVersion and level', () async {
    await m.insights.cards(day);
    final cached = await m.repository.store.insights(day);
    expect(cached, isNotEmpty);
    expect(cached.every((c) => c.level == InsightLevel.basic), isTrue);
    await m.insights.cards(day);
    expect((await m.repository.store.insights(day)).length, cached.length);
  });

  test('a saved training goal adds goal alignment and is recorded', () async {
    final goal = await m.repository.addMemory(
      'Training for a half marathon on 15 Nov',
      category: MemoryCategory.goals,
    );
    final cards = await m.insights.cards(day);
    final strain = cards.firstWhere((c) => c.kind == InsightKind.strain);
    expect(strain.usedMemoryIds, [goal.id]);
    expect(strain.bullets.map((b) => b.label), contains('Your goal'));
  });

  test('watchDay emits at once and again after feedback', () async {
    final seen = <List<Insight>>[];
    final sub = m.insights.watchDay(day).listen(seen.add);
    await pumpEventQueue();
    expect(seen, hasLength(1));
    await m.insights.setFeedback(seen.first.first.id, InsightFeedback.hidden);
    await pumpEventQueue();
    expect(seen.length, 2);
    expect(seen.last.length, seen.first.length - 1);
    await sub.cancel();
  });

  group('against the Coach UI fakes (test/support/coach_fixtures.dart)', () {
    test('CoachServiceImpl runs over FakeCoachRepository', () async {
      final repo = FakeCoachRepository();
      final svc = CoachServiceImpl(
        health: health,
        coach: repo,
        clock: () => now,
      );
      final safe = await svc.ask('I think I am having a heart attack');
      expect(safe.safety, isTrue);
      expect(safe.text, SafetyCheck.emergencyMessage);
      expect(repo.calls, contains('appendMessage:assistant'));
      // The fake's client() throws notConfigured: the UI gets the exception.
      await expectLater(
        svc.ask('How did I sleep?'),
        throwsA(isA<CoachException>()),
      );
      expect(await svc.suggestions(), isNotEmpty);
    });

    test('InsightServiceImpl runs over FakeCoachRepository', () async {
      final repo = FakeCoachRepository();
      final svc = InsightServiceImpl(
        health: health,
        coach: repo,
        store: MemoryCoachStore(),
        clock: () => now,
      );
      final cards = await svc.watchDay(day).first;
      expect(cards, isNotEmpty);
      await repo.saveSettings(const CoachSettings(enabled: false));
      expect(await svc.watchDay(day).first, isEmpty);
    });
  });
}
