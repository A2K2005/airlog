// CoachServiceImpl: the ask / suggest use case (pure Dart).
//
//   question ─► input router (safety.dart): red flags, medication, eating,
//               pregnancy, minors → fixed copy, no model, no network
//            ─► settings + consent gate (cloud providers only)
//            ─► daily budget (cloud): exhausted → clear message, no network
//            ─► card seed ("Discuss"): the card's facts are run once
//               (get_insight_card, r1…) and attached to the question's own
//               user message as quoted "Card context" data (LlmUser.data):
//               never a synthetic assistant tool call, which would carry no
//               thinking block / thought signature. Its refs join this
//               ask's evidence like any tool result
//            ─► tool loop: ≤ 4 tool rounds per answer, each request under a
//               timeout and re-checked against the budget; parallel tool
//               calls run together and go back in ONE results item; the
//               transcript is append-only and replays each
//               LlmTurn.rawAssistant unchanged
//            ─► verifier + output policy ─► one repair round ─► both again
//            ─► still failing: deterministic facts table + honest note
//            ─► stored assistant message (refs, Verification, SentPayload)
//
// General-only mode offers only tools that read no user data, replays no
// earlier messages and never injects a card. Memory tools are offered only
// when memory is on. Earlier asks in a conversation are replayed as plain
// text (no thinking blocks, citations stripped), so each ask can carry its
// own date and context in the system prompt.

import 'dart:async';

import '../day_key.dart';
import '../repositories.dart';
import '../results.dart';
import 'coach_contracts.dart';
import 'format.dart';
import 'policy.dart';
import 'prompts.dart';
import 'safety.dart';
import 'tools.dart';
import 'verifier.dart';

/// Version of the cloud disclosure the user must have accepted.
const int kCoachConsentVersion = 1;

class CoachServiceImpl implements CoachService {
  CoachServiceImpl({
    required this.health,
    required this.coach,
    DateTime Function()? clock,
    this.maxToolRounds = 4,
    this.requestTimeout = const Duration(seconds: 150),
    this.historyTurns = 6,
  }) : clock = clock ?? DateTime.now;

  final HealthRepository health;
  final CoachRepository coach;
  final DateTime Function() clock;

  /// Tool rounds per answer (the repair round included).
  final int maxToolRounds;

  /// Per model request (the HTTP clients have their own, shorter timeout).
  final Duration requestTimeout;

  /// Earlier question/answer pairs replayed as context.
  final int historyTurns;

  int _seq = 0;
  String _id(String kind) =>
      '$kind-${clock().microsecondsSinceEpoch.toRadixString(36)}-${_seq++}';

  static const refusalText =
      'I can\'t help with that one. I can answer questions about your '
      'recovery, sleep, strain and training data.';

