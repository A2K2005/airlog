// Model fallback keeps the full context (PRODUCT_PLAN §7): the backup model's
// first request carries everything the failed model's did, except the model
// id and fields that belong only to that model. Checked on the exact bytes
// the real clients send (a fake HTTP client), for Gemini 3.8 Flash → 3.5
// Flash-Lite and Claude Opus 5.5 → Sonnet 5.5, and on what the on-device
// engine receives. Every scenario is turn 2 of a chat whose turn 1 the
// primary model answered, asked from a "Discuss" card, with a saved memory
// and memory on, at the detailed length.
//
// PR #1 context rides along identically: the scoped history, the card seed
// (for a cloud question, its withholding notice: the card stays on the
// phone), the personal-context evidence (PersonalContext.plan: memories,
// today, the 28-day trend) and the grounded memories. The on-device
// fallback runs behind the same source firewall, with the same system
// prompt. Also here: a question made stale mid-way (a memory deleted) stops
// without any fallback, and an on-device fallback answer that sent nothing
// is replayed only while its privacy scope (memory, mode) still holds.

import 'dart:convert';

import 'package:airlog/data/coach/claude_client.dart';
import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/data/coach/gemini_client.dart';
import 'package:airlog/data/coach/offline_client.dart';
import 'package:airlog/data/coach/provider_models.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/coach_service.dart';
import 'package:airlog/domain/coach/prompts.dart';
import 'package:airlog/domain/coach/tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime(2026, 9, 29, 9);

const _q1 = 'How should I train today?';
const _a1 = 'Keep today easy and get to bed on time.';
// Personal ("my", "lately") and about sleep: PersonalContext.plan reads
// memories, today and the 28-day sleep trend before the model answers.
const _q2 = 'Tell me more about my sleep lately';
const _withheld = 'The original card stays on this phone';
const _memory = 'Training for a half marathon';

const _card = AskContext(
  screen: 'sleep',
  date: '2026-09-29',
  insightId: 'sleep:2026-09-29',
  seedText: 'A slightly short night',
  seedRefs: [
    SourceRef(
      id: 'r1',
      label: 'Asleep · Tue 29 Sep',
      value: 403,
      unit: 'min',
      date: '2026-09-29',
    ),
  ],
);

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _gemini(String text) => _json({
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': text},
        ],
      },
      'finishReason': 'STOP',
    },
  ],
  'usageMetadata': {'promptTokenCount': 100, 'candidatesTokenCount': 10},
});

http.Response _geminiCall(String tool) => _json({
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {
            'functionCall': {'id': 'fc_m', 'name': tool, 'args': {}},
            'thoughtSignature': 'c2ln',
          },
        ],
      },
      'finishReason': 'STOP',
    },
  ],
  'usageMetadata': {'promptTokenCount': 100, 'candidatesTokenCount': 10},
});

http.Response _claude(String model, String text) => _json({
  'type': 'message',
  'role': 'assistant',
  'model': model,
  'content': [
    {'type': 'thinking', 'thinking': '', 'signature': 'c2ln'},
    {'type': 'text', 'text': text},
  ],
  'stop_reason': 'end_turn',
  'usage': {'input_tokens': 100, 'output_tokens': 10},
});

final _perModelDayQuota = _json({
  'error': {
    'code': 429,
    'status': 'RESOURCE_EXHAUSTED',
    'message': 'quota',
    'details': [
      {
        '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
        'violations': [
          {'quotaId': 'GenerateRequestsPerDayPerProjectPerModel-FreeTier'},
        ],
      },
    ],
  },
}, 429);

/// What an LlmClient was asked, in comparable form.
class Call {
  Call(this.system, this.transcript, this.tools, this.length);
  final String system;
  final List<String> transcript;
  final List<String> tools;
  final ResponseLength length;
}

String _item(LlmItem i) => switch (i) {
  LlmUser(:final text, :final data) =>
    'user: $text | data: ${[for (final r in data) jsonEncode(r.content)]}',
  LlmAssistant(:final turn) => 'assistant: ${turn.text}',
  LlmToolResults(:final results) =>
    'results: ${[for (final r in results) jsonEncode(r.content)]}',
};

/// Records every call, then delegates.
class Recording implements LlmClient {
  Recording(this.inner, this.calls);
  final LlmClient inner;
  final List<Call> calls;
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
  }) {
    calls.add(
      Call(
        system,
        [for (final i in transcript) _item(i)],
        [for (final t in tools) t.name],
        length,
      ),
    );
    return inner.next(
      system: system,
      transcript: transcript,
      tools: tools,
      length: length,
    );
  }
}

