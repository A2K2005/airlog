// Today view-model: one day's three scores, the Health Monitor, the honesty
// notes and a deterministic one-line summary, mapped from the engine's
// DayResult. No Flutter widgets here; the screen only renders [TodayState].
//
// Reloads on every repository revision (sync, journal save) and whenever the
// focused day changes. Every sentence the screen shows is built here from the
// engine's numbers, so it can be unit-tested and never says more than the
// data does.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components/metric_tile.dart' show MetricTile;
import '../../design/components/score_ring.dart' show RingState;
import '../../design/tiles/readiness_tile.dart' show ReadinessStep;
import '../../domain/day_key.dart';
import '../../domain/engine/health_monitor.dart';
import '../../domain/engine/notes.dart';
import '../../domain/engine/recovery.dart' show RecoveryEngine;
import '../../domain/engine/stats.dart' show Stats;
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import '../../domain/today_plan.dart';
import '../../domain/engine/engine.dart' show Engine;
import '../../domain/engine/source_apps.dart';

/// One score ring, ready to draw.
class RingVm {
  const RingVm({
    required this.state,
    this.value,
    this.valueText,
    this.caption,
    this.progress,
    this.zone,
  });

  static const loading = RingVm(state: RingState.loading);

  final RingState state;
  final double? value;
  final String? valueText;
  final String? caption;

  /// Calibration progress 0…1 (calibrating rings only).
  final double? progress;

  /// Recovery only: the zone that colours the ring.
  final RecoveryZone? zone;
}

/// One Health Monitor tile plus its last 30 nights (for the tile's sparkline
/// and its explain sheet).
class HealthTileVm {
  const HealthTileVm(this.status, this.series);
  final HealthMetricStatus status;

  /// Dense, oldest first, one slot per day (the focused day last).
  final List<double?> series;

  /// The last [n] slots.
  List<double?> tail(int n) =>
      series.length <= n ? series : series.sublist(series.length - n);
}

/// The Health Monitor alert, rewritten from the out-of-range metrics
/// themselves (never a cause the data did not give).
class AlertVm {
  const AlertVm({required this.title, required this.body, required this.fix});
  final String title;
  final String body;
  final String fix;
}

/// The plain-English line: [why] (the signals behind the score) then
/// [verdict] (the score and what it suggests). Non-breaking spaces keep each
/// number with its unit.
class SummaryVm {
  const SummaryVm(this.why, this.verdict);
  final String why;
  final String verdict;
  String get text => why.isEmpty ? verdict : '$why $verdict';
}

enum TodayContent {
  /// The store is empty (first run, live mode before any sync).
  noData,

  /// There is data, but none for the focused day.
  emptyDay,

  /// The focused day has a result.
  ready,
}

class TodayState {
  const TodayState({
    required this.content,
    required this.now,
    required this.today,
    this.date,
    this.latest,
    this.earliest,
    this.recovery = RingVm.loading,
    this.strain = RingVm.loading,
    this.sleep = RingVm.loading,
    this.summary,
    this.alert,
    this.calibration,
    this.calibrationBody,
    this.health = const [],
    this.warnings = const [],
    this.infoNotes = const [],
    this.profileIncomplete = false,
    this.journalDate,
    this.journalLogged,
    this.bundle,
    this.steps = const [],
    this.usualRecovery,
    this.hrvVsUsual,
    this.rhrVsUsual,
    this.strainFacts,
    this.planBundle,
    this.appNames = const {},
    this.rhrLabel = 'Resting HR vs usual',
  });

  /// The bundle the plan reads: the newest day, except before 05:00, when
  /// the evening's day is still "today" for the plan (eveningKeyOf).
  final DayBundle? planBundle;

  /// Health Connect origin → app name, for the plan's sources line.
  final Map<String, String> appNames;

  /// "Resting HR vs usual", or "Sleeping HR vs usual" when the app never
  /// shares resting HR and sleeping HR stands in (the engine's label).
  final String rhrLabel;

  final TodayContent content;

  /// The day's record and result: the planner reads it. [redesign, additive]
  final DayBundle? bundle;

