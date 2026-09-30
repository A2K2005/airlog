// A conversation's topic, derived from the tools its answers used (never an
// LLM guess): the Conversations screen groups chats by it. Pure Dart.

import 'coach_contracts.dart';
import 'refs.dart' show CoachRoutes;
import 'tools.dart' show CoachTools;

enum ChatTopic {
  sleep('Sleep'),
  recovery('Recovery'),
  training('Training'),
  journal('Journal'),
  general('General');

  const ChatTopic(this.label);
  final String label;
}

abstract final class ChatTopics {
  static const _sleepMetrics = {
    'sleep_duration',
    'sleep_performance',
    'sleep_debt',
    'sleep_consistency',
  };
  static const _recoveryMetrics = {
    'recovery',
    'hrv',
    'resting_hr',
    'respiratory_rate',
    'spo2',
    'skin_temp',
  };
  static const _trainingMetrics = {'strain', 'steps'};

  /// The topic one tool call speaks to ('get_sleep', 'get_range:hrv'), or
  /// null when it is neutral (methodology, coverage, memory, a range whose
  /// metric is unknown).
  static ChatTopic? ofTool(String tool) {
    final i = tool.indexOf(':');
    final name = i < 0 ? tool : tool.substring(0, i);
    final metric = i < 0 ? null : tool.substring(i + 1);
    switch (name) {
      case CoachTools.sleep:
        return ChatTopic.sleep;
      case CoachTools.todaySummary ||
          CoachTools.day ||
          CoachTools.healthMonitor:
        return ChatTopic.recovery;
      case CoachTools.workouts || CoachTools.trainingLoad:
        return ChatTopic.training;
      case CoachTools.journalInsights:
        return ChatTopic.journal;
      case CoachTools.range || CoachTools.compare:
        if (metric == null) return null;
        if (_sleepMetrics.contains(metric)) return ChatTopic.sleep;
        if (_recoveryMetrics.contains(metric)) return ChatTopic.recovery;
        if (_trainingMetrics.contains(metric)) return ChatTopic.training;
        return null;
    }
    return null;
  }

  static ChatTopic? _ofRoute(String? route) => switch (route) {
    CoachRoutes.sleep => ChatTopic.sleep,
    CoachRoutes.recovery || CoachRoutes.trends => ChatTopic.recovery,
    CoachRoutes.strain => ChatTopic.training,
    CoachRoutes.journal => ChatTopic.journal,
    _ => null,
  };

  /// A day summary reads everything (recovery, sleep, strain), so it
  /// decides the topic only when nothing more specific was called.
  static bool _generic(String tool) {
    final name = tool.split(':').first;
    return name == CoachTools.todaySummary || name == CoachTools.day;
  }

  /// The topic of one answer's tool list: the most frequent specific
  /// topic (a tie goes to the first called), else a day summary's
  /// Recovery, else null.
  static ChatTopic? ofTools(List<String> tools) {
    final count = <ChatTopic, int>{};
    for (final t in tools) {
      if (_generic(t)) continue;
      final topic = ofTool(t);
      if (topic != null) count[topic] = (count[topic] ?? 0) + 1;
    }
    if (count.isNotEmpty) {
      var best = count.keys.first;
      for (final e in count.entries) {
        if (e.value > count[best]!) best = e.key;
      }
      return best;
    }
    return tools.any(_generic) ? ChatTopic.recovery : null;
  }

  /// One answer's topic: its recorded tools; for an answer stored before
  /// tools were recorded, the cloud's tool list, then the routes of its
  /// cited sources; null when none speaks to a topic.
  static ChatTopic? ofAnswer(ChatMessage a) {
    if (a.tools.isNotEmpty) return ofTools(a.tools);
    final bySent = ofTools(a.sent?.toolsCalled ?? const []);
    if (bySent != null) return bySent;
    final count = <ChatTopic, int>{};
    for (final r in a.refs) {
      final t = _ofRoute(r.route);
      if (t != null) count[t] = (count[t] ?? 0) + 1;
    }
    if (count.isEmpty) return null;
    var best = count.keys.first;
    for (final e in count.entries) {
      if (e.value > count[best]!) best = e.key;
    }
    return best;
  }

  /// The most frequent answer topic in [messages]; a tie goes to the
  /// earlier answer's topic; none at all is General.
  static ChatTopic ofConversation(List<ChatMessage> messages) {
    final count = <ChatTopic, int>{};
    final order = <ChatTopic>[];
    for (final m in messages) {
      if (m.role != ChatRole.assistant || m.error != null || m.safety) {
        continue;
      }
      final t = ofAnswer(m);
      if (t == null) continue;
      count[t] = (count[t] ?? 0) + 1;
      if (!order.contains(t)) order.add(t);
    }
    if (order.isEmpty) return ChatTopic.general;
    var best = order.first;
    for (final t in order) {
      if (count[t]! > count[best]!) best = t;
    }
    return best;
  }
}
