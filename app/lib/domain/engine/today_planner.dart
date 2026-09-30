// TodayPlanner: DayBundle → TodayPlan (domain/today_plan.dart). [ours]
//
// The app's one job, "How am I + what to do" (PRODUCT_PLAN §7: "The one
// job" and the product-critic review, 2026-09-29). TodayPlan is the ONLY
// narrator of the day: the old Today summary and alert cards are ported
// here. Pure Dart and deterministic: the same bundle, sync status and clock
// always give the same plan. Every number in the copy is a DayResult,
// DayRecord or SyncStatus field (TodayPlan.citedResultFields) printed
// through [PlanFormat], or one of these documented comparisons of two such
// fields: HRV % vs its usual, resting HR bpm vs its usual, and the effort
// range StrainEngine.targetRange(targetStrain). Nothing is estimated.
//
// Words first, numbers on the chips (docs/COPY_REVIEW.md §4.1): the
// headline, summary and action titles are plain sentences; the numbers
// behind them are the evidence chips, on the card and under each action.
//
// Freshness and time of day (explicit):
//   stale     no datum at all, or the newest datum (SyncStatus.lastDataAt,
//             else DayRecord.lastDataAt) is older than [staleAfter] (12 h: a
//             tracker that syncs normally writes heart rate every few hours,
//             so 12 h of silence means last night may not have arrived).
//   evening   eveningKeyOf(now): before 05:00 it is still yesterday evening.
//   behind    the bundle is older than the evening's day: nothing for today
//             has arrived yet.
//   beforeWake  00:00–05:00 with a bundle already dated the new day: its
//             scores come after the wake-up.
//   tonight   phase from [tonightFromHour] (18:00, the resolver's night cut:
//             data after it belongs to the coming night) to 05:00: the plan
//             talks about tonight (sleep goal, missed sleep, bedtime)
//             instead of today's effort.
//
// State (first match wins):
//   noData       behind, beforeWake, or no Recovery (no HRV and no RHR)
//   rest         ≥ 2 concerning vitals, or Recovery < [restBelow] (17, the
//                lower half of the red zone) once not calibrating
//   easy         1 concerning vital, or Recovery red (< 34) once not
//                calibrating
//   calibrating  Recovery or Calibration still calibrating (incl. a new
//                source re-learning its baseline)
//   ready        Recovery green (≥ 67) and not stale
//   steady       otherwise (yellow, or green with stale inputs)
// "Concerning" = HealthMonitor.isConcerning: outside the band in the
// unfavourable direction (HRV/SpO₂ low; RHR, respiratory rate, skin temp
// high). A vital outside its band the favourable way changes nothing.
//
// Actions, at most [maxActions], in this order:
//   today    effort (not stale, not calibrating; a level keyed on the state,
//            the goal range as a chip, progress words after a start), sleep
//            (bedtime or tonight's goal), checkIn (≥ 1 concerning vital;
//            fixed non-diagnostic copy), recover (easy or rest)
//   tonight  sleep, checkIn, recover (no effort)
//   Housekeeping (sync when stale or behind, else wear when inputs are
//   missing or calibrating) only when it would be the sole action;
//   otherwise the freshness line covers it. Never "wear" for an input the
//   source app doesn't share (DayResult.notShared), and never while a new
//   source re-learns (DayResult.sourceChange): wearing doesn't speed that
//   up, so the summary says "Airlog is learning your <app> data" instead.

import '../day_key.dart';
import '../models.dart';
import '../repositories.dart';
import '../results.dart';
import '../today_plan.dart';
import 'health_monitor.dart';
import 'inputs.dart';
import 'notes.dart';
import 'recovery.dart';
import 'source_apps.dart';
import 'strain.dart';

/// The one formatter for every number TodayPlan prints (the property test
/// builds its allowed numbers with it too).
abstract final class PlanFormat {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Recovery score: "72%".
  static String pct(int score) => '$score%';

