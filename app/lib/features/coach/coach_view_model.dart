// The chat's view-model: one conversation, the suggested starters, the
// question in flight, and what the user did with each "Remember this?"
// proposal and each report. Keyed by the launch arguments (CoachLaunch), so
// every opening of the chat is its own session.
//
// Nothing is saved to memory without a tap: a proposal stays pending until
// saveMemory() (Remember) or dismissMemory() (No thanks).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform_services.dart';
import '../../app/providers.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/day_key.dart';
import 'coach_providers.dart';

/// What happened to one proposed memory.
enum MemoryChoice { pending, saved, dismissed }

class CoachChatState {
  const CoachChatState({
    this.conversationId,
    this.messages = const [],
    this.suggestions = const [],
    this.sending = false,
    this.lastQuestion,
    this.fresh = const {},
    this.memory = const {},
    this.categories = const {},
    this.reported = const {},
    this.prefill,
    this.discussing = false,
  });

  final String? conversationId;

  /// Oldest first.
  final List<ChatMessage> messages;
  final List<String> suggestions;

  /// A question is waiting for its answer.
  final bool sending;

  /// The question to send again from an error's "Try again".
  final String? lastQuestion;

  /// Ids of messages added in this session: only these enter with motion.
  final Set<String> fresh;

  /// Keyed by [memoryKey].
  final Map<String, MemoryChoice> memory;

  /// The category picked for each pending proposal ([memoryKey]).
  final Map<String, MemoryCategory> categories;

  /// Answers flagged with "Report answer" (kept on this phone).
  final Set<String> reported;

  /// The composer's starting text.
  final String? prefill;

  /// This session is about the insight card it was opened from ("Discuss"):
  /// the card is pinned and its seed goes with each question. History and
  /// New chat end it, so the card never reaches another conversation.
  final bool discussing;

  bool get isEmpty => messages.isEmpty;

  static String memoryKey(String messageId, int index) => '$messageId#$index';

  MemoryChoice choiceOf(String messageId, int index) =>
      memory[memoryKey(messageId, index)] ?? MemoryChoice.pending;

  /// The user's pick, else the model's category, else a guess from [text].
  MemoryCategory categoryOf(String messageId, int index, String text) =>
      categories[memoryKey(messageId, index)] ??
      _proposedCategory(messageId, index) ??
      guessCategory(text);

  MemoryCategory? _proposedCategory(String messageId, int index) {
    for (final m in messages) {
      if (m.id == messageId) return m.proposedCategory(index);
    }
    return null;
  }

  /// The user question an answer replied to.
  String? questionFor(String answerId) {
    final i = messages.indexWhere((m) => m.id == answerId);
    for (var j = i - 1; j >= 0; j--) {
      if (messages[j].role == ChatRole.user) return messages[j].text;
    }
    return null;
  }

  CoachChatState copyWith({
    String? conversationId,
    bool clearConversation = false,
    List<ChatMessage>? messages,
    List<String>? suggestions,
    bool? sending,
    String? lastQuestion,
    Set<String>? fresh,
    Map<String, MemoryChoice>? memory,
    Map<String, MemoryCategory>? categories,
    Set<String>? reported,
    String? prefill,
    bool clearPrefill = false,
  }) => CoachChatState(
    conversationId: clearConversation
        ? null
        : (conversationId ?? this.conversationId),
    messages: messages ?? this.messages,
    suggestions: suggestions ?? this.suggestions,
    sending: sending ?? this.sending,
    lastQuestion: lastQuestion ?? this.lastQuestion,
    fresh: fresh ?? this.fresh,
    memory: memory ?? this.memory,
    categories: categories ?? this.categories,
    reported: reported ?? this.reported,
    prefill: clearPrefill ? null : (prefill ?? this.prefill),
    discussing: discussing,
  );
}

/// An error answer's kind: a thrown [CoachException], or a stored message
/// whose `error` names a [CoachErrorKind].
CoachErrorKind? errorKindOf(ChatMessage m) {
  final e = m.error;
  if (e == null) return null;
  for (final k in CoachErrorKind.values) {
    if (k.name == e) return k;
  }
  return CoachErrorKind.unknown;
}

class CoachChatViewModel extends AsyncNotifier<CoachChatState> {
  CoachChatViewModel(this.launch);

  final CoachLaunch launch;
  var _local = 0;

