// Recovery detail view-model: how the focused day's Recovery was built,
// input by input, each input against its 30-night band, the Plews 7-day HRV
// readiness and the last 30 scores.
//
// One definition of "usual" everywhere: the mean of the raw nightly values
// in the baseline segment (RecoveryComponent.baseline / HealthMetricStatus
// baseline), so the breakdown, the band charts, Today's summary and the
// engine's own `detail` string agree. ln(RMSSD) is used only inside the HRV
// z-score, never shown as a "usual".

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/charts/contribution_bars.dart' show Contribution;
import '../../design/components/score_ring.dart' show RingState;
import '../../domain/day_key.dart';
import '../../domain/engine/notes.dart';
import '../../domain/engine/recovery.dart';
import '../../domain/engine/strain.dart' show StrainEngine;
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';

enum RecoveryContent { noData, emptyDay, ready }

/// One recovery input over the last 30 nights.
class InputVm {
  const InputVm({
    required this.key,
    required this.label,
    required this.unit,
    required this.decimals,
    required this.values,
    this.today,
    this.mean,
    this.sd,
    this.lower,
    this.upper,
    this.state,
    this.provenance,
    this.footnote,
  });

  /// 'hrv' | 'rhr' | 'sleep' | 'resp'
  final String key;
  final String label;
  final String unit;
  final int decimals;

  /// Dense, oldest first, the focused night last.
  final List<double?> values;
  final double? today;
  final double? mean, sd, lower, upper;

  /// Band state for today's value (null for sleep, which has no band).
  final BandState? state;
  final Provenance? provenance;
  final String? footnote;

  String fmt(double v) => v.toStringAsFixed(decimals);

  /// "Last night 54 ms · usual 47 ms" (the spread lives in the ⓘ sheet).
  String get line {
    final t = today == null
        ? 'No reading last night'
        : 'Last night ${fmt(today!)} $unit';
    if (mean == null) return t;
    return '$t · usual ${fmt(mean!)} $unit';
  }
}

/// Plews 7-day lnRMSSD readiness, shown in milliseconds.
class ReadinessVm {
  const ReadinessVm({
    required this.state,
    required this.rollingMs,
    required this.lowerMs,
    required this.upperMs,
    required this.baselineMs,
    required this.cv,
    required this.swc,
  });
  final SwcState state;
  final double rollingMs, lowerMs, upperMs, baselineMs;

  /// CV of lnRMSSD over the 7 days, %.
  final double cv;

  /// The engine's raw ln values (for the explain sheet).
  final ReadinessSwc swc;

  String get headline => switch (state) {
    SwcState.within => 'Steady',
    SwcState.above => 'Above your usual range',
    SwcState.below => 'Below your usual range',
  };

  String get body {
    final avg = '${rollingMs.round()}\u00A0ms';
    final band = '${lowerMs.round()}–${upperMs.round()}\u00A0ms';
    return switch (state) {
      SwcState.within =>
        'Your HRV this week ($avg) is in your usual range ($band).',
      SwcState.below =>
        'Your HRV this week ($avg) is below your usual range ($band). A '
            'whole week lower is a better reason to ease off than one low '
            'night.',
      SwcState.above =>
        'Your HRV this week ($avg) is above your usual range ($band).',
    };
  }
}

class RecoveryState {
  const RecoveryState({
    required this.content,
    required this.today,
    this.date,
    this.latest,
    this.earliest,
    this.result,
    this.ringState = RingState.noData,
    this.ringCaption,
    this.headline,
    this.meaning,
    this.contributions = const [],
    this.reweightNote,
    this.neutralNote,
    this.inputs = const [],
    this.readiness,
    this.readinessMissing,
    this.history = const [],
    this.historyZones = const [],
    this.notes = const [],
    this.calibration,
  });

  final RecoveryContent content;
  final String today;
  final String? date, latest, earliest;
  final RecoveryResult? result;
  final RingState ringState;
  final String? ringCaption;

  /// "Good · 67–99".
  final String? headline;

