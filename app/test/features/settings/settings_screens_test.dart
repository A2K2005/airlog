import 'package:airlog/features/settings/widgets/hold_to_confirm.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/settings/profile_screen.dart';
import 'package:airlog/features/settings/settings_screen.dart';
import 'package:airlog/features/settings/sources_screen.dart';
import 'package:airlog/features/settings/sync_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

List<SourceStatus> _configured({
  bool ghConnected = false,
  bool hcConnected = true,
}) => [
  const SourceStatus(
    kind: SourceKind.demo,
    available: true,
    enabled: false,
    connected: true,
    detail: 'Synthetic Fitbit Air',
  ),
  SourceStatus(
    kind: SourceKind.healthConnect,
    available: true,
    enabled: true,
    connected: hcConnected,
    detail: hcConnected
        ? 'Reading 9 data types from Fitbit'
        : 'Grant access in Health Connect to read your band',
    lastSyncAt: DateTime(2026, 9, 28, 19, 12),
  ),
  SourceStatus(
    kind: SourceKind.googleHealthApi,
    available: true,
    enabled: ghConnected,
    connected: ghConnected,
    detail: ghConnected
        ? 'Signed in: SpO₂, deep-sleep HRV, respiratory rate, skin temperature'
        : 'Sign in to add SpO₂ and deep-sleep HRV',
    beta: true,
  ),
  const SourceStatus(
    kind: SourceKind.ble,
    available: true,
    enabled: true,
    connected: false,
    detail: 'Live heart rate while the band shares it over Bluetooth',
  ),
  const SourceStatus(
    kind: SourceKind.context,
    available: true,
    enabled: false,
    connected: true,
    detail: 'Weight and steps from other apps in Health Connect (never mixed into band baselines)',
  ),
  const SourceStatus(
    kind: SourceKind.takeout,
    available: false,
    enabled: false,
    connected: false,
    detail: 'Coming later: import a Google Takeout export',
  ),
];

const _grantedHc = HcPermissionState(
  availability: HcAvailability.available,
  granted: [
    'HEART_RATE',
    'HEART_RATE_VARIABILITY_RMSSD',
    'RESTING_HEART_RATE',
    'SLEEP_SESSION',
    'WORKOUT',
    'STEPS',
    'RESPIRATORY_RATE',
    'VO2_MAX',
    'SKIN_TEMPERATURE',
  ],
  missing: ['WEIGHT'],
  historyGranted: true,
);

List<SyncLogEntry> _log() => [
  SyncLogEntry(
    at: DateTime(2026, 9, 28, 19, 12),
    source: SourceKind.healthConnect,
    dataType: 'HEART_RATE',
    status: 'ok',
    records: 1312,
  ),
  SyncLogEntry(
    at: DateTime(2026, 9, 28, 19, 12),
    source: SourceKind.healthConnect,
    dataType: 'SLEEP_SESSION',
    status: 'ok',
    records: 1,
  ),
  SyncLogEntry(
    at: DateTime(2026, 9, 28, 19, 12),
    source: SourceKind.healthConnect,
    dataType: 'SKIN_TEMPERATURE',
    status: 'denied',
    message: 'Permission not granted',
  ),
  SyncLogEntry(
    at: DateTime(2026, 9, 28, 18, 40),
    source: SourceKind.googleHealthApi,
    dataType: 'OXYGEN_SATURATION',
    status: 'error',
    message: 'HTTP 401: token expired, sign in again',
  ),
  SyncLogEntry(
    at: DateTime(2026, 9, 28, 7, 5),
    source: SourceKind.healthConnect,
    dataType: 'WEIGHT',
    status: 'empty',
  ),
];