  @override
  Future<ChatMessage> ask(
    String question, {
    String? conversationId,
    AskContext? context,
  }) async {
    final q = question.trim();
    if (q.isEmpty) {
      throw const CoachException(CoachErrorKind.unknown, 'Empty question.');
    }
    final settings = await coach.settings();
    if (!settings.enabled) {
      throw const CoachException(
        CoachErrorKind.notConfigured,
        'Ask is turned off. Turn it on in Settings → Coach.',
      );
    }

    // 1. Input router: fixed response, no model, no network.
    final flag = SafetyCheck.check(q);
    if (flag != null) {
      final conv = await _conversation(conversationId, q);
      await _storeUser(conv, q);
      return _store(
        ChatMessage(
          id: _id('a'),
          conversationId: conv,
          role: ChatRole.assistant,
          text: flag.message,
          at: clock(),
          safety: true,
          verification: const Verification(
            checkedNumbers: 0,
            unsupported: [],
            repaired: false,
          ),
        ),
      );
    }

    // 2. Cloud gate: consent for this provider + mode, adult, current text.
    final cloud = settings.provider != CoachProvider.offline;
    if (cloud) _requireConsent(settings);
    final client = await coach.client(); // throws notConfigured (no key)

    final useData = settings.mode == CoachMode.useMyData;
    final conv = await _conversation(conversationId, q);
    final history = useData
        ? await _history(conv, cloud: cloud)
        : const <LlmItem>[];
    await _storeUser(conv, q);

    // 3. Daily budget: fail fast, before any network call.
    if (cloud) {
      final u = await coach.usageToday();
      if (u != null && u.exhausted) {
        return _store(
          ChatMessage(
            id: _id('a'),
            conversationId: conv,
            role: ChatRole.assistant,
            text: budgetText(u),
            at: clock(),
            error: CoachErrorKind.dailyLimit.name,
          ),
        );
      }
    }

    final now = clock();
    final memoryOn = useData && await coach.memoryEnabled();
    final seeded = useData && _hasSeed(context);
    final tools = CoachTools.forMode(settings.mode, memory: memoryOn);
    final latest = useData ? await health.latestDate() : null;
    final system = CoachPrompts.system(
      now: now,
      latestDate: latest,
      mode: settings.mode,
      length: settings.length,
      provider: settings.provider,
      context: useData ? context : null,
    );
    final toolbox = CoachToolbox(
      health: health,
      coach: coach,
      now: now,
      cloud: cloud,
      mode: settings.mode,
      memoryEnabled: memoryOn,
      seed: seeded ? context : null,
      question: q,
    );
    final memories = memoryOn
        ? [
            for (final m in await coach.memories())
              if (m.expiresOn == null ||
                  m.expiresOn!.compareTo(DayKey.of(now)) >= 0)
                m.text,
          ]
        : const <String>[];

    final calls = <ToolCall>[];
    final results = <ToolResult>[];
    var chars =
        system.length +
        q.length +
        [for (final i in history) _chars(i)].fold<int>(0, (a, b) => a + b) +
        _toolChars(tools);
    var sentBytes = 0, requests = 0, rounds = 0;

    // The card's own facts, as data in the question's message (first refs
    // r1…, Google Health API withholding applied). They are evidence
    // (results) but not a call: nothing asked for them.
    final seed = seeded
        ? await toolbox.run(const [
            ToolCall(id: 'seed_card', name: CoachTools.insightCard, input: {}),
          ])
        : const <ToolResult>[];
    results.addAll(seed);
    // Built once and never rebuilt: every request of this ask replays the
    // same question message, so the history stays append-only.
    final transcript = <LlmItem>[...history, LlmUser(q, data: seed)];
    for (final r in seed) {
      chars += _jsonChars(r.content);
    }

    Future<LlmTurn> request() async {
      if (cloud) await _checkBudget();
      final t = await client
          .next(
            system: system,
            transcript: List.unmodifiable(transcript),
            tools: tools,
            length: settings.length,
          )
          .timeout(
            requestTimeout,
            onTimeout: () => throw const CoachException(
              CoachErrorKind.network,
              'The AI provider took too long to answer.',
            ),
          );
      requests++;
      sentBytes += t.sentBytes;
      return t;
    }

    /// Runs the model until it answers in text. Null = it kept calling
    /// tools past the round limit (every call still gets a result, so the
    /// transcript stays valid for the repair round).
    Future<LlmTurn?> loop() async {
      var capped = false;
      while (true) {
        final turn = await request();
        transcript.add(LlmAssistant(turn));
        if (turn.refusal || turn.toolCalls.isEmpty) return turn;
        if (rounds >= maxToolRounds) {
          transcript.add(LlmToolResults(_limitResults(turn.toolCalls)));
          if (capped) return null;
          capped = true;
          continue;
        }
        rounds++;
        final res = await toolbox.run(turn.toolCalls);
        calls.addAll(turn.toolCalls);
        results.addAll(res);
        transcript.add(LlmToolResults(res));
        for (final r in res) {
          chars += _jsonChars(r.content);
        }
      }
    }

    String? error;
    String text;
    VerificationReport? report;
    List<SourceRef> shownRefs = const [];

    try {
      final first = await loop();
      if (first != null && first.refusal) {
        error = CoachErrorKind.refused.name;
        text = refusalText;
      } else {
        text = first?.text.trim() ?? '';
        report = _verify(text, q, now, calls, results, memories, false);
        final policy = OutputPolicy.check(text);
        if (text.isEmpty || !report.verified || !policy.ok) {
          // One repair round for both the verifier and the output policy.
          final issues = text.isEmpty
              ? ['(no answer text was produced)']
              : report.unsupported;
          final fix = CoachPrompts.repair(
            issues,
            policy: [for (final v in policy.violations) v.describe],
            policyFixes: [for (final k in policy.kinds) OutputPolicy.fix(k)],
          );
          transcript.add(LlmUser(fix));
          chars += fix.length;
          final second = await loop();
          final t2 = second == null || second.refusal ? '' : second.text.trim();
          final r2 = _verify(t2, q, now, calls, results, memories, true);
          if (t2.isNotEmpty && r2.verified && OutputPolicy.check(t2).ok) {
            text = t2;
            report = r2;
          } else {
            // Deterministic fallback: this turn's facts, verified by
            // construction.
            final (table, refs) = CoachPrompts.factsTable(
              results,
              preferIds: report.citedRefIds,
            );
            text = table;
            report = _verify(text, q, now, calls, results, memories, true);
            shownRefs = refs;
          }
        }
        if (shownRefs.isEmpty) {
          shownRefs = CoachPrompts.citedRefs(text, [
            for (final r in results) ...r.refs,
          ]);
        }
      }
    } on CoachException catch (e) {
      error = e.kind.name;
      text = _errorText(e);
    }

    final sent = cloud
        ? SentPayload(
            provider: settings.provider,
            model: client.model,
            toolsCalled: [
              for (final n in {for (final c in calls) c.name}) n,
            ],
            dataTypes: [
              'Your question',
              if (history.isNotEmpty) 'Earlier messages in this chat',
              ...{...toolbox.dataTypes},
            ],
            approxChars: sentBytes > 0 ? sentBytes : chars,
            bytes: sentBytes,
            requests: requests,
          )
        : null;

    return _store(
      ChatMessage(
        id: _id('a'),
        conversationId: conv,
        role: ChatRole.assistant,
        text: text,
        at: clock(),
        refs: shownRefs,
        verification: report?.verification,
        sent: sent,
        proposedMemories: error == null && memoryOn
            ? [for (final p in toolbox.proposals) p.text]
            : const [],
        proposedCategories: error == null && memoryOn
            ? [for (final p in toolbox.proposals) p.category.name]
            : const [],
        error: error,
      ),
    );
  }

