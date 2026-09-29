// Raw rows as stored in the raw_* tables. Every row carries its source,
// an idempotent upsert key (source_record_id), the upstream record id (for
// Health Connect deletions), the writing app (origin_package) and the device.
//
// These are data-layer types only; the domain never sees them. The resolver
// turns them into DayRecords.

import 'dart:typed_data';

import '../../domain/models.dart';

/// Daily / nightly scalar metrics stored in raw_scalar.
enum ScalarKind {
  rhr('rhr'),
  resp('resp'),
  skinTempDelta('skin_temp_delta'),
  spo2Avg('spo2_avg'),
  spo2Min('spo2_min'),
  vo2max('vo2max'),
  steps('steps'),
  weight('weight'),

  /// Google Health API daily-heart-rate-variability average (all night).
  hrvDaily('hrv_daily'),

  /// Google Health API deep-sleep RMSSD (preferred HRV definition).
  hrvDeepSleep('hrv_deep_sleep'),

  /// On-demand BLE HRV check (RMSSD from RR), not a nightly value.
  hrvCheck('hrv_check');

  const ScalarKind(this.code);
  final String code;

  static ScalarKind fromCode(String c) =>
      values.firstWhere((k) => k.code == c, orElse: () => ScalarKind.rhr);
}

/// Which raw table a row lives in.
enum RawKind { hr, hrv, sleep, workout, scalar }

abstract class RawRow {
  RawRow({
    required this.source,
    required this.sourceRecordId,
    this.recordId,
    this.originPackage,
    this.device,
    DateTime? ingestedAt,
  }) : ingestedAt = ingestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final SourceKind source;

  /// Idempotent upsert key, unique per source.
  final String sourceRecordId;

  /// Upstream record id (Health Connect metadata.id). Several rows can share
  /// one (HR samples of one HeartRateRecord); deletions arrive by this id.
  final String? recordId;
  final String? originPackage;
  final String? device;
  DateTime ingestedAt;

  DateTime get start;
  DateTime get end;
  RawKind get kind;
}

class RawHrRow extends RawRow {
  RawHrRow({
    required super.source,
    required super.sourceRecordId,
    super.recordId,
    super.originPackage,
    super.device,
    super.ingestedAt,
    required this.t,
    required this.bpm,
  });
  final DateTime t;
  final double bpm;
  @override
  DateTime get start => t;
  @override
  DateTime get end => t;
  @override
  RawKind get kind => RawKind.hr;
}

class RawHrvRow extends RawRow {
  RawHrvRow({
    required super.source,
    required super.sourceRecordId,
    super.recordId,
    super.originPackage,
    super.device,
    super.ingestedAt,
    required this.t,
    required this.rmssd,
    this.recordingMethod,
  });
  final DateTime t;
  final double rmssd;

  /// Health Connect recordingMethod name ('automatic', 'active', 'manual',
  /// 'unknown'); null = not recorded (older rows, other sources).
  final String? recordingMethod;

  /// A spot reading (ACTIVE or MANUAL): stored as `hc_spot_rmssd`, never
  /// used for nightly HRV, baselines or Recovery (research/09b §3).
  bool get isSpot => recordingMethod == 'active' || recordingMethod == 'manual';
  @override
  DateTime get start => t;
  @override
  DateTime get end => t;
  @override
  RawKind get kind => RawKind.hrv;
}

class RawSleepRow extends RawRow {
  RawSleepRow({
    required super.source,
    required super.sourceRecordId,
    super.recordId,
    super.originPackage,
    super.device,
    super.ingestedAt,
    required this.start,
    required this.end,
    this.isMain,
    this.minutesAsleep,
    this.minutesAwake,
    this.stages = const [],
    this.writtenAt,
  });
  @override
  final DateTime start;
  @override
  final DateTime end;

  /// Upstream main-sleep flag when the source has one (Google Health API).
  final bool? isMain;
  final double? minutesAsleep;
  final double? minutesAwake;
  final List<StageSpan> stages;

  /// Upstream last-modified time when known (HC metadata via the Kotlin
  /// channel). Used for "later write wins" on duplicate nights.
  final DateTime? writtenAt;

  @override
  RawKind get kind => RawKind.sleep;

  RawSleepRow copyWith({
    List<StageSpan>? stages,
    DateTime? writtenAt,
    String? device,
  }) => RawSleepRow(
    source: source,
    sourceRecordId: sourceRecordId,
    recordId: recordId,
    originPackage: originPackage,
    device: device ?? this.device,
    ingestedAt: ingestedAt,
    start: start,
    end: end,
    isMain: isMain,
    minutesAsleep: minutesAsleep,
    minutesAwake: minutesAwake,
    stages: stages ?? this.stages,
    writtenAt: writtenAt ?? this.writtenAt,
  );
}