  /// Minutes as "7h 36m", "8h" or "45 min" (the coach's duration style).
  static String hm(double minutes) {
    final t = minutes.isFinite && minutes > 0 ? minutes.round() : 0;
    final h = t ~/ 60, m = t % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// Minutes since local midnight (any value; normalised mod 1440) as
  /// "22:40", or "10:40 pm" when [use24h] is false (the phone's setting).
  static String clock(double minutesSinceMidnight, {bool use24h = true}) {
    final r = minutesSinceMidnight.isFinite ? minutesSinceMidnight.round() : 0;
    final t = (r % 1440 + 1440) % 1440;
    final h = t ~/ 60, m = (t % 60).toString().padLeft(2, '0');
    if (use24h) return '${h.toString().padLeft(2, '0')}:$m';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m ${h < 12 ? 'am' : 'pm'}';
  }

  /// Local clock time of [t]: "07:12" or "7:12 am".
  static String time(DateTime t, {bool use24h = true}) {
    final l = t.toLocal();
    return clock((l.hour * 60 + l.minute).toDouble(), use24h: use24h);
  }

  /// When [t] was, from [now]: "07:12", "yesterday 23:10", "Sep 26 23:10",
  /// or in 12-hour form "7:12 am", "yesterday, 11:10 pm", "Sep 26, 11:10 pm".
  static String when(DateTime t, DateTime now, {bool use24h = true}) {
    final day = DayKey.of(t), today = DayKey.of(now);
    final clock = time(t, use24h: use24h);
    final sep = use24h ? ' ' : ', ';
    if (day == today) return clock;
    if (day == DayKey.add(today, -1)) return 'yesterday$sep$clock';
    final l = t.toLocal();
    return '${_months[l.month - 1]} ${l.day}$sep$clock';
  }

  /// Strain, one decimal: "7.4".
  static String strain(double s) => s.toStringAsFixed(1);

  /// HRV in ms, rounded: "52 ms".
  static String ms(double v) => '${v.round()} ms';

  /// Heart rate in bpm, rounded: "54 bpm".
  static String bpm(double v) => '${v.round()} bpm';

  /// |value / usual − 1| in whole percent (HRV vs its usual).
  static int pctVsUsual(double value, double usual) =>
      ((value / usual - 1) * 100).abs().round();

  /// |value − usual| in whole bpm, from the rounded numbers the screens
  /// show (resting HR vs its usual: "54 vs 56" reads as 2 bpm).
  static int bpmVsUsual(double value, double usual) =>
      (value.round() - usual.round()).abs();

  /// A Health Monitor value without its unit.
  static String vitalNumber(HealthMetricKind k, double v) => switch (k) {
    HealthMetricKind.respiratoryRate => v.toStringAsFixed(1),
    HealthMetricKind.skinTemp =>
      '${v < 0 ? '−' : '+'}${v.abs().toStringAsFixed(1)}',
    _ => '${v.round()}',
  };

  static String unit(HealthMetricKind k) => switch (k) {
    HealthMetricKind.spo2 => '%',
    HealthMetricKind.skinTemp => ' °C',
    _ => ' ${k.displayUnit}',
  };

  /// A Health Monitor value with its unit: "16.8 breaths/min", "95%",
  /// "+0.4 °C".
  static String vital(HealthMetricKind k, double v) =>
      '${vitalNumber(k, v)}${unit(k)}';
}

/// The effort level Today's words use, keyed on the day's state (never on
/// the strain range: both sides of a zone edge give the same range, see
/// docs/COPY_REVIEW.md §4.1.6).
enum EffortLevel { rest, easy, moderate, hard, veryHard }

abstract final class TodayPlanner {
  /// Newest datum older than this = stale (see the file header).
  static const Duration staleAfter = Duration(hours: 12);

  /// Recovery below this (once calibrated) makes it a rest day: the lower
  /// half of the red zone.
  static const int restBelow = RecoveryEngine.yellowFrom ~/ 2;

  /// The "tonight" phase starts at 18:00 (the resolver's night cut) and
  /// runs until [tonightUntilHour] (05:00, as eveningKeyOf).
  static const int tonightFromHour = 18;
  static const int tonightUntilHour = 5;

  /// HRV within ±5 % of its usual, or resting HR within ±1.5 bpm, reads
  /// "about the same as usual" (the old Today summary's thresholds).
  static const double hrvUsualPct = 5;
  static const double rhrUsualBpm = 1.5;

  /// Sleep performance below this is mentioned in the summary.
  static const double shortSleepPerformance = 70;

  /// Sleep debt is mentioned from this many minutes (less is noise).
  static const double debtMentionMinutes = 15;

  /// Debt bands for the words: "a bit short" below [debtShortMinutes],
  /// "short" below [debtWellShortMinutes], "well short" from there.
  static const double debtShortMinutes = 60;
  static const double debtWellShortMinutes = 180;

