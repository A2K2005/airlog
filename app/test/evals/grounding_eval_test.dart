// Eval 1 — grounding.
//   * golden_grounding.jsonl (40+ real questions over 90 days of demo data)
//     through the on-device engine: every answer verified with no repair,
//     every number / date / event in every final answer supported (100%),
//     the output policy clean, and at least the expected number of sources.
//   * Hallucinating fakes: a scripted "cloud model" calls the right tools,
//     then answers with one number changed or an invented event. The
//     verifier must catch 100% of them, and every final stored answer must
//     still be verified (repair round, then the facts table).
//     The RAW pre-repair unsupported-claim rate of those fake answers is
//     reported too (measured by the real verifier; informational, no gate).
//   * The documented competitor failures (research/06, 06d): an invented
//     swim, a 5 am run that didn't happen, band-off hours reported as a nap,
//     sleep claimed on a night with no data, a cruise, a made-up workout, a
//     wrong recovery number, missing data reported as zero.
//
// Journal questions are reported separately and kept out of the headline
// pass rate: the demo generator plants the journal effects the engine then
// finds, so they prove grounding of the numbers, not insight quality.

import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/policy.dart';
import 'package:airlog/domain/coach/prompts.dart';
import 'package:airlog/domain/coach/verifier.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coach_harness.dart';
import 'eval_support.dart';

AskContext? contextOf(Map<String, dynamic> r) =>
    r['screen'] == null && r['date'] == null
    ? null
    : AskContext(screen: r['screen'] as String?, date: r['date'] as String?);

/// Changes the first cited number (not a clock time) by +17.
String tamperNumber(String answer) {
  final m = RegExp(r'(?<![\d:.,])(\d+(?:\.\d+)?)(?![\d:])(?=[^\[\n]{0,14}\[r\d+\])')
      .firstMatch(answer);
  if (m == null) return '$answer You slept 9h 58m last night.';
  final v = double.parse(m.group(1)!);
  final w = v == v.roundToDouble() ? '${v.round() + 17}' : (v + 17).toStringAsFixed(1);
  return answer.replaceRange(m.start, m.end, w);
}

String inventEvent(String answer) =>
    '$answer You also swam 1.5 km on Sun 27 Sep.';

