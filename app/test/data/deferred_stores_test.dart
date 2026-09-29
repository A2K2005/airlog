// Lazily opened stores: nothing opens until the first call, a failed open
// is retried, and calls delegate unchanged.

import 'package:airlog/data/db/deferred_stores.dart';
import 'package:airlog/data/db/memory_stores.dart';
import 'package:airlog/data/db/stores.dart';
import 'package:airlog/data/repositories/health_repository_impl.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens on first use, once; a failed open is retried', () async {
    var opens = 0;
    var fail = true;
    final lazy = Lazy<AppStore>(() async {
      opens++;
      if (fail) throw StateError('SQLITE_BUSY');
      return MemoryAppStore();
    });
    final app = DeferredAppStore(lazy.get);
    expect(lazy.started, isFalse);
    expect(opens, 0);
    await expectLater(app.getSetting('k'), throwsStateError);
    expect(await lazy.settled(), isNull);
    fail = false;
    await app.setSetting('k', 'v');
    expect(await app.getSetting('k'), 'v');
    expect(opens, 2);
    expect(lazy.valueOrNull, isA<MemoryAppStore>());
  });

  test(
    'a repository over deferred stores seeds and reads like the plain ones',
    () async {
      final now = DateTime(2026, 9, 28, 9, 30);
      final raw = Lazy<RawStore>(() async => MemoryRawStore());
      final app = Lazy<AppStore>(() async => MemoryAppStore());
      final repo = HealthRepositoryImpl(
        raw: DeferredRawStore(raw.get),
        app: DeferredAppStore(app.get),
        clock: () => now,
        demoDays: 30,
        initialMode: DataMode.demo,
      );
      expect(
        raw.started || app.started,
        isFalse,
        reason: 'construction opens nothing',
      );
      expect(await repo.latestDate(), DayKey.of(now));
      expect(
        (await repo.range(
          DayKey.add(DayKey.of(now), -29),
          DayKey.of(now),
        )).length,
        greaterThanOrEqualTo(28),
      );
      expect(repo.mode, DataMode.demo);
      await repo.dispose();
    },
  );
}
