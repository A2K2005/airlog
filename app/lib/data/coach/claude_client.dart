// ClaudeClient: LlmClient over the raw Claude Messages API (non-streaming).
//
//   POST https://api.anthropic.com/v1/messages
//   headers  x-api-key, anthropic-version: 2023-06-01, content-type
//            (+ anthropic-beta: server-side-fallback-2026-07-01 on the models
//            that take `fallbacks: "default"`)
//   body     model, max_tokens, system (cached), tools (strict, last one
//            cached), tool_choice auto, output_config.effort (not Haiku),
//            fallbacks, messages
//
// Wire rules (claude-api reference):
//   * never `thinking` (Opus 5.5 thinking is always on; omission = adaptive),
//     never temperature / top_p, never a forced tool_choice (400 on the 5.5
//     models);
//   * a model turn is replayed as the `content` array exactly as received
//     (thinking blocks included — preserved thinking needs an append-only,
//     unmodified history); this client never mutates it;
//   * all tool results of one turn go back in ONE user message, and roles
//     always alternate (consecutive same-role items are merged);
//   * app data attached to a question (LlmUser.data: the insight card a
//     chat was opened from) is a text block in that user message, before
//     the question (CoachPrompts.userData). It is never sent as a synthetic
//     assistant tool_use + tool_result: with thinking always on, an
//     assistant turn before a tool_result is expected to carry a thinking
//     block, and a fabricated one has none;
//   * a turn cut off by max_tokens / refusal yields no tool calls; if its
//     replayed content still holds tool_use blocks nobody answered, an
//     is_error tool_result is supplied for each so the request stays valid;
//   * a 429 (per minute), 503 or 529 ("overloaded") is retried at most
//     twice (http_retry.dart: Retry-After, else ~2 s then ~6 s with jitter).
// The API key is sent only in the header and never appears in an exception
// message. Nothing is printed or logged.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;
import 'dart:math' show Random;

import 'package:http/http.dart' as http;

import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/prompts.dart';
import 'http_retry.dart';
import 'provider_models.dart';

class ClaudeClient implements LlmClient {
  ClaudeClient({
    required String apiKey,
    String? model,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.retry = const RetryPolicy(),
    this.sleep,
    this.random,
  }) : _apiKey = apiKey.trim(),
       model = (model == null || model.trim().isEmpty)
           ? ProviderModels.claudeDefault
           : model.trim(),
       _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null;

  final String _apiKey;
  final http.Client _http;
  final bool _ownsHttp;
  final Duration timeout;

  /// Busy answers (429 / 503 / 529) are retried per this policy.
  final RetryPolicy retry;

  /// Test hooks: the wait between retries, and the jitter's randomness.
  final Future<void> Function(Duration)? sleep;
  final Random? random;

  @override
  final String model;

  @override
  CoachProvider get provider => CoachProvider.claude;

  /// Closes the HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  static const _cache = {'type': 'ephemeral'};
  static const _unansweredCall =
      'Not run: the model turn that requested this call was cut off.';

  @override
  Future<LlmTurn> next({
    required String system,
    required List<LlmItem> transcript,
    required List<CoachToolSpec> tools,
    required ResponseLength length,
  }) async {
    _checkKey();
    final spec = ProviderModels.byId(model);
    final effort = spec?.effort;
    final fallback = spec?.serverFallback ?? false;

    final List<int> bytes;
    try {
      bytes = utf8.encode(
        jsonEncode(_requestBody(system, transcript, tools, effort, fallback)),
      );
    } on JsonUnsupportedObjectError {
      throw const CoachException(
        CoachErrorKind.unknown,
        'A tool result could not be encoded as JSON.',
      );
    }
    final headers = <String, String>{
      ClaudeApi.headerKey: _apiKey,
      ClaudeApi.headerVersion: ClaudeApi.version,
      'content-type': 'application/json',
      if (fallback) ClaudeApi.headerBeta: ClaudeApi.serverFallbackBeta,
    };

    final res = await sendWithRetry(
      () => _post(headers, bytes),
      policy: retry,
      sleep: sleep,
      random: random,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _httpError(res);
    }
    return _parse(res, bytes.length);
  }

  // ── request ────────────────────────────────────────────────────────────

