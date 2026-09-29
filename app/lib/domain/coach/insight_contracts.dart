// Insight cards on DETAIL screens (Recovery, Sleep, Strain, workout): a plain-
// words read of that screen's data. Never on Today; TodayPlan owns the day.
//
// CONTRACT FILE (orchestrator): additive changes only, report them.
// Pure Dart.
//
// Rules every implementation keeps (research/07 §3–4, research/06 §8):
//  * InsightLevel.basic (the default) = on-device templates only. No network.
//  * InsightLevel.full is NOT OFFERED in v1 (PRODUCT_PLAN §7, critic review):
//    services treat it as basic, and the UI offers Off / On only. Original
//    design, kept for later: a template first, then an LLM rewrite. It needs coach
//    consent, CoachMode.useMyData and a configured provider. Google Health
//    API values are never sent. The rewrite must pass the verifier (numbers,
//    dates, events and output policy) or the template stays.
//  * Shown only on detail screens, never as a Today feed (PRODUCT_PLAN
//    principle 3). At most one card per kind per day, or one per workout.
//    Full-level cards carry a visible "AI summary" label. When
//    CoachSettings.enabled ("Show coach") is off, watchDay emits [].
//  * Cached per (id, data revision, algoVersion, level). Opening a screen
//    never regenerates, and nothing calls a cloud model from background
//    sync / workmanager.
//  * Health Monitor alerts keep their fixed, non-diagnostic copy. They are
//    never LLM-written.
//  * Any memory used is listed in [Insight.usedMemoryIds] so the card can
//    show it and let the user delete it.

import 'coach_contracts.dart';

enum InsightKind { sleep, recovery, strain, workout, healthMonitor, weekly }

/// Who wrote the card's text.
enum InsightSource { template, llm }

enum InsightFeedback { none, helpful, notHelpful, hidden }

/// Settings → Coach → "Coach messages" (Google Health's full/basic split).
enum InsightLevel {
  off('Off'),
  basic('Basic (on-device)'),
  full('Full (uses your AI provider)');

  const InsightLevel(this.label);
  final String label;
}

/// A labelled line under the body, e.g. ('Intensity', 'Mostly zone 2 …').
class InsightBullet {
  const InsightBullet(this.label, this.text);
  final String label;
  final String text;

  Map<String, dynamic> toJson() => {'label': label, 'text': text};
  factory InsightBullet.fromJson(Map<String, dynamic> j) =>
      InsightBullet(j['label'] as String, j['text'] as String);
}

class Insight {
  const Insight({
    required this.id,
    required this.kind,
    required this.date,
    required this.createdAt,
    required this.headline,
    required this.body,
    this.bullets = const [],
    this.metrics = const [],
    this.refs = const [],
    this.source = InsightSource.template,
    this.usedMemoryIds = const [],
    this.verification,
    this.feedback = InsightFeedback.none,
    this.revision,
    this.algoVersion,
    this.route,
  });

  /// Stable: `kind:yyyy-MM-dd` or `kind:yyyy-MM-dd:workoutId`.
  final String id;
  final InsightKind kind;

  /// The day the card is about (yyyy-MM-dd).
  final String date;

  /// When the card became true (wake time, workout end). Orders the feed.
  final DateTime createdAt;

  final String headline;
  final String body;
  final List<InsightBullet> bullets;

  /// Headline numbers shown as chips (for example "Asleep 6 h 10 m").
  /// A subset of [refs].
  final List<SourceRef> metrics;

  /// Every fact the text relies on. It seeds the chat on "Discuss".
  final List<SourceRef> refs;

  final InsightSource source;
  final List<String> usedMemoryIds;
  final Verification? verification;
  final InsightFeedback feedback;

  /// The data revision and algorithm version the card was built from.
  final int? revision;
  final int? algoVersion;

  /// Detail route opened by tapping the card, e.g. '/sleep'.
  final String? route;

  /// What "Discuss" hands to the chat, so its first reply uses the card's
  /// own facts instead of re-deriving (and possibly contradicting) them.
  AskContext toAskContext() => AskContext(
    screen: kind.name,
    date: date,
    insightId: id,
    seedText: '$headline\n$body',
    seedRefs: refs,
  );

  Insight copyWith({
    String? headline,
    String? body,
    List<InsightBullet>? bullets,
    InsightSource? source,
    List<String>? usedMemoryIds,
    Verification? verification,
    InsightFeedback? feedback,
  }) => Insight(
    id: id,
    kind: kind,
    date: date,
    createdAt: createdAt,
    headline: headline ?? this.headline,
    body: body ?? this.body,
    bullets: bullets ?? this.bullets,
    metrics: metrics,
    refs: refs,
    source: source ?? this.source,
    usedMemoryIds: usedMemoryIds ?? this.usedMemoryIds,
    verification: verification ?? this.verification,
    feedback: feedback ?? this.feedback,
    revision: revision,
    algoVersion: algoVersion,
    route: route,
  );
}

/// Implemented in data/coach. Read by the detail screens (Recovery, Sleep,
/// Strain, workout). It is reached only through `insightServiceProvider`.
abstract class InsightService {
  /// Cards for [date], newest first, not hidden. The stream emits the cached
  /// or template version at once. At InsightLevel.full it emits again when a
  /// verified rewrite is ready, and again after a sync changes the inputs.
  /// It never throws; a failed rewrite leaves the template in place.
  Stream<List<Insight>> watchDay(String date);

  Future<void> setFeedback(String insightId, InsightFeedback feedback);

  Future<InsightLevel> level();
  Future<void> setLevel(InsightLevel level);
}
