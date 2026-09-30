// The home-screen widgets' snapshot (lib/data/services/widget/widget_sink.dart):
// one payload per state (fresh, stale, empty, sample data, calibrating),
// the plan slice, and the QA-08 rule that a widget never shows yesterday's
// numbers as today's. See docs/WIDGETS_PLAN.md §3–4.

import 'dart:async';

import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/data/services/widget/widget_sink.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:airlog/domain/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';

final morning = DateTime(2026, 9, 29, 9, 30);
const today = '2026-09-29';

RecoveryResult rec(
  int score, {
  bool calibrating = false,
  bool withoutHrv = false,
  RecoveryConfidence confidence = RecoveryConfidence.high,
}) => RecoveryResult(
  score: score,
  zone: RecoveryResult.zoneFor(score),
  calibrating: calibrating,
  withoutHrv: withoutHrv,
  confidence: confidence,
  components: [
    if (!withoutHrv)
      const RecoveryComponent(
        key: 'hrv',
        label: 'HRV',
        score01: 0.6,
        weight: 0.4,
        detail: '',
        value: 52,
        baseline: Baseline(mean: 47, sd: 5, count: 20),
      ),
    const RecoveryComponent(
      key: 'rhr',
      label: 'Resting HR',
      score01: 0.6,
      weight: 0.25,
      detail: '',
      value: 54,
      baseline: Baseline(mean: 56, sd: 2, count: 20),
    ),
  ],
);

StrainResult strain(
  double so, {
  double? target = 14.4,
  StrainMethod method = StrainMethod.hrZones,
}) => StrainResult(
  strain: so,
  rawLoad: 100,
  zoneMinutes: const [0, 0, 0, 0, 0],
  method: so > 0 ? method : StrainMethod.none,
  targetStrain: target,
);

SleepAnalysis sleep({double slept = 410, double need = 456}) => SleepAnalysis(
  sleptMinutes: slept,
  napMinutes: 0,
  needMinutes: need,
  performance: slept / need * 100,
  debtAfterMinutes: 30,
  stageMinutes: const {},
  hasData: true,
);

DayBundle bundle({
  String date = today,
  RecoveryResult? recovery,
  StrainResult? strainResult,
  SleepAnalysis? sleepResult,
  bool noSleep = false,
  BedtimeRecommendation? bedtime,
  Calibration calibration = const Calibration(haveNights: 20),
}) => DayBundle(
  DayRecord(
    date: date,
    hrvRmssd: recovery == null || recovery.withoutHrv ? null : 52,
    restingHr: recovery == null ? null : 54,
    hrSamples: [HrSample(DateTime(2026, 9, 29, 8), 70)],
    lastDataAt: morning.subtract(const Duration(minutes: 20)),
  ),
  DayResult(
    date: date,
    algoVersion: kAlgoVersion,
    computedAt: morning,
    health: const HealthMonitorResult(metrics: [], alert: false),
    calibration: calibration,
    recovery: recovery,
    strain: strainResult,
    sleep: noSleep ? null : (sleepResult ?? sleep()),
    bedtime: bedtime,
  ),
);

WidgetSnapshot snap(
  DayBundle b, {
  bool demo = false,
  String? day = today,
  DateTime? now,
}) {
  final at = now ?? morning;
  return WidgetSnapshot.fromDays(
    [b],
    demo: demo,
    today: day,
    plan: Engine.planToday(b, now: at),
    now: at,
  );
}

Map<String, Object?> json(WidgetSnapshot s) =>
    s.toJson(updatedAt: DateTime(2026, 9, 29, 9, 31));

Map<String, Object?> dots(WidgetSnapshot s) =>
    (json(s)['dots']! as Map).cast<String, Object?>();

Map<String, Object?> planJson(WidgetSnapshot s) =>
    (json(s)['plan']! as Map).cast<String, Object?>();

