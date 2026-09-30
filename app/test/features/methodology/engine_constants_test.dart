// The copy reads the engine's named constants, and the constants that
// mirror a contract rule (zone cut-points, "reliable" baseline count, load
// bands) still agree with it. Also: one definition of the HRV "usual" (the
// raw mean) in the engine's own detail string.

import 'package:airlog/design/design.dart';
import 'package:airlog/domain/engine/health_monitor.dart';
import 'package:airlog/domain/engine/load_and_trends.dart';
import 'package:airlog/domain/engine/recovery.dart';
import 'package:airlog/domain/engine/sleep.dart';
import 'package:airlog/domain/engine/stats.dart';
import 'package:airlog/domain/engine/strain.dart';
import 'package:airlog/domain/engine/strain_fallback.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/engine/engine.dart' show SleepConfig;
import 'package:airlog/domain/results.dart';
import 'package:airlog/features/methodology/methodology_screen.dart';
import 'package:flutter/material.dart' show Navigator, NavigatorState, Size;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

void main() {
  setUpAll(loadAppFonts);

  group('mirrors of contract rules', () {
    test('zone cut-points match RecoveryResult.zoneFor', () {
      const g = RecoveryEngine.greenFrom, y = RecoveryEngine.yellowFrom;
      expect(RecoveryResult.zoneFor(g), RecoveryZone.green);
      expect(RecoveryResult.zoneFor(g - 1), RecoveryZone.yellow);
      expect(RecoveryResult.zoneFor(y), RecoveryZone.yellow);
      expect(RecoveryResult.zoneFor(y - 1), RecoveryZone.red);
    });

    test('reliable nights match Baseline.isReliable', () {
      const n = RecoveryEngine.reliableNights;
      expect(const Baseline(mean: 1, sd: 1, count: n).isReliable, isTrue);
      expect(const Baseline(mean: 1, sd: 1, count: n - 1).isReliable, isFalse);
    });

    test('a baseline needs Stats.minBaselineValues values', () {
      const n = Stats.minBaselineValues;
      expect(Stats.baseline(List.filled(n, 1.0)), isNotNull);
      expect(Stats.baseline(List.filled(n - 1, 1.0)), isNull);
    });

    test('the ACWR gauge bands are the engine cut-points', () {
      expect(AcwrGauge.bands[0].$2, TrainingLoadEngine.optimalFrom);
      expect(AcwrGauge.bands[1].$2, TrainingLoadEngine.optimalTo);
      expect(AcwrGauge.bands[2].$2, TrainingLoadEngine.elevatedTo);
      for (final (lo, hi, state) in AcwrGauge.bands) {
        expect(TrainingLoadEngine.stateFor((lo + hi) / 2), state);
      }
    });

    test('the strain boost helper is the documented ramp', () {
      const cfg = SleepConfig();
      expect(SleepEngine.strainBoost(SleepEngine.strainBoostFrom, cfg), 0);
      expect(
        SleepEngine.strainBoost(
          SleepEngine.strainBoostFrom + SleepEngine.strainBoostSpan,
          cfg,
        ),
        cfg.strainNeedBoostMaxMinutes,
      );
    });
  });

  test('the HRV detail string uses the raw mean as "baseline"', () {
    final hrv = <double>[30, 40, 50, 60, 70, 45, 55];
    final history = [
      for (var i = 0; i < hrv.length; i++)
        DayRecord(date: '2026-09-${(10 + i).toString()}', hrvRmssd: hrv[i]),
    ];
    final rec = RecoveryEngine.compute(
      today: DayRecord(date: '2026-09-20', hrvRmssd: 52),
      history: history,
    )!;
    final c = rec.components.firstWhere((c) => c.key == 'hrv');
    final raw = hrv.reduce((a, b) => a + b) / hrv.length;
    expect(c.detail, '52 ms · baseline ${raw.toStringAsFixed(0)} ms');
    expect(c.baseline!.mean, closeTo(raw, 1e-9));
  });

  testWidgets('Methodology prints the engine constants (in its ⓘ sheets)', (
    t,
  ) async {
    // A tall view: every tile is built and on screen, so each ⓘ is tappable.
    await pumpB(
      t,
      const MethodologyScreen(),
      repo: ScreensBRepo.demo(),
      size: const Size(412, 6000),
    );
    await t.pumpAndSettle();
    String n(num v) => numText(v);
    final sheets = <String, List<String>>{
      'About How Recovery works': [
        'minimum SD of ${n(RecoveryEngine.hrvMinSd)} on the log scale',
        'resting heart rate ${n(RecoveryEngine.rhrMinSd)} bpm',
        'breathing rate ${n(RecoveryEngine.respMinSd)} /min',
        'logistic(${n(RecoveryEngine.hrvLogisticSlope)} × z)',
        'below ${n(RecoveryEngine.spo2PenaltyBelow)}% costs '
            '${n(RecoveryEngine.spo2Penalty)} points',
        'more than ${n(RecoveryEngine.skinTempPenaltyZ)} SD above',
        'Good (green) from ${RecoveryEngine.greenFrom}',
      ],
      'About How your sleep goal is set': [
        'Strain above ${n(SleepEngine.strainBoostFrom)}',
        '÷ ${n(SleepEngine.strainBoostSpan)}, 0, 1)',
        '0% means ${n(SleepEngine.consistencyZeroMinutes)} minutes off',
      ],
      'About How Strain works': [
        '${n(StrainEngine.tanakaIntercept)} − ${n(StrainEngine.tanakaSlope)} × age',
        'Effort goal: ${n(StrainEngine.targetFactor)} × the morning',
        'fewer than ${StrainDay.minSamples} readings',
      ],
      'About Overnight signals': [
        'never below ${n(HealthMonitor.spo2HardFloor)}%',
      ],
      'About Training load and trends': [
        'Below ${n(TrainingLoadEngine.optimalFrom)}: less than usual',
      ],
    };
    for (final MapEntry(key: label, value: strings) in sheets.entries) {
      final f = find.bySemanticsLabel(label);
      expect(f, findsOneWidget, reason: label);
      await t.tap(f);
      await t.pumpAndSettle();
      for (final s in strings) {
        expect(find.textContaining(s), findsWidgets, reason: '$label: $s');
      }
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pumpAndSettle();
    }
  });
}
