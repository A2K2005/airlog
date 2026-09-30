// Engine outputs: one immutable, algorithm-versioned DayResult per day.
//
// CONTRACT FILE — the engine produces these, the data layer stores them
// (JSON in SQLite `day_result`), the UI renders them. Additive changes only.
// Pure Dart: no Flutter or plugin imports.
//
// Field semantics follow Pulse (Core/Metrics/*.swift, Apache-2.0); see
// third_party/pulse/NOTICE. Additions of ours are marked [ours].

import 'models.dart';

/// Bump when any formula or constant changes; stored with every DayResult so
/// history can be recomputed and old rows identified.
///   2 (2026-09-29): baselines keyed by definition@origin#device (a change
///     of app or device starts a new segment); RecoveryResult.withoutHrv /
///     coverage / confidence; no strain score without heart rate (the MET
///     and steps estimate is gone); max HR from the birth year, else the
///     observed maximum (never an assumed age); Pulse Age not computed in
///     v1; journal insights need 10 days per group with Holm correction;
///     DayResult.sourceChange; new StatusNotes (not shared, app-named new
///     baseline, observed max HR).
// 3: preserve unknown sleep stages, shared HR anchors, gap-aware alerts,
// device-consistent readiness and persisted partial-strain quality.
const int kAlgoVersion = 3;

// ── Shared ───────────────────────────────────────────────────────────────

/// Personal baseline of one metric (mean/SD over the trailing window).
class Baseline {
  const Baseline({required this.mean, required this.sd, required this.count});
  final double mean;
  final double sd;
  final int count;

  /// Pulse: a baseline is trusted from 5 values.
  bool get isReliable => count >= 5;

  double z(double value, {double minSd = 0.0001}) =>
      (value - mean) / (sd < minSd ? minSd : sd);

  Map<String, dynamic> toJson() => {'mean': mean, 'sd': sd, 'count': count};
  factory Baseline.fromJson(Map<String, dynamic> j) => Baseline(
    mean: (j['mean'] as num).toDouble(),
    sd: (j['sd'] as num).toDouble(),
    count: j['count'] as int,
  );
}

Baseline? _bl(Object? j) =>
    j == null ? null : Baseline.fromJson(j as Map<String, dynamic>);
double? _d(Object? j) => (j as num?)?.toDouble();
DateTime? _t(Object? j) =>
    j == null ? null : DateTime.parse(j as String).toLocal();
String? _ts(DateTime? t) => t?.toUtc().toIso8601String();

/// How far along the personal baselines are. [ours]
///   * < 5 nights: calibrating, scores are shown as provisional ranges
///   * 5..13: provisional (labelled with confidence)
///   * >= 14: established
class Calibration {
  const Calibration({required this.haveNights, this.needNights = 14});
  final int haveNights;
  final int needNights;

  bool get calibrating => haveNights < 5;
  bool get established => haveNights >= needNights;
  double get progress =>
      needNights == 0 ? 1 : (haveNights / needNights).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
    'haveNights': haveNights,
    'needNights': needNights,
  };
  factory Calibration.fromJson(Map<String, dynamic> j) => Calibration(
    haveNights: j['haveNights'] as int,
    needNights: j['needNights'] as int? ?? 14,
  );
}

/// A "status card instead of a guessed number" note. [ours, from Edge]
enum NoteSeverity { info, warning }

class StatusNote {
  const StatusNote({
    required this.metric,
    required this.title,
    required this.body,
    this.severity = NoteSeverity.info,
    this.fix,
  });

  /// Metric code (Metric.code) or 'recovery' / 'strain' / 'sleep'.
  final String metric;
  final String title;
  final String body;
  final NoteSeverity severity;

  /// Optional short instruction, e.g. "Wear the band to bed tonight".
  final String? fix;

  Map<String, dynamic> toJson() => {
    'metric': metric,
    'title': title,
    'body': body,
    'severity': severity.name,
    if (fix != null) 'fix': fix,
  };
  factory StatusNote.fromJson(Map<String, dynamic> j) => StatusNote(
    metric: j['metric'] as String,
    title: j['title'] as String,
    body: j['body'] as String,
    severity: NoteSeverity.values.byName(j['severity'] as String),
    fix: j['fix'] as String?,
  );
}

// ── Recovery ─────────────────────────────────────────────────────────────

enum RecoveryZone { green, yellow, red }

/// How much of the Recovery model reported today. [ours]
///   * high: HRV plus at least 90 % of the model weight;
///   * reduced: scored without HRV, or with less than 90 % of the weight
///     (e.g. no sleep data);
///   * low: less than half of the model weight (e.g. resting HR alone).
enum RecoveryConfidence { high, reduced, low }

