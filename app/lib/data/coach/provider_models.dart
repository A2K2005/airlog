// Cloud coach providers: model ids, list prices, effort, beta headers and
// every wire field name / endpoint the raw-HTTP clients (claude_client.dart,
// gemini_client.dart) use. One file, so a model or price change is one edit.
//
// Sources
//   * Claude: the claude-api reference (models table; model-migration
//     "Migrating to Claude Opus 5.5" and the Claude Sonnet 5.5 refusal
//     notes; curl/examples.md; tool-use-concepts.md; prompt-caching.md;
//     error-codes.md). Model ids are aliases, never date-suffixed.
//   * Gemini: research/06b-gemini-api.md (condensed sub-agent report,
//     accessed 2026-09-29) plus the long-standing v1beta generateContent REST
//     shape. The Gemini 3.x model ids and prices come from that report. The
//     model ids and the request field names marked "verified live
//     2026-09-29" were checked against the live API that day (a made-up
//     weather tool, no health data); prices and the 402 error shape remain
//     UNVERIFIED.
//
// Pure Dart, no I/O.

import '../../domain/coach/coach_contracts.dart';

/// One selectable cloud model.
class LlmModelSpec {
  const LlmModelSpec({
    required this.provider,
    required this.id,
    required this.label,
    required this.inputUsdPerMTok,
    required this.outputUsdPerMTok,
    this.effort,
    this.thinkingBudget,
    this.serverFallback = false,
    this.priceNote,
  });

  final CoachProvider provider;

  /// Provider model id sent on the wire, e.g. 'claude-opus-5-5'.
  final String id;

  /// Human label, e.g. 'Claude Opus 5.5'.
  final String label;

  /// List price in USD per million tokens (standard, uncached input).
  final double inputUsdPerMTok;
  final double outputUsdPerMTok;

  /// Claude `output_config.effort`; null = the field is omitted (Haiku 4.5
  /// has no effort parameter).
  final String? effort;

  /// Claude models before 4.6 (Haiku 4.5) think only in manual mode:
  /// `thinking: {type: "enabled", budget_tokens: N}`, N ≥ 1024 and below
  /// `max_tokens`. They take neither adaptive thinking (a 400) nor effort.
  /// Null = send no `thinking` (Opus / Sonnet 5.5 think adaptively by
  /// default and reject `enabled`). Source: platform.claude.com/docs/en/
  /// build-with-claude/extended-thinking ("Budget rules and tuning";
  /// "Migrating to adaptive thinking"), read 2026-09-30.
  final int? thinkingBudget;

  /// Claude only: send `fallbacks: "default"` with the
  /// [ClaudeApi.serverFallbackBeta] header (safety-classifier declines are
  /// retried server-side on Anthropic's recommended model).
  final bool serverFallback;

  /// Caveat about the price, if any.
  final String? priceNote;
}

/// The model catalogue for the cloud clients.
abstract final class ProviderModels {
  // ── Claude ──────────────────────────────────────────────────────────────
  static const claudeOpus = 'claude-opus-5-5';
  static const claudeSonnet = 'claude-sonnet-5-5';
  static const claudeHaiku = 'claude-haiku-4-5';

  /// Default Claude model when the settings name none.
  static const claudeDefault = claudeOpus;

  // ── Gemini (ids verified live 2026-09-29; prices: research/06b) ────────
  static const geminiFlash = 'gemini-3.8-flash';
  static const geminiFlashLite = 'gemini-3.5-flash-lite';

  /// Default Gemini model when the settings name none.
  static const geminiDefault = geminiFlash;

  /// Cheaper Gemini option.
  static const geminiBudget = geminiFlashLite;

  static const claude = <LlmModelSpec>[
    LlmModelSpec(
      provider: CoachProvider.claude,
      id: claudeOpus,
      label: 'Claude Opus 5.5',
      inputUsdPerMTok: 4,
      outputUsdPerMTok: 20,
      effort: 'medium',
      serverFallback: true,
    ),
    LlmModelSpec(
      provider: CoachProvider.claude,
      id: claudeSonnet,
      label: 'Claude Sonnet 5.5',
      inputUsdPerMTok: 2,
      outputUsdPerMTok: 10,
      effort: 'medium',
      serverFallback: true,
    ),
    LlmModelSpec(
      provider: CoachProvider.claude,
      id: claudeHaiku,
      label: 'Claude Haiku 4.5',
      inputUsdPerMTok: 1,
      outputUsdPerMTok: 5,
      // As a backup for Opus / Sonnet (medium effort) it still reasons
      // before it answers: a fixed thinking budget, well under max_tokens.
      thinkingBudget: 2048,
    ),
  ];

