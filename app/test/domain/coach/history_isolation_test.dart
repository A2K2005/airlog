// PR #1 coach history isolation, which the PR shipped without tests: a
// cloud question replays an earlier answer only when it was built under
// the current privacy scope (same provider, mode, payload version and
// memory scope). A correction ("actually…") replays nothing, and a stored
// answer from before the scope existed is never replayed.

import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/coach_service.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 29, 9);

final claude = CoachSettings(
  provider: CoachProvider.claude,
  consentAt: DateTime(2026, 9, 1),
  consentVersion: kCoachConsentVersion,
  adultConfirmed: true,
);

/// Records every transcript; answers with plain text.
class Fake implements LlmClient {
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
    return const LlmTurn(text: 'Keep it easy today.');
  }
}

CoachModule module(Fake f) => CoachModule.inMemory(
  InMemoryHealthRepository.demo(now: now),
  clock: () => now,
  settings: claude,
  clients: (_, _, _) => f,
  keys: const {
    CoachProvider.claude: 'sk-ant-test-FAKEKEY123',
    CoachProvider.gemini: 'gm-test-FAKEKEY123',
  },
);

/// Turn 1, then [between], then turn 2 ([q2]); the number of items turn 2's
/// first request carried (1 = only its own question).
Future<int> turn2(
  Future<void> Function(CoachModule m) between, {
  String q2 = 'And the day before?',
}) async {
  final f = Fake();
  final m = module(f);
  final a1 = await m.service.ask('What drove my recovery today?');
  expect(a1.sent!.privacyVersion, kCoachPayloadVersion);
  await between(m);
  await m.service.ask(q2, conversationId: a1.conversationId);
  return f.transcripts.last.length;
}

void main() {
  test('the same scope: turn 1 is replayed', () async {
    expect(await turn2((_) async {}), 3);
  });

  test('another provider: not replayed', () async {
    expect(
      await turn2(
        (m) async => m.repository.saveSettings(
          (await m.repository.settings()).copyWith(
            provider: CoachProvider.gemini,
          ),
        ),
      ),
      1,
    );
  });

  test('the memory scope changed (a memory added): not replayed', () async {
    expect(
      await turn2(
        (m) => m.repository.addMemory(
          'Training for a half marathon',
          category: MemoryCategory.goals,
        ),
      ),
      1,
    );
  });

  test('memory turned off: not replayed', () async {
    expect(await turn2((m) => m.repository.setMemoryEnabled(false)), 1);
  });

  test('a correction replays no history', () async {
    expect(
      await turn2((_) async {}, q2: 'Actually I no longer run, what now?'),
      1,
    );
  });

  test('a stored answer without a privacy scope (before PR #1) is never '
      'replayed', () async {
    final f = Fake();
    final m = module(f);
    final c = await m.repository.createConversation('Old chat');
    await m.repository.appendMessage(
      ChatMessage(
        id: 'u0',
        conversationId: c.id,
        role: ChatRole.user,
        text: 'How did I sleep?',
        at: now.subtract(const Duration(minutes: 5)),
      ),
    );
    await m.repository.appendMessage(
      ChatMessage(
        id: 'a0',
        conversationId: c.id,
        role: ChatRole.assistant,
        text: 'You slept well.',
        at: now.subtract(const Duration(minutes: 4)),
        sampleData: true,
        sent: const SentPayload(
          provider: CoachProvider.claude,
          model: 'fake',
          toolsCalled: [],
          dataTypes: ['Your question'],
          approxChars: 10,
        ),
      ),
    );
    await m.service.ask('And the day before?', conversationId: c.id);
    expect(f.transcripts.single, hasLength(1));
  });
}
