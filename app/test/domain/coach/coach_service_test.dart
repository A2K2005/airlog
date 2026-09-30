// CoachServiceImpl: the gates, limits and flows around the model.

import 'dart:async';

import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/coach_service.dart';
import 'package:airlog/domain/coach/prompts.dart';
import 'package:airlog/domain/coach/safety.dart';
import 'package:airlog/domain/coach/tools.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 29, 9);

final cloudSettings = CoachSettings(
  provider: CoachProvider.claude,
  consentAt: DateTime(2026, 9, 1),
  consentVersion: kCoachConsentVersion,
  adultConfirmed: true,
);

class Fake implements LlmClient {
  Fake(this.onNext);
  final FutureOr<LlmTurn> Function(List<LlmItem> t, List<CoachToolSpec> tools)
  onNext;
  final transcripts = <List<LlmItem>>[];
  @override
  CoachProvider get provider => CoachProvider.claude;
  @override
  String get model => 'fake';
  @override
  Future<LlmTurn> next({
    required String system,
    required List<LlmItem> transcript,
    required List<CoachToolSpec> tools,
    required ResponseLength length,
  }) async {
    transcripts.add(List.of(transcript));
    return onNext(transcript, tools);
  }
}

CoachModule module(Fake f, {CoachSettings? settings}) => CoachModule.inMemory(
  InMemoryHealthRepository.demo(now: now),
  clock: () => now,
  settings: settings ?? cloudSettings,
  clients: (_, _, _) => f,
  keys: const {CoachProvider.claude: 'sk-ant-test-FAKEKEY123'},
);

