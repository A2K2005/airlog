// The coach chat over scripted fakes: no setup wall (it opens straight
// away, with one dismissible connect card), the clean header, answers as a
// short plain reply (no citation marks), metric cards, plan actions and
// "What your data shows", the ⋯ menu (engine, data, "Checked against your
// data", what was shared, ask again, report), no data-mode label anywhere
// in the chat, status toasts, the calm composer
// (chips over one pill, the thinking dots), the calm safety answer, errors
// and their fixes, the per-session AI disclosure, "Remember this?" (nothing
// saved without a tap), history and new chat.

import 'package:airlog/app/ask_entry.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/app/providers.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/prompts.dart';
import 'package:airlog/features/coach/coach_screen.dart';
import 'package:airlog/features/coach/coach_settings_screen.dart';
import 'package:airlog/features/coach/widgets/answer_block.dart';
import 'package:airlog/features/coach/widgets/answer_text.dart';
import 'package:airlog/features/coach/widgets/connect_card.dart';
import 'package:airlog/features/coach/widgets/message_widgets.dart';
import 'package:airlog/features/coach/widgets/metric_card.dart';
import 'package:airlog/features/coach/widgets/thinking_row.dart';
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

const _tall = Size(412, 2000);

Future<void> _ask(WidgetTester t, String q) async {
  await t.enterText(find.byKey(const ValueKey('coach-input')), q);
  await t.pump();
  await t.tap(find.bySemanticsLabel('Send'));
  await t.pumpAndSettle();
}

/// The newest reply's text, as shown.
String _reply(WidgetTester t) {
  final text = t.widget<Text>(
    find
        .descendant(of: find.byType(ReplyText), matching: find.byType(Text))
        .first,
  );
  return text.textSpan!.toPlainText();
}

