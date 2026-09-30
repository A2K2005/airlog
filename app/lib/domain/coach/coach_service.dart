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
//            ─► model fallback: a model-specific failure (ModelUnavailable:
//               its quota, busy after retries, not found) restarts the
//               WHOLE question on the provider's next model (same key;
//               "Use a backup model when busy"); any other failure, or the
//               last model failing, answers on this phone (the on-device
//               engine, no network). Never another provider. Verifier,
//               policy and budget apply to every attempt
//            ─► stored assistant message (refs, Verification, SentPayload,
//               answeredBy / fallbackFrom / fallbackReason)
//
// General-only mode offers only tools that read no user data, replays no
// earlier messages and never injects a card. Memory tools are offered only
// when memory is on. Earlier asks in a conversation are replayed as plain
// text (no thinking blocks, citations stripped), so each ask can carry its
// own date and context in the system prompt.

import 'dart:async';
import 'dart:convert';

import '../day_key.dart';
import '../engine/today_planner.dart';
import '../repositories.dart';
import '../results.dart';
import 'answer_actions.dart';
import 'answer_visuals.dart';
import 'coach_contracts.dart';
import 'format.dart';
import 'policy.dart';
import 'prompts.dart';
import 'personal_context.dart';
import 'safety.dart';
import 'tools.dart';
import 'topics.dart';
import 'verifier.dart';