class RawWorkoutRow extends RawRow {
  RawWorkoutRow({
    required super.source,
    required super.sourceRecordId,
    super.recordId,
    super.originPackage,
    super.device,
    super.ingestedAt,
    required this.start,
    required this.end,
    required this.name,
    this.activityType,
    this.avgHr,
    this.calories,
    this.distanceM,
  });
  @override
  final DateTime start;
  @override
  final DateTime end;
  final String name;
  final String? activityType;
  final double? avgHr;
  final double? calories;
  final double? distanceM;
  @override
  RawKind get kind => RawKind.workout;
}

class RawScalarRow extends RawRow {
  RawScalarRow({
    required super.source,
    required super.sourceRecordId,
    super.recordId,
    super.originPackage,
    super.device,
    super.ingestedAt,
    required this.scalar,
    required this.start,
    DateTime? end,
    required this.value,
    this.day,
  }) : end = end ?? start;
  final ScalarKind scalar;
  @override
  final DateTime start;
  @override
  final DateTime end;
  final double value;

  /// Civil day ("yyyy-MM-dd") when the upstream value is a DAILY aggregate
  /// (Google Health API daily-* types); null means "derive from the time".
  final String? day;
  @override
  RawKind get kind => RawKind.scalar;
}

/// One day of heart rate from ONE source and ONE origin app, downsampled to
/// 1-minute buckets (mean bpm). Origins are never mixed in a bucket, so the
/// resolver can pick one app's heart rate per day (decision "Any app").
///
/// [tenths] has one slot per minute from local midnight ([dayStart]) to the
/// next local midnight, so DST days have 1380 or 1500 slots. A slot holds
/// round(bpm * 10), 0 = no sample in that minute.
class HrDay {
  HrDay({
    required this.source,
    required this.date,
    required this.dayStart,
    required this.tenths,
    this.origin = '',
    this.device,
    this.samples = 0,
    this.lastT,
  });
  final SourceKind source;

  /// Origin package of the samples ('' when the source has none).
  final String origin;
  final String date;
  final DateTime dayStart;
  final Uint16List tenths;
  final String? device;

  /// Raw samples that went into the buckets.
  final int samples;
  final DateTime? lastT;

  int get minutesWithData => tenths.where((v) => v > 0).length;

  /// One sample per filled minute. [utc]: timestamps as UTC instants
  /// (same instants, no time-zone lookup each; for consumers that only
  /// compare instants, like the engine and the storage encoder).
  List<HrSample> toSamples({bool utc = false}) {
    final out = <HrSample>[];
    final base = dayStart.millisecondsSinceEpoch;
    for (var i = 0; i < tenths.length; i++) {
      final v = tenths[i];
      if (v == 0) continue;
      out.add(
        HrSample(
          DateTime.fromMillisecondsSinceEpoch(base + i * 60000, isUtc: utc),
          v / 10.0,
        ),
      );
    }
    return out;
  }
}

/// A bag of raw rows: the unit of ingest (upsert batch) and of loading
/// (resolver input).
class RawRows {
  RawRows({
    List<RawHrRow>? hr,
    List<HrDay>? hrDays,
    List<RawHrvRow>? hrv,
    List<RawSleepRow>? sleep,
    List<RawWorkoutRow>? workouts,
    List<RawScalarRow>? scalars,
  }) : hr = hr ?? [],
       hrDays = hrDays ?? [],
       hrv = hrv ?? [],
       sleep = sleep ?? [],
       workouts = workouts ?? [],
       scalars = scalars ?? [];

  /// Raw HR samples (ingest; loads only include them on request).
  final List<RawHrRow> hr;

  /// Minute-bucketed HR per source and day (loads).
  final List<HrDay> hrDays;
  final List<RawHrvRow> hrv;
  final List<RawSleepRow> sleep;
  final List<RawWorkoutRow> workouts;
  final List<RawScalarRow> scalars;

  bool get isEmpty =>
      hr.isEmpty &&
      hrDays.isEmpty &&
      hrv.isEmpty &&
      sleep.isEmpty &&
      workouts.isEmpty &&
      scalars.isEmpty;

  int get length =>
      hr.length + hrv.length + sleep.length + workouts.length + scalars.length;

  Iterable<RawRow> get all sync* {
    yield* hr;
    yield* hrv;
    yield* sleep;
    yield* workouts;
    yield* scalars;
  }

  void addAll(RawRows o) {
    hr.addAll(o.hr);
    hrDays.addAll(o.hrDays);
    hrv.addAll(o.hrv);
    sleep.addAll(o.sleep);
    workouts.addAll(o.workouts);
    scalars.addAll(o.scalars);
  }

  /// Rows whose kind matches [kind] (and [scalar] for scalars).
  Iterable<RawRow> ofKind(RawKind kind, {ScalarKind? scalar}) sync* {
    switch (kind) {
      case RawKind.hr:
        yield* hr;
      case RawKind.hrv:
        yield* hrv;
      case RawKind.sleep:
        yield* sleep;
      case RawKind.workout:
        yield* workouts;
      case RawKind.scalar:
        yield* scalar == null
            ? scalars
            : scalars.where((s) => s.scalar == scalar);
    }
  }
}
