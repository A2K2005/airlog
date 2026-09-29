import 'package:airlog/data/db/hr_buckets.dart';
import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/resolver/definitions.dart';
import 'package:airlog/data/resolver/resolver.dart';
import 'package:airlog/data/resolver/sleep_dedup.dart';
import 'package:airlog/data/services/health_connect/hc_mapper.dart';
import 'package:airlog/data/services/health_connect/hc_types.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

const day = '2026-09-27';
final dayStart = DayKey.start(day);
final now = DateTime(2026, 9, 28, 12);
DateTime at(double h) => dayStart.add(Duration(minutes: (h * 60).round()));

RawSleepRow sleepRow(
  SourceKind s,
  String id,
  DateTime a,
  DateTime b, {
  DateTime? written,
  DateTime? ingested,
  bool? isMain,
  String origin = 'o',
}) => RawSleepRow(
  source: s,
  sourceRecordId: id,
  recordId: id,
  originPackage: origin,
  device: s == SourceKind.healthConnect ? 'Google Fitbit Air' : null,
  ingestedAt: ingested ?? now,
  start: a,
  end: b,
  writtenAt: written,
  isMain: isMain,
  stages: [
    StageSpan(SleepStage.light, a, a.add(b.difference(a) ~/ 2)),
    StageSpan(SleepStage.deep, a.add(b.difference(a) ~/ 2), b),
  ],
);

RawScalarRow sc(
  SourceKind s,
  ScalarKind k,
  String id,
  DateTime t,
  double v, {
  String? d,
}) => RawScalarRow(
  source: s,
  sourceRecordId: id,
  recordId: id,
  ingestedAt: now,
  scalar: k,
  start: t,
  value: v,
  day: d,
  device: s == SourceKind.healthConnect ? 'Google Fitbit Air' : null,
);

/// One HC SpO2 sample as the mapper stores it (night mean + minimum rows).
List<RawScalarRow> hcSpo2(String id, DateTime t, double v) => [
  sc(SourceKind.healthConnect, ScalarKind.spo2Avg, '$id:avg', t, v),
  sc(SourceKind.healthConnect, ScalarKind.spo2Min, '$id:min', t, v),
];

RawHrvRow hv(SourceKind s, String id, DateTime t, double v) => RawHrvRow(
  source: s,
  sourceRecordId: id,
  recordId: id,
  ingestedAt: now,
  t: t,
  rmssd: v,
);

/// Night 26→27 Sep (23:00–07:00) from HC and from the Google Health API.
RawRows twoSourceNight() => RawRows(
  sleep: [
    sleepRow(SourceKind.healthConnect, 'hc-n', at(-1), at(7)),
    sleepRow(SourceKind.googleHealthApi, 'gh-n', at(-1), at(7)),
  ],
  hrv: [
    for (var i = 0; i < 8; i++)
      hv(SourceKind.healthConnect, 'hc$i', at(i * 0.8), 40.0 + i),
    for (var i = 0; i < 8; i++)
      hv(SourceKind.googleHealthApi, 'gh$i', at(i * 0.8), 70),
  ],
  scalars: [
    sc(SourceKind.healthConnect, ScalarKind.rhr, 'hc-rhr', at(6), 52),
    sc(SourceKind.googleHealthApi, ScalarKind.rhr, 'gh-rhr', at(6), 58, d: day),
    sc(
      SourceKind.googleHealthApi,
      ScalarKind.spo2Avg,
      'gh-spo2',
      at(6),
      96,
      d: day,
    ),
    sc(
      SourceKind.googleHealthApi,
      ScalarKind.spo2Min,
      'gh-spo2min',
      at(6),
      92,
      d: day,
    ),
    // HC skin-temperature deltas during the night (evening one belongs to the wake day).
    sc(
      SourceKind.healthConnect,
      ScalarKind.skinTempDelta,
      'st1',
      at(-0.5),
      0.2,
    ),
    sc(SourceKind.healthConnect, ScalarKind.skinTempDelta, 'st2', at(3), 0.4),
  ],
);

DayRecord resolveOne(
  RawRows rows, {
  Set<SourceKind>? enabled,
  DataMode mode = DataMode.live,
}) {
  final recs = const Resolver().resolve(
    rows,
    day,
    day,
    ResolverConfig(mode: mode, now: now, enabled: enabled ?? kDefaultLive),
  );
  return recs.single;
}

const kDefaultLive = {
  SourceKind.healthConnect,
  SourceKind.googleHealthApi,
  SourceKind.ble,
};

