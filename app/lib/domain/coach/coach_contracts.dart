// AI coach — domain contract (pure Dart).
//
// CONTRACT FILE. The coach answers questions about the user's own data by
// calling read-only TOOLS over the local store (never by stuffing numbers into
// the prompt), then a deterministic verifier checks every number/date/event in
// the answer against that turn's tool results. Design: research/06-ai-coach.md,
// research/07 (Google Health Coach), research/08 (WHOOP Coach).
//
// Layering: domain/coach defines models + interfaces + the orchestration use
// case; data/coach implements LlmClient (Claude, Gemini, offline demo) and
// CoachRepository (sqflite + secure key storage); features/coach renders.
// Additive changes only.

/// Which engine answers.
/// * `offline` — deterministic, on-device, NO language model: intent routing
///   over the same read-only tools + templated answers with verified numbers.
///   Works for every user, sends nothing, and is the default (research/06c:
///   Gemini Nano covers only ~5–15 % of Android Air owners' phones).
/// * `claude` / `gemini` — optional cloud models with the user's own key
///   (BYOK), behind an explicit consent sheet.
enum CoachProvider {
  offline('On this phone (no AI)'),
  claude('Claude (Anthropic)'),
  gemini('Gemini (Google)');

  const CoachProvider(this.label);
  final String label;
}

/// WHOOP-style privacy mode. `generalOnly` never calls data tools and never
/// sends any of the user's data — science/training info only.
enum CoachMode { useMyData, generalOnly }

enum ResponseLength { brief, detailed }

class CoachSettings {
  const CoachSettings({
    this.enabled = true,
    this.provider = CoachProvider.offline,
    this.model,
    this.mode = CoachMode.useMyData,
    this.length = ResponseLength.brief,
    this.consentAt,
    this.consentVersion,
    this.adultConfirmed = false,
    this.dailyRequestLimit = kDefaultDailyRequestLimit,
    this.dailyTokenLimit = kDefaultDailyTokenLimit,
    this.backupModels = true,
    this.cloudHintDismissed = false,
  });

  /// Master switch for the Ask feature. The default `offline` provider sends
  /// nothing off the phone, so it is on by default; cloud providers require
  /// [consentAt] for their provider + mode before any request.
  final bool enabled;
  final CoachProvider provider;

  /// Provider model id, e.g. 'claude-opus-5-5'. Null = provider default.
  final String? model;
  final CoachMode mode;
  final ResponseLength length;

  /// When the user accepted the disclosure for [provider] + [mode].
  final DateTime? consentAt;
  final int? consentVersion;
  final bool adultConfirmed;

  /// Daily cloud budget per provider (guardrail; user-adjustable). Once
  /// either is reached, ask() fails fast with no network call. [additive]
  final int dailyRequestLimit;
  final int dailyTokenLimit;

  /// "Use a backup model when busy" (on by default): when the chosen cloud
  /// model fails for a model-specific reason (its own quota, busy after
  /// retries, not found), the question restarts on the provider's next
  /// model with the same key. Off: straight to the on-device answer.
  /// Never another provider. [additive 2026-09-30]
  final bool backupModels;

  /// The chat's one-time "connect Claude or Gemini" card was dismissed
  /// (UI only; no engine reads it). [additive 2026-10-01]
  final bool cloudHintDismissed;

  bool get hasConsent => consentAt != null;

