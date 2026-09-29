// Baselines keyed by Provenance.baselineKey (definition@origin): a change of
// app starts a new segment and the two apps are never pooled (decision
// "Any app", 2026-09-29).

import 'dart:convert';

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/baselines.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/source_apps.dart';
import 'package:airlog/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/builders.dart';

const fitbitHrv = Provenance(
  SourceKind.healthConnect,
  'hc_sleep_mean_rmssd',
  origin: SourceApps.fitbit,
);
const samsungHrv = Provenance(
  SourceKind.healthConnect,
  'hc_sleep_mean_rmssd',
  origin: SourceApps.samsungHealth,
);

/// [fitbitDays] nights of Fitbit HRV around 40 ms, then [samsungDays] of
/// Samsung HRV around 80 ms, ending on [last].
List<DayRecord> switched(String last, int fitbitDays, int samsungDays) {
  final n = fitbitDays + samsungDays;
  return [
    for (var i = 0; i < n; i++)
      denseDay(
        DayKey.add(last, i - (n - 1)),
        hrv: i < fitbitDays ? 40.0 + (i % 3) : 80.0 + (i % 3),
        hrvProv: i < fitbitDays ? fitbitHrv : samsungHrv,
      ),
  ];
}

void main() {
  final now = DateTime(2026, 9, 29, 9);

  test('baselineKey is definition@origin, definition alone without one', () {
    expect(
      fitbitHrv.baselineKey,
      'hc_sleep_mean_rmssd@com.fitbit.FitbitMobile',
    );
    expect(hcHrv.baselineKey, 'hc_sleep_mean_rmssd');
    expect(fitbitHrv == samsungHrv, isFalse);
  });

  test('switching the HRV origin from Fitbit to Samsung starts a new '
      'segment; the two are never pooled', () {
    final days = switched('2026-09-20', 20, 6);
    final today = days.last;
    final history = days.sublist(0, days.length - 1);

    final seg = Baselines.segment(today, history, Metric.hrv);
    expect(seg.seg.key, samsungHrv.baselineKey);
    final values = Baselines.segmentValues(today, history, Metric.hrv);
    expect(values, hasLength(5), reason: 'only the 5 earlier Samsung nights');
    expect(values.every((v) => v >= 80), isTrue, reason: 'no Fitbit value');

    final r = Engine.computeDay(today, history: history, now: now);
    final hrv = r.recovery!.components.firstWhere((c) => c.key == 'hrv');
    expect(hrv.baseline!.count, 5);
    expect(hrv.baseline!.mean, greaterThanOrEqualTo(80));
    expect(
      r.notes.any((n) => n.title == 'New HRV baseline'),
      isFalse,
      reason: 'the switch was 5 nights ago, not today',
    );
    // The health band uses the same segment.
    final band = r.health.metrics.firstWhere((m) => m.kind.name == 'hrv');
    expect(band.baseline!.mean, greaterThanOrEqualTo(80));
  });

  test('the first Samsung night gets an app-named new-baseline note', () {
    final days = switched('2026-09-20', 20, 1);
    final r = Engine.computeDay(
      days.last,
      history: days.sublist(0, days.length - 1),
      now: now,
    );
    final note = r.notes.firstWhere((n) => n.title == 'New HRV baseline');
    expect(note.body, contains('Samsung Health'));
    expect(note.body, contains('Google Health (Fitbit)'));
    expect(note.body, contains('0 earlier nights'));
    // No Samsung baseline yet: HRV scores neutral instead of against Fitbit.
    final hrv = r.recovery!.components.firstWhere((c) => c.key == 'hrv');
    expect(hrv.baseline, isNull);
    expect(hrv.score01, 0.5);
  });

  test(
    'switching back to Fitbit resumes the Fitbit segment, still unpooled',
    () {
      final days = [
        ...switched('2026-09-20', 20, 6),
        for (var i = 1; i <= 2; i++)
          denseDay(DayKey.add('2026-09-20', i), hrv: 41, hrvProv: fitbitHrv),
      ];
      final today = days.last;
      final values = Baselines.segmentValues(
        today,
        days.sublist(0, days.length - 1),
        Metric.hrv,
      );
      expect(values.every((v) => v < 50), isTrue);
      expect(values, hasLength(21));
    },
  );

  test('origin survives the stored JSON round trip, so an incremental '
      'recompute keeps the segments apart', () {
    final days = switched('2026-09-20', 20, 6);
    final reloaded = [
      for (final d in days)
        DayRecord.fromJson(
          jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>,
        ),
    ];
    expect(reloaded.last.provenance[Metric.hrv], samsungHrv);
    expect(reloaded.first.provenance[Metric.hrv]!.origin, SourceApps.fitbit);
    final a = Engine.computeRange(days, now: now).last;
    final b = Engine.computeRange(reloaded, now: now).last;
    expect(jsonEncode(b.recovery!.toJson()), jsonEncode(a.recovery!.toJson()));
    expect(
      b.recovery!.components.firstWhere((c) => c.key == 'hrv').baseline!.count,
      5,
    );
  });

  test('same app, different device (Air vs Pixel Watch) is a new segment; '
      'an unknown device never splits one', () {
    Provenance dev(String? d) => Provenance(
      SourceKind.healthConnect,
      'hc_sleep_mean_rmssd',
      origin: SourceApps.fitbit,
      device: d,
    );
    expect(
      dev('Fitbit Air').baselineKey,
      'hc_sleep_mean_rmssd@com.fitbit.FitbitMobile#Fitbit Air',
    );
    final days = [
      for (var i = 0; i < 12; i++)
        denseDay(
          DayKey.add('2026-09-01', i),
          hrv: 40.0 + i % 3,
          // Background reads carry no device: every third Air night.
          hrvProv: dev(i % 3 == 2 ? null : 'Fitbit Air'),
        ),
      for (var i = 0; i < 6; i++)
        denseDay(
          DayKey.add('2026-09-13', i),
          hrv: 80.0 + i % 3,
          hrvProv: dev(i % 2 == 0 ? 'Google Pixel Watch 3' : null),
        ),
    ];
    final today = days.last; // device unknown → the Pixel Watch segment
    final history = days.sublist(0, days.length - 1);
    final s = Baselines.segment(today, history, Metric.hrv);
    expect(s.seg.prov!.device, 'Google Pixel Watch 3');
    final values = Baselines.segmentValues(today, history, Metric.hrv);
    expect(values.every((v) => v >= 80), isTrue, reason: '$values');
    expect(values, hasLength(5));
    final r = Engine.computeRange(days, now: now);
    final firstWatch = r[12];
    expect(firstWatch.notes.any((n) => n.title == 'New HRV baseline'), isTrue);
    // An Air night without device metadata did NOT start a segment.
    expect(r[2].notes.any((n) => n.title == 'New HRV baseline'), isFalse);
    expect(r[3].notes.any((n) => n.title == 'New HRV baseline'), isFalse);
  });

  test('calibration counts only nights of the current app segment', () {
    final days = switched('2026-09-20', 20, 3);
    for (final d in days) {
      // Resting HR from the same apps as HRV.
      d.provenance[Metric.restingHr] = Provenance(
        SourceKind.healthConnect,
        'hc_daily_rhr',
        origin: d.provenance[Metric.hrv]!.origin,
      );
    }
    final r = Engine.computeDay(
      days.last,
      history: days.sublist(0, days.length - 1),
      now: now,
    );
    expect(r.calibration.haveNights, 2);
    expect(r.recovery!.calibrating, isTrue);
  });
}
