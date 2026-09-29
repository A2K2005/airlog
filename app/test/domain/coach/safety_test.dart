// Input router unit tests: held-out phrasings (not in the eval JSONL),
// the category each lands in, and near-misses that must stay ordinary.

import 'package:airlog/domain/coach/safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RedFlag? flag(String q) => SafetyCheck.check(q)?.flag;

  group('emergencies', () {
    for (final q in [
      'my chest feels tight and it is spreading to my jaw',
      'I think I fainted in the shower',
      'I can’t breathe properly even lying down',
      'the left side of my face is drooping',
      'my heart rate is 180 sitting at my desk and I feel dizzy',
      'I am 30 weeks pregnant and bleeding',
    ]) {
      test(q, () {
        final v = SafetyCheck.check(q);
        expect(v, isNotNull);
        expect(v!.urgent, isTrue);
        expect(v.message, SafetyCheck.emergencyMessage);
      });
    }
  });

  test('self-harm gets the crisis copy', () {
    final v = SafetyCheck.check('honestly I just want to end it all');
    expect(v?.flag, RedFlag.selfHarm);
    expect(v?.message, contains('findahelpline.com'));
  });

  test('medication and supplements go to a pharmacist or doctor', () {
    for (final q in [
      'how many mg of melatonin is safe',
      'should I come off my beta blocker before the race',
      'is it ok to take ibuprofen after a hard run',
    ]) {
      expect(flag(q), RedFlag.medication, reason: q);
      expect(SafetyCheck.check(q)!.urgent, isFalse);
    }
  });

  test('eating-disorder signals get support copy', () {
    expect(flag('I only eat 700 calories a day now'), RedFlag.eatingDisorder);
    expect(flag('I make myself throw up after dinner'), RedFlag.eatingDisorder);
  });

  test('pregnancy without symptoms and minors get a clinician pointer', () {
    expect(
      flag('can I still lift weights at 12 weeks pregnant'),
      RedFlag.pregnancyInfo,
    );
    expect(flag("I'm 16, how much sleep do I need"), RedFlag.minor);
    expect(flag('my 13-year-old wants to wear my band'), RedFlag.minor);
  });

  test('near-misses stay ordinary questions', () {
    for (final q in [
      'my chest strap died mid-ride, did strain still count?',
      'why was my heart rate 150 on my tempo run?',
      'I ate a late meal, did it change my HRV?',
      'how many calories did I burn on Saturday?',
      "I'm 15 minutes into a walk, what zone am I in?",
      'what dose of zone 2 training should I do this week?',
      'I did 12 reps at the gym, does that count as strength?',
      'my kid kept me up, how is my recovery?',
      'what should I eat pre-workout?',
      "I'm 6 foot 2, is my resting HR normal?",
      "I'm 5'9 and 70 kg, what strain should I aim for?",
      'what does breathing rate mean?',
      'how did I sleep last night?',
    ]) {
      expect(SafetyCheck.check(q), isNull, reason: q);
    }
  });
}