  static bool _hasSeed(AskContext? c) =>
      c != null &&
      (c.seedRefs.isNotEmpty || (c.seedText?.trim().isNotEmpty ?? false));

  static List<ToolResult> _limitResults(List<ToolCall> calls) => [
    for (final c in calls)
      ToolResult(
        callId: c.id,
        name: c.name,
        isError: true,
        content: const {
          'error':
              'Tool-call limit reached for this answer. Answer now using '
              'only the results you already have.',
        },
      ),
  ];

  /// Stores an assistant message, tagged "Sample data" in demo mode.
  Future<ChatMessage> _store(ChatMessage m) async {
    final out = health.mode == DataMode.demo
        ? ChatMessage(
            id: m.id,
            conversationId: m.conversationId,
            role: m.role,
            text: m.text,
            at: m.at,
            refs: m.refs,
            verification: m.verification,
            sent: m.sent,
            safety: m.safety,
            proposedMemories: m.proposedMemories,
            proposedCategories: m.proposedCategories,
            error: m.error,
            sampleData: true,
          )
        : m;
    await coach.appendMessage(out);
    return out;
  }

  /// The daily-budget message (no network call was made).
  static String budgetText(CoachUsage u) {
    final byRequests = u.requests >= u.requestLimit;
    final what = byRequests
        ? '${u.requestLimit} questions'
        : '${CoachFormat.grouped(u.tokenLimit)} tokens';
    return 'You\'ve reached today\'s limit for ${u.provider.label} '
        '($what), so nothing was sent. It resets at midnight. You can raise '
        'the limit or switch to the on-device coach in Settings → Coach.';
  }

