// HealthRepositoryImpl — the one HealthRepository the UI talks to.
//
// Modes: demo and live keep SEPARATE data (raw rows are tagged by source,
// day rows by mode), so switching back and forth never mixes or loses
// either side. Demo re-seeds once per calendar day so it always ends today.
// Demo is an EXPLICIT choice only (decision "Demo data", 2026-09-29): a
// fresh install is live with an honest empty state, nothing is seeded before
// the user picks "Try with sample data", and any real source with data
// switches back to live.
//
// Any app (decision 2026-09-29): every Health Connect origin is read; one
// origin per metric is chosen and persisted (resolver/source_choice.dart,
// via ScorePipeline.updatePlans); detectedSources / sourceChoices /
// setSourceChoice expose and pin it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../../domain/day_key.dart';
import '../../domain/engine/engine.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import '../common/time.dart';
import '../db/raw_rows.dart';
import '../db/stores.dart';
import '../db/write_guard.dart';
import '../services/artifact_io.dart';
import '../resolver/resolver.dart';
import '../resolver/source_choice.dart';
import '../../domain/engine/source_apps.dart';
import '../services/demo/demo_generator.dart';
import '../services/google_health/google_health_source.dart';
import '../services/health_connect/hc_types.dart';
import '../services/widget/widget_sink.dart';
import '../sync/demo_seed.dart';
import '../sync/demo_seeder.dart';
import '../sync/score_pipeline.dart';
import '../sync/sync_coordinator.dart';
import '../common/timing.dart';
import 'diagnostics.dart';
import 'export.dart';

const String kModeKey = 'mode';
const String kProfileKey = 'profile';
const String kLastSyncKey = 'last_sync_ms';
const String kHcConnectedOnceKey = 'hc.connected_once';
String _enabledKey(SourceKind k) => 'source.${k.code}.enabled';

const Map<SourceKind, bool> kDefaultEnabled = {
  SourceKind.healthConnect: true,
  SourceKind.googleHealthApi: false,
  SourceKind.ble: true,
  SourceKind.context: false,
  SourceKind.takeout: false,
};

typedef DirectoryProvider = Future<Directory> Function(String purpose);

/// The platform label of an installed app (Android PackageManager), or
/// null when unknown or not visible.
typedef AppLabelLookup = Future<String?> Function(String package);

Future<Directory> tempDirectoryProvider(String purpose) =>
    Directory.systemTemp.createTemp('airlog_$purpose');

class HealthRepositoryImpl implements HealthRepository {
  HealthRepositoryImpl({
    required this.raw,
    required this.app,
    this.clock = systemClock,
    this.hc,
    this.gh,
    this.widgets = const NoopWidgetSink(),
    this.directories = tempDirectoryProvider,
    int demoSeed = 42,
    int demoDays = 90,
    this.initialMode,
    DemoSeedWriter? demoWriter,
    DemoSeedRunner demoRunner = runDemoSeedInline,
    bool persistentStores = false,
    this.appLabel,
  }) : pipeline = ScorePipeline(raw: raw, app: app, utcHr: persistentStores) {
    demo = DemoSeeder(
      raw: raw,
      app: app,
      clock: clock,
      seed: demoSeed,
      days: demoDays,
      writer: demoWriter,
      runner: demoRunner,
    );
    coordinator = SyncCoordinator(
      raw: raw,
      app: app,
      pipeline: pipeline,
      demo: demo,
      clock: clock,
      hc: hc,
      gh: gh,
    );
  }

  final RawStore raw;
  final AppStore app;
  final Clock clock;
  final HealthConnectSource? hc;
  final GoogleHealthSource? gh;
  final WidgetSink widgets;
  final DirectoryProvider directories;
  final ScorePipeline pipeline;
  late final DemoSeeder demo;
  late final SyncCoordinator coordinator;
  final DataMode? initialMode;

  /// Platform labels for origin packages the known-app table lacks.
  final AppLabelLookup? appLabel;

  /// Whether a live-HR strap (real or simulated) is connected right now,
  /// for the Bluetooth row of [sources]. Set by DataModule.
  bool Function()? bleConnected;

  /// Also cleared by [wipeData]: the coach's chats, memories and cached
  /// cards. Set by DataModule (coach, additive).
  Future<void> Function()? onWipe;

  late DataMode _mode = initialMode ?? DataMode.live;
  Map<String, DateTime> _lastByApp = const {};
  int _revision = 0;
  final _revisions = StreamController<int>.broadcast();
  SyncStatus _status = const SyncStatus(phase: SyncPhase.idle);
  final _statusCtl = StreamController<SyncStatus>.broadcast();
  Future<void>? _ready;
  Future<void>? _inflight;
  bool _autoSynced = false;
  bool _disposed = false;
  DateTime? _lastSync;

  /// Starts initialisation (idempotent). Every read awaits it. A failed
  /// start (e.g. SQLITE_BUSY while the background worker writes) is not
  /// cached, so the next call retries.
  Future<void> start() => _ready ??= _init().then(
    (_) => Timing.mark('repo_ready'),
    onError: (Object e, StackTrace st) {
      _ready = null;
      Error.throwWithStackTrace(_typed(e), st);
    },
  );

