// Parity with Luraxx/pulse SelfTest/Sources/pulse-selftest/main.swift
// (Apache-2.0, see third_party/pulse/NOTICE): sections "DayKey" (:137-146),
// "Statistik" (:150-161) and "Trend-Aggregation" (:200-220). Same fixtures,
// same expectations.

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/load_and_trends.dart';
import 'package:airlog/domain/engine/stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DayKey (main.swift:137-146)', () {
    test('addDays across a day boundary', () {
      expect(DayKey.add('2026-07-18', -1), '2026-07-17');
    });
    test('2026-02-27 … 2026-03-02 = 4 days (2026 is not a leap year)', () {
      expect(DayKey.range('2026-02-27', '2026-03-02').length, 4);
    });
    test('distance between keys', () {
      expect(DayKey.diff('2026-07-01', '2026-07-18'), 17);
    });
  });

  group('Statistik (main.swift:150-161)', () {
    test('median', () {
      expect(Stats.percentile([1, 2, 3, 4, 5], 0.5), 3);
    });
    test('percentile of a single value', () {
      expect(Stats.percentile([10], 0.05), 10);
    });
    test('logistic(0) = 0.5', () {
      expect((Stats.logistic(0) - 0.5).abs() < 1e-9, isTrue);
    });
    test('baseline mean / reliability / z at mean', () {
      final b = Stats.baseline([60, 62, 64, 66, 68]);
      expect(b, isNotNull);
      expect((b!.mean - 64).abs() < 1e-9, isTrue);
      expect(b.isReliable, isTrue, reason: '5 values count as reliable');
      expect(b.z(64).abs() < 1e-9, isTrue);
    });
    test('baseline needs at least 3 values', () {
      expect(Stats.baseline([1, 2]), isNull);
    });
  });

  group('Trend-Aggregation (main.swift:200-220)', () {
    final pairs = [
      for (var i = 0; i < 10; i++)
        (key: DayKey.add('2026-06-01', i), value: i.toDouble()),
    ];
    final ma3 = TrendMath.movingAverage(pairs, 3);
    test('moving average keeps the point count', () {
      expect(ma3.length, 10);
    });
    test('first point: mean of itself', () {
      expect((ma3[0].value - 0).abs() < 1e-9, isTrue);
    });
    test('window 3 over 0,1,2 → 1', () {
      expect((ma3[2].value - 1).abs() < 1e-9, isTrue);
    });
    test('window 3 over 7,8,9 → 8', () {
      expect((ma3[9].value - 8).abs() < 1e-9, isTrue);
    });
    test('gap in the window → mean over present values only', () {
      final gap = TrendMath.movingAverage([
        (key: '2026-06-01', value: 10),
        (key: '2026-06-03', value: 30),
      ], 3);
      expect((gap[1].value - 20).abs() < 1e-9, isTrue);
    });
    // 2026-07-19 was a Sunday, 2026-07-20 a Monday.
    final weekly = TrendMath.weeklyMean([
      (key: '2026-07-17', value: 60),
      (key: '2026-07-18', value: 70),
      (key: '2026-07-19', value: 80),
      (key: '2026-07-20', value: 40),
      (key: '2026-07-21', value: 60),
    ]);
    test('two calendar weeks → two points', () {
      expect(weekly.length, 2);
    });
    test('week 1: Monday key + mean 70', () {
      expect(weekly[0].key, '2026-07-13');
      expect((weekly[0].value - 70).abs() < 1e-9, isTrue);
    });
    test('week 2: Monday key + mean 50', () {
      expect(weekly[1].key, '2026-07-20');
      expect((weekly[1].value - 50).abs() < 1e-9, isTrue);
    });
  });
}
