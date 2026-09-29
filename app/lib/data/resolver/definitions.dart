// Provenance definitions and the per-metric source priority
// (ARCHITECTURE.md §3). One place, so the resolver, diagnostics and tests
// agree on every string.
//
// A definition says HOW a value was derived. The engine only builds a
// baseline from days with the same definition, so a source switch starts a
// new baseline segment.

import '../../domain/engine/source_apps.dart';
import '../../domain/models.dart';

abstract final class Definitions {
  static String hrvSleepMean(SourceKind s) => '${s.code}_sleep_mean_rmssd';
  static const String hrvDeepSleep = 'ghapi_deep_sleep_rmssd';
  static const String hrvGhapiDaily = 'ghapi_daily_rmssd';

  /// HRV ladder N3: an app that writes one or two nightly RMSSD records
  /// (persisted shape "single"), mean of them (research/09b §3).
  static const String hrvNightly = 'hc_nightly_rmssd';

  /// HRV ladder S1: sleeping HR, 4 h mean from sleep start + 30 min.
  static const String sleepingHr4h = 'hc_sleep_hr_4h_mean';
  static String hr(SourceKind s) => '${s.code}_hr_1min';
  static String rhr(SourceKind s) => '${s.code}_daily_rhr';
  static String resp(SourceKind s) => '${s.code}_nightly_resp';
  static String skinTemp(SourceKind s) => '${s.code}_nightly_skin_temp_delta';
  static String spo2(SourceKind s) => '${s.code}_nightly_spo2';
  static String vo2max(SourceKind s) => '${s.code}_vo2max';
  static String sleep(SourceKind s) => '${s.code}_sleep_sessions';
  static String workouts(SourceKind s) => '${s.code}_exercise_sessions';
  static String steps(SourceKind s) => '${s.code}_daily_steps';
  static String weight(SourceKind s) => '${s.code}_weight';
}

/// First available wins, per day. Demo mode ignores this: demo is the only
/// source there.
const Map<Metric, List<SourceKind>> kLivePriority = {
  Metric.hr: [
    SourceKind.healthConnect,
    SourceKind.googleHealthApi,
    SourceKind.takeout,
    SourceKind.ble,
  ],
  Metric.restingHr: [
    SourceKind.healthConnect,
    SourceKind.googleHealthApi,
    SourceKind.takeout,
  ],
  Metric.respiratoryRate: [
    SourceKind.healthConnect,
    SourceKind.googleHealthApi,
    SourceKind.takeout,
  ],
  Metric.skinTemp: [
    SourceKind.healthConnect,
    SourceKind.googleHealthApi,
    SourceKind.takeout,
  ],
  Metric.sleep: [
    SourceKind.healthConnect,
    SourceKind.googleHealthApi,
    SourceKind.takeout,
  ],
  // BLE live workouts are added on top when they don't overlap (see resolver).
  Metric.workouts: [
    SourceKind.healthConnect,
    SourceKind.googleHealthApi,
    SourceKind.takeout,
  ],
  Metric.steps: [
    SourceKind.healthConnect,
    SourceKind.googleHealthApi,
    SourceKind.takeout,
    SourceKind.context,
  ],
  // SpO2: Health Connect OxygenSaturationRecord samples inside sleep
  // (hc_nightly_spo2), else the Google Health API's nightly values.
  Metric.spo2: [SourceKind.healthConnect, SourceKind.googleHealthApi],
  Metric.vo2max: [
    SourceKind.healthConnect,
    SourceKind.googleHealthApi,
    SourceKind.takeout,
  ],
  Metric.weight: [
    SourceKind.healthConnect,
    SourceKind.context,
    SourceKind.googleHealthApi,
  ],
};

/// Nightly HRV: sample sources whose RMSSD samples inside the main sleep are
/// averaged, in priority order, after the Google Health deep-sleep value.
const List<SourceKind> kHrvSamplePriority = [
  SourceKind.healthConnect,
  SourceKind.googleHealthApi,
  SourceKind.takeout,
];

/// Origin package of the Google Health (Fitbit) app in Health Connect. No
/// longer a filter (every origin is read; source_choice.dart picks one per
/// metric); kept for fixtures and the pre-v3 HR bucket migration.
const String kFitbitOrigin = SourceApps.fitbit;
