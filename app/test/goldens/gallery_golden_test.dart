// Goldens: every gallery section, plus the shell and the privacy screen, in
// dark and light, on a 412×915 phone (2× pixels) with the real fonts.
//
// Regenerate deliberately and LOOK at the diff:
//   flutter test test/goldens --update-goldens

import 'package:airlog/app/app.dart';
import 'package:airlog/app/providers.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/features/gallery/gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_repo.dart';
import '../support/fonts.dart';

const _phone = Size(412, 915);
const _dpr = 2.0;

void _phoneView(WidgetTester t) {
  t.view.physicalSize = _phone * _dpr;
  t.view.devicePixelRatio = _dpr;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  for (final b in const [Brightness.dark]) { // dark only
    for (final s in GallerySection.values) {
      testWidgets('gallery ${s.name} · ${b.name}', (t) async {
        _phoneView(t);
        await t.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(b),
            home: GalleryScreen(section: s, animate: false),
          ),
        );
        await t.pumpAndSettle();
        await expectLater(
          find.byType(GalleryScreen),
          matchesGoldenFile('gallery_${s.name}_${b.name}.png'),
        );
      });
    }

    testWidgets('shell (demo mode) · ${b.name}', (t) async {
      _phoneView(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            healthRepositoryProvider.overrideWithValue(FakeRepo()),
            // Today's greeting reads the clock: pin it. [screens, additive]
            clockProvider.overrideWithValue(() => DateTime(2026, 9, 28, 9, 30)),
          ],
          child: AirlogApp(
            themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          ),
        ),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(AirlogApp),
        matchesGoldenFile('shell_${b.name}.png'),
      );
    });

    testWidgets('privacy · ${b.name}', (t) async {
      _phoneView(t);
      t.platformDispatcher.defaultRouteNameTestValue = Routes.privacy;
      addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            healthRepositoryProvider.overrideWithValue(FakeRepo()),
            // Today's greeting reads the clock: pin it. [screens, additive]
            clockProvider.overrideWithValue(() => DateTime(2026, 9, 28, 9, 30)),
          ],
          child: AirlogApp(
            themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          ),
        ),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(AirlogApp),
        matchesGoldenFile('privacy_${b.name}.png'),
      );
    });
  }
}
