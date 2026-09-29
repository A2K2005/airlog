// Coach model fallback (PRODUCT_PLAN §7 "Coach model fallback"), end to end
// over the real ClaudeClient / GeminiClient, the real repository chain and
// meter, and CoachServiceImpl, with a fake HTTP client that answers per
// model. Nothing waits for real (the retry sleep is injected).

import 'dart:convert';

import 'package:airlog/data/coach/claude_client.dart';
import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/data/coach/gemini_client.dart';
import 'package:airlog/data/coach/coach_repository_impl.dart';
import 'package:airlog/data/coach/coach_store.dart';
import 'package:airlog/data/coach/provider_models.dart';
import 'package:airlog/data/coach/quota_clock.dart';
import 'package:airlog/data/coach/secret_store.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/coach_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime(2026, 9, 29, 9);

CoachSettings _settings(CoachProvider p, {bool backups = true}) =>
    CoachSettings(
      provider: p,
      consentAt: DateTime(2026, 9, 1),
      consentVersion: kCoachConsentVersion,
      adultConfirmed: true,
      backupModels: backups,
    );

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _geminiText(String text) => _json({
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': text},
        ],
      },
      'finishReason': 'STOP',
      'index': 0,
    },
  ],
  'usageMetadata': {'promptTokenCount': 120, 'candidatesTokenCount': 12},
});

http.Response _claudeText(String model, String text) => _json({
  'id': 'msg_1',
  'type': 'message',
  'role': 'assistant',
  'model': model,
  'content': [
    {'type': 'text', 'text': text},
  ],
  'stop_reason': 'end_turn',
  'usage': {'input_tokens': 120, 'output_tokens': 12},
});

http.Response _geminiError(
  int code,
  String status, {
  List<Map<String, dynamic>> details = const [],
}) => _json({
  'error': {
    'code': code,
    'status': status,
    'message': 'error $code',
    if (details.isNotEmpty) 'details': details,
  },
}, code);

http.Response _claudeError(int code, String type) => _json({
  'type': 'error',
  'error': {'type': type, 'message': 'error $code'},
}, code);

final _perModelDayQuota = [
  {
    '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
    'violations': [
      {'quotaId': 'GenerateRequestsPerDayPerProjectPerModel-FreeTier'},
    ],
  },
];

const _plain = 'Keep today easy and get to bed on time.';

/// A fake provider: answers each model with its own script and records
/// which host and model every HTTP request went to.
class Wire {
  Wire(this.script);

  /// Model id → the n-th response for that model (n from 0).
  final Map<String, http.Response Function(int n, Map<String, dynamic> body)>
  script;
  final hits = <(String host, String model)>[];
  final waits = <Duration>[];
  final factoryCalls = <CoachProvider>[];

  int count(String model) => hits.where((h) => h.$2 == model).length;

  late final client = MockClient((req) async {
    final body = jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
    final model = req.url.host.contains('googleapis')
        ? RegExp(r'models/([^:]+):').firstMatch(req.url.path)!.group(1)!
        : body['model'] as String;
    final n = count(model);
    hits.add((req.url.host, model));
    final f = script[model];
    if (f == null) return _json({'error': 'unexpected model $model'}, 400);
    return f(n, body);
  });

  CoachModule module(CoachSettings s, {DateTime Function()? clock}) =>
      CoachModule.inMemory(
        InMemoryHealthRepository.demo(now: _now),
        clock: clock ?? () => _now,
        settings: s,
        clients: (p, key, model) {
          factoryCalls.add(p);
          return switch (p) {
            CoachProvider.gemini => GeminiClient(
              apiKey: key,
              model: model,
              httpClient: client,
              sleep: (d) async => waits.add(d),
            ),
            _ => ClaudeClient(
              apiKey: key,
              model: model,
              httpClient: client,
              sleep: (d) async => waits.add(d),
            ),
          };
        },
        keys: const {
          CoachProvider.gemini: 'gm-test-FAKEKEY123',
          CoachProvider.claude: 'sk-ant-test-FAKEKEY123',
        },
      );
}

const _flash = ProviderModels.geminiFlash;
const _lite = ProviderModels.geminiFlashLite;