  /// Recovery of the last six days with data, oldest first, with the change
  /// from the day before (the Recovery tile's step chart).
  final List<ReadinessStep> steps;

  /// Mean Recovery over the loaded window (the chart's track line).
  final double? usualRecovery;

  /// "−12%" / "+3 bpm": HRV and resting HR against their usual.
  final String? hrvVsUsual, rhrVsUsual;

  /// Strain without heart rate: the day's activity facts instead of a
  /// number ("2 workouts · 8,400 steps").
  final String? strainFacts;
  final DateTime now;

  /// The clock's day key.
  final String today;

  /// The day shown (null only for [TodayContent.noData]).
  final String? date;
  final String? latest;

  /// Oldest day with data, when it is known to be inside the loaded window.
  final String? earliest;

  final RingVm recovery, strain, sleep;
  final SummaryVm? summary;
  final AlertVm? alert;

  /// Non-null while the baseline is not established (banner shown).
  final Calibration? calibration;
  final String? calibrationBody;
  final List<HealthTileVm> health;

  /// Notes shown as full StatusCards (warnings, source switches).
  final List<StatusNote> warnings;

  /// Informational notes, collapsed behind one row.
  final List<StatusNote> infoNotes;

  /// Birth year missing: zones use an assumed max HR.
  final bool profileIncomplete;

  /// The evening the journal card logs ([eveningKeyOf] the clock), null =
  /// no card (a past day is being shown).
  final String? journalDate;
  final Set<JournalFactor>? journalLogged;

  bool get isToday => date != null && date == today;
  bool get isLatest => date != null && date == latest;

  /// 18:00 to 05:00: the journal card asks for tonight's factors.
  bool get evening => now.hour >= 18 || now.hour < 5;
}

final todayViewModelProvider =
    AsyncNotifierProvider.autoDispose<TodayViewModel, TodayState>(
      TodayViewModel.new,
      retry: (_, _) => null,
    );

class TodayViewModel extends AsyncNotifier<TodayState> {
  static const windowDays = 30;

  @override
  Future<TodayState> build() async {
    ref.watch(revisionProvider);
    final repo = ref.watch(healthRepositoryProvider);
    final now = ref.watch(currentTimeProvider);
    // Today always shows the newest day (no day switcher; history lives on
    // the detail screens and Trends).
    final latestF = ref.watch(latestDateProvider.future);
    final date = await latestF;
    final today = DayKey.of(now);
    if (date == null) {
      return TodayState(content: TodayContent.noData, now: now, today: today);
    }
    final latest = await latestF ?? date;
    final bundle = await repo.day(date);
    final window = await repo.range(DayKey.add(date, -(windowDays - 1)), date);
    // Before 05:00 the plan still speaks about last evening's day.
    var planBundle = bundle;
    final evening = eveningKeyOf(now);
    if (now.hour < 5 && evening != date) {
      planBundle = await repo.day(evening) ?? bundle;
    }
    final appNames = <String, String>{...SourceApps.known};
    try {
      for (final a in await repo.detectedSources()) {
        appNames[a.origin] = a.displayName;
      }
    } catch (_) {}
    // The journal lives in More now; Today reads no journal.
    final s = TodayMapper.map(
      date: date,
      latest: latest,
      now: now,
      bundle: bundle,
      window: window,
    );
    return s.withPlanInputs(planBundle, appNames);
  }

  /// Steps the shown day by ±1 (shared with Sleep and Strain).
  void shift(int days) {
    final s = state.value;
    final latest = s?.latest;
    if (latest == null) return;
    ref.read(selectedDateProvider.notifier).shift(days, latest: latest);
  }

  /// Back to following the newest day.
  void showLatest() => ref.read(selectedDateProvider.notifier).select(null);

  /// Pull to refresh.
  Future<void> refresh() => ref.read(healthRepositoryProvider).syncNow();
}

