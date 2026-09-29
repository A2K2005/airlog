// Health Connect records → raw rows, applying the ingest clean-up rules
// (ARCHITECTURE.md §4):
//   * every origin app is read (decision "Any app", 2026-09-29); each row
//     keeps its origin package, and the resolver later uses ONE origin per
//     metric (never summed or averaged);
//   * types Airlog doesn't score (weight; later nutrition) take the
//     context-only path: SourceKind.context rows, stored only when the user
//     enabled context sources, never an input to a score;
//   * drop future-dated records (e.g. calorie "projection" rows that end at
//     local midnight);
//   * assemble sleep sessions from session + stage records;
//   * SpO₂ samples → one spo2Avg + one spo2Min row each (the resolver keeps
//     only samples inside sleep and takes the night's mean / minimum).

import '../../../domain/models.dart';
import '../../db/raw_rows.dart';
import 'hc_types.dart';

class HcMapResult {
  HcMapResult(this.rows, {this.foreign = 0, this.future = 0});
  final RawRows rows;

  /// Context-only records dropped because context sources are off.
  final int foreign;

  /// Records dropped because they end in the future.
  final int future;
}

/// Grace for clock skew before a record counts as future-dated.
const Duration kFutureGrace = Duration(minutes: 2);

SleepStage? hcStageFromKey(String key) => switch (key) {
  'SLEEP_LIGHT' => SleepStage.light,
  'SLEEP_DEEP' => SleepStage.deep,
  'SLEEP_REM' => SleepStage.rem,
  'SLEEP_AWAKE' ||
  'SLEEP_AWAKE_IN_BED' ||
  'SLEEP_OUT_OF_BED' => SleepStage.awake,
  // "Asleep, stage not specified": counted as asleep by the resolver.
  'SLEEP_ASLEEP' => SleepStage.unknown,
  _ => null,
};

/// SpO₂ as a percentage. A value <= 1 is a fraction (×100); anything outside
/// 50–100 % is a bad read and returns null.
double? spo2Percent(double? v) {
  if (v == null || v.isNaN) return null;
  final pct = v <= 1.0 ? v * 100 : v;
  return pct < 50 || pct > 100 ? null : pct;
}

