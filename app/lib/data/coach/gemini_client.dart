// GeminiClient: LlmClient over the raw Gemini generateContent REST API.
//
//   POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
//   headers  x-goog-api-key, content-type (the key is NEVER in the URL)
//   body     systemInstruction, contents, tools.functionDeclarations,
//            toolConfig AUTO, generationConfig.thinkingConfig.thinkingLevel +
//            maxOutputTokens (no temperature / top_p / top_k: deprecated)
//
// Wire rules:
//   * a model turn is replayed as its `parts` exactly as received (they carry
//     thought signatures); this client never mutates them;
//   * all function responses of one turn go back in ONE 'user' content, each
//     carrying the call id and name; consecutive same-role contents merge;
//   * app data attached to a question (LlmUser.data: the insight card a
//     chat was opened from) is a text part in that 'user' content, before
//     the question (CoachPrompts.userData). It is never sent as a synthetic
//     model functionCall + functionResponse: Gemini 3 expects a thought
//     signature on functionCall parts, and a fabricated one has none;
//   * a turn cut off by MAX_TOKENS / a safety stop yields no tool calls; if
//     its replayed parts still hold functionCalls nobody answered, an error
//     functionResponse is supplied for each so the request stays valid.
//   * a 429 (per minute), 503 ("high demand", frequent on 3.x) or 529 is
//     retried at most twice (http_retry.dart: the server's retryDelay /
//     Retry-After, else ~2 s then ~6 s with jitter); a 429 whose quota is
//     gone for the day is not retried and reports quotaExceeded.
// The Gemini wire field names live in provider_models.dart (GeminiApi); they
// were verified against the live API on 2026-09-29. The API key never
// appears in an exception message. Nothing is printed or logged.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;
import 'dart:math' show Random;

import 'package:http/http.dart' as http;

import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/prompts.dart';
import 'http_retry.dart';
import 'provider_models.dart';

class GeminiClient implements LlmClient {
  GeminiClient({
    required String apiKey,
    String? model,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.retry = const RetryPolicy(),
    this.sleep,
    this.random,
  }) : _apiKey = apiKey.trim(),
       model = (model == null || model.trim().isEmpty)
           ? ProviderModels.geminiDefault
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
  CoachProvider get provider => CoachProvider.gemini;

