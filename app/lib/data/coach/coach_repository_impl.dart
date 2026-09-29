// CoachRepositoryImpl: settings, API keys, chats, confirmed memories, the
// daily cloud budget and the LLM client for the current settings.
//
//   * API keys: SecretStore (flutter_secure_storage) ONLY. Never SQLite,
//     logs, exports, payloads or exception text.
//   * client(): offline → OfflineClient (no network); Claude / Gemini →
//     the raw-HTTP client wrapped in a MeteredClient that checks the daily
//     budget BEFORE each request (fail fast, nothing sent) and records the
//     request and its tokens after it.
//   * wipe(): chats, memories and the insight cache (HealthRepository
//     .wipeData() calls it through DataModule).

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/coach/coach_contracts.dart';
import '../../domain/day_key.dart';
import 'claude_client.dart';
import 'coach_store.dart';
import 'gemini_client.dart';
import 'offline_client.dart';
import 'secret_store.dart';

/// Builds a cloud client. Tests inject fakes; the app uses [defaultClients].
typedef LlmClientFactory = LlmClient Function(
  CoachProvider provider,
  String apiKey,
  String? model,
);

class CoachRepositoryImpl implements CoachRepository {
  CoachRepositoryImpl({
    required this.store,
    required this.secrets,
    DateTime Function()? clock,
    LlmClientFactory? clients,
    http.Client? httpClient,

    /// Settings to start from before anything is stored (tests, demo).
    CoachSettings? initialSettings,
  }) : clock = clock ?? DateTime.now,
       _http = httpClient,
       _settings = initialSettings {
    _clients = clients ?? defaultClients;
  }

  final CoachStore store;
  final SecretStore secrets;
  final DateTime Function() clock;
  final http.Client? _http;
  late final LlmClientFactory _clients;
  http.Client? _shared;

  static const settingsKey = 'coach.settings';
  static const memoryKey = 'coach.memory_enabled';

  /// Secure-storage key for [p]'s API key.
  static String secretKeyFor(CoachProvider p) => 'coach.api_key.${p.name}';

  /// One shared HTTP client for every request (no socket leak per ask).
  /// Per-request timeout: Opus 5.5 always thinks, so 60 s is too short for
  /// a detailed turn.
  LlmClient defaultClients(CoachProvider p, String key, String? model) {
    final h = _http ?? (_shared ??= http.Client());
    return switch (p) {
      CoachProvider.claude => ClaudeClient(
        apiKey: key,
        model: model,
        httpClient: h,
        timeout: const Duration(seconds: 120),
      ),
      CoachProvider.gemini => GeminiClient(
        apiKey: key,
        model: model,
        httpClient: h,
        timeout: const Duration(seconds: 120),
      ),
      CoachProvider.offline => const OfflineClient(),
    };
  }

  // ── Settings ───────────────────────────────────────────────────────────

  CoachSettings? _settings;

  @override
  Future<CoachSettings> settings() async {
    if (_settings != null) return _settings!;
    final raw = await store.getValue(settingsKey);
    CoachSettings s;
    try {
      s = raw == null
          ? const CoachSettings()
          : CoachSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      s = const CoachSettings();
    }
    return _settings = s;
  }

  @override
  Future<void> saveSettings(CoachSettings s) async {
    _settings = s;
    await store.setValue(settingsKey, jsonEncode(s.toJson()));
  }

  // ── Keys (secure storage only) ─────────────────────────────────────────

  @override
  Future<bool> hasApiKey(CoachProvider p) async {
    if (p == CoachProvider.offline) return false;
    final k = await secrets.read(secretKeyFor(p));
    return k != null && k.trim().isNotEmpty;
  }

  @override
  Future<void> saveApiKey(CoachProvider p, String key) async {
    if (p == CoachProvider.offline) {
      throw const CoachException(
        CoachErrorKind.notConfigured,
        'The on-device coach needs no key.',
      );
    }
    final k = key.trim();
    if (k.isEmpty) {
      throw const CoachException(
        CoachErrorKind.invalidKey,
        'The key is empty.',
      );
    }
    await secrets.write(secretKeyFor(p), k);
  }

  @override
  Future<void> deleteApiKey(CoachProvider p) async {
    if (p == CoachProvider.offline) return;
    await secrets.delete(secretKeyFor(p));
  }

  // ── Conversations ──────────────────────────────────────────────────────

  int _n = 0;
  String _id(String kind) =>
      '$kind-${clock().microsecondsSinceEpoch.toRadixString(36)}-${_n++}';

  @override
  Future<List<Conversation>> conversations() => store.conversations();

  @override
  Future<List<ChatMessage>> messages(String conversationId) =>
      store.messages(conversationId);