  /// The request body (before JSON encoding).
  Map<String, dynamic> _requestBody(
    String system,
    List<LlmItem> transcript,
    List<CoachToolSpec> tools,
    String? effort,
    bool fallback,
  ) => {
    'model': model,
    'max_tokens': ClaudeApi.maxTokens,
    if (system.isNotEmpty)
      'system': [
        {'type': 'text', 'text': system, 'cache_control': _cache},
      ],
    if (tools.isNotEmpty)
      'tools': [
        for (var i = 0; i < tools.length; i++)
          {
            'name': tools[i].name,
            'description': tools[i].description,
            'input_schema': tools[i].inputSchema,
            'strict': true,
            if (i == tools.length - 1) 'cache_control': _cache,
          },
      ],
    if (tools.isNotEmpty) 'tool_choice': const {'type': 'auto'},
    if (effort != null) 'output_config': {'effort': effort},
    if (fallback) 'fallbacks': ClaudeApi.fallbacksDefault,
    'messages': buildMessages(transcript),
  };

  /// Maps the provider-neutral transcript to Claude `messages`. Public for
  /// tests; never mutates any [LlmTurn.rawAssistant].
  static List<Map<String, dynamic>> buildMessages(List<LlmItem> transcript) {
    final roles = <String>[];
    final contents = <List<Object?>>[];

    void add(String role, List<Object?> blocks) {
      if (blocks.isEmpty) return; // empty content is a 400
      if (roles.isNotEmpty && roles.last == role) {
        contents.last = _merge(role, contents.last, blocks);
      } else {
        roles.add(role);
        contents.add(blocks);
      }
    }

    for (final item in transcript) {
      switch (item) {
        case LlmUser(:final text, :final data):
          add('user', [
            for (final r in data)
              {'type': 'text', 'text': CoachPrompts.userData(r)},
            if (text.isNotEmpty) {'type': 'text', 'text': text},
          ]);
        case LlmAssistant(:final turn):
          final raw = turn.rawAssistant;
          if (raw is List) {
            add(
              'assistant',
              List<Object?>.of(raw),
            ); // shallow copy, same blocks
          } else {
            add('assistant', [
              if (turn.text.isNotEmpty) {'type': 'text', 'text': turn.text},
              for (final c in turn.toolCalls)
                {
                  'type': 'tool_use',
                  'id': c.id,
                  'name': c.name,
                  'input': c.input,
                },
            ]);
          }
        case LlmToolResults(:final results):
          add('user', [
            for (final r in results)
              {
                'type': 'tool_result',
                'tool_use_id': r.callId,
                'content': jsonEncode(r.content),
                if (r.isError) 'is_error': true,
              },
          ]);
      }
    }

    // Every tool_use must be answered in the next user message.
    for (var i = 0; i < roles.length; i++) {
      if (roles[i] != 'assistant') continue;
      final ids = [
        for (final b in contents[i])
          if (b is Map && b['type'] == 'tool_use' && b['id'] is String)
            b['id'] as String,
      ];
      if (ids.isEmpty) continue;
      final hasNext = i + 1 < roles.length;
      final answered = <Object?>{
        if (hasNext)
          for (final b in contents[i + 1])
            if (b is Map && b['type'] == 'tool_result') b['tool_use_id'],
      };
      final fillers = <Object?>[
        for (final id in ids)
          if (!answered.contains(id))
            {
              'type': 'tool_result',
              'tool_use_id': id,
              'content': jsonEncode(const {'error': _unansweredCall}),
              'is_error': true,
            },
      ];
      if (fillers.isEmpty) continue;
      if (hasNext) {
        contents[i + 1] = [...fillers, ...contents[i + 1]];
      } else {
        roles.add('user');
        contents.add(fillers);
      }
    }

    return [
      for (var i = 0; i < roles.length; i++)
        {'role': roles[i], 'content': contents[i]},
    ];
  }

  static bool _isToolResult(Object? b) =>
      b is Map && b['type'] == 'tool_result';

  /// New list; a user message puts its tool_result blocks first.
  static List<Object?> _merge(String role, List<Object?> a, List<Object?> b) {
    if (role != 'user') return [...a, ...b];
    return [
      ...a.where(_isToolResult),
      ...b.where(_isToolResult),
      ...a.where((x) => !_isToolResult(x)),
      ...b.where((x) => !_isToolResult(x)),
    ];
  }

