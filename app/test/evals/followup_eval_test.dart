// Eval: follow-up questions (golden_followups.jsonl). Ten two-turn chats on
// demo data with a scripted model that answers like the on-device engine.
// The follow-up only makes sense with turn 1 ("And the day after?"), so
// its first request must carry turn 1: the first question, then the first
// answer as plain text (citations stripped), then the follow-up. The same
// set runs live in tool/eval_live.dart, which reports the pass rate per
// model.

import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/prompts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coach_harness.dart';
import 'eval_support.dart';

void main() {
  test('follow-ups: the second request carries the first turn', () async {
    final cases = loadJsonl('golden_followups.jsonl');
    expect(cases.length, greaterThanOrEqualTo(10));
    var carried = 0, plain = 0, last = 0, verified = 0;
    final failures = <String>[];
    for (final c in cases) {
      final id = c['id'] as String;
      final q1 = c['q1'] as String, q2 = c['q2'] as String;
      final llm = ScriptedLlm((r, _) => offlineTurn(r));
      final bench = Bench.cloud(llm);
      final a1 = await bench.ask(q1);
      final before = llm.requests.length;
      final a2 = await bench.module.service.ask(
        q2,
        conversationId: a1.conversationId,
      );
      if (llm.requests.length == before) {
        failures.add('$id: no request for the follow-up');
        continue;
      }
      final t = llm.requests[before].transcript;
      final users = t.whereType<LlmUser>().toList();
      final assistants = t.whereType<LlmAssistant>().toList();
      if (users.length >= 2 && users.first.text == q1) {
        carried++;
      } else {
        failures.add('$id: turn 1 missing from the follow-up request');
      }
      if (assistants.isNotEmpty &&
          assistants.first.turn.text == CoachPrompts.stripCitations(a1.text) &&
          !RegExp(r'\[r\d+\]').hasMatch(assistants.first.turn.text)) {
        plain++;
      } else {
        failures.add('$id: turn 1 answer not replayed as plain text');
      }
      if (t.last is LlmUser && (t.last as LlmUser).text == q2) {
        last++;
      } else {
        failures.add('$id: the follow-up is not the last message');
      }
      if (a2.error == null && (a2.verification?.verified ?? false)) {
        verified++;
      } else {
        failures.add('$id: follow-up answer not verified: ${a2.text}');
      }
    }
    final n = cases.length;
    final rows = [
      EvalRow('second request carries the first question', carried, n, 1),
      EvalRow('first answer replayed as plain text (no refs)', plain, n, 1),
      EvalRow('the follow-up is the newest message', last, n, 1),
      EvalRow('follow-up answers verified', verified, n, 1),
    ];
    report('followups', rows, failures: failures);
    for (final r in rows) {
      expect(r.ok, isTrue, reason: r.line);
    }
  });
}
