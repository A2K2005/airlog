// InsightServiceImpl: proactive insight cards for the detail screens
// (Recovery, Sleep, Strain, workout detail). Rules in insight_contracts.dart
// and the v1 product decisions (PRODUCT_PLAN §7):
//
//   * CoachSettings.enabled false ("Show coach" off) or InsightLevel.off →
//     an empty list.
//   * Cards are deterministic on-device templates (insight_templates.dart).
//     No network, ever. InsightLevel.full is CUT from v1: it is treated as
//     basic, and no card is rewritten by a model.
//   * Cached per (id, data revision, algoVersion, level) in SQLite; the data
//     revision is a hash of the card's own numbers, so opening a screen or a
//     sync that changes nothing else never regenerates.
//   * Nothing here runs from sync or workmanager: cards are built only
//     while a screen is listening to watchDay().
//   * Hidden cards are filtered; feedback is persisted.

import 'dart:async';

import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/insight_contracts.dart';
import '../../domain/day_key.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import 'coach_store.dart';
import 'insight_templates.dart';

class InsightServiceImpl implements InsightService {
  InsightServiceImpl({
    required this.health,
    required this.coach,
    required this.store,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final HealthRepository health;
  final CoachRepository coach;
  final CoachStore store;
  final DateTime Function() clock;

  static const levelKey = 'coach.insight_level';

  final _changes = StreamController<void>.broadcast();

  @override
  Future<InsightLevel> level() async {
    final v = await store.getValue(levelKey);
    return InsightLevel.values.firstWhere(
      (l) => l.name == v,
      orElse: () => InsightLevel.basic,
    );
  }

  @override
  Future<void> setLevel(InsightLevel level) async {
    await store.setValue(levelKey, level.name);
    _changes.add(null);
  }

  @override
  Future<void> setFeedback(String insightId, InsightFeedback feedback) async {
    await store.putFeedback(insightId, feedback);
    _changes.add(null);
  }

  @override
  Stream<List<Insight>> watchDay(String date) {
    late final StreamController<List<Insight>> ctl;
    StreamSubscription<int>? revs;
    StreamSubscription<void>? changes;
    var gen = 0;

    Future<void> emit() async {
      final g = ++gen;
      bool live() => g == gen && !ctl.isClosed;
      try {
        final list = await cards(date);
        if (live()) ctl.add(list);
      } catch (_) {
        // Never throws: an empty feed beats an error on a detail screen.
        if (live()) ctl.add(const []);
      }
    }

    ctl = StreamController<List<Insight>>(
      onListen: () {
        unawaited(emit());
        revs = health.revisions.listen((_) => unawaited(emit()));
        changes = _changes.stream.listen((_) => unawaited(emit()));
      },
      onCancel: () async {
        await revs?.cancel();
        await changes?.cancel();
      },
    );
    return ctl.stream;
  }

  /// The cards for [date] (newest first, hidden ones removed).
  Future<List<Insight>> cards(String date) async {
    final settings = await coach.settings();
    final lvl = await level();
    if (!settings.enabled || lvl == InsightLevel.off) return const [];
    // v1: "full" is not offered; it behaves exactly like basic.
    const key = InsightLevel.basic;
    final b = await health.day(date);
    if (b == null) return const [];
    final week = DayKey.start(date).weekday == DateTime.sunday
        ? await health.range(DayKey.add(date, -6), date)
        : const <DayBundle>[];
    final memories = await _activeMemories(date);
    final drafts = InsightTemplates.build(b, week: week, memories: memories);
    final cached = {
      for (final c in await store.insights(date))
        '${c.id}|${c.revision}|${c.algoVersion}|${c.level.name}': c,
    };
    final feedback = await store.feedback();
    final out = <Insight>[];
    for (final d in drafts) {
      final i = d.insight;
      final k = '${i.id}|${i.revision}|${i.algoVersion}|${key.name}';
      final hit = cached[k];
      final card = hit != null ? _fromJson(hit.json, i) : i;
      if (hit == null) {
        await store.putInsight(
          CachedInsight(
            id: i.id,
            date: date,
            revision: i.revision ?? 0,
            algoVersion: i.algoVersion ?? kAlgoVersion,
            level: key,
            json: _toJson(card),
          ),
        );
      }
      final f = feedback[i.id] ?? InsightFeedback.none;
      if (f == InsightFeedback.hidden) continue;
      out.add(card.copyWith(feedback: f));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<List<MemoryFact>> _activeMemories(String date) async {
    if (!await coach.memoryEnabled()) return const [];
    return [
      for (final m in await coach.memories())
        if (m.expiresOn == null || m.expiresOn!.compareTo(date) >= 0) m,
    ];
  }

  // ── Cache (de)serialisation: only the text parts can differ ────────────

  static Map<String, dynamic> _toJson(Insight i) => {
    'headline': i.headline,
    'body': i.body,
    'bullets': [for (final b in i.bullets) b.toJson()],
    'source': i.source.name,
    if (i.verification != null) 'verification': i.verification!.toJson(),
    'usedMemoryIds': i.usedMemoryIds,
  };

  static Insight _fromJson(Map<String, dynamic> j, Insight template) =>
      template.copyWith(
        headline: j['headline'] as String? ?? template.headline,
        body: j['body'] as String? ?? template.body,
        bullets: [
          for (final b in (j['bullets'] as List? ?? const []))
            InsightBullet.fromJson(b as Map<String, dynamic>),
        ],
        source: InsightSource.values.firstWhere(
          (s) => s.name == j['source'],
          orElse: () => InsightSource.template,
        ),
        verification: j['verification'] == null
            ? null
            : Verification.fromJson(j['verification'] as Map<String, dynamic>),
        usedMemoryIds: (j['usedMemoryIds'] as List? ?? const []).cast<String>(),
      );

  Future<void> dispose() => _changes.close();
}
