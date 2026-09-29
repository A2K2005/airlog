// Goldens: Recovery detail in demo mode at a fixed clock, 412×915 plus a
// full-length render.
//
//   flutter test test/features/recovery --update-goldens

import 'package:airlog/design/design.dart';
import 'package:airlog/features/recovery/recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_a_fixtures.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(ScoreRing.resetPlayed);

  for (final b in const [Brightness.dark]) { // dark only
    testWidgets('recovery · ${b.name}', (t) async {
      phoneView(t);
      await t.pumpWidget(
        screenApp(
          repo: demoRepo(),
          screen: const RecoveryScreen(),
          brightness: b,
        ),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(RecoveryScreen),
        matchesGoldenFile('../../goldens/screens/recovery_${b.name}.png'),
      );
    });

    testWidgets('recovery full length · ${b.name}', (t) async {
      phoneView(t, size: const Size(412, 3000));
      await t.pumpWidget(
        screenApp(
          repo: demoRepo(),
          screen: const RecoveryScreen(),
          brightness: b,
        ),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(RecoveryScreen),
        matchesGoldenFile('../../goldens/screens/recovery_full_${b.name}.png'),
      );
    });
  }
}
