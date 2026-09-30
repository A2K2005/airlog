// TodayPlanner: one test per rule (state, freshness, phase, each action,
// housekeeping, caps, basis, re-learning, tone, numbers). See
// lib/domain/engine/today_planner.dart for the rules table and
// docs/COPY_REVIEW.md §4.1 for the wording.

import 'package:airlog/domain/coach/verifier.dart';
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
  List<Workout>? workouts,
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
    workouts: workouts,
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

/// The plan for [b]. Every plan in this file also passes the number check,
/// in both clock settings (12-hour times print "12" for noon and midnight).
TodayPlan plan(
  DayBundle b, {
  SyncStatus? sync,
  DateTime? now,
  bool use24h = true,
}) {
  final at = now ?? morning;
  for (final h24 in [true, false]) {
    final q = TodayPlanner.plan(today: b, sync: sync, now: at, use24h: h24);
    expect(
      unsupportedNumbers(
        q,
        allowedNumbers(b, sync: sync, now: at, use24h: h24),
      ),
      isEmpty,
    );
    expect(q.actions.length, lessThanOrEqualTo(3));
    expect(q.evidence.length, lessThanOrEqualTo(2));
  }
  return TodayPlanner.plan(today: b, sync: sync, now: at, use24h: use24h);
}

List<PlanActionKind> kinds(TodayPlan p) => [for (final a in p.actions) a.kind];

