// Periodic background sync via workmanager (Android WorkManager, 15 min
// minimum). The callback runs in a separate headless Flutter engine: pub
// plugins are auto-registered there (FlutterEngine default), Dart-side
// plugin registration is ensured below, but MainActivity's own channel
// (VO2 max, device metadata, exact permission set) is absent — those parts
// are skipped and filled on the next foreground sync.

import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../common/timing.dart';
import '../data_module.dart';

const String kBackgroundTask = 'airlog.sync';
const String kBackgroundUniqueName = 'airlog-periodic-sync';

@pragma('vm:entry-point')
void airlogBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    DataModule? m;
    try {
      m = await DataModule.create(background: true);
      await m.repository.backgroundSync();
      return true;
    } catch (_) {
      return false;
    } finally {
      await m?.close();
    }
  });
}

abstract final class BackgroundSync {
  static Future<void> register() async {
    if (!Platform.isAndroid) return;
    final t = Stopwatch()..start();
    try {
      await Workmanager().initialize(airlogBackgroundDispatcher);
      Timing.mark('wm_initialize', tookMs: t.elapsedMilliseconds);
      await Workmanager().registerPeriodicTask(
        kBackgroundUniqueName,
        kBackgroundTask,
        frequency: const Duration(minutes: 15),
        // A periodic task fires right after registration; don't compete with
        // the first-launch demo seed / initial sync in the foreground.
        initialDelay: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.notRequired),
      );
      Timing.mark('wm_registered', tookMs: t.elapsedMilliseconds);
    } catch (_) {
      // Missing plugin (tests/desktop) or WorkManager refused: foreground
      // sync on resume still works.
    }
  }
}