  /// What the zone means, with the day's effort goal as a range.
  final String? meaning;
  final List<Contribution> contributions;

  /// Which inputs were missing and how their weight was shared out.
  final String? reweightNote;

  /// Inputs scored neutral because they have no baseline yet.
  final String? neutralNote;
  final List<InputVm> inputs;
  final ReadinessVm? readiness;
  final String? readinessMissing;

  /// Last 30 days of scores, dense (null = no score), focused day last.
  final List<double?> history;
  final List<RecoveryZone?> historyZones;
  final List<StatusNote> notes;
  final Calibration? calibration;

  bool get isLatest => date != null && date == latest;
}

final recoveryViewModelProvider =
    AsyncNotifierProvider.autoDispose<RecoveryViewModel, RecoveryState>(
      RecoveryViewModel.new,
      retry: (_, _) => null,
    );

class RecoveryViewModel extends AsyncNotifier<RecoveryState> {
  static const windowDays = 30;

  @override
  Future<RecoveryState> build() async {
    ref.watch(revisionProvider);
    final repo = ref.watch(healthRepositoryProvider);
    final now = ref.watch(currentTimeProvider);
    final dateF = ref.watch(focusedDateProvider.future);
    final latestF = ref.watch(latestDateProvider.future);
    final date = await dateF;
    final today = DayKey.of(now);
    if (date == null) {
      return RecoveryState(content: RecoveryContent.noData, today: today);
    }
    final latest = await latestF ?? date;
    final bundle = await repo.day(date);
    final window = await repo.range(DayKey.add(date, -(windowDays - 1)), date);
    return RecoveryMapper.map(
      date: date,
      latest: latest,
      today: today,
      bundle: bundle,
      window: window,
    );
  }

  void shift(int days) {
    final latest = state.value?.latest;
    if (latest == null) return;
    ref.read(selectedDateProvider.notifier).shift(days, latest: latest);
  }
}

abstract final class RecoveryMapper {
  static const labels = {
    'hrv': 'Heart rate variability (HRV)',
    'rhr': 'Resting heart rate',
    'sleep': 'Sleep',
    'resp': 'Breathing rate',
    RecoveryEngine.sleepingHrKey: 'Sleeping heart rate',
  };

  static const _short = {
    'hrv': 'HRV',
    'rhr': 'resting heart rate',
    'sleep': 'sleep',
    'resp': 'breathing rate',
    RecoveryEngine.sleepingHrKey: 'sleeping heart rate',
  };

  static RecoveryState map({
    required String date,
    required String latest,
    required String today,
    required DayBundle? bundle,
    required List<DayBundle> window,
  }) {
    final windowStart = DayKey.add(date, -(RecoveryViewModel.windowDays - 1));
    final first = window.isEmpty ? null : window.first.date;
    final earliest = first != null && first.compareTo(windowStart) > 0
        ? first
        : null;
    if (bundle == null) {
      return RecoveryState(
        content: RecoveryContent.emptyDay,
        today: today,
        date: date,
        latest: latest,
        earliest: earliest,
      );
    }
    final r = bundle.result;
    final rec = r.recovery;
    final keys = DayKey.range(windowStart, date);
    final byDate = {for (final b in window) b.date: b};
    final history = [
      for (final k in keys) byDate[k]?.result.recovery?.score.toDouble(),
    ];
    final zones = [for (final k in keys) byDate[k]?.result.recovery?.zone];
    final (ringState, caption) = _ring(r);
    return RecoveryState(
      content: RecoveryContent.ready,
      today: today,
      date: date,
      latest: latest,
      earliest: earliest,
      result: rec,
      ringState: ringState,
      ringCaption: caption,
      headline: rec == null ? null : zoneHeadline(rec.zone),
      meaning: rec == null
          ? null
          : meaning(rec, r.strain, isToday: date == today),
      contributions: rec == null ? const [] : contributions(rec, r.sleep),
      reweightNote: rec == null ? null : reweightNote(rec),
      neutralNote: rec == null ? null : neutralNote(rec),
      inputs: inputs(bundle, keys, byDate),
      readiness: readiness(r.readiness),
      readinessMissing: r.readiness == null
          ? 'Shows up after 7 nights of HRV, with at least 3 in the last '
                'week.'
          : null,
      history: history,
      historyZones: zones,
      notes: notes(r),
      calibration: r.calibration.established ? null : r.calibration,
    );
  }