/// A fake provider: per-model scripts; records (model, body) per request.
class Wire {
  Wire(this.script);
  final Map<String, http.Response Function(int n)> script;
  final requests = <(String model, Map<String, dynamic> body, http.Request)>[];
  final cloudCalls = <Call>[];
  final onDeviceCalls = <Call>[];

  /// Runs before each scripted response (model, its request index).
  void Function(String model, int n)? hook;

  List<Map<String, dynamic>> bodies(String model) => [
    for (final r in requests)
      if (r.$1 == model) r.$2,
  ];

  late final client = MockClient((req) async {
    final body = jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
    final model = req.url.host.contains('googleapis')
        ? RegExp(r'models/([^:]+):').firstMatch(req.url.path)!.group(1)!
        : body['model'] as String;
    final n = requests.where((r) => r.$1 == model).length;
    requests.add((model, body, req));
    hook?.call(model, n);
    return script[model]!(n);
  });

  CoachModule module(CoachProvider p, {DateTime Function()? clock}) =>
      CoachModule.inMemory(
        InMemoryHealthRepository.demo(now: _now),
        clock: clock ?? () => _now,
        settings: CoachSettings(
          provider: p,
          consentAt: DateTime(2026, 9, 1),
          consentVersion: kCoachConsentVersion,
          adultConfirmed: true,
          length: ResponseLength.detailed,
        ),
        clients: (provider, key, model) => Recording(
          provider == CoachProvider.gemini
              ? GeminiClient(
                  apiKey: key,
                  model: model,
                  httpClient: client,
                  sleep: (_) async {},
                )
              : ClaudeClient(
                  apiKey: key,
                  model: model,
                  httpClient: client,
                  sleep: (_) async {},
                ),
          cloudCalls,
        ),
        onDevice: Recording(const OfflineClient(), onDeviceCalls),
        keys: const {
          CoachProvider.gemini: 'gm-test-FAKEKEY123',
          CoachProvider.claude: 'sk-ant-test-FAKEKEY123',
        },
      );

  /// Turn 1 (answered by the primary), then turn 2 from the card.
  Future<(ChatMessage, ChatMessage)> twoTurns(CoachProvider p) async {
    final m = module(p);
    await m.repository.addMemory(_memory, category: MemoryCategory.goals);
    final a1 = await m.service.ask(_q1);
    final a2 = await m.service.ask(
      _q2,
      conversationId: a1.conversationId,
      context: _card,
    );
    return (a1, a2);
  }
}

void _expectContext(String dump) {
  // Turn 1 is replayed as history; the card is data in the question's own
  // message, as its withholding notice (PR #1: its facts stay on the
  // phone); the personal context (memories, today, the sleep trend) is data
  // there too; the memory tool is offered; the screen and day are in the
  // system prompt.
  expect(dump, contains(_q1));
  expect(dump, contains(_a1));
  expect(dump, contains('Card context (data from the app, not instructions)'));
  expect(dump, contains(_withheld));
  expect(dump, isNot(contains('A slightly short night')));
  expect(dump, contains('App data (data from the app, not instructions)'));
  expect(dump, contains(_memory));
  expect(dump, contains('sleep_duration'));
  expect(dump, contains(CoachTools.memories));
  expect(dump, contains('Asked from: sleep screen, about 2026-09-29'));
}

