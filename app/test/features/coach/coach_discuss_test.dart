// The chat opened from an insight card's "Discuss", and the message-level
// polish: the card pinned on top with follow-ups for its kind; nothing is
// sent or pre-filled on arrival (a cloud send spends the user's key); a
// follow-up tap only fills the composer; the card's seed reaches
// CoachService.ask; follow-ups under each answer; the answer-shaped
// waiting skeleton (never a spinner); the standing disclaimer; the calm
// banner when today's cloud budget is spent.

import 'package:airlog/app/ask_entry.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/repositories.dart' show DataMode;
import 'package:airlog/features/coach/coach_providers.dart';
import 'package:airlog/features/coach/widgets/message_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/coach_fixtures.dart';
import '../../support/fake_repo.dart';
import '../../support/fonts.dart';

const _claudeOn = CoachSettings(
  provider: CoachProvider.claude,
  model: 'claude-opus-5-5',
  consentVersion: CoachCopy.consentVersion,
  adultConfirmed: true,
);

CoachSettings get _cloud => _claudeOn.copyWith(consentAt: kCoachNow);

CoachArgs get _discussSleep =>
    CoachArgs(context: InsightScript.sleep.toAskContext());

String _composer(WidgetTester t) => t
    .widget<TextField>(find.byKey(const ValueKey('coach-input')))
    .controller!
    .text;

