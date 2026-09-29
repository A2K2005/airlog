// Sleep view-model: the focused night (hypnogram, naps, slept vs need with
// the need's parts, debt, efficiency, stages), bed/wake consistency over 14
// or 30 nights, and tonight's bedtime recommendation.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/charts/scatter_consistency.dart' show NightWindow;
import '../../domain/day_key.dart';
import '../../domain/engine/engine.dart' show SleepConfig;
import '../../domain/engine/sleep.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';

enum SleepContent {
  /// The store is empty.
  noData,

  /// Nothing at all for the focused day.
  emptyDay,

  /// The day exists but no sleep session arrived.
  noSleep,
  ready,
}

class NapVm {
  const NapVm(this.start, this.end, this.asleepMinutes);
  final DateTime start, end;
  final double asleepMinutes;
}

/// Tonight's recommendation, as clock text.
class BedtimeVm {
  const BedtimeVm({
    required this.bedtime,
    required this.wake,
    required this.needMinutes,
    required this.debtMinutes,
    required this.debtShareMinutes,
    required this.strainMinutes,
  });

  /// "21:45" / "06:51".
  final String bedtime, wake;
  final double needMinutes, debtMinutes, debtShareMinutes, strainMinutes;
}

class SleepState {
  const SleepState({
    required this.content,
    required this.today,
    this.date,
    this.latest,
    this.earliest,
    this.analysis,
    this.stages = const [],
    this.start,
    this.end,
    this.naps = const [],
    this.debtBefore,
    this.nights = const [],
    this.rangeDays = 14,
    this.bedtime,
    this.notes = const [],
  });

  final SleepContent content;
  final String today;
  final String? date, latest, earliest;
  final SleepAnalysis? analysis;

  /// Main sleep stages and its window.
  final List<StageSpan> stages;
  final DateTime? start, end;
  final List<NapVm> naps;

  /// Debt carried INTO the night (the previous day's debt after), if known.
  final double? debtBefore;

  /// 30 nights, dense, oldest first; the focused night last.
  final List<NightWindow?> nights;

  /// How many of [nights] the consistency chart shows (14 or 30).
  final int rangeDays;
  final BedtimeVm? bedtime;
  final List<StatusNote> notes;

  bool get isLatest => date != null && date == latest;
  bool get isToday => date != null && date == today;

  List<NightWindow?> get shownNights => nights.length <= rangeDays
      ? nights
      : nights.sublist(nights.length - rangeDays);

  /// Change in debt over the night (+ = grew).
  double? get debtChange {
    final a = analysis, b = debtBefore;
    if (a == null || b == null) return null;
    return a.debtAfterMinutes - b;
  }

  /// Deep + REM share of time asleep (main sleep), 0…100.
  double? get restorativePct {
    final a = analysis;
    if (a == null || !a.hasStageData) return null;
    final asleep = [
      SleepStage.light,
      SleepStage.deep,
      SleepStage.rem,
    ].fold(0.0, (t, s) => t + (a.stageMinutes[s] ?? 0));
    if (asleep <= 0) return null;
    return a.restorativeMinutes / asleep * 100;
  }

  SleepState copyWith({int? rangeDays}) => SleepState(
    content: content,
    today: today,
    date: date,
    latest: latest,
    earliest: earliest,
    analysis: analysis,
    stages: stages,
    start: start,
    end: end,
    naps: naps,
    debtBefore: debtBefore,
    nights: nights,
    rangeDays: rangeDays ?? this.rangeDays,
    bedtime: bedtime,
    notes: notes,
  );
}

final sleepViewModelProvider =
    AsyncNotifierProvider.autoDispose<SleepViewModel, SleepState>(
      SleepViewModel.new,
      retry: (_, _) => null,
    );

class SleepViewModel extends AsyncNotifier<SleepState> {
  static const windowDays = 30;

  /// Kept across reloads (a sync must not reset the user's choice).
  int _range = 14;

  @override
  Future<SleepState> build() async {
    ref.watch(revisionProvider);
    final repo = ref.watch(healthRepositoryProvider);
    final now = ref.watch(currentTimeProvider);
    final dateF = ref.watch(focusedDateProvider.future);
    final latestF = ref.watch(latestDateProvider.future);
    final date = await dateF;
    final today = DayKey.of(now);
    if (date == null) {
      return SleepState(content: SleepContent.noData, today: today);
    }
    final latest = await latestF ?? date;
    final bundle = await repo.day(date);
    final window = await repo.range(DayKey.add(date, -(windowDays - 1)), date);
    return SleepMapper.map(
      date: date,
      latest: latest,
      today: today,
      bundle: bundle,
      window: window,
      rangeDays: _range,
      evening: eveningKeyOf(now),
    );
  }

