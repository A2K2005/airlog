// Domain inputs: what the data layer hands the engine for one calendar day.
//
// CONTRACT FILE — shared by domain/, data/ and features/. Additive changes only:
// never rename or remove a field without updating every owner (see
// ARCHITECTURE.md). Pure Dart: no Flutter or plugin imports allowed here.
//
// Shapes follow Pulse's Core/Models/Models.swift (Apache-2.0, see
// third_party/pulse/NOTICE) with two additions of ours:
//   * every metric carries PROVENANCE (which source, which definition), and
//   * the engine keys baselines on that definition, so switching a metric's
//     source starts a new baseline segment instead of mixing definitions.

import 'day_key.dart';

/// Where a raw datum came from. Every stored row carries one.
enum SourceKind {
  healthConnect('hc', 'Health Connect'),
  googleHealthApi('ghapi', 'Google Health API'),
  ble('ble', 'Bluetooth HR'),
  takeout('takeout', 'Google Takeout'),
  context('context', 'Other apps'),
  demo('demo', 'Demo data');

  const SourceKind(this.code, this.label);
  final String code;
  final String label;

  static SourceKind fromCode(String c) =>
      values.firstWhere((s) => s.code == c, orElse: () => SourceKind.demo);
}

/// The metrics the resolver picks ONE source for (never averaged).
enum Metric {
  hr('hr'),
  hrv('hrv'),
  restingHr('rhr'),
  respiratoryRate('resp'),
  spo2('spo2'),
  skinTemp('skin_temp'),
  vo2max('vo2max'),
  sleep('sleep'),
  workouts('workouts'),
  steps('steps'),
  weight('weight'),

  /// [additive 2026-09-29, HRV ladder S1] Mean heart rate of the first 4 h
  /// of the main sleep (from 30 min after sleep start), from the sleep's own
  /// app. NEVER resting HR: its own definition, baseline and label. Used by
  /// Recovery only when the app never shares resting HR (research/09b §3).
  sleepingHr('sleep_hr');

  const Metric(this.code);
  final String code;

  static Metric fromCode(String c) => values.firstWhere((m) => m.code == c);
}

/// Provenance of one metric on one day.
///
/// [definition] identifies HOW the value was derived, e.g.
///   hrv: 'hc_sleep_mean_rmssd'  (mean of HC RMSSD samples inside main sleep)
///   hrv: 'ghapi_deep_sleep_rmssd'
///   rhr: 'hc_daily_rhr'
/// Baselines only compare days with the same definition.
class Provenance {
  const Provenance(this.source, this.definition, {this.device, this.origin});
  final SourceKind source;
  final String definition;

  /// Health Connect origin package the value came from (e.g.
  /// 'com.sec.android.app.shealth'); null for non-HC sources. Baselines are
  /// keyed on [baselineKey], so a change of app starts a new segment.
  final String? origin;

  /// "definition@origin#device"; the origin and device parts only when
  /// known. The engine (engine/baselines.dart Segment) compares these parts;
  /// an unknown device never splits a segment, since device metadata is
  /// not always present (e.g. background reads).
  String get baselineKey =>
      '$definition${origin == null ? '' : '@$origin'}'
      '${device == null ? '' : '#$device'}';

  /// Device name from record metadata, e.g. "Fitbit Air" (null if unknown).
  final String? device;

  /// Short human label for the UI: "Deep-sleep RMSSD · Google Health API".
  String get label => '${_pretty(definition)} · ${source.label}';

  static String _pretty(String d) {
    final parts = d.split('_');
    if (parts.length > 1 &&
        const {
          'hc',
          'ghapi',
          'ble',
          'takeout',
          'context',
          'demo',
        }.contains(parts.first)) {
      parts.removeAt(0);
    }
    final s = parts.join(' ');
    return s.isEmpty ? d : s[0].toUpperCase() + s.substring(1);
  }

  Map<String, dynamic> toJson() => {
    'source': source.code,
    'definition': definition,
    if (device != null) 'device': device,
    if (origin != null) 'origin': origin,
  };

  factory Provenance.fromJson(Map<String, dynamic> j) => Provenance(
    SourceKind.fromCode(j['source'] as String),
    j['definition'] as String,
    device: j['device'] as String?,
    origin: j['origin'] as String?,
  );

  /// Same measurement from the same app ([device] is descriptive only).
  @override
  bool operator ==(Object other) =>
      other is Provenance &&
      other.source == source &&
      other.definition == definition &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(source, definition, origin);
}

// ── Sleep ────────────────────────────────────────────────────────────────

enum SleepStage {
  awake,
  light,
  deep,
  rem,
  unknown;

  bool get isAsleep => this == light || this == deep || this == rem;
}

