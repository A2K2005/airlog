// CoachRepositoryImpl: settings, API keys, chats, confirmed memories, the
// daily cloud budget and the LLM client for the current settings.
//
//   * API keys: SecretStore (flutter_secure_storage) ONLY. Never SQLite,
//     logs, exports, payloads or exception text.
//   * client(): offline → OfflineClient (no network); Claude / Gemini →
//     the raw-HTTP client wrapped in a MeteredClient that checks the daily
//     budget BEFORE each request (fail fast, nothing sent) and records the
//     request and its tokens after it (a request the provider answered with
//     an error counts too, with no tokens).
//   * modelChain(): the chosen model, then the same provider's backups
//     (ProviderModels.chainFor; "Use a backup model when busy"), each its
//     own MeteredClient over the same key. onDeviceClient(): OfflineClient.
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
import 'provider_models.dart';
import 'quota_clock.dart';
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

    /// The on-device engine (tests wrap it to see what it receives).
    this.onDevice,

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

  /// The on-device engine; null = OfflineClient.
  final LlmClient? onDevice;
  late final LlmClientFactory _clients;
  http.Client? _shared;
  int _generation = 0;

  void _checkGeneration(int generation) {
    if (generation != _generation) {
      throw const CoachException(
        CoachErrorKind.notConfigured,
        'Coach settings changed. No further requests were sent. '
        'Start a new question with your current settings.',
      );
    }
  }

  static const settingsKey = 'coach.settings';
  static const memoryKey = 'coach.memory_enabled';

  /// Models whose day quota is used up: {model: {until, reason}} (JSON).
  static const downKey = 'coach.models_down';

  /// Secure-storage key for [p]'s API key.
  static String secretKeyFor(CoachProvider p) => 'coach.api_key.${p.name}';

  /// One shared HTTP client for every request (no socket leak per ask).
  /// Per-request timeout: Opus 5.5 always thinks, so 60 s is too short for
  /// a detailed turn.
  LlmClient defaultClients(CoachProvider p, String key, String? model) {
    final generation = _generation;
    final h = _GuardedHttpClient(
      _http ?? (_shared ??= http.Client()),
      () => _checkGeneration(generation),
    );
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
    _generation++;
    await store.setValue(settingsKey, jsonEncode(s.toJson()));
    _settings = s;
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
    _generation++;
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
    _generation++;
    if (p == CoachProvider.offline) return;
    await secrets.delete(secretKeyFor(p));
    if (await secrets.read(secretKeyFor(p)) != null) {
      throw const CoachException(
        CoachErrorKind.unknown,
        'The cloud engine is off, but the stored key could not be deleted. '
        'Try removing it again.',
      );
    }
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
    final generation = _generation;
    final c = await store.conversation(m.conversationId);
    _checkGeneration(generation);
    if (c == null) {
      // An answer arriving after deletion must not resurrect the chat.
      throw const CoachException(
        CoachErrorKind.notConfigured,
        'This conversation was deleted. Start a new chat.',
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
    _checkGeneration(generation);
    await store.putMessage(m);
  }

  @override
  Future<void> deleteConversation(String id) async {
    _generation++;
    await store.deleteConversation(id);
  }

  @override
  Future<void> deleteAllConversations() async {
    _generation++;
    await store.deleteAllConversations();
  }

  // ── Memory (saved only on the user's explicit Remember / Add) ──────────

  @override
  Future<List<MemoryFact>> memories() => store.memories();

  @override
  Future<MemoryFact> addMemory(
    String text, {
    MemoryCategory category = MemoryCategory.preferences,
    String? expiresOn,
  }) async {
    _generation++;
    final t = _checkMemory(text, expiresOn);
    for (final existing in await store.memories()) {
      if (existing.text.toLowerCase() == t.toLowerCase() &&
          existing.category == category &&
          existing.expiresOn == expiresOn) {
        return existing;
      }
    }
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
    _generation++;
    final t = _checkMemory(text, expiresOn);
    final all = await store.memories();
    final old = all.where((m) => m.id == id).firstOrNull;
    if (old == null) {
      throw const CoachException(
        CoachErrorKind.unknown,
        'This memory no longer exists. Refresh the list before editing.',
      );
    }
    await store.putMemory(
      MemoryFact(
        id: id,
        text: t,
        createdAt: old.createdAt,
        updatedAt: _nextMemoryTime(old),
        category: category ?? old.category,
        expiresOn: expiresOn,
      ),
    );
  }

  static final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  DateTime _nextMemoryTime(MemoryFact old) {
    final now = clock(), last = old.updatedAt ?? old.createdAt;
    return now.isAfter(last) ? now : last.add(const Duration(microseconds: 1));
  }

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
    if (expiresOn != null &&
        (!_iso.hasMatch(expiresOn) ||
            DateTime.tryParse(expiresOn) == null ||
            DayKey.of(DateTime.parse(expiresOn)) != expiresOn)) {
      throw const CoachException(
        CoachErrorKind.unknown,
        'The "until" date must be a real calendar date, like 2026-11-15.',
      );
    }
    return t;
  }

  @override
  Future<bool> memoryEnabled() async =>
      (await store.getValue(memoryKey)) != 'false';

  @override
  Future<void> setMemoryEnabled(bool on) async {
    _generation++;
    await store.setValue(memoryKey, on ? 'true' : 'false');
  }

  @override
  Future<void> deleteMemory(String id) async {
    _generation++;
    await store.deleteMemory(id);
  }

  // ── Client + budget ────────────────────────────────────────────────────

  @override
  Future<LlmClient> client() async => (await modelChain()).first;

  @override
  LlmClient onDeviceClient() => onDevice ?? const OfflineClient();

  // ── Models known to be down ─────────────────────────────────────────────

  final Map<String, ModelDown> _down = {};
  bool _downLoaded = false;

  @override
  Future<void> noteModelUnavailable(String model, ModelUnavailable e) async {
    final now = clock();
    final DateTime until;
    if (e.dayQuota) {
      // Per-model day quotas come back at midnight Pacific (Google).
      until = nextPacificMidnight(now);
    } else if (e.retryAfter != null && e.retryAfter! > Duration.zero) {
      until = now.add(e.retryAfter!);
    } else {
      return;
    }
    await _loadDown();
    _down[model] = ModelDown(until, e.kind);
    if (e.dayQuota) await _saveDown();
  }

  @override
  Future<ModelDown?> modelDown(String model) async {
    await _loadDown();
    final d = _down[model];
    if (d == null) return null;
    if (!clock().isBefore(d.until)) {
      _down.remove(model);
      await _saveDown();
      return null;
    }
    return d;
  }

  Future<void> _loadDown() async {
    if (_downLoaded) return;
    _downLoaded = true;
    try {
      final raw = await store.getValue(downKey);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      for (final e in j.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final until = DateTime.tryParse('${v['until']}');
        final reason = CoachErrorKind.values
            .where((k) => k.name == v['reason'])
            .firstOrNull;
        if (until == null || reason == null) continue;
        _down.putIfAbsent('${e.key}', () => ModelDown(until, reason));
      }
    } catch (_) {
      // Unreadable: nothing is known to be down.
    }
  }

  /// Persists only the day-quota marks that are still in the future (a
  /// retry delay lasts seconds; it lives in memory).
  Future<void> _saveDown() async {
    final now = clock();
    final keep = {
      for (final e in _down.entries)
        if (e.value.until.difference(now) > const Duration(minutes: 10))
          e.key: {
            'until': e.value.until.toUtc().toIso8601String(),
            'reason': e.value.reason.name,
          },
    };
    try {
      await store.setValue(downKey, keep.isEmpty ? null : jsonEncode(keep));
    } catch (_) {}
  }

  @override
  Future<List<LlmClient>> modelChain() async {
    // Generation-fenced (PR #1): a settings, key, memory or chat change
    // after this point stops every model of the chain before it sends.
    final generation = _generation;
    final s = await settings();
    _checkGeneration(generation);
    if (s.provider == CoachProvider.offline) return const [OfflineClient()];
    final key = await secrets.read(secretKeyFor(s.provider));
    _checkGeneration(generation);
    if (key == null || key.trim().isEmpty) {
      throw CoachException(
        CoachErrorKind.notConfigured,
        'Add your ${s.provider.label} API key in Settings → Coach.',
      );
    }
    final ids = ProviderModels.chainFor(
      s.provider,
      s.model,
      backups: s.backupModels,
    );
    return [
      for (final id in ids.isEmpty ? <String?>[s.model] : ids)
        _metered(s, key.trim(), id, generation),
    ];
  }

  /// One model of the chain: the budget and the generation fence before
  /// every request, usage after it (failed calls that reached the provider
  /// count too).
  MeteredClient _metered(
    CoachSettings s,
    String key,
    String? model,
    int generation,
  ) => MeteredClient(
    _clients(s.provider, key, model),
    before: () async {
      _checkGeneration(generation);
      final u = await usageToday();
      if (u != null && u.exhausted) {
        throw CoachException(
          CoachErrorKind.dailyLimit,
          'Today\'s ${s.provider.label} model-request limit is reached. '
          'No further requests were sent. It resets at midnight.',
        );
      }
    },
    after: (t) async {
      await recordUsage(s.provider, t.inputTokens, t.outputTokens);
      _checkGeneration(generation);
    },
    failed: () => recordUsage(s.provider, 0, 0),
  );

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
    _generation++;
    await store.deleteAllConversations();
    await store.deleteAllMemories();
    await store.deleteAllInsights();
  }
}