  /// A ready day's target from here up reads "very hard": 0.2 × Recovery 85
  /// (StrainEngine.targetFactor), the top of the target scale.
  static const double veryHardTargetFrom = 17;

  /// Progress bands, as fractions of the effort range's low end.
  static const double progressStart = 0.25;
  static const double progressHalf = 0.4;
  static const double progressNear = 0.7;

  /// Before this hour, a small strain so far is not mentioned at all.
  static const int progressFromHour = 12;

  static const int maxActions = 3;
  static const int maxEvidence = 2;

  static const _recoveryRoute = '/recovery';
  static const _sleepRoute = '/sleep';
  static const _strainRoute = '/strain';

  /// Plans [today] (the newest day with data; between 00:00 and 05:00 the
  /// evening's day). [sync] carries the freshness line; [now] comes from
  /// clockProvider (never DateTime.now()). [appNames]: display names for
  /// origin packages the known-app table lacks (optional, additive).
  /// [use24h]: the phone's clock setting for bedtimes and times (additive;
  /// the default keeps the 24-hour form).
  static TodayPlan plan({
    required DayBundle today,
    SyncStatus? sync,
    required DateTime now,
    Map<String, String> appNames = const {},
    bool use24h = true,
  }) {
    final r = today.result;
    final record = today.record;
    final rec = r.recovery;
    final cal = r.calibration;
    final sleep = r.sleep;
    final strain = r.strain;
    final bedtime = r.bedtime;
    String clock(double m) => PlanFormat.clock(m, use24h: use24h);
    if (r.notes.any((n) => n.metric == 'age_unsupported')) {
      return TodayPlan(
        date: today.date,
        state: DayState.noData,
        headline: 'Scores are for adults',
        summary: 'Airlog does not provide scores or training guidance for people under 18.',
      );
    }

    final lastData = sync?.lastDataAt ?? record.lastDataAt;
    final stale = lastData == null || now.difference(lastData) > staleAfter;
    final hour = now.toLocal().hour;
    final evening = eveningKeyOf(now);
    final behind = today.date.compareTo(evening) < 0;
    final beforeWake =
        hour < tonightUntilHour && today.date.compareTo(evening) > 0;
    final tonight = hour >= tonightFromHour || hour < tonightUntilHour;
    final current = !behind && !beforeWake;

    final concerning = [
      for (final m in r.health.metrics)
        if (HealthMonitor.isConcerning(m)) m,
    ];
    final calibrating = rec != null && (rec.calibrating || cal.calibrating);
    final limited = rec != null && rec.confidence == RecoveryConfidence.low;
    final provisional =
        rec != null &&
        (!cal.established || rec.calibrating || calibrating || limited);
    final hrvNotShared = r.notShared.containsKey(Metric.hrv.code);
    final noScoreApp =
        rec == null &&
            hrvNotShared &&
            r.notShared[Metric.hrv.code] == r.notShared[Metric.restingHr.code]
        ? r.notShared[Metric.hrv.code]
        : null;
    final change = r.sourceChange;
    final relearning = change?.to == null
        ? null
        : Notes.appName(change!.to!, appNames);

    // ── State ────────────────────────────────────────────────────────────
    final DayState state;
    if (!current || rec == null) {
      state = DayState.noData;
    } else if (concerning.length >= 2 ||
        (!calibrating && !limited && rec.score < restBelow)) {
      state = DayState.rest;
    } else if (concerning.length == 1 ||
        (!calibrating && !limited && rec.zone == RecoveryZone.red)) {
      state = DayState.easy;
    } else if (calibrating) {
      state = DayState.calibrating;
    } else if (rec.zone == RecoveryZone.green && !stale && !limited) {
      state = DayState.ready;
    } else {
      state = DayState.steady;
    }
    final recoveryDriven =
        rec != null &&
        !calibrating &&
        !limited &&
        (rec.score < restBelow || rec.zone == RecoveryZone.red);
    final vitalsDriven =
        concerning.isNotEmpty &&
        (state == DayState.easy || state == DayState.rest) &&
        !recoveryDriven;
    final phase = tonight && current && bedtime != null
        ? PlanPhase.tonight
        : PlanPhase.today;

    // ── Summary: words only; the numbers are on the chips ────────────────
    String summary;
    if (behind) {
      summary = 'Nothing has come in for today yet.';
    } else if (beforeWake) {
      summary = 'Your scores show up after you wake up and your tracker syncs.';
    } else if (rec == null) {
      summary = noScoreApp != null
          ? "$noScoreApp doesn't share the heart data Recovery needs, so "
                "there's no Recovery score. Sleep and Strain still work."
          : "Last night's heart data didn't come in, so there's no "
                'Recovery score today.';
    } else if (limited) {
      summary =
          "Today's score uses only part of your data, so there's no "
          'workout advice today.';
    } else if (phase == PlanPhase.tonight) {
      summary = debtLine(bedtime!.debtMinutes, tonight: true);
    } else if (vitalsDriven) {
      summary = vitalsSentence(concerning);
    } else if (state == DayState.calibrating) {
      if (relearning != null) {
        summary =
            'You switched to $relearning, so Airlog is learning your usual '
            "again. Today's score may change.";
      } else if (cal.haveNights == 0) {
        summary =
            "Airlog is just getting to know you, so today's score may "
            'change.';
      } else {
        summary =
            "Airlog is still learning what's normal for you, so today's "
            'score may change.';
      }
    } else {
      final body = bodySentence(rec, sleep);
      summary = state == DayState.rest && recoveryDriven
          ? "Your body hasn't recovered yet. $body"
          : body;
    }

    // ── Evidence (1–2 headline numbers) ──────────────────────────────────
    final evidence = <PlanEvidence>[];
    if (behind) {
      if (lastData != null) {
        evidence.add(
          PlanEvidence(
            label: 'Last update',
            value: PlanFormat.when(lastData, now, use24h: use24h),
          ),
        );
      }
    } else if (!current) {
      // Before the wake-up: nothing to cite yet.
    } else if (rec == null) {
      if (sleep != null && sleep.hasData) evidence.add(_sleepChip(sleep));
    } else if (phase == PlanPhase.tonight) {
      evidence.add(
        PlanEvidence(
          label: 'Sleep goal',
          value: PlanFormat.hm(bedtime!.projectedNeedMinutes),
          route: _sleepRoute,
        ),
      );
      evidence.add(
        bedtime.debtMinutes >= debtMentionMinutes
            ? PlanEvidence(
                label: 'Missed sleep',
                value: PlanFormat.hm(bedtime.debtMinutes),
                route: _sleepRoute,
              )
            : _recoveryChip(rec, provisional),
      );
    } else {
      evidence.add(_recoveryChip(rec, provisional));
      if (vitalsDriven) {
        evidence.add(_vitalChip(concerning.first));
      } else if (calibrating) {
        final nights = relearning != null ? change!.nights : cal.haveNights;
        // "0 of 14 nights" reads badly on the first morning: no chip.
        if (nights > 0) {
          evidence.add(
            PlanEvidence(
              label: 'Learning',
              value: '$nights of ${cal.needNights} nights',
              route: _recoveryRoute,
            ),
          );
        }
      } else if (_hrvChip(rec) case final c?) {
        evidence.add(c);
      } else if (_rhrChip(rec) case final c?) {
        evidence.add(c);
      }
    }

    // ── Actions ──────────────────────────────────────────────────────────
    final actions = <PlanAction>[];

    // effort (today only)
    final target = strain?.targetStrain;
    if (current &&
        rec != null &&
        phase == PlanPhase.today &&
        !stale &&
        !calibrating &&
        !limited &&
        target != null) {
      final (lo, hi) = StrainEngine.targetRange(target);
      final so =
          strain != null &&
              strain.method != StrainMethod.none &&
              strain.strain > 0
          ? strain.strain
          : null;
      final level = effortFor(state, target);
      // Rest and easy days never nudge you to do more.
      final nudge = level.index >= EffortLevel.moderate.index;
      final started = so != null && so >= progressStart * lo;
      var title = effortTitle(level);
      String why;
      if (!vitalsDriven && so != null && so >= hi) {
        title = "You've done enough for today";
        why = "You're past today's goal. Take it easy from here.";
      } else if (!vitalsDriven && nudge && so != null && so >= lo) {
        title = "You've hit today's goal";
        why = 'Anything more is extra.';
      } else if (!vitalsDriven && nudge && started) {
        why = so < progressHalf * lo
            ? "You've made a start."
            : so < progressNear * lo
            ? "You're about halfway there."
            : "You're nearly there.";
      } else if (!vitalsDriven && nudge && hour >= progressFromHour) {
        final lead = record.workouts.isEmpty
            ? 'No workout recorded yet today.'
            : 'Not much effort so far today.';
        why = '$lead ${effortExample(level)}';
      } else {
        why = effortExample(level);
      }
      actions.add(
        PlanAction(
          kind: PlanActionKind.effort,
          title: title,
          why: why,
          // A vitals-driven easy day has no goal chip: the range comes from
          // a green Recovery and would contradict "keep it easy".
          evidence: vitalsDriven
              ? const []
              : [
                  PlanEvidence(
                    label: 'Effort goal',
                    value: '$lo–$hi',
                    comparison: started
                        ? '${PlanFormat.strain(so)} so far'
                        : null,
                    route: _strainRoute,
                  ),
                ],
          route: _strainRoute,
        ),
      );
    }

    // sleep
    if (current && bedtime != null && rec != null) {
      final need = PlanFormat.hm(bedtime.projectedNeedMinutes);
      final bed = bedtime.recommendedBedtimeMinutes;
      final wake = bedtime.habitualWakeMinutes;
      final debt = bedtime.debtMinutes;
      final owed = debt >= debtMentionMinutes;
      if (phase == PlanPhase.tonight) {
        final past = bed != null && _pastBedtime(now, bed);
        actions.add(
          PlanAction(
            kind: PlanActionKind.sleep,
            title: bed == null
                ? 'Get to bed in good time'
                : past
                ? 'Head to bed when you can'
                : 'Try to be asleep by ${clock(bed)}',
            why: bed == null
                ? 'Your sleep goal tonight is $need.'
                : past
                ? 'The best time to be asleep was ${clock(bed)}.'
                : wake != null
                ? 'You usually wake up at ${clock(wake)}, so that gives you '
                      'enough sleep.'
                : 'That gives you enough sleep tonight.',
            route: _sleepRoute,
          ),
        );
      } else {
        actions.add(
          PlanAction(
            kind: PlanActionKind.sleep,
            title: bed == null
                ? "Get a full night's sleep tonight"
                : 'Try to be asleep by ${clock(bed)}',
            why: owed
                ? debtLine(debt)
                : bed == null
                ? 'Your sleep goal tonight is $need.'
                : 'That gives you enough sleep before your usual wake-up '
                      'time.',
            // The goal as a chip, unless the why already says it.
            evidence: bed == null && !owed
                ? const []
                : [
                    PlanEvidence(
                      label: 'Sleep goal',
                      value: need,
                      comparison: owed
                          ? '${PlanFormat.hm(debt)} missed'
                          : null,
                      route: _sleepRoute,
                    ),
                  ],
            route: _sleepRoute,
          ),
        );
      }
    }

    // checkIn
    if (current && rec != null && concerning.isNotEmpty) {
      final summaryNamesThem = vitalsDriven && phase == PlanPhase.today;
      final shown = {for (final e in evidence) e.label};
      actions.add(
        PlanAction(
          kind: PlanActionKind.checkIn,
          title: HealthMonitor.checkInTitle,
          why: summaryNamesThem
              ? 'This is ${HealthMonitor.checkInNote}.'
              : '${vitalsSentence(concerning)} This is '
                    '${HealthMonitor.checkInNote}.',
          evidence: [
            for (final v in concerning)
              if (!shown.contains(v.kind.title)) _vitalChip(v),
          ],
        ),
      );
    }

    // recover
    if (state == DayState.easy || state == DayState.rest) {
      actions.add(
        PlanAction(
          kind: PlanActionKind.recover,
          title: phase == PlanPhase.tonight
              ? 'Have a calm evening'
              : 'Take it slow today',
          why: vitalsDriven
              ? 'An easier day gives your body a break.'
              : 'Your Recovery is Low today.',
          route: _recoveryRoute,
        ),
      );
    }

    // housekeeping: only as the sole action
    var relearningShown = false;
    if (actions.isEmpty) {
      final app = _primaryApp(record, appNames);
      if (stale || behind) {
        actions.add(
          PlanAction(
            kind: PlanActionKind.sync,
            title: app == null || _looksLikePackage(app)
                ? "Open your tracker's app to sync"
                : 'Open $app to sync',
            why: behind
                ? "Last night's data comes in when it syncs."
                : lastData == null
                ? 'No data has reached Airlog yet.'
                : 'Your latest data is from '
                      '${PlanFormat.when(lastData, now, use24h: use24h)}.',
          ),
        );
      } else if (current) {
        final wear = _wearWhy(
          rec,
          sleep,
          cal,
          calibrating,
          hrvNotShared,
          noScoreApp != null,
        );
        if (wear != null && relearning != null) {
          // A new source is re-learning: wearing won't speed that up. Say
          // so instead of asking to wear (once).
          if (!summary.contains(relearning)) {
            summary =
                '$summary '
                '${_relearningLine(relearning, change!.nights, cal.needNights)}.';
          }
          relearningShown = true;
        } else if (wear != null) {
          actions.add(
            PlanAction(
              kind: PlanActionKind.wear,
              title: calibrating
                  ? 'Keep wearing your tracker to bed'
                  : 'Wear your tracker to bed tonight',
              why: wear,
            ),
          );
        }
      }
    }

    return TodayPlan(
      date: today.date,
      state: state,
      headline: headlineFor(
        state,
        phase: phase,
        noScore: current && rec == null,
      ),
      summary: summary,
      evidence: evidence.take(maxEvidence).toList(),
      actions: actions.take(maxActions).toList(),
      sources: _sources(record, appNames),
      provisional: provisional,
      stale: stale,
      missingInputs: current ? _missing(record, sleep) : const [],
      phase: phase,
      relearningSource: relearning,
      summaryNamesRelearning:
          relearning != null &&
          (relearningShown || state == DayState.calibrating),
    );
  }