class StageSpan {
  const StageSpan(this.stage, this.start, this.end);
  final SleepStage stage;
  final DateTime start;
  final DateTime end;

  double get minutes {
    final m = end.difference(start).inSeconds / 60.0;
    return m < 0 ? 0 : m;
  }

  Map<String, dynamic> toJson() => {
    'stage': stage.name,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
  };

  factory StageSpan.fromJson(Map<String, dynamic> j) => StageSpan(
    SleepStage.values.byName(j['stage'] as String),
    DateTime.parse(j['start'] as String).toLocal(),
    DateTime.parse(j['end'] as String).toLocal(),
  );
}

class SleepSession {
  const SleepSession({
    required this.id,
    required this.start,
    required this.end,
    required this.minutesAsleep,
    required this.minutesAwake,
    this.stages = const [],
    this.isMainSleep = true,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final double minutesAsleep;
  final double minutesAwake;
  final List<StageSpan> stages;
  final bool isMainSleep;

  double get minutesInBed {
    final m = end.difference(start).inSeconds / 60.0;
    return m < 0 ? 0 : m;
  }

  /// Sleep efficiency in percent (asleep / in bed), null when in-bed is 0.
  double? get efficiency {
    final bed = minutesInBed;
    if (bed <= 0) return null;
    final e = minutesAsleep / bed * 100;
    return e > 100 ? 100 : e;
  }

  double minutesIn(SleepStage s) =>
      stages.where((x) => x.stage == s).fold(0.0, (a, x) => a + x.minutes);

  Map<SleepStage, double> get stageMinutes {
    final out = <SleepStage, double>{};
    for (final s in stages) {
      out[s.stage] = (out[s.stage] ?? 0) + s.minutes;
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    'minutesAsleep': minutesAsleep,
    'minutesAwake': minutesAwake,
    'stages': stages.map((s) => s.toJson()).toList(),
    'isMainSleep': isMainSleep,
  };

  factory SleepSession.fromJson(Map<String, dynamic> j) => SleepSession(
    id: j['id'] as String,
    start: DateTime.parse(j['start'] as String).toLocal(),
    end: DateTime.parse(j['end'] as String).toLocal(),
    minutesAsleep: (j['minutesAsleep'] as num).toDouble(),
    minutesAwake: (j['minutesAwake'] as num).toDouble(),
    stages: (j['stages'] as List? ?? const [])
        .map((e) => StageSpan.fromJson(e as Map<String, dynamic>))
        .toList(),
    isMainSleep: j['isMainSleep'] as bool? ?? true,
  );
}

// ── Heart rate / HRV ─────────────────────────────────────────────────────

class HrSample {
  const HrSample(this.t, this.bpm);
  final DateTime t;
  final double bpm;

  Map<String, dynamic> toJson() => {
    't': t.toUtc().toIso8601String(),
    'bpm': bpm,
  };
  factory HrSample.fromJson(Map<String, dynamic> j) => HrSample(
    DateTime.parse(j['t'] as String).toLocal(),
    (j['bpm'] as num).toDouble(),
  );
}

/// One HRV record (Health Connect writes roughly one RMSSD value per ~5 min
/// of sleep; community observation, unverified for the Air).
class HrvSample {
  const HrvSample(this.t, this.rmssdMs);
  final DateTime t;
  final double rmssdMs;

  Map<String, dynamic> toJson() => {
    't': t.toUtc().toIso8601String(),
    'rmssd': rmssdMs,
  };
  factory HrvSample.fromJson(Map<String, dynamic> j) => HrvSample(
    DateTime.parse(j['t'] as String).toLocal(),
    (j['rmssd'] as num).toDouble(),
  );
}

// ── Workouts ─────────────────────────────────────────────────────────────

class Workout {
  const Workout({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.averageHr,
    this.calories,
    this.distanceM,
  });

  final String id;

  /// Human label, e.g. "Run", "Strength training".
  final String name;
  final DateTime start;
  final DateTime end;
  final double? averageHr;
  final double? calories;
  final double? distanceM;

  double get durationMinutes {
    final m = end.difference(start).inSeconds / 60.0;
    return m < 0 ? 0 : m;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    if (averageHr != null) 'averageHr': averageHr,
    if (calories != null) 'calories': calories,
    if (distanceM != null) 'distanceM': distanceM,
  };

  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
    id: j['id'] as String,
    name: j['name'] as String,
    start: DateTime.parse(j['start'] as String).toLocal(),
    end: DateTime.parse(j['end'] as String).toLocal(),
    averageHr: (j['averageHr'] as num?)?.toDouble(),
    calories: (j['calories'] as num?)?.toDouble(),
    distanceM: (j['distanceM'] as num?)?.toDouble(),
  );
}

// ── Profile ──────────────────────────────────────────────────────────────

/// Needed because age norms (VO2 max, HRV, resting HR) and max HR are
/// sex- and age-specific. `unspecified` uses averaged curves.
enum Sex { male, female, unspecified }

class UserProfile {
  const UserProfile({
    this.birthYear,
    this.sex = Sex.unspecified,
    this.maxHrOverride,
    this.weightKg,
  });

  final int? birthYear;
  final Sex sex;

  /// If set, replaces the age-predicted max HR in strain zones.
  final double? maxHrOverride;
  final double? weightKg;

  /// Age in whole years at [now]; defaults to 30 when unknown (Pulse default).
  int ageAt(DateTime now) =>
      birthYear == null ? 30 : (now.year - birthYear!).clamp(10, 100);

  bool get hasAge => birthYear != null;

  UserProfile copyWith({
    int? birthYear,
    Sex? sex,
    double? maxHrOverride,
    double? weightKg,
    bool clearMaxHr = false,
  }) => UserProfile(
    birthYear: birthYear ?? this.birthYear,
    sex: sex ?? this.sex,
    maxHrOverride: clearMaxHr ? null : (maxHrOverride ?? this.maxHrOverride),
    weightKg: weightKg ?? this.weightKg,
  );

  Map<String, dynamic> toJson() => {
    if (birthYear != null) 'birthYear': birthYear,
    'sex': sex.name,
    if (maxHrOverride != null) 'maxHrOverride': maxHrOverride,
    if (weightKg != null) 'weightKg': weightKg,
  };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    birthYear: j['birthYear'] as int?,
    sex: Sex.values.byName(j['sex'] as String? ?? 'unspecified'),
    maxHrOverride: (j['maxHrOverride'] as num?)?.toDouble(),
    weightKg: (j['weightKg'] as num?)?.toDouble(),
  );
}

// ── The per-day input record ─────────────────────────────────────────────

/// Everything the engine needs for one calendar day, already RESOLVED by the
/// data layer (one source per metric). Nightly values belong to the wake day.
class DayRecord {
  DayRecord({
    required this.date,
    this.hrvRmssd,
    this.restingHr,
    this.respiratoryRate,
    this.spo2Avg,
    this.spo2Min,
    this.skinTempDelta,
    this.vo2max,
    this.steps,
    this.weightKg,
    this.sleepingHr4h,
    List<SleepSession>? sleepSessions,
    List<Workout>? workouts,
    List<HrSample>? hrSamples,
    List<HrvSample>? hrvSamples,
    Map<Metric, Provenance>? provenance,
    this.lastDataAt,
  }) : sleepSessions = sleepSessions ?? [],
       workouts = workouts ?? [],
       hrSamples = hrSamples ?? [],
       hrvSamples = hrvSamples ?? [],
       provenance = provenance ?? {};

