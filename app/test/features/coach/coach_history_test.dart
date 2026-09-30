// Conversations as topics: the topic of a chat comes from the tools its
// answers used (never a guess); the topic cards show their counts; a card
// filters the list and tapping it again shows all; search matches titles
// and message text; delete and delete all still work.

import 'package:airlog/app/route_names.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/features/coach/coach_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/coach_fixtures.dart';
import '../../support/fonts.dart';

ChatMessage _q(String id, String text) => ChatMessage(
  id: 'q-$id',
  conversationId: id,
  role: ChatRole.user,
  text: text,
  at: kCoachNow,
);

ChatMessage _a(String id, String text, List<String> tools) => ChatMessage(
  id: 'a-$id',
  conversationId: id,
  role: ChatRole.assistant,
  text: text,
  at: kCoachNow,
  tools: tools,
);

FakeCoachRepository _seeded() {
  final repo = FakeCoachRepository();
  repo
    ..seedConversation(
      'How did I sleep last night?',
      (id) => [
        _q(id, 'How did I sleep last night?'),
        _a(id, 'You slept 6h 40m.', ['get_sleep']),
      ],
      at: kCoachNow.subtract(const Duration(days: 2)),
    )
    ..seedConversation(
      'Was my sleep steady this week?',
      (id) => [
        _q(id, 'Was my sleep steady this week?'),
        _a(id, 'Mostly steady.', ['get_range:sleep_duration']),
      ],
      at: kCoachNow.subtract(const Duration(days: 1)),
    )
    ..seedConversation(
      'Does alcohol affect my recovery?',
      (id) => [
        _q(id, 'Does alcohol affect my recovery?'),
        _a(id, 'Alcohol evenings were followed by lower Recovery.', [
          'get_journal_insights',
        ]),
      ],
    )
    ..seedConversation(
      'What is HRV?',
      (id) => [
        _q(id, 'What is HRV?'),
        _a(id, 'Heart rate variability is …', ['get_methodology']),
      ],
    );
  return repo;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('chats grouped by topic from their tools, with counts', (
    t,
  ) async {
    await pumpCoach(t, repo: _seeded(), initial: Routes.coachHistory);
    expect(find.byType(CoachHistoryScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-sleep')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-journal')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-general')), findsOneWidget);
    // No chat is about training or recovery: those cards are left out.
    expect(find.byKey(const ValueKey('topic-training')), findsNothing);
    expect(find.byKey(const ValueKey('topic-recovery')), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'^Sleep: 2 chats')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Journal: 1 chat,')), findsOneWidget);
    for (final title in [
      'How did I sleep last night?',
      'Was my sleep steady this week?',
      'Does alcohol affect my recovery?',
      'What is HRV?',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('a topic card filters the list; again shows all', (t) async {
    await pumpCoach(t, repo: _seeded(), initial: Routes.coachHistory);
    await t.tap(find.byKey(const ValueKey('topic-sleep')));
    await t.pumpAndSettle();
    expect(find.text('SLEEP CHATS'), findsOneWidget);
    expect(find.text('How did I sleep last night?'), findsOneWidget);
    expect(find.text('Does alcohol affect my recovery?'), findsNothing);
    await t.tap(find.byKey(const ValueKey('topic-sleep')));
    await t.pumpAndSettle();
    expect(find.text('Does alcohol affect my recovery?'), findsOneWidget);
  });

  testWidgets('search matches titles and message text', (t) async {
    await pumpCoach(t, repo: _seeded(), initial: Routes.coachHistory);
    await t.enterText(find.byKey(const ValueKey('history-search')), 'lower');
    await t.pumpAndSettle();
    expect(find.text('Does alcohol affect my recovery?'), findsOneWidget);
    expect(find.text('What is HRV?'), findsNothing);
    await t.enterText(find.byKey(const ValueKey('history-search')), 'zzz');
    await t.pumpAndSettle();
    expect(find.text('No chats match.'), findsOneWidget);
  });

  testWidgets('delete one, then delete all', (t) async {
    final repo = _seeded();
    await pumpCoach(t, repo: repo, initial: Routes.coachHistory);
    await t.tap(find.bySemanticsLabel('Delete What is HRV?'));
    await t.pumpAndSettle();
    expect(find.text('What is HRV?'), findsNothing);
    expect(repo.calls, contains('deleteConversation:c4'));
    expect(find.byKey(const ValueKey('topic-general')), findsNothing);

    await t.tap(find.bySemanticsLabel('Delete all chats'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete all chats').last);
    await t.pumpAndSettle();
    expect(repo.convs, isEmpty);
    expect(find.text('No conversations'), findsOneWidget);
  });

  testWidgets('older answers without tools fall back to their source routes', (
    t,
  ) async {
    final repo = FakeCoachRepository()
      ..seedConversation(
        'Why is my Recovery lower today?',
        (id) => [
          _q(id, 'Why is my Recovery lower today?'),
          CoachScript.answer(
            Scripted.memory,
            id: 'a-$id',
            conversationId: id,
            at: kCoachNow,
          ),
        ],
      );
    await pumpCoach(t, repo: repo, initial: Routes.coachHistory);
    expect(find.byKey(const ValueKey('topic-recovery')), findsOneWidget);
  });
}