  /// "Airlog is learning your Samsung Health data: 3 of 14 nights so far"
  /// (the new source's nights from DayResult.sourceChange).
  static String _relearningLine(String app, int nights, int needNights) =>
      'Airlog is learning your $app data: $nights of $needNights nights so '
      'far';

  /// UI copy per state (copy.dart may restyle, not reword). [phase]: the
  /// evening speaks about tonight. [noScore]: there is data for today but
  /// no Recovery (waiting would not help).
  static String headlineFor(
    DayState s, {
    PlanPhase phase = PlanPhase.today,
    bool noScore = false,
  }) {
    if (s == DayState.noData) {
      return noScore ? 'No Recovery score today' : 'Waiting for your data';
    }
    if (phase == PlanPhase.tonight) {
      return switch (s) {
        DayState.ready || DayState.steady => 'Time to wind down',
        DayState.easy || DayState.rest => 'Rest up tonight',
        _ => 'Still getting to know you',
      };
    }
    return switch (s) {
      DayState.ready => 'Your body is ready',
      DayState.steady => 'Good for a normal day',
      DayState.easy => 'Take it easy today',
      DayState.rest => 'Make today a rest day',
      DayState.calibrating => 'Still getting to know you',
      DayState.noData => 'Waiting for your data',
    };
  }

