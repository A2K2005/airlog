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
//             talks about tonight (sleep target, debt, bedtime) instead of
//             today's effort.
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
//   today    effort (not stale, not calibrating; the strain range, and the
//            strain so far when there is some), sleep (bedtime or tonight's
//            target), checkIn (≥ 1 concerning vital; fixed non-diagnostic
//            copy), recover (easy or rest)
//   tonight  sleep, checkIn, recover (no effort)
//   Housekeeping (sync when stale or behind, else wear when inputs are
//   missing or calibrating) only when it would be the sole action;
//   otherwise the freshness line covers it. Never "wear" for an input the
//   source app doesn't share (DayResult.notShared), and never while a new
//   source re-learns (DayResult.sourceChange): wearing doesn't speed that
//   up, so the summary says "Re-learning your normal with <app>" instead.

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

  /// Minutes as "7 h 36 m", "8 h" or "45 m".
  static String hm(double minutes) {
    final t = minutes.isFinite && minutes > 0 ? minutes.round() : 0;
    final h = t ~/ 60, m = t % 60;
    if (h == 0) return '$m m';
    if (m == 0) return '$h h';
    return '$h h $m m';
  }

  /// Minutes since local midnight (any value; normalised mod 1440) as
  /// "22:40".
  static String clock(double minutesSinceMidnight) {
    final r = minutesSinceMidnight.isFinite ? minutesSinceMidnight.round() : 0;
    final t = (r % 1440 + 1440) % 1440;
    return '${(t ~/ 60).toString().padLeft(2, '0')}:'
        '${(t % 60).toString().padLeft(2, '0')}';
  }

  /// Local clock time of [t]: "07:12".
  static String time(DateTime t) {
    final l = t.toLocal();
    return clock((l.hour * 60 + l.minute).toDouble());
  }

  /// When [t] was, from [now]: "07:12", "yesterday 23:10", "Sep 26 23:10".
  static String when(DateTime t, DateTime now) {
    final day = DayKey.of(t), today = DayKey.of(now);
    if (day == today) return time(t);
    if (day == DayKey.add(today, -1)) return 'yesterday ${time(t)}';
    final l = t.toLocal();
    return '${_months[l.month - 1]} ${l.day} ${time(t)}';
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
    _ => ' ${k.unit}',
  };

  /// A Health Monitor value with its unit: "16.8 /min", "95%", "+0.4 °C".
  static String vital(HealthMetricKind k, double v) =>
      '${vitalNumber(k, v)}${unit(k)}';
}

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
  /// "normal for you" (the old Today summary's thresholds).
  static const double hrvUsualPct = 5;
  static const double rhrUsualBpm = 1.5;

  /// Sleep performance below this is mentioned in the summary.
  static const double shortSleepPerformance = 70;

  /// Sleep debt is mentioned from this many minutes (less is noise).
  static const double debtMentionMinutes = 15;

  static const int maxActions = 3;
  static const int maxEvidence = 2;

  static const _recoveryRoute = '/recovery';
  static const _sleepRoute = '/sleep';
  static const _strainRoute = '/strain';

  /// Plans [today] (the newest day with data; between 00:00 and 05:00 the
  /// evening's day). [sync] carries the freshness line; [now] comes from
  /// clockProvider (never DateTime.now()). [appNames]: display names for
  /// origin packages the known-app table lacks (optional, additive).
  static TodayPlan plan({
    required DayBundle today,
    SyncStatus? sync,
    required DateTime now,
    Map<String, String> appNames = const {},
  }) {
    final r = today.result;
    final record = today.record;
    final rec = r.recovery;
    final cal = r.calibration;
    final sleep = r.sleep;
    final strain = r.strain;
    final bedtime = r.bedtime;

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
    final provisional =
        rec != null && (!cal.established || rec.calibrating || calibrating);
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
        (!calibrating && rec.score < restBelow)) {
      state = DayState.rest;
    } else if (concerning.length == 1 ||
        (!calibrating && rec.zone == RecoveryZone.red)) {
      state = DayState.easy;
    } else if (calibrating) {
      state = DayState.calibrating;
    } else if (rec.zone == RecoveryZone.green && !stale) {
      state = DayState.ready;
    } else {
      state = DayState.steady;
    }
    final recoveryDriven =
        rec != null &&
        !calibrating &&
        (rec.score < restBelow || rec.zone == RecoveryZone.red);
    final vitalsDriven =
        concerning.isNotEmpty &&
        (state == DayState.easy || state == DayState.rest) &&
        !recoveryDriven;
    final phase = tonight && current && bedtime != null
        ? PlanPhase.tonight
        : PlanPhase.today;

    // ── Summary ──────────────────────────────────────────────────────────
    String summary;
    if (behind) {
      summary = lastData == null
          ? 'Nothing has arrived for today yet.'
          : 'Nothing for today has arrived yet; the newest data is from '
                '${PlanFormat.when(lastData, now)}.';
    } else if (beforeWake) {
      summary =
          "Today's scores arrive after you wake and your tracker "
          'syncs.';
    } else if (rec == null) {
      summary = noScoreApp != null
          ? "$noScoreApp doesn't share HRV or resting heart rate with "
                'Health Connect, so there is no Recovery score; sleep and '
                'strain still work.'
          : 'No HRV or resting heart rate arrived for last night, so there '
                'is no Recovery score today.';
    } else if (phase == PlanPhase.tonight) {
      final debt = bedtime!.debtMinutes >= debtMentionMinutes
          ? ', with ${PlanFormat.hm(bedtime.debtMinutes)} of sleep debt '
                'carried'
          : '';
      summary =
          "Tonight's sleep target is "
          '${PlanFormat.hm(bedtime.projectedNeedMinutes)}$debt.';
    } else if (vitalsDriven) {
      summary =
          '${_cap(_compareList(concerning))}; Recovery '
          '${_recoveryWords(rec)}.';
    } else if (state == DayState.calibrating) {
      final p = _recoveryWords(rec);
      if (relearning != null) {
        summary =
            '${_relearningLine(relearning, change!.nights, cal.needNights)}, '
            'so Recovery $p is provisional.';
      } else if (cal.haveNights == 0) {
        summary =
            'Airlog is just starting to learn your normal, so Recovery $p '
            'is provisional.';
      } else {
        summary =
            '${cal.haveNights} of ${cal.needNights} baseline nights so far, '
            'so Recovery $p is provisional.';
      }
    } else {
      final signals = _signals(rec, sleep);
      final lead = state == DayState.rest && recoveryDriven
          ? 'Recovery ${_recoveryWords(rec)}, very low for you'
          : 'Recovery ${_recoveryWords(rec)}';
      summary = signals.isEmpty ? '$lead.' : '$lead: $signals.';
    }

    // ── Evidence (1–2 headline numbers) ──────────────────────────────────
    final evidence = <PlanEvidence>[];
    if (behind) {
      if (lastData != null) {
        evidence.add(
          PlanEvidence(
            label: 'Last data',
            value: PlanFormat.when(lastData, now),
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
          label: 'Sleep target',
          value: PlanFormat.hm(bedtime!.projectedNeedMinutes),
          route: _sleepRoute,
        ),
      );
      evidence.add(_recoveryChip(rec, provisional));
    } else {
      evidence.add(_recoveryChip(rec, provisional));
      if (vitalsDriven) {
        evidence.add(_vitalChip(concerning.first));
      } else if (calibrating) {
        evidence.add(
          PlanEvidence(
            label: 'Baseline',
            value: relearning != null
                ? '${change!.nights} of ${cal.needNights} nights'
                : '${cal.haveNights} of ${cal.needNights} nights',
            route: _recoveryRoute,
          ),
        );
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
        target != null) {
      final (lo, hi) = StrainEngine.targetRange(target);
      final t = PlanFormat.strain(target);
      final so =
          strain != null &&
              strain.method != StrainMethod.none &&
              strain.strain > 0
          ? strain.strain
          : null;
      if (vitalsDriven) {
        actions.add(
          PlanAction(
            kind: PlanActionKind.effort,
            title: 'Keep effort light today',
            why:
                '${concerning.first.kind.label} is outside your usual range, '
                'so today is not the day to chase your strain target.',
            route: _strainRoute,
          ),
        );
      } else if (so != null && so >= hi) {
        actions.add(
          PlanAction(
            kind: PlanActionKind.effort,
            title: "You've reached today's effort",
            why:
                'Strain ${PlanFormat.strain(so)} so far, past your '
                '$lo–$hi target.',
            route: _strainRoute,
          ),
        );
      } else {
        actions.add(
          PlanAction(
            kind: PlanActionKind.effort,
            title: switch (state) {
              DayState.ready => 'Room to push: strain $lo–$hi',
              DayState.easy => 'Keep effort light: strain $lo–$hi',
              DayState.rest => 'Move gently: strain $lo–$hi',
              _ => 'Moderate effort: strain $lo–$hi',
            },
            why: so != null
                ? 'Strain ${PlanFormat.strain(so)} so far of your $lo–$hi '
                      'target.'
                : "Today's strain target is $t.",
            route: _strainRoute,
          ),
        );
      }
    }

    // sleep
    if (current && bedtime != null && rec != null) {
      final need = PlanFormat.hm(bedtime.projectedNeedMinutes);
      final bed = bedtime.recommendedBedtimeMinutes;
      final wake = bedtime.habitualWakeMinutes;
      if (phase == PlanPhase.tonight) {
        final past = bed != null && _pastBedtime(now, bed);
        actions.add(
          PlanAction(
            kind: PlanActionKind.sleep,
            title: bed == null
                ? "Get to bed in time for tonight's target"
                : past
                ? 'Head to bed when you can'
                : 'Aim for bed by ${PlanFormat.clock(bed)}',
            why: past
                ? "For tonight's target, bedtime was ${PlanFormat.clock(bed)}."
                : wake != null
                ? 'Your usual wake-up is ${PlanFormat.clock(wake)}.'
                : "That leaves room for tonight's sleep target.",
            route: _sleepRoute,
          ),
        );
      } else {
        final debt = bedtime.debtMinutes >= debtMentionMinutes
            ? ', with ${PlanFormat.hm(bedtime.debtMinutes)} of sleep debt '
                  'carried'
            : '';
        actions.add(
          PlanAction(
            kind: PlanActionKind.sleep,
            title: bed == null
                ? 'Aim for $need of sleep tonight'
                : 'Aim for bed by ${PlanFormat.clock(bed)}',
            why: bed == null
                ? (debt.isEmpty
                      ? "That is tonight's sleep target."
                      : 'You carry ${PlanFormat.hm(bedtime.debtMinutes)} of '
                            'sleep debt.')
                : "Tonight's sleep target is $need$debt.",
            route: _sleepRoute,
          ),
        );
      }
    }

    // checkIn
    if (current && rec != null && concerning.isNotEmpty) {
      final summaryHasNumbers = vitalsDriven && phase == PlanPhase.today;
      actions.add(
        PlanAction(
          kind: PlanActionKind.checkIn,
          title: HealthMonitor.checkInTitle,
          why: summaryHasNumbers
              ? '${_cap(_names(concerning))} '
                    '${concerning.length == 1 ? 'is' : 'are'} outside your '
                    'usual range: ${HealthMonitor.checkInNote}.'
              : '${_cap(_compareList(concerning))}: '
                    '${HealthMonitor.checkInNote}.',
          evidence: summaryHasNumbers
              ? const []
              : [for (final v in concerning) _vitalChip(v)],
        ),
      );
    }

    // recover
    if (state == DayState.easy || state == DayState.rest) {
      actions.add(
        PlanAction(
          kind: PlanActionKind.recover,
          title: phase == PlanPhase.tonight
              ? 'Keep the evening low-key'
              : 'Keep today low-key',
          why: vitalsDriven
              ? 'An easier day gives your body room while '
                    '${_names(concerning)} '
                    '${concerning.length == 1 ? 'is' : 'are'} off your usual.'
              : 'Recovery is in the red zone.',
          route: _recoveryRoute,
        ),
      );
    }

    // housekeeping: only as the sole action
    if (actions.isEmpty) {
      final app = _primaryApp(record, appNames);
      if (stale || behind) {
        actions.add(
          PlanAction(
            kind: PlanActionKind.sync,
            title: app == null
                ? "Open your tracker's app to sync"
                : 'Open $app to sync',
            why: behind
                ? "It writes last night's data to Health Connect when it "
                      'syncs.'
                : lastData == null
                ? 'No data has reached Airlog yet.'
                : 'The newest data is from ${PlanFormat.when(lastData, now)}.',
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
          final line = _relearningLine(
            relearning,
            change!.nights,
            cal.needNights,
          );
          if (!summary.contains(line)) summary = '$summary $line.';
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
      headline: headlineFor(state),
      summary: summary,
      evidence: evidence.take(maxEvidence).toList(),
      actions: actions.take(maxActions).toList(),
      sources: _sources(record, appNames),
      provisional: provisional,
      stale: stale,
      missingInputs: current ? _missing(record, sleep) : const [],
      phase: phase,
      relearningSource: relearning,
    );
  }

  /// "Re-learning your normal with Samsung Health: 3 of 14 nights so far"
  /// (the new source's nights from DayResult.sourceChange).
  static String _relearningLine(String app, int nights, int needNights) =>
      'Re-learning your normal with $app: $nights of $needNights nights so '
      'far';

  /// UI copy per state (copy.dart may restyle, not reword).
  static String headlineFor(DayState s) => switch (s) {
    DayState.ready => 'Ready to push',
    DayState.steady => 'A normal day',
    DayState.easy => 'Take it easy',
    DayState.rest => 'Make it a rest day',
    DayState.calibrating => 'Still learning your normal',
    DayState.noData => "Waiting for today's data",
  };

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
      return noScoreShared
          ? null
          : 'No HRV or resting heart rate arrived for last night.';
    }
    if (sleep == null || !sleep.hasData) {
      return 'No sleep arrived for last night, so Recovery is scored '
          'without it.';
    }
    if (rec.withoutHrv && !hrvNotShared) {
      return 'No HRV arrived for last night, so Recovery is scored '
          'without it.';
    }
    if (calibrating) {
      return 'Recovery learns your normal from the nights you wear it.';
    }
    return null;
  }

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

  static String _recoveryWords(RecoveryResult rec) =>
      '${PlanFormat.pct(rec.score)}${rec.withoutHrv ? ' without HRV' : ''}';

  static RecoveryComponent? _component(RecoveryResult rec, String key) {
    for (final c in rec.components) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// "HRV is 14% below your usual and resting HR 3 bpm above" (the old
  /// Today summary), plus sleep when its performance was short.
  static String _signals(RecoveryResult rec, SleepAnalysis? sleep) {
    final hrv = _component(rec, 'hrv'), rhr = _component(rec, 'rhr');
    final hv = hrv?.value, hb = hrv?.baseline?.mean;
    final rv = rhr?.value, rb = rhr?.baseline?.mean;
    String? h, rh;
    var hUsual = false, rUsual = false;
    if (hv != null && hb != null && hb > 0) {
      final pct = (hv / hb - 1) * 100;
      if (pct.abs() < hrvUsualPct) {
        hUsual = true;
      } else {
        h =
            '${PlanFormat.pctVsUsual(hv, hb)}% '
            '${pct > 0 ? 'above' : 'below'}';
      }
    }
    if (rv != null && rb != null) {
      final d = rv - rb;
      if (d.abs() < rhrUsualBpm) {
        rUsual = true;
      } else {
        // The two numbers themselves (a bare bpm difference isn't
        // traceable by the coach's verifier).
        rh =
            '${d > 0 ? 'above' : 'below'} your usual '
            '(${rv.round()} vs ${rb.round()} bpm)';
      }
    }
    String first;
    if (hv == null && rv == null) {
      first = '';
    } else if (hv == null) {
      first = rUsual
          ? 'resting HR is normal for you'
          : rh == null
          ? 'resting HR ${PlanFormat.bpm(rv!)}'
          : 'resting HR is $rh';
    } else if (rv == null) {
      first = hUsual
          ? 'HRV is normal for you'
          : h == null
          ? 'HRV ${PlanFormat.ms(hv)}'
          : 'HRV is $h your usual';
    } else if (h != null && rh != null) {
      first = 'HRV is $h your usual and resting HR $rh';
    } else if (h != null) {
      first = rUsual
          ? 'HRV is $h your usual; resting HR is normal'
          : 'HRV is $h your usual';
    } else if (rh != null) {
      first = hUsual ? 'HRV is normal; resting HR is $rh' : 'resting HR is $rh';
    } else if (hUsual && rUsual) {
      first = 'HRV and resting HR are both normal for you';
    } else {
      first = 'HRV ${PlanFormat.ms(hv)}, resting HR ${PlanFormat.bpm(rv)}';
    }
    final perf = sleep != null && sleep.hasData ? sleep.performance : null;
    if (perf != null && perf.isFinite && perf < shortSleepPerformance) {
      final s = 'sleep covered ${perf.round()}% of your target';
      return first.isEmpty ? s : '$first, and $s';
    }
    return first;
  }

  static String _vitalName(HealthMetricKind k) => switch (k) {
    HealthMetricKind.hrv => 'HRV',
    HealthMetricKind.restingHr => 'resting HR',
    HealthMetricKind.respiratoryRate => 'respiratory rate',
    HealthMetricKind.spo2 => 'SpO₂',
    HealthMetricKind.skinTemp => 'skin temperature',
  };

  static String _join(List<String> parts) => parts.length <= 1
      ? parts.join()
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';

  static String _names(List<HealthMetricStatus> vs) =>
      _join([for (final v in vs) _vitalName(v.kind)]);

  /// "resting HR higher (61 vs usual 54 bpm)" (the old Today alert card).
  static String _compare(HealthMetricStatus s) {
    final v = s.value, m = s.baseline?.mean;
    final word = s.state == BandState.above ? 'higher' : 'lower';
    final name = _vitalName(s.kind);
    if (v == null || m == null) return '$name $word than usual';
    return '$name $word (${PlanFormat.vitalNumber(s.kind, v)} vs usual '
        '${PlanFormat.vital(s.kind, m)})';
  }

  static String _compareList(List<HealthMetricStatus> vs) =>
      _join([for (final v in vs) _compare(v)]);

  static PlanEvidence _recoveryChip(RecoveryResult rec, bool provisional) =>
      PlanEvidence(
        label: 'Recovery',
        value: PlanFormat.pct(rec.score),
        comparison: rec.withoutHrv
            ? 'without HRV'
            : (provisional ? 'provisional' : null),
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
          ? 'normal for you'
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
    label: v.kind.label,
    value: v.value == null ? '–' : PlanFormat.vital(v.kind, v.value!),
    comparison: v.baseline == null
        ? null
        : 'usual ${PlanFormat.vital(v.kind, v.baseline!.mean)}',
  );

  static PlanEvidence _sleepChip(SleepAnalysis s) => PlanEvidence(
    label: 'Sleep',
    value: PlanFormat.hm(s.sleptMinutes),
    comparison: 'target ${PlanFormat.hm(s.needMinutes)}',
    route: _sleepRoute,
  );

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