class RecoveryComponent {
  const RecoveryComponent({
    required this.key,
    required this.label,
    required this.score01,
    required this.weight,
    required this.detail,
    this.value,
    this.baseline,
    this.z,
  });

  /// 'hrv' | 'rhr' | 'sleep' | 'resp'
  final String key;
  final String label;

  /// Sub-score 0..1.
  final double score01;

  /// Normalised weight after re-weighting missing inputs (sum = 1).
  final double weight;

  /// e.g. "52 ms · baseline 47 ms"
  final String detail;

  /// Today's raw value in display units (ms, bpm, %, /min). [ours]
  final double? value;

  /// Baseline in DISPLAY units (for HRV: mean/sd of raw ms, not ln). [ours]
  final Baseline? baseline;

  /// z-score used for the sub-score (HRV: on ln scale). [ours]
  final double? z;

  /// Contribution to the final score in points (score01 * weight * 100).
  double get points => score01 * weight * 100;

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'score01': score01,
    'weight': weight,
    'detail': detail,
    if (value != null) 'value': value,
    if (baseline != null) 'baseline': baseline!.toJson(),
    if (z != null) 'z': z,
  };
  factory RecoveryComponent.fromJson(Map<String, dynamic> j) =>
      RecoveryComponent(
        key: j['key'] as String,
        label: j['label'] as String,
        score01: (j['score01'] as num).toDouble(),
        weight: (j['weight'] as num).toDouble(),
        detail: j['detail'] as String,
        value: _d(j['value']),
        baseline: _bl(j['baseline']),
        z: _d(j['z']),
      );
}

/// A penalty applied after weighting (e.g. SpO2 min < 90 %: -7). [Pulse]
class RecoveryPenalty {
  const RecoveryPenalty(this.key, this.label, this.points);
  final String key;
  final String label;
  final double points; // positive number subtracted from the score

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'points': points,
  };
  factory RecoveryPenalty.fromJson(Map<String, dynamic> j) => RecoveryPenalty(
    j['key'] as String,
    j['label'] as String,
    (j['points'] as num).toDouble(),
  );
}

class RecoveryResult {
  const RecoveryResult({
    required this.score,
    required this.zone,
    required this.components,
    required this.calibrating,
    this.penalties = const [],
    this.hrvValue,
    this.hrvBaseline,
    this.rhrValue,
    this.rhrBaseline,
    this.withoutHrv = false,
    this.coverage = 1,
    this.confidence = RecoveryConfidence.high,
  });

  /// 1..99 %
  final int score;
  final RecoveryZone zone;
  final List<RecoveryComponent> components;
  final List<RecoveryPenalty> penalties;

  /// True while the baselines of the metrics that DO report are < 5 nights.
  final bool calibrating;
  final double? hrvValue;
  final Baseline? hrvBaseline; // ms scale
  final double? rhrValue;
  final Baseline? rhrBaseline;

  /// [ours] No HRV reached the engine for this night: the score comes from
  /// the other inputs with their weights re-normalised, and the UI labels it
  /// "without HRV". HRV is never estimated from anything else.
  final bool withoutHrv;

  /// [ours] Share of the full model weight (HRV 40, RHR 25, sleep 25,
  /// resp 10) that reported, 0..1 (e.g. 0.6 without HRV).
  final double coverage;

  /// [ours] See [RecoveryConfidence].
  final RecoveryConfidence confidence;

  static RecoveryZone zoneFor(int score) => score >= 67
      ? RecoveryZone.green
      : (score >= 34 ? RecoveryZone.yellow : RecoveryZone.red);

  Map<String, dynamic> toJson() => {
    'score': score,
    'zone': zone.name,
    'components': components.map((c) => c.toJson()).toList(),
    'penalties': penalties.map((p) => p.toJson()).toList(),
    'calibrating': calibrating,
    if (hrvValue != null) 'hrvValue': hrvValue,
    if (hrvBaseline != null) 'hrvBaseline': hrvBaseline!.toJson(),
    if (rhrValue != null) 'rhrValue': rhrValue,
    if (rhrBaseline != null) 'rhrBaseline': rhrBaseline!.toJson(),
    if (withoutHrv) 'withoutHrv': true,
    'coverage': coverage,
    'confidence': confidence.name,
  };
  factory RecoveryResult.fromJson(Map<String, dynamic> j) => RecoveryResult(
    score: j['score'] as int,
    zone: RecoveryZone.values.byName(j['zone'] as String),
    components: (j['components'] as List)
        .map((e) => RecoveryComponent.fromJson(e as Map<String, dynamic>))
        .toList(),
    penalties: (j['penalties'] as List? ?? const [])
        .map((e) => RecoveryPenalty.fromJson(e as Map<String, dynamic>))
        .toList(),
    calibrating: j['calibrating'] as bool,
    hrvValue: _d(j['hrvValue']),
    hrvBaseline: _bl(j['hrvBaseline']),
    rhrValue: _d(j['rhrValue']),
    rhrBaseline: _bl(j['rhrBaseline']),
    withoutHrv: j['withoutHrv'] as bool? ?? false,
    coverage: _d(j['coverage']) ?? 1,
    confidence: j['confidence'] == null
        ? RecoveryConfidence.high
        : RecoveryConfidence.values.byName(j['confidence'] as String),
  );
}