  /// The effort level for a day that gets effort advice: keyed on the
  /// state, with "very hard" for a ready day whose target is at the top.
  static EffortLevel effortFor(DayState s, double target) => switch (s) {
    DayState.rest => EffortLevel.rest,
    DayState.easy => EffortLevel.easy,
    DayState.ready =>
      target >= veryHardTargetFrom ? EffortLevel.veryHard : EffortLevel.hard,
    _ => EffortLevel.moderate,
  };

  /// Advice, never a report: "would be fine" keeps the coach's verifier
  /// from reading a suggested workout as one that happened.
  static String effortTitle(EffortLevel l) => switch (l) {
    EffortLevel.rest => 'Rest or move gently today',
    EffortLevel.easy => 'Keep any workout easy today',
    EffortLevel.moderate => 'A normal workout would be fine today',
    EffortLevel.hard => 'A hard workout would be fine today',
    EffortLevel.veryHard => 'A very hard workout would be fine today',
  };

  /// One concrete example per level (general guidance, not measured).
  static String effortExample(EffortLevel l) => switch (l) {
    EffortLevel.rest => 'A short walk or some gentle stretching is plenty.',
    EffortLevel.easy => 'Try a walk, an easy bike ride or yoga.',
    EffortLevel.moderate =>
      'Try a steady run, a bike ride or a normal gym session.',
    EffortLevel.hard => 'Try a long run, intervals or a tough gym session.',
    EffortLevel.veryHard =>
      'Try hard intervals, a fast long run or a very tough session.',
  };

