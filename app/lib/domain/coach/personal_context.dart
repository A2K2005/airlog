import '../day_key.dart';
import 'coach_contracts.dart';

/// Small, deterministic retrieval plan, not a generated biography. The
/// existing tool executor still owns provenance, missing data and consent.
abstract final class PersonalContext {
  static List<ToolCall> plan(
    String question,
    String today, {
    required bool memory,
  }) {
    final q = question.toLowerCase();
    final personal = RegExp(
      r'\b(my|me|i|should|recommend|plan|lately|improve|improving|progress|trend)\b',
    ).hasMatch(q);
    if (!personal) return const [];
    final sleep = RegExp(r'\b(sleep|bed|rested|tired|fatigue)\b').hasMatch(q);
    final training = RegExp(
      r'\b(train|training|workout|exercise|strain|run|running|race)\b',
    ).hasMatch(q);
    final journal = RegExp(
      r'\b(alcohol|caffeine|stress|travel|journal|habit|habits|sick)\b',
    ).hasMatch(q);
    final broad = RegExp(
      r'\b(should|recommend|plan|lately|improve|improving|progress|trend)\b|how am i|know about me',
    ).hasMatch(q);
    if (!sleep && !training && !journal && !broad) return const [];
    return [
      if (memory)
        const ToolCall(id: 'context_memory', name: 'get_memories', input: {}),
      const ToolCall(id: 'context_today', name: 'get_today_summary', input: {}),
      ToolCall(
        id: 'context_trend',
        name: 'get_range',
        input: {
          'metric': sleep
              ? 'sleep_duration'
              : training
              ? 'strain'
              : 'recovery',
          'from': DayKey.add(today, -27),
          'to': today,
        },
      ),
      if (journal)
        const ToolCall(
          id: 'context_journal',
          name: 'get_journal_insights',
          input: {},
        )
      else if (training)
        ToolCall(
          id: 'context_load',
          name: 'get_training_load',
          input: {'date': today},
        ),
    ];
  }
}

/// Review intervals are product heuristics, not clinical thresholds. A stale
/// fact is not false, but must be reconfirmed before treating it as current.
abstract final class MemoryContext {
  // Conservative: don't try to infer which old fact an explicit correction
  // contradicts. Omit saved memory/history for this turn and use the user's
  // current words. Persistent edits still require the memory editor.
  static bool isCorrection(String question) => RegExp(
    r'\b(actually|correction|no longer|not anymore|i meant|i now|instead|i don.t|i do not)\b',
    caseSensitive: false,
  ).hasMatch(question);

  static bool active(MemoryFact fact, String today) =>
      fact.expiresOn == null || fact.expiresOn!.compareTo(today) >= 0;

  static bool needsReview(MemoryFact fact, String today) {
    final days = DayKey.diff(
      DayKey.of(fact.updatedAt ?? fact.createdAt),
      today,
    );
    final limit = switch (fact.category) {
      MemoryCategory.mood => 7,
      MemoryCategory.events => 30,
      MemoryCategory.healthHistory => 90,
      MemoryCategory.goals => 180,
      _ => 365,
    };
    return days > limit;
  }

  static List<MemoryFact> select(
    List<MemoryFact> all,
    String today,
    String question, {
    int limit = 20,
  }) {
    final words = RegExp(r'[a-z]{4,}')
        .allMatches(question.toLowerCase())
        .map((m) => m.group(0)!)
        .toSet();
    int relevance(MemoryFact f) =>
        words.where((w) => f.text.toLowerCase().contains(w)).length;
    final eligible = all.where((f) => active(f, today)).toList();
    eligible.sort((a, b) {
      final score = relevance(b).compareTo(relevance(a));
      if (score != 0) return score;
      final recency = (b.updatedAt ?? b.createdAt).compareTo(
        a.updatedAt ?? a.createdAt,
      );
      return recency != 0 ? recency : a.id.compareTo(b.id);
    });
    return eligible.take(limit).toList();
  }
}
