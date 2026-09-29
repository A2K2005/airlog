// Eval 7 — the on-device intent router (data/coach/offline_client.dart).
// offline_router.jsonl: 30+ questions, each with the tool the router must
// pick first and the arguments it must pass (a subset match). Every answer
// must then be grounded: verified by the real verifier with no repair.

import 'package:airlog/data/coach/offline_client.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/tools.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coach_harness.dart';
import 'eval_support.dart';

void main() {
  test('offline intent router: right tool, right window, grounded answer',
      () async {
    final rows = loadJsonl('offline_router.jsonl');
    expect(rows.length, greaterThanOrEqualTo(30));
    final bench = Bench.offline();
    final ctx = OfflineContext(
      today: DayKey.of(kEvalNow),
      latest: await bench.health.latestDate(),
    );
    final tools = {
      for (final t in CoachTools.forMode(CoachMode.useMyData, memory: true))
        t.name,
    };
    var toolOk = 0, argsOk = 0, grounded = 0;
    final failures = <String>[];
    for (final r in rows) {
      final plan = OfflineRouter.route(r['q'] as String, ctx, tools);
      final first = plan.calls.isEmpty ? null : plan.calls.first;
      if (first?.name == r['tool']) {
        toolOk++;
      } else {
        failures.add('${r['id']} "${r['q']}": ${first?.name} ≠ ${r['tool']}');
      }
      final want = (r['args'] as Map).cast<String, dynamic>();
      final ok = first != null &&
          want.entries.every((e) => first.input[e.key] == e.value);
      if (ok) {
        argsOk++;
      } else {
        failures.add('${r['id']} args ${first?.input} ⊉ $want');
      }
      final m = await bench.ask(r['q'] as String);
      if ((m.verification?.verified ?? false) &&
          !(m.verification?.repaired ?? true) &&
          m.error == null) {
        grounded++;
      } else {
        failures.add('${r['id']} not grounded: ${m.text}');
      }
    }
    final out = [
      EvalRow('right tool chosen', toolOk, rows.length, 1.0),
      EvalRow('right arguments (date window, metric, topic)', argsOk,
          rows.length, 1.0),
      EvalRow('grounded answers (verified, no repair)', grounded, rows.length,
          1.0),
    ];
    report('offline_router', out, failures: failures);
    for (final row in out) {
      expect(row.ok, isTrue, reason: row.line);
    }
  });
}