/// Checks revocation at the actual HTTP boundary, including automatic retries.
class _GuardedHttpClient extends http.BaseClient {
  _GuardedHttpClient(this.inner, this.check);
  final http.Client inner;
  final void Function() check;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    check();
    return inner.send(request);
  }

  @override
  void close() {} // The repository owns the shared transport.
}

/// Wraps a cloud client: [before] runs ahead of every request (the daily
/// budget; it throws to stop the request), [after] records what it cost,
/// and [failed] records a request the provider answered with an error (a
/// busy model, a bad key: it still counts toward the daily budget). One
/// call counts once: the client's own retries of a busy answer inside it
/// are not counted again. Nothing is counted when nothing was sent (the
/// budget stop, a missing key) or no answer came back (network).
class MeteredClient implements LlmClient {
  MeteredClient(
    this.inner, {
    required this.before,
    required this.after,
    this.failed,
  });
  final LlmClient inner;
  final Future<void> Function() before;
  final Future<void> Function(LlmTurn turn) after;
  final Future<void> Function()? failed;

  /// The provider answered the request (with an error status).
  static bool reachedProvider(CoachException e) => switch (e.kind) {
    CoachErrorKind.network ||
    CoachErrorKind.dailyLimit ||
    CoachErrorKind.notConfigured => false,
    _ => true,
  };

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
    final LlmTurn t;
    try {
      t = await inner.next(
        system: system,
        transcript: transcript,
        tools: tools,
        length: length,
      );
    } on CoachException catch (e) {
      if (reachedProvider(e)) await failed?.call();
      rethrow;
    }
    await after(t);
    return t;
  }
}