  @override
  Future<Conversation> createConversation(String title) async {
    final now = clock();
    final c = Conversation(
      id: _id('c'),
      title: title.trim().isEmpty ? 'New chat' : title.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await store.putConversation(c);
    return c;
  }

  @override
  Future<void> appendMessage(ChatMessage m) async {
    final c = await store.conversation(m.conversationId);
    if (c == null) {
      await store.putConversation(
        Conversation(
          id: m.conversationId,
          title: 'Chat',
          createdAt: m.at,
          updatedAt: m.at,
        ),
      );
    } else if (m.at.isAfter(c.updatedAt)) {
      await store.putConversation(
        Conversation(
          id: c.id,
          title: c.title,
          createdAt: c.createdAt,
          updatedAt: m.at,
        ),
      );
    }
    await store.putMessage(m);
  }

  @override
  Future<void> deleteConversation(String id) => store.deleteConversation(id);

  @override
  Future<void> deleteAllConversations() => store.deleteAllConversations();

  // ── Memory (saved only on the user's explicit Remember / Add) ──────────

  @override
  Future<List<MemoryFact>> memories() => store.memories();

  @override
  Future<MemoryFact> addMemory(
    String text, {
    MemoryCategory category = MemoryCategory.preferences,
    String? expiresOn,
  }) async {
    final t = _checkMemory(text, expiresOn);
    final m = MemoryFact(
      id: _id('m'),
      text: t,
      createdAt: clock(),
      category: category,
      expiresOn: expiresOn,
    );
    await store.putMemory(m);
    return m;
  }

  @override
  Future<void> updateMemory(
    String id,
    String text, {
    MemoryCategory? category,
    String? expiresOn,
  }) async {
    final t = _checkMemory(text, expiresOn);
    final all = await store.memories();
    final old = all.where((m) => m.id == id).firstOrNull;
    if (old == null) return;
    await store.putMemory(
      MemoryFact(
        id: id,
        text: t,
        createdAt: old.createdAt,
        updatedAt: clock(),
        category: category ?? old.category,
        expiresOn: expiresOn,
      ),
    );
  }

  static final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  String _checkMemory(String text, String? expiresOn) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) {
      throw const CoachException(
        CoachErrorKind.unknown,
        'The memory is empty.',
      );
    }
    if (t.length > 300) {
      throw const CoachException(
        CoachErrorKind.unknown,
        'Keep a memory under 300 characters.',
      );
    }
    if (expiresOn != null && !_iso.hasMatch(expiresOn)) {
      throw const CoachException(
        CoachErrorKind.unknown,
        'The "until" date must look like 2026-11-15.',
      );
    }
    return t;
  }

  @override
  Future<bool> memoryEnabled() async =>
      (await store.getValue(memoryKey)) != 'false';

  @override
  Future<void> setMemoryEnabled(bool on) =>
      store.setValue(memoryKey, on ? 'true' : 'false');

  @override
  Future<void> deleteMemory(String id) => store.deleteMemory(id);

  // ── Client + budget ────────────────────────────────────────────────────

  @override
  Future<LlmClient> client() async {
    final s = await settings();
    if (s.provider == CoachProvider.offline) return const OfflineClient();
    final key = await secrets.read(secretKeyFor(s.provider));
    if (key == null || key.trim().isEmpty) {
      throw CoachException(
        CoachErrorKind.notConfigured,
        'Add your ${s.provider.label} API key in Settings → Coach.',
      );
    }
    return MeteredClient(
      _clients(s.provider, key.trim(), s.model),
      before: () async {
        final u = await usageToday();
        if (u != null && u.exhausted) {
          throw CoachException(
            CoachErrorKind.dailyLimit,
            'Today\'s ${s.provider.label} limit is reached, so nothing was '
            'sent. It resets at midnight.',
          );
        }
      },
      after: (t) => recordUsage(s.provider, t.inputTokens, t.outputTokens),
    );
  }

  @override
  Future<CoachUsage?> usageToday() async {
    final s = await settings();
    if (s.provider == CoachProvider.offline) return null;
    final row = await store.usage(DayKey.of(clock()), s.provider);
    return CoachUsage(
      provider: s.provider,
      requests: row.requests,
      inputTokens: row.inputTokens,
      outputTokens: row.outputTokens,
      requestLimit: s.dailyRequestLimit,
      tokenLimit: s.dailyTokenLimit,
    );
  }

  /// Adds one request to today's meter for [p].
  Future<void> recordUsage(CoachProvider p, int input, int output) async {
    final day = DayKey.of(clock());
    final row = await store.usage(day, p);
    await store.putUsage(day, p, row.plus(input, output));
  }

  /// Clears chats, memories and cached cards (HealthRepository.wipeData).
  /// Settings and keys stay; the user removes those in Settings → Coach.
  Future<void> wipe() async {
    await store.deleteAllConversations();
    await store.deleteAllMemories();
    await store.deleteAllInsights();
  }
}

/// Wraps a cloud client: [before] runs ahead of every request (the daily
/// budget; it throws to stop the request), [after] records what it cost.
class MeteredClient implements LlmClient {
  MeteredClient(this.inner, {required this.before, required this.after});
  final LlmClient inner;
  final Future<void> Function() before;
  final Future<void> Function(LlmTurn turn) after;

  @override
  CoachProvider get provider => inner.provider;

  @override
  String get model => inner.model;

  @override
  Future<LlmTurn> next({
    required String system,
    required List<LlmItem> transcript,
    required List<CoachToolSpec> tools,
    required ResponseLength length,
  }) async {
    await before();
    final t = await inner.next(
      system: system,
      transcript: transcript,
      tools: tools,
      length: length,
    );
    await after(t);
    return t;
  }
}
