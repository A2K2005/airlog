// Incremental recompute (from the earliest dirty day, with the stored clean
// days as engine history) must give the same scores as recomputing everything.

import 'package:airlog/data/db/memory_stores.dart';
import 'package:airlog/data/resolver/resolver.dart';
import 'package:airlog/data/services/demo/demo_generator.dart';
import 'package:airlog/data/sync/score_pipeline.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 28, 9, 30);

Map<String, dynamic> strip(Map<String, dynamic> j) =>
    {...j}..remove('computedAt');

void main() {
  test(
    'recompute(fromDate) == full recompute for the recomputed days',
    () async {
      final raw = MemoryRawStore()
        ..upsertSync(DemoGenerator(days: 120, now: now).generate().rows);
      final app = MemoryAppStore();
      final pipe = ScorePipeline(raw: raw, app: app);
      final cfg = ResolverConfig(mode: DataMode.demo, now: now);
      await pipe.recompute(
        DataMode.demo,
        cfg: cfg,
        profile: const UserProfile(),
      );
      final today = DayKey.of(now);
      final from = DayKey.add(today, -10);
      final full = {
        for (final r in await app.results(DataMode.demo, from, today))
          r.date: strip(r.toJson()),
      };
      expect(full.length, 11);
      await pipe.recompute(
        DataMode.demo,
        fromDate: from,
        cfg: cfg,
        profile: const UserProfile(),
      );
      final inc = {
        for (final r in await app.results(DataMode.demo, from, today))
          r.date: strip(r.toJson()),
      };
      final diffs = <String>[];
      void cmp(String path, Object? a, Object? b) {
        if (a is Map && b is Map) {
          for (final k in {...a.keys, ...b.keys}) {
            cmp('$path.$k', a[k], b[k]);
          }
        } else if (a is List && b is List && a.length == b.length) {
          for (var i = 0; i < a.length; i++) {
            cmp('$path[$i]', a[i], b[i]);
          }
        } else if ('$a' != '$b') {
          diffs.add('$path: full=$a inc=$b');
        }
      }

      for (final d in full.keys) {
        cmp(d, full[d], inc[d]);
      }
      expect(diffs, isEmpty, reason: diffs.take(30).join('\n'));
      // Days before the dirty day are left untouched.
      expect(await app.result(DataMode.demo, DayKey.add(from, -1)), isNotNull);
    },
  );
}