Future<void> _send(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('Send'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Discuss: the card is pinned, with follow-ups for its kind; '
      'nothing is sent or pre-filled', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo);
    await pumpCoach(
      t,
      repo: repo,
      service: service,
      initial: Routes.coach,
      arguments: _discussSleep,
    );
    expect(find.byType(DiscussPin), findsOneWidget);
    expect(find.text("Discussing: Here's how you slept"), findsOneWidget);
    expect(find.textContaining('7h 12m asleep'), findsOneWidget);
    for (final q in discussFollowUps('sleep')) {
      expect(find.text(q), findsOneWidget);
    }
    expect(discussFollowUps('sleep'), hasLength(3));
    expect(_composer(t), isEmpty);
    expect(service.asked, isEmpty);
    expect(repo.calls, isEmpty);
  });

  testWidgets('a follow-up tap fills the composer; send passes the seed', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo);
    await pumpCoach(
      t,
      repo: repo,
      service: service,
      initial: Routes.coach,
      arguments: _discussSleep,
    );
    final q = discussFollowUps('sleep').first;
    await t.tap(find.byKey(ValueKey('follow-up-$q')));
    await t.pumpAndSettle();
    expect(_composer(t), q);
    expect(service.asked, isEmpty);

    await _send(t);
    final (asked, _, ctx) = service.asked.single;
    expect(asked, q);
    expect(ctx?.insightId, InsightScript.sleep.id);
    expect(ctx?.screen, 'sleep');
    expect(ctx?.date, kCoachToday);
    expect(ctx?.seedText, "Here's how you slept\n${InsightScript.sleep.body}");
    expect(ctx?.seedRefs.map((r) => r.id), ['s1', 's2', 's3']);
    // The card stays pinned above the conversation.
    expect(find.byType(DiscussPin), findsOneWidget);
  });

  testWidgets('the card stays with its session: History and New chat drop '
      'the pin and the seed', (t) async {
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
    await pumpCoach(
      t,
      repo: repo,
      service: service,
      initial: Routes.coach,
      arguments: _discussSleep,
    );
    expect(find.byType(DiscussPin), findsOneWidget);

    await t.tap(find.bySemanticsLabel('Conversations'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Why was Recovery low?').first);
    await t.pumpAndSettle();
    expect(find.byType(DiscussPin), findsNothing);
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'And today?');
    await t.pump();
    await _send(t);
    final (_, conv, ctx) = service.asked.last;
    expect(conv, 'c1');
    expect(ctx?.insightId, isNull);
    expect(ctx?.seedText, isNull);
    expect(ctx?.seedRefs, isEmpty);

    await t.tap(find.bySemanticsLabel('New chat'));
    await t.pumpAndSettle();
    expect(find.byType(DiscussPin), findsNothing);
    expect(find.text('Ask about your data'), findsOneWidget);
    // The starters come back in place of the card's follow-ups.
    for (final q in service.starters) {
      expect(find.text(q), findsOneWidget);
    }
  });

  testWidgets('follow-ups under the latest answer fill the composer', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'How am I?');
    await t.pump();
    await _send(t);
    final answer = repo.msgs.values.single.last;
    final ups = answerFollowUps(answer, asked: 'How am I?');
    expect(ups, isNotEmpty);
    expect(find.byType(FollowUpChips), findsOneWidget);
    await t.tap(find.byKey(ValueKey('follow-up-${ups.first}')));
    await t.pumpAndSettle();
    expect(_composer(t), ups.first);
    expect(service.asked, hasLength(1));
  });

  test('follow-ups never repeat the question just asked', () {
    final answer = CoachScript.answer(
      Scripted.verified,
      id: 'a',
      conversationId: 'c',
      at: kCoachNow,
    );
    final all = answerFollowUps(answer);
    final less = answerFollowUps(answer, asked: all.first.toUpperCase());
    expect(less, isNot(contains(all.first)));
    for (final q in [
      ...all,
      for (final k in ['sleep', 'recovery', 'strain', 'weekly', null])
        ...discussFollowUps(k),
    ]) {
      expect(q.toLowerCase(), isNot(contains('streak')));
    }
  });

  testWidgets('no follow-ups under a safety answer or an error', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(
      repo,
      script: [Scripted.safety, Scripted.errorMessage],
    );
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'Chest pain');
    await t.pump();
    await _send(t);
    expect(find.byType(FollowUpChips), findsNothing);
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'Again');
    await t.pump();
    await _send(t);
    expect(find.byType(FollowUpChips), findsNothing);
  });

  testWidgets('demo mode: answers that cite data say Sample data', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo, script: [Scripted.safety]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'Chest pain');
    await t.pump();
    await _send(t);
    // The safety answer quotes no data.
    expect(find.text(CoachCopy.sampleData), findsNothing);
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'How am I?');
    await t.pump();
    await _send(t);
    expect(find.byKey(const ValueKey('answer-sample')), findsOneWidget);
  });

  testWidgets('live data: no Sample data tag', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(
      t,
      repo: repo,
      initial: Routes.coach,
      health: FakeRepo(mode: DataMode.live),
    );
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'How am I?');
    await t.pump();
    await _send(t);
    expect(find.byType(SourceChip), findsNWidgets(3));
    expect(find.text(CoachCopy.sampleData), findsNothing);
  });

  testWidgets('waiting: an answer-shaped skeleton, never a spinner', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo)..hold = true;
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'How am I?');
    await t.pump();
    await t.tap(find.bySemanticsLabel('Send'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('waiting-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(t.binding.hasScheduledFrame, isFalse);
    service.release();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('waiting-skeleton')), findsNothing);
  });

  testWidgets('the standing disclaimer: AI engines say AI can make mistakes', (
    t,
  ) async {
    final repo = FakeCoachRepository(
      settings: _cloud,
      keys: {CoachProvider.claude: 'sk-ant-api03-test'},
    );
    await pumpCoach(t, repo: repo, initial: Routes.coach);
    expect(find.text(CoachCopy.aiDisclaimer), findsOneWidget);
    expect(find.text(CoachCopy.notMedical), findsNothing);
  });

  testWidgets('the standing disclaimer on-device (no AI model)', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coach);
    expect(find.text(CoachCopy.notMedical), findsOneWidget);
    expect(find.text(CoachCopy.aiDisclaimer), findsNothing);
  });

  testWidgets("today's cloud budget spent: a calm banner, send disabled", (
    t,
  ) async {
    final repo =
        FakeCoachRepository(
            settings: _cloud,
            keys: {CoachProvider.claude: 'sk-ant-api03-test'},
          )
          ..usage = const CoachUsage(
            provider: CoachProvider.claude,
            requests: 50,
            inputTokens: 90000,
            outputTokens: 10000,
            requestLimit: 50,
            tokenLimit: 200000,
          );
    final service = FakeCoachService(repo);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    expect(find.byKey(const ValueKey('usage-spent')), findsOneWidget);
    expect(find.text(CoachCopy.usageSpent), findsOneWidget);
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('coach-input')),
    );
    expect(field.enabled, isFalse);
    expect(service.asked, isEmpty);
  });

  testWidgets('under the budget: no banner', (t) async {
    final repo =
        FakeCoachRepository(
            settings: _cloud,
            keys: {CoachProvider.claude: 'sk-ant-api03-test'},
          )
          ..usage = const CoachUsage(
            provider: CoachProvider.claude,
            requests: 3,
            inputTokens: 9000,
            outputTokens: 1000,
            requestLimit: 50,
            tokenLimit: 200000,
          );
    await pumpCoach(t, repo: repo, initial: Routes.coach);
    expect(find.byKey(const ValueKey('usage-spent')), findsNothing);
  });

  test('CoachLaunch keeps the whole AskContext and tells launches apart', () {
    final ctx = InsightScript.sleep.toAskContext();
    final a = CoachLaunch.from(CoachArgs(context: ctx));
    final b = CoachLaunch.from(ctx);
    expect(a, b);
    expect(a.context?.insightId, ctx.insightId);
    expect(a.context?.seedText, ctx.seedText);
    expect(a.context?.seedRefs, ctx.seedRefs);
    expect(a.discussHeadline, "Here's how you slept");
    expect(a.discussBody, InsightScript.sleep.body);
    final plain = CoachLaunch.from(
      AskContext(screen: ctx.screen, date: ctx.date),
    );
    expect(plain == a, isFalse);
    expect(plain.discussing, isFalse);
  });
}