void main() {
  test('golden questions: grounded on-device answers', () async {
    final rows = loadJsonl('golden_grounding.jsonl');
    expect(rows.length, greaterThanOrEqualTo(40));
    final bench = Bench.offline();
    final failures = <String>[];
    var verified = 0, noRepair = 0, policyOk = 0, refsOk = 0;
    var claims = 0, supported = 0;
    var circ = 0, circOk = 0;
    for (final r in rows) {
      if (r['circular'] == true) {
        final m = await bench.ask(r['q'] as String, context: contextOf(r));
        circ++;
        if ((m.verification?.verified ?? false) &&
            !(m.verification?.repaired ?? true)) {
          circOk++;
        }
        continue;
      }
      final m = await bench.ask(r['q'] as String, context: contextOf(r));
      final v = m.verification;
      final ok = m.error == null && v != null && v.verified;
      if (ok) verified++;
      if (v != null && !v.repaired) noRepair++;
      if (OutputPolicy.check(m.text).ok) policyOk++;
      if (m.refs.length >= (r['refs'] as int? ?? 1)) refsOk++;
      claims += v?.checkedNumbers ?? 0;
      supported += (v?.checkedNumbers ?? 0) - (v?.unsupported.length ?? 0);
      if (!ok || (v.repaired) || m.refs.length < (r['refs'] as int? ?? 1)) {
        failures.add('${r['id']} "${r['q']}" → ${m.text.replaceAll('\n', ' ')}'
            ' ${v?.unsupported}');
      }
    }
    final n = rows.length - circ;
    final rows2 = [
      EvalRow('answers verified', verified, n, 1.0),
      EvalRow('answered without a repair round', noRepair, n, 1.0),
      EvalRow('claims supported in final answers', supported, claims, 1.0),
      EvalRow('answers with the expected sources', refsOk, n, 1.0),
      EvalRow('answers passing the output policy', policyOk, n, 1.0),
      EvalRow('(journal, circular on demo) verified', circOk, circ, 1.0),
    ];
    report('grounding_golden', rows2, failures: failures);
    for (final row in rows2) {
      expect(row.ok, isTrue, reason: row.line);
    }
  });

  test('hallucinating fakes are caught and never reach the user', () async {
    final rows = [
      for (final r in loadJsonl('golden_grounding.jsonl'))
        if ((r['refs'] as int? ?? 1) >= 1) r,
    ];
    var cases = 0, caught = 0, finalVerified = 0, finalClean = 0;
    var rawClaims = 0, rawUnsupported = 0;
    final failures = <String>[];
    for (final mode in ['number', 'event']) {
      for (final r in rows) {
        var bad = '';
        String? q0;
        final llm = ScriptedLlm((req, turn) async {
          if (req.isRepair) {
            // Stubborn: repeats the hallucination.
            return LlmTurn(text: bad);
          }
          final t = await offlineTurn(req);
          if (t.toolCalls.isNotEmpty) return t;
          bad = mode == 'number' ? tamperNumber(t.text) : inventEvent(t.text);
          return LlmTurn(text: bad);
        });
        final bench = Bench.cloud(llm);
        q0 = r['q'] as String;
        final m = await bench.ask(q0, context: contextOf(r));
        cases++;
        // The raw, pre-repair answer through the real verifier.
        final last = llm.requests.last;
        final calls = [
          for (final i in last.transcript)
            if (i is LlmAssistant) ...i.turn.toolCalls,
        ];
        final raw = Verifier.verify(
          answer: bad,
          question: q0,
          today: DayKey.of(kEvalNow),
          calls: calls,
          results: last.results,
        );
        rawClaims += raw.verification.checkedNumbers;
        rawUnsupported += raw.claims.where((c) => !c.supported).length;
        // Caught = the service ran the repair round for it.
        final repaired = llm.requests.any((q) => q.isRepair);
        if (repaired) {
          caught++;
        } else {
          failures.add('$mode ${r['id']} not caught: $bad');
        }
        if (m.verification?.verified ?? false) finalVerified++;
        if (!m.text.contains('swam 1.5 km') && m.text != bad) finalClean++;
      }
    }
    final out = [
      EvalRow('hallucinations caught by the verifier', caught, cases, 1.0),
      EvalRow('final answers verified', finalVerified, cases, 1.0),
      EvalRow('hallucinated text never shown', finalClean, cases, 1.0),
      // Informational: how often a claim in a fake's first answer was
      // unsupported (no gate: the gate is the post-repair 0%).
      EvalRow('raw pre-repair unsupported claims (info)', rawUnsupported,
          rawClaims, 1.0, higherIsBetter: false),
    ];
    report('grounding_hallucination', out, failures: failures);
    for (final row in out) {
      expect(row.ok, isTrue, reason: row.line);
    }
  });

  test('documented competitor failures are caught', () async {
    // (question, tool calls the fake makes, the fake's answer)
    final cases = <(String, String, List<ToolCall>, String)>[
      ('invented swim', 'What did I do on Sunday?', [
        const ToolCall(id: 'a', name: 'get_workouts',
            input: {'from': '2026-09-27', 'to': '2026-09-27'}),
      ], 'You had a great swim on Sun 27 Sep.'),
      ('5 am run', 'What did I do yesterday morning?', [
        const ToolCall(id: 'a', name: 'get_workouts',
            input: {'from': '2026-09-28', 'to': '2026-09-28'}),
      ], 'You went for a run at 5 am on Mon 28 Sep.'),
      ('band-off hours as sleep', 'Did I nap on Wed 23 Sep?', [
        const ToolCall(id: 'a', name: 'get_data_coverage',
            input: {'from': '2026-09-23', 'to': '2026-09-23'}),
      ], 'You napped from 13:00 to 14:55 on Wed 23 Sep.'),
      ('sleep on a night with no data', 'How did I sleep on Mon 1 Jun?', [
        const ToolCall(id: 'a', name: 'get_sleep',
            input: {'from': '2026-06-01', 'to': '2026-06-01'}),
      ], 'You slept 7h 30m on the night before Mon 1 Jun.'),
      ('made-up workout', 'How was my yoga class on Sat 26 Sep?', [
        const ToolCall(id: 'a', name: 'get_workouts',
            input: {'from': '2026-09-26', 'to': '2026-09-26'}),
      ], 'Your yoga class on Sat 26 Sep lasted 60 min.'),
      ('cruise', 'Why was my sleep off last week?', [
        const ToolCall(id: 'a', name: 'get_sleep',
            input: {'from': '2026-09-22', 'to': '2026-09-28'}),
      ], 'Your sleep was off because you were on a cruise.'),
      ('wrong recovery', 'What is my recovery today?', [
        const ToolCall(id: 'a', name: 'get_today_summary', input: {}),
      ], 'Your recovery today is 92% [r1].'),
      ('missing as zero', 'How many steps on Mon 1 Jun?', [
        const ToolCall(id: 'a', name: 'get_day', input: {'date': '2026-06-01'}),
      ], 'You took 0 steps on Mon 1 Jun.'),
      ('invented illness', 'Why is my HRV different today?', [
        const ToolCall(id: 'a', name: 'get_today_summary', input: {}),
      ], 'Your HRV changed because you were sick with a fever.'),
    ];
    var caught = 0, safe = 0;
    final failures = <String>[];
    for (final (name, q, calls, bad) in cases) {
      final llm = ScriptedLlm((req, turn) {
        if (req.isRepair) return LlmTurn(text: bad);
        if (turn == 0) return LlmTurn(toolCalls: calls, stopReason: 'tool_use');
        return LlmTurn(text: bad);
      });
      final m = await Bench.cloud(llm).ask(q);
      final repaired = llm.requests.any((r) => r.isRepair);
      if (repaired) {
        caught++;
      } else {
        failures.add('$name not caught');
      }
      if ((m.verification?.verified ?? false) &&
          (m.text.startsWith(CoachPrompts.fallbackNote) ||
              m.text.startsWith(CoachPrompts.noFactsNote))) {
        safe++;
      } else {
        failures.add('$name final: ${m.text}');
      }
    }
    final out = [
      EvalRow('documented failures caught', caught, cases.length, 1.0),
      EvalRow('replaced by the verified facts table', safe, cases.length, 1.0),
    ];
    report('grounding_documented', out, failures: failures);
    for (final row in out) {
      expect(row.ok, isTrue, reason: row.line);
    }
  });
}
