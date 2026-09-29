// Deterministic sample values for the component gallery and its goldens.
// Plausible shapes, fixed clock: nothing here reads DateTime.now() or Random.

import 'dart:math';

import '../../design/design.dart';
import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/results.dart';

/// [t] plus [minutes] (wall-clock arithmetic without a Duration literal).
DateTime plusMin(DateTime t, num minutes) => DateTime(
  t.year,
  t.month,
  t.day,
  t.hour,
  t.minute,
  t.second + (minutes * 60).round(),
);

abstract final class Samples {
  /// The gallery's clock: Monday 28 September 2026, 09:12.
  static final now = DateTime(2026, 9, 28, 9, 12);
  static const today = '2026-09-28';

  /// 30 nights of HRV (ms): a gentle wave, two missing nights, today high.
  static final hrv30 = <double?>[
    for (var i = 0; i < 30; i++)
      i == 8 || i == 19
          ? null
          : (47 + 5 * sin(i / 3.1) + 3 * cos(i / 1.7) + (i == 29 ? 12 : 0))
                .roundToDouble(),
  ];

  static final rhr7 = <double?>[56, 55, 57, 54, 55, 53, 54];
  static final resp7 = <double?>[14.8, 14.6, 14.9, 14.7, 14.5, 14.6, 14.6];
  static final skin7 = <double?>[0.1, 0.0, -0.1, -0.2, -0.3, -0.3, -0.4];

  /// 14 days of recovery (%) and strain (0–21), one day without data.
  static final recovery14 = <double?>[
    72,
    64,
    41,
    55,
    78,
    83,
    69,
    null,
    58,
    30,
    47,
    66,
    74,
    72,
  ];
  static final strain14 = <double?>[
    11.2,
    14.8,
    16.1,
    9.4,
    8.2,
    12.6,
    15.3,
    null,
    13.9,
    17.2,
    10.1,
    9.8,
    12.2,
    12.4,
  ];

  static List<String> xLabelsFor(int days) => [
    dayMonth(DayKey.add(today, -(days - 1))),
    dayMonth(DayKey.add(today, -((days - 1) ~/ 2))),
    'Today',
  ];

  static final components = <RecoveryComponent>[
    const RecoveryComponent(
      key: 'hrv',
      label: 'Heart rate variability',
      score01: .80,
      weight: .40,
      detail: '59 ms · usual 47 ms',
    ),
    const RecoveryComponent(
      key: 'rhr',
      label: 'Resting heart rate',
      score01: .72,
      weight: .25,
      detail: '54 bpm · usual 55 bpm',
    ),
    const RecoveryComponent(
      key: 'sleep',
      label: 'Sleep performance',
      score01: .64,
      weight: .25,
      detail: '7h 12m of 7h 50m needed',
    ),
    const RecoveryComponent(
      key: 'resp',
      label: 'Respiratory rate',
      score01: .60,
      weight: .10,
      detail: '14.6 /min · usual 14.4 /min',
    ),
  ];

  static const penalty = RecoveryPenalty('spo2', 'SpO₂ dipped below 90 %', 3);

  static HealthMetricStatus metric(
    HealthMetricKind k,
    BandState s,
    double? v,
    double mean,
    double sd, {
    Provenance? prov,
  }) => HealthMetricStatus(
    kind: k,
    state: s,
    value: v,
    baseline: Baseline(mean: mean, sd: sd, count: 21),
    lower: mean - 1.65 * sd,
    upper: mean + 1.65 * sd,
    provenance: prov,
  );

  /// SpO₂: one-sided band (a floor, no ceiling), as the engine reports it.
  static HealthMetricStatus spo2(double v) => HealthMetricStatus(
    kind: HealthMetricKind.spo2,
    state: v < 94 ? BandState.below : BandState.inRange,
    value: v,
    baseline: const Baseline(mean: 96.2, sd: .8, count: 21),
    lower: 94,
    provenance: const Provenance(SourceKind.googleHealthApi, 'ghapi_spo2'),
  );

  static final spo2Nights = <double?>[
    96,
    97,
    96,
    null,
    95,
    96,
    97,
    96,
    95,
    96,
    97,
    96,
    96,
    95,
  ];

  static const provHcRhr = Provenance(SourceKind.healthConnect, 'hc_daily_rhr');
  static const provGhHrv = Provenance(
    SourceKind.googleHealthApi,
    'ghapi_deep_sleep_rmssd',
  );
  static const provHcResp = Provenance(
    SourceKind.healthConnect,
    'hc_respiratory_rate',
  );