  static const gemini = <LlmModelSpec>[
    LlmModelSpec(
      provider: CoachProvider.gemini,
      id: geminiFlash,
      label: 'Gemini 3.8 Flash',
      inputUsdPerMTok: 0.75,
      outputUsdPerMTok: 3.75,
      priceNote: 'Introductory price; doubles on 2027-01-01 (research/06b).',
    ),
    LlmModelSpec(
      provider: CoachProvider.gemini,
      id: geminiFlashLite,
      label: 'Gemini 3.5 Flash-Lite',
      inputUsdPerMTok: 0.30,
      outputUsdPerMTok: 2.50,
    ),
  ];

  static const all = <LlmModelSpec>[...claude, ...gemini];

  /// The catalogue entry for [id], or null for an id this file doesn't know.
  static LlmModelSpec? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Default model id for a cloud [provider]; null for offline.
  static String? defaultFor(CoachProvider provider) => switch (provider) {
    CoachProvider.offline => null,
    CoachProvider.claude => claudeDefault,
    CoachProvider.gemini => geminiDefault,
  };

  static List<LlmModelSpec> forProvider(CoachProvider provider) => [
    for (final m in all)
      if (m.provider == provider) m,
  ];

  /// "Use a backup model when busy": each provider's models, in the order
  /// the coach falls back through them (same key; never another provider,
  /// because consent covers one). PRODUCT_PLAN §7 "Coach model fallback".
  static const chains = <CoachProvider, List<String>>{
    CoachProvider.claude: [claudeOpus, claudeSonnet, claudeHaiku],
    CoachProvider.gemini: [geminiFlash, geminiFlashLite],
  };

  /// The models to try for one question, in order: [model] (or the
  /// provider's default), then, when [backups], the models after it in its
  /// provider's chain (a model outside the chain is followed by the whole
  /// chain). Empty for offline.
  static List<String> chainFor(
    CoachProvider provider,
    String? model, {
    bool backups = true,
  }) {
    final first = (model == null || model.trim().isEmpty)
        ? defaultFor(provider)
        : model.trim();
    if (first == null) return const [];
    if (!backups) return [first];
    final chain = chains[provider] ?? const <String>[];
    final at = chain.indexOf(first);
    return [
      first,
      for (final m in at < 0 ? chain : chain.sublist(at + 1))
        if (m != first) m,
    ];
  }
}

/// Estimated cost in USD of one request at list prices, or null for an
/// unknown model. An ESTIMATE: [inputTokens] is priced entirely at the
/// standard input rate, although for Claude it includes cache writes (billed
/// higher) and cache reads (billed far lower), and Gemini 3.8 Flash's
/// introductory price doubles on 2027-01-01. The provider bills the user's
/// own key; this only feeds the in-app estimate.
double? estimateCostUsd(String model, int inputTokens, int outputTokens) {
  final m = ProviderModels.byId(model);
  if (m == null) return null;
  final inTok = inputTokens < 0 ? 0 : inputTokens;
  final outTok = outputTokens < 0 ? 0 : outputTokens;
  return (inTok * m.inputUsdPerMTok + outTok * m.outputUsdPerMTok) / 1e6;
}

/// Claude Messages API wire constants (claude-api reference).
abstract final class ClaudeApi {
  static const endpoint = 'https://api.anthropic.com/v1/messages';
  static const version = '2023-06-01';
  static const headerKey = 'x-api-key';
  static const headerVersion = 'anthropic-version';
  static const headerBeta = 'anthropic-beta';

  /// Gates the scalar `fallbacks: "default"` form. (The array form uses a
  /// different header, and pairing either header with the other form 400s.)
  static const serverFallbackBeta = 'server-side-fallback-2026-07-01';
  static const fallbacksDefault = 'default';

