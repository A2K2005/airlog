// The coach feature's shared pieces: the stored configuration every coach
// screen shows (engine, model, mode, length, key, memory switch), the one
// withdraw path, the launch arguments of a chat, and small pure helpers
// (the pre-filled question for an "Ask about this" screen, the default
// category of a proposed memory, a source's value as text).
//
// Nothing here is read in a widget build directly: the providers throw until
// main.dart (or a test) overrides the coach repository, and a failing
// provider must become an error state, not an exception on screen.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart';
import '../../app/copy.dart';
import '../../app/insight_card.dart' show sourceValue;
import '../../app/platform_services.dart';
import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/day_key.dart';

/// What the coach screens show about the stored setup.
class CoachConfig {
  const CoachConfig({
    this.settings = const CoachSettings(),
    this.hasKey = false,
    this.memoryOn = true,
    this.memoryCount = 0,
  });

  final CoachSettings settings;

  /// A key is stored for [settings]' provider (always false on-device).
  final bool hasKey;
  final bool memoryOn;
  final int memoryCount;

  CoachProvider get provider => settings.provider;
  bool get cloud => provider != CoachProvider.offline;

  /// A cloud engine with a key and a current consent.
  bool get cloudReady =>
      cloud &&
      hasKey &&
      settings.adultConfirmed &&
      settings.hasConsent &&
      (settings.consentVersion ?? 0) >= CoachCopy.consentVersion;

  /// Can a question be asked right now?
  bool get ready => settings.enabled && (!cloud || cloudReady);

  String get engineLabel =>
      CoachCopy.engineLabel(settings.provider, settings.model);
  String get modeLabel => CoachCopy.modeLabel(settings.mode);
}

final coachConfigProvider = FutureProvider.autoDispose<CoachConfig>((
  ref,
) async {
  final repo = ref.watch(coachRepositoryProvider);
  final s = await repo.settings();
  final hasKey = s.provider == CoachProvider.offline
      ? false
      : await repo.hasApiKey(s.provider);
  var memoryOn = true;
  var count = 0;
  try {
    memoryOn = await repo.memoryEnabled();
    count = (await repo.memories()).length;
  } catch (_) {}
  return CoachConfig(
    settings: s,
    hasKey: hasKey,
    memoryOn: memoryOn,
    memoryCount: count,
  );
}, retry: noRetry);

/// Turns the cloud engine off: deletes every stored key, switches back to
/// on-device and clears the consent. Chats and memories stay.
Future<CoachSettings> withdrawCloud(CoachRepository repo) async {
  final s = (await repo.settings()).copyWith(
    provider: CoachProvider.offline,
    clearModel: true,
    clearConsent: true,
  );
  // Stop new sends even if secure storage subsequently refuses deletion.
  await repo.saveSettings(s);
  var failed = false;
  for (final p in CoachProvider.values) {
    if (p == CoachProvider.offline) continue;
    try {
      await repo.deleteApiKey(p);
    } catch (_) {
      failed = true;
    }
  }
  if (failed) {
    throw const CoachException(
      CoachErrorKind.unknown,
      'Cloud is off, but a stored key could not be deleted. Try removing '
      'the key again in coach setup.',
    );
  }
  return s;
}

/// Saves the answer length.
Future<void> saveLength(CoachRepository repo, ResponseLength length) async {
  final s = await repo.settings();
  if (s.length == length) return;
  await repo.saveSettings(s.copyWith(length: length));
}

// ── launching a chat ──────────────────────────────────────────────────────

/// A chat's launch arguments, as a value (the chat view-model's key).
@immutable
class CoachLaunch {
  const CoachLaunch({
    this.screen,
    this.date,
    this.prefill,
    this.conversationId,
    this.insightId,
    this.seedText,
    this.seedRefs = const [],
  });

  /// From the route arguments: [CoachArgs], a bare [AskContext], or none.
  factory CoachLaunch.from(Object? args) => switch (args) {
    final CoachArgs a => CoachLaunch._of(
      a.context,
      prefill: a.prefill,
      conversationId: a.conversationId,
    ),
    final AskContext c => CoachLaunch._of(c),
    _ => const CoachLaunch(),
  };

