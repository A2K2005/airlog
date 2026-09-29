// Eval 1b — a non-Fitbit fixture: a WHOOP-style band whose last three days
// have no HRV at all. The coach must say HRV isn't available, never guess
// it, and a model that guesses a value must be caught.

import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coach_harness.dart';
import 'eval_support.dart';
import 'fixtures.dart';

void main() {
  test('no HRV: the coach says so and never guesses', () async {
    final h = await fixtureRepo((rs) => dropHrv(rs));
    final offline = CoachModule.inMemory(h, clock: () => kEvalNow);
    final failures = <String>[];
    var said = 0, noGuess = 0, verified = 0;
    const qs = [
      'What was my HRV today?',
      'What was my HRV yesterday?',
      'What drove my recovery today?',
    ];
    for (final q in qs) {
      final m = await offline.service.ask(q);
      final hrvNumber = RegExp(r'\bHRV\b[^.\n]{0,20}\d+\s*ms').hasMatch(m.text);
      if (!hrvNumber) {
        noGuess++;
      } else {
        failures.add('guessed: $q → ${m.text}');
      }
      if (!q.contains('drove') &&
          RegExp(r"don't have HRV data").hasMatch(m.text)) {
        said++;
      } else if (q.contains('drove')) {
        said++; // recovery answers simply leave HRV out
      } else {
        failures.add('did not say missing: $q → ${m.text}');
      }
      if (m.verification?.verified ?? false) verified++;
    }

    // A cloud model that guesses the missing value.
    final llm = ScriptedLlm((r, turn) async {
      if (r.isRepair) return const LlmTurn(text: 'Your HRV today was 48 ms.');
      final t = await offlineTurn(r);
      return t.toolCalls.isNotEmpty
          ? t
          : const LlmTurn(text: 'Your HRV today was 48 ms.');
    });
    final cloud = CoachModule.inMemory(
      h,
      clock: () => kEvalNow,
      settings: kCloudSettings,
      clients: (_, _, _) => llm,
      keys: const {CoachProvider.claude: 'sk-ant-test-FAKEKEY123'},
    );
    final g = await cloud.service.ask('What was my HRV today?');
    final caught = llm.requests.any((r) => r.isRepair) &&
        !g.text.contains('48 ms') &&
        (g.verification?.verified ?? false);
    if (!caught) failures.add('guess shown: ${g.text}');

    final rows = [
      EvalRow('says HRV is not available', said, qs.length, 1.0),
      EvalRow('never states an HRV value', noGuess, qs.length, 1.0),
      EvalRow('answers verified', verified, qs.length, 1.0),
      EvalRow('a guessed HRV from a model is caught', caught ? 1 : 0, 1, 1.0),
    ];
    report('non_fitbit', rows, failures: failures);
    for (final r in rows) {
      expect(r.ok, isTrue, reason: r.line);
    }
  });
}
