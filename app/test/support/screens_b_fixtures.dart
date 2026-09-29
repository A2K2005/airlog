// Fixtures for the Strain / Trends / Live / Settings / Diagnostics /
// Onboarding / Methodology screen tests (screen engineer B).
//
//  * ScreensBRepo   wraps the in-memory demo repository (real engine output)
//                   and records every call; sources, permissions, export,
//                   diagnostics, sync log and single days can be overridden.
//  * FakeLiveHr     a LiveHrService driven by the test: samples carry the
//                   timestamps the test chooses (the demo strap stamps
//                   DateTime.now(), which testWidgets does not fake).
//  * StepClock      a steppable clock for clockProvider.
//  * pumpB          pumps a screen on a 412×915 phone with the real theme,
//                   router and fonts.

import 'dart:async';
import 'dart:math' as math;

import 'package:airlog/app/providers.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:airlog/features/diagnostics/diagnostics_screen.dart';
import 'package:airlog/features/live/live_screen.dart';
import 'package:airlog/features/methodology/methodology_screen.dart';
import 'package:airlog/features/onboarding/onboarding_screen.dart';
import 'package:airlog/features/onboarding/onboarding_view_model.dart';
import 'package:airlog/features/privacy/privacy_screen.dart';
import 'package:airlog/features/settings/profile_screen.dart';
import 'package:airlog/features/settings/settings_screen.dart';
import 'package:airlog/features/settings/sources_screen.dart';
import 'package:airlog/features/settings/sync_log_screen.dart';
import 'package:airlog/app/platform_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// The fixed clock every golden uses: Monday 28 September 2026, 19:30.
final kNow = DateTime(2026, 9, 28, 19, 30);
const kToday = '2026-09-28';

const kPhone = Size(412, 915);
const kSmall = Size(320, 640);

class StepClock {
  StepClock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(int seconds) => now = now.add(Duration(seconds: seconds));
}

InMemoryHealthRepository demoRepo() => InMemoryHealthRepository.demo(now: kNow);

class ScreensBRepo implements HealthRepository {
  ScreensBRepo(this.inner);

  factory ScreensBRepo.demo() => ScreensBRepo(demoRepo());

  final HealthRepository inner;
  final calls = <String>[];

  List<SourceStatus>? sourcesOverride;
  HcPermissionState hcState = const HcPermissionState(
    availability: HcAvailability.unsupported,
    granted: [],
    missing: [],
  );
  HcPermissionState? hcAfterRequest;
  bool googleConnectResult = false;
  DiagnosticsReport? report;
  ExportResult export = const ExportResult(
    files: ['/tmp/airlog/scores.csv', '/tmp/airlog/raw.json'],
    directory: '/tmp/airlog',
  );
  List<SyncLogEntry>? log;
  UserProfile? profileOverride;
  final Map<String, DayBundle> dayOverride = {};
  List<DayBundle>? rangeOverride;
  String? latestOverride;
  bool emptyStore = false;
  DataMode? _mode;

  /// Simulates a repository that only knows its stored mode after start-up:
  /// applied on the first latestDate() call.
  DataMode? modeAfterStart;

  @override
  DataMode get mode => _mode ?? inner.mode;

  @override
  Future<void> setMode(DataMode mode) async {
    calls.add('setMode:${mode.name}');
    _mode = mode;
  }

  @override
  int get revision => inner.revision;
  @override
  Stream<int> get revisions => inner.revisions;
  @override
  SyncStatus get syncStatus => inner.syncStatus;
  @override
  Stream<SyncStatus> get syncStatusChanges => inner.syncStatusChanges;

  @override
  Future<String?> latestDate() async {
    if (modeAfterStart != null) {
      _mode = modeAfterStart;
      modeAfterStart = null;
    }
    if (emptyStore) return null;
    return latestOverride ?? await inner.latestDate();
  }

  @override
  Future<DayBundle?> day(String date) async =>
      emptyStore ? null : dayOverride[date] ?? await inner.day(date);

  @override
  Future<List<DayBundle>> range(String from, String to) async {
    if (emptyStore) return const [];
    final r = rangeOverride;
    if (r != null) {
      return [
        for (final b in r)
          if (b.date.compareTo(from) >= 0 && b.date.compareTo(to) <= 0) b,
      ];
    }
    return inner.range(from, to);
  }

  @override
  Future<void> syncNow() async => calls.add('syncNow');