  factory CoachLaunch._of(
    AskContext? c, {
    String? prefill,
    String? conversationId,
  }) => CoachLaunch(
    screen: c?.screen,
    date: c?.date,
    prefill: prefill,
    conversationId: conversationId,
    insightId: c?.insightId,
    seedText: c?.seedText,
    seedRefs: c?.seedRefs ?? const [],
  );

  final String? screen;
  final String? date;
  final String? prefill;
  final String? conversationId;

  /// "Discuss" from an insight card: the card's id, its text and its facts.
  /// The chat pins the card and passes all three to CoachService.ask.
  final String? insightId;
  final String? seedText;
  final List<SourceRef> seedRefs;

  /// Opened from an insight card's "Discuss".
  bool get discussing => insightId != null;

  /// The card's headline (the seed's first line).
  String? get discussHeadline {
    final t = seedText?.trim();
    if (t == null || t.isEmpty) return null;
    return t.split('\n').first.trim();
  }

  /// The card's body (the seed after its first line).
  String? get discussBody {
    final t = seedText?.trim();
    if (t == null) return null;
    final i = t.indexOf('\n');
    if (i < 0) return null;
    final b = t.substring(i + 1).trim();
    return b.isEmpty ? null : b;
  }

  /// The screen and day without the card: once a Discuss session ends
  /// (History, New chat), questions no longer carry the card's seed.
  AskContext? get plainContext => screen == null && date == null
      ? null
      : AskContext(screen: screen, date: date);

  AskContext? get context => screen == null && date == null && insightId == null
      ? null
      : AskContext(
          screen: screen,
          date: date,
          insightId: insightId,
          seedText: seedText,
          seedRefs: seedRefs,
        );

  @override
  bool operator ==(Object other) =>
      other is CoachLaunch &&
      other.screen == screen &&
      other.date == date &&
      other.prefill == prefill &&
      other.conversationId == conversationId &&
      other.insightId == insightId &&
      other.seedText == seedText;

  @override
  int get hashCode =>
      Object.hash(screen, date, prefill, conversationId, insightId, seedText);
}

/// Three follow-ups for a card opened with "Discuss", by the card's kind
/// (an InsightKind name). Tapping one fills the composer; nothing is sent
/// until the user taps send. No streak language, and nothing that asks for
/// the day's overall state or effort plan: TodayPlan alone narrates that.
List<String> discussFollowUps(String? kind) => switch (kind) {
  'sleep' => const [
    'What shaped my sleep last night?',
    'How does this compare with my usual week?',
    'What could help tonight?',
  ],
  'recovery' => const [
    'What drove this Recovery?',
    'How has my HRV changed this week?',
    'How does this compare with last week?',
  ],
  'strain' || 'workout' => const [
    'Was that a lot for my Recovery today?',
    'How does this compare with my usual week?',
    'What should tomorrow look like?',
  ],
  'healthMonitor' => const [
    'What does this mean?',
    'Which numbers moved the most?',
    'How has this changed this week?',
  ],
  'weekly' => const [
    'What went well this week?',
    'What should I focus on next week?',
    'How consistent was my sleep?',
  ],
  _ => const [
    'Tell me more about this',
    'What should I do about it?',
    'How does this compare with my usual?',
  ],
};

/// Follow-ups under the latest answer, from what it cited (deterministic;
/// never the question just asked). Tapping one fills the composer.
List<String> answerFollowUps(ChatMessage answer, {String? asked}) {
  // The topic is the first source the answer cites.
  final topic = answer.refs.map(refRoute).whereType<String>().firstOrNull;
  final List<String> pool;
  if (topic == Routes.sleep) {
    pool = const [
      'How does my sleep compare with my usual week?',
      'What could help tonight?',
      'How is my Recovery today?',
    ];
  } else if (topic == Routes.strain) {
    pool = const [
      'Was that a lot for my Recovery?',
      'What should tomorrow look like?',
      'How did I sleep last night?',
    ];
  } else if (topic == Routes.recovery) {
    pool = const [
      'Which habits help my Recovery most?',
      'How did I sleep last night?',
      'How does this compare with last week?',
    ];
  } else {
    pool = const [
      'How did I sleep last night?',
      'How is my Recovery today?',
      'What changed in my trends lately?',
    ];
  }
  final q = asked?.trim().toLowerCase();
  return [
    for (final p in pool)
      if (p.toLowerCase() != q) p,
  ].take(3).toList();
}