void main() {
  group('payload per state', () {
    test('fresh: every slot is a measured or derived number', () {
      final s = snap(
        bundle(recovery: rec(72), strainResult: strain(8.44)),
      );
      final j = json(s);
      expect(j['v'], 2);
      expect(j['date'], today);
      expect(j['stale'], isFalse);
      expect(j['demo'], isFalse);
      expect(j['recovery'], 72);
      expect(j['zone'], 'green');
      expect(j['recStatus'], 'Good');
      expect(j['recBasis'], '');
      expect(j['strain'], '8.4');
      expect(j['strainTarget'], '14.4');
      expect(j['strainEst'], isFalse);
      expect(j['sleep'], '6h 50m');
      expect(j['sleepPerf'], (410 / 456 * 100).round());
      expect(dots(s), {
        'recovery': '72',
        'strain': '8.4',
        'sleep': '${(410 / 456 * 100).round()}',
      });
      final p = planJson(s);
      expect(p['state'], DayState.ready.name);
      expect(p['headline'], 'Ready to push');
      expect(p['stale'], isFalse);
      expect(p['phase'], PlanPhase.today.name);
      expect(p['action'], isNotNull);
      expect(p['until'], DateTime(2026, 9, 29, 18).millisecondsSinceEpoch);
    });

    test('stale: the values stay, flagged, when the day is not today', () {
      final s = snap(
        bundle(
          date: '2026-09-28',
          recovery: rec(72),
          strainResult: strain(8.4),
        ),
      );
      expect(s.stale, isTrue);
      expect(json(s)['stale'], isTrue);
      expect(json(s)['date'], '2026-09-28');
      expect(dots(s)['recovery'], '72');
      // The planner is stale-aware: no effort advice for a day behind.
      expect(planJson(s)['state'], DayState.noData.name);
    });

    test('empty: no day at all', () {
      final s = WidgetSnapshot.fromDays(
        const [],
        demo: false,
        today: today,
        now: morning,
      );
      final j = json(s);
      expect(j['date'], '');
      expect(j['recovery'], isNull);
      expect(j['recStatus'], WidgetSnapshot.noData);
      expect(j['plan'], isNull);
      expect(dots(s), {'recovery': '--', 'strain': '--', 'sleep': '--'});
    });

    test('sample data: the demo flag rides in the same payload', () {
      final fresh = snap(bundle(recovery: rec(72)), demo: true);
      expect(json(fresh)['demo'], isTrue);
      final empty = WidgetSnapshot.fromDays(const [], demo: true);
      expect(json(empty)['demo'], isTrue);
    });

    test('calibrating: no recovery number, "Learning"', () {
      final s = snap(
        bundle(
          recovery: rec(60, calibrating: true),
          calibration: const Calibration(haveNights: 3),
        ),
      );
      expect(s.recovery, isNull);
      expect(json(s)['recStatus'], 'Learning');
      expect(json(s)['quality'], 'learning');
      expect(dots(s)['recovery'], '--');
    });

    test('basis words follow Today’s Recovery title', () {
      final s = snap(
        bundle(
          recovery: rec(50, withoutHrv: true),
          calibration: const Calibration(haveNights: 8),
        ),
      );
      expect(s.recoveryBasis, ['without HRV', 'provisional']);
      expect(json(s)['recStatus'], 'Fair');
      final low = snap(
        bundle(recovery: rec(20, confidence: RecoveryConfidence.low)),
      );
      expect(low.recoveryBasis, ['provisional']);
      expect(json(low)['recStatus'], 'Low');
    });

    test('no heart rate: no strain score, no sleep: no sleep numbers', () {
      final s = snap(
        bundle(recovery: rec(72), strainResult: strain(0), noSleep: true),
      );
      final j = json(s);
      expect(j['strain'], '–', reason: 'the text key keeps its old value');
      expect(j['strainTarget'], isNull);
      expect(j['sleepPerf'], isNull);
      expect(dots(s)['strain'], '--');
      expect(dots(s)['sleep'], '--');
    });

    test('an estimated strain says so', () {
      final s = snap(
        bundle(
          recovery: rec(72),
          strainResult: strain(5.2, method: StrainMethod.fallback),
        ),
      );
      expect(json(s)['strainEst'], isTrue);
    });

    test('dot slots never use the en dash (the dot face has no ink for it)',
        () {
      for (final s in [
        snap(bundle()),
        snap(bundle(recovery: rec(72), strainResult: strain(8.4))),
        WidgetSnapshot.fromDays(const [], demo: false),
      ]) {
        for (final v in dots(s).values) {
          expect(v, isNot(contains('–')));
          expect(v, isNot(contains('—')));
          expect(
            (v! as String).split('').every(DotMatrixNumber.glyphs.contains),
            isTrue,
            reason: '"$v" must be drawable in the dot face',
          );
        }
      }
    });
  });

  group('plan slice', () {
    test('the next phase boundary is 05:00 or 18:00, local', () {
      expect(
        WidgetPlan.nextBoundary(DateTime(2026, 9, 29, 4, 10)),
        DateTime(2026, 9, 29, 5),
      );
      expect(
        WidgetPlan.nextBoundary(DateTime(2026, 9, 29, 9, 30)),
        DateTime(2026, 9, 29, 18),
      );
      expect(
        WidgetPlan.nextBoundary(DateTime(2026, 9, 29, 18)),
        DateTime(2026, 9, 30, 5),
      );
      expect(
        WidgetPlan.nextBoundary(DateTime(2026, 9, 29, 23, 59)),
        DateTime(2026, 9, 30, 5),
      );
    });

    test('evening: the tonight phase, and the boundary is tomorrow 05:00', () {
      final at = DateTime(2026, 9, 29, 20, 15);
      final s = snap(
        bundle(
          recovery: rec(72),
          strainResult: strain(8.4),
          // The tonight phase speaks about bedtime, so it needs one.
          bedtime: const BedtimeRecommendation(
            projectedNeedMinutes: 485,
            debtMinutes: 80,
            habitualWakeMinutes: 405,
            recommendedBedtimeMinutes: -80,
          ),
        ),
        now: at,
      );
      final p = planJson(s);
      expect(p['phase'], PlanPhase.tonight.name);
      expect((p['eyebrow']! as String).split(' · '), contains('Tonight'));
      expect(p['until'], DateTime(2026, 9, 30, 5).millisecondsSinceEpoch);
    });

    test('the headline and action are the planner’s own words', () {
      final b = bundle(recovery: rec(30), strainResult: strain(3));
      final plan = Engine.planToday(b, now: morning);
      final w = WidgetPlan.of(plan, now: morning);
      expect(w.headline, plan.headline);
      expect(w.action, plan.actions.firstOrNull?.title);
      expect(w.why, plan.actions.firstOrNull?.why);
    });

    test('the basis line matches PlanTile.basis word for word', () {
      const base = TodayPlan(
        date: today,
        state: DayState.steady,
        headline: 'A normal day',
        summary: 'x',
      );
      final plans = [
        base,
        const TodayPlan(
          date: today,
          state: DayState.easy,
          headline: 'h',
          summary: 's',
          phase: PlanPhase.tonight,
          stale: true,
          provisional: true,
          missingInputs: InputGap.values,
          relearningSource: 'Oura',
        ),
        const TodayPlan(
          date: today,
          state: DayState.calibrating,
          headline: 'h',
          summary: 'Re-learning your normal with Oura: 2 of 14 nights.',
          relearningSource: 'Oura',
        ),
      ];
      for (final p in plans) {
        expect(WidgetPlan.basis(p), PlanTile.basis(p));
      }
      for (final g in InputGap.values) {
        expect(WidgetPlan.gapLabel(g), PlanTile.gapLabel(g));
      }
    });
  });

  test('the repository pushes a plan with the snapshot (demo, QA-08 kept)',
      () async {
    final sink = _CapturingSink();
    final repo = InMemoryHealthRepository.demo(
      now: DateTime(2026, 9, 28, 9, 30),
      days: 40,
      widgets: sink,
    );
    await repo.start();
    final s = await sink.first.future.timeout(const Duration(seconds: 20));
    final latest = (await repo.latestDate())!;
    expect(s.demo, isTrue);
    expect(s.date, latest);
    expect(s.stale, latest != DayKey.of(DateTime(2026, 9, 28, 9, 30)));
    expect(s.plan, isNotNull);
    expect(s.plan!.headline, isNotEmpty);
    await repo.dispose();
  });
}

class _CapturingSink implements WidgetSink {
  final first = Completer<WidgetSnapshot>();
  @override
  Future<void> push(WidgetSnapshot snapshot) async {
    if (!first.isCompleted) first.complete(snapshot);
  }
}
