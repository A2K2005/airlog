// Eval 6 — insight cards and the TodayPlan, over all 90 demo days.
//   * Every template card (sleep, recovery, strain, workout, Health Monitor,
//     weekly) passes the real verifier against its own refs and the output
//     policy: 100%. Voice checks: at most 2 body sentences, no streak
//     language, no exclamation marks.
//   * InsightLevel.full is cut from v1: at "full" the service still makes
//     no model call and every card stays a template.
//   * TodayPlanner.plan(today:, sync:, now:) for every day, fresh and stale:
//     summary and every action pass the verifier (numbers traceable to the
//     day's DayResult / DayRecord through the coach's own tools) and the
//     output policy.

import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/data/coach/insight_templates.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/insight_contracts.dart';
import 'package:airlog/domain/coach/format.dart';
import 'package:airlog/domain/coach/policy.dart';
import 'package:airlog/domain/coach/tools.dart';
import 'package:airlog/domain/coach/verifier.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/today_planner.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coach_harness.dart';
import 'eval_support.dart';

void main() {
  test('templates for all 90 demo days pass the verifier and the policy',
      () async {
    final h = InMemoryHealthRepository.demo(now: kEvalNow);
    final today = DayKey.of(kEvalNow);
    final days = await h.range(DayKey.add(today, -89), today);
    expect(days.length, greaterThanOrEqualTo(85));
    var cards = 0, verified = 0, policyOk = 0, voiceOk = 0;
    final perKind = <InsightKind, int>{};
    final failures = <String>[];
    for (final b in days) {
      final week = await h.range(DayKey.add(b.date, -6), b.date);
      final drafts = InsightTemplates.build(b, week: week);
      final kinds = <InsightKind>{};
      for (final d in drafts) {
        cards++;
        final i = d.insight;
        perKind[i.kind] = (perKind[i.kind] ?? 0) + 1;
        if (i.kind != InsightKind.workout && !kinds.add(i.kind)) {
          failures.add('${i.id}: two ${i.kind.name} cards on one day');
        }
        final rep = Verifier.verify(
          answer: d.text,
          question: '',
          today: b.date,
          calls: const [
            ToolCall(id: 'card', name: CoachTools.insightCard, input: {}),
          ],
          results: [d.result],
          memories: d.memoryTexts,
        );
        if (rep.verified) {
          verified++;
        } else {
          failures.add('${i.id} ${rep.unsupported}: ${d.text}');
        }
        final pol = OutputPolicy.check(d.text);
        if (pol.ok) {
          policyOk++;
        } else {
          failures.add('${i.id} policy ${pol.violations.map((v) => v.describe)}');
        }
        final sentences =
            RegExp(r'[.!?](?=\s|$)').allMatches(i.body).length;
        final voice = sentences <= 2 &&
            !d.text.contains('!') &&
            !RegExp(r'\bstreak|in a row\b', caseSensitive: false)
                .hasMatch(d.text) &&
            i.metrics.isNotEmpty;
        if (voice) {
          voiceOk++;
        } else {
          failures.add('${i.id} voice: ${i.body}');
        }
      }
    }
    final rows = [
      EvalRow('cards verified', verified, cards, 1.0),
      EvalRow('cards passing the output policy', policyOk, cards, 1.0),
      EvalRow('cards in the product voice', voiceOk, cards, 1.0),
    ];
    report('cards', rows, failures: failures, notes: [
      'cards per kind: ${{for (final e in perKind.entries) e.key.name: e.value}}',
    ]);
    expect(perKind.keys, containsAll([
      InsightKind.sleep,
      InsightKind.recovery,
      InsightKind.strain,
      InsightKind.workout,
      InsightKind.weekly,
    ]));
    for (final row in rows) {
      expect(row.ok, isTrue, reason: row.line);
    }
  });

  test('InsightLevel.full is cut: no model call, templates only', () async {
    final llm = ScriptedLlm((_, _) => const LlmTurn(text: 'HEADLINE: x'));
    final h = InMemoryHealthRepository.demo(now: kEvalNow);
    final m = CoachModule.inMemory(
      h,
      clock: () => kEvalNow,
      settings: kCloudSettings,
      clients: (_, _, _) => llm,
      keys: const {CoachProvider.claude: 'sk-ant-test-FAKEKEY123'},
    );
    await m.insights.setLevel(InsightLevel.full);
    final cards = await m.insights.cards(DayKey.of(kEvalNow));
    final rows = [
      EvalRow('model calls at level "full"', llm.requests.length, 1, 0.0,
          higherIsBetter: false),
      EvalRow('cards written by a template',
          cards.where((c) => c.source == InsightSource.template).length,
          cards.length, 1.0),
    ];
    report('cards_full_level_cut', rows);
    expect(cards, isNotEmpty);
    for (final row in rows) {
      expect(row.ok, isTrue, reason: row.line);
    }
  });

  test('TodayPlan for all 90 demo days is traceable and policy-clean',
      () async {
    final b0 = Bench.offline();
    final h = b0.health;
    final today = DayKey.of(kEvalNow);
    final days = await h.range(DayKey.add(today, -89), today);
    var plans = 0, verified = 0, policyOk = 0;
    final failures = <String>[];
    // Each day twice: as "today" in its own evening (fresh), and seen
    // from the eval's fixed now (stale: the "waiting for data" path).
    final runs = [
      for (final b in days) ...[
        (b, DayKey.start(b.date).add(const Duration(hours: 21))),
        (b, kEvalNow),
      ],
    ];
    for (final (b, now) in runs) {
      final plan = TodayPlanner.plan(today: b, now: now);
      plans++;
      final text = [
        plan.headline,
        plan.summary,
        for (final a in plan.actions) ...[a.title, a.why],
      ].join('\n');
      // The day's facts through the coach's own tools (what the coach
      // could cite for this day), plus the calibration counts.
      final tb = CoachToolbox(
        health: h,
        coach: b0.module.coach,
        now: kEvalNow,
        cloud: false,
        mode: CoachMode.useMyData,
      );
      final calls = [
        ToolCall(id: 'd', name: CoachTools.day, input: {'date': b.date}),
        ToolCall(
          id: 'l',
          name: CoachTools.trainingLoad,
          input: {'date': b.date},
        ),
        ToolCall(
          id: 'h',
          name: CoachTools.healthMonitor,
          input: {'date': b.date},
        ),
      ];
      final res = [...await tb.run(calls), _dayExtras(b)];
      final rep = Verifier.verify(
        answer: text,
        question: '',
        today: DayKey.of(now),
        calls: calls,
        results: res,
      );
      if (rep.verified) {
        verified++;
      } else {
        failures.add('${b.date} ${rep.unsupported}: ${text.replaceAll('\n', ' | ')}');
      }
      if (OutputPolicy.check(text).ok) {
        policyOk++;
      } else {
        failures.add('${b.date} policy: $text');
      }
    }
    final rows = [
      EvalRow('plans verified against the day', verified, plans, 1.0),
      EvalRow('plans passing the output policy', policyOk, plans, 1.0),
    ];
    report('today_plan', rows, failures: failures);
    for (final row in rows) {
      expect(row.ok, isTrue, reason: row.line);
    }
  });
}

