import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:airlog/data/coach/gemini_client.dart';
import 'package:airlog/data/coach/provider_models.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/prompts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key = 'gm-test-FAKEKEY123';

const _tools = [
  CoachToolSpec(
    name: 'get_today_summary',
    description: 'Today\'s Recovery, sleep and strain…',
    inputSchema: {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
      'additionalProperties': false,
    },
  ),
  CoachToolSpec(
    name: 'get_health_monitor',
    description: 'Overnight resting HR, HRV, SpO₂ and skin temperature (°C).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'date': {'type': 'string', 'description': 'yyyy-MM-dd.'},
      },
      'required': ['date'],
      'additionalProperties': false,
    },
  ),
];

const _system = 'You are Airlog\'s coach. SpO₂ is shown in %.';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _body(http.Request r) =>
    jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

List<Map<String, dynamic>> _contents(http.Request r) =>
    (_body(r)['contents'] as List).cast<Map<String, dynamic>>();

(GeminiClient, List<http.Request>) _client(
  List<http.Response> responses, {
  String? model,
  String key = _key,
  List<Duration>? waited,
}) {
  final seen = <http.Request>[];
  final mock = MockClient((req) async {
    seen.add(req);
    return responses[(seen.length - 1).clamp(0, responses.length - 1)];
  });
  return (
    GeminiClient(
      apiKey: key,
      model: model,
      httpClient: mock,
      // No real waiting in tests; record the backoff instead.
      sleep: (d) async => waited?.add(d),
    ),
    seen,
  );
}

Future<LlmTurn> _ask(
  GeminiClient c, {
  List<LlmItem> transcript = const [LlmUser('How did I sleep?')],
  List<CoachToolSpec> tools = _tools,
  ResponseLength length = ResponseLength.brief,
}) => c.next(
  system: _system,
  transcript: transcript,
  tools: tools,
  length: length,
);

Map<String, dynamic> _candidate(
  List<Object?> parts, {
  String finish = 'STOP',
  Map<String, dynamic>? usage,
}) => {
  'candidates': [
    {
      'content': {'role': 'model', 'parts': parts},
      'finishReason': finish,
      'index': 0,
    },
  ],
  'usageMetadata':
      usage ??
      {
        'promptTokenCount': 900,
        'candidatesTokenCount': 50,
        'thoughtsTokenCount': 30,
        'totalTokenCount': 980,
      },
};

const _callParts = <Object?>[
  {'text': 'Reasoning summary', 'thought': true},
  {'text': 'Checking your night.'},
  {
    'functionCall': {'id': 'fc_1', 'name': 'get_today_summary', 'args': {}},
    'thoughtSignature': 'CiQBVKhc7sig+/==',
  },
  {
    'functionCall': {
      'id': 'fc_2',
      'name': 'get_health_monitor',
      'args': {'date': '2026-09-28'},
    },
  },
];

