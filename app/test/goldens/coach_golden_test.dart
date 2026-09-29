// Goldens: the coach screens at 412×915, dark and light, fixed clock
// (Mon 28 Sep 2026, 19:30), over scripted fakes.
//
//   flutter test test/goldens/coach_golden_test.dart --update-goldens

import 'package:airlog/app/ask_entry.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/app/insight_card.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/features/coach/coach_memory_screen.dart';
import 'package:airlog/features/coach/coach_screen.dart';
import 'package:airlog/features/coach/coach_settings_screen.dart';
import 'package:airlog/features/coach/coach_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_fixtures.dart';
import '../support/fonts.dart';

final _claudeOn = CoachSettings(
  provider: CoachProvider.claude,
  model: 'claude-opus-5-5',
  consentAt: kCoachNow,
  consentVersion: CoachCopy.consentVersion,
  adultConfirmed: true,
);

/// A stored conversation: one question and the scripted [kind] of answer.
String _seed(FakeCoachRepository repo, String question, Scripted kind) => repo
    .seedConversation(
      question,
      (id) => [
        ChatMessage(
          id: 'q-$id',
          conversationId: id,
          role: ChatRole.user,
          text: question,
          at: kCoachNow,
        ),
        CoachScript.answer(
          kind,
          id: 'a-$id',
          conversationId: id,
          at: kCoachNow,
        ),
      ],
    )
    .id;

List<MemoryFact> _facts() => [
  MemoryFact(
    id: 'f1',
    text: 'Training for a half marathon',
    createdAt: kCoachNow,
    category: MemoryCategory.goals,
  ),
  MemoryFact(
    id: 'f2',
    text: 'Race day is 15 November',
    createdAt: kCoachNow,
    category: MemoryCategory.events,
    expiresOn: '2026-11-15',
  ),
  MemoryFact(
    id: 'f3',
    text: 'Travelling for work',
    createdAt: kCoachNow,
    category: MemoryCategory.events,
    expiresOn: '2026-09-20',
  ),
  MemoryFact(
    id: 'f4',
    text: 'Night shifts on Fridays',
    createdAt: kCoachNow,
    category: MemoryCategory.lifestyle,
  ),
  MemoryFact(
    id: 'f5',
    text: 'Prefers metric units and no diet talk',
    createdAt: kCoachNow,
    category: MemoryCategory.preferences,
  ),
];

void main() {
  setUpAll(loadAppFonts);

  for (final b in const [Brightness.dark]) { // dark only
    testWidgets('coach empty · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      await pumpCoach(t, repo: repo, initial: Routes.coach, brightness: b);
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_empty_${b.name}.png'),
      );
    });

    testWidgets('coach answer · ${b.name}', (t) async {
      final repo = FakeCoachRepository(
        settings: _claudeOn,
        keys: {CoachProvider.claude: 'sk-ant-api03-golden-1234'},
      );
      final id = _seed(repo, 'Why is my Recovery lower today?', Scripted.cloud);
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        brightness: b,
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_answer_${b.name}.png'),
      );
    });

    testWidgets('coach fallback · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      final id = _seed(
        repo,
        'Did I go for a run on Sunday?',
        Scripted.fallback,
      );
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        brightness: b,
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_fallback_${b.name}.png'),
      );
    });

    testWidgets('coach safety · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      final id = _seed(repo, 'I have chest pain after my run', Scripted.safety);
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        brightness: b,
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_safety_${b.name}.png'),
      );
    });

    testWidgets('coach remember · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      final id = _seed(
        repo,
        "I'm training for a half marathon on 15 Nov",
        Scripted.memory,
      );
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        brightness: b,
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_remember_${b.name}.png'),
      );
    });

    testWidgets('coach setup cloud · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      await pumpCoach(t, repo: repo, initial: Routes.coachSetup, brightness: b);
      await t.tap(find.byKey(const ValueKey('engine-claude')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CoachSetupScreen),
        matchesGoldenFile('screens/coach_setup_cloud_${b.name}.png'),
      );
    });

    testWidgets('coach setup cloud full length · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coachSetup,
        brightness: b,
        size: const Size(412, 2700),
      );
      await t.tap(find.byKey(const ValueKey('engine-gemini')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CoachSetupScreen),
        matchesGoldenFile('screens/coach_setup_gemini_full_${b.name}.png'),
      );
    });

    testWidgets('coach memory · ${b.name}', (t) async {
      final repo = FakeCoachRepository(memories: _facts());
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coachMemory,
        brightness: b,
      );
      await expectLater(
        find.byType(CoachMemoryScreen),
        matchesGoldenFile('screens/coach_memory_${b.name}.png'),
      );
    });

    testWidgets('coach settings · ${b.name}', (t) async {
      final repo = FakeCoachRepository(
        settings: _claudeOn,
        keys: {CoachProvider.claude: 'sk-ant-api03-golden-1234'},
        memories: _facts(),
      );
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.settingsCoach,
        brightness: b,
      );
      await expectLater(
        find.byType(CoachSettingsScreen),
        matchesGoldenFile('screens/coach_settings_${b.name}.png'),
      );
    });

    testWidgets('coach settings, Coach messages · ${b.name}', (t) async {
      final repo =
          FakeCoachRepository(
              settings: _claudeOn,
              keys: {CoachProvider.claude: 'sk-ant-api03-golden-1234'},
              memories: _facts(),
            )
            ..usage = const CoachUsage(
              provider: CoachProvider.claude,
              requests: 3,
              inputTokens: 11000,
              outputTokens: 1400,
              requestLimit: 50,
              tokenLimit: 200000,
            );
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.settingsCoach,
        brightness: b,
        size: const Size(412, 1900),
      );
      await expectLater(
        find.byType(CoachSettingsScreen),
        matchesGoldenFile('screens/coach_settings_full_${b.name}.png'),
      );
    });

    testWidgets('coach insight cards · ${b.name}', (t) async {
      final repo = FakeCoachRepository(memories: _facts());
      await pumpCoach(
        t,
        repo: repo,
        insights: FakeInsightService(
          insights: [InsightScript.sleep, InsightScript.recoveryAi],
        ),
        brightness: b,
        home: Builder(
          builder: (c) => Scaffold(
            backgroundColor: P.of(c).bg,
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(S.gutter),
                children: const [InsightFeed(date: kCoachToday, max: null)],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(InsightCard), findsNWidgets(2));
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('screens/coach_insight_cards_${b.name}.png'),
      );
    });

    testWidgets('coach discuss · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(context: InsightScript.sleep.toAskContext()),
        brightness: b,
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_discuss_${b.name}.png'),
      );
    });

    testWidgets('coach waiting · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      final service = FakeCoachService(repo)..hold = true;
      await pumpCoach(
        t,
        repo: repo,
        service: service,
        initial: Routes.coach,
        brightness: b,
      );
      await t.enterText(
        find.byKey(const ValueKey('coach-input')),
        'How did I sleep last night?',
      );
      await t.pump();
      await t.tap(find.bySemanticsLabel('Send'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_waiting_${b.name}.png'),
      );
      service.release();
      await t.pumpAndSettle();
    });
  }
}
