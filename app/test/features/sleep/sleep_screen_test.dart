// Sleep: loading, empty store, a full demo night (slept vs need and its
// parts, bedtime, hypnogram, stages, consistency 14/30), the need explain
// sheet, a night with no sleep, a past day, and no overflow at 320 px with
// 1.3× text.

import 'package:airlog/design/design.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/sleep/sleep_screen.dart';
import 'package:airlog/features/sleep/widgets/sleep_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_repo.dart';
import '../../support/fonts.dart';
import '../../support/screens_a_fixtures.dart';

Future<void> _pump(
  WidgetTester t, {
  HealthRepository? repo,
  String? selectedDate,
  Size size = const Size(412, 2600),
  double textScale = 1,
}) async {
  phoneView(t, size: size);
  await t.pumpWidget(
    screenApp(
      repo: repo ?? demoRepo(),
      screen: const SleepScreen(),
      tab: true,
      selectedDate: selectedDate,
      textScale: textScale,
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(ScoreRing.resetPlayed);

  testWidgets('loading: skeletons', (t) async {
    phoneView(t);
    await t.pumpWidget(
      screenApp(repo: PendingRepo(), screen: const SleepScreen(), tab: true),
    );
    await t.pump();
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.text('Sleep'), findsOneWidget);
  });

  testWidgets('empty store', (t) async {
    await _pump(t, repo: FakeRepo());
    expect(find.text('No sleep yet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('full night: slept vs need, parts, bedtime, stages', (t) async {
    await _pump(t);
    // PR #1 dropped the duplicate performance ring: the summary tile carries
    // the score.
    expect(
      find.bySemanticsLabel(RegExp('performance 89 percent')),
      findsOneWidget,
    );
    // The slept / target line lived in the removed ring block; the summary
    // tile states both (its label above).
    expect(find.text('Debt after the night 58m'), findsOneWidget);
    expect(find.text('Baseline 7h 36m'), findsOneWidget);
    expect(find.text('Debt share 3m'), findsOneWidget);
    expect(find.text('Strain boost 12m'), findsOneWidget);
    expect(
      find.text('Aim to be asleep by 23:35', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('you usually wake at 07:28'), findsOneWidget);
    expect(find.byType(HypnogramChart), findsOneWidget);
    expect(find.byType(SleepSummaryTile), findsOneWidget);
    expect(find.text('2h 31m'), findsOneWidget);
    expect(find.text('95 %'), findsOneWidget);
    expect(find.text('43 % against your previous 4 nights'), findsOneWidget);
    expect(find.byType(ScatterConsistency), findsOneWidget);
  });

  testWidgets('consistency range switches 14 → 30 nights without reload', (
    t,
  ) async {
    await _pump(t);
    ScatterConsistency chart() =>
        t.widget<ScatterConsistency>(find.byType(ScatterConsistency));
    expect(chart().nights, hasLength(14));
    await t.tap(find.text('30D'));
    await t.pump();
    expect(find.byType(SkeletonBox), findsNothing);
    await t.pumpAndSettle();
    expect(chart().nights, hasLength(30));
  });

  testWidgets('the need explain sheet shows this night\'s sum', (t) async {
    await _pump(t);
    await t.tap(find.text('How the target is worked out'));
    await t.pumpAndSettle();
    expect(find.text('Sleep target'), findsWidgets);
    expect(find.textContaining('= target 7h 51m'), findsOneWidget);
    expect(
      find.textContaining('clamp((strain − 8) / 13, 0, 1) × 45m'),
      findsOneWidget,
    );
  });

  testWidgets('no sleep recorded: the honest card, debt carried', (t) async {
    final repo = await EditedDemoRepo.create(edit: EditedDemoRepo.noSleep);
    await _pump(t, repo: repo);
    expect(find.text('No sleep recorded'), findsOneWidget);
    expect(find.textContaining('carried forward unchanged'), findsWidgets);
    expect(find.byType(HypnogramChart), findsNothing);
    expect(find.byType(ScatterConsistency), findsOneWidget);
  });

  testWidgets('a past night has no "tonight" card', (t) async {
    await _pump(t, selectedDate: kAlertDay);
    expect(
      find.textContaining('Aim to be asleep', findRichText: true),
      findsNothing,
    );
    expect(find.text('Latest'), findsOneWidget);
    expect(find.byType(HypnogramChart), findsOneWidget);
  });

  testWidgets('a day with a nap lists it and counts it', (t) async {
    await _pump(t, selectedDate: '2026-08-30');
    expect(find.byType(NapsCard), findsOneWidget);
    expect(find.text('15:28–16:00'), findsOneWidget);
    expect(find.text('29m asleep'), findsOneWidget);
    expect(find.textContaining('includes 29m of naps'), findsOneWidget);
  });

  group('no overflow at 320 px and 1.3× text', () {
    for (final (name, date, days) in [
      ('full', null, 90),
      ('past night', kAlertDay, 90),
      ('first nights', null, 3),
      ('nap day', '2026-08-30', 90),
    ]) {
      testWidgets(name, (t) async {
        await _pump(
          t,
          repo: demoRepo(days: days),
          selectedDate: date,
          size: const Size(320, 640),
          textScale: 1.3,
        );
        expect(t.takeException(), isNull);
        await scrollThrough(t);
      });
    }
  });
}