void main() {
  group('state', () {
    test('ready: green and fresh; words first, numbers on the chips', () {
      final p = plan(
        bundle(recovery: rec(72), strainResult: strain(target: 14.4)),
      );
      expect(p.state, DayState.ready);
      expect(p.headline, 'Your body is ready');
      expect(p.summary, 'Your heart is well rested today.');
      expect(p.phase, PlanPhase.today);
      expect(p.stale, isFalse);
      expect(p.provisional, isFalse);
      expect(p.missingInputs, isEmpty);
    });

    test('"about the same as usual" inside ±5 % HRV and ±1.5 bpm', () {
      final p = plan(bundle(recovery: rec(60, hrv: 48, rhr: 56.5)));
      expect(p.summary, 'Your heart looks about the same as usual.');
      expect(p.evidence.last.comparison, 'about usual');
    });

    test('mixed and worse signals', () {
      expect(
        plan(bundle(recovery: rec(60, hrv: 52, rhr: 58))).summary,
        'Your heart shows mixed signs today.',
      );
      expect(
        plan(bundle(recovery: rec(45, hrv: 40, rhr: 56))).summary,
        'Your heart is less rested than usual.',
      );
    });

    test('short sleep is named in words', () {
      final p = plan(bundle(recovery: rec(50), sleepResult: sleep(slept: 300)));
      expect(
        p.summary,
        'Your heart is well rested today, but you slept well under your '
        'sleep goal.',
      );
      final worse = plan(
        bundle(
          recovery: rec(45, hrv: 40, rhr: 56),
          sleepResult: sleep(slept: 300),
        ),
      );
      expect(
        worse.summary,
        'Your heart is less rested than usual, and you slept well under '
        'your sleep goal.',
      );
    });

    test('steady: yellow', () {
      final p = plan(bundle(recovery: rec(50)));
      expect(p.state, DayState.steady);
      expect(p.headline, 'Good for a normal day');
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
      expect(p.headline, 'Take it easy today');
    });

    test('rest: recovery in the lower half of red', () {
      expect(TodayPlanner.restBelow, 17);
      final p = plan(bundle(recovery: rec(12)));
      expect(p.state, DayState.rest);
      expect(p.headline, 'Make today a rest day');
      expect(p.summary, startsWith("Your body hasn't recovered yet. "));
    });

    test('easy: one concerning vital even with green recovery (the old '
        'alert card, ported)', () {
      final p = plan(bundle(recovery: rec(75), vitals: [rhrHigh]));
      expect(p.state, DayState.easy);
      expect(p.summary, 'Your resting heart rate is higher than usual.');
      expect(p.evidence.map((e) => e.label), ['Recovery', 'Resting HR']);
      expect(p.evidence.last.value, '61 bpm');
      expect(p.evidence.last.comparison, 'usual 54 bpm');
    });

    test('rest: two concerning vitals, lower and higher', () {
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
        'Your HRV is lower than usual, and your resting heart rate is '
        'higher.',
      );
    });

    test('breathing rate: plain name, breaths/min on the chip', () {
      final p = plan(
        bundle(
          recovery: rec(75),
          vitals: [
            vital(HealthMetricKind.respiratoryRate, BandState.above, 17.9, 15.3),
          ],
        ),
      );
      expect(p.summary, 'Your breathing rate is higher than usual.');
      expect(p.evidence.last.label, 'Breathing rate');
      expect(p.evidence.last.value, '17.9 breaths/min');
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

    test('calibrating: early estimate; red does not mean easy', () {
      final p = plan(
        bundle(
          recovery: rec(20, calibrating: true),
          strainResult: strain(target: 4),
          calibration: const Calibration(haveNights: 3),
        ),
      );
      expect(p.state, DayState.calibrating);
      expect(p.headline, 'Still getting to know you');
      expect(p.provisional, isTrue);
      expect(
        p.summary,
        "Airlog is still learning what's normal for you, so today's score "
        'may change.',
      );
      expect(p.evidence.first.comparison, 'early estimate');
      expect(p.evidence.last.label, 'Learning');
      expect(p.evidence.last.value, '3 of 14 nights');
      expect(kinds(p), [PlanActionKind.wear], reason: 'no effort advice');
      expect(p.actions.single.title, 'Keep wearing your tracker to bed');
      expect(
        p.actions.single.why,
        "Airlog learns what's normal for you from each night you wear it.",
      );
    });

    test('calibrating, the first morning: no "0 of 14 nights" chip', () {
      final p = plan(
        bundle(
          recovery: rec(20, calibrating: true),
          calibration: const Calibration(haveNights: 0),
        ),
      );
      expect(
        p.summary,
        "Airlog is just getting to know you, so today's score may change.",
      );
      expect(p.evidence.map((e) => e.label), ['Recovery']);
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
      expect(p.summaryNamesRelearning, isTrue);
      expect(p.state, DayState.calibrating);
      expect(
        p.summary,
        'You switched to Oura, so Airlog is learning your usual again. '
        "Today's score may change.",
      );
      expect(p.evidence.last.value, '2 of 14 nights');
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
        'so instead', () {
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
        expect(p.summaryNamesRelearning, isTrue, reason: e.key);
        expect(kinds(p), isNot(contains(PlanActionKind.wear)), reason: e.key);
        expect(p.actions, isEmpty, reason: e.key);
        expect(
          p.summary,
          '${before.summary} Airlog is learning your Oura data: 2 of 14 '
          'nights so far.',
          reason: e.key,
        );
      }
    });

    test('re-learning: other actions are unchanged; the basis tags it', () {
      final p = plan(
        bundle(
          recovery: rec(70),
          strainResult: strain(target: 12),
          bedtime: bed,
          sourceChange: ouraSwitch,
        ),
      );
      expect(kinds(p), [PlanActionKind.effort, PlanActionKind.sleep]);
      expect(p.summary, isNot(contains('Oura')));
      expect(p.relearningSource, 'Oura');
      expect(p.summaryNamesRelearning, isFalse);
    });

    test('noData: no recovery today', () {
      final p = plan(bundle(noSleep: true));
      expect(p.state, DayState.noData);
      expect(p.headline, 'No Recovery score today');
      expect(
        p.summary,
        "Last night's heart data didn't come in, so there's no Recovery "
        'score today.',
      );
      expect(kinds(p), [PlanActionKind.wear]);
      expect(p.actions.single.why, "Last night's heart data didn't come in.");
    });

    test('noData: the app shares neither HRV nor resting HR (Samsung)', () {
      final p = plan(
        bundle(
          notShared: const {'hrv': 'Samsung Health', 'rhr': 'Samsung Health'},
        ),
      );
      expect(p.state, DayState.noData);
      expect(p.headline, 'No Recovery score today');
      expect(
        p.summary,
        "Samsung Health doesn't share the heart data Recovery needs, so "
        "there's no Recovery score. Sleep and Strain still work.",
      );
      expect(p.evidence.single.label, 'Sleep');
      expect(p.evidence.single.comparison, 'goal 7h 36m');
      expect(p.actions, isEmpty, reason: 'wearing the tracker will not help');
      expect(p.missingInputs, containsAll([InputGap.hrv, InputGap.heartRate]));
    });

    test('noData: the newest bundle is from yesterday → sync, sole action', () {
      final b = bundle(
        date: '2026-09-28',
        recovery: rec(70),
        bedtime: bed,
        lastDataAt: DateTime(2026, 9, 28, 23, 10),
      );
      final p = plan(b);
      expect(p.state, DayState.noData);
      expect(p.headline, 'Waiting for your data');
      expect(p.summary, 'Nothing has come in for today yet.');
      expect(p.evidence.single.label, 'Last update');
      expect(p.evidence.single.value, 'yesterday 23:10');
      expect(plan(b, use24h: false).evidence.single.value, 'yesterday, 11:10 pm');
      expect(kinds(p), [PlanActionKind.sync]);
      expect(p.actions.single.why, "Last night's data comes in when it syncs.");
      expect(p.missingInputs, isEmpty);
      expect(p.stale, isFalse, reason: '10 h 20 m is inside 12 h');
    });
  });

  group('time of day', () {
    final evening = DateTime(2026, 9, 29, 21);

    test('tonight: sleep goal and missed sleep; no effort', () {
      final b = bundle(
        recovery: rec(60),
        strainResult: strain(target: 12, so: 8),
        bedtime: bed,
        now: evening,
      );
      final p = plan(b, now: evening);
      expect(p.phase, PlanPhase.tonight);
      expect(p.headline, 'Time to wind down');
      expect(p.summary, "You're short on sleep from recent nights.");
      expect(kinds(p), [PlanActionKind.sleep]);
      expect(p.actions.single.title, 'Try to be asleep by 22:40');
      expect(
        p.actions.single.why,
        'You usually wake up at 06:45, so that gives you enough sleep.',
      );
      expect(p.evidence.first.label, 'Sleep goal');
      expect(p.evidence.first.value, '8h 5m');
      expect(p.evidence.last.label, 'Missed sleep');
      expect(p.evidence.last.value, '1h 20m');
      final h12 = plan(b, now: evening, use24h: false);
      expect(h12.actions.single.title, 'Try to be asleep by 10:40 pm');
      expect(
        h12.actions.single.why,
        'You usually wake up at 6:45 am, so that gives you enough sleep.',
      );
    });

    test('tonight, no missed sleep: the Recovery chip, a normal night', () {
      const rested = BedtimeRecommendation(
        projectedNeedMinutes: 456,
        debtMinutes: 0,
        habitualWakeMinutes: 405,
        recommendedBedtimeMinutes: -51,
      );
      final p = plan(
        bundle(recovery: rec(60), bedtime: rested, now: evening),
        now: evening,
      );
      expect(p.summary, "You're not short on sleep, so a normal night will do.");
      expect(p.evidence.last.label, 'Recovery');
    });

    test('tonight on an easy day: "Rest up tonight"', () {
      final p = plan(
        bundle(recovery: rec(25), bedtime: bed, now: evening),
        now: evening,
      );
      expect(p.headline, 'Rest up tonight');
      expect(p.actions.last.title, 'Have a calm evening');
    });

    test('tonight, past the bedtime', () {
      final late = DateTime(2026, 9, 29, 23, 30);
      final p = plan(
        bundle(recovery: rec(60), bedtime: bed, now: late),
        now: late,
      );
      expect(p.actions.single.title, 'Head to bed when you can');
      expect(p.actions.single.why, 'The best time to be asleep was 22:40.');
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
      expect(p.headline, 'Waiting for your data');
      expect(
        p.summary,
        'Your scores show up after you wake up and your tracker syncs.',
      );
      expect(p.actions, isEmpty);
    });
  });

  group('actions', () {
    test('effort: the level is keyed on the state; the range is a chip', () {
      expect(StrainEngine.targetRange(7.4), (6, 9));
      expect(StrainEngine.targetRange(3), (2, 5));
      expect(StrainEngine.targetRange(18.5), (17, 20));
      final p = plan(
        bundle(recovery: rec(72), strainResult: strain(target: 14.4)),
      );
      final e = p.actions.first;
      expect(e.kind, PlanActionKind.effort);
      expect(e.title, 'A hard workout would be fine today');
      expect(e.why, 'Try a long run, intervals or a tough gym session.');
      expect(e.evidence.single.label, 'Effort goal');
      expect(e.evidence.single.value, '13–16');
      expect(e.evidence.single.comparison, isNull);
      final easy = plan(
        bundle(recovery: rec(25), strainResult: strain(target: 5)),
      );
      expect(easy.actions.first.title, 'Keep any workout easy today');
      expect(easy.actions.first.why, 'Try a walk, an easy bike ride or yoga.');
      expect(easy.actions.first.evidence.single.value, '4–7');
      final rest = plan(
        bundle(recovery: rec(12), strainResult: strain(target: 3)),
      );
      expect(rest.actions.first.title, 'Rest or move gently today');
      expect(rest.actions.first.evidence.single.value, '2–5');
      final steady = plan(
        bundle(recovery: rec(52), strainResult: strain(target: 10.4)),
      );
      expect(
        steady.actions.first.title,
        'A normal workout would be fine today',
      );
      final top = plan(
        bundle(recovery: rec(90), strainResult: strain(target: 18)),
      );
      expect(
        top.actions.first.title,
        'A very hard workout would be fine today',
      );
    });

    test('effort: progress words, the strain so far on the chip', () {
      String why(double so) => plan(
        bundle(recovery: rec(58), strainResult: strain(target: 11.6, so: so)),
      ).actions.first.why;
      // Range 10–13.
      expect(why(3.0), "You've made a start.");
      expect(why(5.0), "You're about halfway there.");
      expect(why(7.2), "You're nearly there.");
      final p = plan(
        bundle(recovery: rec(58), strainResult: strain(target: 11.6, so: 7.2)),
      );
      expect(p.actions.first.title, 'A normal workout would be fine today');
      expect(p.actions.first.evidence.single.comparison, '7.2 so far');
      // A tiny start in the morning isn't mentioned.
      final early = plan(
        bundle(recovery: rec(58), strainResult: strain(target: 11.6, so: 0.6)),
      );
      expect(
        early.actions.first.why,
        'Try a steady run, a bike ride or a normal gym session.',
      );
      expect(early.actions.first.evidence.single.comparison, isNull);
    });

    test('effort: the afternoon without a start says so', () {
      final noon = DateTime(2026, 9, 29, 13);
      final none = plan(
        bundle(
          recovery: rec(58),
          strainResult: strain(target: 11.6),
          now: noon,
        ),
        now: noon,
      );
      expect(
        none.actions.first.why,
        'No workout recorded yet today. Try a steady run, a bike ride or a '
        'normal gym session.',
      );
      final walked = plan(
        bundle(
          recovery: rec(58),
          strainResult: strain(target: 11.6, so: 1),
          now: noon,
          workouts: [
            Workout(
              id: 'w1',
              name: 'Walk',
              start: DateTime(2026, 9, 29, 7),
              end: DateTime(2026, 9, 29, 7, 20),
            ),
          ],
        ),
        now: noon,
      );
      expect(walked.actions.first.why, startsWith('Not much effort so far '));
    });

    test('effort: the goal hit, then passed', () {
      final hit = plan(
        bundle(recovery: rec(72), strainResult: strain(target: 14.4, so: 14)),
      );
      expect(hit.actions.first.title, "You've hit today's goal");
      expect(hit.actions.first.why, 'Anything more is extra.');
      final past = plan(
        bundle(recovery: rec(72), strainResult: strain(target: 14.4, so: 17)),
      );
      expect(past.actions.first.title, "You've done enough for today");
      expect(
        past.actions.first.why,
        "You're past today's goal. Take it easy from here.",
      );
      expect(past.actions.first.evidence.single.comparison, '17.0 so far');
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

    test('effort: a concerning vital keeps it easy, without a goal chip', () {
      final p = plan(
        bundle(
          recovery: rec(75),
          strainResult: strain(target: 15),
          vitals: [rhrHigh],
        ),
      );
      expect(p.actions.first.title, 'Keep any workout easy today');
      expect(p.actions.first.why, 'Try a walk, an easy bike ride or yoga.');
      expect(p.actions.first.evidence, isEmpty);
    });

    test('sleep in the day: bedtime as a clock time, the goal as a chip', () {
      final b = bundle(recovery: rec(60), bedtime: bed);
      final p = plan(b);
      final s = p.actions.single;
      expect(s.kind, PlanActionKind.sleep);
      expect(s.title, 'Try to be asleep by 22:40');
      expect(s.why, "You're short on sleep from recent nights.");
      expect(s.evidence.single.label, 'Sleep goal');
      expect(s.evidence.single.value, '8h 5m');
      expect(s.evidence.single.comparison, '1h 20m missed');
      expect(
        plan(b, use24h: false).actions.single.title,
        'Try to be asleep by 10:40 pm',
      );
    });

    test('sleep: the missed-sleep words by amount', () {
      String why(double debt) => plan(
        bundle(
          recovery: rec(60),
          bedtime: BedtimeRecommendation(
            projectedNeedMinutes: 470,
            debtMinutes: debt,
            habitualWakeMinutes: 405,
            recommendedBedtimeMinutes: -65,
          ),
        ),
      ).actions.single.why;
      expect(why(14), 'That gives you enough sleep before your usual wake-up time.');
      expect(why(15), "You're a bit short on sleep from recent nights.");
      expect(why(60), "You're short on sleep from recent nights.");
      expect(why(300), "You're well short on sleep from recent nights.");
    });

    test('sleep without a habitual wake time: the goal', () {
      final p = plan(
        bundle(
          recovery: rec(60),
          bedtime: const BedtimeRecommendation(
            projectedNeedMinutes: 456,
            debtMinutes: 0,
          ),
        ),
      );
      expect(p.actions.single.title, "Get a full night's sleep tonight");
      expect(p.actions.single.why, 'Your sleep goal tonight is 7h 36m.');
      expect(p.actions.single.evidence, isEmpty);
    });

    test('checkIn: fixed non-diagnostic copy', () {
      final p = plan(bundle(recovery: rec(25), vitals: [rhrHigh]));
      final c = p.actions.firstWhere((a) => a.kind == PlanActionKind.checkIn);
      expect(c.title, HealthMonitor.checkInTitle);
      expect(
        c.why,
        'Your resting heart rate is higher than usual. This is a pattern in '
        'your numbers, not a diagnosis.',
      );
      expect(c.evidence.single.label, 'Resting HR');
      final v = plan(bundle(recovery: rec(75), vitals: [rhrHigh]));
      final vc = v.actions.firstWhere((a) => a.kind == PlanActionKind.checkIn);
      expect(
        vc.why,
        'This is a pattern in your numbers, not a diagnosis.',
        reason: 'the summary already names it',
      );
      expect(vc.evidence, isEmpty, reason: 'its chip is already on the card');
    });

    test('recover: easy or rest days', () {
      final p = plan(bundle(recovery: rec(25)));
      expect(kinds(p), [PlanActionKind.recover]);
      expect(p.actions.single.title, 'Take it slow today');
      expect(p.actions.single.why, 'Your Recovery is Low today.');
      final v = plan(bundle(recovery: rec(75), vitals: [rhrHigh]));
      expect(
        v.actions.last.why,
        'An easier day gives your body a break.',
      );
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
      expect(
        missingHrv.actions.single.why,
        "Last night's HRV didn't come in, so today's score leaves it out.",
      );
      expect(missingHrv.evidence.first.comparison, 'without HRV');
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
      final b = bundle(
        recovery: rec(70),
        lastDataAt: DateTime(2026, 9, 27, 21, 5),
        provenance: {
          Metric.restingHr: const Provenance(
            SourceKind.healthConnect,
            'hc_daily_rhr',
            origin: SourceApps.samsungHealth,
          ),
        },
      );
      final p = plan(b);
      expect(p.actions.single.title, 'Open Samsung Health to sync');
      expect(p.actions.single.why, 'Your latest data is from Sep 27 21:05.');
      expect(
        plan(b, use24h: false).actions.single.why,
        'Your latest data is from Sep 27, 9:05 pm.',
      );
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

    test('formats: durations and 12/24-hour clocks', () {
      expect(PlanFormat.hm(456), '7h 36m');
      expect(PlanFormat.hm(480), '8h');
      expect(PlanFormat.hm(45), '45 min');
      expect(PlanFormat.hm(0), '0 min');
      expect(PlanFormat.clock(1415), '23:35');
      expect(PlanFormat.clock(1415, use24h: false), '11:35 pm');
      expect(PlanFormat.clock(0, use24h: false), '12:00 am');
      expect(PlanFormat.clock(720, use24h: false), '12:00 pm');
      expect(PlanFormat.clock(1460, use24h: false), '12:20 am');
    });

    test("the contract's own example passes the number check", () {
      final b = bundle(
        recovery: rec(40, hrv: 38.7, hrvUsual: 45),
        sleepResult: sleep(slept: 350),
      );
      const example = PlanAction(
        kind: PlanActionKind.recover,
        title: 'Take it slow today',
        why: 'Your HRV is 14% below your usual and you slept 5h 50m.',
      );
      final p = const TodayPlan(
        date: today,
        state: DayState.easy,
        headline: 'Take it easy today',
        summary: '',
        actions: [example],
      );
      expect(unsupportedNumbers(p, allowedNumbers(b, now: morning)), isEmpty);
      final bad = const TodayPlan(
        date: today,
        state: DayState.easy,
        headline: 'Take it easy today',
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
      final evening = DateTime(2026, 9, 29, 21);
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
        plan(
          bundle(recovery: rec(25), bedtime: bed, now: evening),
          now: evening,
        ),
      ];
      for (final p in plans) {
        for (final t in planTexts(p)) {
          expect(bad.hasMatch(t), isFalse, reason: t);
        }
      }
    });

    test('effort advice never reads as a workout that happened', () {
      // The coach's verifier checks plan text (test/evals/cards_eval_test):
      // with no workout recorded, advice must not count as a claim.
      for (final l in EffortLevel.values) {
        final text =
            '${TodayPlanner.effortTitle(l)}\n${TodayPlanner.effortExample(l)}';
        final rep = Verifier.verify(
          answer: text,
          question: '',
          today: today,
          calls: const [],
          results: const [],
        );
        expect(rep.verified, isTrue, reason: '$text: ${rep.unsupported}');
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
