// Storage primitives behind CoachRepositoryImpl and InsightServiceImpl:
// settings, conversations, messages, memories, the daily usage meter and the
// insight-card cache. Two implementations: SQLite (sqlite_coach_store.dart,
// the app) and memory (below, tests and goldens).
//
// API keys are NOT here: they live only in a SecretStore (Android keystore
// through flutter_secure_storage). Nothing in this store is exported.

import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/insight_contracts.dart';

/// One day's cloud usage for one provider.
class UsageRow {
  const UsageRow({
    this.requests = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });
  final int requests;
  final int inputTokens;
  final int outputTokens;

  UsageRow plus(int input, int output) => UsageRow(
    requests: requests + 1,
    inputTokens: inputTokens + input,
    outputTokens: outputTokens + output,
  );
}

/// A cached insight card and the key it was built for.
class CachedInsight {
  const CachedInsight({
    required this.id,
    required this.date,
    required this.revision,
    required this.algoVersion,
    required this.level,
    required this.json,
  });
  final String id;
  final String date;
  final int revision;
  final int algoVersion;
  final InsightLevel level;
  final Map<String, dynamic> json;
}

abstract class CoachStore {
  /// Small key/value settings (JSON strings). Keys are coach-prefixed.
  Future<String?> getValue(String key);
  Future<void> setValue(String key, String? value);

  Future<List<Conversation>> conversations();
  Future<Conversation?> conversation(String id);
  Future<void> putConversation(Conversation c);
  Future<List<ChatMessage>> messages(String conversationId);
  Future<void> putMessage(ChatMessage m);
  Future<void> deleteConversation(String id);
  Future<void> deleteAllConversations();

  Future<List<MemoryFact>> memories();
  Future<void> putMemory(MemoryFact m);
  Future<void> deleteMemory(String id);
  Future<void> deleteAllMemories();

  Future<UsageRow> usage(String day, CoachProvider p);
  Future<void> putUsage(String day, CoachProvider p, UsageRow row);

  /// Cached cards for [date] (any key); the service picks the current one.
  Future<List<CachedInsight>> insights(String date);
  Future<void> putInsight(CachedInsight c);
  Future<Map<String, InsightFeedback>> feedback();
  Future<void> putFeedback(String insightId, InsightFeedback f);
  Future<void> deleteAllInsights();
}

/// In-memory [CoachStore].
class MemoryCoachStore implements CoachStore {
  final Map<String, String> _kv = {};
  final Map<String, Conversation> _convs = {};
  final Map<String, List<ChatMessage>> _msgs = {};
  final Map<String, MemoryFact> _mems = {};
  final Map<String, UsageRow> _usage = {};
  final Map<String, CachedInsight> _insights = {};
  final Map<String, InsightFeedback> _feedback = {};

  @override
  Future<String?> getValue(String key) async => _kv[key];

  @override
  Future<void> setValue(String key, String? value) async =>
      value == null ? _kv.remove(key) : _kv[key] = value;

  @override
  Future<List<Conversation>> conversations() async =>
      _convs.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<Conversation?> conversation(String id) async => _convs[id];

  @override
  Future<void> putConversation(Conversation c) async {
    _convs[c.id] = c;
    _msgs.putIfAbsent(c.id, () => []);
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => [
    ...?_msgs[conversationId],
  ];

  @override
  Future<void> putMessage(ChatMessage m) async {
    final l = _msgs.putIfAbsent(m.conversationId, () => []);
    final i = l.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      l[i] = m;
    } else {
      l.add(m);
    }
  }

  @override
  Future<void> deleteConversation(String id) async {
    _convs.remove(id);
    _msgs.remove(id);
  }

  @override
  Future<void> deleteAllConversations() async {
    _convs.clear();
    _msgs.clear();
  }

  @override
  Future<List<MemoryFact>> memories() async =>
      _mems.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> putMemory(MemoryFact m) async => _mems[m.id] = m;

  @override
  Future<void> deleteMemory(String id) async => _mems.remove(id);

  @override
  Future<void> deleteAllMemories() async => _mems.clear();

  @override
  Future<UsageRow> usage(String day, CoachProvider p) async =>
      _usage['$day/${p.name}'] ?? const UsageRow();

  @override
  Future<void> putUsage(String day, CoachProvider p, UsageRow row) async =>
      _usage['$day/${p.name}'] = row;

  @override
  Future<List<CachedInsight>> insights(String date) async => [
    for (final c in _insights.values)
      if (c.date == date) c,
  ];

  @override
  Future<void> putInsight(CachedInsight c) async =>
      _insights['${c.id}|${c.revision}|${c.algoVersion}|${c.level.name}'] = c;

  @override
  Future<Map<String, InsightFeedback>> feedback() async => {..._feedback};

  @override
  Future<void> putFeedback(String insightId, InsightFeedback f) async =>
      _feedback[insightId] = f;

  @override
  Future<void> deleteAllInsights() async {
    _insights.clear();
    _feedback.clear();
  }
}
