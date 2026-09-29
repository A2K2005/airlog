// Goldens: Today in demo mode at a fixed clock, 412×915 (the first screen)
// plus a full-length render of the whole scroll for review.
//
//   flutter test test/features/today --update-goldens

import 'package:airlog/design/design.dart';
import 'package:airlog/features/today/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_a_fixtures.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(ScoreRing.resetPlayed);

  for (final b in const [Brightness.dark]) { // dark only
    testWidgets('today · ${b.name}', (t) async {
      phoneView(t);
      final repo = demoRepo();
      await repo.syncNow();
      await t.pumpWidget(
        screenApp(
          repo: repo,
          screen: const TodayScreen(),
          tab: true,
          brightness: b,
        ),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(TodayScreen),
        matchesGoldenFile('../../goldens/screens/today_${b.name}.png'),
      );
    });

    testWidgets('today full length · ${b.name}', (t) async {
      phoneView(t, size: const Size(412, 2000));
      final repo = demoRepo();
      await repo.syncNow();
      await t.pumpWidget(
        screenApp(
          repo: repo,
          screen: const TodayScreen(),
          tab: true,
          brightness: b,
        ),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(TodayScreen),
        matchesGoldenFile('../../goldens/screens/today_full_${b.name}.png'),
      );
    });
  }
}