  @override
  Future<List<SyncLogEntry>> syncLog({int limit = 200}) async =>
      log ?? await inner.syncLog(limit: limit);

  @override
  Future<List<SourceStatus>> sources() async =>
      sourcesOverride ?? await inner.sources();

  @override
  Future<void> setSourceEnabled(SourceKind kind, bool enabled) async =>
      calls.add('setSourceEnabled:${kind.code}:$enabled');

  @override
  Future<HcPermissionState> healthConnectPermissions() async => hcState;

  @override
  Future<HcPermissionState> requestHealthConnectPermissions() async {
    calls.add('requestHealthConnectPermissions');
    return hcState = hcAfterRequest ?? hcState;
  }

  @override
  Future<bool> connectGoogleHealth() async {
    calls.add('connectGoogleHealth');
    return googleConnectResult;
  }

  @override
  Future<void> disconnectGoogleHealth() async =>
      calls.add('disconnectGoogleHealth');

  @override
  Future<UserProfile> profile() async =>
      profileOverride ?? await inner.profile();

  @override
  Future<void> saveProfile(UserProfile profile) async {
    calls.add('saveProfile:${profile.toJson()}');
    profileOverride = profile;
  }

  @override
  Future<ExportResult> exportAll() async {
    calls.add('exportAll');
    return export;
  }

  @override
  Future<DiagnosticsReport> diagnostics({int windowDays = 7}) async {
    calls.add('diagnostics:$windowDays');
    return report ?? demoReport(windowDays: windowDays);
  }

  @override
  Future<JournalEntry> journal(String date) => inner.journal(date);
  @override
  Future<void> saveJournal(JournalEntry entry) => inner.saveJournal(entry);
  @override
  Future<List<FactorInsight>> journalInsights() => inner.journalInsights();

  @override
  Future<void> wipeData() async => calls.add('wipeData');

  // Any-app sources (contract 2026-09-29). Placeholder; the Data agent
  // implements these for real in HealthRepositoryImpl.
  @override
  Future<List<SourceApp>> detectedSources() async => const [];

  @override
  Future<Map<Metric, SourceChoice>> sourceChoices() async => const {};

  @override
  Future<void> setSourceChoice(Metric metric, String? origin) async {}
}

/// A diagnostics report shaped like the demo repository's (no file IO).
DiagnosticsReport demoReport({int windowDays = 7, bool demo = true}) {
  final start = DateTime(2026, 9, 28 - windowDays + 1);
  final origin = demo ? 'app.airlog.demo' : 'com.fitbit.FitbitMobile';
  DiagnosticsTypeStat t(
    String type,
    int n, {
    double? spacing,
    double? perHour,
    Map<String, int>? origins,
  }) => DiagnosticsTypeStat(
    dataType: type,
    records: n,
    origins: origins ?? {origin: n},
    devices: {demo ? 'Fitbit Air (demo)' : 'Fitbit Air': n},
    first: start,
    last: DateTime(2026, 9, 28, 19, 12),
    medianSpacingSec: spacing,
    samplesPerHour: perHour,
  );
  final p = demo ? 'Demo data: ' : '';
  return DiagnosticsReport(
    generatedAt: kNow,
    windowDays: windowDays,
    types: [
      t(
        'HEART_RATE',
        1312 * windowDays,
        spacing: 60,
        perHour: 59.6,
        origins: demo
            ? null
            : {
                origin: 1312 * windowDays,
                'com.google.android.apps.fitness': 212,
              },
      ),
      t(
        'HEART_RATE_VARIABILITY_RMSSD',
        88 * windowDays,
        spacing: 300,
        perHour: 11.8,
      ),
      t('RESTING_HEART_RATE', windowDays),
      t('SLEEP_SESSION', windowDays),
      t('STEPS', 24 * windowDays, spacing: 3600, perHour: 1),
    ],
    verdicts: [
      '${p}HR density: 1 sample / 60 s → full zone-based strain',
      '${p}HRV: ${88 * windowDays} RMSSD samples, ~1 / 5.0 min → nightly HRV = mean inside main sleep',
      '${p}Resting HR: $windowDays record(s) from the band',
      '${p}Skin temperature: none from the band → Recovery re-weights without it',
      if (demo) 'Demo data: synthetic "Fitbit Air" — connect Health Connect for the real probe',
    ],
    rawJsonPath: '/tmp/airlog-probe.json',
  );
}

