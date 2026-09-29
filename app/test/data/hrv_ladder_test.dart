// HRV ladder (research/09b §3, §9): recordingMethod carried through ingest,
// N3 single-record nightly HRV with a persisted shape, and Sleeping HR
// (4 h mean) standing in for resting HR — never leaking into it.

import 'dart:convert';

import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/resolver/definitions.dart';
import 'package:airlog/data/resolver/resolver.dart';
import 'package:airlog/data/resolver/source_choice.dart';
import 'package:airlog/data/services/health_connect/hc_types.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/recovery.dart';
import 'package:airlog/domain/engine/source_apps.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
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

/// A Samsung-shaped day with HR every [hrEveryMin] minutes.
List<HcRecord> samsungDay(
  String wakeDay, {
  int hrEveryMin = 1,
  int sleepH = 8,
}) {
  final o = SourceApps.samsungHealth;
  final wake = DayKey.start(wakeDay).add(const Duration(hours: 7));
  final bed = wake.subtract(Duration(hours: sleepH));
  return [
    ...night('s-$wakeDay', bed, wake, origin: o),
    for (var m = 0; m < 20 * 60; m += hrEveryMin)
      hr(
        's-$wakeDay-hr${m ~/ 60}',
        bed.add(Duration(minutes: m)),
        (bed.add(Duration(minutes: m)).isBefore(wake) ? 52.0 : 78.0) + m % 3,
        origin: o,
      ),
    scalar(
      HcType.steps,
      's-$wakeDay-st',
      wake.add(const Duration(hours: 2)),
      9000,
      origin: o,
      end: wake.add(const Duration(hours: 3)),
    ),
  ];
}

List<HcRecord> samsung(int n, {int hrEveryMin = 1, int sleepH = 8}) => [
  for (var i = 0; i < n; i++)
    ...samsungDay(DayKey.add(last, -i), hrEveryMin: hrEveryMin, sleepH: sleepH),
];

HcRecord hrvRec(
  String id,
  DateTime t,
  double v,
  HcRecordingMethod m, {
  String origin = SourceApps.oura,
}) => HcRecord(
  type: HcType.hrv,
  id: id,
  origin: origin,
  start: t,
  end: t,
  value: v,
  recordingMethod: m,
);

