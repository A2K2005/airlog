// Goldens: the coach screens at 412×915, dark only, fixed clock
// (Mon 28 Sep 2026, 19:30), over scripted fakes, with the user's own data
// connected (live mode), so no demo label shows in any render.
//
//   flutter test test/goldens/coach_golden_test.dart --update-goldens

import 'package:airlog/app/ask_entry.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/app/insight_card.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/repositories.dart' show DataMode;
import 'package:airlog/features/coach/coach_history_screen.dart';
import 'package:airlog/features/coach/coach_memory_screen.dart';
import 'package:airlog/features/coach/coach_screen.dart';
import 'package:airlog/features/coach/coach_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_fixtures.dart';
import '../support/fake_repo.dart';
import '../support/fonts.dart';

/// The user's own data (not the demo): renders carry no demo label.
FakeRepo _live() => FakeRepo(mode: DataMode.live);

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
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        brightness: b,
        health: _live(),
      );
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
        health: _live(),
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_answer_${b.name}.png'),
      );
    });

    testWidgets('coach answer on this phone · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      final id = _seed(
        repo,
        'Why is my Recovery lower today?',
        Scripted.verified,
      );
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        brightness: b,
        health: _live(),
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_answer_onphone_${b.name}.png'),
      );
    });

    testWidgets('coach answer menu · ${b.name}', (t) async {
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
        health: _live(),
      );
      await t.tap(find.bySemanticsLabel('Answer options').first);
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screens/coach_answer_menu_${b.name}.png'),
      );
    });

    testWidgets('coach metric sheet · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      final id = _seed(
        repo,
        'How has my HRV been lately?',
        Scripted.trend,
      );
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        brightness: b,
        health: _live(),
      );
      await t.tap(find.byKey(ValueKey('metric-a-$id-r1')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screens/coach_metric_sheet_${b.name}.png'),
      );
    });

    testWidgets('coach answer trend · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      final id = _seed(repo, 'How has my HRV been lately?', Scripted.trend);
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        brightness: b,
        health: _live(),
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_answer_trend_${b.name}.png'),
      );
    });

    testWidgets('coach answer range · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      final id = _seed(repo, 'Is anything off today?', Scripted.range);
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        brightness: b,
        health: _live(),
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_answer_range_${b.name}.png'),
      );
    });

    testWidgets('coach facts · ${b.name}', (t) async {
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
        health: _live(),
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_facts_${b.name}.png'),
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
        health: _live(),
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
        health: _live(),
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_remember_${b.name}.png'),
      );
    });

    testWidgets('coach connect, key · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.settingsCoach,
        brightness: b,
        health: _live(),
      );
      await t.tap(find.byKey(const ValueKey('engine-claude')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screens/coach_connect_key_${b.name}.png'),
      );
    });

    testWidgets('coach connect, Gemini consent full length · ${b.name}', (
      t,
    ) async {
      final repo = FakeCoachRepository(
        keys: {CoachProvider.gemini: 'AIzaSyA1234567890abcdefghijklmnopq4321'},
      );
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.settingsCoach,
        brightness: b,
        health: _live(),
        size: const Size(412, 2900),
      );
      await t.tap(find.byKey(const ValueKey('engine-gemini')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('screens/coach_connect_consent_gemini_full_${b.name}.png'),
      );
    });

    testWidgets('coach history topics · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      void chat(String q, List<String> tools, int daysAgo) =>
          repo.seedConversation(
            q,
            (id) => [
              ChatMessage(
                id: 'q-$id',
                conversationId: id,
                role: ChatRole.user,
                text: q,
                at: kCoachNow,
              ),
              ChatMessage(
                id: 'a-$id',
                conversationId: id,
                role: ChatRole.assistant,
                text: 'x',
                at: kCoachNow,
                tools: tools,
              ),
            ],
            at: kCoachNow.subtract(Duration(days: daysAgo)),
          );
      chat('How did I sleep last night?', ['get_sleep'], 0);
      chat('Why is my Recovery lower today?', ['get_today_summary'], 0);
      chat('Was my sleep steady this week?', ['get_range:sleep_duration'], 1);
      chat('How hard was my last workout?', ['get_workouts'], 2);
      chat('Does alcohol affect my recovery?', ['get_journal_insights'], 3);
      chat('What is HRV?', ['get_methodology'], 5);
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coachHistory,
        brightness: b,
        health: _live(),
      );
      await expectLater(
        find.byType(CoachHistoryScreen),
        matchesGoldenFile('screens/coach_history_topics_${b.name}.png'),
      );
    });

    testWidgets('coach memory · ${b.name}', (t) async {
      final repo = FakeCoachRepository(memories: _facts());
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coachMemory,
        brightness: b,
        health: _live(),
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
        health: _live(),
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
        health: _live(),
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
        health: _live(),
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
        health: _live(),
      );
      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('screens/coach_discuss_${b.name}.png'),
      );
    });

    // The thinking dots rest after their bounded loop, so the frame is
    // deterministic.
    testWidgets('coach thinking · ${b.name}', (t) async {
      final repo = FakeCoachRepository();
      final service = FakeCoachService(repo)..hold = true;
      await pumpCoach(
        t,
        repo: repo,
        service: service,
        initial: Routes.coach,
        brightness: b,
        health: _live(),
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
        matchesGoldenFile('screens/coach_thinking_${b.name}.png'),
      );
      service.release();
      await t.pumpAndSettle();
    });
  }
}
