// Journal view-model: the evening's factor tags for one day (saved as you
// tap, optimistically) and what the engine found about each factor and the
// next morning's Recovery.
//
// Saves are serialised on one chain, so fast taps land in order; while any
// save is in flight the optimistic entry wins over what a reload reads back
// (each save bumps the repository revision, which re-runs build()).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/day_key.dart';
import '../../domain/engine/journal.dart';
import '../../domain/models.dart';
import '../../domain/results.dart';

class JournalState {
  const JournalState({
    required this.date,
    required this.today,
    required this.entry,
    required this.solid,
    required this.emerging,
    required this.missing,
    this.saveError = false,
    this.week = const [],
    this.clockDay,
  });

  /// The last seven evenings ending with [today], oldest first: whether each
  /// was logged (the Consistency tile). [redesign, additive]
  final List<(String, bool)> week;

  /// The clock's calendar day. Before 05:00 the evening being tagged is
  /// yesterday's, so the switcher names it by this day, not "Today" (QA-11).
  final String? clockDay;

  /// Evenings logged in [week].
  int get loggedThisWeek => week.where((w) => w.$2).length;

  /// The evening being tagged.
  final String date;

  /// The current evening ([eveningKeyOf] the clock (domain/day_key.dart)): the newest taggable.
  final String today;
  final JournalEntry entry;

  /// |Δ| > 2·SE, strongest first.
  final List<FactorInsight> solid;

  /// Enough days, but within noise.
  final List<FactorInsight> emerging;

  /// Factors without enough days with and without yet (minDays each).
  final List<JournalFactor> missing;

  /// The last save failed (the entry was reloaded from storage).
  final bool saveError;

  bool get isToday => date == today;
  bool get hasInsights => solid.isNotEmpty || emerging.isNotEmpty;

  JournalState copyWith({JournalEntry? entry, bool? saveError}) => JournalState(
    date: date,
    today: today,
    entry: entry ?? this.entry,
    solid: solid,
    emerging: emerging,
    missing: missing,
    saveError: saveError ?? this.saveError,
    week: [
      for (final w in week)
        w.$1 == date && entry != null ? (w.$1, entry.factors.isNotEmpty) : w,
    ],
    clockDay: clockDay,
  );
}

final journalViewModelProvider =
    AsyncNotifierProvider.autoDispose<JournalViewModel, JournalState>(
      JournalViewModel.new,
      retry: (_, _) => null,
    );

class JournalViewModel extends AsyncNotifier<JournalState> {
  /// Minimum days per group (from the engine, not retyped).
  static const minDays = JournalEngine.minDaysPerGroup;

  String? _date;
  JournalEntry? _optimistic;
  int _pending = 0;
  bool _saveError = false;
  Future<void> _chain = Future<void>.value();

  @override
  Future<JournalState> build() async {
    ref.watch(revisionProvider);
    final repo = ref.watch(healthRepositoryProvider);
    final now = ref.watch(currentTimeProvider);
    final today = eveningKeyOf(now);
    // The evening of the day being looked at elsewhere, else this evening
    // (never one that has not started).
    final picked = ref.read(selectedDateProvider);
    final date = _date ??= picked != null && picked.compareTo(today) < 0
        ? picked
        : today;
    final opt = _optimistic;
    final entry = opt != null && opt.date == date
        ? opt
        : await repo.journal(date);
    final insights = await repo.journalInsights();
    final week = <(String, bool)>[];
    for (var k = 6; k >= 0; k--) {
      final d = DayKey.add(today, -k);
      final e = d == date ? entry : await repo.journal(d);
      week.add((d, e.factors.isNotEmpty));
    }
    return JournalMapper.map(
      date: date,
      today: today,
      entry: entry,
      insights: insights,
      saveError: _saveError,
    ).withWeek(week, DayKey.of(now));
  }

  /// Tags or untags [f] for the shown evening and saves at once.
  void toggle(JournalFactor f) {
    final s = state.value;
    if (s == null) return;
    final next = s.entry.toggle(f);
    _optimistic = next;
    _saveError = false;
    _pending++;
    state = AsyncData(s.copyWith(entry: next, saveError: false));
    final repo = ref.read(healthRepositoryProvider);
    _chain = _chain
        .then((_) => repo.saveJournal(next))
        .then<void>(
          (_) {},
          onError: (Object _) {
            _saveError = true;
          },
        )
        .whenComplete(() {
          _pending--;
          if (_pending == 0) {
            _optimistic = null;
            if (_saveError) ref.invalidateSelf();
          }
        });
  }

  /// Steps the evening by ±1 day (never past today).
  void shift(int days) {
    final s = state.value;
    if (s == null) return;
    final next = DayKey.add(s.date, days);
    if (next.compareTo(s.today) > 0) return;
    _date = next;
    ref.invalidateSelf();
  }

  /// Completes when every queued save has finished (tests).
  Future<void> get settled => _chain;
}

abstract final class JournalMapper {
  static JournalState map({
    required String date,
    required String today,
    required JournalEntry entry,
    required List<FactorInsight> insights,
    bool saveError = false,
  }) {
    final seen = {for (final i in insights) i.factor};
    return JournalState(
      date: date,
      today: today,
      entry: entry,
      solid: [
        for (final i in insights)
          if (i.confidence == InsightConfidence.solid) i,
      ],
      emerging: [
        for (final i in insights)
          if (i.confidence == InsightConfidence.emerging) i,
      ],
      missing: [
        for (final f in JournalFactor.values)
          if (!seen.contains(f)) f,
      ],
      saveError: saveError,
    );
  }

  /// "Alcohol is associated with 24 points lower Recovery the next day".
  static String headline(FactorInsight i) {
    final d = i.delta.round();
    final pts = d.abs() == 1 ? 'point' : 'points';
    // "Associated with", never "causes" (PRODUCT_PLAN §7).
    if (d == 0) {
      return '${i.factor.label}: no difference in your next-day Recovery';
    }
    final dir = d > 0 ? 'higher' : 'lower';
    return '${i.factor.label} is associated with ${d.abs()} $pts $dir '
        'Recovery the next day';
  }

  /// "15 days with, 63 without · average 38% vs 62%".
  static String detail(FactorInsight i) =>
      '${i.daysWith} days with, ${i.daysWithout} without · '
      'average ${i.avgWith.round()}% vs ${i.avgWithout.round()}%';
}

extension on JournalState {
  JournalState withWeek(List<(String, bool)> week, String clockDay) =>
      JournalState(
        date: date,
        today: today,
        entry: entry,
        solid: solid,
        emerging: emerging,
        missing: missing,
        saveError: saveError,
        week: week,
        clockDay: clockDay,
      );
}