  CoachSettings copyWith({
    bool? enabled,
    CoachProvider? provider,
    String? model,
    bool clearModel = false,
    CoachMode? mode,
    ResponseLength? length,
    DateTime? consentAt,
    bool clearConsent = false,
    int? consentVersion,
    bool? adultConfirmed,
    int? dailyRequestLimit,
    int? dailyTokenLimit,
    bool? backupModels,
    bool? cloudHintDismissed,
  }) => CoachSettings(
    enabled: enabled ?? this.enabled,
    provider: provider ?? this.provider,
    model: clearModel ? null : (model ?? this.model),
    mode: mode ?? this.mode,
    length: length ?? this.length,
    consentAt: clearConsent ? null : (consentAt ?? this.consentAt),
    consentVersion: clearConsent
        ? null
        : (consentVersion ?? this.consentVersion),
    adultConfirmed: adultConfirmed ?? this.adultConfirmed,
    dailyRequestLimit: dailyRequestLimit ?? this.dailyRequestLimit,
    dailyTokenLimit: dailyTokenLimit ?? this.dailyTokenLimit,
    backupModels: backupModels ?? this.backupModels,
    cloudHintDismissed: cloudHintDismissed ?? this.cloudHintDismissed,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'provider': provider.name,
    if (model != null) 'model': model,
    'mode': mode.name,
    'length': length.name,
    if (consentAt != null) 'consentAt': consentAt!.toUtc().toIso8601String(),
    if (consentVersion != null) 'consentVersion': consentVersion,
    'adultConfirmed': adultConfirmed,
    'dailyRequestLimit': dailyRequestLimit,
    'dailyTokenLimit': dailyTokenLimit,
    'backupModels': backupModels,
    if (cloudHintDismissed) 'cloudHintDismissed': true,
  };

  factory CoachSettings.fromJson(Map<String, dynamic> j) => CoachSettings(
    enabled: j['enabled'] as bool? ?? true,
    provider: CoachProvider.values.byName(
      j['provider'] as String? ?? 'offline',
    ),
    model: j['model'] as String?,
    mode: CoachMode.values.byName(j['mode'] as String? ?? 'useMyData'),
    length: ResponseLength.values.byName(j['length'] as String? ?? 'brief'),
    consentAt: j['consentAt'] == null
        ? null
        : DateTime.parse(j['consentAt'] as String).toLocal(),
    consentVersion: j['consentVersion'] as int?,
    adultConfirmed: j['adultConfirmed'] as bool? ?? false,
    dailyRequestLimit:
        j['dailyRequestLimit'] as int? ?? kDefaultDailyRequestLimit,
    dailyTokenLimit: j['dailyTokenLimit'] as int? ?? kDefaultDailyTokenLimit,
    backupModels: j['backupModels'] as bool? ?? true,
    cloudHintDismissed: j['cloudHintDismissed'] as bool? ?? false,
  );
}

/// Default daily cloud budget per provider (CoachSettings). [additive]
const int kDefaultDailyRequestLimit = 50;
const int kDefaultDailyTokenLimit = 300000;

// ── Tools (provider-neutral) ──────────────────────────────────────────────

/// A tool the model may call. [inputSchema] is JSON Schema (object) with
/// `additionalProperties: false` and `required`, usable with strict mode.
class CoachToolSpec {
  const CoachToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
    this.readsUserData = true,
  });
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  /// False for tools allowed in [CoachMode.generalOnly] (e.g. methodology).
  final bool readsUserData;
}

/// A citable fact inside a tool result. The verifier accepts a number in the
/// answer only if it matches some [SourceRef.value] (within tolerance) from
/// THIS turn's tool results. The UI renders refs as tappable source chips.
class SourceRef {
  const SourceRef({
    required this.id,
    required this.label,
    this.value,
    this.unit,
    this.date,
    this.route,
  });

  /// Stable id within the turn, e.g. 'r3' (the model cites as [r3]).
  final String id;

  /// Human label, e.g. 'Recovery · Tue 22 Sep'.
  final String label;
  final double? value;
  final String? unit;

  /// yyyy-MM-dd if the fact belongs to a day.
  final String? date;

  /// App route to open when the chip is tapped, e.g. '/recovery'.
  final String? route;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    if (value != null) 'value': value,
    if (unit != null) 'unit': unit,
    if (date != null) 'date': date,
    if (route != null) 'route': route,
  };

  factory SourceRef.fromJson(Map<String, dynamic> j) => SourceRef(
    id: j['id'] as String,
    label: j['label'] as String,
    value: (j['value'] as num?)?.toDouble(),
    unit: j['unit'] as String?,
    date: j['date'] as String?,
    route: j['route'] as String?,
  );
}

class ToolCall {
  const ToolCall({required this.id, required this.name, required this.input});
  final String id; // provider's call id (echoed back in the result)
  final String name;
  final Map<String, dynamic> input;
}