/// A LiveHrService the test drives.
class FakeLiveHr implements LiveHrService {
  FakeLiveHr({this.devices = const [BleDevice('air-1', 'Fitbit Air', -61)]});

  List<BleDevice> devices;
  Object? scanError;
  Object? connectError;
  final saved = <(String, List<LiveHrSample>)>[];
  final connects = <String>[];
  var disconnects = 0;

  LiveHrPhase _phase = LiveHrPhase.idle;
  final _phaseCtl = StreamController<LiveHrPhase>.broadcast();
  final _samplesCtl = StreamController<LiveHrSample>.broadcast();
  final _rrCtl = StreamController<bool>.broadcast();
  bool _rr = false;

  void _set(LiveHrPhase p) {
    _phase = p;
    _phaseCtl.add(p);
  }

  @override
  LiveHrPhase get phase => _phase;
  @override
  Stream<LiveHrPhase> get phaseChanges => _phaseCtl.stream;
  @override
  Stream<LiveHrSample> get samples => _samplesCtl.stream;
  @override
  bool get rrAvailable => _rr;
  @override
  Stream<bool> get rrAvailableChanges => _rrCtl.stream;

  @override
  Stream<List<BleDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    final e = scanError;
    if (e != null) {
      _set(LiveHrPhase.error);
      throw e;
    }
    _set(LiveHrPhase.scanning);
    yield devices;
    _set(LiveHrPhase.idle);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(BleDevice device) async {
    connects.add(device.id);
    _set(LiveHrPhase.connecting);
    final e = connectError;
    if (e != null) {
      _set(LiveHrPhase.error);
      throw e;
    }
    _set(LiveHrPhase.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    _set(LiveHrPhase.disconnected);
  }

  /// Simulates the link dropping.
  void drop() => _set(LiveHrPhase.disconnected);

  void emit(DateTime t, int bpm, {List<double> rr = const []}) {
    if (rr.isNotEmpty && !_rr) {
      _rr = true;
      _rrCtl.add(true);
    }
    _samplesCtl.add(LiveHrSample(t, bpm, rrMs: rr, contact: true));
  }

  @override
  Future<void> saveSession({
    required String kind,
    required List<LiveHrSample> samples,
    String? name,
  }) async {
    saved.add((kind, samples));
  }
}

/// RR intervals (ms) for one second at [bpm] with a little sinus rhythm.
List<double> rrFor(int second, int bpm) {
  final base = 60000 / bpm;
  final n = math.max(1, (bpm / 60).round());
  return [
    for (var i = 0; i < n; i++)
      base * (1 + 0.04 * math.sin((second * n + i) / 2.2)),
  ];
}

class MemoryOnboardingStore implements OnboardingStore {
  MemoryOnboardingStore({this.seenValue = false});
  bool seenValue;
  @override
  Future<bool> seen() async => seenValue;
  @override
  Future<void> markSeen() async => seenValue = true;
}

class RecordingSharer implements FileSharer {
  final shared = <List<String>>[];
  @override
  Future<void> share(
    List<String> paths, {
    String? subject,
    String? text,
  }) async => shared.add(paths);
}

class FixedSelectedDate extends SelectedDate {
  FixedSelectedDate(this.date);
  final String date;
  @override
  String? build() => date;
}

/// The routes these screens navigate to. Deliberately NOT app/routes.dart:
/// that imports every feature (other owners' work in progress included), so
/// these tests would break whenever an unrelated screen does not compile.
final Map<String, WidgetBuilder> bRoutes = {
  Routes.live: (_) => const LiveScreen(),
  Routes.settings: (_) => const SettingsScreen(),
  Routes.sources: (_) => const SourcesScreen(),
  Routes.profile: (_) => const ProfileScreen(),
  Routes.syncLog: (_) => const SyncLogScreen(),
  Routes.methodology: (_) => const MethodologyScreen(),
  Routes.diagnostics: (_) => const DiagnosticsScreen(),
  Routes.onboarding: (_) => const OnboardingScreen(),
  Routes.privacy: (_) => const PrivacyScreen(),
};

Route<dynamic> bRoute(RouteSettings s) => MaterialPageRoute<dynamic>(
  settings: s,
  builder:
      bRoutes[s.name] ??
      (_) => Scaffold(appBar: AppBar(title: Text('route ${s.name}'))),
);

/// Pumps [child] on a phone-sized view with the app's theme and router.
Future<void> pumpB(
  WidgetTester t,
  Widget child, {
  required HealthRepository repo,
  LiveHrService? live,
  DateTime Function()? clock,
  Brightness brightness = Brightness.dark,
  Size size = kPhone,
  double textScale = 1,
  FileSharer? sharer,
  OnboardingStore? onboarding,
  String? selectedDate,
  bool tab = false,
  List<Override> extra = const [],
}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final body = tab ? Scaffold(body: child) : child;
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        healthRepositoryProvider.overrideWithValue(repo),
        liveHrServiceProvider.overrideWithValue(live ?? FakeLiveHr()),
        clockProvider.overrideWithValue(clock ?? () => kNow),
        fileSharerProvider.overrideWithValue(sharer ?? RecordingSharer()),
        onboardingStoreProvider.overrideWithValue(
          onboarding ?? MemoryOnboardingStore(),
        ),
        if (selectedDate != null)
          selectedDateProvider.overrideWith(
            () => FixedSelectedDate(selectedDate),
          ),
        ...extra,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brightness),
        onGenerateRoute: bRoute,
        builder: (context, w) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: w!,
        ),
        home: body,
      ),
    ),
  );
}