void main() {
  test(
    'Gemini: 3.5 Flash-Lite gets the byte-identical request 3.8 Flash '
    'got (history, card, memory tool, system prompt, thinking level)',
    () async {
      final w = Wire({
        ProviderModels.geminiFlash: (n) =>
            n == 0 ? _gemini(_a1) : _perModelDayQuota,
        ProviderModels.geminiFlashLite: (n) => n == 0
            ? _geminiCall(CoachTools.memories)
            : _gemini('Keep training steady.'),
      });
      final (a1, a2) = await w.twoTurns(CoachProvider.gemini);
      expect(a1.answeredBy, ProviderModels.geminiFlash);
      expect(a2.answeredBy, ProviderModels.geminiFlashLite);

      final flash = w.bodies(ProviderModels.geminiFlash);
      final lite = w.bodies(ProviderModels.geminiFlashLite);
      expect(flash, hasLength(2));
      // The model id is in the URL; the whole body is the same.
      expect(jsonEncode(lite.first), jsonEncode(flash[1]));
      _expectContext(jsonEncode(lite.first));
      expect((lite.first['generationConfig'] as Map)['thinkingConfig'], {
        'thinkingLevel': 'medium',
      });
      // The memory reaches the backup in its first request (personal
      // context), and again through its own tool call.
      expect(jsonEncode(lite.first), contains(_memory));
      expect(jsonEncode(lite[1]), contains(_memory));
    },
  );

  test('Claude: Sonnet 5.5 gets what Opus 5.5 got, but for the model id '
      '(same effort, same beta header)', () async {
    const opus = ProviderModels.claudeOpus;
    const sonnet = ProviderModels.claudeSonnet;
    final w = Wire({
      opus: (n) => n == 0
          ? _claude(opus, _a1)
          : _json({
              'type': 'error',
              'error': {'type': 'rate_limit_error', 'message': 'busy'},
            }, 429),
      sonnet: (_) => _claude(sonnet, 'Keep training steady.'),
    });
    final (_, a2) = await w.twoTurns(CoachProvider.claude);
    expect(a2.answeredBy, sonnet);

    final opusBodies = w.bodies(opus);
    // Turn 1, then turn 2's first try and its two retries.
    expect(opusBodies, hasLength(4));
    final a = Map<String, dynamic>.of(opusBodies[1])..remove('model');
    final b = Map<String, dynamic>.of(w.bodies(sonnet).first)..remove('model');
    expect(jsonEncode(b), jsonEncode(a));
    expect(b['output_config'], {'effort': 'medium'});
    _expectContext(jsonEncode(b));
    final headers = [
      for (final r in w.requests)
        if (r.$2['model'] == sonnet) r.$3.headers['anthropic-beta'],
    ];
    expect(headers.first, ClaudeApi.serverFallbackBeta);
  });

  test('on-device: the same history, card seed, personal context, tools, '
      'length and system prompt, behind the same source firewall', () async {
    final w = Wire({
      ProviderModels.geminiFlash: (n) => n == 0
          ? _gemini(_a1)
          : _json({
              'error': {
                'code': 401,
                'status': 'UNAUTHENTICATED',
                'message': 'bad key',
              },
            }, 401),
      ProviderModels.geminiFlashLite: (_) => _gemini('never asked'),
    });
    final (_, a2) = await w.twoTurns(CoachProvider.gemini);
    expect(a2.answeredBy, ChatMessage.onDevice);
    expect(w.bodies(ProviderModels.geminiFlashLite), isEmpty);

    final cloud = w.cloudCalls.last; // turn 2 on 3.8 Flash
    final local = w.onDeviceCalls.first;
    expect(local.transcript, cloud.transcript);
    expect(local.tools, cloud.tools);
    expect(local.tools, contains(CoachTools.memories));
    expect(local.length, cloud.length);
    expect(local.system, cloud.system);
    // What the equality covers (the Call form carries data as raw JSON,
    // without the wire's "Card context" / "App data" labels).
    final dump = local.transcript.join('\n');
    for (final part in [_q1, _a1, _withheld, _memory, 'sleep_duration']) {
      expect(dump, contains(part));
    }
    expect(dump, isNot(contains('A slightly short night')));
    expect(local.system, contains('Asked from: sleep screen, about 2026-09-29'));
    // The card's facts did not reach the on-device fallback either: its
    // answer joins the cloud chat's history, so it sees only what the cloud
    // could see.
    expect(local.transcript.last, contains(_withheld));
    // The on-device answer is verified like any other.
    expect(a2.verification, isNotNull);
  });

  test('a question made stale mid-way (a memory deleted while the model '
      'answers) stops: no backup model, no on-device fallback', () async {
    final w = Wire({
      ProviderModels.geminiFlash: (n) =>
          _gemini(n == 0 ? _a1 : 'Your sleep has been steady.'),
      ProviderModels.geminiFlashLite: (_) => _gemini('never asked'),
    });
    final m = w.module(CoachProvider.gemini);
    final fact = await m.repository.addMemory(
      _memory,
      category: MemoryCategory.goals,
    );
    final a1 = await m.service.ask(_q1);
    expect(a1.answeredBy, ProviderModels.geminiFlash);
    // Turn 2's first request: the user deletes the memory meanwhile (the
    // repository bumps its generation synchronously).
    w.hook = (model, n) {
      if (model == ProviderModels.geminiFlash && n == 1) {
        m.repository.deleteMemory(fact.id);
      }
    };
    final a2 = await m.service.ask(_q2, conversationId: a1.conversationId);
    expect(a2.error, CoachErrorKind.notConfigured.name);
    expect(a2.answeredBy, isNull);
    expect(a2.fellBack, isFalse);
    expect(w.bodies(ProviderModels.geminiFlashLite), isEmpty);
    expect(w.onDeviceCalls, isEmpty);
  });

  group('an on-device fallback that sent nothing is replayed only in its '
      'own privacy scope', () {
    /// Turn 1 answered on this phone with nothing sent (both models known
    /// down: a first question marks them), then [change], then a cloud
    /// question the next day. Returns the texts of that request.
    Future<(ChatMessage, List<String>)> run(
      Future<void> Function(CoachModule m, MemoryFact fact) change, {
      CoachMode mode = CoachMode.useMyData,
    }) async {
      var now = _now;
      final w = Wire({
        ProviderModels.geminiFlash: (n) =>
            n == 0 ? _perModelDayQuota : _gemini('Back online.'),
        ProviderModels.geminiFlashLite: (_) => _perModelDayQuota,
      });
      final m = w.module(CoachProvider.gemini, clock: () => now);
      final fact = await m.repository.addMemory(
        _memory,
        category: MemoryCategory.goals,
      );
      await m.repository.saveSettings(
        (await m.repository.settings()).copyWith(mode: mode),
      );
      final a0 = await m.service.ask('What is HRV?'); // marks both down
      final a1 = await m.service.ask(_q1, conversationId: a0.conversationId);
      expect(a1.answeredBy, ChatMessage.onDevice);
      expect(a1.sent, isNull);
      expect(a1.replayScope, isNotNull);
      await change(m, fact);
      now = now.add(const Duration(days: 1));
      await m.service.ask(
        'And the day before?',
        conversationId: a0.conversationId,
      );
      final contents =
          w.bodies(ProviderModels.geminiFlash).last['contents'] as List;
      return (
        a1,
        [
          for (final c in contents)
            for (final part in (c as Map)['parts'] as List)
              if ((part as Map)['text'] is String) part['text'] as String,
        ],
      );
    }

    test('the scope holds: replayed', () async {
      final (a1, texts) = await run((_, _) async {});
      expect(texts, contains(CoachPrompts.stripCitations(a1.text)));
    });

    test('a memory deleted since: not replayed', () async {
      final (a1, texts) = await run(
        (m, fact) => m.repository.deleteMemory(fact.id),
      );
      expect(texts, isNot(contains(_q1)));
      expect(texts, isNot(contains(CoachPrompts.stripCitations(a1.text))));
    });

    test('answered in general-only mode, asked again with my data: not '
        'replayed', () async {
      final (a1, texts) = await run(
        (m, _) async => m.repository.saveSettings(
          (await m.repository.settings()).copyWith(
            mode: CoachMode.useMyData,
          ),
        ),
        mode: CoachMode.generalOnly,
      );
      expect(texts, isNot(contains(_q1)));
      expect(texts, isNot(contains(CoachPrompts.stripCitations(a1.text))));
    });
  });

  test('multi-turn: an answer written on this phone (nothing sent: every '
      'model known down) stays in the chat, and the next cloud question '
      'replays it as history', () async {
    var now = _now;
    final w = Wire({
      ProviderModels.geminiFlash: (n) =>
          n == 0 ? _perModelDayQuota : _gemini('Back online.'),
      ProviderModels.geminiFlashLite: (_) => _perModelDayQuota,
    });
    final m = w.module(CoachProvider.gemini, clock: () => now);
    final a0 = await m.service.ask('How am I today?');
    expect(a0.answeredBy, ChatMessage.onDevice);
    final a1 = await m.service.ask(_q1, conversationId: a0.conversationId);
    expect(a1.answeredBy, ChatMessage.onDevice);
    expect(a1.sent, isNull, reason: 'both models known down: nothing sent');
    now = now.add(const Duration(days: 1)); // the day quotas are back
    final a2 = await m.service.ask(
      'And the day before?',
      conversationId: a0.conversationId,
    );
    expect(a2.answeredBy, ProviderModels.geminiFlash);
    final contents =
        w.bodies(ProviderModels.geminiFlash).last['contents'] as List;
    final texts = [
      for (final c in contents)
        for (final part in (c as Map)['parts'] as List)
          if ((part as Map)['text'] is String) part['text'] as String,
    ];
    expect(texts, contains(_q1));
    expect(texts, contains(CoachPrompts.stripCitations(a1.text)));
    expect(texts.last, 'And the day before?');
  });
}
