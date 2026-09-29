// Our performance helpers must be exact replacements for the slow paths.
// [ours]

import 'dart:math' as math;

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/hr_series.dart';
import 'package:airlog/domain/engine/stats.dart';
import 'package:airlog/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rng = math.Random(7);

  test('sortedCopy equals List.sort on HR-like, clustered and tiny inputs', () {
    final inputs = <List<double>>[
      [for (var i = 0; i < 1440; i++) 50 + rng.nextDouble() * 120],
      [for (var i = 0; i < 900; i++) 58 + rng.nextInt(4).toDouble()], // ties
      [for (var i = 0; i < 500; i++) i.isEven ? 60.0 : 250.0 - i / 10],
      [3, 1, 2],
      [],
      [5, 5, 5, 5],
    ];
    for (final v in inputs) {
      expect(Stats.sortedCopy(v).toList(), [...v]..sort());
    }
  });

  test('percentileOfSortedLists equals percentile of the concatenation', () {
    for (var trial = 0; trial < 20; trial++) {
      final lists = [
        for (var d = 0; d < 1 + rng.nextInt(30); d++)
          [
            for (var i = 0; i < rng.nextInt(400); i++)
              40 + rng.nextDouble() * 150,
          ]..sort(),
      ];
      final all = [for (final l in lists) ...l];
      for (final p in [0.0, 0.025, 0.5, 0.975, 1.0]) {
        final expected = Stats.percentile(all, p);
        final got = Stats.percentileOfSortedLists(lists, p);
        if (expected == null) {
          expect(got, isNull);
        } else {
          expect(got, closeTo(expected, 1e-9), reason: 'p=$p trial $trial');
        }
      }
    }
  });

  test('Civil date math equals DayKey', () {
    for (var i = -400; i < 400; i += 7) {
      expect(Civil.add('2026-03-29', i), DayKey.add('2026-03-29', i));
    }
    expect(Civil.valid('2026-02-28'), isTrue);
    expect(Civil.valid('2026-02-29'), isFalse);
    expect(Civil.valid('2026-2-28'), isFalse);
    expect(Civil.valid('garbage'), isFalse);
  });

  test('clock minutes equal local hour·60 + minute', () {
    for (var i = 0; i < 200; i++) {
      final t = DateTime(
        2026,
        1,
        1,
      ).add(Duration(minutes: rng.nextInt(525600)));
      expect(Civil.clockMinutes(t), t.hour * 60 + t.minute);
      expect(Civil.clockMinutes(t.toUtc()), t.hour * 60 + t.minute);
    }
  });

  test('batched local midnights equal DayKey.start for a year', () {
    final keys = DayKey.range('2025-12-01', '2026-12-31');
    final m = LocalMidnights.forKeys(keys);
    for (final k in keys) {
      expect(m[k], DayKey.start(k).microsecondsSinceEpoch, reason: k);
    }
    expect(
      m[Civil.add(keys.last, 1)],
      DayKey.end(keys.last).microsecondsSinceEpoch,
    );
  });

  test('HrSeries: sorted columns and inclusive workout range', () {
    final t0 = DateTime(2026, 8, 10, 18);
    final s = HrSeries.of([
      HrSample(t0.add(const Duration(minutes: 2)), 120),
      HrSample(t0, 100),
      HrSample(t0.add(const Duration(minutes: 1)), 110),
      HrSample(t0.add(const Duration(minutes: 3)), 130),
    ]);
    expect(s.bpm.toList(), [100, 110, 120, 130]);
    expect(s.m.toList(), [0, 1, 2, 3]);
    expect(
      s.closedRange(
        t0.add(const Duration(minutes: 1)),
        t0.add(const Duration(minutes: 2)),
      ),
      (1, 3),
    );
  });
}