/// Scrolls [f] fully into view in the first Scrollable, then taps it.
Future<void> tapOn(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
}

/// Scrolls the first Scrollable to the end in steps, failing on the first
/// layout exception (overflow) along the way.
Future<void> scrollThrough(
  WidgetTester t, {
  double step = 300,
  int max = 60,
}) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < max; i++) {
    final state = t.state<ScrollableState>(scrollable);
    final pos = state.position;
    expect(t.takeException(), isNull, reason: 'at offset ${pos.pixels}');
    if (pos.pixels >= pos.maxScrollExtent) break;
    pos.jumpTo(math.min(pos.pixels + step, pos.maxScrollExtent));
    await t.pump();
  }
  expect(t.takeException(), isNull);
}

/// A day with sparse heart rate, so the engine falls back to workouts +
/// steps. Returned as a DayBundle computed by the real engine.
DayBundle fallbackDay() {
  final date = kToday;
  final start = DayKey.start(date);
  DateTime at(int h, [int m = 0]) =>
      DateTime(start.year, start.month, start.day, h, m);
  final records = <DayRecord>[
    for (var i = 20; i >= 1; i--)
      DayRecord(
        date: DayKey.add(date, -i),
        hrvRmssd: 48 + (i % 5),
        restingHr: 55 + (i % 3).toDouble(),
        steps: 9000,
      ),
    DayRecord(
      date: date,
      hrvRmssd: 51,
      restingHr: 55,
      steps: 11200,
      workouts: [
        Workout(
          id: 'w1',
          name: 'Run',
          start: at(7, 5),
          end: at(7, 50),
          averageHr: 148,
        ),
        Workout(
          id: 'w2',
          name: 'Strength training',
          start: at(18),
          end: at(18, 45),
        ),
      ],
      hrSamples: [for (var h = 8; h < 18; h += 2) HrSample(at(h), 72)],
    ),
  ];
  final results = Engine.computeRange(records, now: kNow);
  return DayBundle(records.last, results.last);
}

/// A day that exists but has no heart rate, workouts or steps: the engine
/// reports StrainMethod.none (0 = "no data", not a rest day).
DayBundle noneDay() {
  final records = <DayRecord>[
    for (var i = 10; i >= 1; i--)
      DayRecord(
        date: DayKey.add(kToday, -i),
        hrvRmssd: 50,
        restingHr: 55,
        steps: 8000,
      ),
    DayRecord(date: kToday, hrvRmssd: 51, restingHr: 55),
  ];
  final results = Engine.computeRange(records, now: kNow);
  return DayBundle(records.last, results.last);
}

/// 30 days whose HRV rises steadily (a significant trend) and whose resting
/// HR is noise (not significant). Computed by the real engine.
List<DayBundle> trendingDays() {
  final records = <DayRecord>[
    for (var i = 29; i >= 0; i--)
      DayRecord(
        date: DayKey.add(kToday, -i),
        hrvRmssd: 40 + (29 - i) * 0.8 + (i % 3),
        restingHr: 56 + ((i * 7) % 5) - 2,
        respiratoryRate: 14.6,
        steps: 8000,
      ),
  ];
  final results = Engine.computeRange(records, now: kNow);
  return [
    for (var i = 0; i < records.length; i++) DayBundle(records[i], results[i]),
  ];
}
