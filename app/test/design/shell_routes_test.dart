// The shell and the router: tabs, the settings gear, the demo badge, every
// named route, and cold starts on a deep route (Health Connect opens
// '/privacy').

import 'dart:async';

import 'package:airlog/app/app.dart';
import 'package:airlog/app/providers.dart';
import 'package:airlog/app/routes.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/privacy/privacy_screen.dart';
import 'package:airlog/features/settings/settings_screen.dart';
import 'package:airlog/features/settings/sources_screen.dart';
import 'package:airlog/features/sleep/sleep_screen.dart';
import 'package:airlog/features/strain/strain_screen.dart';
import 'package:airlog/features/today/today_screen.dart';
import 'package:airlog/features/trends/trends_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_repo.dart';

Widget _app({DataMode mode = DataMode.demo}) => ProviderScope(
  overrides: [healthRepositoryProvider.overrideWithValue(FakeRepo(mode: mode))],
  child: const AirlogApp(themeMode: ThemeMode.dark),
);

void main() {
  testWidgets('cold start on /privacy shows the policy, back goes to Today', (
    t,
  ) async {
    t.platformDispatcher.defaultRouteNameTestValue = Routes.privacy;
    addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    expect(find.byType(PrivacyScreen), findsOneWidget);
    expect(
      find.text('Private by default. Cloud only by choice.'),
      findsOneWidget,
    );
    await t.scrollUntilVisible(
      find.text('What Airlog reads from Health Connect'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.scrollUntilVisible(
      find.text('Not medical advice'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Not medical advice'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('cold start on a nested route builds every prefix', (t) async {
    t.platformDispatcher.defaultRouteNameTestValue = Routes.sources;
    addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    expect(find.byType(SourcesScreen), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('every named route builds', (t) async {
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    for (final name in routeTable.keys) {
      if (name == Routes.home) continue;
      unawaited(nav.pushNamed(name));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: name);
      nav.pop();
      await t.pumpAndSettle();
    }
    expect(
      routeTable.keys,
      containsAll(<String>[
        Routes.recovery,
        Routes.live,
        Routes.journal,
        Routes.settings,
        Routes.sources,
        Routes.profile,
        Routes.syncLog,
        Routes.methodology,
        Routes.licenses,
        Routes.diagnostics,
        Routes.onboarding,
        Routes.privacy,
        Routes.gallery,
      ]),
    );
  });

  testWidgets('tabs build lazily, keep state, and switch without animation', (
    t,
  ) async {
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(SleepScreen, skipOffstage: false), findsNothing);
    await t.tap(find.text('Sleep'));
    await t.pump();
    expect(find.byType(SleepScreen), findsOneWidget);
    // Today stays mounted (IndexedStack), just offstage.
    expect(find.byType(TodayScreen, skipOffstage: false), findsOneWidget);
    final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.animationDuration, Duration.zero);
  });

  testWidgets('More opens settings, journal and live', (t) async {
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('More'));
    await t.pumpAndSettle();
    expect(find.text('Journal'), findsOneWidget);
    expect(find.text('Live workout'), findsOneWidget);
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the Sample data chip only in demo mode', (t) async {
    await t.pumpWidget(_app(mode: DataMode.demo));
    await t.pumpAndSettle();
    expect(find.byType(SampleDataChip), findsWidgets);
    await t.pumpWidget(_app(mode: DataMode.live));
    await t.pumpAndSettle();
    expect(find.byType(SampleDataChip), findsNothing);
  });

  testWidgets('the selected tab survives process death (restoration)', (
    t,
  ) async {
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    await t.tap(find.text('Strain'));
    await t.pumpAndSettle();
    expect(find.byType(StrainScreen), findsOneWidget);
    await t.restartAndRestore();
    await t.pumpAndSettle();
    expect(find.byType(StrainScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing); // built lazily, offstage
  });

  testWidgets('every pushed screen carries the Sample data chip in demo', (
    t,
  ) async {
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    for (final name in [
      Routes.recovery,
      Routes.journal,
      Routes.live,
      Routes.settings,
      Routes.sources,
      Routes.profile,
      Routes.coach,
    ]) {
      unawaited(nav.pushNamed(name));
      await t.pumpAndSettle();
      expect(find.byType(SampleDataChip), findsWidgets, reason: name);
      nav.pop();
      await t.pumpAndSettle();
    }
  });

  testWidgets('a tab request by id opens that tab', (t) async {
    late WidgetRef ref;
    await t.pumpWidget(
      ProviderScope(
        overrides: [healthRepositoryProvider.overrideWithValue(FakeRepo())],
        child: Consumer(
          builder: (c, r, _) {
            ref = r;
            return const AirlogApp();
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    ref.read(tabRequestProvider.notifier).go(ShellTabs.trends);
    await t.pumpAndSettle();
    expect(find.byType(TrendsScreen), findsOneWidget);
  });
}
