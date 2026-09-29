// Goldens: Sleep in demo mode at a fixed clock, 412×915 plus a
// full-length render.
//
//   flutter test test/features/sleep --update-goldens

import 'package:airlog/design/design.dart';
import 'package:airlog/features/sleep/sleep_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_a_fixtures.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(ScoreRing.resetPlayed);

  for (final b in const [Brightness.dark]) { // dark only
    testWidgets('sleep · ${b.name}', (t) async {
      phoneView(t);
      await t.pumpWidget(
        screenApp(
          repo: demoRepo(),
          screen: const SleepScreen(),
          tab: true,
          brightness: b,
        ),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(SleepScreen),
        matchesGoldenFile('../../goldens/screens/sleep_${b.name}.png'),
      );
    });

    testWidgets('sleep full length · ${b.name}', (t) async {
      phoneView(t, size: const Size(412, 2000));
      await t.pumpWidget(
        screenApp(
          repo: demoRepo(),
          screen: const SleepScreen(),
          tab: true,
          brightness: b,
        ),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(SleepScreen),
        matchesGoldenFile('../../goldens/screens/sleep_full_${b.name}.png'),
      );
    });
  }
}