  /// Non-streaming ceiling; thinking counts toward it.
  static const maxTokens = 16000;
}

/// Provider-neutral [LlmTurn.stopReason] values (Claude's `stop_reason`
/// spelling; GeminiClient maps its finishReason onto them).
abstract final class LlmStop {
  static const endTurn = 'end_turn';
  static const toolUse = 'tool_use';
  static const maxTokens = 'max_tokens';
  static const refusal = 'refusal';
}

/// Gemini v1beta generateContent wire constants.
///
/// Verified live 2026-09-29 (gemini-3.8-flash and gemini-3.5-flash-lite, a
/// made-up weather tool, no health data):
///   * [functionDeclarationSchema] — `parametersJsonSchema` (full JSON Schema,
///     accepts `additionalProperties`) is accepted; it is used instead of the
///     OpenAPI-subset `parameters`, which historically rejected
///     `additionalProperties`.
///   * [thinkingLevel] and its values 'low' / 'medium' are accepted.
///   * [functionResponseId] — a `functionCall` comes back with an `id` and a
///     `thoughtSignature`; replaying the model turn unchanged plus a
///     `functionResponse` carrying that `id` returns a normal final answer.
///   * Both model ids exist. The API often answers 503 "high demand"; a
///     retry about 8 s later succeeded (GeminiClient retries a 503).
/// Still UNVERIFIED: the error body / 402 prepay status.
abstract final class GeminiApi {
  static const base = 'https://generativelanguage.googleapis.com/v1beta';

  /// `POST {base}/models/{model}:generateContent`; the key goes in a header,
  /// never in the URL.
  static Uri generateContentUri(String model) =>
      Uri.parse('$base/models/${Uri.encodeComponent(model)}:generateContent');

  static const headerKey = 'x-goog-api-key';

  // Request fields.
  static const systemInstruction = 'systemInstruction';
  static const contents = 'contents';
  static const role = 'role';
  static const roleUser = 'user';
  static const roleModel = 'model';
  static const parts = 'parts';
  static const text = 'text';
  static const tools = 'tools';
  static const functionDeclarations = 'functionDeclarations';
  static const functionDeclarationSchema =
      'parametersJsonSchema'; // verified live 2026-09-29
  static const toolConfig = 'toolConfig';
  static const functionCallingConfig = 'functionCallingConfig';
  static const mode = 'mode';
  static const modeAuto = 'AUTO';
  static const generationConfig = 'generationConfig';
  static const thinkingConfig = 'thinkingConfig';
  static const thinkingLevel = 'thinkingLevel'; // verified live 2026-09-29
  static const thinkingLow = 'low'; // verified live — ResponseLength.brief
  static const thinkingMedium =
      'medium'; // verified live — ResponseLength.detailed
  static const maxOutputTokens = 'maxOutputTokens';
  static const maxOutputTokensValue = 8192;

  // Parts.
  static const functionCall = 'functionCall';
  static const functionResponse = 'functionResponse';
  static const functionCallId = 'id';
  static const functionResponseId = 'id'; // verified live 2026-09-29
  static const name = 'name';
  static const args = 'args';
  static const response = 'response';
  static const thought = 'thought';
  static const thoughtSignature = 'thoughtSignature';

  // Response fields.
  static const candidates = 'candidates';
  static const content = 'content';
  static const finishReason = 'finishReason';
  static const promptFeedback = 'promptFeedback';
  static const blockReason = 'blockReason';
  static const usageMetadata = 'usageMetadata';
  static const promptTokenCount = 'promptTokenCount';
  static const candidatesTokenCount = 'candidatesTokenCount';
  static const thoughtsTokenCount = 'thoughtsTokenCount';

  static const finishStop = 'STOP';
  static const finishMaxTokens = 'MAX_TOKENS';

  /// finishReasons treated as a refusal (no text/tool calls are used).
  static const refusalFinishReasons = {
    'SAFETY',
    'PROHIBITED_CONTENT',
    'BLOCKLIST',
    'SPII',
    'RECITATION',
  };

  /// `error.details[].reason` for a bad key (google.rpc.ErrorInfo).
  static const reasonKeyInvalid = 'API_KEY_INVALID';
}