/// Plews lnRMSSD readiness: today's ln(RMSSD) 7-day rolling mean vs the
/// smallest worthwhile change band (baseline ± 0.5·SD). [ours, per Edge cites]
enum SwcState { within, above, below }

class ReadinessSwc {
  const ReadinessSwc({
    required this.lnRmssd7d,
    required this.baselineMean,
    required this.swcLower,
    required this.swcUpper,
    required this.state,
    required this.cv7d,
  });
  final double lnRmssd7d;
  final double baselineMean;
  final double swcLower;
  final double swcUpper;
  final SwcState state;

  /// Coefficient of variation of lnRMSSD over the last 7 days (%).
  final double cv7d;

  Map<String, dynamic> toJson() => {
    'lnRmssd7d': lnRmssd7d,
    'baselineMean': baselineMean,
    'swcLower': swcLower,
    'swcUpper': swcUpper,
    'state': state.name,
    'cv7d': cv7d,
  };
  factory ReadinessSwc.fromJson(Map<String, dynamic> j) => ReadinessSwc(
    lnRmssd7d: (j['lnRmssd7d'] as num).toDouble(),
    baselineMean: (j['baselineMean'] as num).toDouble(),
    swcLower: (j['swcLower'] as num).toDouble(),
    swcUpper: (j['swcUpper'] as num).toDouble(),
    state: SwcState.values.byName(j['state'] as String),
    cv7d: (j['cv7d'] as num).toDouble(),
  );
}

// ── Strain ───────────────────────────────────────────────────────────────

enum StrainMethod {
  /// Karvonen HRR zones on intraday HR (needs ~1 sample/min).
  hrZones,

  /// A WORKOUT scored from its own measured average heart rate (no samples
  /// inside it). Since algo v2 a DAY is never scored this way. [ours]
  fallback,

  /// No heart rate (or no max HR): no score. The day's activity facts
  /// (workouts, steps) are still reported.
  none,
}

/// [ours] Where the max heart rate behind the strain zones came from.
enum MaxHrSource {
  /// The profile's measured max-HR override.
  override,

  /// Tanaka 208 − 0.7 × age, from the profile's birth year.
  birthYear,

  /// No birth year: the highest heart rate observed in the last 90 days.
  /// Labelled in the UI.
  observed,
}

class WorkoutStrain {
  const WorkoutStrain({
    required this.workoutId,
    required this.strain,
    required this.zoneMinutes,
    this.avgHr,
    this.peakHr,
    this.trimp,
    this.method,
  });
  final String workoutId;
  final double strain; // 0..21
  final List<double> zoneMinutes; // 5 zones
  final double? avgHr;
  final double? peakHr;
  final double? trimp; // Banister TRIMP

  /// [ours] How this workout's strain was derived: `hrZones` = from HR
  /// samples inside the workout; `fallback` = estimated from the workout's
  /// recorded average HR. Null in rows written before
  /// this field existed.
  final StrainMethod? method;

  Map<String, dynamic> toJson() => {
    'workoutId': workoutId,
    'strain': strain,
    'zoneMinutes': zoneMinutes,
    if (avgHr != null) 'avgHr': avgHr,
    if (peakHr != null) 'peakHr': peakHr,
    if (trimp != null) 'trimp': trimp,
    if (method != null) 'method': method!.name,
  };
  factory WorkoutStrain.fromJson(Map<String, dynamic> j) => WorkoutStrain(
    workoutId: j['workoutId'] as String,
    strain: (j['strain'] as num).toDouble(),
    zoneMinutes: (j['zoneMinutes'] as List)
        .map((e) => (e as num).toDouble())
        .toList(),
    avgHr: _d(j['avgHr']),
    peakHr: _d(j['peakHr']),
    trimp: _d(j['trimp']),
    method: j['method'] == null
        ? null
        : StrainMethod.values.byName(j['method'] as String),
  );
}

class StrainResult {
  const StrainResult({
    required this.strain,
    required this.rawLoad,
    required this.zoneMinutes,
    required this.method,
    this.restMinutes = 0,
    this.avgHr,
    this.peakHr,
    this.maxHrUsed,
    this.restingHrUsed,
    this.trimp,
    this.targetStrain,
    this.workouts = const [],
    this.loadZoneMinutes = const [],
    this.maxHrSource,
    this.steps,
    this.zonesFromMaxHr = false,
    this.partial = true,
  });