void main() {
  test('priority: Health Connect beats Google Health API; never averaged', () {
    final r = resolveOne(twoSourceNight());
    expect(r.restingHr, 52);
    expect(r.provenance[Metric.restingHr]!.definition, 'hc_daily_rhr');
    expect(r.provenance[Metric.restingHr]!.device, 'Google Fitbit Air');
    expect(r.provenance[Metric.sleep]!.source, SourceKind.healthConnect);
    expect(r.sleepSessions, hasLength(1));
  });

  test('HRV = mean of HC RMSSD samples inside the main sleep', () {
    final r = resolveOne(twoSourceNight());
    expect(r.hrvRmssd, closeTo(43.5, 1e-9)); // mean of 40..47
    expect(r.provenance[Metric.hrv]!.definition, 'hc_sleep_mean_rmssd');
    expect(r.hrvSamples, hasLength(8));
  });

  test('a Google Health deep-sleep RMSSD wins over HC samples', () {
    final rows = twoSourceNight()
      ..scalars.add(
        sc(
          SourceKind.googleHealthApi,
          ScalarKind.hrvDeepSleep,
          'deep',
          at(6),
          61,
          d: day,
        ),
      );
    final r = resolveOne(rows);
    expect(r.hrvRmssd, 61);
    expect(r.provenance[Metric.hrv]!.definition, Definitions.hrvDeepSleep);
  });

  test('switching a source changes the definition (new baseline segment)', () {
    final withHc = resolveOne(twoSourceNight());
    final ghOnly = resolveOne(
      twoSourceNight(),
      enabled: {SourceKind.googleHealthApi},
    );
    expect(withHc.definitionOf(Metric.hrv), 'hc_sleep_mean_rmssd');
    expect(ghOnly.definitionOf(Metric.hrv), 'ghapi_sleep_mean_rmssd');
    expect(ghOnly.hrvRmssd, 70);
    expect(ghOnly.definitionOf(Metric.restingHr), 'ghapi_daily_rhr');
    expect(ghOnly.restingHr, 58);
  });

  test('SpO2 falls back to the Google Health API without HC samples; nightly scalars go to the wake day', () {
    final r = resolveOne(twoSourceNight());
    expect(r.spo2Avg, 96);
    expect(r.spo2Min, 92);
    expect(r.definitionOf(Metric.spo2), 'ghapi_nightly_spo2');
    expect(
      r.skinTempDelta,
      closeTo(0.3, 1e-9),
      reason: 'evening + night deltas → wake day',
    );
    expect(r.definitionOf(Metric.skinTemp), 'hc_nightly_skin_temp_delta');
  });

  test('HC SpO2 inside sleep wins over the Google Health API: avg = mean, min = lowest', () {
    final rows = twoSourceNight()
      ..scalars.addAll([
        ...hcSpo2('o1', at(1), 95),
        ...hcSpo2('o2', at(3), 97),
        ...hcSpo2('o3', at(5), 93),
      ]);
    final r = resolveOne(rows);
    expect(r.spo2Avg, closeTo(95, 1e-9));
    expect(r.spo2Min, 93);
    expect(r.definitionOf(Metric.spo2), 'hc_nightly_spo2');
    expect(r.provenance[Metric.spo2]!.device, 'Google Fitbit Air');
  });

  test(
    'HC SpO2 spot checks outside sleep are ignored (exact session bounds)',
    () {
      final rows = twoSourceNight()
        ..scalars.addAll([
          ...hcSpo2('night', at(2), 96),
          ...hcSpo2('bed', at(-1.5), 85), // 30 min before the 23:00 bedtime
          ...hcSpo2('woke', at(7.5), 86), // 30 min after the 07:00 wake
          ...hcSpo2('noon', at(12), 84),
        ]);
      final r = resolveOne(rows);
      expect(r.spo2Avg, 96);
      expect(r.spo2Min, 96);
      expect(r.definitionOf(Metric.spo2), 'hc_nightly_spo2');
    },
  );

  test('only daytime HC SpO2 → the Google Health API night still counts', () {
    final rows = twoSourceNight()..scalars.addAll(hcSpo2('noon', at(12), 99));
    final r = resolveOne(rows);
    expect(r.spo2Avg, 96);
    expect(r.spo2Min, 92);
    expect(r.definitionOf(Metric.spo2), 'ghapi_nightly_spo2');
  });

  test('HC SpO2 end to end: mapped BLOOD_OXYGEN samples → nightly avg/min on the wake day', () {
    final m = mapHcRecords(
      [
        for (final (id, h, v) in [
          ('a', -0.5, 0.95), // fraction, 23:30 the evening before → wake day
          ('b', 2.0, 97.0),
          ('c', 4.0, 93.0),
          ('d', 5.0, 40.0), // implausible: dropped at ingest
          ('e', 14.0, 90.0), // afternoon spot check: outside sleep
        ])
          HcRecord(
            type: HcType.spo2,
            id: id,
            origin: kFitbitOrigin,
            start: at(h),
            end: at(h),
            value: v,
          ),
      ],
      now: now,
      ingestedAt: now,
    );
    expect(m.rows.scalars, hasLength(8));
    final r = resolveOne(
      RawRows(
        sleep: [sleepRow(SourceKind.healthConnect, 'hc-n', at(-1), at(7))],
        scalars: m.rows.scalars,
      ),
    );
    expect(r.spo2Avg, closeTo(95, 1e-9));
    expect(r.spo2Min, closeTo(93, 1e-9));
    expect(r.definitionOf(Metric.spo2), 'hc_nightly_spo2');
  });

  test('demo mode sees only demo rows (and demo definitions)', () {
    final rows = twoSourceNight()
      ..sleep.add(sleepRow(SourceKind.demo, 'd-n', at(-1.5), at(6.5)))
      ..hrv.addAll([
        for (var i = 0; i < 5; i++) hv(SourceKind.demo, 'd$i', at(i * 1.0), 55),
      ])
      ..scalars.add(sc(SourceKind.demo, ScalarKind.rhr, 'd-rhr', at(6), 50));
    final r = resolveOne(rows, mode: DataMode.demo);
    expect(r.restingHr, 50);
    expect(r.definitionOf(Metric.hrv), 'demo_sleep_mean_rmssd');
    expect(r.definitionOf(Metric.sleep), 'demo_sleep_sessions');
    final live = resolveOne(rows);
    expect(live.definitionOf(Metric.hrv), 'hc_sleep_mean_rmssd');
  });

  test('future-dated rows are ignored', () {
    final rows = RawRows(
      scalars: [
        sc(
          SourceKind.healthConnect,
          ScalarKind.steps,
          'future',
          now.add(const Duration(hours: 3)),
          9000,
        ),
      ],
    );
    final recs = const Resolver().resolve(
      rows,
      day,
      DayKey.of(now),
      ResolverConfig(mode: DataMode.live, now: now),
    );
    expect(recs, isEmpty);
  });

  test('HR from 1-minute buckets; BLE live workouts are added when not overlapping', () {
    final hrDay = buildHrDay(SourceKind.healthConnect, day, [
      for (var i = 0; i < 120; i++)
        RawHrRow(
          source: SourceKind.healthConnect,
          sourceRecordId: 'h$i',
          ingestedAt: now,
          t: at(17).add(Duration(minutes: i)),
          bpm: 140,
        ),
    ]);
    RawWorkoutRow w(SourceKind s, String id, double h, double len) =>
        RawWorkoutRow(
          source: s,
          sourceRecordId: id,
          ingestedAt: now,
          start: at(h),
          end: at(h + len),
          name: id,
        );
    final rows = RawRows(
      hrDays: [hrDay],
      workouts: [
        w(SourceKind.healthConnect, 'band-run', 17, 1),
        w(SourceKind.ble, 'live-dup', 17.1, 0.8), // same session → dropped
        w(SourceKind.ble, 'live-extra', 20, 0.5), // band missed it → kept
      ],
    );
    final r = resolveOne(rows);
    expect(r.hrSamples, hasLength(120));
    expect(r.definitionOf(Metric.hr), 'hc_hr_1min');
    expect(r.workouts.map((x) => x.name), ['band-run', 'live-extra']);
    expect(
      r.workouts.first.averageHr,
      140,
      reason: 'filled from HR when the source has none',
    );
  });

  group('sleep dedup', () {
    test('time-zone duplicate night: the later write wins', () {
      final a = sleepRow(
        SourceKind.healthConnect,
        'first',
        at(-1),
        at(7),
        written: DateTime(2026, 9, 27, 8),
      );
      final b = sleepRow(
        SourceKind.healthConnect,
        'second',
        at(5),
        at(13),
        written: DateTime(2026, 9, 27, 14),
      );
      expect(isDuplicateNight(a, b), isTrue);
      expect(dedupSleep([a, b]).single.sourceRecordId, 'second');
    });

    test(
      'rewritten (overlapping) session: later ingest wins without metadata',
      () {
        final a = sleepRow(
          SourceKind.healthConnect,
          'old',
          at(-1),
          at(7),
          ingested: DateTime(2026, 9, 27, 8),
        );
        final b = sleepRow(
          SourceKind.healthConnect,
          'new',
          at(-0.8),
          at(7.1),
          ingested: DateTime(2026, 9, 27, 9),
        );
        expect(dedupSleep([b, a]).single.sourceRecordId, 'new');
      },
    );

    test('a nap is not a duplicate of the night', () {
      final n = sleepRow(SourceKind.healthConnect, 'night', at(-1), at(7));
      final nap = sleepRow(SourceKind.healthConnect, 'nap', at(14), at(14.5));
      expect(dedupSleep([n, nap]), hasLength(2));
      final r = resolveOne(RawRows(sleep: [n, nap]));
      expect(r.mainSleep!.id, 'hc:night');
      expect(r.naps.single.id, 'hc:nap');
    });

    test('different sources are never deduplicated against each other', () {
      final a = sleepRow(SourceKind.healthConnect, 'a', at(-1), at(7));
      final b = sleepRow(SourceKind.googleHealthApi, 'b', at(-1), at(7));
      expect(dedupSleep([a, b]), hasLength(2));
    });
  });
}
