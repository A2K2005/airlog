// Ported from Luraxx/pulse Core/Models/Journal.swift (JournalEngine,
// Apache-2.0, see third_party/pulse/NOTICE). Changes: Dart port over the
// contract's JournalFactor list (Pulse's `sex` factor is not in our list;
// travel and meditation are); ties in |delta| are broken by factor order so
// the output is deterministic (Dart's sort is not stable).
//
// Method (after Pulse / WHOOP's Monthly Performance Assessment, tightened
// by the product-critic review, 2026-09-29): a factor logged on day D is
// compared with the recovery of day D+1; ≥ 10 days with and ≥ 10 without;
// Welch t-test of the difference of means with a 95 % confidence interval;
// "solid" only when significant after a Holm correction across every factor
// tested (α = 0.05). Association, not causation: copy says "associated
// with".

import 'dart:math' as math;

import '../day_key.dart';
import '../models.dart';
import '../results.dart';
import 'stats.dart';

abstract final class JournalEngine {
  /// Days with and days without a factor before it is assessed. Pulse used
  /// 5 (Journal.swift:145); raised to 10 in algo v2.
  static const int minDaysPerGroup = 10;

  /// Family-wise error rate for the Holm correction across factors.
  static const double alpha = 0.05;

  /// Confidence level of [FactorInsight.ciLow] / [FactorInsight.ciHigh].
  static const double ciLevel = 0.95;

  /// Journal.swift:147.
  static const int assessmentMinRecoveryDays = 28;

  /// Journal.swift:150-152.
  static bool assessmentReady(Map<String, int> recoveryByDay) =>
      recoveryByDay.length >= assessmentMinRecoveryDays;

  static List<FactorInsight> insights(
    Map<String, JournalEntry> entries,
    Map<String, int> recoveryByDay,
  ) {
    final tested =
        <
          ({
            JournalFactor factor,
            List<double> withV,
            List<double> withoutV,
            double delta,
            double se,
            double df,
            double p,
          })
        >[];
    for (final factor in JournalFactor.values) {
      final withValues = <double>[];
      final withoutValues = <double>[];
      for (final MapEntry(key: dayKey, value: entry) in entries.entries) {
        // Next day's recovery (the effect shows in the night after).
        final recovery = recoveryByDay[DayKey.add(dayKey, 1)];
        if (recovery == null) continue;
        if (entry.factors.contains(factor)) {
          withValues.add(recovery.toDouble());
        } else {
          withoutValues.add(recovery.toDouble());
        }
      }
      if (withValues.length < minDaysPerGroup ||
          withoutValues.length < minDaysPerGroup) {
        continue;
      }
      final delta = Stats.mean(withValues) - Stats.mean(withoutValues);
      // Welch standard error and Welch–Satterthwaite degrees of freedom.
      final n1 = withValues.length.toDouble();
      final n2 = withoutValues.length.toDouble();
      final v1 = math.pow(Stats.standardDeviation(withValues), 2) / n1;
      final v2 = math.pow(Stats.standardDeviation(withoutValues), 2) / n2;
      final se = math.sqrt(v1 + v2);
      final den = v1 * v1 / (n1 - 1) + v2 * v2 / (n2 - 1);
      final df = den > 0 ? (v1 + v2) * (v1 + v2) / den : n1 + n2 - 2;
      final double p;
      if (se > 0) {
        p = StudentT.twoSidedP(delta / se, df);
      } else {
        p = delta == 0 ? 1.0 : 0.0;
      }
      tested.add((
        factor: factor,
        withV: withValues,
        withoutV: withoutValues,
        delta: delta,
        se: se,
        df: df,
        p: p,
      ));
    }

    // Holm step-down across the factors tested.
    final order = [for (var i = 0; i < tested.length; i++) i]
      ..sort((a, b) {
        final c = tested[a].p.compareTo(tested[b].p);
        return c != 0
            ? c
            : tested[a].factor.index.compareTo(tested[b].factor.index);
      });
    final solid = <int>{};
    for (var k = 0; k < order.length; k++) {
      if (tested[order[k]].p <= alpha / (order.length - k)) {
        solid.add(order[k]);
      } else {
        break;
      }
    }

    final result = <FactorInsight>[
      for (var i = 0; i < tested.length; i++)
        () {
          final t = tested[i];
          final q = t.se > 0
              ? StudentT.quantile(1 - (1 - ciLevel) / 2, t.df)
              : 0.0;
          return FactorInsight(
            factor: t.factor,
            avgWith: Stats.mean(t.withV),
            avgWithout: Stats.mean(t.withoutV),
            delta: t.delta,
            standardError: t.se,
            confidence: solid.contains(i)
                ? InsightConfidence.solid
                : InsightConfidence.emerging,
            daysWith: t.withV.length,
            daysWithout: t.withoutV.length,
            ciLow: t.delta - q * t.se,
            ciHigh: t.delta + q * t.se,
            pValue: t.p,
          );
        }(),
    ];
    // Strongest |effect| first (Journal.swift:199-200).
    result.sort((a, b) {
      final c = b.delta.abs().compareTo(a.delta.abs());
      return c != 0 ? c : a.factor.index.compareTo(b.factor.index);
    });
    return result;
  }
}