  static const trendUp = TrendResult(
    direction: TrendDirection.up,
    slopePerDay: .4,
    significant: true,
    n: 30,
  );
  static const trendDown = TrendResult(
    direction: TrendDirection.down,
    slopePerDay: -.3,
    significant: true,
    n: 30,
  );
  static const trendNoise = TrendResult(
    direction: TrendDirection.up,
    slopePerDay: .1,
    significant: false,
    n: 30,
  );

  static const load = TrainingLoad(
    acute7: 12.8,
    chronic28: 11.4,
    ratio: 1.12,
    state: LoadState.optimal,
    daysOfHistory: 41,
  );

  static const note = StatusNote(
    metric: 'hrv',
    title: 'No HRV from last night',
    body:
        'The band did not report heart rate variability for this sleep, so '
        'Recovery is built from resting HR, sleep and breathing only.',
    fix: 'Wear the band snugly to bed tonight',
  );

  static const warnNote = StatusNote(
    metric: 'sleep',
    severity: NoteSeverity.warning,
    title: 'Sleep looks split in two',
    body:
        'Fitbit recorded two sessions last night. Only the longer one '
        'counts as main sleep until you merge them.',
  );

  // ── the night ─────────────────────────────────────────────────────────
  static final bed = DateTime(2026, 9, 27, 23, 10);
  static final wake = DateTime(2026, 9, 28, 7, 2);

  static final stages = () {
    final pattern = <(SleepStage, int)>[
      (SleepStage.awake, 6),
      (SleepStage.light, 24),
      (SleepStage.deep, 48),
      (SleepStage.light, 20),
      (SleepStage.rem, 18),
      (SleepStage.awake, 3),
      (SleepStage.light, 34),
      (SleepStage.deep, 32),
      (SleepStage.light, 22),
      (SleepStage.rem, 28),
      (SleepStage.light, 30),
      (SleepStage.awake, 4),
      (SleepStage.light, 26),
      (SleepStage.deep, 14),
      (SleepStage.rem, 36),
      (SleepStage.light, 40),
      (SleepStage.awake, 2),
      (SleepStage.rem, 30),
      (SleepStage.light, 44),
      (SleepStage.awake, 11),
    ];
    final out = <StageSpan>[];
    var t = bed;
    for (final (s, m) in pattern) {
      final e = plusMin(t, m);
      out.add(StageSpan(s, t, e));
      t = e;
    }
    return out;
  }();

  /// 21 nights of bed / wake, with a late weekend and two missing nights.
  static final nights = <NightWindow?>[
    for (var i = 0; i < 21; i++)
      i == 6 || i == 15
          ? null
          : NightWindow(
              plusMin(
                DateTime(2026, 9, 7 + i, 22, 50),
                (sin(i * 1.3) * 25).round() + (i % 7 == 5 ? 70 : 0),
              ),
              plusMin(
                DateTime(2026, 9, 8 + i, 6, 55),
                (cos(i * .9) * 18).round() + (i % 7 == 6 ? 80 : 0),
              ),
            ),
  ];

  // ── the day's heart rate ──────────────────────────────────────────────
  static final dayStart = DateTime(2026, 9, 27);
  static final dayEnd = DateTime(2026, 9, 28);

  static const restingHr = 52.0, maxHr = 188.0;

  /// Karvonen floors for zones 1–5 (50/60/70/80/90 % HRR).
  static final zoneFloors = [
    for (final f in const [.5, .6, .7, .8, .9])
      restingHr + f * (maxHr - restingHr),
  ];

  static final hr = () {
    final out = <HrSample>[];
    for (var m = 0; m < 1440; m++) {
      if (m >= 750 && m < 820) continue; // on the charger
      final h = m / 60;
      double bpm;
      if (h < 7.0 || h >= 23.2) {
        bpm = 52 + 3 * sin(m / 37);
      } else if (h >= 18 && h < 18.85) {
        final k = (h - 18) / .85;
        bpm = 125 + 45 * sin(k * pi) + 6 * sin(m / 3);
      } else if (h >= 7.5 && h < 8.1) {
        bpm = 98 + 8 * sin(m / 5); // walk to work
      } else {
        bpm = 72 + 8 * sin(m / 23) + 5 * cos(m / 7);
      }
      out.add(HrSample(plusMin(dayStart, m), bpm));
    }
    return out;
  }();

  static final workout = (
    DateTime(2026, 9, 27, 18),
    DateTime(2026, 9, 27, 18, 51),
  );
  static final sleepPrev = (DateTime(2026, 9, 27), DateTime(2026, 9, 27, 7));

  /// Minutes in zones 1–5 today.
  static const zoneMinutes = [34.0, 22.0, 14.0, 9.0, 3.0];
}