  void shift(int days) {
    final latest = state.value?.latest;
    if (latest == null) return;
    ref.read(selectedDateProvider.notifier).shift(days, latest: latest);
  }

  void showLatest() => ref.read(selectedDateProvider.notifier).select(null);

  /// 14 or 30 nights in the consistency chart (no reload).
  void setRange(int days) {
    _range = days;
    final s = state.value;
    if (s != null) state = AsyncData(s.copyWith(rangeDays: days));
  }

  Future<void> refresh() => ref.read(healthRepositoryProvider).syncNow();
}

abstract final class SleepMapper {
  static SleepState map({
    required String date,
    required String latest,
    required String today,
    required DayBundle? bundle,
    required List<DayBundle> window,
    int rangeDays = 14,
    String? evening,
  }) {
    final windowStart = DayKey.add(date, -(SleepViewModel.windowDays - 1));
    final first = window.isEmpty ? null : window.first.date;
    final earliest = first != null && first.compareTo(windowStart) > 0
        ? first
        : null;
    final keys = DayKey.range(windowStart, date);
    final byDate = {for (final b in window) b.date: b};
    final nights = [
      for (final k in keys)
        switch (byDate[k]?.record.mainSleep) {
          final m? when m.end.isAfter(m.start) => NightWindow(m.start, m.end),
          _ => null,
        },
    ];
    if (bundle == null) {
      return SleepState(
        content: SleepContent.emptyDay,
        today: today,
        date: date,
        latest: latest,
        earliest: earliest,
        nights: nights,
        rangeDays: rangeDays,
      );
    }
    final a = bundle.result.sleep;
    final main = bundle.record.mainSleep;
    final notes = [
      for (final n in bundle.result.notes)
        if (n.metric == 'sleep') n,
    ];
    final prev = byDate[DayKey.add(date, -1)]?.result.sleep?.debtAfterMinutes;
    final hasSleep = a != null && a.hasData && main != null;
    return SleepState(
      content: hasSleep ? SleepContent.ready : SleepContent.noSleep,
      today: today,
      date: date,
      latest: latest,
      earliest: earliest,
      analysis: a,
      stages: main?.stages ?? const [],
      start: main?.start,
      end: main?.end,
      naps: [
        for (final n in bundle.record.naps)
          NapVm(n.start, n.end, n.minutesAsleep),
      ]..sort((x, y) => x.start.compareTo(y.start)),
      debtBefore: prev,
      nights: nights,
      rangeDays: rangeDays,
      // Only for the night ahead: the current evening's day (a stale
      // "latest" from before this morning's sync is last night's advice).
      bedtime: date == evening
          ? bedtime(bundle.result.bedtime, bundle.result.strain)
          : null,
      notes: notes,
    );
  }

  /// The engine's recommendation; the debt share is re-derived with the
  /// engine's own need function so the sheet can show the parts.
  static BedtimeVm? bedtime(BedtimeRecommendation? b, StrainResult? strain) {
    final bed = b?.recommendedBedtimeMinutes, wake = b?.habitualWakeMinutes;
    if (b == null || bed == null || wake == null) return null;
    final s = strain == null || strain.method == StrainMethod.none
        ? 0.0
        : strain.strain;
    final parts = SleepEngine.need(b.debtMinutes, s, const SleepConfig());
    return BedtimeVm(
      bedtime: clock(bed),
      wake: clock(wake),
      needMinutes: b.projectedNeedMinutes,
      debtMinutes: b.debtMinutes,
      debtShareMinutes: parts.debtMinutes,
      strainMinutes: parts.strainMinutes,
    );
  }

  /// Minutes since midnight (any range) → "21:45".
  static String clock(double minutes) {
    final t = ((minutes.round() % 1440) + 1440) % 1440;
    return '${(t ~/ 60).toString().padLeft(2, '0')}:'
        '${(t % 60).toString().padLeft(2, '0')}';
  }
}

/// "7h 2m" / "45m".
String sleepHm(double minutes) {
  if (!minutes.isFinite) return '';
  final t = minutes.round(), h = t ~/ 60, m = t % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
