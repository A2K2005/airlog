import 'dart:async';

import '../db/write_guard.dart';

/// Exports and probes are foreground-only. Share this gate across repository
/// instances in that isolate so wipe can drain writes, not network probes.
abstract final class ArtifactIo {
  static Future<void> _tail = Future.value();
  static int _epoch = 0;
  static int _wipes = 0;

  static int capture() {
    if (_wipes != 0) throw const SupersededMutation();
    return _epoch;
  }

  static Future<T> _exclusive<T>(Future<T> Function() body) {
    final next = _tail.then((_) => body());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  static Future<T> write<T>(int epoch, Future<T> Function() body) =>
      _exclusive(() async {
        if (_wipes != 0 || epoch != _epoch) throw const SupersededMutation();
        final result = await body();
        if (epoch != _epoch) throw const SupersededMutation();
        return result;
      });

  static Future<void> wipe(
    Future<void> Function() data,
    Future<void> Function() files,
  ) async {
    _epoch++;
    _wipes++;
    try {
      await data();
    } finally {
      try {
        // Even a failed data wipe must remove outputs from superseded tasks.
        await _exclusive(files);
      } finally {
        _wipes--;
      }
    }
  }
}
