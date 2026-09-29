// Plews SWC readiness, ACWR training load, Mann-Kendall / Sen trend. [ours]

import 'dart:math' as math;

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/readiness.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/builders.dart';

void main() {
  group('Plews lnRMSSD SWC', () {
    // Baseline: ln of 44..56 ms (mean ≈ ln 50).
    final base = [for (var i = 0; i < 20; i++) math.log(44 + (i % 7) * 2.0)];
    test('7-day mean inside mean ± 0.5·SD → within', () {
      final r = Readiness.compute(
        lnWindow: [for (var i = 0; i < 7; i++) math.log(50)],
        lnBaseline: base,
      )!;
      expect(r.state, SwcState.within);
      expect(r.swcUpper - r.swcLower, closeTo(2 * 0.5 * _sd(base), 1e-12));
      expect(r.cv7d, 0);
    });
    test('above / below', () {
      expect(
        Readiness.compute(
          lnWindow: [for (var i = 0; i < 7; i++) math.log(70)],
          lnBaseline: base,
        )!.state,
        SwcState.above,
      );
      expect(
        Readiness.compute(
          lnWindow: [math.log(35), math.log(36), math.log(34)],
          lnBaseline: base,
        )!.state,
        SwcState.below,
      );
    });
    test('CV of lnRMSSD over the window', () {
      final w = [math.log(40), math.log(50), math.log(60)];
      final r = Readiness.compute(lnWindow: w, lnBaseline: base)!;
      final mean = w.reduce((a, b) => a + b) / 3;
      expect(r.cv7d, closeTo(_sd(w) / mean * 100, 1e-9));
    });
    test('needs ≥ 3 window nights and ≥ 7 baseline nights', () {
      expect(Readiness.compute(lnWindow: [4, 4], lnBaseline: base), isNull);
      expect(
        Readiness.compute(lnWindow: [4, 4, 4], lnBaseline: base.sublist(0, 6)),
        isNull,
      );
    });
    test('engine attaches readiness once the segment is long enough', () {
      final results = Engine.computeRange(
        denseRange('2026-08-20', 12),
        now: DateTime(2026, 8, 21),
      );
      expect(results[5].readiness, isNull, reason: '5 baseline nights < 7');
      expect(results.last.readiness, isNotNull);
    });
  });

  group('ACWR training load', () {
    Map<String, double> series(
      double Function(int daysAgo) f, {
      int days = 28,
    }) => {for (var i = 0; i < days; i++) DayKey.add('2026-08-28', -i): f(i)};

    test('steady load → ratio 1, optimal', () {
      final t = Engine.trainingLoad(series((_) => 10), '2026-08-28')!;
      expect(t.ratio, closeTo(1, 1e-12));
      expect(t.state, LoadState.optimal);
      expect(t.daysOfHistory, 28);
    });
    test('elevated / high / detraining', () {
      final elevated = Engine.trainingLoad(
        series((d) => d < 7 ? 16 : 10),
        '2026-08-28',
      )!;
      expect(elevated.acute7, 16);
      expect(elevated.chronic28, closeTo(11.5, 1e-12));
      expect(elevated.state, LoadState.elevated);
      expect(
        Engine.trainingLoad(series((d) => d < 7 ? 20 : 5), '2026-08-28')!.state,
        LoadState.high,
      );
      expect(
        Engine.trainingLoad(series((d) => d < 7 ? 4 : 10), '2026-08-28')!.state,
        LoadState.detraining,
      );
    });
    test('< 14 days of history or zero chronic load → null', () {
      expect(
        Engine.trainingLoad(series((_) => 10, days: 13), '2026-08-28'),
        isNull,
      );
      expect(Engine.trainingLoad(series((_) => 0), '2026-08-28'), isNull);
      expect(Engine.trainingLoad(const {}, '2026-08-28'), isNull);
    });
    test('missing days are skipped, not counted as 0', () {
      final s = series((d) => 10)..removeWhere((k, _) => k.endsWith('5'));
      final t = Engine.trainingLoad(s, '2026-08-28')!;
      expect(t.ratio, closeTo(1, 1e-12));
      expect(t.daysOfHistory < 28, isTrue);
    });
  });

  group('Mann-Kendall trend + Sen slope', () {
    test('monotone increase → significant up, Sen slope 1/day', () {
      final t = Engine.trend([for (var i = 0; i < 10; i++) i.toDouble()]);
      expect(t.significant, isTrue);
      expect(t.direction, TrendDirection.up);
      expect(t.slopePerDay, closeTo(1, 1e-12));
      expect(t.n, 10);
    });
    test('monotone decrease → significant down', () {
      final t = Engine.trend([for (var i = 0; i < 12; i++) 60 - 2.0 * i]);
      expect(t.direction, TrendDirection.down);
      expect(t.slopePerDay, closeTo(-2, 1e-12));
    });
    test('noise → not significant, flat', () {
      const noise = <double>[5, 3, 6, 2, 7, 4, 5, 3, 6, 4, 5, 2, 6, 5, 3];
      final t = Engine.trend(noise);
      expect(t.significant, isFalse);
      expect(t.direction, TrendDirection.flat);
    });
    test('n < 7 is never significant', () {
      final t = Engine.trend([1, 2, 3, 4, 5, 6]);
      expect(t.significant, isFalse);
      expect(t.direction, TrendDirection.flat);
      expect(t.slopePerDay, closeTo(1, 1e-12));
    });
    test('all ties → variance 0 → flat, slope 0', () {
      final t = Engine.trend([for (var i = 0; i < 10; i++) 5.0]);
      expect(t.significant, isFalse);
      expect(t.slopePerDay, 0);
    });
    test('gaps keep their index (slope per elapsed day)', () {
      final t = Engine.trend([0, null, 2, null, 4, 5, 6, 7, null, 9, 10]);
      expect(t.n, 8);
      expect(t.slopePerDay, closeTo(1, 1e-12));
      expect(t.significant, isTrue);
    });
    test('empty / all-null input is safe', () {
      expect(Engine.trend(const []).direction, TrendDirection.flat);
      expect(Engine.trend(const [null, null]).n, 0);
      expect(Engine.trend([double.nan, double.infinity]).n, 0);
    });
    test('recent vs prior means', () {
      final t = Engine.trend([
        for (var i = 0; i < 14; i++) i < 7 ? 10.0 : 20.0,
      ]);
      expect(t.priorMean, 10);
      expect(t.recentMean, 20);
    });
  });
}

double _sd(List<double> v) {
  final m = v.reduce((a, b) => a + b) / v.length;
  return math.sqrt(
    v.fold(0.0, (a, x) => a + (x - m) * (x - m)) / (v.length - 1),
  );
}
