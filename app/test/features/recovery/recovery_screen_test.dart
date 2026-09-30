// Recovery detail: loading, empty store, a full demo day (breakdown, bands,
// readiness, history, explain sheet), calibrating, missing HRV (re-weight
// note), the illness penalty, day switching, and no overflow at 320 px with
// 1.3× text.

import 'package:airlog/design/design.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/recovery/recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_repo.dart';
import '../../support/fonts.dart';
import '../../support/screens_a_fixtures.dart';

Future<void> _pump(
  WidgetTester t, {
  HealthRepository? repo,
  String? selectedDate,
  Size size = const Size(412, 3400),
  double textScale = 1,
}) async {
  phoneView(t, size: size);
  await t.pumpWidget(
    screenApp(
      repo: repo ?? demoRepo(),
      screen: const RecoveryScreen(),
      selectedDate: selectedDate,
      textScale: textScale,
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(ScoreRing.resetPlayed);

  testWidgets('loading: a skeleton hero', (t) async {
    phoneView(t);
    await t.pumpWidget(
      screenApp(repo: PendingRepo(), screen: const RecoveryScreen()),
    );
    await t.pump();
    expect(
      t.widget<ScoreRing>(find.byType(ScoreRing)).state,
      RingState.loading,
    );
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets('empty store', (t) async {
    await _pump(t, repo: FakeRepo());
    expect(find.text('No Recovery yet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('full demo day: breakdown, bands, readiness, history', (t) async {
    await _pump(t);
    expect(find.bySemanticsLabel('Recovery 78 percent'), findsOneWidget);
    expect(find.text('Good · 67–99'), findsOneWidget);
    // The zone only, and the goal as a range (never "at or better than your
    // usual": a green score doesn't mean every signal was).
    expect(
      find.text('You’ve recovered well. Effort goal today: 14–17.'),
      findsOneWidget,
    );
    expect(find.textContaining('better than your usual'), findsNothing);
    // One "usual" everywhere: 47 ms, the raw mean (the engine's detail
    // string uses the same number now; ln only lives inside the z-score).
    expect(find.text('53 ms · usual 47 ms'), findsOneWidget);
    expect(find.text('+28'), findsOneWidget);
    expect(find.text(' / 40'), findsOneWidget);
    expect(find.byType(BaselineBandChart), findsNWidgets(4));
    expect(
      find.textContaining('Last night 53 ms · usual 47 ms'),
      findsOneWidget,
    );
    expect(find.text('Sleep mean RMSSD · Demo data'), findsOneWidget);
    expect(find.textContaining('No usual range here'), findsOneWidget);
    expect(find.text('7-night HRV'), findsOneWidget);
    expect(find.text('Above your usual range'), findsWidgets);
    expect(find.text('Recovery history'), findsOneWidget);
    expect(find.textContaining('Good 15'), findsOneWidget);
    // Nothing missing on a normal demo night.
    expect(find.textContaining('went to your other signals'), findsNothing);
  });

  testWidgets('the explain sheet has the exact formula and weights', (t) async {
    await _pump(t);
    await t.tap(find.bySemanticsLabel('How Recovery works'));
    await t.pumpAndSettle();
    expect(find.text('Recovery 78'), findsOneWidget);
    expect(
      find.textContaining('HRV 40 · resting heart rate 25 · sleep 25'),
      findsOneWidget,
    );
    expect(find.textContaining('e^(−1.1·z)'), findsOneWidget);
    expect(
      find.textContaining(
        'Good (green) ≥ 67 · Fair (yellow) 34–66 · Low (red) < 34',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Plews et al.'), findsOneWidget);
  });

  testWidgets('the readiness card opens the Plews method', (t) async {
    await _pump(t);
    await t.tap(find.text('7-night HRV'));
    await t.pumpAndSettle();
    expect(find.textContaining('smallest worthwhile change'), findsWidgets);
    expect(
      find.textContaining('band = baseline mean ± 0.5 × SD'),
      findsOneWidget,
    );
  });

  testWidgets('calibrating: ring without a number, neutral inputs explained', (
    t,
  ) async {
    await _pump(t, repo: demoRepo(days: 3));
    final ring = t.widget<ScoreRing>(find.byType(ScoreRing));
    expect(ring.state, RingState.calibrating);
    expect(find.text('Learning · night 2 of 14'), findsWidgets);
    expect(
      find.textContaining(
        'still learning your usual HRV and resting heart rate',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Shows up after 7 nights of HRV'),
      findsOneWidget,
    );
  });

  testWidgets('missing HRV: the re-weighting is spelled out', (t) async {
    final repo = await EditedDemoRepo.create(edit: EditedDemoRepo.noHrv);
    await _pump(t, repo: repo);
    expect(
      find.textContaining(
        'No HRV last night, so its 40 points went to your other signals',
      ),
      findsOneWidget,
    );
    expect(find.text('No HRV for this night'), findsOneWidget);
    expect(find.textContaining('No reading last night'), findsOneWidget);
  });

  testWidgets('planted illness: red zone and the skin-temperature penalty', (
    t,
  ) async {
    await _pump(t, selectedDate: kAlertDay);
    expect(find.text('Low · 1–33'), findsOneWidget);
    expect(
      find.text('Skin temperature well above your usual'),
      findsOneWidget,
    );
    expect(find.text('−5'), findsOneWidget);
    expect(find.text('Below your usual range'), findsWidgets);
    expect(find.text('Above your usual range'), findsWidgets);
  });

  testWidgets('day switcher steps back without a skeleton', (t) async {
    await _pump(t);
    await t.tap(find.byIcon(Icons.chevron_left_rounded));
    await t.pump();
    expect(find.byType(SkeletonBox), findsNothing);
    await t.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.bySemanticsLabel('Recovery 63 percent'), findsOneWidget);
  });

  group('no overflow at 320 px and 1.3× text', () {
    for (final (name, date, days) in [
      ('full', null, 90),
      ('alert day', kAlertDay, 90),
      ('calibrating', null, 3),
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

    testWidgets('explain sheet', (t) async {
      await _pump(t, size: const Size(320, 640), textScale: 1.3);
      await t.tap(find.bySemanticsLabel('How Recovery works'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await scrollThrough(t, scrollable: find.byType(Scrollable).last);
    });
  });
}