  static (RingState, String?) _ring(DayResult r) {
    final rec = r.recovery;
    if (rec == null) return (RingState.noData, 'No heart data');
    if (rec.calibrating) {
      return (
        RingState.calibrating,
        'Learning · night ${r.calibration.haveNights.clamp(0, r.calibration.needNights)} '
            'of ${r.calibration.needNights}',
      );
    }
    if (!r.calibration.established) {
      return (
        RingState.provisional,
        'Early estimate · night ${r.calibration.haveNights} of '
            '${r.calibration.needNights}',
      );
    }
    return (RingState.measured, null);
  }

  static String zoneHeadline(RecoveryZone z) => switch (z) {
    RecoveryZone.green => 'Good · ${RecoveryEngine.greenFrom}–99',
    RecoveryZone.yellow =>
      'Fair · ${RecoveryEngine.yellowFrom}–${RecoveryEngine.greenFrom - 1}',
    RecoveryZone.red => 'Low · 1–${RecoveryEngine.yellowFrom - 1}',
  };

  /// What the zone means, and the day's effort goal as a range. It describes
  /// the zone only (a score of 67 doesn't mean every signal was at or above
  /// your usual) and gives no advice: TodayPlan is the day's only narrator.
  static String meaning(
    RecoveryResult rec,
    StrainResult? strain, {
    required bool isToday,
  }) {
    final zone = switch (rec.zone) {
      RecoveryZone.green =>
        isToday ? 'You’ve recovered well.' : 'You had recovered well that day.',
      RecoveryZone.yellow =>
        isToday
            ? 'You’ve partly recovered.'
            : 'You had partly recovered that day.',
      RecoveryZone.red =>
        isToday
            ? 'You haven’t fully recovered.'
            : 'You hadn’t fully recovered that day.',
    };
    final t = strain?.targetStrain;
    if (t == null) return zone;
    final (lo, hi) = StrainEngine.targetRange(t);
    return isToday
        ? '$zone Effort goal today: $lo–$hi.'
        : '$zone Effort goal was $lo–$hi.';
  }

  static String _unit(String key) => switch (key) {
    'hrv' => 'ms',
    'rhr' || RecoveryEngine.sleepingHrKey => 'bpm',
    'resp' => 'breaths/min',
    _ => '%',
  };

  static int _decimals(String key) => key == 'resp' ? 1 : 0;

  /// The engine's points, with details in the one shared "usual".
  static List<Contribution> contributions(
    RecoveryResult rec,
    SleepAnalysis? sleep,
  ) {
    String fmt(String key, double v) => v.toStringAsFixed(_decimals(key));
    return [
      for (final c in rec.components)
        Contribution(
          label: labels[c.key] ?? c.label,
          points: c.points,
          maxPoints: c.weight * 100,
          detail: switch (c.key) {
            'sleep' =>
              sleep != null && sleep.hasData
                  ? '${c.value?.round() ?? 0}% of your sleep goal · '
                        '${_hm(sleep.sleptMinutes)} of ${_hm(sleep.needMinutes)}'
                  : '${c.value?.round() ?? 0}% of your sleep goal',
            _ =>
              c.value == null
                  ? c.detail
                  : c.baseline == null
                  ? '${fmt(c.key, c.value!)} ${_unit(c.key)} · still learning '
                        'your usual, so half points for now'
                  : '${fmt(c.key, c.value!)} ${_unit(c.key)} · usual '
                        '${fmt(c.key, c.baseline!.mean)} ${_unit(c.key)}',
          },
        ),
      for (final p in rec.penalties)
        Contribution(
          label: p.label,
          points: p.points,
          maxPoints: p.points,
          penalty: true,
        ),
    ];
  }

