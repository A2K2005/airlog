// "How am I + what to do": the app's one job (user decision 2026-09-29,
// PRODUCT_PLAN decisions table).
//
// CONTRACT FILE (orchestrator): additive changes only, report them.
// Pure Dart. Built by TodayPlanner (domain/engine/today_planner.dart) from
// the day's DayBundle alone. It is deterministic: every sentence and number
// comes from a DayResult or DayRecord field, and nothing is estimated or
// invented. It is the ONLY narrator of the day's overall state. Insight cards
// on detail screens add detail and never restate the state in other words.

/// The day in plain words. Labels are UI copy (copy.dart owns final wording).
enum DayState {
  /// Recovery high and inputs fresh: "Your body is ready".
  ready,

  /// Around the user's baseline: "Good for a normal day".
  steady,

  /// Recovery low or a vital outside its band: "Take it easy today".
  easy,

  /// Recovery very low, or several vitals out: "Make today a rest day".
  rest,

  /// Baseline not established yet: "Still getting to know you".
  calibrating,

  /// No usable data for today, or it's stale: "Waiting for your data".
  noData,
}

/// Which inputs today's scores lack. Shown on Today, e.g. "without HRV".
enum InputGap { hrv, heartRate, sleep, respiratoryRate, skinTemp, spo2 }

/// Framing by time of day. After the evening cut-off, the plan speaks about
/// tonight (bedtime, sleep target, debt) instead of today's effort.
enum PlanPhase { today, tonight }

enum PlanActionKind {
  /// Effort guidance, with the strain range from StrainResult.targetStrain.
  effort,

  /// Bedtime or sleep-need guidance from BedtimeRecommendation or SleepAnalysis.
  sleep,

  /// Low-cost recovery habit tied to a measured signal.
  recover,

  /// Wear the band tonight, or keep it on (fills missing inputs).
  wear,

  /// Open the source app to sync (stale data).
  sync,

  /// A vital outside its band: notice how you feel. Fixed, non-diagnostic
  /// copy from the Health Monitor.
  checkIn,
}

/// One number the plan relies on, shown as a chip, e.g. ("HRV", "38 ms",
/// "−14% vs your usual").
class PlanEvidence {
  const PlanEvidence({
    required this.label,
    required this.value,
    this.comparison,
    this.route,
  });
  final String label;
  final String value;
  final String? comparison;

  /// Detail route opened on tap, e.g. '/recovery'.
  final String? route;
}

class PlanAction {
  const PlanAction({
    required this.kind,
    required this.title,
    required this.why,
    this.evidence = const [],
    this.route,
  });
  final PlanActionKind kind;

  /// Imperative and concrete, in words, e.g. "A normal workout is fine
  /// today".
  final String title;

  /// One plain sentence, e.g. "Try a steady run or bike ride, or your usual
  /// gym session."
  final String why;

  /// The numbers behind the action, shown as small chips under the why,
  /// e.g. ("Effort goal", "9–12", "3.1 so far").
  final List<PlanEvidence> evidence;
  final String? route;
}

class TodayPlan {
  const TodayPlan({
    required this.date,
    required this.state,
    required this.headline,
    required this.summary,
    this.evidence = const [],
    this.actions = const [],
    this.sources = const [],
    this.provisional = false,
    this.stale = false,
    this.missingInputs = const [],
    this.phase = PlanPhase.today,
    this.relearningSource,
    this.summaryNamesRelearning = false,
  });

  final String date;
  final DayState state;

  /// The plain-words answer, e.g. "Take it easy today".
  final String headline;

  /// One sentence of why, in words (the numbers are on the chips). While a
  /// new source re-learns and the plan would otherwise ask to wear the
  /// tracker, a second sentence says so instead ("Airlog is learning your
  /// Oura data: 2 of 14 nights so far.").
  final String summary;

  /// 1–2 headline numbers behind the state. Actions don't repeat them.
  final List<PlanEvidence> evidence;

  /// 0–3 actions, most important first. Empty is fine ("Nothing to change").
  /// Housekeeping (wear, sync) appears here only when it is the sole action;
  /// otherwise it belongs on the freshness line.
  final List<PlanAction> actions;

  /// Display names of the apps the inputs came from, e.g. ["Samsung Health"].
  final List<String> sources;

  /// Baseline still calibrating: scores are provisional.
  final bool provisional;

  /// Newest data older than the freshness threshold. When true, the plan
  /// gives no effort advice.
  final bool stale;

  /// The basis of today's scores. Non-empty means the UI labels them
  /// (e.g. "Recovery without HRV").
  final List<InputGap> missingInputs;

  final PlanPhase phase;

  /// Display name of an app that recently became a key metric's source.
  /// Set while its baseline re-learns ("Learning your Oura data").
  final String? relearningSource;

  /// [additive] The summary already names the re-learning source, so the
  /// UI doesn't tag it a second time.
  final bool summaryNamesRelearning;

  /// Result fields the plan may cite; the eval checks every number in the
  /// plan's text against them. The PLANNER OWNS THIS LIST: it must cover every
  /// field the rules read (recovery components and baselines, asleep minutes,
  /// strain so far, …), and it grows with the rules.
  static const citedResultFields = {
    'recovery.score',
    'recovery.zone',
    'recovery.withoutHrv',
    // HRV / resting HR value and its usual (baseline mean); the summary
    // may compare them: HRV |value ÷ usual − 1| in %.
    'recovery.components.value',
    'recovery.components.baseline',
    'strain.targetStrain', // and StrainEngine.targetRange(targetStrain)
    'strain.strain',
    'sleep.sleptMinutes',
    'sleep.needMinutes',
    'sleep.performance',
    'sleep.debtAfterMinutes',
    'bedtime.projectedNeedMinutes',
    'bedtime.debtMinutes',
    'bedtime.recommendedBedtimeMinutes',
    'bedtime.habitualWakeMinutes',
    'health.metrics', // value and baseline mean of each vital
    'calibration', // haveNights, needNights
    'sourceChange', // nights, and the new source's app name
    'notShared', // app names
    'record.lastDataAt', // or SyncStatus.lastDataAt
  };
}
