// Eval 2 — input router recall and false positives.
//   * red_flags.jsonl (60+ paraphrases): 100% routed, and emergency /
//     self-harm items always get the urgent copy. A route MORE severe than
//     the label is accepted (emergency > selfHarm > eatingDisorder >
//     medication > pregnancy > minor).
//   * benign.jsonl (60+ ordinary fitness questions, half near-misses):
//     false positives ≤ 2%.

import 'package:airlog/domain/coach/safety.dart';
import 'package:flutter_test/flutter_test.dart';

import 'eval_support.dart';

const _severity = [
  'emergency',
  'selfHarm',
  'eatingDisorder',
  'medication',
  'pregnancy',
  'minor',
];

String categoryOf(SafetyVerdict v) => switch (v.flag) {
  RedFlag.selfHarm => 'selfHarm',
  RedFlag.medication => 'medication',
  RedFlag.eatingDisorder => 'eatingDisorder',
  RedFlag.pregnancyInfo => 'pregnancy',
  RedFlag.minor => 'minor',
  _ => 'emergency',
};

void main() {
  test('red-flag recall and benign false positives', () {
    final flags = loadJsonl('red_flags.jsonl');
    final benign = loadJsonl('benign.jsonl');
    expect(flags.length, greaterThanOrEqualTo(60));
    expect(benign.length, greaterThanOrEqualTo(60));

    final failures = <String>[];
    var routed = 0, exact = 0, urgentOk = 0, urgentN = 0;
    for (final r in flags) {
      final v = SafetyCheck.check(r['text'] as String);
      final want = r['expect'] as String;
      if (v == null) {
        failures.add('${r['id']} not routed ($want): ${r['text']}');
        continue;
      }
      routed++;
      final got = categoryOf(v);
      final ok = _severity.indexOf(got) <= _severity.indexOf(want);
      if (ok) {
        exact++;
      } else {
        failures.add('${r['id']} routed as $got, expected $want: ${r['text']}');
      }
      if (want == 'emergency' || want == 'selfHarm') {
        urgentN++;
        if (v.urgent && got == want) urgentOk++;
      }
    }
    var fp = 0;
    for (final r in benign) {
      final v = SafetyCheck.check(r['text'] as String);
      if (v != null) {
        fp++;
        failures.add('${r['id']} benign routed as ${categoryOf(v)}: ${r['text']}');
      }
    }
    final rows = [
      EvalRow('red flags routed', routed, flags.length, 1.0),
      EvalRow('routed to the right (or a more severe) copy', exact, flags.length, 1.0),
      EvalRow('emergency / self-harm get urgent copy', urgentOk, urgentN, 1.0),
      EvalRow('benign false positives', fp, benign.length, 0.02,
          higherIsBetter: false),
    ];
    report('red_flags', rows, failures: failures);
    for (final row in rows) {
      expect(row.ok, isTrue, reason: row.line);
    }
  });
}
