// computeRange / computeDay mechanics, JSON round-trip, numerical hygiene,
// performance, and the full engine on Pulse's demo fixture. [ours]

import 'dart:convert';

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/builders.dart';
import 'fixtures/pulse_demo_data.dart';

String enc(DayResult r) => jsonEncode(r.toJson());

void main() {
  final now = DateTime(2026, 9, 1, 12);
  const withAge = EngineConfig(
    profile: UserProfile(birthYear: 1992, sex: Sex.male),
  );

  group('computeRange mechanics', () {
    test(
      'unsorted input with gaps and duplicates → one sorted result per date',
      () {
        final days = denseRange('2026-08-20', 10);
        final dupe = denseDay('2026-08-15', rhr: 70);
        final input = [
          ...days.reversed.where((d) => d.date != '2026-08-13'), // gap
          dupe, // later duplicate wins
        ];
        final results = Engine.computeRange(input, now: now);
        expect(results.map((r) => r.date).toList(), [
          for (final d in days)
            if (d.date != '2026-08-13') d.date,
        ]);
        final r15 = results.firstWhere((r) => r.date == '2026-08-15');
        expect(r15.recovery!.rhrValue, 70);
        for (final r in results) {
          expect(r.algoVersion, kAlgoVersion);
          expect(r.computedAt, now);
        }
      },
    );

    test('invalid dates are skipped', () {
      final results = Engine.computeRange([
        DayRecord(date: 'garbage'),
        DayRecord(date: '2026-02-30'),
        denseDay('2026-08-01'),
      ], now: now);
      expect(results.map((r) => r.date), ['2026-08-01']);
    });

    test('each day sees only strictly earlier days as history', () {
      final results = Engine.computeRange(
        denseRange('2026-08-20', 6),
        now: now,
      );
      expect(results.first.recovery!.rhrBaseline, isNull);
      expect(results[3].recovery!.rhrBaseline!.count, 3);
      expect(results.last.recovery!.rhrBaseline!.count, 5);
    });

    test(
      'sleep debt carries across a gap; strain boost only from yesterday',
      () {
        DayRecord short(String d) {
          final r = denseDay(d, hr: false, workout: false);
          return DayRecord(
            date: d,
            restingHr: 55,
            sleepSessions: [
              SleepSession(
                id: 's$d',
                start: r.sleepSessions.first.start,
                end: r.sleepSessions.first.start.add(const Duration(hours: 5)),
                minutesAsleep: 300,
                minutesAwake: 0,
              ),
            ],
          );
        }

        final results = Engine.computeRange([
          short('2026-08-01'),
          short('2026-08-04'),
        ], now: now);
        final d1 = results[0].sleep!;
        final d4 = results[1].sleep!;
        expect(d1.debtAfterMinutes, closeTo(156, 1e-9));
        expect(d4.needBreakdown!.debtMinutes, closeTo(156 * 0.30, 1e-9));
        expect(
          d4.needBreakdown!.strainMinutes,
          0,
          reason: 'previous is 3 days back',
        );
        expect(d4.debtAfterMinutes, closeTo(300, 1e-9)); // 156 + 156, capped
        for (final r in results) {
          final b = r.sleep!.needBreakdown!;
          expect(
            b.baselineMinutes + b.debtMinutes + b.strainMinutes,
            closeTo(r.sleep!.needMinutes, 1e-9),
          );
        }
      },
    );

    test(
      'computeDay == matching day of computeRange (with historyResults)',
      () {
        final days = denseRange('2026-08-31', 40);
        final all = Engine.computeRange(days, config: withAge, now: now);
        final rest = Engine.computeRange(
          days.sublist(0, 39),
          config: withAge,
          now: now,
        );
        final single = Engine.computeDay(
          days.last,
          history: days.sublist(0, 39).reversed.toList(), // any order
          previous: rest.last,
          historyResults: rest,
          config: withAge,
          now: now,
        );
        expect(enc(single), enc(all.last));

        // Without historyResults only Pulse Age (30 nights of sleep
        // performance) may differ; every other section is identical.
        final bare = Engine.computeDay(
          days.last,
          history: days.sublist(0, 39),
          previous: rest.last,
          config: withAge,
          now: now,
        );
        final a = bare.toJson()..remove('pulseAge');
        final b = all.last.toJson()..remove('pulseAge');
        expect(jsonEncode(a), jsonEncode(b));
      },
    );
  });

  group('JSON round-trip (results.dart toJson/fromJson)', () {
    test('engine-produced DayResult with every section', () {
      final days = denseRange('2026-08-31', 40);
      days.last
        ..spo2Avg = 95
        ..spo2Min = 88; // triggers the SpO₂ penalty
      final r = Engine.computeRange(days, config: withAge, now: now).last;
      expect(r.recovery, isNotNull);
      expect(r.recovery!.penalties, isNotEmpty);
      expect(r.strain!.workouts, isNotEmpty);
      expect(r.strain!.loadZoneMinutes, hasLength(6));
      expect(r.strain!.trimp, isNotNull);
      expect(r.strain!.targetStrain, isNotNull);
      expect(r.sleep!.needBreakdown, isNotNull);
      expect(r.bedtime, isNotNull);
      expect(r.readiness, isNotNull);
      // Pulse Age is not computed in v1 (product-critic review, 2026-09-29;
      // v2 candidate once a MEASURED VO₂max is required). The hand-built
      // result below still round-trips the section.
      expect(r.pulseAge, isNull);
      expect(r.strain!.maxHrSource, MaxHrSource.birthYear);
      // A complete day with a birth year has no honesty notes left.
      final json = enc(r);
      final back = DayResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(enc(back), json);
    });

    test('hand-built DayResult with alert and every optional field', () {
      final t = DateTime.utc(2026, 8, 31, 6, 30).toLocal();
      final r = DayResult(
        date: '2026-08-31',
        algoVersion: kAlgoVersion,
        computedAt: t,
        recovery: const RecoveryResult(
          score: 42,
          zone: RecoveryZone.yellow,
          components: [
            RecoveryComponent(
              key: 'hrv',
              label: 'HRV',
              score01: 0.4,
              weight: 1,
              detail: 'd',
              value: 40,
              baseline: Baseline(mean: 45, sd: 5, count: 20),
              z: -1.2,
            ),
          ],
          penalties: [RecoveryPenalty('spo2', 'x', 7)],
          calibrating: false,
          hrvValue: 40,
          hrvBaseline: Baseline(mean: 45, sd: 5, count: 20),
          rhrValue: 56,
          rhrBaseline: Baseline(mean: 54, sd: 2, count: 20),
        ),
        strain: const StrainResult(
          strain: 12.5,
          rawLoad: 300,
          zoneMinutes: [10, 5, 4, 3, 1],
          loadZoneMinutes: [1, 2, 3, 4, 5, 6],
          method: StrainMethod.hrZones,
          restMinutes: 900,
          avgHr: 80,
          peakHr: 170,
          maxHrUsed: 187,
          restingHrUsed: 55,
          trimp: 90,
          targetStrain: 8.4,
          workouts: [
            WorkoutStrain(
              workoutId: 'w',
              strain: 10,
              zoneMinutes: [1, 2, 3, 4, 5],
              avgHr: 150,
              peakHr: 175,
              trimp: 60,
              method: StrainMethod.fallback,
            ),
          ],
        ),
        sleep: SleepAnalysis(
          sleptMinutes: 420,
          napMinutes: 20,
          needMinutes: 480,
          performance: 87.5,
          debtAfterMinutes: 60,
          stageMinutes: const {SleepStage.deep: 80, SleepStage.rem: 90},
          hasData: true,
          consistency: 80,
          efficiency: 92,
          bedTime: t.subtract(const Duration(hours: 8)),
          wakeTime: t,
          needBreakdown: const SleepNeedBreakdown(
            baselineMinutes: 456,
            debtMinutes: 18,
            strainMinutes: 6,
          ),
        ),
        bedtime: const BedtimeRecommendation(
          projectedNeedMinutes: 470,
          debtMinutes: 60,
          habitualWakeMinutes: 400,
          recommendedBedtimeMinutes: 1370,
        ),
        health: const HealthMonitorResult(
          metrics: [
            HealthMetricStatus(
              kind: HealthMetricKind.restingHr,
              state: BandState.above,
              value: 62,
              baseline: Baseline(mean: 54, sd: 2, count: 20),
              lower: 50.7,
              upper: 57.3,
              provenance: hcRhr,
            ),
          ],
          alert: true,
          alertReason: 'Resting HR has been elevated for 2 days',
        ),
        readiness: const ReadinessSwc(
          lnRmssd7d: 3.8,
          baselineMean: 3.9,
          swcLower: 3.85,
          swcUpper: 3.95,
          state: SwcState.below,
          cv7d: 4.2,
        ),
        pulseAge: const PulseAgeResult(
          chronoAge: 34,
          pulseAge: 31.5,
          components: [
            AgeComponent(
              key: 'fitness',
              label: 'Fitness',
              detail: 'd',
              deltaYears: -3,
              kind: AgeComponentKind.equivalent,
            ),
          ],
          calibrating: false,
          calibrationHave: 30,
          calibrationNeed: 30,
          vo2max: 47,
          fitnessAge: 30,
        ),
        calibration: const Calibration(haveNights: 20, needNights: 14),
        notes: const [
          StatusNote(
            metric: 'hrv',
            title: 't',
            body: 'b',
            severity: NoteSeverity.warning,
            fix: 'f',
          ),
        ],
      );
      final json = enc(r);
      final back = DayResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(enc(back), json);
      expect(back.strain!.workouts.single.method, StrainMethod.fallback);
      expect(back.strain!.loadZoneMinutes, [1, 2, 3, 4, 5, 6]);
    });

    test('rows written before the additive fields still decode', () {
      final legacy = {
        'strain': 5.0,
        'rawLoad': 100.0,
        'zoneMinutes': [0, 0, 0, 0, 0],
        'method': 'hrZones',
        'workouts': [
          {
            'workoutId': 'w',
            'strain': 3.0,
            'zoneMinutes': [0, 0, 0, 0, 0],
          },
        ],
      };
      final s = StrainResult.fromJson(legacy);
      expect(s.loadZoneMinutes, isEmpty);
      expect(s.workouts.single.method, isNull);
    });
  });

  group('numerical hygiene', () {
    test('no NaN / Infinity escapes from degenerate inputs', () {
      final t = DayKey.start('2026-08-10');
      final degenerate = <DayRecord>[
        DayRecord(date: '2026-08-01'),
        DayRecord(
          date: '2026-08-02',
          hrvRmssd: 0,
          restingHr: double.nan,
          respiratoryRate: double.infinity,
          spo2Avg: -5,
          spo2Min: double.nan,
          skinTempDelta: double.negativeInfinity,
          vo2max: 0,
          steps: -10,
        ),
        DayRecord(
          date: '2026-08-03',
          hrvRmssd: -20,
          restingHr: 0,
          sleepSessions: [
            SleepSession(
              id: 'bad',
              start: t,
              end: t.subtract(const Duration(hours: 2)),
              minutesAsleep: double.nan,
              minutesAwake: double.infinity,
            ),
          ],
          workouts: [
            Workout(
              id: 'w0',
              name: '',
              start: t,
              end: t,
              averageHr: double.nan,
            ),
          ],
          hrSamples: [
            HrSample(t, double.nan),
            HrSample(t, 0),
            HrSample(t, 1e9),
            HrSample(t.add(const Duration(minutes: 1)), 60),
          ],
        ),
        DayRecord(
          date: '2026-08-04',
          hrvRmssd: 1e-300,
          restingHr: 60,
          hrSamples: [for (var i = 0; i < 400; i++) HrSample(t, 60)],
        ),
        for (var i = 5; i < 20; i++)
          DayRecord(
            date: DayKey.add('2026-08-01', i),
            hrvRmssd: 50,
            restingHr: 55,
            respiratoryRate: 14,
            skinTempDelta: 0,
            spo2Avg: 97,
            spo2Min: 95,
          ),
      ];
      for (final config in [
        const EngineConfig(),
        withAge,
        const EngineConfig(
          profile: UserProfile(birthYear: 1990, maxHrOverride: 50),
          sleep: SleepConfig(baselineNeedMinutes: 0),
          strainTau: 0,
          baselineWindowDays: 0,
        ),
      ]) {
        final results = Engine.computeRange(
          degenerate,
          config: config,
          now: now,
        );
        expect(results, isNotEmpty);
        for (final r in results) {
          final json = r.toJson();
          expect(() => jsonEncode(json), returnsNormally, reason: r.date);
          expect(nonFinite(json), isEmpty, reason: r.date);
        }
      }
    });

    test('facade helpers are finite on degenerate input', () {
      expect(Engine.rmssdFromRr([double.nan, double.infinity, -1]), isNull);
      expect(Engine.baevskyStress(const []), isNull);
      expect(Engine.hrr60([HrSample(now, double.nan)], now), isNull);
      final w = Engine.liveWorkoutStrain(
        [HrSample(now, double.nan)],
        restingHr: double.nan,
        now: now,
      );
      expect(nonFinite(w.toJson()), isEmpty);
      expect(
        Engine.trainingLoad({'2026-08-01': double.nan}, '2026-08-01'),
        isNull,
      );
    });
  });

  // 1-min HR all day, staged sleep, a workout, every nightly metric, and NO
  // measured VO₂max (the worst case: Pulse Age then needs the 30-day p97.5
  // of intraday HR every day). Timed after one JIT warm-up run; best of 3
  // to damp noise from other processes. Cold time is reported alongside.
  // Budget is 300 ms on a quiet machine (measured 150–255 ms warm); the
  // assertion allows 2x headroom so CI/parallel builds don't flake. A real
  // regression (e.g. an O(n²) baseline) blows far past 600 ms.
  test('performance: 365 dense days in < 600 ms (300 ms budget)', () {
    final days = [
      for (var i = 0; i < 365; i++)
        denseDay(
          DayKey.add('2025-09-01', i),
          hrv: 45 + (i % 9).toDouble(),
          rhr: 52 + (i % 4).toDouble(),
          spo2Avg: 96,
          spo2Min: 93,
        ),
    ];
    expect(days.first.hrSamples.length, 1440);
    final cold = Stopwatch()..start();
    Engine.computeRange(days, config: withAge, now: now);
    cold.stop();
    var best = 1 << 30;
    late List<DayResult> results;
    for (var run = 0; run < 3; run++) {
      final sw = Stopwatch()..start();
      results = Engine.computeRange(days, config: withAge, now: now);
      sw.stop();
      if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
    }
    expect(results, hasLength(365));
    expect(results.last.pulseAge, isNull, reason: 'no Pulse Age in v1');
    expect(
      best < 600,
      isTrue,
      reason:
          '365 days took $best ms warm (cold ${cold.elapsedMilliseconds} ms)',
    );
  });

  group('full engine on Pulse demo data (end-to-end sanity)', () {
    final results = Engine.computeRange(
      pulseDemo().values.toList(),
      config: const EngineConfig(
        profile: UserProfile(birthYear: 1996, sex: Sex.male),
      ),
      now: kPulseNow,
    );
    test('120 results, scores in range', () {
      expect(results, hasLength(120));
      for (final r in results) {
        if (r.recovery != null) {
          expect(r.recovery!.score >= 1 && r.recovery!.score <= 99, isTrue);
        }
        expect(r.strain!.strain >= 0 && r.strain!.strain <= 21, isTrue);
        expect(r.sleep!.hasData, isTrue);
        expect(r.health.metrics, hasLength(5));
      }
      expect(results.last.recovery, isNotNull);
      expect(results.last.pulseAge, isNull, reason: 'no Pulse Age in v1');
    });
    test('2-minute demo HR is sparse by our rule → partial HR-zone strain '
        '(never a steps/MET estimate)', () {
      final last28 = results.sublist(results.length - 28);
      expect(
        last28.every((r) => r.strain!.method == StrainMethod.hrZones),
        isTrue,
      );
      expect(
        last28.every(
          (r) =>
              r.notes.any((n) => n.title == 'Strain from partial heart rate'),
        ),
        isTrue,
      );
    });
  });
}
