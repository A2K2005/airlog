// Output policy unit tests (domain/coach/policy.dart).

import 'package:airlog/domain/coach/policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Set<PolicyKind> kinds(String t) => OutputPolicy.check(t).kinds;

  test('diagnosis language is rejected', () {
    for (final t in [
      'You have AFib.',
      'This looks like obstructive sleep apnea.',
      'You are sick.',
      'Your HRV drop points to a viral infection [r2].',
      "It's probably the flu.",
    ]) {
      expect(kinds(t), contains(PolicyKind.diagnosis), reason: t);
    }
  });

  test('dosing and medication instructions are rejected', () {
    for (final t in [
      'Take 400 mg of ibuprofen.',
      'Stop your meds for a few days.',
      'You should try melatonin tonight.',
      'Double your beta blocker before the race.',
    ]) {
      expect(kinds(t), contains(PolicyKind.dosing), reason: t);
    }
  });

  test('certainty about illness is rejected', () {
    expect(
      kinds('This definitely means you are getting sick.'),
      contains(PolicyKind.certainty),
    );
    expect(
      kinds('There is no doubt this is an infection.'),
      contains(PolicyKind.certainty),
    );
  });

  test('shaming and weight-loss pressure are rejected', () {
    for (final t in [
      'That was lazy.',
      'You need to lose weight.',
      'Burn off that pizza with an extra run.',
      'Cut down to 1,200 calories a day.',
    ]) {
      expect(kinds(t), contains(PolicyKind.shaming), reason: t);
    }
  });

  test('negated, conditional and pointer sentences pass', () {
    for (final t in [
      'Out-of-range values can follow training, alcohol, heat or illness. '
          'This is not a diagnosis; if you feel unwell, talk to a doctor.',
      "It doesn't mean you're sick.",
      "I can't give medication or dosing advice; a pharmacist can help.",
      "Don't stop or change your medication without your doctor.",
      'There is no need to feel guilty about a rest day.',
      'You definitely slept longer on Saturday [r3].',
      'Your recovery is 34% [r1], in the red zone.',
      'Consistency (5 of 7 nights met your sleep need).',
    ]) {
      expect(
        OutputPolicy.check(t).ok,
        isTrue,
        reason:
            '$t → ${OutputPolicy.check(t).violations.map((v) => v.describe)}',
      );
    }
  });

  test('every kind has repair guidance', () {
    for (final k in PolicyKind.values) {
      expect(OutputPolicy.fix(k), isNotEmpty);
    }
  });
}