void main() {
  group('request', () {
    test('URL, headers (key never in the URL) and body shape', () async {
      final (c, seen) = _client([
        _json(
          _candidate([
            {'text': 'Fine.'},
          ]),
        ),
      ]);
      expect(c.provider, CoachProvider.gemini);
      expect(c.model, 'gemini-3.8-flash');
      await _ask(c);

      final r = seen.single;
      expect(r.method, 'POST');
      expect(
        r.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-3.8-flash:generateContent',
      );
      expect(r.url.hasQuery, isFalse);
      expect(r.url.toString(), isNot(contains(_key)));
      expect(r.headers['x-goog-api-key'], _key);
      expect(r.headers['content-type'], 'application/json');

      final b = _body(r);
      expect(b['systemInstruction'], {
        'parts': [
          {'text': _system},
        ],
      });
      expect(b['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'How did I sleep?'},
          ],
        },
      ]);
      final decls =
          ((b['tools'] as List).single as Map)['functionDeclarations'] as List;
      expect(decls, hasLength(_tools.length));
      for (var i = 0; i < decls.length; i++) {
        expect(decls[i], {
          'name': _tools[i].name,
          'description': _tools[i].description,
          GeminiApi.functionDeclarationSchema: _tools[i].inputSchema,
        });
      }
      expect(b['toolConfig'], {
        'functionCallingConfig': {'mode': 'AUTO'},
      });
      expect(b['generationConfig'], {
        'thinkingConfig': {'thinkingLevel': 'low'},
        'maxOutputTokens': 8192,
      });
      final gen = b['generationConfig'] as Map;
      for (final banned in ['temperature', 'topP', 'topK']) {
        expect(gen.containsKey(banned), isFalse, reason: banned);
      }
    });

    test(
      'detailed length asks for medium thinking; budget model URL',
      () async {
        final (c, seen) = _client([
          _json(
            _candidate([
              {'text': 'ok'},
            ]),
          ),
        ], model: ProviderModels.geminiBudget);
        await _ask(c, length: ResponseLength.detailed);
        expect(
          seen.single.url.path,
          '/v1beta/models/gemini-3.5-flash-lite:generateContent',
        );
        expect(
          (_body(seen.single)['generationConfig'] as Map)['thinkingConfig'],
          {'thinkingLevel': 'medium'},
        );
      },
    );

    test('no tools: tools and toolConfig are omitted', () async {
      final (c, seen) = _client([
        _json(
          _candidate([
            {'text': 'ok'},
          ]),
        ),
      ]);
      await _ask(c, tools: const []);
      final b = _body(seen.single);
      expect(b.containsKey('tools'), isFalse);
      expect(b.containsKey('toolConfig'), isFalse);
    });
  });

  group('transcript', () {
    test('function responses carry id + name in ONE user content; model parts '
        '(with thoughtSignature) replayed unchanged', () async {
      final (c, seen) = _client([
        _json(_candidate(_callParts)),
        _json(
          _candidate([
            {'text': 'You slept 7 h [r1].'},
          ]),
        ),
      ]);
      final turn = await _ask(c);
      final before = jsonEncode(turn.rawAssistant);

      final transcript = <LlmItem>[
        const LlmUser('How did I sleep?'),
        LlmAssistant(turn),
        const LlmToolResults([
          ToolResult(
            callId: 'fc_1',
            name: 'get_today_summary',
            content: {
              'sleep': {'value': 420, 'unit': 'min', 'ref': 'r1'},
            },
          ),
          ToolResult(
            callId: 'fc_2',
            name: 'get_health_monitor',
            content: {'error': 'No overnight data.'},
            isError: true,
          ),
        ]),
      ];
      await _ask(c, transcript: transcript);

      final contents = _contents(seen[1]);
      expect(contents.map((x) => x['role']), ['user', 'model', 'user']);
      expect(jsonEncode(contents[1]['parts']), jsonEncode(_callParts));
      expect(
        ((contents[1]['parts'] as List)[2] as Map)['thoughtSignature'],
        'CiQBVKhc7sig+/==',
      );
      expect(contents[2]['parts'], [
        {
          'functionResponse': {
            'id': 'fc_1',
            'name': 'get_today_summary',
            'response': {
              'sleep': {'value': 420, 'unit': 'min', 'ref': 'r1'},
            },
          },
        },
        {
          'functionResponse': {
            'id': 'fc_2',
            'name': 'get_health_monitor',
            'response': {'error': 'No overnight data.'},
          },
        },
      ]);

      // Never mutated.
      await _ask(c, transcript: transcript);
      expect(utf8.decode(seen[2].bodyBytes), utf8.decode(seen[1].bodyBytes));
      expect(jsonEncode(turn.rawAssistant), before);
    });

    test('consecutive same-role contents merge, responses first; plain and '
        'empty turns', () async {
      final (c, seen) = _client([
        _json(
          _candidate([
            {'text': 'ok'},
          ]),
        ),
      ]);
      await _ask(
        c,
        transcript: const [
          LlmUser('Earlier question'),
          LlmAssistant(LlmTurn(text: 'Earlier answer')),
          LlmUser('How did I sleep?'),
          LlmAssistant(
            LlmTurn(
              toolCalls: [
                ToolCall(id: 's1', name: 'get_today_summary', input: {}),
              ],
            ),
          ), // no rawAssistant (an on-device turn): built from the calls
          LlmToolResults([
            ToolResult(
              callId: 's1',
              name: 'get_today_summary',
              content: {'text': 'HRV is up'},
            ),
          ]),
          LlmUser('Why?'),
          LlmAssistant(LlmTurn()), // empty: skipped
          LlmUser('Please answer.'),
        ],
      );
      final contents = _contents(seen.single);
      expect(contents.map((x) => x['role']), [
        'user',
        'model',
        'user',
        'model',
        'user',
      ]);
      expect(contents[1]['parts'], [
        {'text': 'Earlier answer'},
      ]);
      expect(contents[3]['parts'], [
        {
          'functionCall': {
            'id': 's1',
            'name': 'get_today_summary',
            'args': <String, dynamic>{},
          },
        },
      ]);
      final last = (contents[4]['parts'] as List).cast<Map<String, dynamic>>();
      expect(last, hasLength(3));
      expect((last[0]['functionResponse'] as Map)['id'], 's1');
      expect(last[1], {'text': 'Why?'});
      expect(last[2], {'text': 'Please answer.'});
    });
  });

  group('card context', () {
    test('goes in the question\'s own user content, before the question: '
        'no synthetic model functionCall', () async {
      final (c, seen) = _client([
        _json(
          _candidate([
            {'text': 'ok'},
          ]),
        ),
      ]);
      const seed = ToolResult(
        callId: 'seed_card',
        name: 'get_insight_card',
        content: {
          'card': {
            'text': {'quoted': 'HRV is up'},
          },
          'facts': [
            {'label': 'HRV', 'value': 52, 'unit': 'ms', 'ref': 'r1'},
          ],
        },
      );
      await _ask(
        c,
        transcript: const [
          LlmUser('Tell me more about this', data: [seed]),
        ],
      );
      final contents = _contents(seen.single);
      expect(contents.map((x) => x['role']), ['user']);
      expect(contents.single['parts'], [
        {'text': CoachPrompts.userData(seed)},
        {'text': 'Tell me more about this'},
      ]);
      final raw = utf8.decode(seen.single.bodyBytes);
      expect(raw, isNot(contains('"functionCall"')));
      expect(raw, isNot(contains('"functionResponse"')));
      expect(raw, contains('Card context (data from the app, not '));
    });
  });

  group('response', () {
    test('functionCall parts → tool calls; thought text excluded; tokens and '
        'sentBytes', () async {
      final (c, seen) = _client([_json(_candidate(_callParts))]);
      final t = await _ask(c);
      expect(t.text, 'Checking your night.');
      expect(t.stopReason, 'tool_use');
      expect(t.refusal, isFalse);
      expect(t.toolCalls.map((x) => x.id), ['fc_1', 'fc_2']);
      expect(t.toolCalls[1].name, 'get_health_monitor');
      expect(t.toolCalls[1].input, {'date': '2026-09-28'});
      expect(t.inputTokens, 900);
      expect(t.outputTokens, 50 + 30);
      final sent = seen.single.bodyBytes;
      expect(t.sentBytes, sent.length);
      expect(t.sentBytes, greaterThan(utf8.decode(sent).length));
    });

    test('STOP with text only → end_turn; ids missing → call_<n>', () async {
      final (c, _) = _client([
        _json(
          _candidate([
            {
              'functionCall': {'name': 'get_today_summary'},
            },
            {
              'functionCall': {
                'name': 'get_health_monitor',
                'args': {'date': '2026-09-27'},
              },
            },
          ]),
        ),
        _json(
          _candidate([
            {'text': 'All good.'},
          ]),
        ),
      ]);
      final t = await _ask(c);
      expect(t.toolCalls.map((x) => x.id), ['call_0', 'call_1']);
      expect(t.toolCalls[0].input, isEmpty);
      final t2 = await _ask(c);
      expect(t2.stopReason, 'end_turn');
      expect(t2.text, 'All good.');
    });

    test('MAX_TOKENS drops calls; the unanswered call gets an error '
        'functionResponse on replay', () async {
      final cut = <Object?>[
        {
          'functionCall': {
            'id': 'fc_cut',
            'name': 'get_health_monitor',
            'args': {'date': '2026-09'},
          },
          'thoughtSignature': 'sigcut',
        },
      ];
      final (c, seen) = _client([
        _json(_candidate(cut, finish: 'MAX_TOKENS')),
        _json(
          _candidate([
            {'text': 'ok'},
          ]),
        ),
      ]);
      final t = await _ask(c);
      expect(t.stopReason, 'max_tokens');
      expect(t.toolCalls, isEmpty);
      expect(t.refusal, isFalse);

      await _ask(
        c,
        transcript: [
          const LlmUser('How did I sleep?'),
          LlmAssistant(t),
          const LlmUser('Answer with what you have.'),
        ],
      );
      final contents = _contents(seen[1]);
      expect(contents.map((x) => x['role']), ['user', 'model', 'user']);
      expect(jsonEncode(contents[1]['parts']), jsonEncode(cut));
      final parts = (contents[2]['parts'] as List).cast<Map<String, dynamic>>();
      expect(parts, hasLength(2));
      final fr = parts[0]['functionResponse'] as Map;
      expect(fr['id'], 'fc_cut');
      expect(fr['name'], 'get_health_monitor');
      expect((fr['response'] as Map).containsKey('error'), isTrue);
      expect(parts[1], {'text': 'Answer with what you have.'});
    });

    test('SAFETY → refusal with no tool calls', () async {
      final (c, _) = _client([
        _json(
          _candidate([
            {
              'functionCall': {'id': 'x', 'name': 'get_today_summary'},
            },
          ], finish: 'SAFETY'),
        ),
      ]);
      final t = await _ask(c);
      expect(t.refusal, isTrue);
      expect(t.stopReason, 'refusal');
      expect(t.toolCalls, isEmpty);
    });

    test('promptFeedback.blockReason without candidates → refusal', () async {
      final (c, _) = _client([
        _json({
          'promptFeedback': {'blockReason': 'PROHIBITED_CONTENT'},
          'usageMetadata': {'promptTokenCount': 12},
        }),
      ]);
      final t = await _ask(c);
      expect(t.refusal, isTrue);
      expect(t.stopReason, 'refusal');
      expect(t.inputTokens, 12);
      expect(t.outputTokens, 0);
    });

    test('no candidates and no block reason → server', () async {
      final (c, _) = _client([_json(<String, dynamic>{})]);
      await expectLater(
        _ask(c),
        throwsA(
          isA<CoachException>().having(
            (e) => e.kind,
            'kind',
            CoachErrorKind.server,
          ),
        ),
      );
    });
  });

  group('errors', () {
    Map<String, dynamic> err(
      int code,
      String status,
      String message, {
      String? reason,
    }) => {
      'error': {
        'code': code,
        'message': message,
        'status': status,
        if (reason != null)
          'details': [
            {
              '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
              'reason': reason,
              'domain': 'googleapis.com',
            },
          ],
      },
    };

    final cases = <(String, int, Map<String, dynamic>, CoachErrorKind)>[
      (
        '400 API_KEY_INVALID reason',
        400,
        err(
          400,
          'INVALID_ARGUMENT',
          'Bad key $_key',
          reason: 'API_KEY_INVALID',
        ),
        CoachErrorKind.invalidKey,
      ),
      (
        '400 "API key not valid" message',
        400,
        err(
          400,
          'INVALID_ARGUMENT',
          'API key not valid. Please pass a valid API key. ($_key)',
        ),
        CoachErrorKind.invalidKey,
      ),
      (
        '400 other',
        400,
        err(400, 'INVALID_ARGUMENT', 'Invalid JSON payload; key $_key'),
        CoachErrorKind.unknown,
      ),
      (
        '401',
        401,
        err(401, 'UNAUTHENTICATED', 'Unauthenticated: $_key'),
        CoachErrorKind.invalidKey,
      ),
      (
        '403',
        403,
        err(403, 'PERMISSION_DENIED', 'Denied for $_key'),
        CoachErrorKind.invalidKey,
      ),
      (
        '402',
        402,
        err(402, 'FAILED_PRECONDITION', 'Prepay credit exhausted ($_key)'),
        CoachErrorKind.quotaExceeded,
      ),
      (
        '404',
        404,
        err(404, 'NOT_FOUND', 'models/x is not found ($_key)'),
        CoachErrorKind.unknown,
      ),
      (
        '429',
        429,
        err(429, 'RESOURCE_EXHAUSTED', 'Quota exceeded for $_key'),
        CoachErrorKind.rateLimited,
      ),
      (
        '500',
        500,
        err(500, 'INTERNAL', 'Internal error ($_key)'),
        CoachErrorKind.server,
      ),
      (
        '503',
        503,
        err(503, 'UNAVAILABLE', 'The model is overloaded ($_key)'),
        CoachErrorKind.server,
      ),
    ];
    for (final (name, status, body, kind) in cases) {
      test('$name → ${kind.name}, key scrubbed', () async {
        final (c, _) = _client([_json(body, status)]);
        final e = await _ask(c)
            .then<Object>((_) => 'no error', onError: (Object e) => e);
        expect(e, isA<CoachException>());
        final ce = e as CoachException;
        expect(ce.kind, kind);
        expect(ce.message, contains('[redacted]'));
        expect(ce.toString(), isNot(contains(_key)));
        expect(ce.toString(), isNot(contains('FAKEKEY123')));
      });
    }

    test('malformed 200 JSON → server', () async {
      final (c, _) = _client([
        http.Response.bytes(utf8.encode('{"candidates": ['), 200),
      ]);
      await expectLater(
        _ask(c),
        throwsA(
          isA<CoachException>().having(
            (e) => e.kind,
            'kind',
            CoachErrorKind.server,
          ),
        ),
      );
    });

    group('busy answers are retried', () {
      Map<String, dynamic> busy(
        int code,
        String status,
        String message, {
        List<Map<String, dynamic>> details = const [],
      }) => {
        'error': {
          'code': code,
          'message': message,
          'status': status,
          if (details.isNotEmpty) 'details': details,
        },
      };

      test('503 high demand, then OK: one retry, no error', () async {
        final waited = <Duration>[];
        final (c, seen) = _client([
          _json(
            busy(503, 'UNAVAILABLE', 'The model is experiencing high demand.'),
            503,
          ),
          _json(
            _candidate([
              {'text': 'Fine.'},
            ]),
          ),
        ], waited: waited);
        final turn = await _ask(c);
        expect(turn.text, 'Fine.');
        expect(seen, hasLength(2));
        expect(waited.single.inMilliseconds, inInclusiveRange(1500, 2500));
      });

      test('429 per minute honours RetryInfo.retryDelay', () async {
        final waited = <Duration>[];
        final (c, seen) = _client([
          _json(
            busy(
              429,
              'RESOURCE_EXHAUSTED',
              'You exceeded your current quota. Please retry in 12.4s.',
              details: [
                {
                  '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
                  'violations': [
                    {
                      'quotaMetric': 'generativelanguage.googleapis.com/generate_content_free_tier_requests',
                      'quotaId': 'GenerateRequestsPerMinutePerProjectPerModel-FreeTier',
                    },
                  ],
                },
                {
                  '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                  'retryDelay': '12s',
                },
              ],
            ),
            429,
          ),
          _json(
            _candidate([
              {'text': 'ok'},
            ]),
          ),
        ], waited: waited);
        await _ask(c);
        expect(seen, hasLength(2));
        expect(waited, [const Duration(seconds: 12)]);
      });

      test('429 with the quota used up for the day: no retry, '
          'quotaExceeded', () async {
        final waited = <Duration>[];
        final (c, seen) = _client([
          _json(
            busy(
              429,
              'RESOURCE_EXHAUSTED',
              'You exceeded your current quota ($_key).',
              details: [
                {
                  '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
                  'violations': [
                    {
                      'quotaId':
                          'GenerateRequestsPerDayPerProjectPerModel-FreeTier',
                    },
                  ],
                },
                {
                  '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                  'retryDelay': '20s',
                },
              ],
            ),
            429,
          ),
        ], waited: waited);
        final e = await _ask(c)
            .then<Object>((_) => 'no error', onError: (Object e) => e);
        expect((e as CoachException).kind, CoachErrorKind.quotaExceeded);
        expect(e.toString(), isNot(contains(_key)));
        expect(seen, hasLength(1));
        expect(waited, isEmpty);
      });

      test('at most two retries, then the error', () async {
        final waited = <Duration>[];
        final (c, seen) = _client([
          _json(busy(503, 'UNAVAILABLE', 'High demand.'), 503),
        ], waited: waited);
        await expectLater(
          _ask(c),
          throwsA(
            isA<CoachException>().having(
              (e) => e.kind,
              'kind',
              CoachErrorKind.server,
            ),
          ),
        );
        expect(seen, hasLength(3));
        expect(waited, hasLength(2));
      });

      test('a wait past the time budget is not taken', () async {
        final waited = <Duration>[];
        final (c, seen) = _client([
          _json(
            busy(
              429,
              'RESOURCE_EXHAUSTED',
              'Per-minute quota.',
              details: [
                {
                  '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                  'retryDelay': '600s',
                },
              ],
            ),
            429,
          ),
        ], waited: waited);
        final e = await _ask(c)
            .then<Object>((_) => 'no error', onError: (Object e) => e);
        expect((e as CoachException).kind, CoachErrorKind.rateLimited);
        expect(seen, hasLength(1));
        expect(waited, isEmpty);
      });
    });

    test('ClientException / SocketException → network, key scrubbed', () async {
      final c1 = GeminiClient(
        apiKey: _key,
        httpClient: MockClient(
          (_) async => throw http.ClientException('closed; key=$_key'),
        ),
      );
      final e = await _ask(c1)
          .then<Object>((_) => 'no error', onError: (Object e) => e);
      expect((e as CoachException).kind, CoachErrorKind.network);
      expect(e.toString(), isNot(contains(_key)));

      final c2 = GeminiClient(
        apiKey: _key,
        httpClient: MockClient(
          (_) async => throw const SocketException('Failed host lookup'),
        ),
      );
      await expectLater(
        _ask(c2),
        throwsA(
          isA<CoachException>().having(
            (e) => e.kind,
            'kind',
            CoachErrorKind.network,
          ),
        ),
      );
    });

    test('timeout → network', () async {
      final never = Completer<http.Response>();
      final c = GeminiClient(
        apiKey: _key,
        httpClient: MockClient((_) => never.future),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        _ask(c),
        throwsA(
          isA<CoachException>()
              .having((e) => e.kind, 'kind', CoachErrorKind.network)
              .having((e) => e.toString(), 'toString', isNot(contains(_key))),
        ),
      );
    });

    test('missing key → notConfigured, no request', () async {
      final (c, seen) = _client([
        _json(
          _candidate([
            {'text': 'ok'},
          ]),
        ),
      ], key: '');
      await expectLater(
        _ask(c),
        throwsA(
          isA<CoachException>().having(
            (e) => e.kind,
            'kind',
            CoachErrorKind.notConfigured,
          ),
        ),
      );
      expect(seen, isEmpty);
    });
  });
}