  /// "yyyy-MM-dd" (see DayKey).
  final String date;

  // Nightly recovery inputs.
  double? hrvRmssd; // ms, one nightly value (definition in provenance)
  double? restingHr; // bpm
  double? respiratoryRate; // breaths/min
  double? spo2Avg; // % (Google Health API only)
  double? spo2Min; // %
  /// Skin temperature deviation from the device's own baseline, °C.
  /// Health Connect's SkinTemperatureRecord is a delta; the engine treats it
  /// as a delta too (Pulse used absolute body temp; same band logic).
  double? skinTempDelta;
  double? vo2max; // ml/kg/min

  // Activity.
  int? steps;
  double? weightKg; // context source (smart scale)

  /// [additive 2026-09-29] Sleeping HR (4 h mean), bpm; see
  /// Metric.sleepingHr. Never copied into [restingHr].
  double? sleepingHr4h;
  final List<SleepSession> sleepSessions;
  final List<Workout> workouts;

  /// Intraday HR, downsampled to 1-minute resolution, oldest first.
  final List<HrSample> hrSamples;

  /// Raw HRV records for the night (diagnostics / future Energy gauge).
  final List<HrvSample> hrvSamples;

  /// Which source + definition produced each metric today.
  final Map<Metric, Provenance> provenance;

  /// Newest timestamp of any raw datum on this day (freshness line).
  DateTime? lastDataAt;

  DateTime get startOfDay => DayKey.start(date);

  /// Main sleep = the session flagged as such, otherwise the longest.
  SleepSession? get mainSleep {
    for (final s in sleepSessions) {
      if (s.isMainSleep) return s;
    }
    if (sleepSessions.isEmpty) return null;
    return sleepSessions.reduce(
      (a, b) => a.minutesAsleep >= b.minutesAsleep ? a : b,
    );
  }