  /// 0..21, `21·(1−e^(−load/τ))`, τ = 450.
  final double strain;
  final double rawLoad;

  /// Minutes in HRR zones 1..5 (50-60, 60-70, 70-80, 80-90, 90-100 %).
  final List<double> zoneMinutes;

  /// Minutes below display zone 1 (< 50 % HRR), so that [trackedMinutes] is
  /// the whole tracked time.
  final double restMinutes;

  /// [ours] Minutes in Pulse's six LOAD zones, which are what actually drive
  /// [rawLoad]: lower bounds 20/30/45/60/72/85 % HRR, weights
  /// 0.5/1/2.5/5/8/11 (labels in engine/strain.dart `StrainEngine`). Time
  /// between 20 and 50 % HRR adds load but shows as rest in [zoneMinutes].
  /// Empty in rows written before this field existed.
  final List<double> loadZoneMinutes;
  final StrainMethod method;
  final double? avgHr;
  final double? peakHr;
  final double? maxHrUsed; // [ours] for the explanation sheet
  final double? restingHrUsed; // [ours]
  final double? trimp; // [ours] Banister TRIMP cross-check

  /// Suggested strain for today given this morning's recovery. [Pulse]
  final double? targetStrain;
  final List<WorkoutStrain> workouts;

  /// [ours] Where [maxHrUsed] came from (null when there is none).
  final MaxHrSource? maxHrSource;

  /// [ours] The day's step count, an activity fact reported with or
  /// without a score (never converted into strain).
  final int? steps;

  /// [ours] No resting HR: zones used % of max HR (Swain 1994 conversion,
  /// StrainEngine.swainSlope) instead of heart-rate reserve; flagged.
  final bool zonesFromMaxHr;

  /// Incomplete HR coverage. Older cached rows have unknown coverage and
  /// must not be treated as complete observations by load/trend consumers.
  final bool partial;

  double get trackedMinutes =>
      restMinutes + zoneMinutes.fold(0.0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
    'strain': strain,
    'rawLoad': rawLoad,
    'zoneMinutes': zoneMinutes,
    'method': method.name,
    'restMinutes': restMinutes,
    if (avgHr != null) 'avgHr': avgHr,
    if (peakHr != null) 'peakHr': peakHr,
    if (maxHrUsed != null) 'maxHrUsed': maxHrUsed,
    if (restingHrUsed != null) 'restingHrUsed': restingHrUsed,
    if (trimp != null) 'trimp': trimp,
    if (targetStrain != null) 'targetStrain': targetStrain,
    'workouts': workouts.map((w) => w.toJson()).toList(),
    if (loadZoneMinutes.isNotEmpty) 'loadZoneMinutes': loadZoneMinutes,
    if (maxHrSource != null) 'maxHrSource': maxHrSource!.name,
    if (steps != null) 'steps': steps,
    if (zonesFromMaxHr) 'zonesFromMaxHr': true,
    'partial': partial,
  };
  factory StrainResult.fromJson(Map<String, dynamic> j) => StrainResult(
    strain: (j['strain'] as num).toDouble(),
    rawLoad: (j['rawLoad'] as num).toDouble(),
    zoneMinutes: (j['zoneMinutes'] as List)
        .map((e) => (e as num).toDouble())
        .toList(),
    method: StrainMethod.values.byName(j['method'] as String),
    restMinutes: _d(j['restMinutes']) ?? 0,
    avgHr: _d(j['avgHr']),
    peakHr: _d(j['peakHr']),
    maxHrUsed: _d(j['maxHrUsed']),
    restingHrUsed: _d(j['restingHrUsed']),
    trimp: _d(j['trimp']),
    targetStrain: _d(j['targetStrain']),
    workouts: (j['workouts'] as List? ?? const [])
        .map((e) => WorkoutStrain.fromJson(e as Map<String, dynamic>))
        .toList(),
    loadZoneMinutes: (j['loadZoneMinutes'] as List? ?? const [])
        .map((e) => (e as num).toDouble())
        .toList(),
    maxHrSource: j['maxHrSource'] == null
        ? null
        : MaxHrSource.values.byName(j['maxHrSource'] as String),
    steps: j['steps'] as int?,
    zonesFromMaxHr: j['zonesFromMaxHr'] as bool? ?? false,
    partial: j['partial'] as bool? ?? true,
  );
}

// ── Sleep ────────────────────────────────────────────────────────────────

class SleepAnalysis {
  const SleepAnalysis({
    required this.sleptMinutes,
    required this.napMinutes,
    required this.needMinutes,
    required this.performance,
    required this.debtAfterMinutes,
    required this.stageMinutes,
    required this.hasData,
    this.consistency,
    this.efficiency,
    this.bedTime,
    this.wakeTime,
    this.needBreakdown,
  });

