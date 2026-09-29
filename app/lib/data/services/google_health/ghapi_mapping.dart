// Google Health API v4 data types, payload keys and value keys — ALL IN ONE
// PLACE because most of them are UNVERIFIED.
//
// Status (research/03-data-access.md, 2026-09-28):
//   * Verified in the official REST reference: the data-type names below,
//     HRV `rootMeanSquareOfSuccessiveDifferencesMilliseconds`,
//     `averageHeartRateVariabilityMilliseconds`,
//     `deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds`,
//     `nightlyTemperatureCelsius`, `baselineTemperatureCelsius`,
//     heart-rate `beatsPerMinute`, sleep STAGES AWAKE/LIGHT/DEEP/REM.
//   * UNVERIFIED (taken from Pulse's HealthAPIClient/SyncEngine, which was
//     written against the same new API): the payload key casing, the
//     AIP-160 filter field paths, envelope names (`dataPoints`,
//     `nextPageToken`), SpO2 / respiratory-rate / RHR / VO2 value keys and
//     the sleep summary keys. Candidate keys are tried in order, so a wrong
//     guess degrades to "0 values decoded" in the sync log (raw count > 0),
//     never a crash. Fix names HERE after the first real pull (`ghealth`
//     CLI, Phase 0).

enum GhTimeFilter { physical, civilDate }

class GhType {
  const GhType({
    required this.type,
    required this.payloadKey,
    required this.filterField,
    this.timeFilter = GhTimeFilter.physical,
    this.valueKeys = const [],
    this.timeKeys = const [
      'physicalTime',
      'sampleTime',
      'startTime',
      'time',
      'endTime',
    ],
  });

  /// kebab-case type in the URL path.
  final String type;

  /// camelCase key of the payload inside a data point.
  final String payloadKey;

  /// Field path after the payload key used in the `filter` query param.
  final String filterField;
  final GhTimeFilter timeFilter;
  final List<String> valueKeys;
  final List<String> timeKeys;
}

abstract final class GhMap {
  static const String baseUrl = 'https://health.googleapis.com/v4';

  static const scopes = [
    'https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly',
    'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
    'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
  ];

  static const authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const tokenEndpoint = 'https://oauth2.googleapis.com/token';

  static const envelopeKeys = ['dataPoints', 'data_points'];
  static const nextPageKeys = ['nextPageToken', 'next_page_token'];

  static const heartRate = GhType(
    type: 'heart-rate',
    payloadKey: 'heartRate',
    filterField: 'sample_time.physical_time',
    valueKeys: ['beatsPerMinute', 'bpm', 'value'],
  );

  static const hrvSamples = GhType(
    type: 'heart-rate-variability',
    payloadKey: 'heartRateVariability',
    filterField: 'sample_time.physical_time',
    valueKeys: [
      'rootMeanSquareOfSuccessiveDifferencesMilliseconds',
      'rmssdMilliseconds',
      'rmssd',
      'value',
    ],
  );

  static const hrvDaily = GhType(
    type: 'daily-heart-rate-variability',
    payloadKey: 'dailyHeartRateVariability',
    filterField: 'date',
    timeFilter: GhTimeFilter.civilDate,
    valueKeys: [
      'averageHeartRateVariabilityMilliseconds',
      'rmssdMilliseconds',
      'rmssd',
    ],
  );
  static const hrvDeepSleepKeys = [
    'deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds',
    'deepSleepRmssdMilliseconds',
  ];

  static const spo2Samples = GhType(
    type: 'oxygen-saturation',
    payloadKey: 'oxygenSaturation',
    filterField: 'sample_time.physical_time',
    valueKeys: ['percentage', 'value'],
  );

  static const spo2Daily = GhType(
    type: 'daily-oxygen-saturation',
    payloadKey: 'dailyOxygenSaturation',
    filterField: 'date',
    timeFilter: GhTimeFilter.civilDate,
    valueKeys: ['averagePercentage', 'percentage', 'value'],
  );
  static const spo2MinKeys = [
    'minimumPercentage',
    'lowerBoundPercentage',
    'minPercentage',
  ];

  static const respDaily = GhType(
    type: 'daily-respiratory-rate',
    payloadKey: 'dailyRespiratoryRate',
    filterField: 'date',
    timeFilter: GhTimeFilter.civilDate,
    valueKeys: ['breathsPerMinute', 'averageBreathsPerMinute', 'rate', 'value'],
  );

  static const skinTempDaily = GhType(
    type: 'daily-sleep-temperature-derivations',
    payloadKey: 'dailySleepTemperatureDerivations',
    filterField: 'date',
    timeFilter: GhTimeFilter.civilDate,
    valueKeys: ['nightlyTemperatureCelsius'],
  );
  static const skinTempBaselineKeys = ['baselineTemperatureCelsius'];

  static const rhrDaily = GhType(
    type: 'daily-resting-heart-rate',
    payloadKey: 'dailyRestingHeartRate',
    filterField: 'date',
    timeFilter: GhTimeFilter.civilDate,
    valueKeys: ['beatsPerMinute', 'bpm', 'value'],
  );

  static const vo2Daily = GhType(
    type: 'daily-vo2-max',
    payloadKey: 'dailyVo2Max',
    filterField: 'date',
    timeFilter: GhTimeFilter.civilDate,
    valueKeys: ['vo2Max', 'vo2max', 'cardioFitnessScore', 'value'],
  );

  static const sleep = GhType(
    type: 'sleep',
    payloadKey: 'sleep',
    filterField: 'interval.end_time',
  );
  static const sleepIntervalKeys = ['interval', 'sessionTimeInterval'];
  static const sleepStagesKey = 'stages';
  static const sleepStageTypeKey = 'type';
  static const sleepSummaryKeys = ['summary'];
  static const minutesAsleepKeys = ['minutesAsleep', 'totalMinutesAsleep'];
  static const minutesAwakeKeys = ['minutesAwake'];
  static const isMainSleepKeys = ['isMainSleep', 'mainSleep'];
  static const dateKeys = ['date'];
}