  // ── transport ──────────────────────────────────────────────────────────

  void _checkKey() {
    if (_apiKey.isEmpty) {
      throw const CoachException(
        CoachErrorKind.notConfigured,
        'No Anthropic API key is saved.',
      );
    }
    for (final u in _apiKey.codeUnits) {
      if (u < 0x21 || u > 0x7e) {
        throw const CoachException(
          CoachErrorKind.invalidKey,
          'The Anthropic API key contains characters an API key cannot '
          'have. Paste it again.',
        );
      }
    }
  }

  Future<http.Response> _post(
    Map<String, String> headers,
    List<int> bytes,
  ) async {
    try {
      return await _http
          .post(Uri.parse(ClaudeApi.endpoint), headers: headers, body: bytes)
          .timeout(timeout);
    } on TimeoutException {
      throw CoachException(
        CoachErrorKind.network,
        'Anthropic did not answer within ${timeout.inSeconds} s.',
      );
    } on http.ClientException catch (e) {
      throw CoachException(CoachErrorKind.network, _scrub(e.message));
    } on IOException catch (e) {
      throw CoachException(CoachErrorKind.network, _scrub('$e'));
    } catch (e) {
      throw CoachException(CoachErrorKind.unknown, _scrub('$e'));
    }
  }

  String _scrub(String s) {
    var out = _apiKey.isEmpty ? s : s.replaceAll(_apiKey, '[redacted]');
    if (out.length > 300) out = '${out.substring(0, 300)}…';
    return out;
  }

  CoachException _httpError(http.Response res) {
    final code = res.statusCode;
    String? type;
    String? message;
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      final e = j is Map ? j['error'] : null;
      if (e is Map) {
        if (e['type'] is String) type = e['type'] as String;
        if (e['message'] is String) message = e['message'] as String;
      }
    } on FormatException {
      // Not JSON (a proxy page): report the status only.
    }
    final detail = [?type, ?message].join(': ');
    final text = _scrub(detail.isEmpty ? 'HTTP $code' : 'HTTP $code $detail');
    final kind = switch (code) {
      401 || 403 => CoachErrorKind.invalidKey,
      402 => CoachErrorKind.quotaExceeded,
      429 when isDailyQuota(res) => CoachErrorKind.quotaExceeded,
      429 => CoachErrorKind.rateLimited,
      >= 500 && < 600 => CoachErrorKind.server,
      _ => CoachErrorKind.unknown,
    };
    return CoachException(kind, text);
  }

  // ── response ───────────────────────────────────────────────────────────

  LlmTurn _parse(http.Response res, int sentBytes) {
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const CoachException(
        CoachErrorKind.server,
        'Anthropic sent a response that is not valid JSON.',
      );
    }
    final content = j is Map ? j['content'] : null;
    if (j is! Map || content is! List) {
      throw const CoachException(
        CoachErrorKind.server,
        'Anthropic sent a response without content.',
      );
    }
    final stop = j['stop_reason'] is String
        ? j['stop_reason'] as String
        : LlmStop.endTurn;
    final cutOff = stop == LlmStop.refusal || stop == LlmStop.maxTokens;

    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final b in content) {
      if (b is! Map) continue;
      switch (b['type']) {
        case 'text':
          final t = b['text'];
          if (t is String) text.write(t);
        case 'tool_use':
          final id = b['id'], name = b['name'], input = b['input'];
          if (id is String && name is String) {
            calls.add(
              ToolCall(
                id: id,
                name: name,
                input: input is Map
                    ? Map<String, dynamic>.from(input)
                    : <String, dynamic>{},
              ),
            );
          }
      }
    }

    final usage = j['usage'];
    int u(String k) {
      final v = usage is Map ? usage[k] : null;
      return v is num ? v.toInt() : 0;
    }

    return LlmTurn(
      text: text.toString(),
      toolCalls: cutOff ? const [] : calls,
      stopReason: stop,
      refusal: stop == LlmStop.refusal,
      rawAssistant: content,
      inputTokens:
          u('input_tokens') +
          u('cache_creation_input_tokens') +
          u('cache_read_input_tokens'),
      outputTokens: u('output_tokens'),
      sentBytes: sentBytes,
    );
  }
}
