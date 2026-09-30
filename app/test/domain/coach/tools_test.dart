// Tool executor: argument validation, window clamping, quoted data, the
// card seed, the mode and memory gates.

import 'dart:convert';

import 'package:airlog/data/coach/in_memory_coach_repository.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/quoted.dart';
import 'package:airlog/domain/coach/tools.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 29, 9);

CoachToolbox box({
  CoachMode mode = CoachMode.useMyData,
  bool memory = true,
  AskContext? seed,
  InMemoryCoachRepository? coach,
  String? question,
}) => CoachToolbox(
  health: InMemoryHealthRepository.demo(now: now),
  coach: coach ?? InMemoryCoachRepository(clock: () => now),
  now: now,
  cloud: false,
  mode: mode,
  memoryEnabled: memory,
  seed: seed,
  question: question,
);

Future<ToolResult> one(
  CoachToolbox b,
  String name,
  Map<String, dynamic> input,
) async => (await b.run([ToolCall(id: 'x', name: name, input: input)])).single;

void main() {
  test('every spec is strict-compatible', () {
    for (final t in [...CoachTools.all, CoachTools.insightCardSpec]) {
      expect(t.inputSchema['type'], 'object');
      expect(t.inputSchema['additionalProperties'], false);
      expect(t.inputSchema['required'], isA<List<dynamic>>());
    }
  });

  test('arguments are validated against the schema', () async {
    final b = box();
    expect(
      (await one(b, 'get_day', {'date': '2026-09-28', 'evil': 1})).isError,
      isTrue,
    );
    expect((await one(b, 'get_day', {})).isError, isTrue);
    expect((await one(b, 'get_day', {'date': 42})).isError, isTrue);
    expect(
      (await one(b, 'get_range', {
        'metric': 'mood',
        'from': '2026-09-01',
        'to': '2026-09-02',
      })).isError,
      isTrue,
    );
    expect((await one(b, 'get_day', {'date': '2026-09-31'})).isError, isTrue);
    expect((await one(b, 'no_such_tool', {})).isError, isTrue);
  });

  test('windows are clamped to 90 days and never past today', () async {
    final r = await one(box(), 'get_range', {
      'metric': 'hrv',
      'from': '1990-01-01',
      'to': '2030-01-01',
    });
    expect(r.isError, isFalse);
    expect(r.content['to'], '2026-09-29');
    expect(r.content['daysInWindow'], 90);
    expect(jsonEncode(r.content), contains('capped at 90 days'));
    expect(
      (await one(box(), 'get_day', {'date': '2026-10-02'})).isError,
      isTrue,
    );
  });

  test('workout titles go out as quoted data with a notice', () async {
    final r = await one(box(), 'get_workouts', {
      'from': '2026-09-23',
      'to': '2026-09-29',
    });
    final ws = r.content['workouts'] as List;
    expect(ws, isNotEmpty);
    expect(QuotedText.isQuoted((ws.first as Map)['workout']), isTrue);
    expect(r.content[QuotedText.noticeKey], QuotedText.notice);
  });

  test(
    'general-only mode refuses data tools; methodology still works',
    () async {
      final b = box(mode: CoachMode.generalOnly);
      expect((await one(b, 'get_today_summary', {})).isError, isTrue);
      expect(
        (await one(b, 'get_methodology', {'topic': 'hrv'})).isError,
        isFalse,
      );
      expect(
        CoachTools.forMode(
          CoachMode.generalOnly,
          memory: true,
        ).map((t) => t.name),
        ['get_methodology'],
      );
      // The card seed goes in the user message, never as an offered tool.
      expect(
        CoachTools.forMode(
          CoachMode.useMyData,
          memory: true,
        ).map((t) => t.name),
        isNot(contains(CoachTools.insightCard)),
      );
    },
  );

  test('memory off: no memory tools, and they refuse if called', () async {
    expect(
      CoachTools.forMode(CoachMode.useMyData, memory: false).map((t) => t.name),
      isNot(contains('get_memories')),
    );
    final b = box(memory: false);
    expect((await one(b, 'get_memories', {})).isError, isTrue);
    expect(
      (await one(b, 'propose_memory', {
        'text': 'x',
        'category': 'goals',
      })).isError,
      isTrue,
    );
  });

  test('propose_memory saves nothing and refuses health numbers', () async {
    final coach = InMemoryCoachRepository(clock: () => now);
    // PR #1: every proposal, not only health history and mood, must be
    // stated by the user in this message; the question states the goal.
    final b = box(
      coach: coach,
      question: "I'm training for a half marathon on 15 Nov. How am I doing?",
    );
    final ok = await one(b, 'propose_memory', {
      'text': 'Training for a half marathon on 15 Nov',
      'category': 'goals',
    });
    expect(ok.content['status'], 'pending user confirmation');
    expect(b.proposals, hasLength(1));
    expect(await coach.memories(), isEmpty);
    final bad = await one(b, 'propose_memory', {
      'text': 'My resting heart rate is 48 bpm',
      'category': 'healthHistory',
    });
    expect(bad.isError, isTrue);
  });

  test('health history and mood proposals must be user-stated', () async {
    final b = box(question: 'I had knee surgery in March, how is my recovery?');
    final ok = await one(b, 'propose_memory', {
      'text': 'Had knee surgery in March',
      'category': 'healthHistory',
    });
    expect(ok.isError, isFalse);
    expect(ok.content['needsExplicitConfirm'], isTrue);
    final inferred = await one(b, 'propose_memory', {
      'text': 'Probably has sleep apnea',
      'category': 'healthHistory',
    });
    expect(inferred.isError, isTrue);
    final mood = await one(
      box(question: 'How did I sleep?'),
      'propose_memory',
      {'text': 'Feeling anxious lately', 'category': 'mood'},
    );
    expect(mood.isError, isTrue);
  });

  test('the card seed carries its facts as quoted data', () async {
    const seed = AskContext(
      screen: 'sleep',
      date: '2026-09-29',
      seedText: 'A solid night',
      seedRefs: [
        SourceRef(
          id: 'r1',
          label: 'Asleep · Tue 29 Sep',
          value: 403,
          unit: 'min',
          date: '2026-09-29',
        ),
      ],
    );
    final r = await one(box(seed: seed), CoachTools.insightCard, {});
    expect(r.refs.single.value, 403);
    expect(QuotedText.isQuoted((r.content['card'] as Map)['text']), isTrue);
    expect(
      (await one(box(), CoachTools.insightCard, {})).isError,
      isTrue,
      reason: 'no seed, no card tool',
    );
  });
}
