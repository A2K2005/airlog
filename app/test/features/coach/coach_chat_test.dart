// The coach chat over scripted fakes: the send flow and its static waiting
// state, citations and Sources (tapping one opens its screen with the day
// selected), the verification pill and the honest fallback, the calm safety
// answer, errors and their fixes, "What was sent", Report, the per-session
// AI disclosure, "Remember this?" (nothing saved without a tap), history
// and new chat.

import 'package:airlog/app/ask_entry.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/app/providers.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/features/coach/coach_screen.dart';
import 'package:airlog/features/coach/coach_setup_screen.dart';
import 'package:airlog/features/coach/widgets/answer_text.dart';
import 'package:airlog/features/coach/widgets/message_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/coach_fixtures.dart';
import '../../support/fonts.dart';

const _claude = CoachSettings(
  provider: CoachProvider.claude,
  model: 'claude-opus-5-5',
  consentVersion: CoachCopy.consentVersion,
  adultConfirmed: true,
);

CoachSettings get _claudeOn => _claude.copyWith(consentAt: kCoachNow);

Future<void> _ask(WidgetTester t, String q) async {
  await t.enterText(find.byKey(const ValueKey('coach-input')), q);
  await t.pump();
  await t.tap(find.bySemanticsLabel('Send'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('empty state: suggestions and what on-device can answer', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    expect(find.byType(CoachScreen), findsOneWidget);
    expect(find.text('On-device'), findsOneWidget);
    expect(find.text('Uses your data'), findsOneWidget);
    expect(find.text(CoachCopy.onDeviceCan), findsOneWidget);
    for (final q in service.starters) {
      expect(find.text(q), findsOneWidget);
    }
    expect(find.text(CoachCopy.notMedical), findsOneWidget);
    // On-device: no AI disclosure (there is no AI model).
    expect(find.byType(DisclosureCard), findsNothing);
    expect(service.suggestionContexts, [null]);
  });

  testWidgets('send: the question shows at once, a static waiting row, '
      'then the verified answer with its sources', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo)..hold = true;
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);

    await t.enterText(find.byKey(const ValueKey('coach-input')), 'How am I?');
    await t.pump();
    await t.tap(find.bySemanticsLabel('Send'));
    await t.pump();
    await t.pumpAndSettle();
    // The question is on screen and the waiting row is static: the tree
    // settles while the answer is still on its way (nothing loops).
    expect(find.text('How am I?'), findsOneWidget);
    expect(find.text('Checking your data…'), findsOneWidget);
    expect(t.binding.hasScheduledFrame, isFalse);
    // Send is disabled while waiting.
    expect(find.bySemanticsLabel('Waiting for the answer'), findsOneWidget);

    service.release();
    await t.pumpAndSettle();
    expect(find.text('Checking your data…'), findsNothing);
    expect(service.asked.single.$1, 'How am I?');
    // Citations become numbered chips; the Sources row lists all three.
    expect(find.byType(CiteMark), findsNWidgets(6));
    expect(find.byType(SourceChip), findsNWidgets(3));
    expect(find.text('Checked against your data · 3 numbers'), findsOneWidget);
    // The stored transcript replaced the optimistic question: one bubble.
    expect(find.byType(UserBubble), findsOneWidget);
    // The composer is cleared.
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('coach-input')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('a source chip opens its screen with the day selected', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    final log = await pumpCoach(t, repo: repo, initial: Routes.coach);
    await _ask(t, 'How did I sleep?');
    // r3 is Sleep on Sun 27 Sep.
    await t.tap(find.byKey(const ValueKey('source-a2-r3')));
    await t.pumpAndSettle();
    expect(log.names, [Routes.sleep]);
    expect(coachContainer(t).read(selectedDateProvider), '2026-09-27');
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('source-a2-r1')));
    await t.pumpAndSettle();
    expect(log.names, [Routes.sleep, Routes.recovery]);
    expect(coachContainer(t).read(selectedDateProvider), kCoachToday);
  });

  testWidgets('fallback: facts only, said plainly', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo, script: [Scripted.fallback]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'Did I run on Sunday?');
    expect(find.text(CoachCopy.fallback), findsOneWidget);
    expect(find.textContaining(CoachCopy.checked), findsNothing);
    expect(find.byType(SourceChip), findsNWidgets(2));
  });

  testWidgets('safety: calm, distinct, no sources or pill', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo, script: [Scripted.safety]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'I have chest pain');
    expect(find.byType(SafetyAnswer), findsOneWidget);
    expect(find.text('For your safety'), findsOneWidget);
    expect(find.byType(SourceChip), findsNothing);
    expect(find.byType(VerificationPill), findsNothing);
  });

  testWidgets('errors: not configured opens setup; network retries', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(
      repo,
      script: [const CoachException(CoachErrorKind.network), Scripted.verified],
    );
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    expect(find.text('No connection'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('No connection'), findsNothing);
    expect(find.byType(SourceChip), findsNWidgets(3));
    expect(service.asked.length, 2);
    expect(service.asked[1].$1, 'How am I?');
    // One question bubble, not two.
    expect(find.byType(UserBubble), findsOneWidget);
  });

  testWidgets('errors: a refused key opens setup', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(
      repo,
      script: [const CoachException(CoachErrorKind.invalidKey)],
    );
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    expect(find.text('Your key was not accepted'), findsOneWidget);
    await t.tap(find.text('Fix the key'));
    await t.pumpAndSettle();
    expect(find.byType(CoachSetupScreen), findsOneWidget);
  });

  testWidgets('errors: the daily limit shows its own message, not '
      '"out of credit"', (t) async {
    const budget =
        "You've reached today's limit for Claude (20 questions), so nothing "
        'was sent. It resets at midnight.';
    final repo = FakeCoachRepository();
    final service = FakeCoachService(
      repo,
      script: [const CoachException(CoachErrorKind.dailyLimit, budget)],
    );
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    expect(find.text('Today’s limit reached'), findsOneWidget);
    expect(find.text(budget), findsOneWidget);
    expect(find.textContaining('out of credit'), findsNothing);
    await t.tap(find.text('Open setup'));
    await t.pumpAndSettle();
    expect(find.byType(CoachSetupScreen), findsOneWidget);
  });

  testWidgets('errors: a provider 402 says out of credit and never shows '
      'the raw HTTP text', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(
      repo,
      script: [
        const CoachException(
          CoachErrorKind.quotaExceeded,
          'HTTP 402 billing_error: credit balance too low',
        ),
      ],
    );
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    expect(find.text('Your provider account is out of credit'), findsOneWidget);
    expect(find.textContaining('HTTP 402'), findsNothing);
  });

  testWidgets('model fallback: the answer says quietly which engine wrote '
      'it; the chosen model\'s answers say nothing', (t) async {
    final repo = FakeCoachRepository(
      settings: _claudeOn,
      keys: {CoachProvider.claude: 'sk-ant-api03-test-1234'},
    );
    final service = FakeCoachService(
      repo,
      script: [Scripted.cloud, Scripted.viaBackup, Scripted.onDeviceFallback],
    );
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    expect(find.textContaining('via '), findsNothing);
    expect(find.textContaining('Answered on this phone'), findsNothing);

    await _ask(t, 'And today?');
    expect(find.text('via Sonnet 5.5'), findsOneWidget);

    await _ask(t, 'And tomorrow?');
    expect(
      find.text('Answered on this phone — Claude is unavailable right now.'),
      findsOneWidget,
    );
  });

  testWidgets('an answer written on this phone offers "Ask Claude again": '
      "the same question with the chat's context", (t) async {
    final repo = FakeCoachRepository(
      settings: _claudeOn,
      keys: {CoachProvider.claude: 'sk-ant-api03-test-1234'},
    );
    final service = FakeCoachService(
      repo,
      script: [Scripted.onDeviceFallback, Scripted.cloud],
    );
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    final again = find.text(CoachCopy.askAgain(CoachProvider.claude));
    expect(again, findsOneWidget);
    await t.ensureVisible(again);
    await t.pumpAndSettle();
    await t.tap(again);
    await t.pumpAndSettle();
    expect(service.asked, hasLength(2));
    expect(service.asked[1].$1, 'How am I?');
    expect(service.asked[1].$3, service.asked[0].$3);
    // Same conversation: a new turn, not a new chat.
    final conv = (await repo.conversations()).single;
    final stored = await repo.messages(conv.id);
    expect(
      [
        for (final m in stored)
          if (m.role == ChatRole.user) m.text,
      ],
      ['How am I?', 'How am I?'],
    );
  });

  testWidgets('"Ask Claude again" hides while the chosen model is known '
      'to be down', (t) async {
    final repo =
        FakeCoachRepository(
            settings: _claudeOn,
            keys: {CoachProvider.claude: 'sk-ant-api03-test-1234'},
          )
          ..down['claude-opus-5-5'] = ModelDown(
            kCoachNow.add(const Duration(hours: 3)),
            CoachErrorKind.quotaExceeded,
          );
    final service = FakeCoachService(repo, script: [Scripted.onDeviceFallback]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    expect(find.textContaining('Answered on this phone'), findsOneWidget);
    expect(find.text(CoachCopy.askAgain(CoachProvider.claude)), findsNothing);
  });

  test('fallback notes name the reason plainly', () {
    ChatMessage m(String by, String? reason) => ChatMessage(
      id: 'a',
      conversationId: 'c',
      role: ChatRole.assistant,
      text: 'x',
      at: kCoachNow,
      answeredBy: by,
      fallbackFrom: 'gemini-3.8-flash',
      fallbackReason: reason,
    );
    const g = CoachProvider.gemini;
    expect(
      CoachCopy.answeredByNote(g, m('gemini-3.5-flash-lite', 'server')),
      'via 3.5 Flash-Lite',
    );
    expect(
      CoachCopy.answeredByNote(g, m(ChatMessage.onDevice, 'server')),
      'Answered on this phone — Gemini is unavailable right now.',
    );
    expect(
      CoachCopy.answeredByNote(g, m(ChatMessage.onDevice, 'invalidKey')),
      contains("Gemini didn't accept your API key"),
    );
    expect(
      CoachCopy.answeredByNote(g, m(ChatMessage.onDevice, 'quotaExceeded')),
      contains('out of credit or quota'),
    );
    // The chosen model answered: no note.
    expect(
      CoachCopy.answeredByNote(
        g,
        ChatMessage(
          id: 'a',
          conversationId: 'c',
          role: ChatRole.assistant,
          text: 'x',
          at: kCoachNow,
          answeredBy: 'gemini-3.8-flash',
        ),
      ),
      isNull,
    );
    // Ids outside the catalogue still read well.
    expect(
      CoachCopy.modelName(CoachProvider.claude, 'claude-opus-4-8'),
      'Opus 4.8',
    );
    expect(CoachCopy.modelName(g, 'gemini-4.0-pro'), '4.0 Pro');
    expect(CoachCopy.modelName(g, 'something-else'), 'something-else');
  });

  testWidgets('errors: a stored error message maps to its kind', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo, script: [Scripted.errorMessage]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    expect(find.text('Too many questions at once'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a cloud session opens with the AI disclosure, and an answer '
      'shows what was sent', (t) async {
    final repo = FakeCoachRepository(
      settings: _claudeOn,
      keys: {CoachProvider.claude: 'sk-ant-api03-test-1234'},
    );
    final service = FakeCoachService(repo, script: [Scripted.cloud]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    expect(find.text('Claude · Opus 5.5'), findsOneWidget);
    expect(find.byType(DisclosureCard), findsOneWidget);
    await _ask(t, 'How am I?');
    expect(find.byType(DisclosureCard), findsOneWidget);
    await t.tap(find.text('What was sent'));
    await t.pumpAndSettle();
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('Opus 5.5'), findsOneWidget);
    expect(find.text('HRV (30 nights)'), findsOneWidget);
    expect(find.text('About 4.2k characters'), findsOneWidget);
    expect(find.text('get day, get range'), findsOneWidget);
  });

  testWidgets('a cloud engine without consent cannot send', (t) async {
    final repo = FakeCoachRepository(
      settings: _claude,
      keys: {CoachProvider.claude: 'sk-ant-api03-test-1234'},
    );
    final service = FakeCoachService(repo);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    expect(find.text('Finish setting up Claude'), findsOneWidget);
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('coach-input')),
    );
    expect(field.enabled, isFalse);
    await t.tap(find.text('Open setup'));
    await t.pumpAndSettle();
    expect(find.byType(CoachSetupScreen), findsOneWidget);
    expect(service.asked, isEmpty);
  });

  testWidgets('Remember this?: nothing is saved without a tap', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(
      repo,
      script: [Scripted.memory, Scripted.memory],
    );
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'I am training for a half marathon');
    expect(find.text('Remember this?'), findsOneWidget);
    expect(find.text('“${CoachScript.memoryFact}”'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('addMemory')), isEmpty);
    expect(repo.memoryList, isEmpty);

    // Pick the category, then Remember.
    await t.tap(find.bySemanticsLabel(RegExp('^Category: ')));
    await t.pumpAndSettle();
    await t.tap(find.text('Goals').last);
    await t.pumpAndSettle();
    expect(repo.memoryList, isEmpty);
    await t.tap(find.text('Remember'));
    await t.pumpAndSettle();
    expect(repo.memoryList.single.text, CoachScript.memoryFact);
    expect(repo.memoryList.single.category, MemoryCategory.goals);
    expect(find.text('Saved to What Coach knows'), findsOneWidget);

    // A second proposal, dismissed: still one memory.
    await _ask(t, 'Remember it again');
    await t.tap(find.text('No thanks'));
    await t.pumpAndSettle();
    expect(find.text('Remember this?'), findsNothing);
    expect(repo.memoryList, hasLength(1));
  });

  testWidgets('health history needs a second confirm; Cancel saves '
      'nothing', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo, script: [Scripted.sensitiveMemory]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'I get migraines after short nights');
    // The model's category, not the keyword guess.
    expect(
      find.bySemanticsLabel(RegExp('^Category: Health history')),
      findsOneWidget,
    );

    await t.tap(find.text('Remember'));
    await t.pumpAndSettle();
    expect(find.text('Remember this health detail?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(repo.memoryList, isEmpty);
    expect(find.text('Remember this?'), findsOneWidget);

    await t.tap(find.text('Remember'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes, remember'));
    await t.pumpAndSettle();
    expect(repo.memoryList.single.text, CoachScript.sensitiveFact);
    expect(repo.memoryList.single.category, MemoryCategory.healthHistory);
    expect(find.text('Saved to What Coach knows'), findsOneWidget);
  });

  testWidgets('a proposal re-filed as Mood also asks first', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo, script: [Scripted.memory]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'I am training for a half marathon');
    await t.tap(find.bySemanticsLabel(RegExp('^Category: ')));
    await t.pumpAndSettle();
    await t.tap(find.text('Mood').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Remember'));
    await t.pumpAndSettle();
    expect(find.text('Remember how you feel?'), findsOneWidget);
    await t.tap(find.text('Yes, remember'));
    await t.pumpAndSettle();
    expect(repo.memoryList.single.category, MemoryCategory.mood);
  });

  testWidgets('memory off: no Remember this? cards', (t) async {
    final repo = FakeCoachRepository(memoryOn: false);
    final service = FakeCoachService(repo, script: [Scripted.memory]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'I am training for a half marathon');
    expect(find.text('Remember this?'), findsNothing);
  });

  testWidgets('Report answer: flagged on this phone, details copied', (
    t,
  ) async {
    final copied = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coach);
    await _ask(t, 'How am I?');
    await t.tap(find.text('Report answer'));
    await t.pumpAndSettle();
    expect(find.text('Report this answer'), findsOneWidget);
    await t.tap(find.text('Flag and copy details'));
    await t.pumpAndSettle();
    expect(find.text('Reported'), findsOneWidget);
    expect(copied.single, contains('Question: How am I?'));
    expect(copied.single, contains('Source 1: Recovery · Mon 28 Sep = 64 %'));
    expect(copied.single, isNot(contains('[r1]')));
  });

  testWidgets('history: reopen a conversation; new chat starts over', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    repo.seedConversation(
      'Why was Recovery low?',
      (id) => [
        ChatMessage(
          id: 'old-u',
          conversationId: id,
          role: ChatRole.user,
          text: 'Why was Recovery low?',
          at: kCoachNow,
        ),
        CoachScript.answer(
          Scripted.verified,
          id: 'old-a',
          conversationId: id,
          at: kCoachNow,
        ),
      ],
    );
    final service = FakeCoachService(repo);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await t.tap(find.bySemanticsLabel('Conversations'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Why was Recovery low?').first);
    await t.pumpAndSettle();
    expect(find.byType(CoachScreen), findsOneWidget);
    expect(find.byType(SourceChip), findsNWidgets(3));
    // Stored messages never replay an entrance.
    for (final e in t.widgetList<CoachEnter>(find.byType(CoachEnter))) {
      expect(e.play, isFalse);
    }
    // The next question continues that conversation.
    await _ask(t, 'And today?');
    expect(service.asked.last.$2, 'c1');
    await t.tap(find.bySemanticsLabel('New chat'));
    await t.pumpAndSettle();
    expect(find.byType(SourceChip), findsNothing);
    expect(find.text('Ask about your data'), findsOneWidget);
  });

  testWidgets('Brief / Detailed is saved', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coach);
    await t.tap(find.text('Detailed'));
    await t.pumpAndSettle();
    expect(repo.current.length, ResponseLength.detailed);
  });

  testWidgets('the engine chip opens setup', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coach);
    await t.tap(find.byKey(const ValueKey('engine-chip')));
    await t.pumpAndSettle();
    expect(find.byType(CoachSetupScreen), findsOneWidget);
  });

  testWidgets('a launch with a context passes it to the service', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo);
    await pumpCoach(
      t,
      repo: repo,
      service: service,
      initial: Routes.coach,
      arguments: const CoachArgs(
        context: AskContext(screen: 'recovery', date: '2026-09-27'),
      ),
    );
    expect(service.suggestionContexts.single?.screen, 'recovery');
    await t.tap(find.bySemanticsLabel('Send'));
    await t.pumpAndSettle();
    expect(service.asked.single.$1, 'What drove my Recovery on Sun 27 Sep?');
    expect(service.asked.single.$3?.date, '2026-09-27');
  });

  testWidgets('reduced motion: messages fade only', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coach, reduceMotion: true);
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'How am I?');
    await t.pump();
    await t.tap(find.bySemanticsLabel('Send'));
    await t.pump();
    await t.pump(Motion.press);
    expect(
      find.descendant(
        of: find.byType(CoachEnter),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    await t.pumpAndSettle();
  });
}