  /// Storage failures surface as a typed [DataUnavailableException] (the
  /// UI words it); never a raw DatabaseException (QA-01).
  static Object _typed(Object e) => e is DatabaseException
      ? DataUnavailableException(DataErrorKind.storage, '$e')
      : e;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DatabaseException catch (e, st) {
      Error.throwWithStackTrace(_typed(e), st);
    }
  }

  SyncStatus _st(SyncPhase phase, {DateTime? lastDataAt, String? message}) =>
      SyncStatus(
        phase: phase,
        lastSyncAt: _lastSync,
        lastDataAt: lastDataAt ?? _status.lastDataAt,
        message: message,
        lastDataByApp: _lastByApp,
      );

  Future<void> get ready => start();

  Future<void> _init() => app.mutate(_initOwned);

  Future<void> _initOwned() async {
    final stored = await app.getSetting(kModeKey);
    // Demo only when the user chose it; a fresh install is live.
    _mode =
        initialMode ??
        (stored == DataMode.demo.name ? DataMode.demo : DataMode.live);
    if (_mode == DataMode.demo && initialMode == null && await _realData()) {
      // Any real source with data makes it live.
      _mode = DataMode.live;
      await app.setSetting(kModeKey, DataMode.live.name);
    }
    final last = int.tryParse(await app.getSetting(kLastSyncKey) ?? '');
    _lastSync = last == null ? null : fromMs(last);
    await _ensureModeData();
    await _refreshLastByApp();
    // Emit (not just set): listeners subscribed before init completed.
    _setStatus(_st(SyncPhase.idle, lastDataAt: await _lastDataAt()));
    // Refresh the home-screen widget on every start (the day may have rolled).
    unawaited(_pushWidget());
  }

  /// Demo: seed/re-seed. Both modes: recompute when scores are missing or
  /// were produced by another algorithm version (engine update).
  Future<void> _ensureModeData() async {
    final profile = await this.profile();
    if (_mode == DataMode.demo) {
      final run = await _syncDemoWithStatus(profile);
      if (run.outcome != null) {
        // Seeding the synthetic band counts as a sync (freshness line).
        _lastSync = clock();
        await app.setSetting(
          kLastSyncKey,
          '${_lastSync!.millisecondsSinceEpoch}',
        );
        _bump();
        unawaited(_pushWidget());
        return;
      }
    }
    if (await _needsRecompute(_mode)) {
      await pipeline.recompute(_mode, cfg: await _cfg(_mode), profile: profile);
      _bump();
      unawaited(_pushWidget());
    }
  }

  String get _seedMessage => 'Preparing ${demo.days} days of sample data…';

  /// Real (non-demo) rows exist in the store.
  Future<bool> _realData() async =>
      await raw.span(
        sources: const {
          SourceKind.healthConnect,
          SourceKind.googleHealthApi,
          SourceKind.ble,
          SourceKind.context,
        },
      ) !=
      null;

  /// Newest datum per origin app (display name), for one freshness line
  /// per source.
  Future<void> _refreshLastByApp() async {
    if (_mode == DataMode.demo) {
      final l = await _lastDataAt();
      _lastByApp = l == null ? const {} : {SourceKind.demo.label: l};
      return;
    }
    final now = clock();
    final rows = await raw.load(
      now.subtract(const Duration(days: kCoverageWindowDays)),
      now,
      sources: const {SourceKind.healthConnect, SourceKind.context},
    );
    final byOrigin = <String, DateTime>{};
    void see(String? o, DateTime? t) {
      if (o == null || o.isEmpty || t == null) return;
      final cur = byOrigin[o];
      if (cur == null || t.isAfter(cur)) byOrigin[o] = t;
    }

    for (final d in rows.hrDays) {
      see(d.origin, d.lastT);
    }
    for (final r in rows.all) {
      see(r.originPackage, r.end);
    }
    final names = await pipeline.appNames(byOrigin.keys);
    _lastByApp = {
      for (final e in byOrigin.entries)
        SourceApps.displayName(e.key, fallback: names[e.key]): e.value,
    };
  }

  /// Demo sync; while it actually (re)seeds, the status says so (the UI's
  /// freshness line shows it). A failed seed leaves an error status.
  Future<SyncRun> _syncDemoWithStatus(UserProfile profile) async {
    final seeding = !await demo.isFresh();
    if (seeding) {
      _setStatus(
        SyncStatus(
          phase: SyncPhase.syncing,
          lastSyncAt: _lastSync,
          lastDataAt: _status.lastDataAt,
          message: _seedMessage,
        ),
      );
    }
    try {
      return await coordinator.syncDemo(profile: profile);
    } catch (e) {
      if (seeding) {
        _setStatus(
          SyncStatus(
            phase: SyncPhase.error,
            lastSyncAt: _lastSync,
            lastDataAt: _status.lastDataAt,
            // The error itself is rethrown below; the UI gets plain words.
            message: 'Couldn’t make sample data.',
          ),
        );
      }
      rethrow;
    }
  }

  Future<bool> _needsRecompute(DataMode mode) async {
    if (await app.getSetting(pendingRecomputeKey(mode.name)) != null) {
      return true;
    }
    final latest = await app.latestDate(mode);
    if (latest == null) {
      return (await raw.span(sources: Resolver.sourcesFor(await _cfg(mode)))) !=
          null;
    }
    if (await app.hasStaleResults(mode, kAlgoVersion)) return true;
    return await app.result(mode, latest) == null;
  }

  Future<Set<SourceKind>> _enabled() async {
    final out = <SourceKind>{};
    for (final e in kDefaultEnabled.entries) {
      final v = await app.getSetting(_enabledKey(e.key));
      if (v == null ? e.value : v == 'true') out.add(e.key);
    }
    return out;
  }

  Future<ResolverConfig> _cfg(DataMode mode) async =>
      ResolverConfig(mode: mode, now: clock(), enabled: await _enabled());

  void _bump() {
    _revision++;
    if (!_revisions.isClosed) _revisions.add(_revision);
  }

  void _setStatus(SyncStatus s) {
    _status = s;
    if (!_statusCtl.isClosed) _statusCtl.add(s);
  }

  Future<DateTime?> _lastDataAt() async {
    final latest = await app.latestDate(_mode);
    if (latest == null) return null;
    return (await app.record(_mode, latest))?.lastDataAt;
  }

  int _widgetRequest = 0;

  /// The phone's 12/24-hour setting for the plan widget's times. A headless
  /// background engine has no view, and Android sends user settings only
  /// when one attaches, so the value read in the foreground is kept and
  /// reused there (24-hour until the app has been opened once).
  Future<bool> _use24h() async {
    const key = 'ui.use24h';
    final d = PlatformDispatcher.instance;
    if (d.views.isNotEmpty) {
      final v = d.alwaysUse24HourFormat;
      try {
        await app.setSetting(key, '$v');
      } catch (_) {}
      return v;
    }
    try {
      return (await app.getSetting(key) ?? 'true') == 'true';
    } catch (_) {
      return true;
    }
  }

  Future<void> _pushWidget() async {
    final request = ++_widgetRequest;
    final mode = _mode;
    try {
      final latest = await app.latestDate(mode);
      final days = latest == null
          ? const <DayBundle>[]
          : (await app.bundles(
              mode,
              DayKey.add(latest, -1),
              latest,
            )).reversed.toList();
      // The plan widget's plan: the planner over the same bundle Today plans
      // from (before 05:00, the evening's day; TodayViewModel.build).
      final now = clock();
      var planDay = days.firstOrNull;
      final evening = eveningKeyOf(now);
      if (planDay != null && now.hour < 5 && evening != planDay.date) {
        planDay =
            days.where((d) => d.date == evening).firstOrNull ??
            (await app.bundles(mode, evening, evening)).firstOrNull ??
            planDay;
      }
      final use24h = await _use24h();
      final plan = planDay == null
          ? null
          : Engine.planToday(
              planDay,
              sync: _status,
              now: now,
              appNames: SourceApps.known,
              use24h: use24h,
            );
      if (request != _widgetRequest || mode != _mode || _disposed) return;
      await widgets.push(
        WidgetSnapshot.fromDays(
          days,
          demo: mode == DataMode.demo,
          today: DayKey.of(now),
          plan: plan,
          now: now,
        ),
      );
    } catch (_) {}
  }

  Future<DayBundle?> _bundle(String date) async {
    final days = await app.bundles(_mode, date, date);
    return days.firstOrNull;
  }

  // ── HealthRepository ───────────────────────────────────────────────────

  @override
  DataMode get mode => _mode;

  @override
  Future<void> setMode(DataMode mode) async {
    await start();
    await app.mutate(() => _setMode(mode), mode: mode);
  }

  Future<void> _setMode(DataMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    await app.setSetting(kModeKey, mode.name);
    await _ensureModeData();
    await _refreshLastByApp();
    _setStatus(_st(SyncPhase.idle, lastDataAt: await _lastDataAt()));
    _bump();
    unawaited(_pushWidget());
    if (mode == DataMode.live) unawaited(syncNow());
  }

  @override
  int get revision => _revision;

  @override
  Stream<int> get revisions => _revisions.stream;

  @override
  SyncStatus get syncStatus => _status;

  @override
  Stream<SyncStatus> get syncStatusChanges => _statusCtl.stream;

  @override
  Future<String?> latestDate() => _guard(() async {
    await start();
    if (_mode == DataMode.live && !_autoSynced) {
      _autoSynced = true;
      unawaited(syncNow());
    }
    return app.latestDate(_mode);
  });

  @override
  Future<DayBundle?> day(String date) => _guard(() async {
    await start();
    return _bundle(date);
  });

  @override
  Future<List<DayBundle>> range(String from, String to) =>
      _guard(() => _range(from, to));

  Future<List<DayBundle>> _range(String from, String to) async {
    await start();
    return app.bundles(_mode, from, to);
  }

  @override
  Future<void> syncNow() {
    if (_disposed) return Future.value();
    return _inflight ??= _sync(background: false)
        .whenComplete(() => _inflight = null);
  }

  /// workmanager entry point (live mode only; demo needs no background work).
  /// Reads the persisted mode BEFORE start(), so a background run never
  /// seeds demo data concurrently with the foreground. No stored mode = a
  /// fresh install = live.
  Future<void> backgroundSync() async {
    if (await app.getSetting(kModeKey) == DataMode.demo.name) return;
    await start();
    if (_mode != DataMode.live) return;
    await (_inflight ??= _sync(background: true)
        .whenComplete(() => _inflight = null));
  }

  /// Called by DataModule's lifecycle listener when the app comes back.
  /// Re-checks Health Connect permissions first (the user may have changed
  /// them in the Health Connect app; QA-06).
  Future<void> onAppResumed() async {
    await start();
    // A worker owns another repository instance. Refresh cached UI reads even
    // when it already consumed the provider's changes feed.
    _bump();
    try {
      final before = _perms;
      final now = await healthConnectPermissions();
      if (before != null &&
          before.granted.length != now.granted.length &&
          _mode == DataMode.live) {
        // Permissions changed in the Health Connect app (QA-06).
        if (now.granted.length > before.granted.length) {
          await syncAgain();
          return;
        }
        _bump();
      }
    } catch (_) {}
    final last = _lastSync;
    if (last == null || clock().difference(last) > const Duration(minutes: 5)) {
      await syncNow();
    }
  }

  Future<void> _sync({required bool background}) async {
    await start();
    try {
      await app.mutate(() => _syncOwned(background: background), mode: _mode);
    } on SupersededMutation {
      // The newer configuration/delete/sync owns the final state.
      if (background) rethrow;
    } catch (e) {
      if (background) rethrow;
      // Never a class name in the UI (it was "Sync failed: SocketException").
      _setStatus(_st(SyncPhase.error, message: _syncFailed));
    }
  }

  static const _syncFailed =
      'Sync failed. Check your connection and try again.';

  Future<void> _syncOwned({required bool background}) async {
    _autoSynced =
        true; // a sync ran this session; latestDate() needn't start one
    _setStatus(_st(SyncPhase.syncing));
    try {
      final profile = await this.profile();
      final SyncRun run;
      if (_mode == DataMode.demo) {
        if (!await demo.isFresh()) {
          _setStatus(
            SyncStatus(
              phase: SyncPhase.syncing,
              lastSyncAt: _lastSync,
              lastDataAt: _status.lastDataAt,
              message: _seedMessage,
            ),
          );
        }
        run = await coordinator.syncDemo(profile: profile);
      } else {
        run = await coordinator.syncLive(
          enabled: await _enabled(),
          profile: profile,
          background: background,
        );
      }
      _lastSync = clock();
      await app.setSetting(
        kLastSyncKey,
        '${_lastSync!.millisecondsSinceEpoch}',
      );
      final errors = run.log.where((e) => e.status == 'error').toList();
      await _refreshLastByApp();
      _setStatus(
        _st(
          errors.isEmpty ? SyncPhase.idle : SyncPhase.error,
          lastDataAt: await _lastDataAt(),
          message: errors.isEmpty
              ? null
              : '${errors.length == 1 ? 'One kind of data' : '${errors.length} kinds of data'} '
                    'didn’t sync: ${errors.map((e) => e.dataType).join(', ')}',
        ),
      );
      _bump();
      await _pushWidget();
      if (background && errors.isNotEmpty) {
        throw StateError('Background sync incomplete');
      }
    } catch (e) {
      if (e is SupersededMutation) rethrow;
      final t = _typed(e);
      _setStatus(
        _st(
          SyncPhase.error,
          message: t is DataUnavailableException ? t.userMessage : _syncFailed,
        ),
      );
      if (background) rethrow;
    }
  }

  @override
  Future<List<SyncLogEntry>> syncLog({int limit = 200}) =>
      _guard(() => app.logs(limit: limit));

  @override
  Future<List<SourceStatus>> sources() => _guard(() async {
    await start();
    final enabled = await _enabled();
    final hcAvail = hc == null
        ? HcAvailability.unsupported
        : await hc!.availability();
    HcPermissionState? perms;
    if (hcAvail == HcAvailability.available) {
      try {
        perms = await hc!.permissionState();
      } catch (_) {}
    }
    final granted = perms?.granted.length ?? 0;
    final ghConfigured = gh?.configured ?? false;
    final ghSigned = ghConfigured && await gh!.signedIn;
    final ghLast = int.tryParse(
      await app.getSetting('ghapi.last_sync_ms') ?? '',
    );
    return [
      SourceStatus(
        kind: SourceKind.demo,
        available: true,
        enabled: _mode == DataMode.demo,
        connected: true,
        detail: 'Sample data: ${demo.days} made-up days',
        lastSyncAt: _mode == DataMode.demo ? _lastSync : null,
      ),
      SourceStatus(
        kind: SourceKind.healthConnect,
        available: hcAvail == HcAvailability.available,
        enabled: enabled.contains(SourceKind.healthConnect),
        connected: granted > 0,
        detail: switch (hcAvail) {
          HcAvailability.available =>
            granted > 0
                ? 'Reading $granted data type${granted == 1 ? '' : 's'} from '
                      'the apps on this phone'
                : 'Connect Health Connect to see your data',
          HcAvailability.notInstalled => 'Health Connect is not installed',
          HcAvailability.updateRequired => 'Update Health Connect to continue',
          HcAvailability.unsupported =>
            'Health Connect isn’t available on this phone',
          HcAvailability.checkFailed => 'Airlog couldn’t check Health Connect',
        },
        lastSyncAt: _mode == DataMode.live ? _lastSync : null,
      ),
      SourceStatus(
        kind: SourceKind.googleHealthApi,
        available: ghConfigured,
        enabled: enabled.contains(SourceKind.googleHealthApi),
        connected: ghSigned,
        // Never a build flag in the UI: without an OAuth client ID
        // (GOOGLE_OAUTH_CLIENT_ID) this version simply has no Enhanced mode.
        detail: !ghConfigured
            ? 'Not available in this version'
            : ghSigned
            ? 'Signed in: blood oxygen, deep-sleep HRV, breathing rate, skin '
                  'temperature'
            : 'Sign in to add blood oxygen and deep-sleep HRV',
        lastSyncAt: ghLast == null ? null : fromMs(ghLast),
        beta: true,
      ),
      SourceStatus(
        kind: SourceKind.ble,
        available:
            Platform.isAndroid || Platform.isIOS || _mode == DataMode.demo,
        enabled: enabled.contains(SourceKind.ble),
        connected: bleConnected?.call() ?? false,
        detail: _mode == DataMode.demo
            ? 'Pretend live heart rate (sample data)'
            : 'Live heart rate while your tracker shares it over Bluetooth',
      ),
      SourceStatus(
        kind: SourceKind.context,
        available: hcAvail == HcAvailability.available,
        enabled: enabled.contains(SourceKind.context),
        connected: granted > 0,
        detail:
            'Weight from any app in Health Connect (shown, not used in scores)',
      ),
      // No Takeout row: the import was cut (PRODUCT_PLAN §7).
    ];
  });

  @override
  Future<void> setSourceEnabled(SourceKind kind, bool enabled) async {
    await start();
    await app.mutate(() => _setSourceEnabled(kind, enabled), mode: _mode);
  }

  Future<void> _setSourceEnabled(SourceKind kind, bool enabled) async {
    if (kind == SourceKind.demo) {
      await setMode(enabled ? DataMode.demo : DataMode.live);
      return;
    }
    await app.setSetting(_enabledKey(kind), '$enabled');
    if (_mode == DataMode.live) {
      await pipeline.recompute(
        DataMode.live,
        cfg: await _cfg(DataMode.live),
        profile: await profile(),
      );
      _bump();
      if (enabled) unawaited(syncNow());
    }
  }

  static const _noHc = HcPermissionState(
    availability: HcAvailability.unsupported,
    granted: [],
    missing: [],
  );

  @override
  Future<HcPermissionState> healthConnectPermissions() async {
    final h = hc;
    if (h == null) return _noHc;
    try {
      final st = await h.permissionState();
      return _perms = st.granted.isEmpty && await healthConnectDeniedTwice()
          ? HcPermissionState(
              availability: st.availability,
              granted: st.granted,
              missing: st.missing,
              historyGranted: st.historyGranted,
              backgroundGranted: st.backgroundGranted,
              deniedTwice: true,
            )
          : st;
    } catch (_) {
      return _noHc;
    }
  }

  HcPermissionState? _perms;

  /// Settings key: consecutive Health Connect requests that granted
  /// nothing (Android stops showing the sheet after two; QA-13).
  static const kHcDeniedCountKey = 'hc.denied_count';

  /// The user denied the Health Connect sheet twice in a row: Android won't
  /// show it again, so the UI should offer "Open Health Connect settings".
  Future<bool> healthConnectDeniedTwice() async =>
      (int.tryParse(await app.getSetting(kHcDeniedCountKey) ?? '') ?? 0) >= 2;

  @override
  Future<HcPermissionState> requestHealthConnectPermissions() async {
    final h = hc;
    if (h == null) return _noHc;
    final st = await h.requestPermissions();
    _perms = st;
    final denied =
        int.tryParse(await app.getSetting(kHcDeniedCountKey) ?? '') ?? 0;
    await app.setSetting(
      kHcDeniedCountKey,
      st.granted.isEmpty ? '${denied + 1}' : '0',
    );
    if (st.granted.isNotEmpty) {
      final once = await app.getSetting(kHcConnectedOnceKey);
      if (once == null) {
        await app.setSetting(kHcConnectedOnceKey, 'true');
        if (_mode != DataMode.live) {
          await setMode(DataMode.live); // syncs
          return st;
        }
      }
      // Fresh grant while live: sync now, even if a sync (without the
      // permission) is still running.
      if (_mode == DataMode.live) unawaited(syncAgain());
    }
    return st;
  }

  /// Like [syncNow], but never reuses a sync already in flight: it runs a
  /// new one after it (new permissions, a new source choice).
  Future<void> syncAgain() async {
    final running = _inflight;
    if (running != null) {
      try {
        await running;
      } catch (_) {}
    }
    await syncNow();
  }

  @override
  Future<bool> connectGoogleHealth() async {
    final g = gh;
    if (g == null || !g.configured) return false;
    final ok = await g.signIn();
    if (ok) await setSourceEnabled(SourceKind.googleHealthApi, true);
    return ok;
  }

  @override
  Future<void> disconnectGoogleHealth() async {
    await start();
    await app.mutate(_disconnectGoogleHealth, mode: _mode);
  }

  Future<void> _disconnectGoogleHealth() async {
    final g = gh;
    if (g == null) return;
    await g.signOut();
    await app.setSetting(_enabledKey(SourceKind.googleHealthApi), 'false');
    await app.setSetting('ghapi.last_sync_ms', null);
    // Health API user-data policy: honour deletion; drop its rows.
    await raw.wipe(sources: const {SourceKind.googleHealthApi});
    if (_mode == DataMode.live) {
      await pipeline.recompute(
        DataMode.live,
        cfg: await _cfg(DataMode.live),
        profile: await profile(),
      );
      _bump();
    }
  }

  @override
  Future<UserProfile> profile() => _guard(() async {
    final s = await app.getSetting(kProfileKey);
    if (s == null) return const UserProfile();
    try {
      return UserProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return const UserProfile();
    }
  });

  @override
  Future<void> saveProfile(UserProfile profile) => _guard(() async {
    await start();
    await app.mutate(() async {
      await app.setSetting(kProfileKey, jsonEncode(profile.toJson()));
      // Max HR / age norms change every score.
      await pipeline.recompute(_mode, cfg: await _cfg(_mode), profile: profile);
      _bump();
      unawaited(_pushWidget());
    }, mode: _mode);
  });

  @override
  Future<ExportResult> exportAll() => _guard(() async {
    final artifactEpoch = ArtifactIo.capture();
    await start();
    final cfg = await _cfg(_mode);
    final far = DateTime(2100);
    final rows = await raw.load(
      DateTime(1970),
      far,
      sources: Resolver.sourcesFor(cfg),
      includeRawHr: true,
    );
    final stamp = clock().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final base = await directories('exports');
    return ArtifactIo.write(
      artifactEpoch,
      () async => writeExport(
        dir: Directory(p.join(base.path, 'airlog-${_mode.name}-$stamp')),
        raw: rows,
        records: await app.records(_mode, '0000-00-00', '9999-12-31'),
        results: await app.results(_mode, '0000-00-00', '9999-12-31'),
        journal: await app.journals(_mode),
        mode: _mode,
      ),
    );
  });

  @override
  Future<DiagnosticsReport> diagnostics({
    int windowDays = 7,
  }) => _guard(() async {
    final artifactEpoch = ArtifactIo.capture();
    await start();
    final now = clock();
    final from = DayKey.start(DayKey.add(DayKey.of(now), -(windowDays - 1)));
    final points = <String, List<ProbePoint>>{};
    HcPermissionState? perms;
    var future = 0;
    final errors = <String, String>{};
    if (_mode == DataMode.demo) {
      final rows = await raw.load(
        from,
        now,
        sources: const {SourceKind.demo},
        includeRawHr: true,
      );
      void add(String type, RawRow r) => points
          .putIfAbsent(type, () => [])
          .add(
            ProbePoint(
              r.start,
              r.originPackage ?? kDemoOrigin,
              device: r.device,
            ),
          );
      for (final r in rows.hr) {
        add('HEART_RATE', r);
      }
      for (final r in rows.hrv) {
        add('HEART_RATE_VARIABILITY_RMSSD', r);
      }
      for (final r in rows.sleep) {
        add('SLEEP_SESSION', r);
      }
      for (final r in rows.workouts) {
        add('WORKOUT', r);
      }
      for (final r in rows.scalars) {
        // One SpO2 point per night: the min row describes the same night.
        if (r.scalar == ScalarKind.spo2Min) continue;
        final key = switch (r.scalar) {
          ScalarKind.rhr => 'RESTING_HEART_RATE',
          ScalarKind.resp => 'RESPIRATORY_RATE',
          ScalarKind.skinTempDelta => 'SKIN_TEMPERATURE',
          ScalarKind.steps => 'STEPS',
          ScalarKind.vo2max => 'VO2_MAX',
          ScalarKind.spo2Avg => HcType.spo2.key,
          _ => r.scalar.code,
        };
        add(key, r);
      }
    } else if (hc != null) {
      perms = await healthConnectPermissions();
      for (final t in HcType.stored) {
        if (!perms.granted.contains(t.key)) {
          errors[t.key] = 'permission not granted';
          continue;
        }
        final list = points.putIfAbsent(t.key, () => []);
        var a = from;
        while (a.isBefore(now)) {
          final b = t == HcType.heartRate ? DayKey.end(DayKey.of(a)) : now;
          try {
            for (final r in await hc!.read(t, a, b.isAfter(now) ? now : b)) {
              if (r.type == HcType.sleep && r.stage != null) continue;
              if (r.end.isAfter(now.add(const Duration(minutes: 2)))) future++;
              list.add(
                ProbePoint(r.start, r.origin, device: r.device, recordId: r.id),
              );
            }
          } catch (e) {
            errors[t.key] = '$e';
          }
          a = b;
        }
      }
    }
    final stats = {
      for (final e in points.entries)
        e.key: buildTypeStat(
          e.key,
          e.value,
          primaryOrigin: _mode == DataMode.demo ? kDemoOrigin : null,
        ),
    };
    final labels = await pipeline.appNames({
      for (final s in stats.values) ...s.origins.keys,
    });
    final verdicts = buildVerdicts(
      stats,
      demo: _mode == DataMode.demo,
      perms: perms,
      googleConfigured: gh?.configured ?? false,
      futureDated: future,
      appName: (o) => SourceApps.displayName(o, fallback: labels[o]),
    );
    if (_mode == DataMode.live && hc == null) {
      verdicts.insert(
        0,
        'Health Connect is not available in this build/device',
      );
    }
    String? path;
    try {
      path = await ArtifactIo.write(artifactEpoch, () async {
        final dir = await directories('diagnostics');
        await dir.create(recursive: true);
        final stamp = now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
        final f = File(p.join(dir.path, 'airlog-probe-$stamp.json'));
        await f.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'generatedAt': now.toUtc().toIso8601String(),
            'mode': _mode.name,
            'windowDays': windowDays,
            'verdicts': verdicts,
            'errors': errors,
            'permissions': perms == null
                ? null
                : {
                    'availability': perms.availability.name,
                    'granted': perms.granted,
                    'missing': perms.missing,
                    'history': perms.historyGranted,
                    'background': perms.backgroundGranted,
                  },
            'types': [
              for (final s in stats.values)
                {
                  'dataType': s.dataType,
                  'records': s.records,
                  'origins': s.origins,
                  'devices': s.devices,
                  'first': s.first?.toUtc().toIso8601String(),
                  'last': s.last?.toUtc().toIso8601String(),
                  'medianSpacingSec': s.medianSpacingSec,
                  'samplesPerHour': s.samplesPerHour,
                  'sample': [
                    for (final pt
                        in (points[s.dataType] ?? const <ProbePoint>[]).take(
                          50,
                        ))
                      {
                        't': pt.t.toUtc().toIso8601String(),
                        'origin': pt.origin,
                        if (pt.device != null) 'device': pt.device,
                        if (pt.recordId != null) 'id': pt.recordId,
                      },
                  ],
                },
            ],
          }),
        );
        return f.path;
      });
    } on SupersededMutation {
      rethrow;
    } catch (_) {}
    return DiagnosticsReport(
      generatedAt: now,
      windowDays: windowDays,
      types: stats.values.toList()
        ..sort((a, b) => a.dataType.compareTo(b.dataType)),
      verdicts: verdicts,
      rawJsonPath: path,
    );
  });

  @override
  Future<JournalEntry> journal(String date) => _guard(() async {
    await start();
    return await app.journal(_mode, date) ?? JournalEntry(date: date);
  });

  @override
  Future<void> saveJournal(JournalEntry entry) => _guard(() async {
    await start();
    await app.putJournal(_mode, entry);
    _bump();
  });

  @override
  Future<List<FactorInsight>> journalInsights() => _guard(() async {
    await start();
    final entries = await app.journals(_mode);
    final recovery = <String, int>{
      for (final r in await app.results(_mode, '0000-00-00', '9999-12-31'))
        if (r.recovery != null) r.date: r.recovery!.score,
    };
    try {
      return Engine.journalInsights(entries, recovery);
    } catch (_) {
      return const [];
    }
  });

  @override
  Future<void> wipeData() async {
    await ArtifactIo.wipe(
      () async {
        await start();
        await app.mutate(_wipeData, mode: _mode);
      },
      () async {
        for (final purpose in ['exports', 'diagnostics']) {
          final dir = await directories(purpose);
          if (await dir.exists()) await dir.delete(recursive: true);
        }
      },
    );
  }

  Future<void> _wipeData() async {
    await raw.wipe();
    await app.wipe();
    await app.setSetting(kDemoSeededForKey, null);
    await app.setSetting(kLastSyncKey, null);
    await app.setSetting('ghapi.last_sync_ms', null);
    await onWipe?.call();
    for (final m in Metric.values) {
      await app.setSetting(originPlanKey(m), null);
    }
    _lastSync = null;
    if (_mode == DataMode.demo) await _ensureModeData();
    await _refreshLastByApp();
    _setStatus(_st(SyncPhase.idle, lastDataAt: await _lastDataAt()));
    _bump();
    // The widget must not keep the wiped numbers (QA-15).
    await _pushWidget();
  }

  // ── Live sessions (BLE / demo strap) ───────────────────────────────────

  /// Persists a live session: HR samples as raw HR rows, plus a workout row
  /// ('workout') or an RMSSD scalar ('hrv_check'). In demo mode rows are
  /// tagged demo so they show up in demo data; in live mode they are ble.
  Future<void> saveLiveSession({
    required String kind,
    required List<LiveHrSample> samples,
    String? name,
    String? device,
  }) async {
    await start();
    await app.mutate(
      () => _saveLiveSession(
        kind: kind,
        samples: samples,
        name: name,
        device: device,
      ),
      mode: _mode,
    );
  }

  Future<void> _saveLiveSession({
    required String kind,
    required List<LiveHrSample> samples,
    String? name,
    String? device,
  }) async {
    if (samples.isEmpty) return;
    final src = _mode == DataMode.demo ? SourceKind.demo : SourceKind.ble;
    final sorted = [...samples]..sort((a, b) => a.t.compareTo(b.t));
    final start0 = sorted.first.t, end0 = sorted.last.t;
    final sessionId = '${src.code}:$kind:${start0.millisecondsSinceEpoch}';
    final dev =
        device ?? (_mode == DataMode.demo ? kDemoDevice : 'Bluetooth HR');
    final rows = RawRows(
      hr: [
        for (final s in sorted)
          if (s.bpm > 0 && s.contact != false)
            RawHrRow(
              source: src,
              sourceRecordId: '$sessionId@${s.t.millisecondsSinceEpoch}',
              recordId: sessionId,
              originPackage: 'app.airlog.live',
              device: dev,
              ingestedAt: clock(),
              t: s.t,
              bpm: s.bpm.toDouble(),
            ),
      ],
    );
    if (kind == 'workout' && end0.difference(start0).inMinutes >= 1) {
      final bpms = [
        for (final s in sorted)
          if (s.bpm > 0) s.bpm.toDouble(),
      ];
      rows.workouts.add(
        RawWorkoutRow(
          source: src,
          sourceRecordId: sessionId,
          recordId: sessionId,
          originPackage: 'app.airlog.live',
          device: dev,
          ingestedAt: clock(),
          start: start0,
          end: end0,
          name: name ?? 'Live workout',
          activityType: 'LIVE',
          avgHr: bpms.isEmpty ? null : mean(bpms),
        ),
      );
    } else if (kind == 'hrv_check') {
      final rr = [for (final s in sorted) ...s.rrMs];
      double? rmssd;
      try {
        rmssd = Engine.rmssdFromRr(rr);
      } catch (_) {}
      if (rmssd != null) {
        rows.scalars.add(
          RawScalarRow(
            source: src,
            sourceRecordId: sessionId,
            recordId: sessionId,
            originPackage: 'app.airlog.live',
            device: dev,
            ingestedAt: clock(),
            scalar: ScalarKind.hrvCheck,
            start: start0,
            end: end0,
            value: rmssd,
          ),
        );
      }
    }
    final days = await raw.upsert(rows);
    if (days.isNotEmpty) {
      await pipeline.recompute(
        _mode,
        fromDate: days.reduce((a, b) => a.compareTo(b) <= 0 ? a : b),
        cfg: await _cfg(_mode),
        profile: await profile(),
      );
    }
    _bump();
    unawaited(_pushWidget());
  }

  /// Closes the streams. The done futures are not awaited: a broadcast
  /// controller whose listeners already cancelled never completes it under
  /// testWidgets' fake async.
  Future<void> dispose() async {
    _disposed = true;
    await _inflight;
    unawaited(_revisions.close());
    unawaited(_statusCtl.close());
  }

  // ── Any app via Health Connect (decision 2026-09-29) ───────────────────

  /// Display name of [origin]: the known-app table, else the platform label
  /// (cached in settings), else the package.
  Future<String> _appName(String origin) async {
    final known = SourceApps.knownName(origin);
    if (known != null) return known;
    var label = await app.getSetting(appLabelKey(origin));
    if (label == null && appLabel != null) {
      try {
        label = await appLabel!(origin);
      } catch (_) {}
      await app.setSetting(appLabelKey(origin), label ?? '');
    }
    return SourceApps.displayName(origin, fallback: label);
  }

  @override
  Future<List<SourceApp>> detectedSources() => _guard(() async {
    await start();
    if (_mode == DataMode.demo) return const [];
    final now = clock();
    final today = DayKey.of(now);
    final from = DayKey.add(today, -(kCoverageWindowDays - 1));
    final rows = await raw.load(
      DayKey.start(from),
      now,
      sources: const {SourceKind.healthConnect, SourceKind.context},
    );
    final days = originDaysOf(rows);
    final last = <String, DateTime>{};
    final device = <String, (DateTime, String)>{};
    void see(String? o, DateTime? t, String? d) {
      if (o == null || t == null) return;
      final cur = last[o];
      if (cur == null || t.isAfter(cur)) last[o] = t;
      if (d != null && d.isNotEmpty) {
        final cd = device[o];
        if (cd == null || t.isAfter(cd.$1)) device[o] = (t, d);
      }
    }

    for (final d in rows.hrDays) {
      see(d.origin, d.lastT, d.device);
    }
    for (final r in rows.all) {
      see(r.originPackage, r.end, r.device);
    }
    final origins = {for (final m in days.values) ...m.keys, ...last.keys}
      ..remove('');
    final out = <SourceApp>[];
    for (final o in origins.toList()..sort()) {
      out.add(
        SourceApp(
          origin: o,
          displayName: await _appName(o),
          daysWithData: {
            for (final e in days.entries)
              if (e.value[o] case final d? when d.isNotEmpty)
                e.key: SourceChooser.coverage(d, from, today),
          },
          lastDataAt: last[o],
          device: device[o]?.$2,
        ),
      );
    }
    return out;
  });

  @override
  Future<Map<Metric, SourceChoice>> sourceChoices() => _guard(() async {
    await start();
    if (_mode == DataMode.demo) return const {};
    final plans = await pipeline.loadPlans();
    return {
      for (final e in plans.entries)
        e.key: SourceChoice(
          metric: e.key,
          origin: e.value.current,
          displayName: await _appName(e.value.current),
          automatic: e.value.automatic,
          since: e.value.since,
          suggestedOrigin: e.value.suggested,
          suggestedDisplayName: e.value.suggested == null
              ? null
              : await _appName(e.value.suggested!),
        ),
    };
  });

  /// Pins [metric] to [origin] from the first day it has data (null: back
  /// to automatic), then recomputes from the first day whose origin
  /// changes.
  @override
  Future<void> setSourceChoice(Metric metric, String? origin) =>
      _guard(() async {
        await start();
        await app.mutate(() async {
          final now = clock();
          final span = await raw.span(
            sources: const {SourceKind.healthConnect, SourceKind.context},
          );
          final rows = span == null
              ? RawRows()
              : await raw.load(
                  span.$1,
                  now,
                  sources: const {SourceKind.healthConnect, SourceKind.context},
                );
          final days =
              originDaysOf(rows)[metric] ?? const <String, Set<String>>{};
          final old = (await pipeline.loadPlans())[metric];
          final chosen = origin == null
              ? SourceChooser.update(metric, days, null, today: DayKey.of(now))
              : SourceChooser.pin(
                  metric,
                  origin,
                  days,
                  prev: old,
                  today: DayKey.of(now),
                );
          // Which apps don't share the metric is not part of the choice.
          final next = old == null
              ? chosen
              : chosen?.copyWith(notShared: old.notShared);
          await pipeline.savePlan(next, metric);
          final all = {for (final d in days.values) ...d};
          final from = next?.firstDifference(old, all);
          if (_mode == DataMode.live && (from != null || next == null)) {
            await pipeline.recompute(
              DataMode.live,
              fromDate: from,
              cfg: await _cfg(DataMode.live),
              profile: await profile(),
            );
            _bump();
            unawaited(_pushWidget());
          }
        }, mode: _mode);
      });
}