/// DayResult numbers the tools don't carry (calibration, bedtime advice).
ToolResult _dayExtras(DayBundle b) {
  final r = b.result;
  var n = 0;
  final refs = <SourceRef>[];
  void add(String label, double v, String unit) => refs.add(
    SourceRef(id: 'x${++n}', label: label, value: v, unit: unit, date: r.date),
  );
  add('Recovery calibration · baseline nights so far',
      r.calibration.haveNights.toDouble(), 'nights');
  add('Recovery calibration · baseline nights needed',
      r.calibration.needNights.toDouble(), 'nights');
  final last = b.record.lastDataAt;
  if (last != null) {
    add('Newest data', CoachFormat.minutesOfDay(last).toDouble(), 'clock');
  }
  final bt = r.bedtime;
  if (bt != null) {
    add('Sleep need tonight', bt.projectedNeedMinutes, 'min');
    add('Sleep debt tonight', bt.debtMinutes, 'min');
    if (bt.recommendedBedtimeMinutes != null) {
      add('Recommended bedtime', bt.recommendedBedtimeMinutes!, 'clock');
    }
    if (bt.habitualWakeMinutes != null) {
      add('Habitual wake time', bt.habitualWakeMinutes!, 'clock');
    }
  }
  return ToolResult(callId: 'x', name: 'day_extras', content: const {}, refs: refs);
}
