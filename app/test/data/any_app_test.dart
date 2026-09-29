// Any app via Health Connect (decision 2026-09-29): one origin per metric,
// never summed or averaged; the persisted choice moves only after a
// sustained absence or on a user pin; per-app fixtures (Samsung, WHOOP,
// Oura, Fitbit) through the real mapper, resolver and engine.

import 'dart:convert';

import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/resolver/resolver.dart';
import 'package:airlog/data/resolver/source_choice.dart';
import 'package:airlog/data/services/health_connect/hc_types.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/recovery.dart';
import 'package:airlog/domain/engine/source_apps.dart';
import 'package:airlog/domain/engine/today_planner.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:airlog/domain/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/hc_apps.dart';

final now = DateTime(2026, 9, 28, 21);
const last = '2026-09-28';

List<DayRecord> resolve(RawRows rows, {Map<Metric, OriginPlan>? plans}) =>
    const Resolver().resolve(
      rows,
      DayKey.add(last, -30),
      last,
      ResolverConfig(mode: DataMode.live, now: now, origins: plans ?? const {}),
    );

List<HcRecord> days(AppShape app, int n, {String end = last}) => [
  for (var i = 0; i < n; i++) ...appDay(app, DayKey.add(end, -i), seed: i),
];

void main() {
  group('resolver: one origin per metric', () {
    test('two apps on the same days: never summed or averaged', () {
      final rows = ingest([
        ...days(AppShape.fitbit, 10),
        ...days(AppShape.samsung, 10),
      ], now);
      final recs = resolve(rows);
      final d = recs.last;
      // Steps are ONE app's total, not 8000 + 11000.
      expect(d.steps, anyOf(8000, 11000));
      final stepsApp = d.provenance[Metric.steps]!.origin;
      expect(d.steps, stepsApp == SourceApps.fitbit ? 8000 : 11000);
      // One app's sleep session, not both nights.
      expect(d.sleepSessions, hasLength(1));
      expect(d.totalSleepMinutes, lessThanOrEqualTo(8 * 60));
      // HR minutes from one app: every sample within that app's range.
      final hrApp = d.provenance[Metric.hr]!.origin!;
      final base = hrApp == SourceApps.fitbit ? 70 : 80;
      expect(
        d.hrSamples.every((s) => s.bpm >= base && s.bpm < base + 10),
        isTrue,
      );
      // Samsung writes no HRV/RHR: those come from Fitbit (the only app).
      expect(d.provenance[Metric.hrv]!.origin, SourceApps.fitbit);
      expect(d.provenance[Metric.restingHr]!.origin, SourceApps.fitbit);
      // Every metric is stamped with its origin.
      for (final p in d.provenance.values) {
        expect(p.origin, isNotNull);
      }
    });

    test('the persisted plan is followed day by day (dated segments)', () {
      final rows = ingest([
        ...days(AppShape.fitbit, 10),
        ...days(AppShape.oura, 10),
      ], now);
      final plan = OriginPlan(
        metric: Metric.hrv,
        segments: [
          OriginSegment(SourceApps.fitbit, DayKey.add(last, -9)),
          OriginSegment(SourceApps.oura, DayKey.add(last, -3)),
        ],
      );
      final recs = resolve(rows, plans: {Metric.hrv: plan});
      final byDate = {for (final r in recs) r.date: r};
      expect(
        byDate[DayKey.add(last, -4)]!.provenance[Metric.hrv]!.origin,
        SourceApps.fitbit,
      );
      expect(
        byDate[DayKey.add(last, -3)]!.provenance[Metric.hrv]!.origin,
        SourceApps.oura,
      );
      expect(byDate[last]!.hrvRmssd, greaterThanOrEqualTo(60));
    });
  });

  group('fixtures through the engine and the planner', () {
    test('Samsung Health (continuous HR): Recovery from sleep + sleeping '
        'HR, honest notes, Strain still works', () {
      final recs = resolve(ingest(days(AppShape.samsung, 8), now));
      final r = Engine.computeRange(recs, now: now).last;
      expect(r.recovery, isNotNull);
      expect(r.recovery!.withoutHrv, isTrue);
      expect(r.notShared, {'hrv': 'Samsung Health', 'rhr': 'Samsung Health'});
      expect(
        r.notes.firstWhere((n) => n.metric == 'rhr').title,
        'No resting heart rate from Samsung Health',
      );
      expect(r.strain!.method.name, 'hrZones');
      expect(r.sleep!.hasData, isTrue);
      final plan = TodayPlanner.plan(
        today: DayBundle(recs.last, r),
        now: DateTime(2026, 9, 28, 10),
      );
      expect(plan.state, isNot(DayState.noData));
      expect(
        plan.missingInputs,
        containsAll([InputGap.hrv, InputGap.heartRate]),
      );
      expect(plan.actions.where((a) => a.kind == PlanActionKind.wear), isEmpty);
      expect(plan.sources, ['Samsung Health']);
    });

    test('WHOOP: Recovery without HRV, named, lower confidence', () {
      final recs = resolve(ingest(days(AppShape.whoop, 8), now));
      final r = Engine.computeRange(recs, now: now).last;
      expect(r.recovery, isNotNull);
      expect(r.recovery!.withoutHrv, isTrue);
      expect(r.recovery!.confidence.name, 'reduced');
      expect(r.notShared, {'hrv': 'WHOOP'});
      expect(
        r.notes.firstWhere((n) => n.metric == 'hrv').title,
        'Recovery without HRV',
      );
    });

    test('Oura: full Recovery from its own measurements', () {
      final recs = resolve(ingest(days(AppShape.oura, 8), now));
      final r = Engine.computeRange(recs, now: now).last;
      expect(r.recovery!.withoutHrv, isFalse);
      expect(recs.last.provenance[Metric.hrv]!.origin, SourceApps.oura);
      expect(
        recs.last.provenance[Metric.hrv]!.baselineKey,
        'hc_sleep_mean_rmssd@com.ouraring.oura',
      );
      expect(r.notShared, isEmpty);
    });
  });

  group('switch: Fitbit → Samsung Health (shares neither HRV nor resting '
      'HR)', () {
    // 24 nights on a Fitbit, then Samsung Health for the last 6. The plans
    // move after 4 silent Fitbit days, backdated to the first one. The
    // Fitbit's resting HR from a few days ago must not hold back the
    // sleeping-HR stand-in for 14 days.
    final switchDay = DayKey.add(last, -5);
    const samsung = SourceApps.samsungHealth;
    RawRows rows() => ingest([
      for (var i = 6; i < 30; i++)
        ...appDay(AppShape.fitbit, DayKey.add(last, -i), seed: i),
      for (var i = 0; i < 6; i++)
        ...appDay(AppShape.samsung, DayKey.add(last, -i), seed: i),
    ], now);
    bool standIn(DayResult r) =>
        r.recovery?.components.any(
          (c) => c.key == RecoveryEngine.sleepingHrKey,
        ) ??
        false;

    test('the source choice persists that Samsung Health shares neither', () {
      final r = rows();
      final plans = plansFor(r, today: last);
      expect(plans[Metric.sleep]!.current, samsung);
      expect(plans[Metric.sleep]!.since, switchDay);
      expect(plans[Metric.restingHr]!.current, SourceApps.fitbit);
      final days = originDaysOf(r);
      expect(SourceChooser.notSharedBy(Metric.restingHr, days), [samsung]);
      expect(SourceChooser.notSharedBy(Metric.hrv, days), [samsung]);
      final p = plans[Metric.restingHr]!.copyWith(
        notShared: SourceChooser.notSharedBy(Metric.restingHr, days),
      );
      final back = OriginPlan.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      );
      expect(back.notShared, [samsung]);
      // A plan saved before the field existed reads as "none known".
      final legacy = p.toJson()..remove('notShared');
      expect(OriginPlan.fromJson(legacy).notShared, isEmpty);
    });

    test('persisted: sleeping HR stands in from the first night after the '
        'switch; the plan says re-learning, never "wear"', () {
      final recs = resolve(rows());
      final results = Engine.computeRange(
        recs,
        now: now,
        config: const EngineConfig(
          notShared: {
            'hrv': {samsung},
            'rhr': {samsung},
          },
        ),
      );
      final byDate = {for (final x in results) x.date: x};
      expect(standIn(byDate[DayKey.add(last, -6)]!), isFalse, reason: 'Fitbit');
      for (var i = 5; i >= 0; i--) {
        final d = DayKey.add(last, -i);
        final x = byDate[d]!;
        expect(x.recovery, isNotNull, reason: d);
        expect(standIn(x), isTrue, reason: d);
        expect(x.notShared, {
          'hrv': 'Samsung Health',
          'rhr': 'Samsung Health',
        }, reason: d);
        expect(x.sourceChange?.metric, 'rhr', reason: d);
        expect(x.sourceChange!.from!.origin, SourceApps.fitbit, reason: d);
        expect(x.sourceChange!.to!.origin, samsung, reason: d);
        expect(x.sourceChange!.nights, 5 - i, reason: d);
      }
      final plan = TodayPlanner.plan(
        today: DayBundle(recs.last, results.last),
        now: DateTime(2026, 9, 28, 10),
      );
      expect(plan.relearningSource, 'Samsung Health');
      expect(plan.state, isNot(DayState.noData));
      expect(plan.actions.where((a) => a.kind == PlanActionKind.wear), isEmpty);
    });

    test('observed only (nothing persisted): the stand-in starts on the '
        'third night, not after 14 days', () {
      final byDate = {
        for (final x in Engine.computeRange(resolve(rows()), now: now))
          x.date: x,
      };
      expect(standIn(byDate[switchDay]!), isFalse, reason: 'night 1');
      expect(
        standIn(byDate[DayKey.add(last, -4)]!),
        isFalse,
        reason: 'night 2',
      );
      for (var i = 3; i >= 0; i--) {
        final d = DayKey.add(last, -i);
        expect(standIn(byDate[d]!), isTrue, reason: d);
        expect(byDate[d]!.notShared['rhr'], 'Samsung Health', reason: d);
      }
    });

    test('an app that still writes resting HR keeps blocking: a missed '
        'Fitbit night beside Samsung sleep is a wear gap', () {
      // Samsung Health tracks sleep all along; the Fitbit writes resting HR
      // every day but the last. The Fitbit is still active, so its recent
      // resting HR means "missing tonight", not "not shared".
      final records = [
        for (var i = 1; i < 20; i++) ...[
          ...appDay(AppShape.samsung, DayKey.add(last, -i), seed: i),
          ...appDay(
            AppShape.fitbit,
            DayKey.add(last, -i),
            seed: i,
          ).where((r) => r.type == HcType.restingHr),
        ],
        ...appDay(AppShape.samsung, last),
      ];
      final plans = {
        Metric.sleep: OriginPlan(
          metric: Metric.sleep,
          segments: [OriginSegment(samsung, DayKey.add(last, -19))],
        ),
      };
      final recs = resolve(ingest(records, now), plans: plans);
      expect(
        recs[recs.length - 2].provenance[Metric.restingHr]!.origin,
        SourceApps.fitbit,
      );
      final r = Engine.computeRange(
        recs,
        now: now,
        config: const EngineConfig(
          notShared: {
            'rhr': {samsung},
          },
        ),
      ).last;
      expect(r.notShared.containsKey('rhr'), isFalse);
      expect(standIn(r), isFalse);
    });
  });

  group('SourceChooser', () {
    OriginDays od(Map<String, Iterable<int>> offsets) => {
      for (final e in offsets.entries)
        e.key: {for (final i in e.value) DayKey.add(last, -i)},
    };
    const today = '2026-09-29';

    test('automatic: best 14-day coverage', () {
      final p = SourceChooser.update(
        Metric.steps,
        od({
          'a': [for (var i = 0; i < 20; i += 2) i],
          'b': [for (var i = 0; i < 20; i++) i],
        }),
        null,
        today: today,
      )!;
      expect(p.current, 'b');
      expect(p.automatic, isTrue);
    });

    test('alternating daily gaps never change the choice', () {
      var p = SourceChooser.update(
        Metric.hr,
        od({
          'fitbit': [for (var i = 20; i < 40; i++) i],
          'phone': [for (var i = 0; i < 40; i++) i],
        }),
        null,
        today: DayKey.add(last, -19),
      )!;
      expect(p.current, 'fitbit');
      // Then 20 days where the Fitbit misses every other day.
      final d = od({
        'fitbit': [
          for (var i = 20; i < 40; i++) i,
          for (var i = 0; i < 20; i += 2) i,
        ],
        'phone': [for (var i = 0; i < 40; i++) i],
      });
      for (var k = 18; k >= -1; k--) {
        p = SourceChooser.update(Metric.hr, d, p, today: DayKey.add(last, -k))!;
        expect(p.current, 'fitbit', reason: 'day $k');
        expect(p.segments, hasLength(1));
      }
    });

    test('a sustained absence (4 days) switches, backdated to the first '
        'silent day; shorter gaps do not', () {
      expect(kSustainedAbsenceDays, 4);
      final d = od({
        'fitbit': [for (var i = 6; i < 30; i++) i], // silent for 6 days
        'oura': [for (var i = 0; i < 10; i++) i],
      });
      final p0 = SourceChooser.update(
        Metric.hrv,
        d,
        null,
        today: DayKey.add(last, -6),
      )!;
      expect(p0.current, 'fitbit');
      // 3 complete silent days: not yet, but a suggestion.
      final p3 = SourceChooser.update(
        Metric.hrv,
        d,
        p0,
        today: DayKey.add(last, -2),
      )!;
      expect(p3.current, 'fitbit');
      expect(p3.suggested, 'oura');
      final p4 = SourceChooser.update(
        Metric.hrv,
        d,
        p3,
        today: DayKey.add(last, -1),
      )!;
      expect(p4.current, 'oura');
      expect(p4.since, DayKey.add(last, -5), reason: 'first silent day');
      expect(p4.originOn(DayKey.add(last, -6)), 'fitbit');
      expect(
        p4.firstDifference(p3, {DayKey.add(last, -5), last}),
        DayKey.add(last, -5),
      );
    });

    test("a pin starts at the app's first day, keeps earlier days, never "
        'moves', () {
      final d = od({
        'fitbit': [for (var i = 0; i < 30; i++) i],
        'oura': [for (var i = 0; i < 12; i++) i],
      });
      final auto = SourceChooser.update(Metric.hrv, d, null, today: today)!;
      expect(auto.current, 'fitbit');
      var p = SourceChooser.pin(
        Metric.hrv,
        'oura',
        d,
        prev: auto,
        today: today,
      );
      p = SourceChooser.update(Metric.hrv, d, p, today: today)!;
      expect(p.automatic, isFalse);
      expect(p.current, 'oura');
      expect(p.since, DayKey.add(last, -11));
      expect(p.originOn(DayKey.add(last, -29)), 'fitbit');
      // Pinned to an app that then goes silent: it still never moves.
      final silent = od({
        'fitbit': [for (var i = 0; i < 30; i++) i],
        'oura': [for (var i = 20; i < 30; i++) i],
      });
      var q = SourceChooser.pin(Metric.hrv, 'oura', silent, today: today);
      q = SourceChooser.update(Metric.hrv, silent, q, today: today)!;
      expect(q.current, 'oura');
      expect(q.suggested, 'fitbit');
    });

    test('plans round-trip through JSON', () {
      final p = SourceChooser.update(
        Metric.sleep,
        od({
          'a': [1, 2, 3],
        }),
        null,
        today: today,
      )!;
      final back = OriginPlan.fromJson(p.toJson());
      expect(back.toJson(), p.toJson());
    });
  });
}