  List<SleepSession> get naps {
    final m = mainSleep;
    if (m == null) return const [];
    return sleepSessions.where((s) => s.id != m.id).toList();
  }

  double get totalSleepMinutes =>
      sleepSessions.fold(0.0, (a, s) => a + s.minutesAsleep);

  /// Definition string for [m] today, or null if the metric is absent.
  String? definitionOf(Metric m) => provenance[m]?.definition;

  Map<String, dynamic> toJson() => {
    'date': date,
    if (hrvRmssd != null) 'hrvRmssd': hrvRmssd,
    if (restingHr != null) 'restingHr': restingHr,
    if (respiratoryRate != null) 'respiratoryRate': respiratoryRate,
    if (spo2Avg != null) 'spo2Avg': spo2Avg,
    if (spo2Min != null) 'spo2Min': spo2Min,
    if (skinTempDelta != null) 'skinTempDelta': skinTempDelta,
    if (vo2max != null) 'vo2max': vo2max,
    if (steps != null) 'steps': steps,
    if (weightKg != null) 'weightKg': weightKg,
    if (sleepingHr4h != null) 'sleepingHr4h': sleepingHr4h,
    'sleepSessions': sleepSessions.map((s) => s.toJson()).toList(),
    'workouts': workouts.map((w) => w.toJson()).toList(),
    'hrSamples': hrSamples.map((s) => s.toJson()).toList(),
    'hrvSamples': hrvSamples.map((s) => s.toJson()).toList(),
    'provenance': {
      for (final e in provenance.entries) e.key.code: e.value.toJson(),
    },
    if (lastDataAt != null) 'lastDataAt': lastDataAt!.toUtc().toIso8601String(),
  };

  factory DayRecord.fromJson(Map<String, dynamic> j) => DayRecord(
    date: j['date'] as String,
    hrvRmssd: (j['hrvRmssd'] as num?)?.toDouble(),
    restingHr: (j['restingHr'] as num?)?.toDouble(),
    respiratoryRate: (j['respiratoryRate'] as num?)?.toDouble(),
    spo2Avg: (j['spo2Avg'] as num?)?.toDouble(),
    spo2Min: (j['spo2Min'] as num?)?.toDouble(),
    skinTempDelta: (j['skinTempDelta'] as num?)?.toDouble(),
    vo2max: (j['vo2max'] as num?)?.toDouble(),
    steps: j['steps'] as int?,
    weightKg: (j['weightKg'] as num?)?.toDouble(),
    sleepingHr4h: (j['sleepingHr4h'] as num?)?.toDouble(),
    sleepSessions: (j['sleepSessions'] as List? ?? const [])
        .map((e) => SleepSession.fromJson(e as Map<String, dynamic>))
        .toList(),
    workouts: (j['workouts'] as List? ?? const [])
        .map((e) => Workout.fromJson(e as Map<String, dynamic>))
        .toList(),
    hrSamples: (j['hrSamples'] as List? ?? const [])
        .map((e) => HrSample.fromJson(e as Map<String, dynamic>))
        .toList(),
    hrvSamples: (j['hrvSamples'] as List? ?? const [])
        .map((e) => HrvSample.fromJson(e as Map<String, dynamic>))
        .toList(),
    provenance: {
      for (final e in ((j['provenance'] as Map?) ?? const {}).entries)
        Metric.fromCode(e.key as String): Provenance.fromJson(
          e.value as Map<String, dynamic>,
        ),
    },
    lastDataAt: j['lastDataAt'] == null
        ? null
        : DateTime.parse(j['lastDataAt'] as String).toLocal(),
  );
}

// ── Journal (behaviour tags, from Pulse Core/Models/Journal.swift) ─────────

/// A fixed, small list (no free-text sprawl) so correlations stay robust.
enum JournalFactor {
  alcohol('Alcohol'),
  lateCaffeine('Late caffeine'),
  lateMeal('Late meal'),
  stress('Stress'),
  sick('Feeling sick'),
  screenBeforeBed('Screens before bed'),
  exercised('Trained'),
  travel('Travel'),
  meditation('Meditation');

  const JournalFactor(this.label);
  final String label;
}

/// Which factors applied on [date] (the evening before the next recovery).
class JournalEntry {
  const JournalEntry({required this.date, this.factors = const {}});
  final String date;
  final Set<JournalFactor> factors;

  JournalEntry toggle(JournalFactor f) => JournalEntry(
    date: date,
    factors: factors.contains(f) ? ({...factors}..remove(f)) : {...factors, f},
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'factors': factors.map((f) => f.name).toList()..sort(),
  };

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
    date: j['date'] as String,
    factors: {
      for (final n in (j['factors'] as List? ?? const []))
        JournalFactor.values.byName(n as String),
    },
  );
}
