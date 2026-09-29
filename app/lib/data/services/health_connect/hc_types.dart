// Backend-agnostic view of Health Connect used by the sync layer. The real
// implementation wraps the `health` plugin (+ our Kotlin channel); tests use
// a fake. No plugin types leak past this file's implementers.

import '../../../domain/models.dart';
import '../../../domain/repositories.dart';

/// The Health Connect record types Airlog reads (and requests READ for).
enum HcType {
  heartRate('HEART_RATE', 'android.permission.health.READ_HEART_RATE'),
  hrv(
    'HEART_RATE_VARIABILITY_RMSSD',
    'android.permission.health.READ_HEART_RATE_VARIABILITY',
  ),
  restingHr(
    'RESTING_HEART_RATE',
    'android.permission.health.READ_RESTING_HEART_RATE',
  ),
  respiratoryRate(
    'RESPIRATORY_RATE',
    'android.permission.health.READ_RESPIRATORY_RATE',
  ),
  skinTemp(
    'SKIN_TEMPERATURE',
    'android.permission.health.READ_SKIN_TEMPERATURE',
  ),
  sleep('SLEEP_SESSION', 'android.permission.health.READ_SLEEP'),
  exercise('WORKOUT', 'android.permission.health.READ_EXERCISE'),
  steps('STEPS', 'android.permission.health.READ_STEPS'),
  weight('WEIGHT', 'android.permission.health.READ_WEIGHT'),
  vo2max('VO2_MAX', 'android.permission.health.READ_VO2_MAX'),

  /// OxygenSaturationRecord (the plugin's BLOOD_OXYGEN; value 0–100 %).
  spo2('BLOOD_OXYGEN', 'android.permission.health.READ_OXYGEN_SATURATION'),

  /// Not stored; the plugin's workout reader sums distance and total
  /// calories inside each session and FAILS the whole workout read without
  /// these two permissions (HealthDataReader.handleWorkoutData).
  distance('DISTANCE_DELTA', 'android.permission.health.READ_DISTANCE'),
  totalCalories(
    'TOTAL_CALORIES_BURNED',
    'android.permission.health.READ_TOTAL_CALORIES_BURNED',
  );

  const HcType(this.key, this.permission);

  /// `health` plugin HealthDataType name (and Diagnostics label).
  final String key;
  final String permission;

  /// Types we store (read in sync). distance/totalCalories are helpers.
  static const stored = [
    heartRate,
    hrv,
    restingHr,
    respiratoryRate,
    skinTemp,
    sleep,
    exercise,
    steps,
    weight,
    vo2max,
    spo2,
  ];
}

const String kPermHistory =
    'android.permission.health.READ_HEALTH_DATA_HISTORY';
const String kPermBackground =
    'android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND';

/// Health Connect metadata.recordingMethod (HRV ladder, research/09b §3):
/// nightly HRV accepts AUTOMATIC or UNKNOWN inside the main sleep; ACTIVE
/// and MANUAL readings are spot checks, stored but never scored.
enum HcRecordingMethod {
  unknown,
  active,
  automatic,
  manual;

  static HcRecordingMethod fromName(String? n) =>
      values.firstWhere((m) => m.name == n, orElse: () => unknown);
}

/// One Health Connect datum, flattened. A HeartRateRecord yields one
/// HcRecord per sample (same [id]); a SleepSessionRecord yields one session
/// record plus one record per stage ([stage] set, same [id]).
class HcRecord {
  const HcRecord({
    required this.type,
    required this.id,
    required this.origin,
    required this.start,
    required this.end,
    this.value,
    this.stage,
    this.workoutType,
    this.distanceM,
    this.energyKcal,
    this.device,
    this.lastModified,
    this.recordingMethod = HcRecordingMethod.unknown,
  });

  final HcType type;

  /// metadata.id (shared by all samples / stages of one record).
  final String id;

  /// dataOrigin.packageName (the plugin puts it in `sourceName`; its
  /// `sourceId` is always "" on Android).
  final String origin;
  final DateTime start;
  final DateTime end;
  final double? value;

  /// Sleep stage records only; null = the session itself.
  final SleepStage? stage;
  final String? workoutType;
  final double? distanceM;
  final double? energyKcal;

  /// "Google Fitbit Air" etc. from metadata.device (Kotlin channel), if known.
  final String? device;
  final DateTime? lastModified;

  /// metadata.recordingMethod (unknown when the writer doesn't say).
  final HcRecordingMethod recordingMethod;

  HcRecord withMeta({String? device, DateTime? lastModified}) => HcRecord(
    type: type,
    id: id,
    origin: origin,
    start: start,
    end: end,
    value: value,
    stage: stage,
    workoutType: workoutType,
    distanceM: distanceM,
    energyKcal: energyKcal,
    device: device ?? this.device,
    lastModified: lastModified ?? this.lastModified,
    recordingMethod: recordingMethod,
  );
}

class HcChangesPage {
  const HcChangesPage({
    required this.upserts,
    required this.deletedIds,
    required this.nextToken,
    required this.hasMore,
    required this.expired,
  });
  final List<HcRecord> upserts;
  final List<String> deletedIds;
  final String nextToken;
  final bool hasMore;
  final bool expired;
}

/// Metadata for one record (device + last-modified), from the Kotlin channel.
class HcRecordMeta {
  const HcRecordMeta(this.id, {this.origin, this.device, this.lastModified});
  final String id;
  final String? origin;
  final String? device;
  final DateTime? lastModified;
}

abstract class HealthConnectSource {
  Future<HcAvailability> availability();

  /// Granted / missing per type + history/background flags.
  Future<HcPermissionState> permissionState();

  /// Opens the Health Connect sheet for every type + history + background.
  Future<HcPermissionState> requestPermissions();

  /// All origins, unfiltered; throws SourceException on failure.
  Future<List<HcRecord>> read(HcType type, DateTime from, DateTime to);

  /// Null when the token could not be created.
  Future<String?> changesToken(List<HcType> types);

  /// Null on any failure (treated like an expired token: full re-read).
  Future<HcChangesPage?> changes(String token);

  /// Whether the device's Health Connect supports [type] at all
  /// (SKIN_TEMPERATURE is a feature flag on older versions).
  Future<bool> supports(HcType type);
}
