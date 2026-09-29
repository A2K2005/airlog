// Today: loading keeps the content's shape, the empty store, a full demo day
// (plan, the three score tiles, the vitals), calibrating, missing inputs,
// the planted illness alert, navigation, reload without flicker, pull to
// refresh, More, and no overflow at 320 px with 1.3× text.

import 'package:airlog/app/providers.dart';
import 'package:airlog/app/shell.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/recovery/recovery_screen.dart';
import 'package:airlog/features/sleep/sleep_screen.dart';
import 'package:airlog/features/today/today_screen.dart';
import 'package:airlog/features/today/today_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_repo.dart';
import '../../support/fonts.dart';
import '../../support/screens_a_fixtures.dart';

Future<void> _pump(
  WidgetTester t, {
  HealthRepository? repo,
  DateTime? now,
  // Tall, so the whole list is laid out (ListView builds lazily).
  Size size = const Size(412, 3000),
  double textScale = 1,
}) async {
  phoneView(t, size: size);
  await t.pumpWidget(
    screenApp(
      repo: repo ?? demoRepo(),
      screen: const TodayScreen(),
      tab: true,
      now: now,
      textScale: textScale,
    ),
  );
  await t.pumpAndSettle();
}

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(TodayScreen)));

ReadinessTile _recovery(WidgetTester t) =>
    t.widget<ReadinessTile>(find.byType(ReadinessTile));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('loading: tile skeletons in the content\'s shape, More there', (
    t,
  ) async {
    phoneView(t);
    await t.pumpWidget(
      screenApp(repo: PendingRepo(), screen: const TodayScreen(), tab: true),
    );
    await t.pump();
    expect(find.byType(TileSkeleton), findsWidgets);
    expect(find.byType(ReadinessTile), findsNothing);
    expect(find.bySemanticsLabel('More'), findsOneWidget);
  });

  testWidgets('empty store: explains what to do', (t) async {
    await _pump(t, repo: FakeRepo());
    expect(find.text('No data yet'), findsOneWidget);
    expect(find.text('Check sources'), findsOneWidget);
    expect(find.byType(ReadinessTile), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('full demo day: plan, scores, vitals, one freshness line', (
    t,
  ) async {
    final repo = demoRepo();
    await repo.syncNow();
    await _pump(t, repo: repo);
    // The plan renders first, whatever the planner says.
    expect(find.byType(PlanTile), findsOneWidget);
    final plan = _container(t).read(todayPlanProvider)!;
    expect(find.text(plan.headline), findsOneWidget);
    // The three scores.
    final rec = _recovery(t);
    expect(rec.score, '78');
    expect(rec.status, 'Good');
    expect(rec.valueA, '+13%');
    expect(rec.valueB, '−3 bpm');
    expect(rec.steps, isNotEmpty);
    expect(t.widget<ArcScoreTile>(find.byType(ArcScoreTile)).value, '0.6');
    expect(t.widget<RingScoreTile>(find.byType(RingScoreTile)).value, '89');
    // The vitals, each against its usual.
    expect(find.byType(LineBaselineTile), findsOneWidget);
    expect(find.byType(ArcBaselineTile), findsOneWidget);
    // Respiration, and SpO₂ when it reported.
    expect(find.byType(BandBaselineTile), findsNWidgets(2));
    expect(find.byType(TopArcTile), findsOneWidget);
    expect(find.text('In range'), findsNWidgets(5));
    expect(find.byType(FreshnessLine), findsOneWidget);
    // Calm: no narration card, no journal card, no wall of status cards.
    expect(find.byType(StatusCard), findsNothing);
    expect(find.text('Log tonight\'s factors'), findsNothing);
    expect(find.byType(HealthAlertTile), findsNothing);
  });

  testWidgets('the Recovery tile opens the breakdown', (t) async {
    await _pump(t);
    await t.tap(find.byType(ReadinessTile));
    await t.pumpAndSettle();
    expect(find.byType(RecoveryScreen), findsOneWidget);
  });

  testWidgets('the Sleep and Strain tiles ask the shell for their tab', (
    t,
  ) async {
    await _pump(t);
    await t.tap(find.byType(RingScoreTile));
    await t.pump();
    expect(_container(t).read(tabRequestProvider)?.index, ShellTabs.sleep);
    await t.tap(find.byType(ArcScoreTile));
    await t.pump();
    final r = _container(t).read(tabRequestProvider)!;
    expect(r.index, ShellTabs.strain);
    expect(r.seq, 2);
  });

  testWidgets('a vital opens its 30-night band chart', (t) async {
    await _pump(t);
    await t.tap(find.byType(ArcBaselineTile));
    await t.pumpAndSettle();
    expect(find.text('LAST 30 NIGHTS'), findsOneWidget);
    expect(find.byType(BaselineBandChart), findsOneWidget);
  });

  testWidgets('calibrating (third night): no score, learning, progress', (
    t,
  ) async {
    await _pump(t, repo: demoRepo(days: 3));
    final rec = _recovery(t);
    expect(rec.score, DotMatrixNumber.missing);
    expect(rec.status, 'Learning');
    final prog = t.widget<ProgressTile>(find.byType(ProgressTile));
    expect(prog.title, 'Learning your normal');
    expect(prog.unit, 'of 14 nights');
  });

  testWidgets('missing HRV: the score keeps its basis, a data note', (
    t,
  ) async {
    final repo = await EditedDemoRepo.create(edit: EditedDemoRepo.noHrv);
    await _pump(t, repo: repo);
    expect(_recovery(t).score, isNot(DotMatrixNumber.missing));
    expect(_recovery(t).valueA, '--');
    expect(find.textContaining('Data notes'), findsOneWidget);
  });

  testWidgets('no HRV and no resting HR: no score, said plainly', (t) async {
    final repo = await EditedDemoRepo.create(edit: EditedDemoRepo.noNightly);
    await _pump(t, repo: repo);
    final rec = _recovery(t);
    expect(rec.score, DotMatrixNumber.missing);
    expect(rec.status, 'No data');
    expect(find.textContaining('Data notes'), findsOneWidget);
  });

  testWidgets('planted illness: the alert tile names the metrics', (t) async {
    final repo = await EditedDemoRepo.asOfDay(kAlertDay);
    await _pump(t, repo: repo);
    expect(find.byType(HealthAlertTile), findsOneWidget);
    expect(find.text('Above usual'), findsWidgets);
    await t.tap(find.byType(HealthAlertTile));
    await t.pumpAndSettle();
    expect(find.textContaining('not a diagnosis'), findsOneWidget);
  });

  testWidgets('a repository revision (sync) keeps the screen, no flicker', (
    t,
  ) async {
    final repo = demoRepo();
    await _pump(t, repo: repo);
    await repo.saveJournal(
      (await repo.journal(kToday)).toggle(JournalFactor.alcohol),
    );
    await t.pump();
    expect(find.byType(TileSkeleton), findsNothing);
    await t.pumpAndSettle();
    expect(find.byType(ReadinessTile), findsOneWidget);
  });

  testWidgets('pull to refresh syncs and updates the freshness line', (
    t,
  ) async {
    final repo = demoRepo();
    await _pump(t, repo: repo, size: kPhone);
    // One subtle line per source app.
    expect(find.text('Sample data · just now'), findsOneWidget);
    await t.fling(find.byType(ScreenHeader), const Offset(0, 400), 1000);
    await t.pump();
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    await t.pumpAndSettle();
    expect(repo.syncStatus.lastSyncAt, kNow);
    expect(find.byType(FreshnessLine), findsOneWidget);
  });

  testWidgets('More lists Coach, Journal, Live workout and Settings', (
    t,
  ) async {
    await _pump(t);
    await t.tap(find.bySemanticsLabel('More'));
    await t.pumpAndSettle();
    for (final label in ['Coach', 'Journal', 'Live workout', 'Settings']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Pulse Age'), findsNothing);
  });

  testWidgets('inside the real shell, the Sleep tile opens the Sleep tab', (
    t,
  ) async {
    phoneView(t, size: const Size(412, 3000));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          healthRepositoryProvider.overrideWithValue(demoRepo()),
          clockProvider.overrideWithValue(() => kNow),
        ],
        child: MaterialApp(theme: buildTheme(), home: const AppShell()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(SleepScreen), findsNothing);
    await t.tap(find.byType(RingScoreTile));
    await t.pumpAndSettle();
    expect(find.byType(SleepScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing); // offstage now
  });

  group('mapper', () {
    test('ring states follow the calibration rule', () async {
      final full = (await demoRepo().day(kToday))!.result;
      expect(TodayMapper.recoveryRing(full).state, RingState.measured);
      final early = (await demoRepo(days: 3).day(kToday))!.result;
      expect(TodayMapper.recoveryRing(early).state, RingState.calibrating);
      final mid = (await demoRepo(days: 9).day(kToday))!.result;
      expect(mid.calibration.established, isFalse);
      expect(TodayMapper.recoveryRing(mid).state, RingState.provisional);
    });

    test('recovery steps: six days, oldest first, signed changes', () async {
      final repo = demoRepo();
      final window = await repo.range('2026-08-30', kToday);
      final steps = TodayMapper.recoverySteps(window, kToday);
      expect(steps.length, 6);
      for (var i = 1; i < steps.length; i++) {
        final d = (steps[i].value - steps[i - 1].value).round();
        expect(
          steps[i].delta,
          d > 0 ? '+$d' : (d < 0 ? '−${-d}' : '0'),
        );
      }
    });
  });

  group('no overflow at 320 px and 1.3× text', () {
    testWidgets('today', (t) async {
      await _pump(
        t,
        size: const Size(320, 640),
        textScale: 1.3,
        now: kEvening,
      );
      expect(t.takeException(), isNull);
      await scrollThrough(t);
    });

    testWidgets('calibrating', (t) async {
      await _pump(
        t,
        repo: demoRepo(days: 3),
        size: const Size(320, 640),
        textScale: 1.3,
      );
      await scrollThrough(t);
    });
  });
}
