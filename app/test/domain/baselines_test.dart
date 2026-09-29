// Definition-keyed baselines, source-switch segmentation and calibration
// counting. [ours]

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/baselines.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/health_monitor.dart';
import 'package:airlog/domain/engine/recovery.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/builders.dart';

void main() {
  // 20 nights of all-night HC RMSSD (~40 ms), then Google Health deep-sleep
  // RMSSD (~80 ms: a different measurement, not a physiological change).
  final hcDays = [
    for (var i = 0; i < 20; i++)
      denseDay(
        DayKey.add('2026-08-01', i),
        hrv: 38 + (i % 5).toDouble(),
        hr: false,
      ),
  ];
  List<DayRecord> ghDays(int n) => [
    for (var i = 0; i < n; i++)
      denseDay(
        DayKey.add('2026-08-21', i),
        hrv: 78 + (i % 5).toDouble(),
        hrvProv: ghHrv,
        hr: false,
      ),
  ];

  group('source switch starts a new baseline segment', () {
    test('first night on the new source: no HRV baseline, calibrating', () {
      final today = ghDays(1).first;
      final r = RecoveryEngine.compute(today: today, history: hcDays)!;
      final hrv = r.components.firstWhere((c) => c.key == 'hrv');
      expect(hrv.baseline, isNull, reason: 'must not mix 40 ms HC nights in');
      expect(hrv.score01, 0.5);
      expect(r.hrvBaseline, isNull);
      expect(r.calibrating, isTrue);
      // RHR keeps its own (unchanged) definition and baseline.
      expect(r.rhrBaseline?.count, 20);
    });

    test('after 6 nights the baseline holds only the new definition', () {
      final gh = ghDays(7);
      final history = [...hcDays, ...gh.sublist(0, 6)];
      final r = RecoveryEngine.compute(today: gh.last, history: history)!;
      expect(r.hrvBaseline!.count, 6);
      expect(
        r.hrvBaseline!.mean > 75,
        isTrue,
        reason: '${r.hrvBaseline!.mean}',
      );
      final hrv = r.components.firstWhere((c) => c.key == 'hrv');
      expect(hrv.z!.abs() < 3, isTrue, reason: 'z vs own segment: ${hrv.z}');
    });

    test(
      'health monitor treats the switch night as calibrating, not "above"',
      () {
        final s = HealthMonitor.evaluate(
          ghDays(1).first,
          hcDays,
        ).firstWhere((m) => m.kind == HealthMetricKind.hrv);
        expect(s.state, BandState.calibrating);
        expect(s.provenance, ghHrv);
      },
    );

    test('engine emits a "new baseline" note exactly on the switch night', () {
      final results = Engine.computeRange([
        ...hcDays,
        ...ghDays(3),
      ], now: DateTime(2026, 9, 1));
      List<StatusNote> hrvNotes(String d) => results
          .firstWhere((r) => r.date == d)
          .notes
          .where((n) => n.metric == 'hrv' && n.title.startsWith('New'))
          .toList();
      expect(hrvNotes('2026-08-21'), hasLength(1));
      expect(hrvNotes('2026-08-22'), isEmpty);
      expect(hrvNotes('2026-08-20'), isEmpty);

      // The calibrating note counts the lagging input (new HRV segment),
      // not the 20 resting-HR nights.
      final day2 = results.firstWhere((r) => r.date == '2026-08-22');
      expect(day2.recovery!.calibrating, isTrue);
      final cal = day2.notes.firstWhere(
        (n) => n.title == 'Calibrating your baseline',
      );
      expect(cal.body, contains('5 nights of HRV (1 so far)'));
      expect(day2.calibration.haveNights, 21);
    });

    test('switching back resumes the old segment (definition-keyed)', () {
      final back = denseDay('2026-08-24', hrv: 40, hr: false);
      final r = RecoveryEngine.compute(
        today: back,
        history: [...hcDays, ...ghDays(3)],
      )!;
      expect(r.hrvBaseline!.count, 20);
      expect(r.hrvBaseline!.mean < 45, isTrue);
    });
  });

  group('segment rules', () {
    test('missing provenance matches missing provenance (Pulse behaviour)', () {
      final history = [
        for (var i = 0; i < 6; i++)
          DayRecord(date: DayKey.add('2026-06-01', i), hrvRmssd: 50),
      ];
      final today = DayRecord(date: '2026-06-07', hrvRmssd: 50);
      expect(Baselines.segmentValues(today, history, Metric.hrv), hasLength(6));
    });

    test('today without the metric uses the latest history definition', () {
      final history = [...hcDays, ...ghDays(4)];
      final today = denseDay('2026-08-25', hrv: null, hr: false);
      final seg = Baselines.segment(today, history, Metric.hrv);
      expect(seg.exists, isTrue);
      expect(seg.seg.key, ghHrv.baselineKey);
      expect(Baselines.segmentValues(today, history, Metric.hrv), hasLength(4));
    });

    test('window = N most recent matching values', () {
      final history = [
        for (var i = 0; i < 40; i++)
          DayRecord(
            date: DayKey.add('2026-05-01', i),
            restingHr: 50 + i.toDouble(),
            provenance: {Metric.restingHr: hcRhr},
          ),
      ];
      final today = DayRecord(
        date: '2026-06-10',
        restingHr: 60,
        provenance: {Metric.restingHr: hcRhr},
      );
      final v = Baselines.segmentValues(today, history, Metric.restingHr);
      expect(v, hasLength(30));
      expect(v.first, 60); // 50 + 10: the oldest of the last 30
      expect(v.last, 89);
    });
  });

  group('calibration counting', () {
    test('prior nights with HRV or RHR in the current segment', () {
      final history = <DayRecord>[
        for (var i = 0; i < 4; i++)
          DayRecord(
            date: DayKey.add('2026-06-01', i),
            hrvRmssd: 50,
            provenance: {Metric.hrv: hcHrv},
          ),
        for (var i = 4; i < 7; i++)
          DayRecord(
            date: DayKey.add('2026-06-01', i),
            restingHr: 55,
            provenance: {Metric.restingHr: hcRhr},
          ),
        for (var i = 7; i < 10; i++)
          DayRecord(date: DayKey.add('2026-06-01', i)),
      ];
      final today = DayRecord(
        date: '2026-06-11',
        hrvRmssd: 52,
        restingHr: 56,
        provenance: {Metric.hrv: hcHrv, Metric.restingHr: hcRhr},
      );
      expect(Baselines.calibrationNights(today, history), 7);

      // HRV switches source today: old HRV nights no longer count.
      final switched = DayRecord(
        date: '2026-06-11',
        hrvRmssd: 80,
        restingHr: 56,
        provenance: {Metric.hrv: ghHrv, Metric.restingHr: hcRhr},
      );
      expect(Baselines.calibrationNights(switched, history), 3);
    });

    test('DayResult.calibration uses config.calibrationNeedNights', () {
      final days = denseRange('2026-08-10', 8);
      final results = Engine.computeRange(
        days,
        config: const EngineConfig(calibrationNeedNights: 21),
        now: DateTime(2026, 8, 11),
      );
      expect(results.first.calibration.haveNights, 0);
      expect(results.last.calibration.haveNights, 7);
      expect(results.last.calibration.needNights, 21);
    });
  });
}
