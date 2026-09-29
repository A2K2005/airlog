// Verifier unit tests: what counts as evidence and what doesn't.

import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/verifier.dart';
import 'package:flutter_test/flutter_test.dart';

const today = '2026-09-29';

ToolResult result(Map<String, dynamic> content, List<SourceRef> refs) =>
    ToolResult(callId: 'c', name: 'get_day', content: content, refs: refs);

const rec = SourceRef(
  id: 'r1',
  label: 'Recovery · Tue 29 Sep',
  value: 70,
  unit: '%',
  date: today,
);
const hrv = SourceRef(
  id: 'r2',
  label: 'HRV · Tue 29 Sep',
  value: 51,
  unit: 'ms',
  date: today,
);

VerificationReport v(
  String answer, {
  List<ToolResult>? results,
  String question = 'q',
  List<String> memories = const [],
}) => Verifier.verify(
  answer: answer,
  question: question,
  today: today,
  calls: const [
    ToolCall(id: 'c', name: 'get_day', input: {'date': today}),
  ],
  results:
      results ??
      [
        result({'date': today}, const [rec, hrv]),
      ],
  memories: memories,
);

void main() {
  test('cited numbers must match their ref', () {
    expect(v('Recovery 70% [r1], HRV 51 ms [r2].').verified, isTrue);
    expect(v('Recovery 72% [r1].').verified, isFalse);
    expect(v('Recovery 70% [r9].').verified, isFalse);
  });

  test('numbers inside quoted text are never evidence', () {
    final r = result(
      {
        'date': today,
        'workouts': [
          {
            'workout': {'quoted': 'Recovery 99% run'},
            'date': today,
          },
        ],
      },
      const [rec],
    );
    expect(v('Your recovery is 99%.', results: [r]).verified, isFalse);
  });

  test('display strings are not separate evidence', () {
    final r = result(
      {
        'total': {
          'value': 329,
          'unit': 'min',
          'display': '5h 29m',
          'ref': 'r1',
        },
      },
      const [
        SourceRef(
          id: 'r1',
          label: 'Workouts · total time',
          value: 329,
          unit: 'min',
        ),
      ],
    );
    expect(v('Your HRV was 5 ms.', results: [r]).verified, isFalse);
    expect(
      v('You trained 5h 29m [r1] in total.', results: [r]).verified,
      isTrue,
    );
  });

  test('memory numbers never ground a measured metric', () {
    const mem = ['My recovery is always 99% on rest days'];
    expect(v('Your recovery is 99%.', memories: mem).verified, isFalse);
    expect(
      v(
        'Your half marathon is on 15 Nov.',
        memories: const ['Half marathon on 15 Nov'],
      ).verified,
      isTrue,
    );
  });

  test('numbers the user asked about are fine', () {
    expect(
      v(
        'Not 85% — your recovery is 70% [r1].',
        question: 'Is it 85%?',
      ).verified,
      isTrue,
    );
  });

  test('a weekday that does not match the date is caught', () {
    expect(v('On Mon 29 Sep your recovery was 70% [r1].').verified, isFalse);
  });

  test('events need a record; negations and advice are not claims', () {
    expect(v('You went for a swim today.').verified, isFalse);
    expect(v('No swim is recorded today.').verified, isTrue);
    expect(v('An easy walk could help today.').verified, isTrue);
  });
}