void main() {
  test('the chain lives in provider_models: same provider, in order', () {
    expect(ProviderModels.chainFor(CoachProvider.gemini, null), [
      _flash,
      _lite,
    ]);
    expect(ProviderModels.chainFor(CoachProvider.claude, null), [
      ProviderModels.claudeOpus,
      ProviderModels.claudeSonnet,
      ProviderModels.claudeHaiku,
    ]);
    // A cheaper chosen model only falls further down.
    expect(
      ProviderModels.chainFor(
        CoachProvider.claude,
        ProviderModels.claudeSonnet,
      ),
      [ProviderModels.claudeSonnet, ProviderModels.claudeHaiku],
    );
    expect(ProviderModels.chainFor(CoachProvider.gemini, _lite), [_lite]);
    expect(
      ProviderModels.chainFor(CoachProvider.gemini, _flash, backups: false),
      [_flash],
    );
    expect(ProviderModels.chainFor(CoachProvider.offline, null), isEmpty);
  });

  test('"Use a backup model when busy" is on by default and persists', () {
    expect(const CoachSettings().backupModels, isTrue);
    expect(CoachSettings.fromJson(const {}).backupModels, isTrue);
    final off = const CoachSettings().copyWith(backupModels: false);
    expect(CoachSettings.fromJson(off.toJson()).backupModels, isFalse);
  });

  test('a per-model day quota (429) restarts the question on the next '
      'model, and the answer says which model wrote it', () async {
    final w = Wire({
      _flash: (_, _) =>
          _geminiError(429, 'RESOURCE_EXHAUSTED', details: _perModelDayQuota),
      _lite: (_, _) => _geminiText(_plain),
    });
    final m = w.module(_settings(CoachProvider.gemini));
    final a = await m.service.ask('How should I train today?');
    expect(a.error, isNull);
    expect(a.text, _plain);
    expect(a.answeredBy, _lite);
    expect(a.fallbackFrom, _flash);
    expect(a.fallbackReason, CoachErrorKind.quotaExceeded.name);
    // A day quota is not retried on the same model.
    expect(w.count(_flash), 1);
    expect(w.count(_lite), 1);
    expect(w.waits, isEmpty);
    // The fallback turn is a fresh question: one user message, no replayed
    // model turn from the failed model.
    final liteBody = w.hits.indexWhere((h) => h.$2 == _lite);
    expect(liteBody, 1);
  });

  test('a 503 that persists after the retries moves to the next model; '
      'the budget counts every request', () async {
    final w = Wire({
      _flash: (_, _) => _geminiError(503, 'UNAVAILABLE'),
      _lite: (_, _) => _geminiText(_plain),
    });
    final m = w.module(_settings(CoachProvider.gemini));
    final a = await m.service.ask('How should I train today?');
    expect(a.error, isNull);
    expect(a.answeredBy, _lite);
    expect(a.fallbackReason, CoachErrorKind.server.name);
    // One call on 3.8 Flash = the first try + 2 retries.
    expect(w.count(_flash), 3);
    expect(w.waits, hasLength(2));
    expect(w.count(_lite), 1);
    // Every call counts toward the daily budget: the failed one too (its
    // retries inside the call count once), plus the answering one.
    final u = await m.repository.usageToday();
    expect(u!.requests, 2);
    expect(u.inputTokens, 120);
    expect(a.sent!.requests, 2);
    expect(a.sent!.model, _lite);
  });

  test(
    'a rejected key (401) skips the chain: answered on this phone',
    () async {
      final w = Wire({
        _flash: (_, _) => _geminiError(401, 'UNAUTHENTICATED'),
        _lite: (_, _) => _geminiText(_plain),
      });
      final m = w.module(_settings(CoachProvider.gemini));
      final a = await m.service.ask('How did I sleep last night?');
      expect(a.error, isNull);
      expect(a.answeredBy, ChatMessage.onDevice);
      expect(a.fallbackFrom, _flash);
      expect(a.fallbackReason, CoachErrorKind.invalidKey.name);
      expect(w.count(_lite), 0, reason: 'account-wide: no backup model');
      // The on-device answer is checked like any other.
      expect(a.verification, isNotNull);
      expect(a.verification!.verified, isTrue);
      expect(a.refs, isNotEmpty);
      // The rejected request still counts.
      expect((await m.repository.usageToday())!.requests, 1);
    },
  );

  test('402 / out of credit is account-wide too', () async {
    final w = Wire({
      _flash: (_, _) => _geminiError(402, 'FAILED_PRECONDITION'),
      _lite: (_, _) => _geminiText(_plain),
    });
    final a = await w
        .module(_settings(CoachProvider.gemini))
        .service
        .ask('How did I sleep last night?');
    expect(a.answeredBy, ChatMessage.onDevice);
    expect(a.fallbackReason, CoachErrorKind.quotaExceeded.name);
    expect(w.count(_lite), 0);
  });

  test('every model busy: the chain ends on this phone', () async {
    final w = Wire({
      _flash: (_, _) => _geminiError(503, 'UNAVAILABLE'),
      _lite: (_, _) => _geminiError(503, 'UNAVAILABLE'),
    });
    final m = w.module(_settings(CoachProvider.gemini));
    final a = await m.service.ask('How did I sleep last night?');
    expect(a.error, isNull);
    expect(a.answeredBy, ChatMessage.onDevice);
    expect(a.fallbackFrom, _flash);
    expect(a.fallbackReason, CoachErrorKind.server.name);
    expect(w.count(_flash), 3);
    expect(w.count(_lite), 3);
    expect(a.text, isNotEmpty);
    expect((await m.repository.usageToday())!.requests, 2);
  });

  test('backup models off: no chain, straight to on-device', () async {
    final w = Wire({
      _flash: (_, _) => _geminiError(503, 'UNAVAILABLE'),
      _lite: (_, _) => _geminiText(_plain),
    });
    final a = await w
        .module(_settings(CoachProvider.gemini, backups: false))
        .service
        .ask('How did I sleep last night?');
    expect(a.answeredBy, ChatMessage.onDevice);
    expect(a.fallbackFrom, _flash);
    expect(w.count(_lite), 0);
  });

  test('Claude: 404 model not found moves down the Claude chain only, '
      'never to Gemini', () async {
    const opus = ProviderModels.claudeOpus;
    const sonnet = ProviderModels.claudeSonnet;
    final w = Wire({
      opus: (_, _) => _claudeError(404, 'not_found_error'),
      sonnet: (_, _) => _claudeText(sonnet, _plain),
    });
    final a = await w
        .module(_settings(CoachProvider.claude))
        .service
        .ask('How should I train today?');
    expect(a.answeredBy, sonnet);
    expect(a.fallbackFrom, opus);
    expect(a.fallbackReason, CoachErrorKind.unknown.name);
    expect(w.factoryCalls.toSet(), {CoachProvider.claude});
  });

  test('no cross-provider fallback: Claude all overloaded ends on-device, '
      'Gemini is never asked although its key is stored', () async {
    const opus = ProviderModels.claudeOpus;
    const sonnet = ProviderModels.claudeSonnet;
    const haiku = ProviderModels.claudeHaiku;
    final w = Wire({
      opus: (_, _) => _claudeError(529, 'overloaded_error'),
      sonnet: (_, _) => _claudeError(529, 'overloaded_error'),
      haiku: (_, _) => _claudeError(529, 'overloaded_error'),
      _flash: (_, _) => _geminiText(_plain),
    });
    final m = w.module(_settings(CoachProvider.claude));
    final a = await m.service.ask('How did I sleep last night?');
    expect(a.answeredBy, ChatMessage.onDevice);
    expect(w.factoryCalls.toSet(), {CoachProvider.claude});
    expect(w.hits.where((h) => h.$1.contains('googleapis')), isEmpty);
    expect({for (final h in w.hits) h.$2}, {opus, sonnet, haiku});
    expect((await m.repository.usageToday())!.requests, 3);
  });

  test('a server-side switch is recorded from the response model', () async {
    const opus = ProviderModels.claudeOpus;
    final w = Wire({opus: (_, _) => _claudeText('claude-opus-4-8', _plain)});
    final a = await w
        .module(_settings(CoachProvider.claude))
        .service
        .ask('How should I train today?');
    expect(a.answeredBy, 'claude-opus-4-8');
    expect(a.fallbackFrom, opus);
    expect(a.fallbackReason, isNull, reason: 'the app did not fall back');
  });

  test('the verifier still runs on a fallback answer: the repair round '
      'goes to the same fallback model', () async {
    final w = Wire({
      _flash: (_, _) => _geminiError(503, 'UNAVAILABLE'),
      // First answer quotes a number nothing supports; the repair fixes it.
      _lite: (n, _) => n == 0
          ? _geminiText('Your HRV was 997 ms last night.')
          : _geminiText(_plain),
    });
    final m = w.module(_settings(CoachProvider.gemini));
    final a = await m.service.ask('How should I train today?');
    expect(a.answeredBy, _lite);
    expect(w.count(_lite), 2);
    expect(w.count(_flash), 3, reason: 'the repair never goes back');
    expect(a.text, _plain);
    expect(a.verification!.repaired, isTrue);
    expect(a.verification!.verified, isTrue);
    expect(a.text, isNot(contains('997')));
  });

  test('a refusal is an answer, not a failure: no backup model', () async {
    const opus = ProviderModels.claudeOpus;
    final w = Wire({
      opus: (_, _) => _json({
        'type': 'message',
        'model': opus,
        'content': <Object>[],
        'stop_reason': 'refusal',
        'usage': {'input_tokens': 10, 'output_tokens': 0},
      }),
    });
    final a = await w
        .module(_settings(CoachProvider.claude))
        .service
        .ask('How should I train today?');
    expect(a.error, CoachErrorKind.refused.name);
    expect(w.hits, hasLength(1));
    expect(a.fallbackFrom, isNull);
  });

  group('models known to be down are skipped', () {
    test('a per-model day quota: later questions go straight to the next '
        'model, with no failed request and no wait', () async {
      final w = Wire({
        _flash: (_, _) =>
            _geminiError(429, 'RESOURCE_EXHAUSTED', details: _perModelDayQuota),
        _lite: (_, _) => _geminiText(_plain),
      });
      final m = w.module(_settings(CoachProvider.gemini));
      await m.service.ask('How should I train today?');
      expect(w.count(_flash), 1);
      final second = await m.service.ask('And tomorrow?');
      expect(w.count(_flash), 1, reason: 'skipped: no request');
      expect(w.count(_lite), 2);
      expect(w.waits, isEmpty);
      expect(second.answeredBy, _lite);
      expect(second.fallbackFrom, _flash);
      expect(second.fallbackReason, CoachErrorKind.quotaExceeded.name);
      final down = await m.repository.modelDown(_flash);
      expect(down!.until, nextPacificMidnight(_now));
      expect((await m.repository.usageToday())!.requests, 3);
    });

    test('a retry delay: skipped until it passes, then tried again', () async {
      var now = _now;
      final w = Wire({
        // The server asks for 10 min: longer than the request's budget, so
        // it is not retried in place.
        _flash: (n, _) => n == 0
            ? _geminiError(
                429,
                'RESOURCE_EXHAUSTED',
                details: [
                  {
                    '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                    'retryDelay': '600s',
                  },
                ],
              )
            : _geminiText('Flash is back.'),
        _lite: (_, _) => _geminiText(_plain),
      });
      final m = w.module(_settings(CoachProvider.gemini), clock: () => now);
      await m.service.ask('How should I train today?');
      now = now.add(const Duration(minutes: 5));
      await m.service.ask('And tomorrow?');
      expect(w.count(_flash), 1);
      now = now.add(const Duration(minutes: 6));
      final back = await m.service.ask('And the day after?');
      expect(w.count(_flash), 2);
      expect(back.answeredBy, _flash);
      expect(back.fellBack, isFalse);
    });

    test(
      'every model known down: on this phone, and nothing is sent',
      () async {
        final w = Wire({
          _flash: (_, _) => _geminiError(
            429,
            'RESOURCE_EXHAUSTED',
            details: _perModelDayQuota,
          ),
          _lite: (_, _) => _geminiError(
            429,
            'RESOURCE_EXHAUSTED',
            details: _perModelDayQuota,
          ),
        });
        final m = w.module(_settings(CoachProvider.gemini));
        await m.service.ask('How did I sleep last night?');
        expect(w.hits, hasLength(2));
        final a = await m.service.ask('How did I sleep last night?');
        expect(w.hits, hasLength(2), reason: 'no request at all');
        expect(a.answeredBy, ChatMessage.onDevice);
        expect(a.fallbackReason, CoachErrorKind.quotaExceeded.name);
        expect(a.sent, isNull);
      },
    );

    test('the day-quota mark is persisted until midnight Pacific; a retry '
        'delay is not', () async {
      final store = MemoryCoachStore();
      var now = DateTime.utc(2026, 9, 29, 3, 30); // 20:30 PDT on the 28th
      CoachRepositoryImpl repo() => CoachRepositoryImpl(
        store: store,
        secrets: MemorySecretStore(),
        clock: () => now,
      );
      final a = repo();
      await a.noteModelUnavailable(
        _flash,
        const ModelUnavailable(
          CoachErrorKind.quotaExceeded,
          'day quota',
          dayQuota: true,
        ),
      );
      await a.noteModelUnavailable(
        _lite,
        const ModelUnavailable(
          CoachErrorKind.rateLimited,
          'wait',
          retryAfter: Duration(minutes: 30),
        ),
      );
      final b = repo(); // a new process: same store, empty memory
      final down = await b.modelDown(_flash);
      expect(down!.until, DateTime.utc(2026, 9, 29, 7));
      expect(down.reason, CoachErrorKind.quotaExceeded);
      expect(await b.modelDown(_lite), isNull);
      expect(await a.modelDown(_lite), isNotNull);
      now = DateTime.utc(2026, 9, 29, 7);
      expect(await b.modelDown(_flash), isNull);
      expect(await repo().modelDown(_flash), isNull);
    });

    test('a 503 without a delay leaves no mark: the next question tries the '
        'model again', () async {
      final w = Wire({
        _flash: (_, _) => _geminiError(503, 'UNAVAILABLE'),
        _lite: (_, _) => _geminiText(_plain),
      });
      final m = w.module(_settings(CoachProvider.gemini));
      await m.service.ask('How should I train today?');
      await m.service.ask('And tomorrow?');
      expect(w.count(_flash), 6);
      expect(await m.repository.modelDown(_flash), isNull);
    });
  });

  test('midnight Pacific: PDT in summer, PST in winter', () {
    // 09:00 IST on 29 Sep = 20:30 PDT on the 28th → 29 Sep 00:00 PDT.
    expect(
      nextPacificMidnight(DateTime.utc(2026, 9, 29, 3, 30)),
      DateTime.utc(2026, 9, 29, 7),
    );
    // 1 Dec 04:00 PST → 2 Dec 00:00 PST.
    expect(
      nextPacificMidnight(DateTime.utc(2026, 12, 1, 12)),
      DateTime.utc(2026, 12, 2, 8),
    );
    // The day DST starts (8 Mar 2026): midnight is still PST.
    expect(
      nextPacificMidnight(DateTime.utc(2026, 3, 7, 20)),
      DateTime.utc(2026, 3, 8, 8),
    );
    // The day DST ends (1 Nov 2026): midnight is still PDT.
    expect(
      nextPacificMidnight(DateTime.utc(2026, 10, 31, 20)),
      DateTime.utc(2026, 11, 1, 7),
    );
  });

  test('the fallback fields survive storage', () {
    final m = ChatMessage(
      id: 'a',
      conversationId: 'c',
      role: ChatRole.assistant,
      text: 'x',
      at: DateTime.utc(2026, 9, 29, 8),
      answeredBy: _lite,
      fallbackFrom: _flash,
      fallbackReason: 'server',
    );
    final back = ChatMessage.fromJson(m.toJson());
    expect(back.answeredBy, _lite);
    expect(back.fallbackFrom, _flash);
    expect(back.fallbackReason, 'server');
    expect(back.fellBack, isTrue);
  });
}