  final double sleptMinutes;
  final double napMinutes;
  final double needMinutes;

  /// 0..100 (slept / need).
  final double performance;

  /// Sleep debt AFTER this night (minutes), capped.
  final double debtAfterMinutes;

  /// Bed/wake regularity 0..100, null without history.
  final double? consistency;
  final double? efficiency;
  final Map<SleepStage, double> stageMinutes;
  final DateTime? bedTime;
  final DateTime? wakeTime;
  final bool hasData;

  /// [ours] How need was built: baseline + debt share + strain boost.
  final SleepNeedBreakdown? needBreakdown;

  bool get hasStageData =>
      (stageMinutes[SleepStage.unknown] ?? 0) == 0 &&
      stageMinutes.entries.any((e) => e.key.isAsleep && e.value > 0);

  double get restorativeMinutes =>
      (stageMinutes[SleepStage.deep] ?? 0) +
      (stageMinutes[SleepStage.rem] ?? 0);

  Map<String, dynamic> toJson() => {
    'sleptMinutes': sleptMinutes,
    'napMinutes': napMinutes,
    'needMinutes': needMinutes,
    'performance': performance,
    'debtAfterMinutes': debtAfterMinutes,
    if (consistency != null) 'consistency': consistency,
    if (efficiency != null) 'efficiency': efficiency,
    'stageMinutes': {for (final e in stageMinutes.entries) e.key.name: e.value},
    if (bedTime != null) 'bedTime': _ts(bedTime),
    if (wakeTime != null) 'wakeTime': _ts(wakeTime),
    'hasData': hasData,
    if (needBreakdown != null) 'needBreakdown': needBreakdown!.toJson(),
  };
  factory SleepAnalysis.fromJson(Map<String, dynamic> j) => SleepAnalysis(
    sleptMinutes: (j['sleptMinutes'] as num).toDouble(),
    napMinutes: (j['napMinutes'] as num).toDouble(),
    needMinutes: (j['needMinutes'] as num).toDouble(),
    performance: (j['performance'] as num).toDouble(),
    debtAfterMinutes: (j['debtAfterMinutes'] as num).toDouble(),
    consistency: _d(j['consistency']),
    efficiency: _d(j['efficiency']),
    stageMinutes: {
      for (final e in ((j['stageMinutes'] as Map?) ?? const {}).entries)
        SleepStage.values.byName(e.key as String): (e.value as num).toDouble(),
    },
    bedTime: _t(j['bedTime']),
    wakeTime: _t(j['wakeTime']),
    hasData: j['hasData'] as bool,
    needBreakdown: j['needBreakdown'] == null
        ? null
        : SleepNeedBreakdown.fromJson(
            j['needBreakdown'] as Map<String, dynamic>,
          ),
  );
}

class SleepNeedBreakdown {
  const SleepNeedBreakdown({
    required this.baselineMinutes,
    required this.debtMinutes,
    required this.strainMinutes,
  });
  final double baselineMinutes;
  final double debtMinutes;
  final double strainMinutes;

  Map<String, dynamic> toJson() => {
    'baselineMinutes': baselineMinutes,
    'debtMinutes': debtMinutes,
    'strainMinutes': strainMinutes,
  };
  factory SleepNeedBreakdown.fromJson(Map<String, dynamic> j) =>
      SleepNeedBreakdown(
        baselineMinutes: (j['baselineMinutes'] as num).toDouble(),
        debtMinutes: (j['debtMinutes'] as num).toDouble(),
        strainMinutes: (j['strainMinutes'] as num).toDouble(),
      );
}

/// Recommendation for the coming night. [Pulse]
class BedtimeRecommendation {
  const BedtimeRecommendation({
    required this.projectedNeedMinutes,
    required this.debtMinutes,
    this.habitualWakeMinutes,
    this.recommendedBedtimeMinutes,
  });
  final double projectedNeedMinutes;

  /// Minutes since local midnight.
  final double? habitualWakeMinutes;

  /// Minutes since local midnight (may be negative = previous evening, or
  /// > 1440; normalise when displaying).
  final double? recommendedBedtimeMinutes;
  final double debtMinutes;

  Map<String, dynamic> toJson() => {
    'projectedNeedMinutes': projectedNeedMinutes,
    'debtMinutes': debtMinutes,
    if (habitualWakeMinutes != null) 'habitualWakeMinutes': habitualWakeMinutes,
    if (recommendedBedtimeMinutes != null)
      'recommendedBedtimeMinutes': recommendedBedtimeMinutes,
  };
  factory BedtimeRecommendation.fromJson(Map<String, dynamic> j) =>
      BedtimeRecommendation(
        projectedNeedMinutes: (j['projectedNeedMinutes'] as num).toDouble(),
        debtMinutes: (j['debtMinutes'] as num).toDouble(),
        habitualWakeMinutes: _d(j['habitualWakeMinutes']),
        recommendedBedtimeMinutes: _d(j['recommendedBedtimeMinutes']),
      );
}