  /// Closes the HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

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
    final List<int> bytes;
    try {
      bytes = utf8.encode(
        jsonEncode(_requestBody(system, transcript, tools, length)),
      );
    } on JsonUnsupportedObjectError {
      throw const CoachException(
        CoachErrorKind.unknown,
        'A tool result could not be encoded as JSON.',
      );
    }
    final headers = <String, String>{
      GeminiApi.headerKey: _apiKey,
      'content-type': 'application/json',
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

  Map<String, dynamic> _requestBody(
    String system,
    List<LlmItem> transcript,
    List<CoachToolSpec> tools,
    ResponseLength length,
  ) => {
    if (system.isNotEmpty)
      GeminiApi.systemInstruction: {
        GeminiApi.parts: [
          {GeminiApi.text: system},
        ],
      },
    GeminiApi.contents: buildContents(transcript),
    if (tools.isNotEmpty)
      GeminiApi.tools: [
        {
          GeminiApi.functionDeclarations: [
            for (final t in tools)
              {
                GeminiApi.name: t.name,
                'description': t.description,
                GeminiApi.functionDeclarationSchema: t.inputSchema,
              },
          ],
        },
      ],
    if (tools.isNotEmpty)
      GeminiApi.toolConfig: {
        GeminiApi.functionCallingConfig: {GeminiApi.mode: GeminiApi.modeAuto},
      },
    GeminiApi.generationConfig: {
      GeminiApi.thinkingConfig: {
        GeminiApi.thinkingLevel: length == ResponseLength.detailed
            ? GeminiApi.thinkingMedium
            : GeminiApi.thinkingLow,
      },
      GeminiApi.maxOutputTokens: GeminiApi.maxOutputTokensValue,
    },
  };

  /// Maps the provider-neutral transcript to Gemini `contents`. Public for
  /// tests; never mutates any [LlmTurn.rawAssistant].
  static List<Map<String, dynamic>> buildContents(List<LlmItem> transcript) {
    final roles = <String>[];
    final parts = <List<Object?>>[];

    void add(String role, List<Object?> ps) {
      if (ps.isEmpty) return; // a content without parts is a 400
      if (roles.isNotEmpty && roles.last == role) {
        parts.last = _merge(role, parts.last, ps);
      } else {
        roles.add(role);
        parts.add(ps);
      }
    }

    for (final item in transcript) {
      switch (item) {
        case LlmUser(:final text, :final data):
          add(GeminiApi.roleUser, [
            for (final r in data) {GeminiApi.text: CoachPrompts.userData(r)},
            if (text.isNotEmpty) {GeminiApi.text: text},
          ]);
        case LlmAssistant(:final turn):
          final raw = turn.rawAssistant;
          if (raw is List) {
            add(GeminiApi.roleModel, List<Object?>.of(raw)); // same parts
          } else {
            add(GeminiApi.roleModel, [
              if (turn.text.isNotEmpty) {GeminiApi.text: turn.text},
              for (final c in turn.toolCalls)
                {
                  GeminiApi.functionCall: {
                    GeminiApi.functionCallId: c.id,
                    GeminiApi.name: c.name,
                    GeminiApi.args: c.input,
                  },
                },
            ]);
          }
        case LlmToolResults(:final results):
          add(GeminiApi.roleUser, [
            for (final r in results) _response(r.callId, r.name, r.content),
          ]);
      }
    }

    // Every functionCall must be answered in the next 'user' content.
    for (var i = 0; i < roles.length; i++) {
      if (roles[i] != GeminiApi.roleModel) continue;
      final calls = [
        for (final p in parts[i])
          if (p is Map && p[GeminiApi.functionCall] is Map)
            p[GeminiApi.functionCall] as Map,
      ];
      if (calls.isEmpty) continue;
      final hasNext = i + 1 < roles.length;
      final answeredIds = <Object?>{};
      final answeredNames = <Object?>[];
      if (hasNext) {
        for (final p in parts[i + 1]) {
          final fr = p is Map ? p[GeminiApi.functionResponse] : null;
          if (fr is Map) {
            answeredIds.add(fr[GeminiApi.functionResponseId]);
            answeredNames.add(fr[GeminiApi.name]);
          }
        }
      }
      final fillers = <Object?>[];
      for (final c in calls) {
        final id = c[GeminiApi.functionCallId];
        final name = c[GeminiApi.name];
        final answered = id is String
            ? answeredIds.contains(id)
            : answeredNames.remove(name);
        if (!answered && name is String) {
          fillers.add(
            _response(id is String ? id : null, name, const {
              'error': _unansweredCall,
            }),
          );
        }
      }
      if (fillers.isEmpty) continue;
      if (hasNext) {
        parts[i + 1] = [...fillers, ...parts[i + 1]];
      } else {
        roles.add(GeminiApi.roleUser);
        parts.add(fillers);
      }
    }

    return [
      for (var i = 0; i < roles.length; i++)
        {GeminiApi.role: roles[i], GeminiApi.parts: parts[i]},
    ];
  }

  static Map<String, dynamic> _response(
    String? id,
    String name,
    Map<String, dynamic> content,
  ) => {
    GeminiApi.functionResponse: {
      GeminiApi.functionResponseId: ?id,
      GeminiApi.name: name,
      GeminiApi.response: content,
    },
  };

  static bool _isResponse(Object? p) =>
      p is Map && p.containsKey(GeminiApi.functionResponse);

  /// New list; a 'user' content puts its functionResponse parts first.
  static List<Object?> _merge(String role, List<Object?> a, List<Object?> b) {
    if (role != GeminiApi.roleUser) return [...a, ...b];
    return [
      ...a.where(_isResponse),
      ...b.where(_isResponse),
      ...a.where((x) => !_isResponse(x)),
      ...b.where((x) => !_isResponse(x)),
    ];
  }

  // ── transport ──────────────────────────────────────────────────────────

  void _checkKey() {
    if (_apiKey.isEmpty) {
      throw const CoachException(
        CoachErrorKind.notConfigured,
        'No Gemini API key is saved.',
      );
    }
    for (final u in _apiKey.codeUnits) {
      if (u < 0x21 || u > 0x7e) {
        throw const CoachException(
          CoachErrorKind.invalidKey,
          'The Gemini API key contains characters an API key cannot have. '
          'Paste it again.',
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
          .post(
            GeminiApi.generateContentUri(model),
            headers: headers,
            body: bytes,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw CoachException(
        CoachErrorKind.network,
        'Gemini did not answer within ${timeout.inSeconds} s.',
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
    String? status;
    String? message;
    var keyInvalid = false;
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      final e = j is Map ? j['error'] : null;
      if (e is Map) {
        if (e['status'] is String) status = e['status'] as String;
        if (e['message'] is String) message = e['message'] as String;
        final details = e['details'];
        if (details is List) {
          for (final d in details) {
            if (d is Map && d['reason'] == GeminiApi.reasonKeyInvalid) {
              keyInvalid = true;
            }
          }
        }
      }
    } on FormatException {
      // Not JSON (a proxy page): report the status only.
    }
    final m = message?.toLowerCase() ?? '';
    if (m.contains('api key not valid') ||
        m.contains('api key expired') ||
        m.contains('api_key_invalid')) {
      keyInvalid = true;
    }
    final detail = [?status, ?message].join(': ');
    final text = _scrub(detail.isEmpty ? 'HTTP $code' : 'HTTP $code $detail');
    final kind = switch (code) {
      400 when keyInvalid => CoachErrorKind.invalidKey,
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
        'Gemini sent a response that is not valid JSON.',
      );
    }
    if (j is! Map) {
      throw const CoachException(
        CoachErrorKind.server,
        'Gemini sent a response that is not a JSON object.',
      );
    }

    final usage = j[GeminiApi.usageMetadata];
    int u(String k) {
      final v = usage is Map ? usage[k] : null;
      return v is num ? v.toInt() : 0;
    }

    final inTok = u(GeminiApi.promptTokenCount);
    final outTok =
        u(GeminiApi.candidatesTokenCount) + u(GeminiApi.thoughtsTokenCount);

    final feedback = j[GeminiApi.promptFeedback];
    final blocked =
        feedback is Map && feedback[GeminiApi.blockReason] is String;
    final candidates = j[GeminiApi.candidates];
    final first = candidates is List && candidates.isNotEmpty
        ? candidates.first
        : null;

    if (first is! Map) {
      if (blocked) {
        return LlmTurn(
          stopReason: LlmStop.refusal,
          refusal: true,
          rawAssistant: const <Object?>[],
          inputTokens: inTok,
          outputTokens: outTok,
          sentBytes: sentBytes,
        );
      }
      throw const CoachException(
        CoachErrorKind.server,
        'Gemini sent a response without candidates.',
      );
    }

    final content = first[GeminiApi.content];
    final rawParts = content is Map ? content[GeminiApi.parts] : null;
    final List<Object?> parts = rawParts is List ? rawParts : <Object?>[];
    final finish = first[GeminiApi.finishReason] is String
        ? first[GeminiApi.finishReason] as String
        : null;

    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final p in parts) {
      if (p is! Map) continue;
      final t = p[GeminiApi.text];
      if (t is String && p[GeminiApi.thought] != true) text.write(t);
      final fc = p[GeminiApi.functionCall];
      if (fc is Map && fc[GeminiApi.name] is String) {
        final id = fc[GeminiApi.functionCallId];
        final args = fc[GeminiApi.args];
        calls.add(
          ToolCall(
            id: id is String && id.isNotEmpty ? id : 'call_${calls.length}',
            name: fc[GeminiApi.name] as String,
            input: args is Map
                ? Map<String, dynamic>.from(args)
                : <String, dynamic>{},
          ),
        );
      }
    }

    final refused = blocked || GeminiApi.refusalFinishReasons.contains(finish);
    final String stop;
    var keepCalls = false;
    if (refused) {
      stop = LlmStop.refusal;
    } else if (finish == null ||
        finish == GeminiApi.finishStop ||
        finish == 'FINISH_REASON_UNSPECIFIED') {
      keepCalls = true;
      stop = calls.isEmpty ? LlmStop.endTurn : LlmStop.toolUse;
    } else if (finish == GeminiApi.finishMaxTokens) {
      stop = LlmStop.maxTokens;
    } else {
      stop = finish.toLowerCase(); // e.g. malformed_function_call
    }

    return LlmTurn(
      text: text.toString(),
      toolCalls: keepCalls ? calls : const [],
      stopReason: stop,
      refusal: refused,
      rawAssistant: parts,
      inputTokens: inTok,
      outputTokens: outTok,
      sentBytes: sentBytes,
    );
  }
}