  CoachRepository get _repo => ref.read(coachRepositoryProvider);
  CoachService get _service => ref.read(coachServiceProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  Future<CoachChatState> build() async {
    final service = ref.watch(coachServiceProvider);
    final repo = ref.watch(coachRepositoryProvider);
    final today = DayKey.of(ref.read(clockProvider)());
    var suggestions = const <String>[];
    if (launch.discussing) {
      // "Discuss" from an insight card: follow-ups for the card's kind. They
      // fill the composer when tapped; nothing is sent on arrival.
      suggestions = discussFollowUps(launch.screen);
    } else {
      try {
        suggestions = await service.suggestions(context: launch.context);
      } catch (_) {}
    }
    var messages = const <ChatMessage>[];
    final id = launch.conversationId;
    if (id != null) messages = await repo.messages(id);
    return CoachChatState(
      conversationId: id,
      messages: messages,
      suggestions: suggestions,
      discussing: launch.discussing,
      // A discussed card never pre-fills: the composer fills only when the
      // user taps a follow-up (a cloud send spends their key).
      prefill: launch.discussing
          ? null
          : launch.prefill ?? prefillFor(launch.screen, launch.date, today),
    );
  }

  String _id(String kind) => 'local-$kind-${++_local}';

  /// Sends [question]. Returns false when nothing was sent (empty, or a
  /// question is already waiting).
  Future<bool> send(String question) async {
    final q = question.trim();
    final s = state.value;
    if (q.isEmpty || s == null || s.sending) return false;
    final mine = ChatMessage(
      id: _id('u'),
      conversationId: s.conversationId ?? '',
      role: ChatRole.user,
      text: q,
      at: _now(),
    );
    state = AsyncData(
      s.copyWith(
        messages: [...s.messages, mine],
        sending: true,
        lastQuestion: q,
        fresh: {...s.fresh, mine.id},
        clearPrefill: true,
      ),
    );
    await _ask(q, mine);
    return true;
  }

  /// Sends the last question again (an error's "Try again"), in place of the
  /// error.
  Future<void> retry() async {
    final s = state.value;
    if (s == null || s.sending || s.messages.isEmpty) return;
    final q = s.lastQuestion ?? s.questionFor(s.messages.last.id);
    if (q == null) return;
    final kept = [...s.messages];
    if (kept.isNotEmpty && errorKindOf(kept.last) != null) kept.removeLast();
    ChatMessage? mine;
    for (final m in kept.reversed) {
      if (m.role == ChatRole.user) {
        mine = m;
        break;
      }
    }
    state = AsyncData(s.copyWith(messages: kept, sending: true));
    await _ask(q, mine);
  }

  Future<void> _ask(String q, ChatMessage? mine) async {
    final before = state.value!;
    ChatMessage answer;
    try {
      answer = await _service.ask(
        q,
        conversationId: before.conversationId,
        context: before.discussing ? launch.context : launch.plainContext,
      );
    } on CoachException catch (e) {
      answer = _errorMessage(before.conversationId, e.kind, e.message);
    } catch (e) {
      answer = _errorMessage(before.conversationId, CoachErrorKind.unknown);
    }
    if (!ref.mounted) return;
    final cur = state.value ?? before;
    final convId = answer.conversationId.isEmpty
        ? cur.conversationId
        : answer.conversationId;
    // The stored transcript is the truth when it holds this answer; the
    // optimistic question is kept if the service did not store it.
    var list = [...cur.messages, answer];
    if (convId != null && !answer.id.startsWith('local-')) {
      try {
        final stored = await _repo.messages(convId);
        if (stored.any((m) => m.id == answer.id)) {
          list = [...stored];
          final hasQ = list.any((m) => m.role == ChatRole.user && m.text == q);
          if (!hasQ && mine != null) {
            list.insert(list.indexWhere((m) => m.id == answer.id), mine);
          }
        }
      } catch (_) {}
    }
    if (!ref.mounted) return;
    state = AsyncData(
      cur.copyWith(
        conversationId: convId,
        messages: list,
        sending: false,
        fresh: {...cur.fresh, answer.id},
      ),
    );
  }

  ChatMessage _errorMessage(
    String? conversationId,
    CoachErrorKind kind, [
    String? detail,
  ]) => ChatMessage(
    id: _id('e'),
    conversationId: conversationId ?? '',
    role: ChatRole.assistant,
    text: detail ?? '',
    at: _now(),
    error: kind.name,
  );

  /// The starters for a session that is no longer about a card: a Discuss
  /// session's follow-ups go with the card.
  Future<List<String>> _startersAfter(CoachChatState s) async {
    if (!s.discussing) return s.suggestions;
    try {
      return await _service.suggestions(context: launch.plainContext);
    } catch (_) {
      return const [];
    }
  }

  /// Starts a new session (the next question opens a new conversation).
  Future<void> newChat() async {
    final s = state.value;
    if (s == null || s.sending) return;
    final suggestions = await _startersAfter(s);
    if (!ref.mounted) return;
    state = AsyncData(CoachChatState(suggestions: suggestions));
  }

  /// Shows a stored conversation (from History).
  Future<void> openConversation(String id) async {
    final s = state.value;
    if (s == null || s.sending) return;
    final messages = await _repo.messages(id);
    final suggestions = await _startersAfter(s);
    if (!ref.mounted) return;
    state = AsyncData(
      CoachChatState(
        conversationId: id,
        messages: messages,
        suggestions: suggestions,
      ),
    );
  }

  /// Picks the category a proposal will be saved under (nothing is saved).
  void pickCategory(String messageId, int index, MemoryCategory c) {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(
      s.copyWith(
        categories: {
          ...s.categories,
          CoachChatState.memoryKey(messageId, index): c,
        },
      ),
    );
  }

  /// "Remember": the only path that saves a proposed memory.
  Future<bool> saveMemory(String messageId, int index, String text) async {
    final s = state.value;
    if (s == null) return false;
    final key = CoachChatState.memoryKey(messageId, index);
    if (s.memory[key] == MemoryChoice.saved) return true;
    try {
      await _repo.addMemory(
        text,
        category: s.categoryOf(messageId, index, text),
      );
    } catch (_) {
      return false;
    }
    if (!ref.mounted) return true;
    final cur = state.value ?? s;
    state = AsyncData(
      cur.copyWith(memory: {...cur.memory, key: MemoryChoice.saved}),
    );
    ref.invalidate(coachConfigProvider);
    return true;
  }

  /// "No thanks": forgets the proposal.
  void dismissMemory(String messageId, int index) {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(
      s.copyWith(
        memory: {
          ...s.memory,
          CoachChatState.memoryKey(messageId, index): MemoryChoice.dismissed,
        },
      ),
    );
  }

  /// Flags an answer on this phone (Play's AI-content reporting). Nothing
  /// is sent anywhere.
  void report(String messageId) {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(s.copyWith(reported: {...s.reported, messageId}));
  }
}

final coachChatProvider = AsyncNotifierProvider.autoDispose
    .family<CoachChatViewModel, CoachChatState, CoachLaunch>(
      CoachChatViewModel.new,
      retry: noRetry,
    );
