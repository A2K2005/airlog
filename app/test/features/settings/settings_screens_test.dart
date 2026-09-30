import 'package:airlog/features/settings/widgets/hold_to_confirm.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/app/platform_services.dart';
import 'package:airlog/design/design.dart' show AppButton, SettingsValueRow;
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
  bool ghAvailable = true,
  bool hcAvailable = true,
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
    available: hcAvailable,
    enabled: true,
    connected: hcConnected,
    detail: hcConnected
        ? 'Reading 9 data types from Fitbit'
        : 'Grant access in Health Connect to read your band',
    lastSyncAt: DateTime(2026, 9, 28, 19, 12),
  ),
  SourceStatus(
    kind: SourceKind.googleHealthApi,
    available: ghAvailable,
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

final _apps = [
  SourceApp(
    origin: 'com.fitbit.FitbitMobile',
    displayName: 'Google Health (Fitbit)',
    device: 'Fitbit Air',
    lastDataAt: DateTime(2026, 9, 28, 17, 30),
    daysWithData: const {
      Metric.hr: 14,
      Metric.hrv: 14,
      Metric.sleep: 14,
      Metric.restingHr: 14,
      Metric.steps: 12,
      Metric.weight: 3,
    },
  ),
  SourceApp(
    origin: 'com.ouraring.oura',
    displayName: 'Oura',
    lastDataAt: DateTime(2026, 9, 27, 7, 10),
    daysWithData: const {Metric.hrv: 9, Metric.sleep: 9},
  ),
];

final _choices = {
  for (final m in [Metric.hr, Metric.hrv, Metric.restingHr, Metric.sleep])
    m: SourceChoice(
      metric: m,
      origin: 'com.fitbit.FitbitMobile',
      displayName: 'Google Health (Fitbit)',
      automatic: true,
      suggestedOrigin: m == Metric.hrv ? 'com.ouraring.oura' : null,
      suggestedDisplayName: m == Metric.hrv ? 'Oura' : null,
    ),
};

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
      expect(find.text('DATA'), findsOneWidget);
      expect(find.text('Sample data'), findsWidgets);
      await t.tap(find.text('My data'));
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
        find.text('Your data was deleted. Settings and keys are kept.'),
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
      // The confirm button repeats the consequence (COPY_REVIEW SE09).
      await t.tap(find.widgetWithText(TextButton, 'Delete all data'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('wipeData'));
      // PR #1: says exactly what went (settings and keys stay).
      expect(
        find.text('Your data was deleted. Settings and keys are kept.'),
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
        find.text('Score formula version'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // PR #1: algorithm v3.
      expect(
        find.descendant(
          of: find.byType(SettingsValueRow).first,
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(find.text('App version'), findsOneWidget);
      // The non-affiliation line lives on Licences (B1).
      await t.scrollUntilVisible(
        find.text('Not medical advice.'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('WHOOP'), findsNothing);
    });

    testWidgets('no overflow at 320 px and text scale 1.3 and 2.0', (t) async {
      for (final scale in const [1.3, 2.0]) {
        await t.pumpWidget(const SizedBox());
        await pumpB(
          t,
          const SettingsScreen(),
          repo: ScreensBRepo.demo(),
          size: kSmall,
          textScale: scale,
        );
        await t.pumpAndSettle();
        await scrollThrough(t);
      }
    });
  });

  group('Sources', () {
    ScreensBRepo hcRepo(
      HcAvailability a, {
      bool deniedTwice = false,
      bool live = false,
    }) {
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured(
          hcConnected: false,
          hcAvailable: a == HcAvailability.available,
          ghAvailable: false,
        )
        ..hcState = HcPermissionState(
          availability: a,
          granted: const [],
          missing: const ['HEART_RATE', 'SLEEP_SESSION'],
          deniedTwice: deniedTwice,
        );
      return repo;
    }

    List<AppButton> disabled(WidgetTester t) => [
      for (final b in t.widgetList<AppButton>(
        find.byType(AppButton, skipOffstage: false),
      ))
        if (b.onTap == null) b,
    ];

    testWidgets('Enhanced mode is hidden when the build has no sign-in', (
      t,
    ) async {
      await pumpB(
        t,
        const SourcesScreen(),
        repo: ScreensBRepo.demo()
          ..sourcesOverride = _configured(ghAvailable: false)
          ..hcState = _grantedHc,
      );
      await t.pumpAndSettle();
      await scrollThrough(t);
      expect(find.text('Enhanced mode (cloud)', skipOffstage: false),
          findsNothing);
      expect(find.textContaining('dart-define', skipOffstage: false),
          findsNothing);
      expect(find.textContaining('100', skipOffstage: false), findsNothing);
      expect(find.textContaining('Google Health API', skipOffstage: false),
          findsNothing);
    });

    testWidgets('Enhanced mode: pills, and the beta note behind ⓘ', (t) async {
      await pumpB(
        t,
        const SourcesScreen(),
        repo: ScreensBRepo.demo()
          ..sourcesOverride = _configured()
          ..hcState = _grantedHc,
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Enhanced mode (cloud)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Off'), findsWidgets);
      expect(find.textContaining('verified'), findsNothing);
      await t.tap(find.bySemanticsLabel('About Enhanced mode (cloud)'));
      await t.pumpAndSettle();
      expect(find.textContaining('hasn’t verified this app yet'), findsOneWidget);
      expect(find.textContaining('100'), findsNothing);
    });

    testWidgets('Health Connect: every state names one next step', (t) async {
      final opened = <Uri>[];
      for (final (a, primary, secondary) in const [
        (HcAvailability.unsupported, 'Check again', 'Get Health Connect'),
        (HcAvailability.notInstalled, 'Install Health Connect', null),
        (HcAvailability.updateRequired, 'Update Health Connect', null),
        (HcAvailability.available, 'Connect my data', null),
      ]) {
        await t.pumpWidget(const SizedBox());
        await pumpB(
          t,
          const SourcesScreen(),
          repo: hcRepo(a),
          extra: [
            linkOpenerProvider.overrideWithValue((u) async {
              opened.add(u);
              return true;
            }),
          ],
        );
        await t.pumpAndSettle();
        expect(find.text(primary), findsWidgets, reason: '$a');
        if (secondary != null) {
          expect(find.text(secondary), findsOneWidget, reason: '$a');
        }
        expect(disabled(t), isEmpty, reason: '$a: no dead buttons');
        if (a == HcAvailability.notInstalled) {
          await t.tap(find.text(primary).last);
          await t.pumpAndSettle();
          expect(opened.last.host, 'play.google.com');
        }
        if (a == HcAvailability.unsupported) {
          await t.tap(find.text(primary).last);
          await t.pumpAndSettle();
          expect(find.textContaining('Still can’t reach'), findsOneWidget);
          await t.tap(find.text(secondary!));
          await t.pumpAndSettle();
          expect(opened.last.host, 'play.google.com');
        }
      }
    });

    testWidgets('denied twice opens Health Connect settings', (t) async {
      final opened = <Uri>[];
      await pumpB(
        t,
        const SourcesScreen(),
        repo: hcRepo(HcAvailability.available, deniedTwice: true),
        extra: [
          linkOpenerProvider.overrideWithValue((u) async {
            opened.add(u);
            return true;
          }),
        ],
      );
      await t.pumpAndSettle();
      await tapOn(t, find.text('Open Health Connect settings').last);
      await t.pumpAndSettle();
      expect(opened.single.scheme, 'intent');
    });

    testWidgets('"Allow the rest" with no change opens HC settings', (
      t,
    ) async {
      final opened = <Uri>[];
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured()
        ..hcState = _grantedHc
        ..hcAfterRequest = _grantedHc;
      await pumpB(
        t,
        const SourcesScreen(),
        repo: repo,
        extra: [
          linkOpenerProvider.overrideWithValue((u) async {
            opened.add(u);
            return true;
          }),
        ],
      );
      await t.pumpAndSettle();
      await tapOn(t, find.text('Allow the rest'));
      await t.pumpAndSettle();
      await t.tap(find.text('Continue to Health Connect'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('requestHealthConnectPermissions'));
      expect(opened.single.scheme, 'intent');
      expect(find.textContaining('didn’t show the request'), findsOneWidget);
    });

    testWidgets('apps: what each shares, and the app per measurement', (
      t,
    ) async {
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured()
        ..hcState = _grantedHc
        ..appsOverride = _apps
        ..choicesOverride = _choices;
      await pumpB(t, const SourcesScreen(), repo: repo);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Oura'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('USED FOR'), findsOneWidget);
      // SO16: the metric keeps its casing in the suggestion.
      await t.scrollUntilVisible(
        find.textContaining('has newer HRV data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Oura has newer HRV data'), findsOneWidget);
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
      // The sample-data strip and the tile run the same action.
      expect(find.text('Connect my data'), findsNWidgets(2));
      await t.tap(find.text('Connect my data').first);
      await t.pumpAndSettle();
      expect(find.text('What Airlog will read'), findsOneWidget);
      expect(repo.calls, isNot(contains('requestHealthConnectPermissions')));
      await t.tap(find.text('Continue to Health Connect'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('requestHealthConnectPermissions'));
      expect(find.text('Reading 9 kinds of data.'), findsOneWidget);
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
      await tapOn(t, find.text('Turn on Enhanced mode'));
      await t.pumpAndSettle();
      expect(find.text('Before you sign in'), findsOneWidget);
      expect(find.textContaining('hasn’t verified this app yet'), findsOneWidget);
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
      await tapOn(t, find.text('Turn off'));
      await t.pumpAndSettle();
      expect(find.text('Turn off Enhanced mode?'), findsOneWidget);
      await t.tap(find.text('Turn off').last);
      await t.pumpAndSettle();
      expect(repo.calls, contains('disconnectGoogleHealth'));

      await t.scrollUntilVisible(
        find.text('Use data from other apps'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.text('Use data from other apps'));
      await t.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('Use data from other apps'),
        matching: find.byType(Row),
      );
      await t.tap(
        find.descendant(of: row.first, matching: find.byType(Switch)),
      );
      await t.pumpAndSettle();
      expect(repo.calls, contains('setSourceEnabled:context:true'));
    });

    testWidgets('no overflow at 320 px and text scale 1.3 and 2.0', (t) async {
      for (final scale in const [1.3, 2.0]) {
        for (final repo in [
          ScreensBRepo.demo()
            ..sourcesOverride = _configured()
            ..hcState = _grantedHc
            ..appsOverride = _apps
            ..choicesOverride = _choices,
          ScreensBRepo.demo(),
          hcRepo(HcAvailability.notInstalled),
        ]) {
          await t.pumpWidget(const SizedBox());
          await pumpB(
            t,
            const SourcesScreen(),
            repo: repo,
            size: kSmall,
            textScale: scale,
          );
          await t.pumpAndSettle();
          await scrollThrough(t);
        }
      }
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
      expect(find.textContaining('From your age: 183'), findsOneWidget);
      // The hero shows the number the details give.
      expect(find.text('183'), findsOneWidget);
      await t.tap(find.text('Male'));
      await t.pump();
      await tapOn(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.calls.last, contains('birthYear: 1990'));
      expect(repo.calls.last, contains('sex: male'));
      expect(find.textContaining('scores were updated'), findsWidgets);
      // Honesty (COPY_REVIEW P05): never an assumed age.
      expect(find.textContaining('assumes 30'), findsNothing);
    });

    testWidgets('no overflow at 320 px and text scale 1.3 and 2.0', (t) async {
      for (final scale in const [1.3, 2.0]) {
        await t.pumpWidget(const SizedBox());
        await pumpB(
          t,
          const ProfileScreen(),
          repo: ScreensBRepo.demo(),
          size: kSmall,
          textScale: scale,
        );
        await t.pumpAndSettle();
        await scrollThrough(t);
      }
    });
  });

  group('Sync log', () {
    testWidgets('lists each type with status and relative time', (t) async {
      final repo = ScreensBRepo.demo()..log = _log();
      await pumpB(t, const SyncLogScreen(), repo: repo);
      await t.pumpAndSettle();
      expect(find.text('Heart rate'), findsOneWidget);
      expect(find.textContaining('1312 records'), findsOneWidget);
      // Status words as pills (COPY_REVIEW SY01); the fixes come first.
      expect(find.text('Not allowed'), findsWidgets);
      expect(find.text('Failed'), findsWidgets);
      expect(find.text('18 min ago'), findsWidgets);
      expect(find.text('NEEDS A FIX'), findsOneWidget);
      expect(find.text('Fix in Data sources'), findsNWidgets(2));
      // The cloud source is "Enhanced mode", never its API name.
      expect(find.textContaining('Google Health API'), findsNothing);
      expect(find.textContaining('Enhanced mode'), findsWidgets);
      await t.tap(find.text('Fix in Data sources').first);
      await t.pumpAndSettle();
      expect(find.text('Data sources'), findsWidgets);
    });

    testWidgets('no overflow at 320 px and text scale 2.0', (t) async {
      await pumpB(
        t,
        const SyncLogScreen(),
        repo: ScreensBRepo.demo()..log = _log(),
        size: kSmall,
        textScale: 2,
      );
      await t.pumpAndSettle();
      await scrollThrough(t);
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

    testWidgets('golden settings 2x text · ${b.name}', (t) async {
      await pumpB(
        t,
        const SettingsScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
        textScale: 2,
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/settings_bigtext_${b.name}.png'),
      );
    });

    // Sample data on a phone that has Health Connect, not yet connected:
    // what a new user actually sees.
    testWidgets('golden sources · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured(hcConnected: false, ghAvailable: false)
        ..hcState = const HcPermissionState(
          availability: HcAvailability.available,
          granted: [],
          missing: ['HEART_RATE'],
        );
      await pumpB(t, const SourcesScreen(), repo: repo, brightness: b);
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/sources_${b.name}.png'),
      );
    });

    // Health Connect could not be reached: "Check again" first.
    testWidgets('golden sources hc not found · ${b.name}', (t) async {
      await pumpB(
        t,
        const SourcesScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/sources_hc_notfound_${b.name}.png',
        ),
      );
    });

    testWidgets('golden sources apps · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured()
        ..hcState = _grantedHc
        ..appsOverride = _apps
        ..choicesOverride = _choices;
      await repo.setMode(DataMode.live);
      await pumpB(t, const SourcesScreen(), repo: repo, brightness: b);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Oura'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/sources_apps_${b.name}.png'),
      );
    });

    testWidgets('golden sources enhanced info · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo()
        ..sourcesOverride = _configured()
        ..hcState = _grantedHc;
      await repo.setMode(DataMode.live);
      await pumpB(t, const SourcesScreen(), repo: repo, brightness: b);
      await t.pumpAndSettle();
      await tapOn(t, find.bySemanticsLabel('About Enhanced mode (cloud)'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/sources_enhanced_info_${b.name}.png',
        ),
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
