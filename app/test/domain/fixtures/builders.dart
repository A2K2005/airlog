// Synthetic, deterministic day builders for engine unit tests. [ours]

import 'dart:math' as math;

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';

const hcHrv = Provenance(SourceKind.healthConnect, 'hc_sleep_mean_rmssd');
const ghHrv = Provenance(SourceKind.googleHealthApi, 'ghapi_deep_sleep_rmssd');
const hcRhr = Provenance(SourceKind.healthConnect, 'hc_daily_rhr');
const hcResp = Provenance(SourceKind.healthConnect, 'hc_sleep_resp');
const hcTemp = Provenance(SourceKind.healthConnect, 'hc_skin_temp_delta');

/// A fully populated day: 23:00→07:00 staged sleep, 1-min HR all day, a
/// 45-min run at 18:00 (avg 150), steps, nightly metrics with provenance.
DayRecord denseDay(
  String date, {
  double? hrv = 50,
  double? rhr = 55,
  double? resp = 14.5,
  double? skinTemp = 0.1,
  double? spo2Avg,
  double? spo2Min,
  double? vo2max,
  int? steps = 9000,
  Provenance hrvProv = hcHrv,
  bool workout = true,
  bool hr = true,
  int hrStepMinutes = 1,
  int seed = 1,
}) {
  final rng = math.Random(seed ^ date.hashCode);
  final dayStart = DayKey.start(date);
  final bed = dayStart.subtract(const Duration(hours: 1));
  final wake = dayStart.add(const Duration(hours: 7));
  final stages = <StageSpan>[];
  var t = bed;
  var i = 0;
  const cycle = [
    SleepStage.light,
    SleepStage.deep,
    SleepStage.light,
    SleepStage.rem,
  ];
  while (t.isBefore(wake)) {
    final end = t.add(const Duration(minutes: 30));
    stages.add(
      StageSpan(cycle[i % cycle.length], t, end.isAfter(wake) ? wake : end),
    );
    t = end;
    i++;
  }
  final w = Workout(
    id: 'w-$date',
    name: 'Run',
    start: dayStart.add(const Duration(hours: 18)),
    end: dayStart.add(const Duration(hours: 18, minutes: 45)),
    averageHr: 150,
  );
  final baseRhr = rhr ?? 55;
  final samples = <HrSample>[];
  if (hr) {
    for (var m = 0; m < 1440; m += hrStepMinutes) {
      final ts = dayStart.add(Duration(minutes: m));
      double bpm;
      if (ts.isBefore(wake)) {
        bpm = baseRhr + 3 + rng.nextDouble() * 2;
      } else if (workout && !ts.isBefore(w.start) && ts.isBefore(w.end)) {
        bpm = 145 + rng.nextDouble() * 10;
      } else {
        bpm = baseRhr + 18 + rng.nextDouble() * 12;
      }
      samples.add(HrSample(ts, bpm));
    }
  }
  return DayRecord(
    date: date,
    hrvRmssd: hrv,
    restingHr: rhr,
    respiratoryRate: resp,
    skinTempDelta: skinTemp,
    spo2Avg: spo2Avg,
    spo2Min: spo2Min,
    vo2max: vo2max,
    steps: steps,
    sleepSessions: [
      SleepSession(
        id: 's-$date',
        start: bed,
        end: wake,
        minutesAsleep: 465,
        minutesAwake: 15,
        stages: stages,
      ),
    ],
    workouts: workout ? [w] : [],
    hrSamples: samples,
    provenance: {
      if (hrv != null) Metric.hrv: hrvProv,
      if (rhr != null) Metric.restingHr: hcRhr,
      if (resp != null) Metric.respiratoryRate: hcResp,
      if (skinTemp != null) Metric.skinTemp: hcTemp,
    },
  );
}

/// [n] consecutive dense days ending at [last].
List<DayRecord> denseRange(
  String last,
  int n, {
  double Function(int i)? hrv,
  double Function(int i)? rhr,
}) {
  return [
    for (var i = 0; i < n; i++)
      denseDay(
        DayKey.add(last, i - (n - 1)),
        hrv: hrv == null ? 45 + (i % 5) * 2.0 : hrv(i),
        rhr: rhr == null ? 54 + (i % 3).toDouble() : rhr(i),
      ),
  ];
}

/// Recursively asserts every number in a JSON tree is finite.
List<String> nonFinite(Object? node, [String path = r'$']) {
  final bad = <String>[];
  if (node is num) {
    if (!node.isFinite) bad.add(path);
  } else if (node is Map) {
    for (final e in node.entries) {
      bad.addAll(nonFinite(e.value, '$path.${e.key}'));
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      bad.addAll(nonFinite(node[i], '$path[$i]'));
    }
  }
  return bad;
}