  /// Sleep debt in words (no minutes: the chips carry them). [tonight]:
  /// the evening summary, where "no debt" still says what to do.
  static String debtLine(double debtMinutes, {bool tonight = false}) =>
      debtMinutes < debtMentionMinutes
      ? (tonight
            ? "You're not short on sleep, so a normal night will do."
            : 'That gives you enough sleep before your usual wake-up time.')
      : debtMinutes < debtShortMinutes
      ? "You're a bit short on sleep from recent nights."
      : debtMinutes < debtWellShortMinutes
      ? "You're short on sleep from recent nights."
      : "You're well short on sleep from recent nights.";

  // ── helpers ──────────────────────────────────────────────────────────────

  static String? _wearWhy(
    RecoveryResult? rec,
    SleepAnalysis? sleep,
    Calibration cal,
    bool calibrating,
    bool hrvNotShared,
    bool noScoreShared,
  ) {
    if (rec == null) {
      return noScoreShared ? null : "Last night's heart data didn't come in.";
    }
    if (sleep == null || !sleep.hasData) {
      return "Last night's sleep didn't come in, so today's score leaves "
          'it out.';
    }
    if (rec.withoutHrv && !hrvNotShared) {
      return "Last night's HRV didn't come in, so today's score leaves it "
          'out.';
    }
    if (calibrating) {
      return "Airlog learns what's normal for you from each night you "
          'wear it.';
    }
    return null;
  }

