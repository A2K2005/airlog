// First launch: the repository reports SyncStatus(syncing, message) and has
// nothing stored yet. Today, Sleep, Strain and Trends show a calm
// PreparingNote under skeleton rings (not a bare skeleton), and the switch to
// real data moves nothing above the cards: the rings and the day switcher
// keep their exact place.

import 'package:airlog/design/design.dart';
import 'package:airlog/features/sleep/sleep_screen.dart';
import 'package:airlog/features/strain/strain_screen.dart';
import 'package:airlog/features/today/today_screen.dart';
import 'package:airlog/features/trends/trends_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_a_fixtures.dart';
import '../../support/seeding_repo.dart';

Future<SeedingRepo> _pumpSeeding(
  WidgetTester t,
  Widget screen, {
  String? message = 'Preparing 90 days of sample data…',
}) async {
  phoneView(t, size: const Size(412, 1600));
  final repo = SeedingRepo(demoRepo(), message: message);
  await t.pumpWidget(screenApp(repo: repo, screen: screen, tab: true));
  await t.pump();
  await t.pump();
  return repo;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(ScoreRing.resetPlayed);

  testWidgets(
    'Today: preparing note above tile skeletons, then data in place',
    (t) async {
      final repo = await _pumpSeeding(t, const TodayScreen());
      expect(find.text('Preparing 90 days of sample data…'), findsOneWidget);
      expect(find.byType(PreparingNote), findsOneWidget);
      expect(find.byType(TileSkeleton), findsWidgets);
      final headerBefore = t.getRect(find.byType(ScreenHeader));

      await repo.finish();
      await t.pumpAndSettle();

      expect(find.byType(PreparingNote), findsNothing);
      expect(find.byType(TileSkeleton), findsNothing);
      expect(find.byType(ReadinessTile), findsOneWidget);
      // No layout jump above the tiles: the header keeps its place.
      expect(t.getRect(find.byType(ScreenHeader)).top, headerBefore.top);
    },
  );

  testWidgets('without a message the note uses the demo copy', (t) async {
    final repo = await _pumpSeeding(t, const TodayScreen(), message: null);
    expect(find.text(PreparingNote.demoTitle), findsOneWidget);
    await repo.finish();
    await t.pumpAndSettle();
  });

  testWidgets('an ordinary load (not seeding) stays a plain skeleton', (
    t,
  ) async {
    phoneView(t);
    await t.pumpWidget(
      screenApp(repo: PendingRepo(), screen: const TodayScreen(), tab: true),
    );
    await t.pump();
    expect(find.byType(PreparingNote), findsNothing);
    expect(find.byType(TileSkeleton), findsWidgets);
  });

  testWidgets('Sleep: preparing note under the skeleton ring, then data', (
    t,
  ) async {
    final repo = await _pumpSeeding(t, const SleepScreen());
    expect(find.byType(PreparingNote), findsOneWidget);
    // The skeleton is the hero tile's own shape, in its place.
    final before = t.getRect(find.byType(TileSkeleton).first);
    await repo.finish();
    await t.pumpAndSettle();
    expect(find.byType(PreparingNote), findsNothing);
    expect(t.getRect(find.byType(SleepSummaryTile)).size, before.size);
    expect(t.getRect(find.byType(SleepSummaryTile)).left, before.left);
  });

  testWidgets('Strain: preparing note under the skeleton ring, then data', (
    t,
  ) async {
    final repo = await _pumpSeeding(t, const StrainScreen());
    expect(find.byType(PreparingNote), findsOneWidget);
    final before = t.getRect(find.byType(TileSkeleton).first);
    await repo.finish();
    await t.pumpAndSettle();
    expect(find.byType(PreparingNote), findsNothing);
    expect(t.getRect(find.byType(ArcStateTile)).size, before.size);
    expect(t.getRect(find.byType(ArcStateTile)).left, before.left);
  });

  testWidgets('Trends: preparing note above the skeleton cards, then data', (
    t,
  ) async {
    final repo = await _pumpSeeding(t, const TrendsScreen());
    expect(find.byType(PreparingNote), findsOneWidget);
    await repo.finish();
    await t.pumpAndSettle();
    expect(find.byType(PreparingNote), findsNothing);
    expect(find.text('Training load'), findsOneWidget);
  });
}