class ToolResult {
  const ToolResult({
    required this.callId,
    required this.name,
    required this.content,
    this.refs = const [],
    this.isError = false,
  });
  final String callId;
  final String name;

  /// JSON-serialisable payload sent back to the model (compact, no raw
  /// sample arrays unless asked; each fact tagged with its ref id).
  final Map<String, dynamic> content;
  final List<SourceRef> refs;
  final bool isError;
}

// ── Conversation ──────────────────────────────────────────────────────────

enum ChatRole { user, assistant }

class Verification {
  const Verification({
    required this.checkedNumbers,
    required this.unsupported,
    required this.repaired,
  });

  /// How many numbers/dates in the final text were checked.
  final int checkedNumbers;

  /// Claims that matched nothing in the tool results (empty = verified).
  final List<String> unsupported;

  /// True if one repair round was needed.
  final bool repaired;

  bool get verified => unsupported.isEmpty;

  Map<String, dynamic> toJson() => {
    'checkedNumbers': checkedNumbers,
    'unsupported': unsupported,
    'repaired': repaired,
  };
  factory Verification.fromJson(Map<String, dynamic> j) => Verification(
    checkedNumbers: j['checkedNumbers'] as int,
    unsupported: (j['unsupported'] as List).cast<String>(),
    repaired: j['repaired'] as bool? ?? false,
  );
}

/// What left the phone for one answer (the "What was sent" sheet).
class SentPayload {
  const SentPayload({
    required this.provider,
    required this.model,
    required this.toolsCalled,
    required this.dataTypes,
    required this.approxChars,
    this.bytes,
    this.requests,
    this.privacyVersion,
    this.memoryContext,
    this.mode,
  });
  final CoachProvider provider;
  final String model;
  final List<String> toolsCalled;

  /// Human list, e.g. ['Recovery (7 days)', 'HRV (30 nights)'].
  final List<String> dataTypes;
  final int approxChars;

  /// Exact UTF-8 bytes of every request body sent for this answer, summed
  /// (LlmTurn.sentBytes). Null for answers stored before it existed.
  /// [additive]
  final int? bytes;

  /// Number of requests sent for this answer. [additive]
  final int? requests;

  /// Only current, scoped turns may be replayed to a cloud provider.
  final int? privacyVersion;
  final String? memoryContext;
  final CoachMode? mode;

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'model': model,
    'toolsCalled': toolsCalled,
    'dataTypes': dataTypes,
    'approxChars': approxChars,
    if (bytes != null) 'bytes': bytes,
    if (requests != null) 'requests': requests,
    if (privacyVersion != null) 'privacyVersion': privacyVersion,
    if (memoryContext != null) 'memoryContext': memoryContext,
    if (mode != null) 'mode': mode!.name,
  };
  factory SentPayload.fromJson(Map<String, dynamic> j) => SentPayload(
    provider: CoachProvider.values.byName(j['provider'] as String),
    model: j['model'] as String,
    toolsCalled: (j['toolsCalled'] as List).cast<String>(),
    dataTypes: (j['dataTypes'] as List).cast<String>(),
    approxChars: j['approxChars'] as int,
    bytes: j['bytes'] as int?,
    requests: j['requests'] as int?,
    privacyVersion: j['privacyVersion'] as int?,
    memoryContext: j['memoryContext'] as String?,
    mode: j['mode'] == null
        ? null
        : CoachMode.values.byName(j['mode'] as String),
  );
}

/// One day of a trend on an answer's card: [value] null = no reading that
/// day (never zero). [additive 2026-10-01]
class SeriesPoint {
  const SeriesPoint(this.date, this.value);

  /// yyyy-MM-dd.
  final String date;
  final double? value;

  Map<String, dynamic> toJson() => {'date': date, 'value': value};
  factory SeriesPoint.fromJson(Map<String, dynamic> j) =>
      SeriesPoint(j['date'] as String, (j['value'] as num?)?.toDouble());
}