  /// A package id ("com.x.y") rather than an app name: the sync title
  /// falls back to "your tracker's app".
  static bool _looksLikePackage(String name) =>
      RegExp(r'^[a-z][\w]*(\.[\w]+){2,}$').hasMatch(name);

  /// The basis gaps: heartRate = no resting HR (a Recovery input) or no
  /// intraday heart rate (the only Strain input).
  static List<InputGap> _missing(DayRecord r, SleepAnalysis? sleep) => [
    if (Inputs.hrv(r) == null) InputGap.hrv,
    if (Inputs.rhr(r) == null || Inputs.hr(r).isEmpty) InputGap.heartRate,
    if (sleep == null || !sleep.hasData) InputGap.sleep,
    if (Inputs.resp(r) == null) InputGap.respiratoryRate,
    if (Inputs.skinTemp(r) == null) InputGap.skinTemp,
    if (Inputs.spo2Avg(r) == null && Inputs.spo2Min(r) == null) InputGap.spo2,
  ];

  /// After [bed] (minutes since midnight, any value) on the evening clock.
  static bool _pastBedtime(DateTime now, double bed) {
    final l = now.toLocal();
    var n = l.hour * 60 + l.minute;
    if (n < 12 * 60) n += 1440;
    var b = (bed.round() % 1440 + 1440) % 1440;
    if (b < 12 * 60) b += 1440;
    return n > b;
  }