/// Pure mapping from engine output to [TodayState]. Public for unit tests.
abstract final class TodayMapper {
  static TodayState map({
    required String date,
    required String latest,
    required DateTime now,
    required DayBundle? bundle,
    required List<DayBundle> window,
    String? journalDate,
    Set<JournalFactor>? journalLogged,
  }) {
    final today = DayKey.of(now);
    final first = window.isEmpty ? null : window.first.date;
    final windowStart = DayKey.add(date, -(TodayViewModel.windowDays - 1));
    final earliest = first != null && first.compareTo(windowStart) > 0
        ? first
        : null;
    if (bundle == null) {
      return TodayState(
        content: TodayContent.emptyDay,
        now: now,
        today: today,
        date: date,
        latest: latest,
        earliest: earliest,
        recovery: const RingVm(state: RingState.noData),
        strain: const RingVm(state: RingState.noData),
        sleep: const RingVm(state: RingState.noData),
        journalDate: journalDate,
        journalLogged: journalLogged,
      );
    }
    final r = bundle.result;
    final isToday = date == today;
    final notes = sortNotes(r);
    final cal = r.calibration;
    return TodayState(
      content: TodayContent.ready,
      now: now,
      today: today,
      date: date,
      latest: latest,
      earliest: earliest,
      recovery: recoveryRing(r),
      strain: strainRing(r.strain),
      sleep: sleepRing(r.sleep),
      summary: summary(r, isToday: isToday),
      alert: alert(r, window, date),
      calibration: cal.established ? null : cal,
      calibrationBody: cal.established ? null : notes.calibrationBody,
      health: healthTiles(r, window, date),
      warnings: notes.cards,
      infoNotes: notes.info,
      profileIncomplete: notes.profileIncomplete,
      journalDate: journalDate,
      journalLogged: journalLogged,
      bundle: bundle,
      steps: recoverySteps(window, date),
      usualRecovery: usualRecovery(window),
      hrvVsUsual: vsUsual(r.recovery, 'hrv'),
      rhrVsUsual:
          vsUsual(r.recovery, 'rhr') ??
          vsUsual(r.recovery, RecoveryEngine.sleepingHrKey),
      rhrLabel:
          r.recovery != null &&
              component(r.recovery!, 'rhr') == null &&
              component(r.recovery!, RecoveryEngine.sleepingHrKey) != null
          ? 'Sleeping HR vs usual'
          : 'Resting HR vs usual',
      strainFacts: activityFacts(bundle),
    );
  }

  // ── tiles ──────────────────────────────────────────────────────────────