/// Version of the cloud disclosure the user must have accepted.
const int kCoachConsentVersion = 1;
const int kCoachPayloadVersion = 3;

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
      throw const CoachException(
        CoachErrorKind.unknown,
        'Type a question first.',
      );
    }
    final settings = await coach.settings();
    if (!settings.enabled) {
      throw const CoachException(
        CoachErrorKind.notConfigured,
        'Coach is turned off. Turn it on in Settings → Coach.',
      );
    }

    // 1. Input router: fixed response, no model, no network.
    var flag = SafetyCheck.check(q);
    if (flag == null) {
      final birthYear = (await health.profile()).birthYear;
      if (birthYear != null && clock().year - birthYear < 18) {
        flag = const SafetyVerdict(RedFlag.minor, SafetyCheck.minorMessage);
      }
    }
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

    // 2. Cloud gate: consent for this provider + mode, adult, current text,
    //    and a stored key. A cloud engine that isn't ready never walls the
    //    chat: the question is answered on this phone instead, as a purely
    //    local question (local history, no context pre-read, no source
    //    firewall, never replayed to a provider), and nothing is sent.
    final cloudChosen = settings.provider != CoachProvider.offline;
    var chain = const <LlmClient>[];
    CoachException? notReady;
    if (cloudChosen) {
      try {
        _requireConsent(settings);
        // The chosen model, then its same-provider backups ("Use a backup
        // model when busy"). Throws notConfigured (no key).
        chain = await coach.modelChain();
      } on CoachException catch (e) {
        if (e.kind != CoachErrorKind.notConfigured) rethrow;
        notReady = e;
      }
    } else {
      chain = await coach.modelChain();
    }
    final cloud = cloudChosen && notReady == null;

    final useData = settings.mode == CoachMode.useMyData;
    final memoryScope = await _memoryScope();
    final dataMode = health.mode;
    final conv = await _conversation(conversationId, q);
    final history = useData && !MemoryContext.isCorrection(q)
        ? await _history(conv, cloud: cloud, memoryScope: memoryScope)
        : const <LlmItem>[];
    await _storeUser(conv, q);

    // 3. Daily budget, before any network call. Spent: this question is
    //    answered on this phone exactly like the budget running out mid-
    //    question (the same context and replay scope), and nothing is sent.
    var spent = false;
    if (cloud) {
      final u = await coach.usageToday();
      spent = u != null && u.exhausted;
    }

    final now = clock();
    final memoryOn = useData && await coach.memoryEnabled();
    final latest = useData ? await health.latestDate() : null;

    // 4. The question, on each engine in turn (model fallback, PRODUCT_PLAN
    //    §7). Every attempt restarts the WHOLE question: a fresh tool loop,
    //    fresh evidence, fresh refs. Models are never mixed inside one loop
    //    (thinking blocks and thought signatures are bound to their model).
    //    A model-specific failure (ModelUnavailable) moves to the next model
    //    of the same provider; anything else, or the last model failing,
    //    answers on this phone with no network. Never another provider.
    //    Context parity: every attempt, the on-device one included, gets the
    //    same scoped history, card seed, personal context, memory tools,
    //    system prompt and length, behind the same source firewall.
    final tally = _Tally();
    Future<_Answer> attempt(LlmClient client, {required bool network}) =>
        _attempt(
          client: client,
          network: network,
          cloud: cloud,
          settings: settings,
          q: q,
          now: now,
          history: history,
          context: context,
          useData: useData,
          memoryOn: memoryOn,
          latest: latest,
          memoryScope: memoryScope,
          dataMode: dataMode,
          tally: tally,
        );

    final chosen = chain.isNotEmpty
        ? chain.first.model
        : settings.model ?? settings.provider.name;
    _Answer? answer;
    CoachException? failure =
        notReady ??
        (spent ? const CoachException(CoachErrorKind.dailyLimit) : null);
    if (!cloudChosen || (cloud && !spent)) {
      for (var i = 0; i < chain.length && answer == null; i++) {
        final client = chain[i];
        // A model known to be down (its day quota, the provider's retry
        // delay) is skipped: no failed request first, no extra wait.
        final down = cloud ? await coach.modelDown(client.model) : null;
        if (down != null) {
          failure = ModelUnavailable(down.reason, 'Known to be down.');
          continue;
        }
        try {
          answer = await attempt(client, network: cloud);
        } on CoachException catch (e) {
          failure = e;
          if (!cloud) break;
          if (e is ModelUnavailable) {
            await coach.noteModelUnavailable(client.model, e);
            if (i < chain.length - 1) continue;
          }
          break;
        }
      }
    }
    // Settings, key, consent, data mode, memory or the chat changed while
    // answering (the generation fences): the question is stale, so nothing
    // more runs, not even on this phone.
    final stale =
        notReady == null && failure?.kind == CoachErrorKind.notConfigured;
    var onDevice = false;
    if (answer == null && cloudChosen && !stale) {
      try {
        answer = await attempt(coach.onDeviceClient(), network: false);
        onDevice = true;
      } on CoachException catch (e) {
        failure = e;
      }
    }

    String? error;
    String text;
    if (answer == null) {
      error = failure!.kind.name;
      text = _errorText(failure);
    } else if (answer.refused) {
      error = CoachErrorKind.refused.name;
      text = refusalText;
    } else {
      text = answer.text;
    }

    final answeredBy = !cloudChosen || answer == null
        ? null
        : onDevice
        ? ChatMessage.onDevice
        : answer.model ?? chosen;
    final fellBack = answeredBy != null && answeredBy != chosen;

    // Nothing went over the network (every model known to be down, the
    // budget stopped it, or the cloud wasn't ready): there is nothing to
    // show under "What was shared".
    final sent = cloud && tally.attempts > 0
        ? SentPayload(
            provider: settings.provider,
            model: tally.lastModel ?? chosen,
            toolsCalled: [...tally.toolsCalled],
            dataTypes: [
              'Your question',
              if (history.isNotEmpty) 'Earlier messages in this chat',
              ...tally.dataTypes,
            ],
            approxChars: tally.bytes > 0 ? tally.bytes : tally.chars,
            bytes: tally.bytes,
            requests: tally.requests,
            privacyVersion: kCoachPayloadVersion,
            memoryContext: memoryScope,
            mode: settings.mode,
          )
        : null;

    final proposals = error == null && memoryOn
        ? answer!.proposals
        : const <MemoryProposal>[];
    // What the answer's cards may show, read on the phone from its own tool
    // results and never sent (AnswerVisuals, AnswerActions).
    final ok = error == null ? answer : null;
    final tools = ok == null ? const <String>[] : toolNames(ok.calls);
    final visuals = ok == null || !useData || ok.factsOnly
        ? const <AnswerVisual>[]
        : AnswerVisuals.build(ok.results, ok.refs);
    final actions = ok == null || !useData || latest == null
        ? const <AnswerAction>[]
        : await _actions(ok, tools, latest, now);
    return _store(
      ChatMessage(
        id: _id('a'),
        conversationId: conv,
        role: ChatRole.assistant,
        text: text,
        at: clock(),
        refs: error == null ? answer!.refs : const [],
        verification: answer?.report?.verification,
        sent: sent,
        proposedMemories: [for (final p in proposals) p.text],
        proposedCategories: [for (final p in proposals) p.category.name],
        proposedExpiries: [for (final p in proposals) p.expiresOn],
        error: error,
        answeredBy: answeredBy,
        fallbackFrom: fellBack ? chosen : null,
        fallbackReason: fellBack ? failure?.kind.name : null,
        // An on-device fallback that sent nothing has no SentPayload to
        // scope its replay by; it records the scope it was built under. A
        // question answered locally because the cloud wasn't ready has no
        // cloud scope at all, so it is never replayed.
        replayScope: fellBack && sent == null && notReady == null
            ? replayScopeOf(settings, memoryScope)
            : null,
        visuals: visuals,
        actions: actions,
        tools: tools,
        factsOnly: ok?.factsOnly ?? false,
      ),
    );
  }

  /// The tools an answer's engine called, for its topic: 'get_sleep',
  /// 'get_range:hrv'. The app's own context reads (PersonalContext's
  /// "context_*" calls, the card seed) are left out: they read the same
  /// day summary for every personal question.
  static List<String> toolNames(List<ToolCall> calls) => [
    for (final c in calls)
      if (!c.id.startsWith('context_') && c.name != CoachTools.insightCard)
        (c.name == CoachTools.range || c.name == CoachTools.compare) &&
                c.input['metric'] is String
            ? '${c.name}:${c.input['metric']}'
            : c.name,
  ];

  /// Today's plan actions for the answer's topic, when the answer read the
  /// newest day with data ([latest]). The plan's own words, never sent.
  Future<List<AnswerAction>> _actions(
    _Answer a,
    List<String> tools,
    String latest,
    DateTime now,
  ) async {
    if (a.factsOnly) return const [];
    final topic = ChatTopics.ofTools(tools);
    if (topic == null) return const [];
    final read = a.calls.any(
      (c) =>
          c.name == CoachTools.todaySummary ||
          (c.name == CoachTools.day && c.input['date'] == latest) ||
          (c.name == CoachTools.sleep && c.input['to'] == latest),
    );
    if (!read) return const [];
    try {
      final b = await health.day(latest);
      if (b == null) return const [];
      return AnswerActions.fromPlan(
        TodayPlanner.plan(today: b, now: now),
        topic,
      );
    } catch (_) {
      return const [];
    }
  }

  /// The privacy scope a cloud answer is built under (PR #1 history
  /// isolation): provider, mode, payload version and the memory scope.
  static String replayScopeOf(CoachSettings s, String memoryScope) =>
      jsonEncode([
        s.provider.name,
        s.mode.name,
        kCoachPayloadVersion,
        memoryScope,
      ]);

  /// One run of the question on [client]: the card seed, the tool loop
  /// (≤ [maxToolRounds] rounds), the verifier and output policy, one repair
  /// round, then the facts table. [network]: a cloud request (consent and
  /// the budget are re-checked before each one, and what is sent is
  /// tallied); false for the on-device engine. [cloud]: the question is a
  /// cloud one. It sets the source firewall, the card seed, the personal
  /// context and the system prompt, identically for every attempt, so an
  /// on-device fallback sees exactly what the chosen model saw (and its
  /// answer is safe to replay to that provider as history). Throws the
  /// client's CoachException.
  Future<_Answer> _attempt({
    required LlmClient client,
    required bool network,
    required bool cloud,
    required CoachSettings settings,
    required String q,
    required DateTime now,
    required List<LlmItem> history,
    required AskContext? context,
    required bool useData,
    required bool memoryOn,
    required String? latest,
    required String memoryScope,
    required DataMode dataMode,
    required _Tally tally,
  }) async {
    final seeded = useData && _hasSeed(context);
    final tools = CoachTools.forMode(settings.mode, memory: memoryOn);
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
    // Only memory actually retrieved on this attempt can ground an answer.
    // Stale facts remain labelled context but cannot validate current
    // claims.
    final memories = toolbox.groundedMemories;

    final calls = <ToolCall>[];
    final results = <ToolResult>[];
    var chars =
        system.length +
        q.length +
        [for (final i in history) _chars(i)].fold<int>(0, (a, b) => a + b) +
        _toolChars(tools);
    var rounds = 0;
    String? model;

    // On-device gets the card facts. Cloud gets a withholding notice and
    // must read current facts through the guarded data tools instead.
    final seed = seeded
        ? await toolbox.run(const [
            ToolCall(id: 'seed_card', name: CoachTools.insightCard, input: {}),
          ])
        : const <ToolResult>[];
    results.addAll(seed);
    // Read bounded, question-relevant evidence before the model answers.
    // No extra model request; the same consent/source firewall applies.
    final contextCalls = cloud && useData
        ? PersonalContext.plan(q, DayKey.of(now), memory: memoryOn)
        : const <ToolCall>[];
    final personal = await toolbox.run(contextCalls);
    calls.addAll(contextCalls);
    results.addAll(personal);
    // Built once and never rebuilt: every request of this attempt replays
    // the same question message, so the history stays append-only.
    final transcript = <LlmItem>[
      ...history,
      LlmUser(q, data: [...seed, ...personal]),
    ];
    for (final r in [...seed, ...personal]) {
      chars += _jsonChars(r.content);
    }

    Future<LlmTurn> request() async {
      // The question's settings, consent, data mode and memory scope must
      // still hold before every request of every attempt.
      final current = await coach.settings();
      if (!current.enabled ||
          current.provider != settings.provider ||
          current.mode != settings.mode ||
          current.consentAt != settings.consentAt ||
          current.consentVersion != settings.consentVersion ||
          health.mode != dataMode ||
          await _memoryScope() != memoryScope) {
        throw const CoachException(
          CoachErrorKind.notConfigured,
          'Your settings changed, so Coach stopped. Nothing more was sent. '
          'Ask again.',
        );
      }
      if (network) {
        _requireConsent(current);
        await _checkBudget();
        tally.attempts++;
      }
      final LlmTurn t;
      try {
        t = await client
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
      } on CoachException catch (e) {
        // A request the provider answered with an error still counts.
        if (network && _reached(e)) {
          tally.requests++;
          tally.lastModel = client.model;
        }
        rethrow;
      }
      if (network) {
        tally.requests++;
        tally.bytes += t.sentBytes;
        tally.lastModel = t.model ?? client.model;
      }
      model = t.model ?? client.model;
      if (health.mode != dataMode) {
        throw const CoachException(
          CoachErrorKind.notConfigured,
          'You switched data while Coach was answering. Ask again.',
        );
      }
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

    try {
      final first = await loop();
      if (first != null && first.refusal) {
        return _Answer.refusal(model);
      }
      var text = first?.text.trim() ?? '';
      var report = _verify(text, q, now, calls, results, memories, false);
      List<SourceRef> shownRefs = const [];
      var factsOnly = false;
      final policy = OutputPolicy.check(text);
      if (text.isEmpty || !report.verified || !policy.ok) {
        // One repair round for both the verifier and the output policy, on
        // the same model.
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
          // Deterministic fallback: this attempt's facts, verified by
          // construction.
          final (table, refs) = CoachPrompts.factsTable(
            results,
            preferIds: report.citedRefIds,
          );
          text = table;
          report = _verify(text, q, now, calls, results, memories, true);
          shownRefs = refs;
          factsOnly = true;
        }
      }
      if (shownRefs.isEmpty) {
        shownRefs = CoachPrompts.citedRefs(text, [
          for (final r in results) ...r.refs,
        ]);
      }
      return _Answer(
        text: text,
        report: report,
        refs: shownRefs,
        proposals: List.of(toolbox.proposals),
        model: model,
        calls: List.unmodifiable(calls),
        results: List.unmodifiable(results),
        factsOnly: factsOnly,
      );
    } finally {
      if (network) {
        // What reached the provider on this attempt, answered or not.
        tally.chars += chars;
        tally.toolsCalled.addAll({for (final c in calls) c.name});
        tally.dataTypes.addAll(toolbox.dataTypes);
      }
    }
  }

  /// The provider answered the request (with an error status): it counts
  /// as a request (MeteredClient.reachedProvider meters the same way).
  static bool _reached(CoachException e) => switch (e.kind) {
    CoachErrorKind.network ||
    CoachErrorKind.dailyLimit ||
    CoachErrorKind.notConfigured => false,
    _ => true,
  };

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
        ? m.copyWith(sampleData: true)
        : m;
    await coach.appendMessage(out);
    return out;
  }

  /// The daily-budget message (no network call was made).
  static String budgetText(CoachUsage u) {
    final byRequests = u.requests >= u.requestLimit;
    final what = byRequests
        ? '${u.requestLimit} model requests'
        : '${CoachFormat.grouped(u.tokenLimit)} tokens';
    final who = switch (u.provider) {
      CoachProvider.claude => 'Claude',
      CoachProvider.gemini => 'Gemini',
      CoachProvider.offline => 'the coach',
    };
    return 'You’ve used today’s limit for $who ($what). Nothing more will '
        'be sent. It resets at midnight. The on-phone coach still works.';
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
      'Too many questions at once. Try again in a minute.',
    // The provider's own words (an HTTP status and error body) are never
    // shown; the app's daily budget message is.
    CoachErrorKind.quotaExceeded => 'Your AI account is out of credit.',
    CoachErrorKind.dailyLimit =>
      e.message ??
          "You've reached today's limit. No further requests were sent. It resets at "
              'midnight.',
    CoachErrorKind.network =>
      'No answer arrived from the AI provider. A request may already have '
          'reached it. Check your connection and try again.',
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

  /// The saved memories this question may use (ids, versions, expiry,
  /// review state), or 'off'. A change mid-question stops it; an answer
  /// built under another scope is not replayed to a cloud provider.
  Future<String> _memoryScope() async {
    if (!await coach.memoryEnabled()) return 'off';
    final today = DayKey.of(clock());
    final facts = [
      for (final m in await coach.memories())
        if (m.expiresOn == null || m.expiresOn!.compareTo(today) >= 0)
          '${m.id}|${m.updatedAt?.toIso8601String()}|${m.expiresOn}|${MemoryContext.needsReview(m, today)}',
    ];
    facts.sort();
    return jsonEncode(facts);
  }

  /// Earlier Q/A of [conv] as plain text (answers without errors; fixed
  /// safety copy is not replayed; sample-data answers only in demo mode).
  /// For a cloud provider only answers built under the current privacy
  /// scope are replayed ([_replayable]).
  Future<List<LlmItem>> _history(
    String conv, {
    required bool cloud,
    required String memoryScope,
  }) async {
    final msgs = await coach.messages(conv);
    final settings = await coach.settings();
    final pairs = <(String, String)>[];
    for (var i = 0; i + 1 < msgs.length; i++) {
      final u = msgs[i], a = msgs[i + 1];
      if (u.role == ChatRole.user &&
          a.role == ChatRole.assistant &&
          a.error == null &&
          !a.safety &&
          a.sampleData == (health.mode == DataMode.demo) &&
          (!cloud || _replayable(a, settings, memoryScope))) {
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

  /// History isolation for a cloud chat: the same provider, mode, payload
  /// version and memory scope as now. That includes answers a backup model
  /// or this phone wrote as the chosen model's fallback: they ran behind the
  /// same source firewall with the same context, and are part of the chat.
  /// An on-device fallback that sent nothing carries its scope in
  /// [ChatMessage.replayScope]; an answer of the on-device coach itself
  /// (never a fallback) is never replayed.
  static bool _replayable(ChatMessage a, CoachSettings s, String memoryScope) {
    final sent = a.sent;
    if (sent != null) {
      return sent.provider == s.provider &&
          sent.mode == s.mode &&
          sent.privacyVersion == kCoachPayloadVersion &&
          sent.memoryContext == memoryScope;
    }
    return a.fellBack && a.replayScope == replayScopeOf(s, memoryScope);
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
        add('How much sleep have I missed?');
        add('How consistent was my sleep this week?');
      case 'strain' || 'workout':
        add('How hard should I go today?');
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
              ? 'Why is my Recovery low $when?'
              : 'What changed my Recovery $when?',
        );
        add('How does my HRV compare with my usual?');
        add('What does HRV mean?');
      default:
        if (rec != null && rec.zone == RecoveryZone.red) {
          add('Why is my Recovery low today?');
        } else {
          add('What changed my Recovery today?');
        }
        if (b?.result.health.alert ?? false) {
          add('What does today\'s Health Monitor alert mean?');
        }
        final debt = b?.result.sleep?.debtAfterMinutes ?? 0;
        if ((b?.result.sleep?.hasData ?? false) && debt >= 60) {
          add('How much sleep have I missed?');
        } else {
          add('How did I sleep last night?');
        }
        add('How hard should I go today?');
        add('Compare this week with last week');
    }
    add('Where is my data missing this week?');
    return out;
  }
}

/// What reached the provider across every attempt of one question (the
/// "What was sent" sheet and the request count).
class _Tally {
  /// Requests sent (answered or not) / answered by the provider.
  int attempts = 0, requests = 0, bytes = 0, chars = 0;
  String? lastModel;
  final toolsCalled = <String>{};
  final dataTypes = <String>{};
}

/// One attempt's answer.
class _Answer {
  const _Answer({
    required this.text,
    required this.report,
    required this.refs,
    required this.proposals,
    this.model,
    this.calls = const [],
    this.results = const [],
    this.factsOnly = false,
  }) : refused = false;

  const _Answer.refusal(this.model)
    : text = '',
      report = null,
      refs = const [],
      proposals = const [],
      calls = const [],
      results = const [],
      factsOnly = false,
      refused = true;

  final String text;
  final VerificationReport? report;
  final List<SourceRef> refs;
  final List<MemoryProposal> proposals;

  /// The model that wrote it (the provider's own word when it says).
  final String? model;
  final bool refused;

  /// This attempt's tool calls and results (the answer's own evidence).
  final List<ToolCall> calls;
  final List<ToolResult> results;

  /// The text is the deterministic facts table.
  final bool factsOnly;
}