  static RecoveryComponent? _component(RecoveryResult rec, String key) {
    for (final c in rec.components) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// "Your heart is well rested today." from HRV and resting HR against
  /// their usual, plus sleep when it fell well short of the goal. With
  /// nothing to compare, the Recovery zone speaks.
  static String bodySentence(RecoveryResult rec, SleepAnalysis? sleep) {
    final hrv = _component(rec, 'hrv'), rhr = _component(rec, 'rhr');
    final hv = hrv?.value, hb = hrv?.baseline?.mean;
    final rv = rhr?.value, rb = rhr?.baseline?.mean;
    // +1 better, 0 usual, −1 worse, null nothing to compare.
    int? h, r;
    if (hv != null && hb != null && hb > 0) {
      final pct = (hv / hb - 1) * 100;
      h = pct.abs() < hrvUsualPct ? 0 : (pct > 0 ? 1 : -1);
    }
    if (rv != null && rb != null) {
      final d = rv - rb;
      r = d.abs() < rhrUsualBpm ? 0 : (d < 0 ? 1 : -1);
    }
    final good = h == 1 || r == 1;
    final bad = h == -1 || r == -1;
    String first;
    bool positive;
    if (good && bad) {
      first = 'Your heart shows mixed signs today.';
      positive = false;
    } else if (good) {
      first = 'Your heart is well rested today.';
      positive = true;
    } else if (bad) {
      first = 'Your heart is less rested than usual.';
      positive = false;
    } else if (h == 0 || r == 0) {
      first = 'Your heart looks about the same as usual.';
      positive = true;
    } else {
      first = switch (rec.zone) {
        RecoveryZone.green => "You've recovered well.",
        RecoveryZone.yellow => "You've partly recovered.",
        RecoveryZone.red => "You haven't fully recovered yet.",
      };
      positive = false;
    }
    final perf = sleep != null && sleep.hasData ? sleep.performance : null;
    if (perf != null && perf.isFinite && perf < shortSleepPerformance) {
      return '${first.substring(0, first.length - 1)}'
          '${positive ? ', but' : ', and'} you slept well under your sleep '
          'goal.';
    }
    return first;
  }

  static String _join(List<String> parts) => parts.length <= 1
      ? parts.join()
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';

  /// "Your HRV is lower than usual, and your resting heart rate and
  /// breathing rate are higher." No numbers: the chips carry them.
  static String vitalsSentence(List<HealthMetricStatus> vs) {
    final lower = [
      for (final v in vs)
        if (v.state == BandState.below) v.kind.plainName,
    ];
    final higher = [
      for (final v in vs)
        if (v.state != BandState.below) v.kind.plainName,
    ];
    String be(List<String> xs) => xs.length == 1 ? 'is' : 'are';
    if (lower.isEmpty) {
      return 'Your ${_join(higher)} ${be(higher)} higher than usual.';
    }
    if (higher.isEmpty) {
      return 'Your ${_join(lower)} ${be(lower)} lower than usual.';
    }
    return 'Your ${_join(lower)} ${be(lower)} lower than usual, and your '
        '${_join(higher)} ${be(higher)} higher.';
  }

  static PlanEvidence _recoveryChip(RecoveryResult rec, bool provisional) =>
      PlanEvidence(
        label: 'Recovery',
        value: PlanFormat.pct(rec.score),
        comparison: rec.withoutHrv
            ? 'without HRV'
            : (provisional ? 'early estimate' : null),
        route: _recoveryRoute,
      );

  static PlanEvidence? _hrvChip(RecoveryResult rec) {
    final c = _component(rec, 'hrv');
    final v = c?.value, b = c?.baseline?.mean;
    if (v == null) return null;
    String? cmp;
    if (b != null && b > 0) {
      final pct = (v / b - 1) * 100;
      cmp = pct.abs() < hrvUsualPct
          ? 'about usual'
          : '${PlanFormat.pctVsUsual(v, b)}% ${pct > 0 ? 'above' : 'below'} '
                'usual';
    }
    return PlanEvidence(
      label: 'HRV',
      value: PlanFormat.ms(v),
      comparison: cmp,
      route: _recoveryRoute,
    );
  }

  static PlanEvidence? _rhrChip(RecoveryResult rec) {
    final c = _component(rec, 'rhr');
    final v = c?.value, b = c?.baseline?.mean;
    if (v == null) return null;
    return PlanEvidence(
      label: 'Resting HR',
      value: PlanFormat.bpm(v),
      comparison: b == null ? null : 'usual ${PlanFormat.bpm(b)}',
      route: _recoveryRoute,
    );
  }

  static PlanEvidence _vitalChip(HealthMetricStatus v) => PlanEvidence(
    label: v.kind.title,
    value: v.value == null ? '–' : PlanFormat.vital(v.kind, v.value!),
    comparison: v.baseline == null
        ? null
        : 'usual ${PlanFormat.vital(v.kind, v.baseline!.mean)}',
  );

  static PlanEvidence _sleepChip(SleepAnalysis s) => PlanEvidence(
    label: 'Sleep',
    value: PlanFormat.hm(s.sleptMinutes),
    comparison: 'goal ${PlanFormat.hm(s.needMinutes)}',
    route: _sleepRoute,
  );

  static const _appMetrics = [
    Metric.hr,
    Metric.sleep,
    Metric.restingHr,
    Metric.hrv,
    Metric.respiratoryRate,
    Metric.skinTemp,
    Metric.spo2,
    Metric.steps,
    Metric.workouts,
  ];

  /// The app to open for a sync: the first metric's origin with a name.
  static String? _primaryApp(DayRecord r, Map<String, String> names) {
    for (final m in _appMetrics) {
      final p = r.provenance[m];
      if (p?.origin != null) return Notes.appName(p!, names);
    }
    return null;
  }

  /// Distinct display names of the apps behind today's inputs.
  static List<String> _sources(DayRecord r, Map<String, String> names) {
    final out = <String>[];
    for (final m in _appMetrics) {
      final p = r.provenance[m];
      if (p == null) continue;
      final n = p.origin != null
          ? Notes.appName(p, names)
          : SourceApps.nameOf(p);
      if (!out.contains(n)) out.add(n);
    }
    return out;
  }
}
