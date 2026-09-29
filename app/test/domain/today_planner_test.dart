// TodayPlanner: one test per rule (state, freshness, phase, each action,
// housekeeping, caps, basis, re-learning, tone, numbers). See
// lib/domain/engine/today_planner.dart for the rules table.

import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/health_monitor.dart';
import 'package:airlog/domain/engine/source_apps.dart';
import 'package:airlog/domain/engine/strain.dart';
import 'package:airlog/domain/engine/today_planner.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:airlog/domain/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/plan_numbers.dart';

final morning = DateTime(2026, 9, 29, 9, 30);
const today = '2026-09-29';

RecoveryResult rec(
  int score, {
  bool calibrating = false,
  double? hrv = 52,
  double hrvUsual = 47,
  double rhr = 54,
  double rhrUsual = 56,
}) => RecoveryResult(
  score: score,
  zone: RecoveryResult.zoneFor(score),
  calibrating: calibrating,
  withoutHrv: hrv == null,
  components: [
    if (hrv != null)
      RecoveryComponent(
        key: 'hrv',
        label: 'HRV',
        score01: 0.6,
        weight: 0.4,
        detail: '',
        value: hrv,
        baseline: Baseline(mean: hrvUsual, sd: 5, count: 20),
      ),
    RecoveryComponent(
      key: 'rhr',
      label: 'Resting HR',
      score01: 0.6,
      weight: 0.25,
      detail: '',
      value: rhr,
      baseline: Baseline(mean: rhrUsual, sd: 2, count: 20),
    ),
  ],
);

