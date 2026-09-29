import 'package:airlog/design/design.dart';
import 'package:airlog/domain/results.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/features/strain/strain_screen.dart';
import 'package:airlog/features/strain/strain_view_model.dart';
import 'package:airlog/features/strain/widgets/strain_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(ScoreRing.resetPlayed);

  testWidgets('full day: ring, target, zones and workouts', (t) async {
    final repo = ScreensBRepo.demo();
    await pumpB(
      t,
      const StrainScreen(),
      repo: repo,
      tab: true,
      selectedDate: '2026-09-21',
      size: const Size(412, 2600),
    );
    await t.pumpAndSettle();
    expect(find.text('Strain'), findsWidgets);
    expect(find.byType(ArcStateTile), findsOneWidget);
    expect(find.byType(ZoneBarTile), findsOneWidget);
    // PR #1 dropped the duplicate strain ring and TARGET block: one primary
    // score tile, then the target basis.
    expect(find.text('Target basis'), findsOneWidget);
    expect(find.text('Heart rate by zone'), findsOneWidget);
    expect(find.textContaining('Finished'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Workouts'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('TRIMP'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('workout rows show distance and calories only when recorded', (
    t,
  ) async {
    Future<void> row(Workout w) => pumpB(
      t,
      Scaffold(
        body: Center(
          child: WorkoutCard(row: StrainWorkoutRow(workout: w)),
        ),
      ),
      repo: ScreensBRepo.demo(),
    );
    final start = DateTime(2026, 9, 28, 7);
    await row(
      Workout(
        id: 'a',
        name: 'Run',
        start: start,
        end: start.add(const Duration(minutes: 40)),
        distanceM: 5210,
        calories: 411.6,
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('5.21 km'), findsOneWidget);
    expect(find.text('412 kcal'), findsOneWidget);
    expect(find.text('DISTANCE'), findsOneWidget);

    await row(
      Workout(
        id: 'b',
        name: 'Walk',
        start: start,
        end: start.add(const Duration(minutes: 20)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('DISTANCE'), findsNothing);
    expect(find.text('CALORIES'), findsNothing);
  });

  testWidgets('a day with no input shows the status card, not a 0 strain', (
    t,
  ) async {
    final repo = ScreensBRepo.demo();
    final day = noneDay();
    expect(day.result.strain!.method, StrainMethod.none);
    repo.dayOverride[kToday] = day;
    await pumpB(t, const StrainScreen(), repo: repo, tab: true);
    await t.pumpAndSettle();
    expect(find.text('No Strain score'), findsOneWidget);
    expect(find.text('Heart rate by zone'), findsNothing);
    expect(find.text('0.0'), findsNothing);
    // No 0–21 number without heart rate: the arc stays empty.
    final tile = t.widget<ArcStateTile>(find.byType(ArcStateTile));
    expect(tile.value, DotMatrixNumber.missing);
    expect(tile.progress, isNull);
  });

  testWidgets('empty store shows an empty state, not a zero', (t) async {
    final repo = ScreensBRepo.demo()..emptyStore = true;
    await pumpB(t, const StrainScreen(), repo: repo, tab: true);
    await t.pumpAndSettle();
    expect(find.text('No strain yet'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
  });

  testWidgets('loading shows a skeleton first', (t) async {
    final repo = ScreensBRepo.demo();
    await pumpB(t, const StrainScreen(), repo: repo, tab: true);
    expect(find.byType(TileSkeleton), findsWidgets);
    await t.pumpAndSettle();
    expect(find.byType(TileSkeleton), findsNothing);
  });

  testWidgets('explain sheet shows the engine constants', (t) async {
    final repo = ScreensBRepo.demo();
    await pumpB(
      t,
      const StrainScreen(),
      repo: repo,
      tab: true,
      selectedDate: '2026-09-21',
    );
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.info_outline_rounded).first);
    await t.pumpAndSettle();
    expect(
      find.text('Heart-rate zones (Karvonen)'.toUpperCase()),
      findsOneWidget,
    );
    expect(find.textContaining('÷ 450'), findsOneWidget);
    expect(find.text('Demanding'), findsOneWidget);
  });

  testWidgets('no overflow at 320 px and text scale 1.3', (t) async {
    final repo = ScreensBRepo.demo();
    await pumpB(
      t,
      const StrainScreen(),
      repo: repo,
      tab: true,
      size: kSmall,
      textScale: 1.3,
      selectedDate: '2026-09-21',
    );
    await t.pumpAndSettle();
    await scrollThrough(t);
  });

  for (final b in const [Brightness.dark]) {
    // dark only
    testWidgets('golden · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo();
      await pumpB(
        t,
        const StrainScreen(),
        repo: repo,
        tab: true,
        brightness: b,
        selectedDate: '2026-09-21',
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/strain_${b.name}.png'),
      );
    });

    testWidgets('golden scrolled · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo();
      await pumpB(
        t,
        const StrainScreen(),
        repo: repo,
        tab: true,
        brightness: b,
        selectedDate: '2026-09-21',
      );
      await t.pumpAndSettle();
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/strain_workouts_${b.name}.png',
        ),
      );
    });
  }
}