  /// The last six days with a Recovery score, oldest first; each carries its
  /// change in points from the day with data before it.
  static List<ReadinessStep> recoverySteps(
    List<DayBundle> window,
    String date,
  ) {
    final scored = [
      for (final b in window)
        if (b.date.compareTo(date) <= 0 &&
            b.result.recovery != null &&
            !b.result.recovery!.calibrating)
          (b.date, b.result.recovery!.score),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final tail = scored.length > 7 ? scored.sublist(scored.length - 7) : scored;
    final out = <ReadinessStep>[];
    for (var i = 0; i < tail.length; i++) {
      if (tail.length == 7 && i == 0) continue;
      final prev = i == 0 ? null : tail[i - 1].$2;
      final d = prev == null ? null : tail[i].$2 - prev;
      out.add(
        ReadinessStep(
          value: tail[i].$2.toDouble(),
          label: '${tail[i].$2}',
          delta: d == null ? null : (d > 0 ? '+$d' : (d < 0 ? '−${-d}' : '0')),
        ),
      );
    }
    return out;
  }

  static double? usualRecovery(List<DayBundle> window) {
    final xs = [
      for (final b in window)
        if (b.result.recovery != null && !b.result.recovery!.calibrating)
          b.result.recovery!.score,
    ];
    if (xs.length < 3) return null;
    return xs.reduce((a, b) => a + b) / xs.length;
  }

  /// "+12%" (HRV, relative) or "−3 bpm" (resting HR, absolute) against the
  /// input's baseline mean; null when either is missing.
  static String? vsUsual(RecoveryResult? r, String key) {
    if (r == null) return null;
    final c = component(r, key);
    final v = c?.value, m = c?.baseline?.mean;
    if (v == null || m == null || m == 0) return null;
    if (key == 'hrv') {
      final pct = ((v / m - 1) * 100).round();
      return pct == 0 ? 'Same as usual' : '${pct > 0 ? '+' : '−'}${pct.abs()}%';
    }
    final d = (v.round() - m.round());
    return d == 0 ? 'Same as usual' : '${d > 0 ? '+' : '−'}${d.abs()} bpm';
  }

  /// Strain without heart rate shows what was measured instead of a number.
  static String? activityFacts(DayBundle? b) {
    if (b == null) return null;
    final s = b.result.strain;
    if (s != null && s.method != StrainMethod.none) return null;
    final w = b.record.workouts.length;
    final st = b.record.steps;
    final parts = [
      if (w > 0) '$w ${w == 1 ? 'workout' : 'workouts'}',
      if (st != null && st > 0) '${_thousands(st)} steps',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _thousands(int n) {
    final s = '$n';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  // ── rings ──────────────────────────────────────────────────────────────

  /// Coordinator rule: calibrating while Pulse's per-metric flag is set
  /// (< 5 nights), provisional until 14 nights, measured after.
  static RingVm recoveryRing(DayResult r) {
    final rec = r.recovery;
    if (rec == null) {
      return const RingVm(state: RingState.noData, caption: 'No HRV or RHR');
    }
    if (rec.calibrating) {
      final left = nightsToReliable(rec, r.calibration);
      return RingVm(
        state: RingState.calibrating,
        progress: r.calibration.progress,
        caption: left <= 1 ? '1 more night' : '$left more nights',
        zone: rec.zone,
      );
    }
    final provisional = !r.calibration.established;
    return RingVm(
      state: provisional ? RingState.provisional : RingState.measured,
      value: rec.score.toDouble(),
      caption: provisional ? 'Provisional' : zoneName(rec.zone),
      zone: rec.zone,
    );
  }

  /// Nights still needed before HRV and resting HR each have 5 baseline
  /// values (the inputs that report today). The engine keeps no baseline
  /// under 3 values, so below that the calibration count stands in.
  static int nightsToReliable(RecoveryResult rec, Calibration cal) {
    int? have;
    for (final c in rec.components) {
      if (c.key != 'hrv' && c.key != 'rhr') continue;
      final n =
          c.baseline?.count ??
          (cal.haveNights < Stats.minBaselineValues
              ? cal.haveNights
              : Stats.minBaselineValues - 1);
      if (have == null || n < have) have = n;
    }
    final left = RecoveryEngine.reliableNights - (have ?? cal.haveNights);
    return left < 1 ? 1 : left;
  }

  static String zoneName(RecoveryZone z) => switch (z) {
    RecoveryZone.green => 'Green zone',
    RecoveryZone.yellow => 'Yellow zone',
    RecoveryZone.red => 'Red zone',
  };

  static RingVm strainRing(StrainResult? s) {
    if (s == null || s.method == StrainMethod.none) {
      return const RingVm(state: RingState.noData, caption: 'No HR data');
    }
    final target = s.targetStrain;
    final estimated = s.method == StrainMethod.fallback;
    return RingVm(
      state: estimated ? RingState.provisional : RingState.measured,
      value: s.strain,
      valueText: s.strain.toStringAsFixed(1),
      caption: [
        if (estimated) 'Estimated',
        if (target != null) 'Target ${target.toStringAsFixed(1)}',
      ].join(' · '),
    );
  }

  static RingVm sleepRing(SleepAnalysis? s) {
    if (s == null || !s.hasData) {
      return const RingVm(state: RingState.noData, caption: 'No sleep');
    }
    return RingVm(
      state: RingState.measured,
      value: s.performance,
      caption: hm(s.sleptMinutes),
    );
  }

  // ── summary ────────────────────────────────────────────────────────────

  static const _nb = '\u00A0';

  /// One or two sentences, every clause backed by a number the engine gave.
  static SummaryVm summary(DayResult r, {required bool isToday}) {
    final rec = r.recovery;
    final sleep = r.sleep;
    if (rec == null) {
      final slept = sleep != null && sleep.hasData
          ? ' You slept ${hm(sleep.sleptMinutes)} of the '
                '${hm(sleep.needMinutes)} you needed.'
          : '';
      return SummaryVm(
        '',
        'No Recovery score: neither HRV nor resting heart rate arrived '
            'for ${isToday ? 'last night' : 'that night'}.$slept',
      );
    }
    final hrv = component(rec, 'hrv');
    final rhr = component(rec, 'rhr');
    if (rec.calibrating) {
      final left = nightsToReliable(rec, r.calibration);
      final measured = [
        if (hrv?.value != null) 'HRV ${hrv!.value!.round()}${_nb}ms',
        if (rhr?.value != null) 'resting HR ${rhr!.value!.round()}${_nb}bpm',
      ];
      return SummaryVm(
        measured.isEmpty ? '' : 'Last night: ${measured.join(', ')}.',
        'Still learning your baseline: $left more '
        '${left == 1 ? 'night' : 'nights'} before Recovery means much.',
      );
    }
    final why = signals(hrv, rhr, sleep);
    final score =
        'Recovery ${rec.score}$_nb%'
        '${r.calibration.established ? '' : ' (provisional)'}';
    final target = r.strain?.targetStrain;
    String advice;
    if (isToday) {
      final t = target == null
          ? ''
          : ' (target strain ${target.toStringAsFixed(1)})';
      advice = switch (rec.zone) {
        RecoveryZone.green => ' — a good day for a harder session$t.',
        RecoveryZone.yellow => ' — a moderate session suits today$t.',
        RecoveryZone.red => ' — a day to keep it light$t.',
      };
    } else {
      final s = r.strain;
      final reached = s == null || s.method == StrainMethod.none
          ? ''
          : '; strain reached ${s.strain.toStringAsFixed(1)}';
      advice = target == null
          ? '$reached.'
          : ' — target strain was ${target.toStringAsFixed(1)}$reached.';
    }
    return SummaryVm(why, '$score$advice');
  }

  /// "HRV is 14 % above your usual and resting HR 3 bpm below."
  static String signals(
    RecoveryComponent? hrv,
    RecoveryComponent? rhr,
    SleepAnalysis? sleep,
  ) {
    final hv = hrv?.value, hb = hrv?.baseline?.mean;
    final rv = rhr?.value, rb = rhr?.baseline?.mean;
    String? h, rh;
    var hUsual = false, rUsual = false;
    if (hv != null && hb != null && hb > 0) {
      final pct = (hv / hb - 1) * 100;
      if (pct.abs() < 5) {
        hUsual = true;
      } else {
        h = '${pct.abs().round()}$_nb% ${pct > 0 ? 'above' : 'below'}';
      }
    }
    if (rv != null && rb != null) {
      final d = rv - rb;
      if (d.abs() < 1.5) {
        rUsual = true;
      } else {
        rh = '${d.abs().round()}${_nb}bpm ${d > 0 ? 'above' : 'below'}';
      }
    }
    final String first;
    if (hv == null && rv == null) {
      first = 'No HRV or resting heart rate last night.';
    } else if (hv == null) {
      first = rUsual
          ? 'No HRV last night; resting HR is normal for you.'
          : rh == null
          ? 'No HRV last night.'
          : 'No HRV last night; resting HR is $rh your usual.';
    } else if (rv == null) {
      first = hUsual
          ? 'HRV is normal for you; no resting HR last night.'
          : h == null
          ? 'No resting HR last night.'
          : 'HRV is $h your usual; no resting HR last night.';
    } else if (h != null && rh != null) {
      first = 'HRV is $h your usual and resting HR $rh.';
    } else if (h != null) {
      first = 'HRV is $h your usual; resting HR is normal.';
    } else if (rh != null) {
      first = 'HRV is normal; resting HR is $rh your usual.';
    } else if (hUsual && rUsual) {
      first = 'HRV and resting HR are both normal for you.';
    } else {
      first = 'Baselines for HRV and resting HR are still short.';
    }
    final perf = sleep != null && sleep.hasData ? sleep.performance : null;
    if (perf != null && perf < 70) {
      return '${first.substring(0, first.length - 1)}, and sleep covered '
          '${perf.round()}$_nb% of your need.';
    }
    return first;
  }

  static RecoveryComponent? component(RecoveryResult r, String key) {
    for (final c in r.components) {
      if (c.key == key) return c;
    }
    return null;
  }

  // ── Health Monitor ─────────────────────────────────────────────────────

  static const _order = [
    HealthMetricKind.hrv,
    HealthMetricKind.restingHr,
    HealthMetricKind.respiratoryRate,
    HealthMetricKind.skinTemp,
    HealthMetricKind.spo2,
  ];

  /// The four core nightly metrics always; SpO₂ only when it reported
  /// (it needs Enhanced mode, and a daily "No data" tile would be noise).
  static List<HealthTileVm> healthTiles(
    DayResult r,
    List<DayBundle> window,
    String date,
  ) {
    final keys = DayKey.range(
      DayKey.add(date, -(TodayViewModel.windowDays - 1)),
      date,
    );
    final byDate = {for (final b in window) b.date: b};
    final out = <HealthTileVm>[];
    for (final k in _order) {
      final s = statusOf(r.health, k);
      if (s == null) continue;
      if (k == HealthMetricKind.spo2 && s.value == null) continue;
      out.add(
        HealthTileVm(s, [
          for (final d in keys) statusOf(byDate[d]?.result.health, k)?.value,
        ]),
      );
    }
    return out;
  }

  static HealthMetricStatus? statusOf(
    HealthMonitorResult? h,
    HealthMetricKind k,
  ) {
    if (h == null) return null;
    for (final m in h.metrics) {
      if (m.kind == k) return m;
    }
    return null;
  }

  static AlertVm? alert(DayResult r, List<DayBundle> window, String date) {
    if (!r.health.alert) return null;
    final concerning = [
      for (final k in _order)
        if (statusOf(r.health, k) case final s?)
          if (HealthMonitor.isConcerning(s)) s,
    ];
    const fix =
        'An easier day and an early night are a sensible response. This is '
        'a pattern in your numbers, not a diagnosis.';
    if (concerning.isEmpty) {
      return AlertVm(
        title: 'Signals outside your usual range',
        body: r.health.alertReason ?? '',
        fix: fix,
      );
    }
    if (concerning.length >= 2) {
      final parts = [for (final s in concerning) _compare(s)];
      final list = parts.length == 2
          ? '${parts[0]} and ${parts[1]}'
          : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
      return AlertVm(
        title: '${_count(concerning.length)} signals outside your usual range',
        body: '${_cap(list)}.',
        fix: fix,
      );
    }
    final s = concerning.single;
    final days = streak(s.kind, window, date);
    final dir = HealthMonitor.directionWord(s.kind) == 'low' ? 'low' : 'high';
    return AlertVm(
      title: days >= 2
          ? '${s.kind.label} $dir for $days days'
          : '${s.kind.label} outside your usual range',
      body: '${_cap(_compare(s))}.',
      fix: fix,
    );
  }

  /// Consecutive days, ending on [date], on which [kind] was concerning.
  static int streak(
    HealthMetricKind kind,
    List<DayBundle> window,
    String date,
  ) {
    final byDate = {for (final b in window) b.date: b};
    var n = 0;
    var d = date;
    while (true) {
      final s = statusOf(byDate[d]?.result.health, kind);
      if (s == null || !HealthMonitor.isConcerning(s)) break;
      n++;
      d = DayKey.add(d, -1);
    }
    return n;
  }

  /// "resting HR higher (60 vs usual 54 bpm)".
  static String _compare(HealthMetricStatus s) {
    final v = s.value, m = s.baseline?.mean;
    final word = s.state == BandState.above ? 'higher' : 'lower';
    final name = switch (s.kind) {
      HealthMetricKind.hrv => 'HRV',
      HealthMetricKind.restingHr => 'resting HR',
      HealthMetricKind.respiratoryRate => 'respiratory rate',
      HealthMetricKind.spo2 => 'SpO₂',
      HealthMetricKind.skinTemp => 'skin temperature',
    };
    if (v == null || m == null) return '$name $word than usual';
    return '$name $word (${metricValue(s.kind, v)} vs usual '
        '${metricValue(s.kind, m)} ${s.kind.unit})';
  }

  static String _count(int n) => switch (n) {
    2 => 'Two',
    3 => 'Three',
    4 => 'Four',
    5 => 'Five',
    _ => '$n',
  };

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Display value in the metric's own precision ("54", "15.2", "+0.6"):
  /// the Health Monitor tile's own formatter, so tile, alert and sheet agree.
  static String metricValue(HealthMetricKind k, double v) =>
      MetricTile.valueText(k, v);

  // ── notes ──────────────────────────────────────────────────────────────

  static final _calibratingTitle = Notes.recoveryCalibrating(0, '').title;
  static final _assumedMaxTitle = Notes.assumedMaxHr(0).title;

  /// Sorts the day's notes for Today:
  ///  * the calibrating note becomes the banner's body (no duplicate card);
  ///  * setup notes (birth year) collapse into one Profile line;
  ///  * warnings and source switches get full cards;
  ///  * with no Recovery at all, the one "No Recovery" card stands in for
  ///    the missing-HRV and missing-RHR warnings (they move to "more");
  ///  * everything else is informational, one tap away.
  static ({
    List<StatusNote> cards,
    List<StatusNote> info,
    bool profileIncomplete,
    String? calibrationBody,
  })
  sortNotes(DayResult r) {
    final cards = <StatusNote>[];
    final info = <StatusNote>[];
    var profile = false;
    String? calibrationBody;
    final noRecovery = r.recovery == null;
    for (final n in r.notes) {
      if (n.metric == 'recovery' && n.title == _calibratingTitle) {
        calibrationBody = n.body;
        continue;
      }
      if (n.metric == 'pulse_age' || n.title == _assumedMaxTitle) {
        profile = true;
        continue;
      }
      if (n.metric == 'vo2max') continue;
      final switched =
          n.title.startsWith('New ') && n.title.endsWith('baseline');
      final covered =
          noRecovery &&
          (n.metric == Metric.hrv.code || n.metric == Metric.restingHr.code);
      if ((n.severity == NoteSeverity.warning && !covered) || switched) {
        cards.add(n);
      } else {
        info.add(n);
      }
    }
    return (
      cards: cards,
      info: info,
      profileIncomplete: profile,
      calibrationBody: calibrationBody,
    );
  }
}

/// "7h 2m" / "45m" (same form as the chart axes).
String hm(double minutes) {
  if (!minutes.isFinite) return '';
  final t = minutes.round(), h = t ~/ 60, m = t % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// The day's plan for Today's hero: TodayPlanner over the newest day, the
/// sync status and the clock. Recomputed (cheaply) when any of them changes;
/// the repository is not re-read. [redesign]
final todayPlanProvider = Provider.autoDispose<TodayPlan?>((ref) {
  final s = ref.watch(todayViewModelProvider).value;
  final b = s?.planBundle ?? s?.bundle;
  if (b == null) return null;
  final sync = ref.watch(syncStatusProvider).value;
  return Engine.planToday(
    b,
    sync: sync,
    now: ref.watch(currentTimeProvider),
    appNames: s!.appNames,
  );
});

extension on TodayState {
  TodayState withPlanInputs(DayBundle? planBundle, Map<String, String> names) =>
      TodayState(
        content: content,
        now: now,
        today: today,
        date: date,
        latest: latest,
        earliest: earliest,
        recovery: recovery,
        strain: strain,
        sleep: sleep,
        summary: summary,
        alert: alert,
        calibration: calibration,
        calibrationBody: calibrationBody,
        health: health,
        warnings: warnings,
        infoNotes: infoNotes,
        profileIncomplete: profileIncomplete,
        journalDate: journalDate,
        journalLogged: journalLogged,
        bundle: bundle,
        steps: steps,
        usualRecovery: usualRecovery,
        hrvVsUsual: hrvVsUsual,
        rhrVsUsual: rhrVsUsual,
        strainFacts: strainFacts,
        rhrLabel: rhrLabel,
        planBundle: planBundle,
        appNames: names,
      );
}