  Future<void> _checkBudget() async {
    final u = await coach.usageToday();
    if (u != null && u.exhausted) {
      throw CoachException(CoachErrorKind.dailyLimit, budgetText(u));
    }
  }

  VerificationReport _verify(
    String text,
    String q,
    DateTime now,
    List<ToolCall> calls,
    List<ToolResult> results,
    List<String> memories,
    bool repaired,
  ) => Verifier.verify(
    answer: text,
    question: q,
    today: DayKey.of(now),
    calls: calls,
    results: results,
    memories: memories,
    repaired: repaired,
    nowMinutes: CoachFormat.minutesOfDay(now),
  );

  void _requireConsent(CoachSettings s) {
    final who = s.provider.label;
    if (!s.hasConsent) {
      throw CoachException(
        CoachErrorKind.notConfigured,
        'Review and accept what is sent to $who before asking '
        '(Settings → Coach).',
      );
    }
    if ((s.consentVersion ?? kCoachConsentVersion) < kCoachConsentVersion) {
      throw CoachException(
        CoachErrorKind.notConfigured,
        'What is sent to $who has changed. Review and accept it again in '
        'Settings → Coach.',
      );
    }
    if (!s.adultConfirmed) {
      throw CoachException(
        CoachErrorKind.notConfigured,
        '$who can only be used by adults. Confirm you are 18 or older in '
        'Settings → Coach.',
      );
    }
  }

  String _errorText(CoachException e) => switch (e.kind) {
    CoachErrorKind.invalidKey =>
      'Your API key was rejected. Check it in Settings → Coach.',
    CoachErrorKind.rateLimited =>
      'The AI provider is rate-limiting requests. Try again in a minute.',
    // The provider's own words (an HTTP status and error body) are never
    // shown; the app's daily budget message is.
    CoachErrorKind.quotaExceeded =>
      'Your AI provider account is out of credit or quota.',
    CoachErrorKind.dailyLimit =>
      e.message ??
          "You've reached today's limit, so nothing was sent. It resets at "
              'midnight.',
    CoachErrorKind.network =>
      'Couldn\'t reach the AI provider. Check your connection and try again.',
    CoachErrorKind.server =>
      'The AI provider had a problem. Try again shortly.',
    CoachErrorKind.refused => refusalText,
    CoachErrorKind.notConfigured =>
      e.message ?? 'Set up the coach in Settings → Coach.',
    CoachErrorKind.unknown => 'Something went wrong answering that.',
  };

  Future<String> _conversation(String? id, String q) async {
    if (id != null) return id;
    final c = await coach.createConversation(CoachFormat.title(q));
    return c.id;
  }

  Future<void> _storeUser(String conv, String q) => coach.appendMessage(
    ChatMessage(
      id: _id('u'),
      conversationId: conv,
      role: ChatRole.user,
      text: q,
      at: clock(),
    ),
  );

  /// Earlier Q/A of [conv] as plain text (answers without errors; fixed
  /// safety copy is not replayed). For a cloud provider only answers that
  /// were themselves produced for a cloud provider (sent != null) are
  /// replayed: an on-device answer was built without the Google Health API
  /// filter and must never leave the phone as history.
  Future<List<LlmItem>> _history(String conv, {required bool cloud}) async {
    final msgs = await coach.messages(conv);
    final pairs = <(String, String)>[];
    for (var i = 0; i + 1 < msgs.length; i++) {
      final u = msgs[i], a = msgs[i + 1];
      if (u.role == ChatRole.user &&
          a.role == ChatRole.assistant &&
          a.error == null &&
          !a.safety &&
          (!cloud || a.sent != null)) {
        pairs.add((u.text, CoachPrompts.stripCitations(a.text)));
        i++;
      }
    }
    final keep = pairs.length > historyTurns
        ? pairs.sublist(pairs.length - historyTurns)
        : pairs;
    return [
      for (final (u, a) in keep) ...[
        LlmUser(u),
        LlmAssistant(LlmTurn(text: a)),
      ],
    ];
  }