String prettyWorkout(String? type) {
  if (type == null || type.isEmpty) return 'Workout';
  const names = {
    'RUNNING': 'Run',
    'RUNNING_TREADMILL': 'Treadmill run',
    'WALKING': 'Walk',
    'BIKING': 'Cycling',
    'BIKING_STATIONARY': 'Indoor cycling',
    'STRENGTH_TRAINING': 'Strength training',
    'WEIGHTLIFTING': 'Weightlifting',
    'HIGH_INTENSITY_INTERVAL_TRAINING': 'HIIT',
    'SWIMMING_POOL': 'Pool swim',
    'SWIMMING_OPEN_WATER': 'Open-water swim',
    'YOGA': 'Yoga',
    'HIKING': 'Hike',
    'ELLIPTICAL': 'Elliptical',
    'ROWING_MACHINE': 'Rowing machine',
    'OTHER': 'Workout',
  };
  final n = names[type];
  if (n != null) return n;
  final s = type.toLowerCase().replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

HcMapResult mapHcRecords(
  List<HcRecord> records, {
  required DateTime now,
  required DateTime ingestedAt,
  bool contextEnabled = false,
}) {
  final rows = RawRows();
  var foreign = 0, future = 0;
  final cutoff = now.add(kFutureGrace);
  final sessions = <String, HcRecord>{};
  final stages = <String, List<HcRecord>>{};

  for (final r in records) {
    if (r.end.isAfter(cutoff) || r.start.isAfter(cutoff)) {
      future++;
      continue;
    }
    final contextOnly = r.type == HcType.weight;
    if (contextOnly && !contextEnabled) {
      foreign++;
      continue;
    }
    final source = contextOnly ? SourceKind.context : SourceKind.healthConnect;
    RawScalarRow scalar(ScalarKind k, {String? srid, double? value}) =>
        RawScalarRow(
          source: source,
          sourceRecordId: srid ?? r.id,
          recordId: r.id,
          originPackage: r.origin,
          device: r.device,
          ingestedAt: ingestedAt,
          scalar: k,
          start: r.start,
          end: r.end,
          value: value ?? r.value ?? 0,
        );
    switch (r.type) {
      case HcType.heartRate:
        if (r.value == null) continue;
        rows.hr.add(
          RawHrRow(
            source: source,
            sourceRecordId: '${r.id}@${r.start.millisecondsSinceEpoch}',
            recordId: r.id,
            originPackage: r.origin,
            device: r.device,
            ingestedAt: ingestedAt,
            t: r.start,
            bpm: r.value!,
          ),
        );
      case HcType.hrv:
        if (r.value == null) continue;
        rows.hrv.add(
          RawHrvRow(
            source: source,
            sourceRecordId: r.id,
            recordId: r.id,
            originPackage: r.origin,
            device: r.device,
            ingestedAt: ingestedAt,
            t: r.start,
            rmssd: r.value!,
            recordingMethod: r.recordingMethod.name,
          ),
        );
      case HcType.restingHr:
        if (r.value != null) rows.scalars.add(scalar(ScalarKind.rhr));
      case HcType.respiratoryRate:
        if (r.value != null) rows.scalars.add(scalar(ScalarKind.resp));
      case HcType.skinTemp:
        // One SkinTemperatureRecord carries many deltas (same id).
        if (r.value != null) {
          rows.scalars.add(
            scalar(
              ScalarKind.skinTempDelta,
              srid: '${r.id}@${r.start.millisecondsSinceEpoch}',
            ),
          );
        }
      case HcType.steps:
        if (r.value != null) rows.scalars.add(scalar(ScalarKind.steps));
      case HcType.weight:
        if (r.value != null) rows.scalars.add(scalar(ScalarKind.weight));
      case HcType.vo2max:
        if (r.value != null) rows.scalars.add(scalar(ScalarKind.vo2max));
      case HcType.spo2:
        // One OxygenSaturationRecord = one sample. Distinct srids: the raw
        // scalar key is (source, source_record_id) across kinds. `day` stays
        // null so the resolver assigns the wake day.
        final pct = spo2Percent(r.value);
        if (pct == null) continue;
        rows.scalars
          ..add(scalar(ScalarKind.spo2Avg, srid: '${r.id}:avg', value: pct))
          ..add(scalar(ScalarKind.spo2Min, srid: '${r.id}:min', value: pct));
      case HcType.sleep:
        if (r.stage == null) {
          sessions[r.id] = r;
        } else {
          stages.putIfAbsent(r.id, () => []).add(r);
        }
      case HcType.exercise:
        rows.workouts.add(
          RawWorkoutRow(
            source: source,
            sourceRecordId: r.id,
            recordId: r.id,
            originPackage: r.origin,
            device: r.device,
            ingestedAt: ingestedAt,
            start: r.start,
            end: r.end,
            name: prettyWorkout(r.workoutType),
            activityType: r.workoutType,
            calories: r.energyKcal,
            distanceM: r.distanceM,
          ),
        );
      case HcType.distance:
      case HcType.totalCalories:
        break;
    }
  }

  for (final s in sessions.values) {
    final st = <StageSpan>[
      for (final x in stages[s.id] ?? const <HcRecord>[])
        if (x.stage != null && x.end.isAfter(x.start))
          StageSpan(
            x.stage!,
            x.start.isBefore(s.start) ? s.start : x.start,
            x.end.isAfter(s.end) ? s.end : x.end,
          ),
    ]..sort((a, b) => a.start.compareTo(b.start));
    rows.sleep.add(
      RawSleepRow(
        source: SourceKind.healthConnect,
        sourceRecordId: s.id,
        recordId: s.id,
        originPackage: s.origin,
        device: s.device,
        ingestedAt: ingestedAt,
        start: s.start,
        end: s.end,
        stages: st,
        writtenAt: s.lastModified,
      ),
    );
  }
  return HcMapResult(rows, foreign: foreign, future: future);
}