// ── Health Monitor ───────────────────────────────────────────────────────

enum BandState { inRange, above, below, noData, calibrating }

enum HealthMetricKind {
  restingHr('Resting HR', 'bpm'),
  hrv('HRV', 'ms'),
  respiratoryRate('Respiratory rate', '/min'),
  spo2('SpO₂', '%'),
  skinTemp('Skin temp', '°C');

  const HealthMetricKind(this.label, this.unit);

  /// The engine's short name. Coach refs and the verifier read it, so the
  /// UI uses [title] and [plainName] instead (docs/COPY_REVIEW.md §2).
  final String label;
  final String unit;

  /// The name on tiles, chips and sheet titles: "Breathing rate".
  String get title => switch (this) {
    restingHr => 'Resting HR',
    hrv => 'HRV',
    respiratoryRate => 'Breathing rate',
    spo2 => 'Blood oxygen',
    skinTemp => 'Skin temperature',
  };

  /// The name inside a sentence: "your resting heart rate".
  String get plainName => switch (this) {
    restingHr => 'resting heart rate',
    hrv => 'HRV',
    respiratoryRate => 'breathing rate',
    spo2 => 'blood oxygen',
    skinTemp => 'skin temperature',
  };

  /// The unit as sentences write it: "breaths/min" for breathing rate.
  String get displayUnit => this == respiratoryRate ? 'breaths/min' : unit;
}

class HealthMetricStatus {
  const HealthMetricStatus({
    required this.kind,
    required this.state,
    this.value,
    this.baseline,
    this.lower,
    this.upper,
    this.provenance,
  });
  final HealthMetricKind kind;
  final BandState state;
  final double? value;
  final Baseline? baseline;
  final double? lower;
  final double? upper;
  final Provenance? provenance; // [ours]

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'state': state.name,
    if (value != null) 'value': value,
    if (baseline != null) 'baseline': baseline!.toJson(),
    if (lower != null) 'lower': lower,
    if (upper != null) 'upper': upper,
    if (provenance != null) 'provenance': provenance!.toJson(),
  };
  factory HealthMetricStatus.fromJson(Map<String, dynamic> j) =>
      HealthMetricStatus(
        kind: HealthMetricKind.values.byName(j['kind'] as String),
        state: BandState.values.byName(j['state'] as String),
        value: _d(j['value']),
        baseline: _bl(j['baseline']),
        lower: _d(j['lower']),
        upper: _d(j['upper']),
        provenance: j['provenance'] == null
            ? null
            : Provenance.fromJson(j['provenance'] as Map<String, dynamic>),
      );
}

class HealthMonitorResult {
  const HealthMonitorResult({
    required this.metrics,
    required this.alert,
    this.alertReason,
  });
  final List<HealthMetricStatus> metrics;

  /// True if ≥2 metrics are out of range today, or 1 metric for ≥2 days.
  final bool alert;
  final String? alertReason;

  int get outOfRange => metrics
      .where((m) => m.state == BandState.above || m.state == BandState.below)
      .length;

  Map<String, dynamic> toJson() => {
    'metrics': metrics.map((m) => m.toJson()).toList(),
    'alert': alert,
    if (alertReason != null) 'alertReason': alertReason,
  };
  factory HealthMonitorResult.fromJson(Map<String, dynamic> j) =>
      HealthMonitorResult(
        metrics: (j['metrics'] as List)
            .map((e) => HealthMetricStatus.fromJson(e as Map<String, dynamic>))
            .toList(),
        alert: j['alert'] as bool,
        alertReason: j['alertReason'] as String?,
      );
}

// ── Pulse Age (v2 feature, computed when inputs allow) ───────────────────

enum AgeComponentKind { equivalent, adjustment }

class AgeComponent {
  const AgeComponent({
    required this.key,
    required this.label,
    required this.detail,
    required this.deltaYears,
    required this.kind,
  });
  final String key;
  final String label;
  final String detail;
  final double deltaYears;
  final AgeComponentKind kind;

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'detail': detail,
    'deltaYears': deltaYears,
    'kind': kind.name,
  };
  factory AgeComponent.fromJson(Map<String, dynamic> j) => AgeComponent(
    key: j['key'] as String,
    label: j['label'] as String,
    detail: j['detail'] as String,
    deltaYears: (j['deltaYears'] as num).toDouble(),
    kind: AgeComponentKind.values.byName(j['kind'] as String),
  );
}

