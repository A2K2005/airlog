// Startup / seeding timing marks for on-device measurement.
//
// Off by default. Build with `--dart-define=AIRLOG_TIMING=true` and read
// them with `adb logcat -s flutter | grep airlog.timing` (debugPrint reaches
// logcat in release builds too). Marks are milliseconds since main().

import 'package:flutter/foundation.dart';

const bool kAirlogTiming = bool.fromEnvironment('AIRLOG_TIMING');

abstract final class Timing {
  static final Stopwatch _sinceMain = Stopwatch();

  /// Call first thing in main().
  static void start() {
    if (!_sinceMain.isRunning) _sinceMain.start();
  }

  static int get sinceMainMs => _sinceMain.elapsedMilliseconds;

  /// `airlog.timing <name> at=<ms since main>[ took=<ms>]`.
  static void mark(String name, {int? tookMs}) {
    if (!kAirlogTiming) return;
    debugPrint(
      'airlog.timing $name at=${sinceMainMs}ms'
      '${tookMs == null ? '' : ' took=${tookMs}ms'}',
    );
  }

  /// One line per phase of a multi-phase job.
  static void phases(String job, Map<String, int> ms) {
    if (!kAirlogTiming) return;
    final total = ms.values.fold(0, (a, b) => a + b);
    debugPrint(
      'airlog.timing $job at=${sinceMainMs}ms total=${total}ms '
      '${ms.entries.map((e) => '${e.key}=${e.value}ms').join(' ')}',
    );
  }
}