  static int _chars(LlmItem i) => switch (i) {
    LlmUser(:final text, :final data) => data.fold<int>(
      text.length,
      (a, r) => a + _jsonChars(r.content),
    ),
    LlmAssistant(:final turn) => turn.text.length,
    LlmToolResults(:final results) => results.fold<int>(
      0,
      (a, r) => a + _jsonChars(r.content),
    ),
  };

  static int _toolChars(List<CoachToolSpec> tools) => tools.fold<int>(
    0,
    (a, t) => a + t.name.length + t.description.length + 200,
  );

  static int _jsonChars(Object? v) {
    if (v is Map) {
      return v.entries.fold<int>(
        2,
        (a, e) => a + '${e.key}'.length + 3 + _jsonChars(e.value),
      );
    }
    if (v is List) return v.fold<int>(2, (a, e) => a + 1 + _jsonChars(e));
    return '$v'.length;
  }

  // ── Suggestions ────────────────────────────────────────────────────────

  @override
  Future<List<String>> suggestions({AskContext? context}) async {
    final settings = await coach.settings();
    if (settings.mode == CoachMode.generalOnly) {
      return const [
        'What does HRV mean?',
        'How is Recovery calculated?',
        'How is my strain target set?',
      ];
    }
    final today = DayKey.of(clock());
    final day = context?.date ?? today;
    DayBundle? b;
    try {
      b =
          await health.day(day) ??
          (context?.date == null
              ? await health.day(await health.latestDate() ?? today)
              : null);
    } catch (_) {
      b = null;
    }
    final isToday = day == today;
    final when = isToday ? 'today' : 'on ${CoachFormat.day(day)}';
    final out = <String>[];
    void add(String s) {
      if (!out.contains(s) && out.length < 4) out.add(s);
    }

    if (_hasSeed(context)) add('Tell me more about this');
    final rec = b?.result.recovery;
    switch (context?.screen) {
      case 'sleep':
        add(isToday ? 'How did I sleep last night?' : 'How did I sleep $when?');
        add('How much sleep debt do I have?');
        add('How consistent was my sleep this week?');
      case 'strain' || 'workout':
        add('What strain should I aim for today?');
        add('What workouts did I do this week?');
        add('Is my training load too high?');
      case 'trends' || 'weekly':
        add('Is my HRV trending up or down over the last 30 days?');
        add('Compare this week with last week');
        add('How has my resting heart rate changed over 30 days?');
      case 'journal':
        add('How does alcohol affect my recovery?');
        add('Which journal factors affect my recovery most?');
      case 'recovery':
        add(
          rec != null && rec.zone != RecoveryZone.green
              ? 'Why is my recovery low $when?'
              : 'What drove my recovery $when?',
        );
        add('How does my HRV compare with my baseline?');
        add('What does HRV mean?');
      default:
        if (rec != null && rec.zone == RecoveryZone.red) {
          add('Why is my recovery low today?');
        } else {
          add('What drove my recovery today?');
        }
        if (b?.result.health.alert ?? false) {
          add('What does today\'s Health Monitor alert mean?');
        }
        final debt = b?.result.sleep?.debtAfterMinutes ?? 0;
        if ((b?.result.sleep?.hasData ?? false) && debt >= 60) {
          add('How much sleep debt do I have?');
        } else {
          add('How did I sleep last night?');
        }
        add('What strain should I aim for today?');
        add('Compare this week with last week');
    }
    add('Where is my data missing this week?');
    return out;
  }
}