class PulseAgeResult {
  const PulseAgeResult({
    required this.chronoAge,
    required this.components,
    required this.calibrating,
    required this.calibrationHave,
    required this.calibrationNeed,
    this.pulseAge,
    this.vo2max,
    this.vo2maxEstimated = false,
    this.fitnessAge,
  });
  final int chronoAge;
  final double? pulseAge;
  final List<AgeComponent> components;
  final double? vo2max;
  final bool vo2maxEstimated;
  final double? fitnessAge;
  final bool calibrating;
  final int calibrationHave;
  final int calibrationNeed;

  double? get deltaYears => pulseAge == null ? null : pulseAge! - chronoAge;

  Map<String, dynamic> toJson() => {
    'chronoAge': chronoAge,
    if (pulseAge != null) 'pulseAge': pulseAge,
    'components': components.map((c) => c.toJson()).toList(),
    if (vo2max != null) 'vo2max': vo2max,
    'vo2maxEstimated': vo2maxEstimated,
    if (fitnessAge != null) 'fitnessAge': fitnessAge,
    'calibrating': calibrating,
    'calibrationHave': calibrationHave,
    'calibrationNeed': calibrationNeed,
  };
  factory PulseAgeResult.fromJson(Map<String, dynamic> j) => PulseAgeResult(
    chronoAge: j['chronoAge'] as int,
    pulseAge: _d(j['pulseAge']),
    components: (j['components'] as List)
        .map((e) => AgeComponent.fromJson(e as Map<String, dynamic>))
        .toList(),
    vo2max: _d(j['vo2max']),
    vo2maxEstimated: j['vo2maxEstimated'] as bool? ?? false,
    fitnessAge: _d(j['fitnessAge']),
    calibrating: j['calibrating'] as bool,
    calibrationHave: j['calibrationHave'] as int,
    calibrationNeed: j['calibrationNeed'] as int,
  );
}

// ── The day ──────────────────────────────────────────────────────────────

/// [ours] A key metric (HRV or resting HR) recently changed app, device or
/// definition, so its baseline is re-learning ("New source: re-learning your
/// normal"). Set while the new segment has fewer nights than the
/// calibration window.
class SourceChange {
  const SourceChange({
    required this.metric,
    required this.nights,
    this.from,
    this.to,
  });

  /// Metric.code ('hrv' | 'rhr'). For 'rhr', [to] may be a sleeping-HR
  /// provenance (`hc_sleep_hr_4h_mean@<app>`) when sleeping HR stands in for
  /// resting HR after a switch to an app that never shares it; [nights] is
  /// then that segment's.
  final String metric;
  final Provenance? from;
  final Provenance? to;

  /// Nights already in the new segment, before this day.
  final int nights;

  Map<String, dynamic> toJson() => {
    'metric': metric,
    'nights': nights,
    if (from != null) 'from': from!.toJson(),
    if (to != null) 'to': to!.toJson(),
  };
  factory SourceChange.fromJson(Map<String, dynamic> j) => SourceChange(
    metric: j['metric'] as String,
    nights: j['nights'] as int,
    from: j['from'] == null
        ? null
        : Provenance.fromJson(j['from'] as Map<String, dynamic>),
    to: j['to'] == null
        ? null
        : Provenance.fromJson(j['to'] as Map<String, dynamic>),
  );
}

class DayResult {
  const DayResult({
    required this.date,
    required this.algoVersion,
    required this.computedAt,
    required this.health,
    required this.calibration,
    this.recovery,
    this.strain,
    this.sleep,
    this.bedtime,
    this.readiness,
    this.pulseAge,
    this.notes = const [],
    this.sourceChange,
    this.notShared = const {},
  });

  final String date;
  final int algoVersion;
  final DateTime computedAt;

  /// Null = not enough input; the UI shows the matching StatusNote instead.
  final RecoveryResult? recovery;
  final StrainResult? strain;
  final SleepAnalysis? sleep;
  final BedtimeRecommendation? bedtime;
  final HealthMonitorResult health;
  final ReadinessSwc? readiness;
  final PulseAgeResult? pulseAge;
  final Calibration calibration;

  /// Honesty cards: what is missing, why, how to fix.
  final List<StatusNote> notes;

  /// [ours] See [SourceChange]; null when no key metric is re-learning.
  final SourceChange? sourceChange;

  /// [ours] Inputs today's source app doesn't share with Health Connect
  /// (it wrote other nightly data for several nights, never this): Metric
  /// code → the app's display name, e.g. {'hrv': 'WHOOP'} or
  /// {'hrv': 'Samsung Health', 'rhr': 'Samsung Health'}. Wearing the
  /// tracker won't fill these; another app might.
  final Map<String, String> notShared;