void main() {
  test('a red flag gets fixed copy with no model call', () async {
    final f = Fake((_, _) => throw StateError('no call expected'));
    final m = await module(f).service.ask('I have crushing chest pain');
    expect(m.safety, isTrue);
    expect(m.text, SafetyCheck.emergencyMessage);
    expect(f.transcripts, isEmpty);
  });

  test('cloud needs consent, a current version and 18+', () async {
    final f = Fake((_, _) => const LlmTurn(text: 'x'));
    for (final s in [
      cloudSettings.copyWith(clearConsent: true),
      cloudSettings.copyWith(adultConfirmed: false),
    ]) {
      await expectLater(
        module(f, settings: s).service.ask('How did I sleep?'),
        throwsA(
          isA<CoachException>().having(
            (e) => e.kind,
            'kind',
            CoachErrorKind.notConfigured,
          ),
        ),
      );
    }
    expect(f.transcripts, isEmpty);
  });

  test('an exhausted daily budget fails fast with no network call', () async {
    final f = Fake((_, _) => const LlmTurn(text: 'x'));
    final m = module(f, settings: cloudSettings.copyWith(dailyRequestLimit: 1));
    await m.repository.recordUsage(CoachProvider.claude, 10, 10);
    final a = await m.service.ask('How did I sleep last night?');
    expect(a.error, CoachErrorKind.dailyLimit.name);
    expect(a.text, contains('limit'));
    expect(f.transcripts, isEmpty);
  });

  test('requests are metered against the budget', () async {
    final f = Fake(
      (t, _) => const LlmTurn(
        text: 'I can answer questions about your data.',
        inputTokens: 1000,
        outputTokens: 50,
      ),
    );
    final m = module(f);
    await m.service.ask('Hello there');
    final u = await m.repository.usageToday();
    expect(u!.requests, 1);
    expect(u.inputTokens, 1000);
    expect(u.requestLimit, kDefaultDailyRequestLimit);
  });

  test('at most 4 tool rounds, then the facts table', () async {
    final f = Fake(
      (t, _) => const LlmTurn(
        toolCalls: [ToolCall(id: 'a', name: 'get_today_summary', input: {})],
        stopReason: 'tool_use',
      ),
    );
    final a = await module(f).service.ask('Tell me everything');
    final rounds = f.transcripts.last
        .whereType<LlmToolResults>()
        .where((r) => !r.results.first.isError)
        .length;
    expect(rounds, 4);
    expect(a.text, startsWith(CoachPrompts.fallbackNote));
    expect(a.verification!.verified, isTrue);
  });

  test('a request that never returns times out, and the question is '
      'answered on this phone instead (model fallback)', () async {
    final f = Fake((_, _) => Completer<LlmTurn>().future);
    final m = CoachModule.inMemory(
      InMemoryHealthRepository.demo(now: now),
      clock: () => now,
      settings: cloudSettings,
      clients: (_, _, _) => f,
      keys: const {CoachProvider.claude: 'k'},
    );
    final svc = CoachServiceImpl(
      health: InMemoryHealthRepository.demo(now: now),
      coach: m.repository,
      clock: () => now,
      requestTimeout: const Duration(milliseconds: 50),
    );
    final a = await svc.ask('How did I sleep?');
    // A timeout is not bound to the model, so no backup model is asked:
    // the on-device engine answers, labelled with why.
    expect(a.error, isNull);
    expect(a.answeredBy, ChatMessage.onDevice);
    expect(a.fallbackFrom, 'fake');
    expect(a.fallbackReason, CoachErrorKind.network.name);
    expect(a.verification, isNotNull);
    expect(f.transcripts, hasLength(1));
  });

  test('a refusal is handled gracefully', () async {
    final f = Fake(
      (_, _) => const LlmTurn(refusal: true, stopReason: 'refusal'),
    );
    final a = await module(f).service.ask('Why is my HRV low?');
    expect(a.error, CoachErrorKind.refused.name);
    expect(a.text, CoachServiceImpl.refusalText);
  });

  test('a policy violation is repaired once, then replaced', () async {
    final f = Fake((t, _) {
      if (t.whereType<LlmToolResults>().isEmpty) {
        return const LlmTurn(
          toolCalls: [ToolCall(id: 'a', name: 'get_today_summary', input: {})],
          stopReason: 'tool_use',
        );
      }
      return const LlmTurn(text: 'This looks like the flu.');
    });
    final a = await module(f).service.ask('Why is my recovery low?');
    final repair = f.transcripts.last.whereType<LlmUser>().last.text;
    expect(repair, startsWith(CoachPrompts.repairMarker));
    expect(repair, contains('Diagnosis language'));
    expect(a.text, isNot(contains('flu')));
    expect(a.verification!.repaired, isTrue);
  });

  test('a card seed is card context in the question\'s own message: no '
      'synthetic tool turn, not offered as a tool; a cloud provider gets the '
      'withholding notice, not the card (PR #1)', () async {
    final f = Fake((t, tools) {
      expect(tools.map((x) => x.name), isNot(contains(CoachTools.insightCard)));
      return const LlmTurn(text: 'The card itself stays on your phone.');
    });
    const ctx = AskContext(
      screen: 'sleep',
      date: '2026-09-29',
      insightId: 'sleep:2026-09-29',
      seedText: 'A slightly short night',
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
    final a = await module(f).service.ask('Tell me more', context: ctx);
    final first = f.transcripts.first;
    expect(first, hasLength(1));
    expect(first.whereType<LlmAssistant>(), isEmpty);
    expect(first.whereType<LlmToolResults>(), isEmpty);
    final q = first.single as LlmUser;
    expect(q.text, 'Tell me more');
    expect(q.data.single.name, CoachTools.insightCard);
    // PR #1: the card's facts stay on the phone (on-device gets them, see
    // tools_test "the card seed carries its facts as quoted data"); the
    // cloud reads current facts through the guarded data tools instead.
    expect(q.data.single.refs, isEmpty);
    expect(q.data.single.content, contains('missing'));
    expect('${q.data.single.content}', isNot(contains('403')));
    expect(a.verification!.verified, isTrue);
    expect(a.sent!.toolsCalled, isEmpty, reason: 'nothing was called');
  });

  test('general-only: no data tools, no history, no seed', () async {
    final f = Fake((t, tools) {
      expect(tools.map((x) => x.name), ['get_methodology']);
      return const LlmTurn(
        text: 'Recovery compares last night with your baseline.',
      );
    });
    final m = module(
      f,
      settings: cloudSettings.copyWith(mode: CoachMode.generalOnly),
    );
    final a1 = await m.service.ask(
      'What is recovery?',
      context: const AskContext(
        seedText: 'x',
        seedRefs: [SourceRef(id: 'r1', label: 'Asleep', value: 1, unit: 'min')],
      ),
    );
    await m.service.ask('And HRV?', conversationId: a1.conversationId);
    expect(f.transcripts.last, hasLength(1), reason: 'no earlier messages');
  });

  test(
    'demo answers are tagged as sample data; proposals are not saved',
    () async {
      final f = Fake((t, _) {
        if (t.whereType<LlmToolResults>().isEmpty) {
          return const LlmTurn(
            toolCalls: [
              ToolCall(
                id: 'p',
                name: 'propose_memory',
                input: {
                  'text': 'Training for a half marathon',
                  'category': 'goals',
                },
              ),
            ],
            stopReason: 'tool_use',
          );
        }
        return const LlmTurn(text: 'I can remember that if you confirm.');
      });
      final m = module(f);
      final a = await m.service.ask('I am training for a half marathon');
      expect(a.sampleData, isTrue);
      expect(a.proposedMemories, ['Training for a half marathon']);
      // The model's category travels with the proposal (the UI's default,
      // and what decides the second confirm), and survives storage.
      expect(a.proposedCategories, ['goals']);
      expect(a.proposedCategory(0), MemoryCategory.goals);
      final back = ChatMessage.fromJson(a.toJson());
      expect(back.proposedCategory(0), MemoryCategory.goals);
      expect(await m.repository.memories(), isEmpty);
    },
  );

  test('older stored messages without categories still load', () {
    final m = ChatMessage.fromJson({
      'id': 'a',
      'conversationId': 'c',
      'role': 'assistant',
      'text': 'x',
      'at': '2026-09-29T08:00:00Z',
      'proposedMemories': ['Has asthma'],
    });
    expect(m.proposedCategories, isEmpty);
    expect(m.proposedCategory(0), isNull);
    expect(MemoryCategory.healthHistory.needsExplicitConfirm, isTrue);
    expect(MemoryCategory.mood.needsExplicitConfirm, isTrue);
    expect(MemoryCategory.goals.needsExplicitConfirm, isFalse);
  });
}