/// Opens the ⋯ menu of the newest answer.
Future<void> _menu(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel(AnswerCopy.options).first);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('it opens straight away: the starters, what this phone can '
      'answer, one connect card, no chips in the header, no length toggle', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo);
    final log = await pumpCoach(
      t,
      repo: repo,
      service: service,
      initial: Routes.coach,
    );
    expect(find.byType(CoachScreen), findsOneWidget);
    expect(log.names, isEmpty, reason: 'nothing is pushed first');
    expect(find.text('Coach'), findsOneWidget);
    expect(find.text(CoachCopy.onDeviceCan), findsOneWidget);
    for (final q in service.starters) {
      expect(find.text(q), findsOneWidget);
    }
    expect(find.text(CoachCopy.notMedical), findsOneWidget);
    expect(find.byType(ConnectHintCard), findsOneWidget);
    expect(find.text(CoachCopy.connectHint), findsOneWidget);
    // On this phone: no AI disclosure (there is no AI model).
    expect(find.byType(DisclosureLine), findsNothing);
    // The header holds only the title, Conversations and New chat.
    expect(find.text('On this phone'), findsNothing);
    expect(find.text(CoachCopy.modeLabel(CoachMode.useMyData)), findsNothing);
    expect(find.byType(SegmentedControl<ResponseLength>), findsNothing);
    expect(find.text('Detailed'), findsNothing);
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('coach-input')),
    );
    expect(field.enabled, isTrue);
    expect(service.suggestionContexts, [null]);
  });

  testWidgets('the connect card opens Settings → Coach, and once dismissed '
      'it stays gone', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coach);
    await t.tap(find.byKey(const ValueKey('connect-hint-open')));
    await t.pumpAndSettle();
    expect(find.byType(CoachSettingsScreen), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('connect-hint-dismiss')));
    await t.pumpAndSettle();
    expect(repo.current.cloudHintDismissed, isTrue);
    expect(find.byType(ConnectHintCard), findsNothing);
    await pumpCoach(t, repo: repo, initial: Routes.coach);
    expect(find.byType(ConnectHintCard), findsNothing);
  });

  testWidgets('no wall: a cloud engine that needs a review still takes the '
      'question (the service answers it on this phone)', (t) async {
    final repo = FakeCoachRepository(
      settings: _claude,
      keys: {CoachProvider.claude: 'sk-ant-api03-test-1234'},
    );
    final service = FakeCoachService(repo);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    expect(find.textContaining('Finish setting up'), findsNothing);
    expect(find.byType(ConnectHintCard), findsNothing);
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('coach-input')),
    );
    expect(field.enabled, isTrue);
    await _ask(t, 'How am I?');
    expect(service.asked.single.$1, 'How am I?');
  });

  testWidgets('send: the question at once, the thinking dots, then a short '
      'reply with ticked superscripts, two metric cards and a plan action', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo)..hold = true;
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);

    await t.enterText(find.byKey(const ValueKey('coach-input')), 'How am I?');
    await t.pump();
    await t.tap(find.bySemanticsLabel('Send'));
    await t.pump();
    expect(find.text('How am I?'), findsOneWidget);
    // A short grace first, so an instant answer never flashes the dots.
    expect(find.byType(ThinkingDots), findsNothing);
    await t.pump(Motion.fast);
    await t.pump(Motion.base);
    expect(find.byType(ThinkingDots), findsOneWidget);
    expect(find.text(ThinkingRow.label), findsOneWidget);
    expect(find.bySemanticsLabel(ThinkingRow.spoken), findsOneWidget);
    // Send is disabled while waiting.
    expect(find.bySemanticsLabel('Waiting for the answer'), findsOneWidget);
    // The loop is bounded: the tree settles while the answer is still out.
    await t.pumpAndSettle();
    expect(find.byType(ThinkingDots), findsOneWidget);

    service.release();
    await t.pumpAndSettle();
    expect(find.byType(ThinkingRow), findsNothing);
    expect(service.asked.single.$1, 'How am I?');
    // The reply is plain text: no citation marks, no ticks, and a
    // percentage with no space.
    final reply = _reply(t);
    expect(reply, startsWith('Your Recovery is 64% today, a little under'));
    expect(reply, isNot(contains('[r')));
    expect(reply, isNot(contains('✓')));
    expect(
      find.descendant(
        of: find.byType(ReplyText),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    // Cards: Recovery (the number) and HRV against its usual.
    expect(find.byType(MetricCard), findsNWidgets(2));
    expect(find.text('Usual 58 ms · 10% below usual'), findsOneWidget);
    expect(find.text(AnswerCopy.fromPlan), findsOneWidget);
    expect(find.text('Keep it light today'), findsOneWidget);
    // No pill, no Sources wall, no buttons row, no data-mode chip.
    expect(find.textContaining('Checked against your data'), findsNothing);
    expect(find.text('SOURCES'), findsNothing);
    expect(find.text('What was sent'), findsNothing);
    expect(find.text('Report answer'), findsNothing);
    expect(find.text(CoachCopy.sampleData), findsNothing);
    // The stored transcript replaced the optimistic question: one bubble.
    expect(find.byType(UserBubble), findsOneWidget);
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('coach-input')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('⋯ → "Checked against your data" lists each number and where '
      'it came from; a row opens its sheet, and the sheet its screen with '
      'the day selected', (t) async {
    final repo = FakeCoachRepository();
    final log = await pumpCoach(t, repo: repo, initial: Routes.coach);
    await _ask(t, 'How did I sleep?');
    await _menu(t);
    await t.tap(find.byKey(const ValueKey('menu-sources')));
    await t.pumpAndSettle();
    expect(find.text(AnswerCopy.checkedTitle), findsOneWidget);
    expect(find.text(AnswerCopy.checkedWhy), findsOneWidget);
    for (final r in CoachScript.refs) {
      expect(find.text(r.label), findsOneWidget);
    }
    for (final v in ['64%', '52 ms', '6h 40m']) {
      expect(
        find.descendant(of: find.byType(BottomSheet), matching: find.text(v)),
        findsOneWidget,
      );
    }
    expect(
      t.getSize(find.byKey(const ValueKey('source-row-a2-r1'))).height,
      greaterThanOrEqualTo(48),
    );
    // r3 is Sleep on Sun 27 Sep.
    await t.tap(find.byKey(const ValueKey('source-row-a2-r3')));
    await t.pumpAndSettle();
    expect(find.text('Sun 27 Sep'), findsOneWidget);
    expect(find.text('6h 40m'), findsOneWidget);
    expect(find.textContaining('Found in your data'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('metric-open-screen')));
    await t.pumpAndSettle();
    expect(log.names, [Routes.sleep]);
    expect(coachContainer(t).read(selectedDateProvider), '2026-09-27');
  });

  testWidgets('a metric card opens its sheet', (t) async {
    final repo = FakeCoachRepository();
    final log = await pumpCoach(t, repo: repo, initial: Routes.coach);
    await _ask(t, 'How am I?');
    await t.tap(find.byKey(const ValueKey('metric-a2-r2')));
    await t.pumpAndSettle();
    expect(find.text('HRV'), findsWidgets);
    expect(find.text('Usual 58 ms · 10% below usual'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('metric-open-screen')));
    await t.pumpAndSettle();
    expect(log.names, [Routes.recovery]);
  });

  testWidgets('trend and range answers draw only what their tools gave', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(
      repo,
      script: [Scripted.trend, Scripted.range],
    );
    await pumpCoach(
      t,
      repo: repo,
      service: service,
      initial: Routes.coach,
      size: _tall,
    );
    await _ask(t, 'How has my HRV been lately?');
    expect(find.byType(Sparkline), findsOneWidget);
    expect(find.text('Last 14 days · usual dotted'), findsOneWidget);
    expect(find.text('Average · Tue 15 Sep to Mon 28 Sep'), findsOneWidget);
    await _ask(t, 'Is anything off?');
    expect(find.text('Above usual'), findsOneWidget);
    expect(find.byType(Sparkline), findsOneWidget, reason: 'no invented trend');
  });

  testWidgets('facts only: "What your data shows" as tiles, one honest '
      'line, no raw table and no ticks', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo, script: [Scripted.fallback]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'Did I run on Sunday?');
    expect(find.byType(FactsCard), findsOneWidget);
    expect(find.text(AnswerCopy.factsTitle), findsOneWidget);
    expect(find.text(AnswerCopy.factsCaption), findsOneWidget);
    expect(find.textContaining(CoachPrompts.fallbackNote), findsNothing);
    expect(find.textContaining('•'), findsNothing);
    expect(find.byType(ReplyText), findsNothing);
    expect(find.byType(MetricCard), findsNothing);
    expect(find.byKey(const ValueKey('fact-r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('fact-r2')), findsOneWidget);
    // Its menu lists the sources, not "Checked against your data".
    await _menu(t);
    expect(find.text(AnswerCopy.checkedTitle), findsNothing);
    expect(find.text('Sources · 2'), findsOneWidget);
  });

  test('facts-only is told by its flag, or by its opening words on older '
      'messages', () {
    ChatMessage m(String text, {bool flag = false}) => ChatMessage(
      id: 'a',
      conversationId: 'c',
      role: ChatRole.assistant,
      text: text,
      at: kCoachNow,
      factsOnly: flag,
      verification: const Verification(
        checkedNumbers: 2,
        unsupported: [],
        repaired: true,
      ),
    );
    expect(isFactsOnly(m('x', flag: true)), isTrue);
    expect(isFactsOnly(m('${CoachPrompts.fallbackNote}\n• a')), isTrue);
    expect(
      isFactsOnly(
        m(
          "I couldn't phrase an answer without adding details your data "
          "doesn't show, so here are the facts I found instead:",
        ),
      ),
      isTrue,
    );
    expect(isFactsOnly(m('Your Recovery is 64%.')), isFalse);
    expect(isChecked(m('Your Recovery is 64%.')), isTrue);
    expect(isChecked(m('x', flag: true)), isFalse);
  });

  testWidgets('safety: calm, distinct, no sources, cards, menu or chips', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo, script: [Scripted.safety]);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'I have chest pain');
    expect(find.byType(SafetyAnswer), findsOneWidget);
    expect(find.text('For your safety'), findsOneWidget);
    expect(find.byType(ReplyText), findsNothing);
    expect(find.byType(AnswerFooter), findsNothing);
    expect(find.byKey(const ValueKey('composer-chips')), findsNothing);
  });

  testWidgets('errors: a network error retries in place', (t) async {
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
    expect(find.byType(ReplyText), findsOneWidget);
    expect(service.asked.length, 2);
    expect(service.asked[1].$1, 'How am I?');
    expect(find.byType(UserBubble), findsOneWidget);
  });

  testWidgets('errors: a refused key opens Settings → Coach', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(
      repo,
      script: [const CoachException(CoachErrorKind.invalidKey)],
    );
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    expect(find.text('Your key didn’t work'), findsOneWidget);
    await t.tap(find.text('Fix the key'));
    await t.pumpAndSettle();
    expect(find.byType(CoachSettingsScreen), findsOneWidget);
  });

  testWidgets('errors: the daily limit shows its own message, not '
      '"out of credit"', (t) async {
    const budget =
        'You’ve used today’s limit for Claude (20 model requests). Nothing '
        'more will be sent. It resets at midnight.';
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
    await t.tap(find.text('Open Coach settings'));
    await t.pumpAndSettle();
    expect(find.byType(CoachSettingsScreen), findsOneWidget);
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
    expect(find.text('Your nobody account is out of credit'), findsNothing);
    expect(find.textContaining('out of credit'), findsWidgets);
    expect(find.textContaining('HTTP 402'), findsNothing);
  });

  testWidgets('model fallback: the ⋯ menu says which engine wrote it, and a '
      'quiet glyph marks it; the chosen model\'s answers show none', (
    t,
  ) async {
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
    expect(find.bySemanticsLabel(RegExp('^Answered')), findsNothing);
    await _menu(t);
    expect(find.text('Answered by Claude · Opus 5.5'), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-engine-note')), findsNothing);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await _ask(t, 'And today?');
    expect(find.bySemanticsLabel('Answered by Sonnet 5.5'), findsOneWidget);
    await _menu(t);
    expect(find.text('Answered by Claude · Sonnet 5.5'), findsOneWidget);
    expect(find.text('Answered by Sonnet 5.5'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await _ask(t, 'And tomorrow?');
    await _menu(t);
    expect(find.text(AnswerCopy.onThisPhone), findsOneWidget);
    expect(
      find.text('Answered on this phone: Claude isn’t available right now.'),
      findsOneWidget,
    );
  });

  testWidgets('an answer written on this phone offers "Ask Claude again" in '
      "its menu: the same question with the chat's context", (t) async {
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
    await _menu(t);
    final again = find.byKey(const ValueKey('menu-ask-again'));
    expect(again, findsOneWidget);
    expect(find.text(CoachCopy.askAgain(CoachProvider.claude)), findsOneWidget);
    await t.tap(again);
    await t.pumpAndSettle();
    expect(service.asked, hasLength(2));
    expect(service.asked[1].$1, 'How am I?');
    expect(service.asked[1].$3, service.asked[0].$3);
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
      'to be down, and while today\'s budget is spent', (t) async {
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
    await _menu(t);
    expect(find.byKey(const ValueKey('menu-ask-again')), findsNothing);

    final spent =
        FakeCoachRepository(
            settings: _claudeOn,
            keys: {CoachProvider.claude: 'sk-ant-api03-test-1234'},
          )
          ..usage = const CoachUsage(
            provider: CoachProvider.claude,
            requests: 50,
            inputTokens: 0,
            outputTokens: 0,
            requestLimit: 50,
            tokenLimit: 200000,
          );
    await pumpCoach(
      t,
      repo: spent,
      service: FakeCoachService(spent, script: [Scripted.onDeviceFallback]),
      initial: Routes.coach,
    );
    await _ask(t, 'How am I?');
    await _menu(t);
    expect(find.byKey(const ValueKey('menu-ask-again')), findsNothing);
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
      'Answered by 3.5 Flash-Lite',
    );
    expect(
      CoachCopy.answeredByNote(g, m(ChatMessage.onDevice, 'server')),
      'Answered on this phone: Gemini isn’t available right now.',
    );
    expect(
      CoachCopy.answeredByNote(g, m(ChatMessage.onDevice, 'invalidKey')),
      contains('Gemini didn’t accept your API key'),
    );
    expect(
      CoachCopy.answeredByNote(g, m(ChatMessage.onDevice, 'quotaExceeded')),
      contains('out of credit'),
    );
    expect(
      CoachCopy.answeredByNote(g, m(ChatMessage.onDevice, 'notConfigured')),
      contains('needs a quick review in Settings → Coach'),
    );
    expect(
      CoachCopy.answeredByNote(g, m(ChatMessage.onDevice, 'dailyLimit')),
      contains('limit is used up'),
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

  testWidgets('a cloud session opens with the one-line AI disclosure, and '
      '⋯ shows what was shared', (t) async {
    final repo = FakeCoachRepository(
      settings: _claudeOn,
      keys: {CoachProvider.claude: 'sk-ant-api03-test-1234'},
    );
    final service = FakeCoachService(repo, script: [Scripted.cloud]);
    await pumpCoach(
      t,
      repo: repo,
      service: service,
      initial: Routes.coach,
      size: _tall,
    );
    expect(find.text('Claude · Opus 5.5'), findsNothing, reason: 'no chip');
    expect(find.byType(DisclosureLine), findsOneWidget);
    expect(find.text(CoachCopy.aiDisclaimer), findsOneWidget);
    expect(find.byType(ConnectHintCard), findsNothing);
    await _ask(t, 'How am I?');
    expect(find.byType(DisclosureLine), findsOneWidget);
    await _menu(t);
    expect(find.text('With my data'), findsOneWidget);
    expect(find.text(AnswerCopy.checkedTitle), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('menu-shared')));
    await t.pumpAndSettle();
    expect(find.text('What this answer shared'), findsOneWidget);
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('Opus 5.5'), findsOneWidget);
    expect(find.text('HRV (30 nights)'), findsOneWidget);
    expect(find.text('About 4.2k characters'), findsOneWidget);
    expect(find.text('get day, get range'), findsOneWidget);
  });

  testWidgets('an answer from this phone shared nothing, and says so', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coach);
    await _ask(t, 'How am I?');
    await _menu(t);
    expect(find.text(AnswerCopy.onThisPhone), findsOneWidget);
    expect(find.text(AnswerCopy.nothingShared), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-shared')), findsNothing);
  });

  testWidgets('Remember this?: nothing is saved without a tap; saving shows '
      'a toast', (t) async {
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

    await t.tap(find.bySemanticsLabel(RegExp('^Category: ')));
    await t.pumpAndSettle();
    await t.tap(find.text('Goals').last);
    await t.pumpAndSettle();
    expect(repo.memoryList, isEmpty);
    await t.tap(find.text('Remember'));
    await t.pumpAndSettle();
    expect(repo.memoryList.single.text, CoachScript.memoryFact);
    expect(repo.memoryList.single.category, MemoryCategory.goals);
    expect(find.text(AnswerCopy.saved), findsOneWidget);
    expect(find.byType(StatusToast), findsOneWidget);

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
    expect(find.text(AnswerCopy.saved), findsOneWidget);
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

  testWidgets('Report answer, from the menu: flagged on this phone, details '
      'copied, a toast instead of a snack bar', (t) async {
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
    await _menu(t);
    await t.tap(find.byKey(const ValueKey('menu-report')));
    await t.pumpAndSettle();
    expect(find.text('Report this answer'), findsOneWidget);
    await t.tap(find.text('Flag and copy'));
    await t.pumpAndSettle();
    expect(find.text(AnswerCopy.flagged), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(copied.single, contains('Question: How am I?'));
    expect(copied.single, contains('Source 1: Recovery · Mon 28 Sep = 64%'));
    expect(copied.single, isNot(contains('[r1]')));
    await _menu(t);
    expect(find.text('Reported'), findsOneWidget);
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
    expect(find.byType(ReplyText), findsOneWidget);
    // Stored messages never replay an entrance.
    for (final e in t.widgetList<CoachEnter>(find.byType(CoachEnter))) {
      expect(e.play, isFalse);
    }
    await _ask(t, 'And today?');
    expect(service.asked.last.$2, 'c1');
    await t.tap(find.bySemanticsLabel('New chat'));
    await t.pumpAndSettle();
    expect(find.byType(ReplyText), findsNothing);
    expect(find.text('Ask about your data'), findsOneWidget);
  });

  testWidgets('follow-ups: chips just above the pill fill it, and hide while '
      'typing', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo);
    await pumpCoach(t, repo: repo, service: service, initial: Routes.coach);
    await _ask(t, 'How am I?');
    final chips = find.byKey(const ValueKey('composer-chips'));
    expect(chips, findsOneWidget);
    const q = 'Which habits help my Recovery most?';
    await t.tap(find.byKey(const ValueKey('follow-up-$q')));
    await t.pumpAndSettle();
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('coach-input')),
    );
    expect(field.controller!.text, q);
    expect(service.asked, hasLength(1), reason: 'a chip never sends');
    final hidden = t.widget<AnimatedOpacity>(
      find.ancestor(of: chips, matching: find.byType(AnimatedOpacity)).first,
    );
    expect(hidden.opacity, 0);
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

  testWidgets('reduced motion: messages and cards fade only, and the '
      'thinking dots are still', (t) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo)..hold = true;
    await pumpCoach(
      t,
      repo: repo,
      service: service,
      initial: Routes.coach,
      reduceMotion: true,
    );
    await t.enterText(find.byKey(const ValueKey('coach-input')), 'How am I?');
    await t.pump();
    await t.tap(find.bySemanticsLabel('Send'));
    await t.pump();
    await t.pump(Motion.fast);
    // The row's own fade (kept under reduced motion) ends; nothing loops.
    await t.pump(Motion.slow);
    await t.pump(Motion.slow);
    expect(find.byType(ThinkingDots), findsOneWidget);
    expect(t.binding.hasScheduledFrame, isFalse, reason: 'no loop');
    service.release();
    await t.pump();
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