StrainResult strain({double? target, double so = 0}) => StrainResult(
  strain: so,
  rawLoad: 100,
  zoneMinutes: const [0, 0, 0, 0, 0],
  method: so > 0 ? StrainMethod.hrZones : StrainMethod.none,
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

const bed = BedtimeRecommendation(
  projectedNeedMinutes: 485,
  debtMinutes: 80,
  habitualWakeMinutes: 405,
  recommendedBedtimeMinutes: -80,
);

HealthMetricStatus vital(
  HealthMetricKind k,
  BandState s,
  double v,
  double usual,
) => HealthMetricStatus(
  kind: k,
  state: s,
  value: v,
  lower: usual - 3,
  upper: usual + 3,
  baseline: Baseline(mean: usual, sd: 1, count: 20),
);

final rhrHigh = vital(HealthMetricKind.restingHr, BandState.above, 61, 54);

DayBundle bundle({
  String date = today,
  RecoveryResult? recovery,
  StrainResult? strainResult,
  SleepAnalysis? sleepResult,
  bool noSleep = false,
  BedtimeRecommendation? bedtime,
  List<HealthMetricStatus> vitals = const [],
  Calibration calibration = const Calibration(haveNights: 20),
  Map<String, String> notShared = const {},
  SourceChange? sourceChange,
  DateTime? lastDataAt,
  DateTime? now,
  Map<Metric, Provenance>? provenance,
}) {
  final record = DayRecord(
    date: date,
    provenance: provenance,
    hrvRmssd: recovery?.withoutHrv == false ? 52 : null,
    restingHr: recovery == null ? null : 54,
    respiratoryRate: 14.5,
    skinTempDelta: 0.1,
    spo2Avg: 96,
    hrSamples: [HrSample(DateTime(2026, 9, 29, 8), 70)],
    lastDataAt:
        lastDataAt ?? (now ?? morning).subtract(const Duration(minutes: 20)),
  );
  return DayBundle(
    record,
    DayResult(
      date: date,
      algoVersion: kAlgoVersion,
      computedAt: morning,
      health: HealthMonitorResult(metrics: vitals, alert: false),
      calibration: calibration,
      recovery: recovery,
      strain: strainResult,
      sleep: noSleep ? null : (sleepResult ?? sleep()),
      bedtime: bedtime,
      notShared: notShared,
      sourceChange: sourceChange,
    ),
  );
}

TodayPlan plan(DayBundle b, {SyncStatus? sync, DateTime? now}) {
  final at = now ?? morning;
  final p = TodayPlanner.plan(today: b, sync: sync, now: at);
  // Every plan in this file also passes the number check.
  expect(
    unsupportedNumbers(p, allowedNumbers(b, sync: sync, now: at)),
    isEmpty,
  );
  expect(p.actions.length, lessThanOrEqualTo(3));
  expect(p.evidence.length, lessThanOrEqualTo(2));
  return p;
}

List<PlanActionKind> kinds(TodayPlan p) => [for (final a in p.actions) a.kind];

void main() {
  group('state', () {
    test('ready: green and fresh; the old summary card, ported', () {
      final p = plan(
        bundle(recovery: rec(72), strainResult: strain(target: 14.4)),
      );
      expect(p.state, DayState.ready);
      expect(p.headline, 'Ready to push');
      expect(
        p.summary,
        'Recovery 72%: HRV is 11% above your usual and resting HR below '
        'your usual (54 vs 56 bpm).',
      );
      expect(p.phase, PlanPhase.today);
      expect(p.stale, isFalse);
      expect(p.provisional, isFalse);
      expect(p.missingInputs, isEmpty);
    });

    test('"normal for you" inside ±5 % HRV and ±1.5 bpm', () {
      final p = plan(bundle(recovery: rec(60, hrv: 48, rhr: 56.5)));
      expect(
        p.summary,
        'Recovery 60%: HRV and resting HR are both normal for you.',
      );
    });

    test('short sleep is named', () {
      final p = plan(bundle(recovery: rec(50), sleepResult: sleep(slept: 300)));
      expect(p.summary, endsWith(', and sleep covered 66% of your target.'));
    });

    test('steady: yellow', () {
      final p = plan(bundle(recovery: rec(50)));
      expect(p.state, DayState.steady);
      expect(p.headline, 'A normal day');
    });

    test('green with stale inputs is steady', () {
      final p = plan(
        bundle(
          recovery: rec(80),
          strainResult: strain(target: 16),
          lastDataAt: morning.subtract(const Duration(hours: 13)),
        ),
      );
      expect(p.state, DayState.steady);
      expect(p.stale, isTrue);
    });

    test('freshness threshold is 12 h, SyncStatus.lastDataAt first', () {
      final b = bundle(
        recovery: rec(80),
        lastDataAt: morning.subtract(const Duration(hours: 20)),
      );
      SyncStatus at(Duration d) =>
          SyncStatus(phase: SyncPhase.idle, lastDataAt: morning.subtract(d));
      expect(
        plan(b, sync: at(const Duration(hours: 11, minutes: 59))).stale,
        isFalse,
      );
      expect(
        plan(b, sync: at(const Duration(hours: 12, minutes: 1))).stale,
        isTrue,
      );
    });

    test('easy: red recovery', () {
      final p = plan(bundle(recovery: rec(25)));
      expect(p.state, DayState.easy);
      expect(p.headline, 'Take it easy');
    });

    test('rest: recovery in the lower half of red', () {
      expect(TodayPlanner.restBelow, 17);
      final p = plan(bundle(recovery: rec(12)));
      expect(p.state, DayState.rest);
      expect(p.headline, 'Make it a rest day');
      expect(p.summary, startsWith('Recovery 12%, very low for you'));
    });

    test('easy: one concerning vital even with green recovery (the old '
        'alert card, ported)', () {
      final p = plan(bundle(recovery: rec(75), vitals: [rhrHigh]));
      expect(p.state, DayState.easy);
      expect(
        p.summary,
        'Resting HR higher (61 vs usual 54 bpm); Recovery 75%.',
      );
      expect(p.evidence.map((e) => e.label), ['Recovery', 'Resting HR']);
    });

    test('rest: two concerning vitals', () {
      final p = plan(
        bundle(
          recovery: rec(60),
          vitals: [
            rhrHigh,
            vital(HealthMetricKind.hrv, BandState.below, 30, 45),
          ],
        ),
      );
      expect(p.state, DayState.rest);
      expect(
        p.summary,
        'Resting HR higher (61 vs usual 54 bpm) and HRV lower (30 vs usual '
        '45 ms); Recovery 60%.',
      );
    });

    test('a vital outside its band the favourable way changes nothing', () {
      final p = plan(
        bundle(
          recovery: rec(75),
          vitals: [vital(HealthMetricKind.hrv, BandState.above, 70, 50)],
        ),
      );
      expect(p.state, DayState.ready);
      expect(kinds(p), isNot(contains(PlanActionKind.checkIn)));
    });

    test('calibrating: provisional; red does not mean easy', () {
      final p = plan(
        bundle(
          recovery: rec(20, calibrating: true),
          strainResult: strain(target: 4),
          calibration: const Calibration(haveNights: 3),
        ),
      );
      expect(p.state, DayState.calibrating);
      expect(p.headline, 'Still learning your normal');
      expect(p.provisional, isTrue);
      expect(
        p.summary,
        '3 of 14 baseline nights so far, so Recovery 20% is provisional.',
      );
      expect(kinds(p), [PlanActionKind.wear], reason: 'no effort advice');
      expect(p.actions.single.title, 'Keep wearing your tracker to bed');
    });

    test('re-learning a new source', () {
      final p = plan(
        bundle(
          recovery: rec(55, calibrating: true),
          calibration: const Calibration(haveNights: 2),
          sourceChange: const SourceChange(
            metric: 'hrv',
            nights: 2,
            from: Provenance(
              SourceKind.healthConnect,
              'hc_sleep_mean_rmssd',
              origin: SourceApps.fitbit,
            ),
            to: Provenance(
              SourceKind.healthConnect,
              'hc_sleep_mean_rmssd',
              origin: SourceApps.oura,
            ),
          ),
        ),
      );
      expect(p.relearningSource, 'Oura');
      expect(p.state, DayState.calibrating);
      expect(
        p.summary,
        'Re-learning your normal with Oura: 2 of 14 nights so far, so '
        'Recovery 55% is provisional.',
      );
      // Calibrating would ask to keep wearing; a new source re-learns
      // whatever you do, so there is no "wear" action.
      expect(kinds(p), isNot(contains(PlanActionKind.wear)));
      expect(p.actions, isEmpty);
    });

    const ouraSwitch = SourceChange(
      metric: 'hrv',
      nights: 2,
      from: Provenance(
        SourceKind.healthConnect,
        'hc_sleep_mean_rmssd',
        origin: SourceApps.fitbit,
      ),
      to: Provenance(
        SourceKind.healthConnect,
        'hc_sleep_mean_rmssd',
        origin: SourceApps.oura,
      ),
    );

    test('re-learning: never "wear", whatever the state; the summary says '
        're-learning instead', () {
      // Without the switch each of these offers "wear" as the sole action.
      final cases = {
        'no sleep, calibrated': bundle(recovery: rec(70), noSleep: true),
        'no Recovery today': bundle(noSleep: true),
        'without HRV': bundle(recovery: rec(60, hrv: null)),
      };
      for (final e in cases.entries) {
        final before = plan(e.value);
        expect(kinds(before), [PlanActionKind.wear], reason: e.key);
        final b = bundle(
          recovery: e.value.result.recovery,
          noSleep: e.value.result.sleep == null,
          sourceChange: ouraSwitch,
        );
        final p = plan(b);
        expect(p.relearningSource, 'Oura', reason: e.key);
        expect(kinds(p), isNot(contains(PlanActionKind.wear)), reason: e.key);
        expect(p.actions, isEmpty, reason: e.key);
        expect(
          p.summary,
          '${before.summary} Re-learning your normal with Oura: 2 of 14 '
          'nights so far.',
          reason: e.key,
        );
      }
    });

    test('re-learning: other actions are unchanged', () {
      final p = plan(
        bundle(
          recovery: rec(70),
          strainResult: strain(target: 12),
          bedtime: bed,
          sourceChange: ouraSwitch,
        ),
      );
      expect(kinds(p), [PlanActionKind.effort, PlanActionKind.sleep]);
      expect(p.summary, isNot(contains('Re-learning')));
      expect(p.relearningSource, 'Oura');
    });

    test('noData: no recovery today', () {
      final p = plan(bundle(noSleep: true));
      expect(p.state, DayState.noData);
      expect(p.headline, "Waiting for today's data");
      expect(kinds(p), [PlanActionKind.wear]);
    });

    test('noData: the app shares neither HRV nor resting HR (Samsung)', () {
      final p = plan(
        bundle(
          notShared: const {'hrv': 'Samsung Health', 'rhr': 'Samsung Health'},
        ),
      );
      expect(p.state, DayState.noData);
      expect(
        p.summary,
        "Samsung Health doesn't share HRV or resting heart rate with Health "
        'Connect, so there is no Recovery score; sleep and strain still work.',
      );
      expect(p.actions, isEmpty, reason: 'wearing the tracker will not help');
      expect(p.missingInputs, containsAll([InputGap.hrv, InputGap.heartRate]));
    });

    test('noData: the newest bundle is from yesterday → sync, sole action', () {
      final p = plan(
        bundle(
          date: '2026-09-28',
          recovery: rec(70),
          bedtime: bed,
          lastDataAt: DateTime(2026, 9, 28, 23, 10),
        ),
      );
      expect(p.state, DayState.noData);
      expect(
        p.summary,
        'Nothing for today has arrived yet; the newest data is from '
        'yesterday 23:10.',
      );
      expect(kinds(p), [PlanActionKind.sync]);
      expect(p.missingInputs, isEmpty);
      expect(p.stale, isFalse, reason: '10 h 20 m is inside 12 h');
    });
  });

  group('time of day', () {
    final evening = DateTime(2026, 9, 29, 21);

    test('tonight: sleep target and debt; no effort', () {
      final p = plan(
        bundle(
          recovery: rec(60),
          strainResult: strain(target: 12, so: 8),
          bedtime: bed,
          now: evening,
        ),
        now: evening,
      );
      expect(p.phase, PlanPhase.tonight);
      expect(
        p.summary,
        "Tonight's sleep target is 8 h 5 m, with 1 h 20 m of sleep debt "
        'carried.',
      );
      expect(kinds(p), [PlanActionKind.sleep]);
      expect(p.actions.single.title, 'Aim for bed by 22:40');
      expect(p.actions.single.why, 'Your usual wake-up is 06:45.');
      expect(p.evidence.first.label, 'Sleep target');
    });

    test('tonight, past the bedtime', () {
      final late = DateTime(2026, 9, 29, 23, 30);
      final p = plan(
        bundle(recovery: rec(60), bedtime: bed, now: late),
        now: late,
      );
      expect(p.actions.single.title, 'Head to bed when you can');
    });

    test('after midnight the evening is still yesterday', () {
      final night = DateTime(2026, 9, 30, 1, 30);
      final p = plan(
        bundle(recovery: rec(60), bedtime: bed, now: night),
        now: night,
      );
      expect(p.state, DayState.steady);
      expect(p.phase, PlanPhase.tonight);
      expect(p.actions.single.title, 'Head to bed when you can');
    });

    test('before the wake-up, a new day has no scores yet', () {
      final night = DateTime(2026, 9, 30, 2);
      final p = plan(
        bundle(date: '2026-09-30', noSleep: true, now: night),
        now: night,
      );
      expect(p.state, DayState.noData);
      expect(
        p.summary,
        "Today's scores arrive after you wake and your tracker syncs.",
      );
      expect(p.actions, isEmpty);
    });
  });

  group('actions', () {
    test('effort: range is target ± 1.5 in whole strain points', () {
      expect(StrainEngine.targetRange(7.4), (6, 9));
      expect(StrainEngine.targetRange(3), (2, 5));
      expect(StrainEngine.targetRange(18.5), (17, 20));
      final p = plan(
        bundle(recovery: rec(72), strainResult: strain(target: 14.4)),
      );
      final e = p.actions.first;
      expect(e.kind, PlanActionKind.effort);
      expect(e.title, 'Room to push: strain 13–16');
      expect(e.why, "Today's strain target is 14.4.");
      final easy = plan(
        bundle(recovery: rec(25), strainResult: strain(target: 5)),
      );
      expect(easy.actions.first.title, 'Keep effort light: strain 4–7');
      final rest = plan(
        bundle(recovery: rec(12), strainResult: strain(target: 3)),
      );
      expect(rest.actions.first.title, 'Move gently: strain 2–5');
    });

    test('effort: strain progress during the day', () {
      final p = plan(
        bundle(recovery: rec(58), strainResult: strain(target: 11.6, so: 7.2)),
      );
      expect(p.actions.first.title, 'Moderate effort: strain 10–13');
      expect(p.actions.first.why, 'Strain 7.2 so far of your 10–13 target.');
    });

    test('effort: range already reached', () {
      final p = plan(
        bundle(recovery: rec(72), strainResult: strain(target: 14.4, so: 17)),
      );
      expect(p.actions.first.title, "You've reached today's effort");
      expect(
        p.actions.first.why,
        'Strain 17.0 so far, past your 13–16 target.',
      );
    });

    test('effort: stale data gives no effort advice', () {
      final p = plan(
        bundle(
          recovery: rec(72),
          strainResult: strain(target: 14.4),
          bedtime: bed,
          lastDataAt: morning.subtract(const Duration(hours: 14)),
        ),
      );
      expect(kinds(p), [PlanActionKind.sleep]);
    });

    test('effort: a concerning vital overrides the range', () {
      final p = plan(
        bundle(
          recovery: rec(75),
          strainResult: strain(target: 15),
          vitals: [rhrHigh],
        ),
      );
      expect(p.actions.first.title, 'Keep effort light today');
    });

    test('sleep in the day: bedtime normalised to a clock time', () {
      final p = plan(bundle(recovery: rec(60), bedtime: bed));
      final s = p.actions.single;
      expect(s.kind, PlanActionKind.sleep);
      expect(s.title, 'Aim for bed by 22:40');
      expect(
        s.why,
        "Tonight's sleep target is 8 h 5 m, with 1 h 20 m of sleep debt "
        'carried.',
      );
    });

    test('sleep without a habitual wake time: the target', () {
      final p = plan(
        bundle(
          recovery: rec(60),
          bedtime: const BedtimeRecommendation(
            projectedNeedMinutes: 456,
            debtMinutes: 0,
          ),
        ),
      );
      expect(p.actions.single.title, 'Aim for 7 h 36 m of sleep tonight');
      expect(p.actions.single.why, "That is tonight's sleep target.");
    });

    test('checkIn: fixed non-diagnostic copy', () {
      final p = plan(bundle(recovery: rec(25), vitals: [rhrHigh]));
      final c = p.actions.firstWhere((a) => a.kind == PlanActionKind.checkIn);
      expect(c.title, HealthMonitor.checkInTitle);
      expect(
        c.why,
        'Resting HR higher (61 vs usual 54 bpm): a pattern in your numbers, '
        'not a diagnosis.',
      );
      final v = plan(bundle(recovery: rec(75), vitals: [rhrHigh]));
      expect(
        v.actions.firstWhere((a) => a.kind == PlanActionKind.checkIn).why,
        'Resting HR is outside your usual range: a pattern in your numbers, '
        'not a diagnosis.',
        reason: 'the summary already carries the numbers',
      );
    });

    test('recover: easy or rest days', () {
      final p = plan(bundle(recovery: rec(25)));
      expect(kinds(p), [PlanActionKind.recover]);
      expect(p.actions.single.why, 'Recovery is in the red zone.');
    });

    test('at most 3, in order; housekeeping dropped when others exist', () {
      final p = plan(
        bundle(
          recovery: rec(25),
          noSleep: true,
          strainResult: strain(target: 5),
          bedtime: bed,
          vitals: [rhrHigh],
        ),
      );
      expect(kinds(p), [
        PlanActionKind.effort,
        PlanActionKind.sleep,
        PlanActionKind.checkIn,
      ]);
    });

    test('wear only as the sole action, never for an unshared input', () {
      final missingHrv = plan(bundle(recovery: rec(70, hrv: null)));
      expect(kinds(missingHrv), [PlanActionKind.wear]);
      expect(missingHrv.summary, startsWith('Recovery 70% without HRV'));
      expect(missingHrv.missingInputs, [InputGap.hrv]);
      final whoop = plan(
        bundle(recovery: rec(70, hrv: null), notShared: const {'hrv': 'WHOOP'}),
      );
      expect(whoop.actions, isEmpty);
      expect(whoop.evidence.first.comparison, 'without HRV');
      final withSleepAction = plan(
        bundle(recovery: rec(70, hrv: null), bedtime: bed),
      );
      expect(kinds(withSleepAction), [PlanActionKind.sleep]);
    });

    test('sync names the source app; sources list the apps', () {
      final p = plan(
        bundle(
          recovery: rec(70),
          lastDataAt: DateTime(2026, 9, 27, 21, 5),
          provenance: {
            Metric.restingHr: const Provenance(
              SourceKind.healthConnect,
              'hc_daily_rhr',
              origin: SourceApps.samsungHealth,
            ),
          },
        ),
      );
      expect(p.actions.single.title, 'Open Samsung Health to sync');
      expect(p.actions.single.why, 'The newest data is from Sep 27 21:05.');
      expect(p.sources, ['Samsung Health']);
    });

    test('nothing to change: a fresh, normal day with no advice inputs', () {
      expect(plan(bundle(recovery: rec(55))).actions, isEmpty);
    });
  });

  group('evidence, numbers and tone', () {
    test('1–2 chips, the second the key signal vs usual', () {
      final p = plan(bundle(recovery: rec(72)));
      expect(p.evidence, hasLength(2));
      expect(p.evidence.first.value, '72%');
      expect(p.evidence.last.label, 'HRV');
      expect(p.evidence.last.value, '52 ms');
      expect(p.evidence.last.comparison, '11% above usual');
    });

    test("the contract's own example passes the number check", () {
      final b = bundle(
        recovery: rec(40, hrv: 38.7, hrvUsual: 45),
        sleepResult: sleep(slept: 350),
      );
      const example = PlanAction(
        kind: PlanActionKind.recover,
        title: 'Keep today low-key',
        why: 'Your HRV is 14% below your usual and you slept 5 h 50 m.',
      );
      final p = const TodayPlan(
        date: today,
        state: DayState.easy,
        headline: 'Take it easy',
        summary: '',
        actions: [example],
      );
      expect(unsupportedNumbers(p, allowedNumbers(b, now: morning)), isEmpty);
      final bad = const TodayPlan(
        date: today,
        state: DayState.easy,
        headline: 'Take it easy',
        summary: 'Your HRV is 23% below your usual.',
      );
      expect(
        unsupportedNumbers(bad, allowedNumbers(b, now: morning)),
        isNotEmpty,
      );
    });

    test('calm: no shame, no diagnosis, no streaks', () {
      final bad = RegExp(
        r'infection|illness|sick|overtrain|streak|in a row|fail|should have'
        r'|!',
        caseSensitive: false,
      );
      final plans = [
        plan(bundle(recovery: rec(12), strainResult: strain(target: 3))),
        plan(
          bundle(
            recovery: rec(60),
            vitals: [
              rhrHigh,
              vital(HealthMetricKind.skinTemp, BandState.above, 0.9, 0.1),
            ],
          ),
        ),
        plan(bundle(date: '2026-09-27')),
      ];
      for (final p in plans) {
        for (final t in planTexts(p)) {
          expect(bad.hasMatch(t), isFalse, reason: t);
        }
      }
    });

    test('the Engine facade returns the same plan', () {
      final b = bundle(recovery: rec(72), strainResult: strain(target: 14.4));
      final a = TodayPlanner.plan(today: b, now: morning);
      final e = Engine.planToday(b, now: morning);
      expect(e.summary, a.summary);
      expect(kinds(e), kinds(a));
    });
  });
}