  Map<String, dynamic> toJson() => {
    'date': date,
    'algoVersion': algoVersion,
    'computedAt': _ts(computedAt),
    if (recovery != null) 'recovery': recovery!.toJson(),
    if (strain != null) 'strain': strain!.toJson(),
    if (sleep != null) 'sleep': sleep!.toJson(),
    if (bedtime != null) 'bedtime': bedtime!.toJson(),
    'health': health.toJson(),
    if (readiness != null) 'readiness': readiness!.toJson(),
    if (pulseAge != null) 'pulseAge': pulseAge!.toJson(),
    'calibration': calibration.toJson(),
    'notes': notes.map((n) => n.toJson()).toList(),
    if (sourceChange != null) 'sourceChange': sourceChange!.toJson(),
    if (notShared.isNotEmpty) 'notShared': notShared,
  };

  factory DayResult.fromJson(Map<String, dynamic> j) => DayResult(
    date: j['date'] as String,
    algoVersion: j['algoVersion'] as int,
    computedAt: _t(j['computedAt'])!,
    recovery: j['recovery'] == null
        ? null
        : RecoveryResult.fromJson(j['recovery'] as Map<String, dynamic>),
    strain: j['strain'] == null
        ? null
        : StrainResult.fromJson(j['strain'] as Map<String, dynamic>),
    sleep: j['sleep'] == null
        ? null
        : SleepAnalysis.fromJson(j['sleep'] as Map<String, dynamic>),
    bedtime: j['bedtime'] == null
        ? null
        : BedtimeRecommendation.fromJson(j['bedtime'] as Map<String, dynamic>),
    health: HealthMonitorResult.fromJson(j['health'] as Map<String, dynamic>),
    readiness: j['readiness'] == null
        ? null
        : ReadinessSwc.fromJson(j['readiness'] as Map<String, dynamic>),
    pulseAge: j['pulseAge'] == null
        ? null
        : PulseAgeResult.fromJson(j['pulseAge'] as Map<String, dynamic>),
    calibration: Calibration.fromJson(j['calibration'] as Map<String, dynamic>),
    notes: (j['notes'] as List? ?? const [])
        .map((e) => StatusNote.fromJson(e as Map<String, dynamic>))
        .toList(),
    sourceChange: j['sourceChange'] == null
        ? null
        : SourceChange.fromJson(j['sourceChange'] as Map<String, dynamic>),
    notShared: {
      for (final e in ((j['notShared'] as Map?) ?? const {}).entries)
        e.key as String: e.value as String,
    },
  );
}

// ── Journal insights (Pulse JournalEngine: WHOOP-style ≥5 / ≥5 days) ──────

enum InsightConfidence {
  /// Significant after Holm correction across the factors tested (Welch t,
  /// α = 0.05). [since algo v2; Pulse used |delta| > 2·SE]
  solid,

  /// Minimum group sizes reached, but the difference is within noise.
  emerging,
}

class FactorInsight {
  const FactorInsight({
    required this.factor,
    required this.avgWith,
    required this.avgWithout,
    required this.delta,
    required this.standardError,
    required this.confidence,
    required this.daysWith,
    required this.daysWithout,
    this.ciLow,
    this.ciHigh,
    this.pValue,
  });
  final JournalFactor factor;

  /// Mean NEXT-day recovery on days with / without the factor.
  final double avgWith;
  final double avgWithout;

  /// Recovery points (negative = factor lowers next-day recovery).
  final double delta;
  final double standardError;
  final InsightConfidence confidence;
  final int daysWith;
  final int daysWithout;

  /// [ours] 95 % confidence interval of [delta] (Welch t), recovery points.
  final double? ciLow;
  final double? ciHigh;

  /// [ours] Two-sided Welch p-value BEFORE the Holm correction.
  final double? pValue;
}

// ── Training load (ACWR) and trends [ours] ────────────────────────────────

enum LoadState { detraining, optimal, elevated, high }

class TrainingLoad {
  const TrainingLoad({
    required this.acute7,
    required this.chronic28,
    required this.ratio,
    required this.state,
    required this.daysOfHistory,
  });

  /// Mean daily strain, last 7 days / last 28 days.
  final double acute7;
  final double chronic28;

  /// Acute / chronic recorded effort. Legacy state names are bucket labels,
  /// not validated predictions of fitness, injury risk or optimal training.
  final double ratio;
  final LoadState state;
  final int daysOfHistory;
}

enum TrendDirection { up, down, flat }

/// Trend arrows are shown ONLY when [significant] (Edge's honesty rule).
class TrendResult {
  const TrendResult({
    required this.direction,
    required this.slopePerDay,
    required this.significant,
    required this.n,
    this.recentMean,
    this.priorMean,
  });
  final TrendDirection direction;
  final double slopePerDay;

  /// Mann-Kendall (or OLS slope) test at p < 0.05.
  final bool significant;
  final int n;
  final double? recentMean;
  final double? priorMean;
}
