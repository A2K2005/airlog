import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:airlog/data/coach/claude_client.dart';
import 'package:airlog/data/coach/provider_models.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/prompts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key = 'sk-ant-test-FAKEKEY123';

// Strict-compatible specs shaped like CoachTools.all (one optional property,
// non-ASCII text in descriptions).
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
  CoachToolSpec(
    name: 'propose_memory',
    description: 'Suggests saving a lasting fact.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'},
        'expiresOn': {'type': 'string'},
      },
      'required': ['text'],
      'additionalProperties': false,
    },
    readsUserData: false,
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

List<Map<String, dynamic>> _messages(http.Request r) =>
    (_body(r)['messages'] as List).cast<Map<String, dynamic>>();

/// A client whose mock answers [responses] in order and records requests.
(ClaudeClient, List<http.Request>) _client(
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
    ClaudeClient(
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
  ClaudeClient c, {
  List<LlmItem> transcript = const [LlmUser('How did I sleep?')],
  List<CoachToolSpec> tools = _tools,
  String system = _system,
}) => c.next(
  system: system,
  transcript: transcript,
  tools: tools,
  length: ResponseLength.brief,
);

const _toolUseJson = '''
{"id":"msg_01","type":"message","role":"assistant","model":"claude-opus-5-5",
 "content":[
  {"type":"thinking","thinking":"","signature":"EqQBCkgIARABGAIiQ3sig+/=="},
  {"type":"text","text":"Let me check your night."},
  {"type":"tool_use","id":"toolu_01","name":"get_today_summary","input":{}},
  {"type":"tool_use","id":"toolu_02","name":"get_health_monitor",
   "input":{"date":"2026-09-28"}}
 ],
 "stop_reason":"tool_use","stop_sequence":null,
 "usage":{"input_tokens":120,"cache_creation_input_tokens":3000,
          "cache_read_input_tokens":500,"output_tokens":80}}
''';

http.Response _raw(String json) => http.Response.bytes(
  utf8.encode(json),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _textResponse(String text, {String stop = 'end_turn'}) => {
  'id': 'msg_02',
  'type': 'message',
  'role': 'assistant',
  'content': [
    {'type': 'thinking', 'thinking': '', 'signature': 'sig2'},
    {'type': 'text', 'text': text},
  ],
  'stop_reason': stop,
  'usage': {'input_tokens': 10, 'output_tokens': 5},
};

void main() {
  group('request', () {
    test('Opus 5.5: URL, headers and body shape', () async {
      final (c, seen) = _client([_json(_textResponse('Fine.'))]);
      expect(c.provider, CoachProvider.claude);
      expect(c.model, 'claude-opus-5-5');
      await _ask(c);

      final r = seen.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(r.url.toString(), isNot(contains(_key)));
      expect(r.headers['x-api-key'], _key);
      expect(r.headers['anthropic-version'], '2023-06-01');
      expect(r.headers['content-type'], 'application/json');
      expect(r.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');

      final b = _body(r);
      expect(b['model'], 'claude-opus-5-5');
      expect(b['max_tokens'], 16000);
      expect(b['system'], [
        {
          'type': 'text',
          'text': _system,
          'cache_control': {'type': 'ephemeral'},
        },
      ]);
      final tools = (b['tools'] as List).cast<Map<String, dynamic>>();
      expect(tools, hasLength(_tools.length));
      for (var i = 0; i < tools.length; i++) {
        expect(tools[i]['name'], _tools[i].name);
        expect(tools[i]['description'], _tools[i].description);
        expect(tools[i]['input_schema'], _tools[i].inputSchema);
        expect(tools[i]['strict'], true);
        if (i == tools.length - 1) {
          expect(tools[i]['cache_control'], {'type': 'ephemeral'});
        } else {
          expect(tools[i].containsKey('cache_control'), isFalse);
        }
      }
      expect(b['tool_choice'], {'type': 'auto'});
      expect(b['output_config'], {'effort': 'medium'});
      expect(b['fallbacks'], 'default');
      for (final banned in ['thinking', 'temperature', 'top_p', 'top_k']) {
        expect(b.containsKey(banned), isFalse, reason: banned);
      }
      expect(b['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'How did I sleep?'},
          ],
        },
      ]);
    });

    test('Sonnet 5.5 gets the fallback beta and effort medium', () async {
      final (c, seen) = _client([
        _json(_textResponse('ok')),
      ], model: 'claude-sonnet-5-5');
      await _ask(c);
      final b = _body(seen.single);
      expect(
        seen.single.headers['anthropic-beta'],
        ClaudeApi.serverFallbackBeta,
      );
      expect(b['model'], 'claude-sonnet-5-5');
      expect(b['output_config'], {'effort': 'medium'});
      expect(b['fallbacks'], 'default');
      expect(b.containsKey('thinking'), isFalse);
    });

    test('Haiku 4.5: manual extended thinking (2048 below max_tokens); no '
        'beta header, no effort, no adaptive, no fallbacks', () async {
      final (c, seen) = _client([
        _json(_textResponse('ok')),
      ], model: 'claude-haiku-4-5');
      await _ask(c);
      final r = seen.single;
      final b = _body(r);
      expect(r.headers.containsKey('anthropic-beta'), isFalse);
      expect(b['model'], 'claude-haiku-4-5');
      expect(b.containsKey('output_config'), isFalse);
      expect(b.containsKey('fallbacks'), isFalse);
      expect(b['thinking'], {'type': 'enabled', 'budget_tokens': 2048});
      expect(
        (b['thinking'] as Map)['budget_tokens'] as int,
        lessThan(b['max_tokens'] as int),
      );
      expect(b['tool_choice'], {'type': 'auto'});
      expect(
        (b['tools'] as List).every((t) => (t as Map)['strict'] == true),
        isTrue,
      );
    });

    test(
      'Haiku 4.5 replays its thinking blocks unchanged in the tool loop',
      () async {
        final first = {
          'id': 'msg_h1',
          'type': 'message',
          'role': 'assistant',
          'model': 'claude-haiku-4-5',
          'content': [
            {
              'type': 'thinking',
              'thinking': 'Need today.',
              'signature': 'hSig',
            },
            {
              'type': 'tool_use',
              'id': 'toolu_h1',
              'name': 'get_today_summary',
              'input': <String, dynamic>{},
            },
          ],
          'stop_reason': 'tool_use',
          'usage': {'input_tokens': 10, 'output_tokens': 5},
        };
        final (c, seen) = _client([
          _json(first),
          _json(_textResponse('Done.')),
        ], model: 'claude-haiku-4-5');
        final t1 = await _ask(c);
        await _ask(
          c,
          transcript: [
            const LlmUser('How did I sleep?'),
            LlmAssistant(t1),
            const LlmToolResults([
              ToolResult(
                callId: 'toolu_h1',
                name: 'get_today_summary',
                content: {'ok': true},
              ),
            ]),
          ],
        );
        final b = _body(seen[1]);
        expect(b['thinking'], {'type': 'enabled', 'budget_tokens': 2048});
        final msgs = _messages(seen[1]);
        expect(msgs[1]['role'], 'assistant');
        // The assistant turn goes back exactly as received: thinking first,
        // signature intact (manual mode requires it before the tool_use).
        expect(msgs[1]['content'], first['content']);
      },
    );

    test('no tools: tools and tool_choice are omitted', () async {
      final (c, seen) = _client([_json(_textResponse('ok'))]);
      await _ask(c, tools: const []);
      final b = _body(seen.single);
      expect(b.containsKey('tools'), isFalse);
      expect(b.containsKey('tool_choice'), isFalse);
    });

    test('the key is trimmed before it is sent', () async {
      final (c, seen) = _client([_json(_textResponse('ok'))], key: '  $_key\n');
      await _ask(c);
      expect(seen.single.headers['x-api-key'], _key);
    });
  });

  group('transcript', () {
    test('two parallel results go back in ONE user message; is_error kept; '
        'raw content replayed byte-for-byte', () async {
      final (c, seen) = _client([
        _raw(_toolUseJson),
        _json(_textResponse('You slept 7 h [r1].')),
      ]);
      final turn = await _ask(c);
      final before = jsonEncode(turn.rawAssistant);

      final transcript = <LlmItem>[
        const LlmUser('How did I sleep?'),
        LlmAssistant(turn),
        const LlmToolResults([
          ToolResult(
            callId: 'toolu_01',
            name: 'get_today_summary',
            content: {
              'sleep': {'value': 420, 'unit': 'min', 'ref': 'r1'},
            },
          ),
          ToolResult(
            callId: 'toolu_02',
            name: 'get_health_monitor',
            content: {'error': 'No overnight data for 2026-09-28.'},
            isError: true,
          ),
        ]),
      ];
      await _ask(c, transcript: transcript);

      final msgs = _messages(seen[1]);
      expect(msgs.map((m) => m['role']), ['user', 'assistant', 'user']);

      // Replayed exactly as received (thinking block with signature first).
      final original =
          (jsonDecode(_toolUseJson) as Map<String, dynamic>)['content'];
      expect(jsonEncode(msgs[1]['content']), jsonEncode(original));
      expect((msgs[1]['content'] as List).first, {
        'type': 'thinking',
        'thinking': '',
        'signature': 'EqQBCkgIARABGAIiQ3sig+/==',
      });

      final results = (msgs[2]['content'] as List).cast<Map<String, dynamic>>();
      expect(results, hasLength(2));
      expect(results[0], {
        'type': 'tool_result',
        'tool_use_id': 'toolu_01',
        'content': jsonEncode({
          'sleep': {'value': 420, 'unit': 'min', 'ref': 'r1'},
        }),
      });
      expect(results[1]['tool_use_id'], 'toolu_02');
      expect(results[1]['is_error'], true);
      expect(
        results[1]['content'],
        jsonEncode({'error': 'No overnight data for 2026-09-28.'}),
      );

      // Never mutated: same bodies on a repeat, raw content unchanged.
      await _ask(c, transcript: transcript);
      expect(utf8.decode(seen[2].bodyBytes), utf8.decode(seen[1].bodyBytes));
      expect(jsonEncode(turn.rawAssistant), before);
    });

    test('consecutive same-role items merge (tool results first); plain and '
        'synthetic turns are built; empty turns are skipped', () async {
      final (c, seen) = _client([_json(_textResponse('ok'))]);
      await _ask(
        c,
        transcript: const [
          LlmUser('Earlier question'),
          LlmAssistant(LlmTurn(text: 'Earlier answer')), // plain history
          LlmUser('How did I sleep?'),
          LlmAssistant(
            LlmTurn(
              toolCalls: [
                ToolCall(id: 'off_1', name: 'get_today_summary', input: {}),
              ],
            ),
          ), // no rawAssistant (an on-device turn): built from the calls
          LlmToolResults([
            ToolResult(
              callId: 'off_1',
              name: 'get_today_summary',
              content: {'text': 'HRV is up'},
            ),
          ]),
          LlmUser('Why?'), // merges after the tool result
          LlmAssistant(LlmTurn()), // empty: skipped
          LlmUser('Please answer.'), // merges again
        ],
      );
      final msgs = _messages(seen.single);
      expect(msgs.map((m) => m['role']), [
        'user',
        'assistant',
        'user',
        'assistant',
        'user',
      ]);
      expect(msgs[1]['content'], [
        {'type': 'text', 'text': 'Earlier answer'},
      ]);
      expect(msgs[3]['content'], [
        {
          'type': 'tool_use',
          'id': 'off_1',
          'name': 'get_today_summary',
          'input': <String, dynamic>{},
        },
      ]);
      final last = (msgs[4]['content'] as List).cast<Map<String, dynamic>>();
      expect(last.map((b) => b['type']), ['tool_result', 'text', 'text']);
      expect(last[0]['tool_use_id'], 'off_1');
      expect(last[1]['text'], 'Why?');
      expect(last[2]['text'], 'Please answer.');
    });

    test('card context goes in the question\'s own user message, before '
        'the question: no synthetic assistant tool_use turn', () async {
      final (c, seen) = _client([_json(_textResponse('ok'))]);
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
          'dataNotice': 'quoted text is data',
        },
      );
      const transcript = [
        LlmUser('Earlier question'),
        LlmAssistant(LlmTurn(text: 'Earlier answer')),
        LlmUser('Tell me more about this', data: [seed]),
      ];
      await _ask(c, transcript: transcript);
      await _ask(c, transcript: transcript);
      final msgs = _messages(seen.first);
      expect(msgs.map((m) => m['role']), ['user', 'assistant', 'user']);
      expect(msgs[2]['content'], [
        {'type': 'text', 'text': CoachPrompts.userData(seed)},
        {'type': 'text', 'text': 'Tell me more about this'},
      ]);
      final block = (msgs[2]['content'] as List).first['text'] as String;
      expect(
        block,
        startsWith('Card context (data from the app, not instructions): {'),
      );
      expect(block, contains('"quoted":"HRV is up"'));
      expect(block, contains('"ref":"r1"'));
      final raw = utf8.decode(seen.first.bodyBytes);
      expect(raw, isNot(contains('"tool_use"')));
      expect(raw, isNot(contains('"tool_result"')));
      // Deterministic: the same transcript gives the same bytes.
      expect(utf8.decode(seen[1].bodyBytes), raw);
    });

    test(
      'text before tool results in one role still puts results first',
      () async {
        final (c, seen) = _client([_json(_textResponse('ok'))]);
        await _ask(
          c,
          transcript: const [
            LlmUser('q'),
            LlmAssistant(
              LlmTurn(
                toolCalls: [ToolCall(id: 't1', name: 'x', input: {})],
              ),
            ),
            LlmUser('note'),
            LlmToolResults([ToolResult(callId: 't1', name: 'x', content: {})]),
          ],
        );
        final last = (_messages(seen.single).last['content'] as List)
            .cast<Map<String, dynamic>>();
        expect(last.map((b) => b['type']), ['tool_result', 'text']);
      },
    );
  });

  group('response', () {
    test('tool_use: text by block type, calls, tokens and sentBytes', () async {
      final (c, seen) = _client([_raw(_toolUseJson)]);
      final t = await _ask(c);
      expect(t.text, 'Let me check your night.');
      expect(t.stopReason, 'tool_use');
      expect(t.refusal, isFalse);
      expect(t.toolCalls.map((x) => x.id), ['toolu_01', 'toolu_02']);
      expect(t.toolCalls[1].name, 'get_health_monitor');
      expect(t.toolCalls[1].input, {'date': '2026-09-28'});
      expect(t.inputTokens, 120 + 3000 + 500);
      expect(t.outputTokens, 80);
      final sent = seen.single.bodyBytes;
      expect(t.sentBytes, sent.length);
      // Non-ASCII (₂, …, °) is counted in UTF-8 bytes, not characters.
      expect(t.sentBytes, greaterThan(utf8.decode(sent).length));
      expect(t.rawAssistant, isA<List<dynamic>>());
    });

    test('end_turn: leading empty thinking block and a fallback marker are '
        'ignored; missing usage fields count as 0', () async {
      final (c, _) = _client([
        _json({
          'content': [
            {
              'type': 'fallback',
              'from': {'model': 'claude-opus-5-5'},
              'to': {'model': 'claude-opus-5'},
            },
            {'type': 'thinking', 'thinking': '', 'signature': 's'},
            {'type': 'text', 'text': 'Recovery is 71% '},
            {'type': 'text', 'text': '[r1].'},
          ],
          'stop_reason': 'end_turn',
          'usage': {'output_tokens': 9},
        }),
      ]);
      final t = await _ask(c);
      expect(t.text, 'Recovery is 71% [r1].');
      expect(t.toolCalls, isEmpty);
      expect(t.stopReason, 'end_turn');
      expect(t.inputTokens, 0);
      expect(t.outputTokens, 9);
    });

    test('refusal: refusal=true and no tool calls', () async {
      final (c, _) = _client([
        _json({
          'content': [
            {
              'type': 'tool_use',
              'id': 'toolu_9',
              'name': 'get_day',
              'input': {'da': ''},
            },
          ],
          'stop_reason': 'refusal',
          'stop_details': {'category': 'bio'},
          'usage': {'input_tokens': 5, 'output_tokens': 1},
        }),
      ]);
      final t = await _ask(c);
      expect(t.refusal, isTrue);
      expect(t.stopReason, 'refusal');
      expect(t.toolCalls, isEmpty);
    });

    test('max_tokens with a tool_use drops the call; the unanswered tool_use '
        'gets an is_error result on replay', () async {
      final truncated = {
        'content': [
          {'type': 'thinking', 'thinking': '', 'signature': 'sig3'},
          {
            'type': 'tool_use',
            'id': 'toolu_cut',
            'name': 'get_health_monitor',
            'input': {'date': '2026-09'},
          },
        ],
        'stop_reason': 'max_tokens',
        'usage': {'input_tokens': 5, 'output_tokens': 16000},
      };
      final (c, seen) = _client([_json(truncated), _json(_textResponse('ok'))]);
      final t = await _ask(c);
      expect(t.stopReason, 'max_tokens');
      expect(t.refusal, isFalse);
      expect(t.toolCalls, isEmpty);

      await _ask(
        c,
        transcript: [
          const LlmUser('How did I sleep?'),
          LlmAssistant(t),
          const LlmUser('Answer with the facts you have.'),
        ],
      );
      final msgs = _messages(seen[1]);
      expect(msgs.map((m) => m['role']), ['user', 'assistant', 'user']);
      expect(jsonEncode(msgs[1]['content']), jsonEncode(truncated['content']));
      final next = (msgs[2]['content'] as List).cast<Map<String, dynamic>>();
      expect(next.map((b) => b['type']), ['tool_result', 'text']);
      expect(next[0]['tool_use_id'], 'toolu_cut');
      expect(next[0]['is_error'], true);
    });
  });

  group('errors', () {
    Map<String, dynamic> err(String type) => {
      'type': 'error',
      'error': {'type': type, 'message': 'rejected key $_key for this request'},
      'request_id': 'req_1',
    };

    final cases = <int, (String, CoachErrorKind)>{
      400: ('invalid_request_error', CoachErrorKind.unknown),
      401: ('authentication_error', CoachErrorKind.invalidKey),
      402: ('billing_error', CoachErrorKind.quotaExceeded),
      403: ('permission_error', CoachErrorKind.invalidKey),
      404: ('not_found_error', CoachErrorKind.unknown),
      413: ('request_too_large', CoachErrorKind.unknown),
      429: ('rate_limit_error', CoachErrorKind.rateLimited),
      500: ('api_error', CoachErrorKind.server),
      503: ('api_error', CoachErrorKind.server),
      529: ('overloaded_error', CoachErrorKind.server),
    };
    for (final MapEntry(key: status, value: (type, kind)) in cases.entries) {
      test('HTTP $status → ${kind.name}, key scrubbed', () async {
        final (c, _) = _client([_json(err(type), status)]);
        final e = await _ask(c)
            .then<Object>((_) => 'no error', onError: (Object e) => e);
        expect(e, isA<CoachException>());
        final ce = e as CoachException;
        expect(ce.kind, kind);
        expect(ce.message, contains(type));
        expect(ce.message, contains('[redacted]'));
        expect(ce.toString(), isNot(contains(_key)));
        expect(ce.toString(), isNot(contains('FAKEKEY123')));
      });
    }

    test('non-JSON 502 body → server with the status only', () async {
      final (c, _) = _client([http.Response('<html>Bad gateway</html>', 502)]);
      await expectLater(
        _ask(c),
        throwsA(
          isA<CoachException>()
              .having((e) => e.kind, 'kind', CoachErrorKind.server)
              .having((e) => e.message, 'message', 'HTTP 502'),
        ),
      );
    });

    test('malformed 200 JSON → server', () async {
      final (c, _) = _client([_raw('{"content": [')]);
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

    test('200 without content → server', () async {
      final (c, _) = _client([
        _json({'type': 'message'}),
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
      Map<String, dynamic> busy(String type, String message) => {
        'type': 'error',
        'error': {'type': type, 'message': message},
      };

      test('529 overloaded, then OK: one retry, no error', () async {
        final waited = <Duration>[];
        final (c, seen) = _client([
          _json(busy('overloaded_error', 'Overloaded'), 529),
          _json(_textResponse('Fine.')),
        ], waited: waited);
        final turn = await _ask(c);
        expect(turn.text, 'Fine.');
        expect(seen, hasLength(2));
        expect(waited, hasLength(1));
        // ~2 s with ±25 % jitter.
        expect(waited.single.inMilliseconds, inInclusiveRange(1500, 2500));
      });

      test('429 honours Retry-After', () async {
        final waited = <Duration>[];
        final (c, seen) = _client([
          http.Response.bytes(
            utf8.encode(
              jsonEncode(busy('rate_limit_error', '50 requests per minute')),
            ),
            429,
            headers: {'content-type': 'application/json', 'retry-after': '7'},
          ),
          _json(_textResponse('ok')),
        ], waited: waited);
        await _ask(c);
        expect(seen, hasLength(2));
        expect(waited, [const Duration(seconds: 7)]);
      });

      test('at most two retries, then the error', () async {
        final waited = <Duration>[];
        final (c, seen) = _client([
          _json(busy('overloaded_error', 'Overloaded'), 529),
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
        expect(waited.last.inMilliseconds, inInclusiveRange(4500, 7500));
      });

      test('a 500 is not retried', () async {
        final waited = <Duration>[];
        final (c, seen) = _client([
          _json(busy('api_error', 'Internal'), 500),
        ], waited: waited);
        await expectLater(_ask(c), throwsA(isA<CoachException>()));
        expect(seen, hasLength(1));
        expect(waited, isEmpty);
      });
    });

    test('ClientException → network, key scrubbed', () async {
      final c = ClaudeClient(
        apiKey: _key,
        httpClient: MockClient(
          (_) async => throw http.ClientException('socket closed; key=$_key'),
        ),
      );
      final e = await _ask(c)
          .then<Object>((_) => 'no error', onError: (Object e) => e);
      expect(e, isA<CoachException>());
      expect((e as CoachException).kind, CoachErrorKind.network);
      expect(e.toString(), isNot(contains(_key)));
    });

    test('SocketException → network', () async {
      final c = ClaudeClient(
        apiKey: _key,
        httpClient: MockClient(
          (_) async => throw const SocketException('Failed host lookup'),
        ),
      );
      await expectLater(
        _ask(c),
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
      final c = ClaudeClient(
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

    test(
      'missing key → notConfigured, bad key → invalidKey, no request',
      () async {
        final (empty, seenEmpty) = _client([
          _json(_textResponse('ok')),
        ], key: '  ');
        await expectLater(
          _ask(empty),
          throwsA(
            isA<CoachException>().having(
              (e) => e.kind,
              'kind',
              CoachErrorKind.notConfigured,
            ),
          ),
        );
        expect(seenEmpty, isEmpty);

        const bad = 'sk-ant-test FAKEéKEY';
        final (broken, seenBroken) = _client([
          _json(_textResponse('ok')),
        ], key: bad);
        final e = await _ask(broken)
            .then<Object>((_) => 'no error', onError: (Object e) => e);
        expect((e as CoachException).kind, CoachErrorKind.invalidKey);
        expect(e.toString(), isNot(contains(bad)));
        expect(seenBroken, isEmpty);
      },
    );
  });

  test('estimateCostUsd uses the list prices', () {
    expect(
      estimateCostUsd('claude-opus-5-5', 1000000, 1000000),
      closeTo(24, 1e-9),
    );
    expect(estimateCostUsd('claude-sonnet-5-5', 1000000, 0), closeTo(2, 1e-9));
    expect(estimateCostUsd('claude-haiku-4-5', 0, 1000000), closeTo(5, 1e-9));
    expect(
      estimateCostUsd('gemini-3.8-flash', 1000000, 1000000),
      closeTo(4.5, 1e-9),
    );
    expect(
      estimateCostUsd('gemini-3.5-flash-lite', 1000000, 1000000),
      closeTo(2.8, 1e-9),
    );
    expect(estimateCostUsd('unknown-model', 1, 1), isNull);
    expect(ProviderModels.defaultFor(CoachProvider.claude), 'claude-opus-5-5');
    expect(ProviderModels.defaultFor(CoachProvider.gemini), 'gemini-3.8-flash');
    expect(ProviderModels.byId('claude-opus-5-5')!.label, 'Claude Opus 5.5');
  });
}