void main() {
  setUpAll(loadAppFonts);

  group('Settings', () {
    testWidgets('mode switch, export and navigation call the repository', (
      t,
    ) async {
      final repo = ScreensBRepo.demo();
      final sharer = RecordingSharer();
      await pumpB(t, const SettingsScreen(), repo: repo, sharer: sharer);
      await t.pumpAndSettle();
      expect(find.text('Data mode'), findsOneWidget);
      await t.tap(find.text('Live'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('setMode:live'));

      await tapOn(t, find.text('Export'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('exportAll'));
      expect(sharer.shared.single, repo.export.files);
      expect(find.textContaining('Exported 2 files'), findsOneWidget);
    });

    Future<Finder> holdButton(WidgetTester t) async {
      final hold = find.text('Hold to delete').first;
      await t.scrollUntilVisible(
        hold,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(hold);
      await t.pumpAndSettle();
      return hold;
    }

    testWidgets('delete needs a full 2-second hold; the hold is the confirm', (
      t,
    ) async {
      final repo = ScreensBRepo.demo();
      await pumpB(t, const SettingsScreen(), repo: repo);
      await t.pumpAndSettle();
      final hold = await holdButton(t);

      // A short tap only explains.
      await t.tap(hold);
      await t.pump();
      expect(find.textContaining('Press and hold'), findsOneWidget);
      expect(repo.calls, isNot(contains('wipeData')));
      await t.pumpAndSettle();

      // Releasing early does nothing.
      var g = await t.startGesture(t.getCenter(hold));
      await t.pump(const Duration(milliseconds: 150));
      await t.pump(const Duration(milliseconds: 900));
      await g.up();
      await t.pumpAndSettle();
      expect(repo.calls, isNot(contains('wipeData')));

      // A full hold deletes, with no second question.
      g = await t.startGesture(t.getCenter(hold));
      await t.pump(const Duration(milliseconds: 150));
      await t.pump(const Duration(milliseconds: 2100));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(find.text('Delete all data?'), findsNothing);
      expect(repo.calls, contains('wipeData'));
      // PR #1: says exactly what went (settings and keys stay).
      expect(
        find.text('Stored records deleted. Settings and keys kept.'),
        findsOneWidget,
      );
    });

    testWidgets('fill: 2 s linear while pressed, 200 ms ease-out on release', (
      t,
    ) async {
      await pumpB(t, const SettingsScreen(), repo: ScreensBRepo.demo());
      await t.pumpAndSettle();
      final hold = await holdButton(t);
      double fill() {
        final clip = t.widget<ClipRect>(
          find.descendant(
            of: find.byType(HoldToConfirm),
            matching: find.byType(ClipRect),
          ),
        );
        final box = t.getSize(find.byType(HoldToConfirm));
        return clip.clipper!.getClip(box).width / box.width;
      }

      final g = await t.startGesture(t.getCenter(hold));
      // The tap-down arrives after the platform's press delay (100 ms).
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      final a = fill();
      await t.pump(const Duration(milliseconds: 500));
      final b = fill();
      // Linear: equal time, equal progress (a quarter of 2 s each).
      expect(a, closeTo(.25, .03));
      expect(b - a, closeTo(.25, .03));

      await g.up();
      await t.pump(); // the release starts on this frame
      await t.pump(const Duration(milliseconds: 40));
      final early = fill();
      await t.pump(const Duration(milliseconds: 170));
      // Ease-out: most of the way back in the first fifth of the release,
      // and fully empty within 200 ms.
      expect(early, lessThan(b * .6));
      expect(fill(), 0);
    });

    testWidgets('the 2-second hold survives Android "Remove animations"', (
      t,
    ) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = ScreensBRepo.demo();
      await pumpB(t, const SettingsScreen(), repo: repo);
      await t.pumpAndSettle();
      final hold = await holdButton(t);

      var g = await t.startGesture(t.getCenter(hold));
      await t.pump(const Duration(milliseconds: 150));
      await t.pump(const Duration(milliseconds: 1000));
      await t.pump();
      expect(repo.calls, isNot(contains('wipeData')));
      await g.up();
      await t.pumpAndSettle();

      g = await t.startGesture(t.getCenter(hold));
      await t.pump(const Duration(milliseconds: 150));
      await t.pump(const Duration(milliseconds: 2100));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(repo.calls, contains('wipeData'));
    });

    testWidgets('with a screen reader, a tap opens the confirm dialog', (
      t,
    ) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = ScreensBRepo.demo();
      await pumpB(t, const SettingsScreen(), repo: repo);
      await t.pumpAndSettle();
      final hold = await holdButton(t);

      await t.tap(hold);
      await t.pumpAndSettle();
      expect(find.text('Delete all data?'), findsOneWidget);
      expect(repo.calls, isNot(contains('wipeData')));
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('wipeData'));
      // PR #1: says exactly what went (settings and keys stay).
      expect(
        find.text('Stored records deleted. Settings and keys kept.'),
        findsOneWidget,
      );
    });

    testWidgets('the delete card is the label the privacy policy names', (
      t,
    ) async {
      await pumpB(t, const SettingsScreen(), repo: ScreensBRepo.demo());
      await t.pumpAndSettle();
      await holdButton(t);
      expect(find.text(SettingsCopy.deleteTitle), findsOneWidget);
      expect(find.text(SettingsCopy.exportTitle), findsOneWidget);
      expect(SettingsCopy.deletePath, 'Settings → Delete all data');
    });

    testWidgets('shows the algorithm and app versions', (t) async {
      await pumpB(t, const SettingsScreen(), repo: ScreensBRepo.demo());
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Algorithm version'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('v3'), findsOneWidget); // PR #1: algorithm v3
      expect(find.text('App version'), findsOneWidget);
    });

    testWidgets('no overflow at 320 px and text scale 1.3', (t) async {
      await pumpB(
        t,
        const SettingsScreen(),
        repo: ScreensBRepo.demo(),
        size: kSmall,
        textScale: 1.3,
      );
      await t.pumpAndSettle();
      await scrollThrough(t);
    });
  });

  group('Sources', () {
    testWidgets('Enhanced mode: not configured, with the disclosure', (
      t,
    ) async {
      await pumpB(t, const SourcesScreen(), repo: ScreensBRepo.demo());
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Enhanced mode'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Not configured'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.textContaining('100 people'), findsOneWidget);
      expect(find.textContaining('unverified app'), findsOneWidget);
    });

    testWidgets('Health Connect: rationale first, then the system sheet', (
      t,
    ) async {
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured(hcConnected: false)
        ..hcState = const HcPermissionState(
          availability: HcAvailability.available,
          granted: [],
          missing: ['HEART_RATE'],
        )
        ..hcAfterRequest = _grantedHc;
      await pumpB(t, const SourcesScreen(), repo: repo);
      await t.pumpAndSettle();
      await t.tap(find.text('Connect Health Connect'));
      await t.pumpAndSettle();
      expect(find.text('What Airlog will read'), findsOneWidget);
      expect(repo.calls, isNot(contains('requestHealthConnectPermissions')));
      await t.tap(find.text('Continue to Health Connect'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('requestHealthConnectPermissions'));
      expect(find.text('Reading 9 data types.'), findsOneWidget);
    });

    testWidgets('Enhanced mode connect shows the disclosure, then signs in', (
      t,
    ) async {
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured()
        ..hcState = _grantedHc
        ..googleConnectResult = true;
      await pumpB(t, const SourcesScreen(), repo: repo);
      await t.pumpAndSettle();
      await tapOn(t, find.text('Connect Google Health'));
      await t.pumpAndSettle();
      expect(find.text('Before you sign in'), findsOneWidget);
      await t.tap(find.text('Continue to Google'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('connectGoogleHealth'));
    });

    testWidgets('Enhanced mode disconnect and the context toggle', (t) async {
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured(ghConnected: true)
        ..hcState = _grantedHc;
      await pumpB(t, const SourcesScreen(), repo: repo);
      await t.pumpAndSettle();
      await tapOn(t, find.text('Disconnect'));
      await t.pumpAndSettle();
      await t.tap(find.text('Disconnect').last);
      await t.pumpAndSettle();
      expect(repo.calls, contains('disconnectGoogleHealth'));

      await t.scrollUntilVisible(
        find.text('Use context from other apps'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.text('Use context from other apps'));
      await t.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('Use context from other apps'),
        matching: find.byType(Row),
      );
      await t.tap(
        find.descendant(of: row.first, matching: find.byType(Switch)),
      );
      await t.pumpAndSettle();
      expect(repo.calls, contains('setSourceEnabled:context:true'));
    });

    testWidgets('no overflow at 320 px and text scale 1.3', (t) async {
      await pumpB(
        t,
        const SourcesScreen(),
        repo: ScreensBRepo.demo()
          ..sourcesOverride = _configured()
          ..hcState = _grantedHc,
        size: kSmall,
        textScale: 1.3,
      );
      await t.pumpAndSettle();
      await scrollThrough(t);
    });
  });

  group('Profile', () {
    testWidgets('validates and saves a new profile', (t) async {
      final repo = ScreensBRepo.demo();
      await pumpB(t, const ProfileScreen(), repo: repo);
      await t.pumpAndSettle();
      // No birth year: no assumed-age prediction.
      expect(find.textContaining('From your data'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'Birth year'), '1890');
      await t.pump();
      expect(find.textContaining('Enter a year between'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'Birth year'), '1990');
      await t.pump();
      expect(find.textContaining('Predicted 183'), findsOneWidget);
      await t.tap(find.text('Male'));
      await t.pump();
      await tapOn(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.calls.last, contains('birthYear: 1990'));
      expect(repo.calls.last, contains('sex: male'));
      expect(find.textContaining('recalculated'), findsWidgets);
    });

    testWidgets('no overflow at 320 px and text scale 1.3', (t) async {
      await pumpB(
        t,
        const ProfileScreen(),
        repo: ScreensBRepo.demo(),
        size: kSmall,
        textScale: 1.3,
      );
      await t.pumpAndSettle();
      await scrollThrough(t);
    });
  });

  group('Sync log', () {
    testWidgets('lists each type with status and relative time', (t) async {
      final repo = ScreensBRepo.demo()..log = _log();
      await pumpB(t, const SyncLogScreen(), repo: repo);
      await t.pumpAndSettle();
      expect(find.text('Heart rate'), findsOneWidget);
      expect(find.textContaining('1312 records'), findsOneWidget);
      expect(find.textContaining('No permission'), findsOneWidget);
      expect(find.textContaining('Failed'), findsOneWidget);
      expect(find.text('18 min ago'), findsWidgets);
    });

    testWidgets('demo mode explains an empty log', (t) async {
      await pumpB(t, const SyncLogScreen(), repo: ScreensBRepo.demo());
      await t.pumpAndSettle();
      expect(find.text('Nothing synced yet'), findsOneWidget);
    });
  });

  for (final b in const [Brightness.dark]) {
    // dark only
    testWidgets('golden settings · ${b.name}', (t) async {
      await pumpB(
        t,
        const SettingsScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/settings_${b.name}.png'),
      );
    });

    testWidgets('golden settings lower · ${b.name}', (t) async {
      await pumpB(
        t,
        const SettingsScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await t.drag(find.byType(Scrollable).first, const Offset(0, -800));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/settings_lower_${b.name}.png'),
      );
    });

    testWidgets('golden sources · ${b.name}', (t) async {
      await pumpB(
        t,
        const SourcesScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/sources_${b.name}.png'),
      );
    });

    testWidgets('golden sources connected · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured()
        ..hcState = _grantedHc;
      await repo.setMode(DataMode.live);
      await pumpB(t, const SourcesScreen(), repo: repo, brightness: b);
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/sources_connected_${b.name}.png',
        ),
      );
    });

    testWidgets('golden profile · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo()
        ..profileOverride = const UserProfile(birthYear: 1991, sex: Sex.female);
      await pumpB(t, const ProfileScreen(), repo: repo, brightness: b);
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/settings_profile_${b.name}.png',
        ),
      );
    });

    testWidgets('golden sync log · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo()..log = _log();
      await pumpB(t, const SyncLogScreen(), repo: repo, brightness: b);
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/settings_synclog_${b.name}.png',
        ),
      );
    });
  }
}
