// What an answer's cards may show: pictures of its cited numbers
// (AnswerVisuals), today's plan actions (AnswerActions), the chat's topic
// (ChatTopics) and the tools it records (CoachServiceImpl.toolNames). Every
// number comes from the answer's own tool results; nothing is computed.

import 'package:airlog/domain/coach/answer_actions.dart';
import 'package:airlog/domain/coach/answer_visuals.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/coach_service.dart';
import 'package:airlog/domain/coach/topics.dart';
import 'package:airlog/domain/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _f(num v, String unit, String ref) => {
  'value': v,
  'unit': unit,
  'ref': ref,
};

SourceRef _r(String id, String label, double v, String unit, [String? d]) =>
    SourceRef(id: id, label: label, value: v, unit: unit, date: d);

final _range = ToolResult(
  callId: 'c1',
  name: 'get_range',
  content: {
    'metric': 'hrv',
    'from': '2026-09-23',
    'to': '2026-09-28',
    'noDataDates': ['2026-09-25'],
    'mean': _f(50, 'ms', 'r1'),
    'baseline': {'asOf': '2026-09-28', 'mean': _f(55, 'ms', 'r2')},
    'daily': [
      {'date': '2026-09-23', 'hrv': _f(48, 'ms', 'r3')},
      {'date': '2026-09-24', 'hrv': _f(51, 'ms', 'r4')},
      {'date': '2026-09-26', 'hrv': _f(47, 'ms', 'r5')},
      {'date': '2026-09-27', 'hrv': _f(53, 'ms', 'r6')},
      {'date': '2026-09-28', 'hrv': _f(52, 'ms', 'r7')},
    ],
  },
);

final _vitals = ToolResult(
  callId: 'c2',
  name: 'get_health_monitor',
  content: {
    'date': '2026-09-28',
    'metrics': [
      {
        'metric': 'Resting HR',
        'state': 'above range',
        'value': _f(61, 'bpm', 'r8'),
        'baseline': _f(54, 'bpm', 'r9'),
        'rangeLow': _f(50, 'bpm', 'r10'),
        'rangeHigh': _f(58, 'bpm', 'r11'),
      },
    ],
  },
);

final _today = ToolResult(
  callId: 'c3',
  name: 'get_today_summary',
  content: {
    'date': '2026-09-28',
    'recovery': {
      'score': _f(64, '%', 'r12'),
      'drivers': [
        {
          'input': 'HRV',
          'value': _f(52, 'ms', 'r13'),
          'baseline': _f(58, 'ms', 'r14'),
          'vsBaseline': _f(-10, '%', 'r15'),
        },
      ],
    },
    'strain': {'value': _f(9.4, 'strain', 'r16')},
  },
);