/// What an answer's card may draw next to one cited number, copied from
/// THIS answer's tool results after verification (AnswerVisuals.build).
/// Every number here is a SourceRef value a tool returned: the UI never
/// computes a new one. Stored on the phone with the message; never sent to
/// a model (history replays text only) and never read by the verifier.
/// [additive 2026-10-01]
class AnswerVisual {
  const AnswerVisual({
    required this.refId,
    required this.metric,
    this.series = const [],
    this.usual,
    this.usualLow,
    this.usualHigh,
    this.vsUsualPct,
    this.state,
  });

  /// The cited ref this pictures (one of ChatMessage.refs).
  final String refId;

  /// 'recovery', or a RangeMetric wire name ('hrv', 'sleep_duration', …).
  final String metric;

  /// Oldest first, at most 31 days.
  final List<SeriesPoint> series;

  /// The personal usual (baseline mean) a tool returned for this metric.
  final double? usual;

  /// The usual range (Health Monitor rangeLow / rangeHigh).
  final double? usualLow, usualHigh;

  /// The tool's own "vs baseline" percentage, when it gave one.
  final double? vsUsualPct;

  /// Health Monitor state: 'in range' | 'above range' | 'below range'.
  final String? state;

  Map<String, dynamic> toJson() => {
    'refId': refId,
    'metric': metric,
    if (series.isNotEmpty) 'series': [for (final p in series) p.toJson()],
    if (usual != null) 'usual': usual,
    if (usualLow != null) 'usualLow': usualLow,
    if (usualHigh != null) 'usualHigh': usualHigh,
    if (vsUsualPct != null) 'vsUsualPct': vsUsualPct,
    if (state != null) 'state': state,
  };

  factory AnswerVisual.fromJson(Map<String, dynamic> j) => AnswerVisual(
    refId: j['refId'] as String,
    metric: j['metric'] as String,
    series: [
      for (final p in j['series'] as List? ?? const [])
        SeriesPoint.fromJson(p as Map<String, dynamic>),
    ],
    usual: (j['usual'] as num?)?.toDouble(),
    usualLow: (j['usualLow'] as num?)?.toDouble(),
    usualHigh: (j['usualHigh'] as num?)?.toDouble(),
    vsUsualPct: (j['vsUsualPct'] as num?)?.toDouble(),
    state: j['state'] as String?,
  );
}

/// One of today's plan actions shown under an answer, word for word from
/// TodayPlan (AnswerActions.fromPlan). Built on the phone after the answer;
/// never sent anywhere. [additive 2026-10-01]
class AnswerAction {
  const AnswerAction({
    required this.kind,
    required this.title,
    required this.date,
    this.meta,
    this.route,
  });

  /// A PlanActionKind name ('sleep', 'effort', …).
  final String kind;

  /// PlanAction.title, verbatim.
  final String title;

  /// The plan's day, yyyy-MM-dd.
  final String date;

