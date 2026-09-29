// TodayPlan property test over all 90 demo days (the seeded synthetic
// tracker with its planted illness): every plan has at most 3 actions and
// 2 chips, and every number in its text is a cited field (or a documented
// comparison of two), in the morning and in the evening phase.

import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/today_planner.dart';
import 'package:airlog/domain/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fixtures/plan_numbers.dart';

void main() {
  test('90 demo days: ≤ 3 actions, ≤ 2 chips, no unsupported number', () async {
    final now = DateTime(2026, 9, 28, 9);
    final repo = InMemoryHealthRepository.demo(now: now);
    final latest = (await repo.latestDate())!;
    final days = await repo.range(DayKey.add(latest, -89), latest);
    expect(days, hasLength(90));
    final states = <DayState>{};
    final kinds = <PlanActionKind>{};
    for (final b in days) {
      final start = DayKey.start(b.date);
      for (final at in [
        start.add(const Duration(hours: 10)),
        start.add(const Duration(hours: 21)),
      ]) {
        final p = TodayPlanner.plan(today: b, now: at);
        final where = '${b.date} ${at.hour}:00 ${p.state.name}';
        expect(p.actions.length, lessThanOrEqualTo(3), reason: where);
        expect(p.evidence.length, lessThanOrEqualTo(2), reason: where);
        expect(p.headline, isNotEmpty, reason: where);
        expect(p.summary, isNotEmpty, reason: where);
        expect(
          unsupportedNumbers(p, allowedNumbers(b, now: at)),
          isEmpty,
          reason: where,
        );
        states.add(p.state);
        kinds.addAll(p.actions.map((a) => a.kind));
        if (at.hour == 21 && b.result.bedtime != null) {
          expect(p.phase, PlanPhase.tonight, reason: where);
          expect(
            p.actions.any((a) => a.kind == PlanActionKind.effort),
            isFalse,
            reason: where,
          );
        }
      }
    }
    // The planted illness and the calibration weeks reach several states.
    expect(states, containsAll([DayState.calibrating, DayState.easy]));
    expect(states.length, greaterThanOrEqualTo(4), reason: '$states');
    expect(kinds, containsAll([PlanActionKind.effort, PlanActionKind.sleep]));
  });
}
