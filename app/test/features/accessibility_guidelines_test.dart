// Android accessibility guidelines on the tabs and the main pushed screens,
// with real demo data:
// every tap target ≥ 48 dp, every tappable node labelled, text contrast.

import 'package:airlog/design/design.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/journal/journal_screen.dart';
import 'package:airlog/features/live/live_screen.dart';
import 'package:airlog/features/onboarding/onboarding_copy.dart';
import 'package:airlog/features/onboarding/onboarding_screen.dart';
import 'package:airlog/features/settings/settings_screen.dart';
import 'package:airlog/features/settings/sources_screen.dart';
import 'package:airlog/features/sleep/sleep_screen.dart';
import 'package:airlog/features/strain/strain_screen.dart';
import 'package:airlog/features/today/today_screen.dart';
import 'package:airlog/features/trends/trends_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fonts.dart';
import '../support/screens_b_fixtures.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(ScoreRing.resetPlayed);

  final screens = <String, (Widget, bool)>{
    'Today': (const TodayScreen(), true),
    'Sleep': (const SleepScreen(), true),
    'Strain': (const StrainScreen(), true),
    'Trends': (const TrendsScreen(), true),
    'Settings': (const SettingsScreen(), false),
    'Sources': (const SourcesScreen(), false),
    'Onboarding': (const OnboardingScreen(), false),
    'Journal': (const JournalScreen(), false),
    'Live': (const LiveScreen(), false),
  };

  for (final MapEntry(key: name, value: (screen, tab)) in screens.entries) {
    // Dark only: the app is dark only.
    for (final b in const [Brightness.dark]) {
      testWidgets('$name · ${b.name}: tap targets, labels, contrast', (
        t,
      ) async {
        final handle = t.ensureSemantics();
        await pumpB(
          t,
          screen,
          repo: ScreensBRepo.demo(),
          tab: tab,
          brightness: b,
        );
        await t.pumpAndSettle();
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(t, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }

  // Onboarding past its first step: the glow panels, the birth-year sheet
  // and "Not connected".
  testWidgets('Onboarding steps 2–3b · dark: tap targets, labels, contrast', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    final repo = ScreensBRepo.demo()
      ..hcAfterRequest = const HcPermissionState(
        availability: HcAvailability.available,
        granted: [],
        missing: ['HEART_RATE'],
      );
    await pumpB(t, const OnboardingScreen(), repo: repo);
    await t.pumpAndSettle();
    Future<void> check(String where) async {
      await expectLater(
        t,
        meetsGuideline(androidTapTargetGuideline),
        reason: where,
      );
      await expectLater(
        t,
        meetsGuideline(labeledTapTargetGuideline),
        reason: where,
      );
      await expectLater(t, meetsGuideline(textContrastGuideline), reason: where);
    }

    await t.tap(find.text(OnboardingCopy.getStarted));
    await t.pumpAndSettle();
    await check('works with');
    await t.tap(find.text(OnboardingCopy.next));
    await t.pumpAndSettle();
    await check('choose');
    await t.tap(find.text(OnboardingCopy.birthYearAdd));
    await t.pumpAndSettle();
    await check('birth-year sheet');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await tapOn(t, find.text(OnboardingCopy.trackerTitle));
    await t.pumpAndSettle();
    await check('not connected');
    handle.dispose();
  });
}
