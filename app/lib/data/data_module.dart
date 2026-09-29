// Composition of the data layer: sqflite stores → services (Health
// Connect, Google Health API, BLE, demo) → sync → HealthRepositoryImpl.
// main.dart calls DataModule.open() (synchronous: nothing is awaited before
// runApp) and hands [health] / [liveHr] to Riverpod. First launch runs in
// DEMO mode (seeded synthetic Fitbit Air) until the user connects Health
// Connect; the choice is persisted.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../domain/repositories.dart';
import 'coach/coach_module.dart';
import 'common/time.dart';
import 'common/timing.dart';
import 'db/deferred_stores.dart';
import 'db/sqlite_stores.dart';
import 'db/stores.dart';
import 'repositories/health_repository_impl.dart';
import 'services/ble/live_hr_service_impl.dart';
import 'services/demo/demo_live_hr_service.dart';
import 'services/google_health/google_auth.dart';
import 'services/google_health/google_health_source.dart';
import 'services/health_connect/health_connect_service.dart';
import 'services/widget/widget_sink.dart';
import 'sync/background.dart';
import 'sync/demo_seed.dart';

class DataModule {
  DataModule(this.health, this.liveHr, {this.impl, this.onClose});

  final HealthRepository health;
  final LiveHrService liveHr;
  final HealthRepositoryImpl? impl;
  final Future<void> Function()? onClose;
  AppLifecycleListener? _lifecycle;

  /// The AI coach (chats, memory, cards) over the same database. Null in
  /// the workmanager isolate: nothing there may call a cloud model.
  CoachModule? coach;

  HealthRepositoryImpl get repository =>
      impl ?? (health as HealthRepositoryImpl);

  static Future<Directory> _docs(String purpose) async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, purpose));
    await d.create(recursive: true);
    return d;
  }

  /// Builds the data layer WITHOUT waiting for anything: the database
  /// opens lazily on the first store call, which [HealthRepositoryImpl.start]
  /// makes right away (so the open overlaps the first frame) and every
  /// repository read awaits. [background]: the workmanager isolate (no
  /// lifecycle hooks, no re-registration, no demo seeding).
  static DataModule open({bool background = false}) {
    const Clock clock = systemClock;
    final db = Lazy<Database>(() async {
      final t = Stopwatch()..start();
      // The workmanager isolate runs in the SAME process as the app: with
      // sqflite's default single-instance handle, its close() would close
      // the app's database too (QA-01). It opens its own connection.
      final d = await AirlogDatabase.open(singleInstance: !background);
      Timing.mark('db_open', tookMs: t.elapsedMilliseconds);
      return d;
    });
    final rawStore = Lazy<RawStore>(
      () async => SqliteRawStore(await db.get(), clock: clock),
    );
    final appStore = Lazy<AppStore>(
      () async => SqliteAppStore(await db.get(), clock: clock),
    );
    final hc = Platform.isAndroid ? HealthConnectPluginSource() : null;
    final gh = GoogleHealthApiSource(
      GoogleAuth(GoogleOAuthConfig.fromEnvironment(), const SecureTokenStore()),
    );
    final repo = HealthRepositoryImpl(
      raw: DeferredRawStore(rawStore.get),
      app: DeferredAppStore(appStore.get),
      clock: clock,
      hc: hc,
      gh: gh,
      widgets: const HomeWidgetSink(),
      directories: _docs,
      // First-launch demo seed: computed in a worker isolate, written in one
      // transaction.
      demoWriter: (ops) async => runSqlOps(await db.get(), ops),
      demoRunner: runDemoSeedInIsolate,
      persistentStores: true,
      appLabel: platformAppLabel,
    );
    // Readiness (demo seeding on first launch) runs in the background;
    // every repository read awaits it, so the UI simply shows loading.
    // The workmanager isolate skips this (backgroundSync checks the mode
    // first and never seeds demo data).
    if (!background) unawaited(repo.start().catchError((Object _) {}));

    late final LiveHrServiceImpl real;
    real = LiveHrServiceImpl(
      saver: ({required kind, required samples, name}) => repo.saveLiveSession(
        kind: kind,
        samples: samples,
        name: name,
        device: real.deviceName,
      ),
    );
    final live = ModeAwareLiveHrService(
      demo: DemoLiveHrService(saver: repo.saveLiveSession),
      real: real,
      mode: () => repo.mode,
    );
    repo.bleConnected = () => live.isConnected;

    // The coach shares the database; wiping the data clears its chats,
    // memories and cached cards too.
    final coach = background ? null : CoachModule.sqlite(repo, db.get);
    if (coach != null) repo.onWipe = coach.repository.wipe;

    final module = DataModule(
      repo,
      live,
      impl: repo,
      onClose: () async {
        await repo.dispose();
        // Close only a database that opened (awaiting an open in flight).
        await (await db.settled())?.close();
      },
    );
    module.coach = coach;
    if (!background) {
      module._lifecycle = AppLifecycleListener(
        onResume: () => unawaited(repo.onAppResumed()),
      );
      unawaited(BackgroundSync.register());
    }
    return module;
  }

  /// [open], for callers that want a Future (the workmanager isolate).
  static Future<DataModule> create({bool background = false}) async =>
      open(background: background);

  Future<void> close() async {
    _lifecycle?.dispose();
    await onClose?.call();
  }
}