  /// "No breathing rate last night, so its 10 points went to your other
  /// signals."
  static String? reweightNote(RecoveryResult rec) {
    final present = {for (final c in rec.components) c.key};
    final missing = [
      for (final k in RecoveryEngine.weights.keys)
        if (!present.contains(k)) k,
    ];
    if (missing.isEmpty) return null;
    final pts = missing.fold(
      0.0,
      (a, k) => a + (RecoveryEngine.weights[k] ?? 0) * 100,
    );
    final names = missing.map((k) => _short[k]!).toList();
    final list = names.length == 1
        ? names.single
        : '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}';
    return 'No $list last night, so ${names.length == 1 ? 'its' : 'their'} '
        '${pts.round()} points went to your other signals.';
  }

  static String? neutralNote(RecoveryResult rec) {
    final neutral = [
      for (final c in rec.components)
        if (c.key != 'sleep' && c.baseline == null)
          _short[c.key] ?? c.label,
    ];
    if (neutral.isEmpty) return null;
    return 'Airlog is still learning your usual ${neutral.join(' and ')}, '
        'so ${neutral.length == 1 ? 'it gets' : 'they get'} half points for '
        'now.';
  }

  static HealthMetricStatus? _status(DayResult? r, HealthMetricKind k) {
    if (r == null) return null;
    for (final m in r.health.metrics) {
      if (m.kind == k) return m;
    }
    return null;
  }

  /// HRV, resting HR and respiratory rate inside the SAME band the Health
  /// Monitor uses; sleep performance without a band (it is measured against
  /// need, not against a personal baseline).
  static List<InputVm> inputs(
    DayBundle bundle,
    List<String> keys,
    Map<String, DayBundle> byDate,
  ) {
    final r = bundle.result;
    InputVm banded(String key, HealthMetricKind kind, Metric metric) {
      final s = _status(r, kind);
      return InputVm(
        key: key,
        label: labels[key]!,
        unit: kind.displayUnit,
        decimals: _decimals(key),
        values: [for (final k in keys) _status(byDate[k]?.result, kind)?.value],
        today: s?.value,
        mean: s?.baseline?.mean,
        sd: s?.baseline?.sd,
        lower: s?.lower,
        upper: s?.upper,
        state: s?.state,
        provenance: bundle.record.provenance[metric],
      );
    }

    return [
      banded('hrv', HealthMetricKind.hrv, Metric.hrv),
      banded('rhr', HealthMetricKind.restingHr, Metric.restingHr),
      InputVm(
        key: 'sleep',
        label: labels['sleep']!,
        unit: '%',
        decimals: 0,
        values: [
          for (final k in keys)
            switch (byDate[k]?.result.sleep) {
              final s? when s.hasData => s.performance,
              _ => null,
            },
        ],
        today: r.sleep != null && r.sleep!.hasData
            ? r.sleep!.performance
            : null,
        provenance: bundle.record.provenance[Metric.sleep],
        footnote:
            'No usual range here. This is how much of your sleep goal you got '
            '(100% means you met it).',
      ),
      banded('resp', HealthMetricKind.respiratoryRate, Metric.respiratoryRate),
    ];
  }

  static ReadinessVm? readiness(ReadinessSwc? s) {
    if (s == null) return null;
    return ReadinessVm(
      state: s.state,
      rollingMs: math.exp(s.lnRmssd7d),
      lowerMs: math.exp(s.swcLower),
      upperMs: math.exp(s.swcUpper),
      baselineMs: math.exp(s.baselineMean),
      cv: s.cv7d,
      swc: s,
    );
  }

  /// Notes about Recovery's own inputs; setup and strain notes live elsewhere.
  static List<StatusNote> notes(DayResult r) => [
    for (final n in r.notes)
      if (const {
            'recovery',
            'hrv',
            'rhr',
            'sleep',
            'resp',
            'spo2',
            'skin_temp',
          }.contains(n.metric) &&
          !Notes.isCalibrating(n))
        n,
  ];

  static String _hm(double minutes) {
    final t = minutes.round(), h = t ~/ 60, m = t % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