void main() {
  group('Sleeping HR (4 h mean)', () {
    test('Samsung, continuous HR: Recovery from sleep + sleeping HR, 50/50, '
        'confidence pinned at reduced', () {
      final recs = resolve(ingest(samsung(8), now));
      final d = recs.last;
      expect(d.sleepingHr4h, isNotNull);
      expect(d.sleepingHr4h, inInclusiveRange(52, 55));
      expect(
        d.provenance[Metric.sleepingHr]!.baselineKey,
        '${Definitions.sleepingHr4h}@${SourceApps.samsungHealth}',
      );
      final r = Engine.computeRange(recs, now: now).last;
      final rec = r.recovery!;
      expect(rec.components.map((c) => c.key).toSet(), {
        'sleep',
        RecoveryEngine.sleepingHrKey,
      });
      final shr = rec.components.firstWhere(
        (c) => c.key == RecoveryEngine.sleepingHrKey,
      );
      expect(shr.label, 'Sleeping HR (4 h mean)');
      expect(shr.weight, closeTo(0.5, 1e-9));
      expect(rec.coverage, closeTo(0.5, 1e-9));
      expect(rec.confidence, RecoveryConfidence.reduced);
      expect(rec.withoutHrv, isTrue);
      expect(r.notShared, {'hrv': 'Samsung Health', 'rhr': 'Samsung Health'});
      final n = r.notes.firstWhere((n) => n.metric == 'rhr');
      expect(n.body, contains('sleeping heart rate instead'));
      expect(r.calibration.haveNights, 7);
    });

    test('never leaks into resting HR, Strain, Health Monitor or the export '
        'resting column', () {
      final recs = resolve(ingest(samsung(8), now));
      final d = recs.last;
      expect(d.restingHr, isNull);
      expect(d.provenance[Metric.restingHr], isNull);
      final j = d.toJson();
      expect(j.containsKey('restingHr'), isFalse);
      expect(j['sleepingHr4h'], isNotNull);
      final r = Engine.computeRange(recs, now: now).last;
      expect(r.strain!.restingHrUsed, isNull);
      expect(r.strain!.zonesFromMaxHr, isTrue, reason: 'no RHR → %HRmax zones');
      final rhrBand = r.health.metrics.firstWhere(
        (m) => m.kind == HealthMetricKind.restingHr,
      );
      expect(rhrBand.state, BandState.noData);
      expect(rhrBand.value, isNull);
      expect(r.recovery!.rhrValue, isNull);
      expect(jsonEncode(r.toJson()).contains('"rhrValue"'), isFalse);
    });

    test('Samsung with 10-min HR: the gate fails → no Recovery, and the '
        'note says how to fix it', () {
      final recs = resolve(ingest(samsung(8, hrEveryMin: 10), now));
      expect(recs.last.sleepingHr4h, isNull);
      final r = Engine.computeRange(recs, now: now).last;
      expect(r.recovery, isNull);
      final n = r.notes.firstWhere((n) => n.metric == 'recovery');
      expect(
        n.fix,
        startsWith(
          'Turn on continuous heart-rate measurement in '
          'Samsung Health',
        ),
      );
    });

    test('a sleep under 4 h 30 min: no sleeping HR', () {
      final recs = resolve(ingest(samsung(3, sleepH: 4), now));
      expect(recs.last.sleepingHr4h, isNull);
    });

    test('an app that DOES write resting HR never uses sleeping HR, even on '
        'a night its RHR is missing', () {
      final records = [
        for (var i = 1; i < 10; i++)
          ...appDay(AppShape.fitbit, DayKey.add(last, -i)),
        ...appDay(AppShape.fitbit, last)
          ..removeWhere((r) => r.type == HcType.restingHr),
      ];
      final recs = resolve(ingest(records, now));
      final r = Engine.computeRange(recs, now: now).last;
      expect(recs.last.sleepingHr4h, isNotNull, reason: 'computed, unused');
      expect(
        r.recovery!.components.any(
          (c) => c.key == RecoveryEngine.sleepingHrKey,
        ),
        isFalse,
      );
    });
  });

  group('recordingMethod and N3 single nightly HRV', () {
    test('ACTIVE / MANUAL readings are spot checks: stored, never nightly', () {
      final wake = DayKey.start(last).add(const Duration(hours: 7));
      final records = [
        ...night(
          'n',
          wake.subtract(const Duration(hours: 8)),
          wake,
          origin: SourceApps.oura,
        ),
        for (var i = 0; i < 6; i++)
          hrvRec(
            'a$i',
            wake.subtract(Duration(hours: 1 + i)),
            40,
            HcRecordingMethod.automatic,
          ),
        // A daytime / in-sleep active spot check must not count.
        hrvRec(
          'spot',
          wake.subtract(const Duration(hours: 2)),
          200,
          HcRecordingMethod.active,
        ),
      ];
      final rows = ingest(records, now);
      expect(
        rows.hrv.firstWhere((r) => r.sourceRecordId == 'spot').isSpot,
        isTrue,
      );
      final d = resolve(rows).last;
      expect(d.hrvRmssd, 40);
    });

    test('shape: series vs single, decided with hysteresis', () {
      final plan = OriginPlan(
        metric: Metric.hrv,
        segments: [OriginSegment(SourceApps.oura, DayKey.add(last, -20))],
      );
      Map<String, int> counts(int n, int each) => {
        for (var i = 1; i <= n; i++) DayKey.add(last, -i + 1): each,
      };
      final single = SourceChooser.updateShape(
        plan,
        counts(14, 1),
        today: DayKey.add(last, 1),
      );
      expect(single.shape, 'single');
      // Half the nights with a series: stays single (needs ≥ 75 %).
      final mixed = {
        ...counts(14, 1),
        for (var i = 0; i < 7; i++) DayKey.add(last, -i): 5,
      };
      expect(
        SourceChooser.updateShape(
          single,
          mixed,
          today: DayKey.add(last, 1),
        ).shape,
        'single',
      );
      expect(
        SourceChooser.updateShape(
          single,
          counts(14, 6),
          today: DayKey.add(last, 1),
        ).shape,
        'samples',
      );
    });

    test('N3: a single-shape app gives hc_nightly_rmssd from its 1–2 '
        'records (wake-stamped, noon-stamped, in sleep); a daytime ACTIVE '
        'spot never leaks in', () {
      final records = <HcRecord>[];
      for (var i = 0; i < 10; i++) {
        final day = DayKey.add(last, -i);
        final wake = DayKey.start(day).add(const Duration(hours: 7));
        records.addAll(
          night(
            'n$i',
            wake.subtract(const Duration(hours: 8)),
            wake,
            origin: SourceApps.oura,
          ),
        );
        records.add(switch (i % 3) {
          0 => hrvRec('w$i', wake, 50, HcRecordingMethod.automatic),
          1 => hrvRec(
            'noon$i',
            DayKey.start(day).add(const Duration(hours: 12)),
            52,
            HcRecordingMethod.automatic,
          ),
          _ => hrvRec(
            's$i',
            wake.subtract(const Duration(hours: 3)),
            54,
            HcRecordingMethod.unknown,
          ),
        });
        records.add(
          hrvRec(
            'spot$i',
            DayKey.start(day).add(const Duration(hours: 15)),
            150,
            HcRecordingMethod.active,
          ),
        );
      }
      final rows = ingest(records, now);
      final counts = hrvNightCounts(rows, SourceApps.oura);
      final plan = SourceChooser.updateShape(
        SourceChooser.update(
          Metric.hrv,
          originDaysOf(rows)[Metric.hrv]!,
          null,
          today: DayKey.add(last, 1),
        )!,
        counts,
        today: DayKey.add(last, 1),
      );
      expect(plan.shape, 'single');
      final recs = resolve(rows, plans: {Metric.hrv: plan});
      final byDate = {for (final r in recs) r.date: r};
      for (var i = 0; i < 10; i++) {
        final d = byDate[DayKey.add(last, -i)]!;
        expect(
          d.definitionOf(Metric.hrv),
          Definitions.hrvNightly,
          reason: d.date,
        );
        expect(d.hrvRmssd, isNot(150), reason: 'spot leaked on ${d.date}');
        expect(d.hrvRmssd, [50.0, 52.0, 54.0][i % 3], reason: d.date);
      }
    });
  });
}