/// Today's cloud usage against the daily budget, or null (on-device, not
/// tracked, or unreadable).
final coachUsageProvider = FutureProvider.autoDispose<CoachUsage?>((ref) async {
  try {
    return await ref.watch(coachRepositoryProvider).usageToday();
  } catch (_) {
    return null;
  }
}, retry: noRetry);

/// The question an "Ask about this" button pre-fills, for [screen] on [date]
/// ([today] = the phone's day). No numbers: the coach looks them up.
String? prefillFor(String? screen, String? date, String today) {
  final isToday = date == null || date == today;
  final day = isToday ? null : shortDay(date);
  return switch (screen) {
    'today' => isToday ? 'How am I doing today?' : 'How was $day for me?',
    'recovery' =>
      isToday
          ? 'What drove my Recovery today?'
          : 'What drove my Recovery on $day?',
    'sleep' =>
      isToday ? 'How did I sleep last night?' : 'How did I sleep on $day?',
    'strain' =>
      isToday ? 'How hard did I push today?' : 'How hard did I push on $day?',
    'trends' => 'What has changed in my trends lately?',
    'journal' => 'Which of my habits affect my Recovery?',
    _ => null,
  };
}

/// A first guess at a proposed memory's category; the user can change it
/// before anything is saved.
MemoryCategory guessCategory(String text) {
  final t = text.toLowerCase();
  bool has(List<String> words) => words.any(t.contains);
  if (has(['injur', 'surgery', 'asthma', 'condition', 'diagnos', 'illness'])) {
    return MemoryCategory.healthHistory;
  }
  if (has(['race', 'marathon', 'trip', 'wedding', 'travel', ' on ', 'until'])) {
    return MemoryCategory.events;
  }
  if (has(['goal', 'training for', 'want to', 'aim', 'target'])) {
    return MemoryCategory.goals;
  }
  if (has(['stress', 'anxious', 'mood', 'feeling', 'happy', 'sad'])) {
    return MemoryCategory.mood;
  }
  if (has(['shift', 'baby', 'newborn', 'work', 'commute', 'kids', 'dog'])) {
    return MemoryCategory.lifestyle;
  }
  if (has(['i am', "i'm", 'years old', 'vegetarian', 'vegan'])) {
    return MemoryCategory.identity;
  }
  return MemoryCategory.preferences;
}

/// A source's value as the chip prints it: "64 %", "52 ms", "6h 40m",
/// "11.2". Null when the source carries no number.
String? refValue(SourceRef r) => sourceValue(r);

/// Routes a source chip can open: pushed detail screens, and the day tabs
/// pushed as pages (back returns to the chat).
const coachRefRoutes = {
  Routes.recovery,
  Routes.journal,
  Routes.sleep,
  Routes.strain,
  Routes.trends,
  Routes.today,
};

/// The route a source opens, normalised ('recovery' → '/recovery'), or null
/// when it opens nothing.
String? refRoute(SourceRef r) {
  final raw = r.route?.trim();
  if (raw == null || raw.isEmpty) return null;
  final route = raw.startsWith('/') ? raw : '/$raw';
  return coachRefRoutes.contains(route) ? route : null;
}

/// Opens [r]'s screen with its day selected.
Future<void> openRef(BuildContext context, WidgetRef ref, SourceRef r) async {
  final route = refRoute(r);
  if (route == null) return;
  final date = r.date;
  if (date != null && _isDay(date)) {
    final latest = ref.read(latestDateProvider).value;
    ref
        .read(selectedDateProvider.notifier)
        .select(latest != null && date.compareTo(latest) >= 0 ? null : date);
  }
  await Navigator.of(context).pushNamed(route);
}

bool _isDay(String s) {
  try {
    return DayKey.of(DayKey.start(s)) == s;
  } catch (_) {
    return false;
  }
}
