// Conversations: the stored chats with their topic (derived from the tools
// each chat's answers used, never an LLM guess: ChatTopics), a topic filter
// and a search over titles and message text; delete one, delete all.
//
// Each chat's messages are read once to find its topic and its searchable
// text (a local read; the app keeps tens of chats, not thousands).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform_services.dart';
import '../../app/providers.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/topics.dart';

class CoachChatItem {
  const CoachChatItem(this.conversation, this.topic, this.text);
  final Conversation conversation;
  final ChatTopic topic;

  /// The title and every message, lower-cased, for search.
  final String text;
}

class CoachHistoryState {
  const CoachHistoryState({
    this.items = const [],
    this.topic,
    this.query = '',
  });

  /// Newest first.
  final List<CoachChatItem> items;

  /// The chosen topic card, or null for all.
  final ChatTopic? topic;
  final String query;

  /// Chats per topic, for the topic cards (topics with none are left out;
  /// General last).
  Map<ChatTopic, List<CoachChatItem>> get byTopic => {
    for (final t in ChatTopic.values)
      if (items.any((i) => i.topic == t))
        t: [
          for (final i in items)
            if (i.topic == t) i,
        ],
  };

  /// The list under the cards: the chosen topic, then the search.
  List<CoachChatItem> get shown {
    final q = query.trim().toLowerCase();
    return [
      for (final i in items)
        if ((topic == null || i.topic == topic) &&
            (q.isEmpty || i.text.contains(q)))
          i,
    ];
  }

  CoachHistoryState copyWith({
    List<CoachChatItem>? items,
    ChatTopic? topic,
    bool clearTopic = false,
    String? query,
  }) => CoachHistoryState(
    items: items ?? this.items,
    topic: clearTopic ? null : (topic ?? this.topic),
    query: query ?? this.query,
  );
}

class CoachHistoryViewModel extends AsyncNotifier<CoachHistoryState> {
  @override
  Future<CoachHistoryState> build() async {
    final repo = ref.watch(coachRepositoryProvider);
    final list = [...await repo.conversations()]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final items = await Future.wait([
      for (final c in list)
        () async {
          List<ChatMessage> msgs;
          try {
            msgs = await repo.messages(c.id);
          } catch (_) {
            msgs = const [];
          }
          final text = [
            c.title,
            for (final m in msgs) m.text,
          ].join('\n').toLowerCase();
          return CoachChatItem(c, ChatTopics.ofConversation(msgs), text);
        }(),
    ]);
    return CoachHistoryState(items: items);
  }

  CoachRepository get _repo => ref.read(coachRepositoryProvider);

  void _set(CoachHistoryState Function(CoachHistoryState s) f) {
    final s = state.value;
    if (s != null) state = AsyncData(f(s));
  }

  /// Picks a topic card; the same card again shows every chat.
  void pickTopic(ChatTopic t) => _set(
    (s) => s.topic == t ? s.copyWith(clearTopic: true) : s.copyWith(topic: t),
  );

  void search(String q) => _set((s) => s.copyWith(query: q));

  Future<bool> delete(String id) async {
    _set(
      (s) => s.copyWith(
        items: [
          for (final i in s.items)
            if (i.conversation.id != id) i,
        ],
      ),
    );
    try {
      await _repo.deleteConversation(id);
      return true;
    } catch (_) {
      if (ref.mounted) ref.invalidateSelf();
      return false;
    }
  }

  Future<bool> deleteAll() async {
    try {
      await _repo.deleteAllConversations();
      if (ref.mounted) {
        state = const AsyncData(CoachHistoryState());
      }
      return true;
    } catch (_) {
      if (ref.mounted) ref.invalidateSelf();
      return false;
    }
  }
}

final coachHistoryProvider =
    AsyncNotifierProvider.autoDispose<
      CoachHistoryViewModel,
      CoachHistoryState
    >(CoachHistoryViewModel.new, retry: noRetry);