void main() {
  group('AnswerVisuals', () {
    test('a trend from the answer\'s own range; missing days stay null, '
        'never zero', () {
      final v = AnswerVisuals.build(
        [_range],
        [_r('r7', 'HRV · Mon 28 Sep', 52, 'ms', '2026-09-28')],
      ).single;
      expect(v.metric, 'hrv');
      expect(v.series.map((p) => p.date), [
        '2026-09-23',
        '2026-09-24',
        '2026-09-25',
        '2026-09-26',
        '2026-09-27',
        '2026-09-28',
      ]);
      expect(v.series.map((p) => p.value), [48, 51, null, 47, 53, 52]);
      expect(v.usual, 55);
    });

    test('the Health Monitor gives the usual range and its state', () {
      final v = AnswerVisuals.build(
        [_vitals],
        [_r('r8', 'Resting HR · Mon 28 Sep', 61, 'bpm', '2026-09-28')],
      ).single;
      expect(v.metric, 'resting_hr');
      expect((v.usualLow, v.usualHigh), (50, 58));
      expect(v.state, 'above range');
      expect(v.series, isEmpty);
    });

    test('a single-day answer gets the usual and the tool\'s own '
        '"vs usual", no trend', () {
      final out = AnswerVisuals.build(
        [_today],
        [
          _r('r12', 'Recovery · Mon 28 Sep', 64, '%', '2026-09-28'),
          _r('r13', 'HRV · Mon 28 Sep', 52, 'ms', '2026-09-28'),
        ],
      );
      expect(out.map((v) => v.metric), ['recovery', 'hrv']);
      expect(out[0].usual, isNull);
      expect(out[1].usual, 58);
      expect(out[1].vsUsualPct, -10);
      expect(out.every((v) => v.series.isEmpty), isTrue);
    });

    test('non-headline refs get no picture; one per metric; at most 3', () {
      expect(
        AnswerVisuals.build(
          [_today],
          [_r('r15', 'HRV vs baseline', -10, '%')],
        ),
        isEmpty,
      );
      expect(
        AnswerVisuals.build(
          [_range],
          [
            _r('r7', 'HRV', 52, 'ms'),
            _r('r6', 'HRV', 53, 'ms'),
          ],
        ),
        hasLength(1),
      );
      expect(
        AnswerVisuals.build(
          [_today, _range, _vitals],
          [
            _r('r12', 'Recovery', 64, '%'),
            _r('r7', 'HRV', 52, 'ms'),
            _r('r8', 'Resting HR', 61, 'bpm'),
            _r('r16', 'Strain', 9.4, 'strain'),
          ],
        ),
        hasLength(AnswerVisuals.maxVisuals),
      );
    });

    test('an uncited ref never gets a card', () {
      expect(AnswerVisuals.build([_range, _vitals], const []), isEmpty);
    });
  });

  group('ChatTopics', () {
    ChatMessage a(List<String> tools, {List<SourceRef> refs = const []}) =>
        ChatMessage(
          id: 'a${tools.length}',
          conversationId: 'c',
          role: ChatRole.assistant,
          text: 'x',
          at: DateTime(2026, 9, 28),
          tools: tools,
          refs: refs,
        );

    test('from the tools, never a guess; a day summary only when nothing '
        'more specific was called', () {
      expect(ChatTopics.ofAnswer(a(['get_sleep'])), ChatTopic.sleep);
      expect(
        ChatTopics.ofAnswer(a(['get_today_summary', 'get_journal_insights'])),
        ChatTopic.journal,
      );
      expect(
        ChatTopics.ofAnswer(a(['get_today_summary'])),
        ChatTopic.recovery,
      );
      expect(ChatTopics.ofAnswer(a(['get_range:strain'])), ChatTopic.training);
      expect(
        ChatTopics.ofAnswer(a(['get_range:sleep_duration'])),
        ChatTopic.sleep,
      );
      expect(ChatTopics.ofAnswer(a(['get_methodology'])), isNull);
    });

    test('"Does alcohol affect my recovery?" on the cloud lands in Journal: '
        'the app\'s own context reads are not the answer\'s tools', () {
      final tools = CoachServiceImpl.toolNames(const [
        ToolCall(id: 'context_memory', name: 'get_memories', input: {}),
        ToolCall(id: 'context_today', name: 'get_today_summary', input: {}),
        ToolCall(
          id: 'context_trend',
          name: 'get_range',
          input: {'metric': 'recovery'},
        ),
        ToolCall(id: 'context_journal', name: 'get_journal_insights', input: {}),
        ToolCall(id: 'toolu_1', name: 'get_journal_insights', input: {}),
      ]);
      expect(tools, ['get_journal_insights']);
      expect(
        ChatTopics.ofConversation([a(tools)]),
        ChatTopic.journal,
      );
    });

    test('a conversation: the most frequent answer topic; a tie goes to '
        'the earlier answer; nothing is General', () {
      expect(
        ChatTopics.ofConversation([
          a(['get_sleep']),
          a(['get_workouts']),
        ]),
        ChatTopic.sleep,
      );
      expect(
        ChatTopics.ofConversation([
          a(['get_sleep']),
          a(['get_workouts']),
          a(['get_training_load']),
        ]),
        ChatTopic.training,
      );
      expect(ChatTopics.ofConversation(const []), ChatTopic.general);
    });

    test('older answers without tools: the cloud list, then source routes', () {
      final old = a(
        const [],
        refs: const [
          SourceRef(id: 'r1', label: 'Sleep', value: 400, route: '/sleep'),
        ],
      );
      expect(ChatTopics.ofAnswer(old), ChatTopic.sleep);
    });
  });

  group('AnswerActions', () {
    const plan = TodayPlan(
      date: '2026-09-28',
      state: DayState.easy,
      headline: 'Take it easy today',
      summary: 'Your HRV is below your usual.',
      actions: [
        PlanAction(
          kind: PlanActionKind.effort,
          title: 'Keep effort light: strain 6–9',
          why: 'Recovery is 64%.',
          evidence: [PlanEvidence(label: 'Goal', value: '6–9')],
          route: '/strain',
        ),
        PlanAction(
          kind: PlanActionKind.sleep,
          title: 'Get to bed by 23:35',
          why: 'Your sleep goal is 7h 50m.',
          evidence: [PlanEvidence(label: 'Sleep goal', value: '7h 50m')],
          route: '/sleep',
        ),
      ],
    );

    test('the plan\'s own words, picked by topic', () {
      final sleep = AnswerActions.fromPlan(plan, ChatTopic.sleep).single;
      expect(sleep.title, 'Get to bed by 23:35');
      expect(sleep.meta, 'Sleep goal 7h 50m');
      expect(sleep.kind, 'sleep');
      expect(sleep.date, '2026-09-28');
      expect(
        AnswerActions.fromPlan(plan, ChatTopic.training).single.title,
        'Keep effort light: strain 6–9',
      );
      expect(AnswerActions.fromPlan(plan, ChatTopic.journal), isEmpty);
      expect(AnswerActions.fromPlan(plan, ChatTopic.general), isEmpty);
    });

    test('none when the plan is behind, learning or empty', () {
      for (final p in [
        const TodayPlan(
          date: '2026-09-28',
          state: DayState.easy,
          headline: 'h',
          summary: 's',
          stale: true,
          actions: [
            PlanAction(kind: PlanActionKind.sleep, title: 't', why: 'w'),
          ],
        ),
        const TodayPlan(
          date: '2026-09-28',
          state: DayState.calibrating,
          headline: 'h',
          summary: 's',
          actions: [
            PlanAction(kind: PlanActionKind.sleep, title: 't', why: 'w'),
          ],
        ),
      ]) {
        expect(AnswerActions.fromPlan(p, ChatTopic.sleep), isEmpty);
      }
    });
  });
}