  /// The action's first evidence as "{label} {value}", verbatim.
  final String? meta;
  final String? route;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'title': title,
    'date': date,
    if (meta != null) 'meta': meta,
    if (route != null) 'route': route,
  };

  factory AnswerAction.fromJson(Map<String, dynamic> j) => AnswerAction(
    kind: j['kind'] as String,
    title: j['title'] as String,
    date: j['date'] as String,
    meta: j['meta'] as String?,
    route: j['route'] as String?,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.text,
    required this.at,
    this.refs = const [],
    this.verification,
    this.sent,
    this.safety = false,
    this.proposedMemories = const [],
    this.proposedCategories = const [],
    this.proposedExpiries = const [],
    this.error,
    this.sampleData = false,
    this.answeredBy,
    this.fallbackFrom,
    this.fallbackReason,
    this.replayScope,
    this.visuals = const [],
    this.actions = const [],
    this.tools = const [],
    this.factsOnly = false,
  });

  /// [answeredBy] when the on-device engine wrote the answer.
  static const onDevice = 'on-device';
  final String id;
  final String conversationId;
  final ChatRole role;
  final String text;
  final DateTime at;

  /// Sources cited by this answer (assistant only).
  final List<SourceRef> refs;
  final Verification? verification;
  final SentPayload? sent;

  /// True if this is the deterministic safety response (no model call).
  final bool safety;

  /// Facts the model proposed to remember; the UI asks "Remember this?".
  final List<String> proposedMemories;

  /// The category the model gave each proposal ([MemoryCategory] names,
  /// parallel to [proposedMemories]); empty on older messages. [additive]
  final List<String> proposedCategories;
  final List<String?> proposedExpiries;
  String? proposedExpiry(int i) =>
      i < 0 || i >= proposedExpiries.length ? null : proposedExpiries[i];
  final String? error;

  /// The model's category for proposal [i], or null when unknown.
  MemoryCategory? proposedCategory(int i) {
    if (i < 0 || i >= proposedCategories.length) return null;
    for (final c in MemoryCategory.values) {
      if (c.name == proposedCategories[i]) return c;
    }
    return null;
  }

  /// The answer was built from the demo (sample) data, not the user's own:
  /// the chat tags it "Sample data". [additive]
  final bool sampleData;

  /// Cloud answers: the model that wrote this answer (the provider's own
  /// word for it when it says), or [onDevice]. Null for safety, error and
  /// on-device-engine answers. [additive 2026-09-30]
  final String? answeredBy;

  /// The model the user chose, when another one answered (a backup model,
  /// or the on-device fallback); null when the chosen model answered.
  final String? fallbackFrom;

  /// Why the chosen model didn't answer ([CoachErrorKind] name), when the
  /// app fell back; null for a provider-side switch.
  final String? fallbackReason;

  /// Another engine than the chosen model answered.
  bool get fellBack => fallbackFrom != null;

  /// The privacy scope an on-device fallback answer that sent nothing was
  /// built under (CoachServiceImpl.replayScopeOf); a cloud chat replays it
  /// as history only while the scope still holds. Null otherwise (a sent
  /// answer is scoped by [sent]). [additive 2026-09-30]
  final String? replayScope;

  /// Pictures for the answer's cited numbers (AnswerVisual). Empty on older
  /// messages: they show no cards. [additive 2026-10-01]
  final List<AnswerVisual> visuals;

  /// Today's plan actions for this answer's topic (AnswerAction).
  /// [additive 2026-10-01]
  final List<AnswerAction> actions;

  /// The tools this answer's engine called ('get_sleep', 'get_range:hrv'),
  /// without the app's own context reads: the chat's topic comes from
  /// these. [additive 2026-10-01]
  final List<String> tools;

  /// The answer is the deterministic facts table (the verifier or output
  /// policy rejected the model's text twice). The table re-verifies by
  /// construction, so [verification] cannot tell. [additive 2026-10-01]
  final bool factsOnly;

  ChatMessage copyWith({
    String? conversationId,
    String? text,
    List<SourceRef>? refs,
    bool? sampleData,
    List<AnswerVisual>? visuals,
    List<AnswerAction>? actions,
    List<String>? tools,
    bool? factsOnly,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId ?? this.conversationId,
    role: role,
    text: text ?? this.text,
    at: at,
    refs: refs ?? this.refs,
    verification: verification,
    sent: sent,
    safety: safety,
    proposedMemories: proposedMemories,
    proposedCategories: proposedCategories,
    proposedExpiries: proposedExpiries,
    error: error,
    sampleData: sampleData ?? this.sampleData,
    answeredBy: answeredBy,
    fallbackFrom: fallbackFrom,
    fallbackReason: fallbackReason,
    replayScope: replayScope,
    visuals: visuals ?? this.visuals,
    actions: actions ?? this.actions,
    tools: tools ?? this.tools,
    factsOnly: factsOnly ?? this.factsOnly,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'role': role.name,
    'text': text,
    'at': at.toUtc().toIso8601String(),
    'refs': refs.map((r) => r.toJson()).toList(),
    if (verification != null) 'verification': verification!.toJson(),
    if (sent != null) 'sent': sent!.toJson(),
    'safety': safety,
    'proposedMemories': proposedMemories,
    if (proposedCategories.isNotEmpty) 'proposedCategories': proposedCategories,
    if (proposedExpiries.isNotEmpty) 'proposedExpiries': proposedExpiries,
    if (error != null) 'error': error,
    if (sampleData) 'sampleData': true,
    if (answeredBy != null) 'answeredBy': answeredBy,
    if (fallbackFrom != null) 'fallbackFrom': fallbackFrom,
    if (fallbackReason != null) 'fallbackReason': fallbackReason,
    if (replayScope != null) 'replayScope': replayScope,
    if (visuals.isNotEmpty) 'visuals': [for (final v in visuals) v.toJson()],
    if (actions.isNotEmpty) 'actions': [for (final a in actions) a.toJson()],
    if (tools.isNotEmpty) 'tools': tools,
    if (factsOnly) 'factsOnly': true,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    conversationId: j['conversationId'] as String,
    role: ChatRole.values.byName(j['role'] as String),
    text: j['text'] as String,
    at: DateTime.parse(j['at'] as String).toLocal(),
    refs: (j['refs'] as List? ?? const [])
        .map((e) => SourceRef.fromJson(e as Map<String, dynamic>))
        .toList(),
    verification: j['verification'] == null
        ? null
        : Verification.fromJson(j['verification'] as Map<String, dynamic>),
    sent: j['sent'] == null
        ? null
        : SentPayload.fromJson(j['sent'] as Map<String, dynamic>),
    safety: j['safety'] as bool? ?? false,
    proposedMemories: (j['proposedMemories'] as List? ?? const [])
        .cast<String>(),
    proposedCategories: [
      for (final c in j['proposedCategories'] as List? ?? const [])
        if (c is String) c,
    ],
    proposedExpiries: (j['proposedExpiries'] as List? ?? const [])
        .cast<String?>(),
    error: j['error'] as String?,
    sampleData: j['sampleData'] as bool? ?? false,
    answeredBy: j['answeredBy'] as String?,
    fallbackFrom: j['fallbackFrom'] as String?,
    fallbackReason: j['fallbackReason'] as String?,
    replayScope: j['replayScope'] as String?,
    visuals: [
      for (final v in j['visuals'] as List? ?? const [])
        AnswerVisual.fromJson(v as Map<String, dynamic>),
    ],
    actions: [
      for (final a in j['actions'] as List? ?? const [])
        AnswerAction.fromJson(a as Map<String, dynamic>),
    ],
    tools: [
      for (final t in j['tools'] as List? ?? const [])
        if (t is String) t,
    ],
    factsOnly: j['factsOnly'] as bool? ?? false,
  );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// A user-confirmed fact the coach may use ("training for a half marathon
/// on 15 Nov"). Never health numbers — those always come from tools.
/// Memory categories (WHOOP "My Memory" uses the same seven; research/06d).
enum MemoryCategory {
  goals('Goals'),
  identity('About you'),
  lifestyle('Lifestyle'),
  preferences('Preferences'),
  events('Events'),
  healthHistory('Health history'),
  mood('Mood');

  const MemoryCategory(this.label);
  final String label;

  /// Health history and mood are sensitive: proposed only in the user's own
  /// words, and saved only after a second, explicit confirm.
  bool get needsExplicitConfirm => this == healthHistory || this == mood;
}

class MemoryFact {
  const MemoryFact({
    required this.id,
    required this.text,
    required this.createdAt,
    this.updatedAt,
    this.category = MemoryCategory.preferences,
    this.expiresOn,
  });
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final MemoryCategory category;

  /// yyyy-MM-dd after which a temporary fact (an event, an illness) stops
  /// being used. Null = until deleted. Users can always delete ("memory that
  /// won't forget" is a top complaint in research/06d).
  final String? expiresOn;
}

/// Where a question was asked from ("Ask about this" on a screen).
class AskContext {
  const AskContext({
    this.screen,
    this.date,
    this.insightId,
    this.seedText,
    this.seedRefs = const [],
  });

  /// 'today' | 'recovery' | 'sleep' | 'strain' | 'trends' | 'journal' |
  /// 'health', or an InsightKind name when opened from a card's "Discuss".
  final String? screen;
  final String? date;

  /// "Discuss" from an insight card (see insight_contracts.dart). The chat
  /// sends [seedText] and [seedRefs] as card context in the question's own
  /// user message (LlmUser.data), so the first answer cites the card's own
  /// numbers. Seed text is data, never instructions.
  final String? insightId;
  final String? seedText;
  final List<SourceRef> seedRefs;
}

// ── Provider-neutral LLM interface (implemented in data/coach) ───────────

/// One model turn: either text (final) or tool calls to execute.
class LlmTurn {
  const LlmTurn({
    this.text = '',
    this.toolCalls = const [],
    this.stopReason = 'end_turn',
    this.refusal = false,
    this.rawAssistant,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.sentBytes = 0,
    this.model,
  });
  final String text;
  final List<ToolCall> toolCalls;
  final String stopReason;
  final bool refusal;

  /// Provider-native assistant content to append back UNCHANGED on the next
  /// request (Claude: the full `content` array incl. thinking blocks —
  /// required for preserved thinking; Gemini: the `parts`).
  final Object? rawAssistant;

  /// Billed tokens of this request (input includes cache reads/writes) and
  /// the exact UTF-8 size of the request body that produced it. Zero for
  /// the offline client and synthetic turns. [additive]
  final int inputTokens;
  final int outputTokens;
  final int sentBytes;

  /// The model the provider says produced this turn (Claude's response
  /// `model`, which a server-side refusal fallback can change). Null = the
  /// requested model. [additive 2026-09-30]
  final String? model;
}

/// Provider-neutral transcript item for the LLM client. The client owns the
/// translation to its wire format and must replay [LlmTurn.rawAssistant]
/// byte-for-byte (append-only history).
sealed class LlmItem {
  const LlmItem();
}

class LlmUser extends LlmItem {
  const LlmUser(this.text, {this.data = const []});
  final String text;

  /// App data attached to this user message, e.g. the insight card a chat
  /// was opened from ("Discuss"). [additive] Each result goes on the wire
  /// as a labelled data block BEFORE [text] (CoachPrompts.userData), in
  /// the same user message: never as a synthetic assistant tool call. A
  /// fabricated tool_use turn carries no thinking block (Claude Opus 5.5
  /// thinks on every turn) and a fabricated Gemini 3 functionCall no thought
  /// signature, and either can be rejected. Its refs are this ask's
  /// evidence like any tool result's; its free text is quoted data.
  final List<ToolResult> data;
}

class LlmAssistant extends LlmItem {
  const LlmAssistant(this.turn);
  final LlmTurn turn;
}

class LlmToolResults extends LlmItem {
  const LlmToolResults(this.results);
  final List<ToolResult> results;
}

abstract class LlmClient {
  CoachProvider get provider;
  String get model;

  /// Sends system + transcript + tools; returns the next assistant turn.
  /// Throws [CoachException] on transport/auth/quota errors.
  Future<LlmTurn> next({
    required String system,
    required List<LlmItem> transcript,
    required List<CoachToolSpec> tools,
    required ResponseLength length,
  });
}

enum CoachErrorKind {
  notConfigured,
  invalidKey,
  rateLimited,

  /// The provider account is out of credit or quota (HTTP 402, or a 429 for
  /// the day).
  quotaExceeded,

  /// Airlog's own daily budget for the cloud coach is used up, so nothing
  /// was sent; the message says which limit and when it resets.
  dailyLimit,
  network,
  refused,
  server,
  unknown,
}

class CoachException implements Exception {
  const CoachException(this.kind, [this.message]);
  final CoachErrorKind kind;
  final String? message;
  @override
  String toString() => 'CoachException(${kind.name}: $message)';
}

/// A failure bound to the model that was asked, not to the account: its
/// own quota (a per-model daily 429), busy after the client's retries
/// (429 / 503 / 529), or not found (404). The same question may restart on
/// the provider's next model; an account-wide failure (bad key, billing,
/// out of credit) is a plain [CoachException]. [additive 2026-09-30]
class ModelUnavailable extends CoachException {
  const ModelUnavailable(
    super.kind,
    super.message, {
    this.retryAfter,
    this.dayQuota = false,
  });

  /// The provider's own wait (Retry-After, Gemini's RetryInfo.retryDelay).
  final Duration? retryAfter;

  /// The model's quota for the DAY is used up (until the provider's reset).
  final bool dayQuota;

  @override
  String toString() => 'ModelUnavailable(${kind.name}: $message)';
}

/// A model the coach knows can't answer before [until]: later questions
/// skip it, with no failed request first. [reason] is the failure that
/// said so. [additive 2026-09-30]
class ModelDown {
  const ModelDown(this.until, this.reason);
  final DateTime until;
  final CoachErrorKind reason;
}

// ── Persistence (implemented in data/coach) ───────────────────────────────

abstract class CoachRepository {
  Future<CoachSettings> settings();
  Future<void> saveSettings(CoachSettings s);

  /// API keys live in secure storage only; never in SQLite or exports.
  Future<bool> hasApiKey(CoachProvider p);
  Future<void> saveApiKey(CoachProvider p, String key);
  Future<void> deleteApiKey(CoachProvider p);

  Future<List<Conversation>> conversations();
  Future<List<ChatMessage>> messages(String conversationId);
  Future<Conversation> createConversation(String title);
  Future<void> appendMessage(ChatMessage m);
  Future<void> deleteConversation(String id);
  Future<void> deleteAllConversations();

  Future<List<MemoryFact>> memories();
  Future<MemoryFact> addMemory(
    String text, {
    MemoryCategory category = MemoryCategory.preferences,
    String? expiresOn,
  });
  Future<void> updateMemory(
    String id,
    String text, {
    MemoryCategory? category,
    String? expiresOn,
  });

  /// Global memory switch (off = coach never reads or proposes memories).
  Future<bool> memoryEnabled();
  Future<void> setMemoryEnabled(bool on);
  Future<void> deleteMemory(String id);

  /// Builds the LLM client for the current settings + stored key (the
  /// offline provider returns a deterministic client with no network).
  /// Throws CoachException(notConfigured) when a cloud key is missing.
  Future<LlmClient> client();

  /// The engines to try for one question, in order: the chosen model, then
  /// (when [CoachSettings.backupModels] is on) the same provider's backup
  /// models with the same key (ProviderModels.chains). Never another
  /// provider. The offline provider: just the on-device engine. Throws like
  /// [client]. [additive 2026-09-30]
  Future<List<LlmClient>> modelChain();

  /// The on-device engine (no network, no key): the last resort when the
  /// cloud provider can't answer. [additive 2026-09-30]
  LlmClient onDeviceClient();

  /// Remembers that [model] can't answer for a while ([e]'s retry delay:
  /// in memory; its day quota: until the provider's reset, persisted), so
  /// later questions skip it. No wait known: nothing is remembered.
  /// [additive 2026-09-30]
  Future<void> noteModelUnavailable(String model, ModelUnavailable e);

  /// When [model] is known to be down, until when and why; null = try it.
  Future<ModelDown?> modelDown(String model);

  /// Today's cloud usage against the daily budget (guardrail). Null = offline
  /// provider or not tracked. It has a default so existing fakes still compile.
  Future<CoachUsage?> usageToday() async => null;
}

/// Daily cloud budget for the active provider (local day). Once
/// [exhausted], ask() fails fast with a clear message and makes no network
/// call.
class CoachUsage {
  const CoachUsage({
    required this.provider,
    required this.requests,
    required this.inputTokens,
    required this.outputTokens,
    required this.requestLimit,
    required this.tokenLimit,
  });
  final CoachProvider provider;
  final int requests;
  final int inputTokens;
  final int outputTokens;
  final int requestLimit;
  final int tokenLimit;

  bool get exhausted =>
      requests >= requestLimit || inputTokens + outputTokens >= tokenLimit;
}

/// The use case the UI calls. Implemented in domain/coach (pure Dart) on top
/// of [LlmClient], the tool executor and the verifier.
abstract class CoachService {
  /// Ask a question in [conversationId] (null = new conversation). Returns
  /// the stored assistant message (verified, with refs and SentPayload).
  Future<ChatMessage> ask(
    String question, {
    String? conversationId,
    AskContext? context,
  });

  /// Suggested starter prompts (deterministic, from today's data).
  Future<List<String>> suggestions({AskContext? context});
}
