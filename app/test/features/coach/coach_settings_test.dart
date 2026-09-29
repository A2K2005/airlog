// Settings → Coach: the "Show coach" master switch (off hides every entry
// point), "Coach messages" on / off (on = InsightLevel.basic; v1 has no
// Full), and today's usage row (hidden when not tracked).

import 'dart:async';

import 'package:airlog/app/ask_entry.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/insight_contracts.dart';
import 'package:airlog/features/coach/coach_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/coach_fixtures.dart';
import '../../support/fonts.dart';

const _key = 'sk-ant-api03-test';

final _cloud = CoachSettings(
  provider: CoachProvider.claude,
  model: 'claude-opus-5-5',
  consentAt: kCoachNow,
  consentVersion: CoachCopy.consentVersion,
  adultConfirmed: true,
);

Future<void> _see(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<FakeInsightService> _pump(
  WidgetTester t,
  FakeCoachRepository repo, {
  InsightLevel level = InsightLevel.basic,
}) async {
  final insights = FakeInsightService(current: level);
  await pumpCoach(
    t,
    repo: repo,
    insights: insights,
    initial: Routes.settingsCoach,
  );
  expect(find.byType(CoachSettingsScreen), findsOneWidget);
  return insights;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Show coach off hides every entry point', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(
      t,
      repo: repo,
      home: const Scaffold(
        body: Column(
          children: [
            AskAboutThis(screen: 'sleep'),
            AskIconButton(screen: 'sleep'),
          ],
        ),
      ),
    );
    expect(find.text(CoachCopy.askAboutThis), findsOneWidget);
    unawaited(
      Navigator.of(t.element(find.byType(AskAboutThis)))
          .pushNamed(Routes.settingsCoach),
    );
    await t.pumpAndSettle();
    expect(find.text(CoachCopy.showCoach), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('switch-show-coach')));
    await t.pumpAndSettle();
    expect(repo.current.enabled, isFalse);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text(CoachCopy.askAboutThis), findsNothing);
    expect(find.bySemanticsLabel('Ask the coach'), findsNothing);

    await pumpCoach(t, repo: repo, initial: Routes.settingsCoach);
    await t.tap(find.byKey(const ValueKey('switch-show-coach')));
    await t.pumpAndSettle();
    expect(repo.current.enabled, isTrue);
    expect(await coachContainer(t).read(coachEnabledProvider.future), isTrue);
  });

  testWidgets('Coach messages is on or off; on means Basic', (t) async {
    final repo = FakeCoachRepository(
      settings: _cloud,
      keys: {CoachProvider.claude: _key},
    );
    final insights = await _pump(t, repo);
    final sw = find.byKey(const ValueKey('switch-coach-messages'));
    await _see(t, sw);
    expect(find.text(InsightCopy.levelTitle), findsOneWidget);
    expect(find.text(InsightCopy.messagesOnBody), findsOneWidget);
    // No Full option, even with a consented cloud engine.
    expect(find.text(InsightLevel.full.label), findsNothing);
    expect(t.widget<Switch>(sw).value, isTrue);
    await t.tap(sw);
    await t.pumpAndSettle();
    expect(insights.levels, [InsightLevel.off]);
    expect(t.widget<Switch>(sw).value, isFalse);
    expect(find.text(InsightCopy.messagesOffBody), findsOneWidget);
    await t.tap(sw);
    await t.pumpAndSettle();
    expect(insights.levels, [InsightLevel.off, InsightLevel.basic]);
  });

  testWidgets('Coach messages starts off when the level is Off', (t) async {
    await _pump(t, FakeCoachRepository(), level: InsightLevel.off);
    final sw = find.byKey(const ValueKey('switch-coach-messages'));
    await _see(t, sw);
    expect(t.widget<Switch>(sw).value, isFalse);
  });

  testWidgets("today's usage: hidden when not tracked, shown when it is", (
    t,
  ) async {
    final repo = FakeCoachRepository(
      settings: _cloud,
      keys: {CoachProvider.claude: _key},
    );
    await _pump(t, repo);
    expect(find.byKey(const ValueKey('row-usage')), findsNothing);

    repo.usage = const CoachUsage(
      provider: CoachProvider.claude,
      requests: 3,
      inputTokens: 11000,
      outputTokens: 1400,
      requestLimit: 50,
      tokenLimit: 200000,
    );
    await _pump(t, repo);
    await _see(t, find.byKey(const ValueKey('row-usage')));
    expect(find.text(InsightCopy.usageTitle), findsOneWidget);
    expect(find.text('3 of 50 questions · 12k of 200k tokens'), findsOneWidget);
    expect(find.text(CoachCopy.usageSpent), findsNothing);
  });

  testWidgets('"Use a backup model when busy": cloud only, on by default, '
      'saved when turned off', (t) async {
    final off = FakeCoachRepository();
    await _pump(t, off);
    expect(find.byKey(const ValueKey('row-backup-models')), findsNothing);

    final repo = FakeCoachRepository(
      settings: _cloud,
      keys: {CoachProvider.claude: _key},
    );
    await _pump(t, repo);
    final row = find.byKey(const ValueKey('switch-backup-models'));
    await _see(t, row);
    expect(find.text(CoachCopy.backupModels), findsOneWidget);
    expect(
      find.text(CoachCopy.backupModelsBody(CoachProvider.claude)),
      findsOneWidget,
    );
    expect(t.widget<Switch>(row).value, isTrue);
    await t.tap(row);
    await t.pumpAndSettle();
    expect((await repo.settings()).backupModels, isFalse);
    expect(t.widget<Switch>(row).value, isFalse);
  });

  test('usage line', () {
    expect(
      usageLine(
        const CoachUsage(
          provider: CoachProvider.gemini,
          requests: 50,
          inputTokens: 1200,
          outputTokens: 300,
          requestLimit: 50,
          tokenLimit: 200000,
        ),
      ),
      '50 of 50 questions · 1.5k of 200k tokens',
    );
  });
}
