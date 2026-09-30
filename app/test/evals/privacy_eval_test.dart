// Eval 5 — privacy invariants, checked on the exact bytes the real
// ClaudeClient puts on the wire (package:http MockClient; no network):
//   * general-only mode sends zero user data: only get_methodology is
//     offered, no earlier messages, no card seed, no memories, no dates of
//     data;
//   * Google Health API-sourced values (and scores derived from them) never
//     appear in a cloud payload, and the payload says they were withheld;
//   * the API key is only ever in the x-api-key header: never in a body,
//     the stored chat, the stored settings, or exception text;
//   * SentPayload (the "What was sent" sheet) equals what was sent: its byte
//     count is the sum of the request bodies, its request count and tools
//     match;
//   * memory is never sent when memory is off or in general-only mode.

import 'dart:convert';

import 'package:airlog/data/coach/claude_client.dart';
import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/data/coach/coach_repository_impl.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'coach_harness.dart';
import 'eval_support.dart';
import 'fixtures.dart';

const kKey = 'sk-ant-test-PRIVACYKEY-0123456789';

/// A Claude-shaped reply.
String reply({List<Map<String, dynamic>> tools = const [], String? text}) =>
    jsonEncode({
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'model': 'claude-opus-5-5',
      'content': [
        {'type': 'thinking', 'thinking': '', 'signature': 'c2ln'},
        if (text != null) {'type': 'text', 'text': text},
        for (final (i, t) in tools.indexed)
          {'type': 'tool_use', 'id': 'toolu_$i', 'name': t['name'], 'input': t['input']},
      ],
      'stop_reason': tools.isEmpty ? 'end_turn' : 'tool_use',
      'usage': {'input_tokens': 1200, 'output_tokens': 80},
    });

/// Captures every request; [answer] scripts the reply to each body.
class Wire {
  Wire(this.answer);
  final http.Response Function(Map<String, dynamic> body, int n) answer;
  final List<http.Request> requests = [];

  late final http.Client client = MockClient((r) async {
    requests.add(r);
    return answer(jsonDecode(r.body) as Map<String, dynamic>, requests.length - 1);
  });

  List<String> get bodies => [for (final r in requests) r.body];
  int get bytes => requests.fold(0, (a, r) => a + utf8.encode(r.body).length);
}

/// The decoded text of every tool_result block in [bodies].
List<String> toolResultTexts(List<String> bodies) => [
  for (final b in bodies)
    for (final msg in (jsonDecode(b)['messages'] as List))
      if (msg['content'] is List)
        for (final c in msg['content'] as List)
          if (c is Map && c['type'] == 'tool_result') '${c['content']}',
];

bool hasToolResults(Map<String, dynamic> body) =>
    (body['messages'] as List).any((m) =>
        m['content'] is List &&
        (m['content'] as List).any((b) => b is Map && b['type'] == 'tool_result'));

CoachModule cloud(
  HealthRepository h,
  Wire w, {
  CoachSettings? settings,
}) =>
    CoachModule.inMemory(
      h,
      clock: () => kEvalNow,
      settings: settings ?? kCloudSettings,
      keys: const {CoachProvider.claude: kKey},
      clients: (_, key, model) =>
          ClaudeClient(apiKey: key, model: model, httpClient: w.client),
    );

void main() {
  final rows = <EvalRow>[];
  final failures = <String>[];
  void check(String name, bool ok, [String? why]) {
    rows.add(EvalRow(name, ok ? 1 : 0, 1, 1.0));
    if (!ok) failures.add('$name${why == null ? '' : ': $why'}');
  }

  tearDownAll(() => report('privacy', rows, failures: failures));

  test('general-only mode sends zero user data', () async {
    final h = await fixtureRepo((_) {});
    final w = Wire((body, n) => http.Response(
          hasToolResults(body)
              ? reply(text: 'Recovery compares last night with your own baseline.')
              : reply(tools: [
                  {'name': 'get_methodology', 'input': {'topic': 'recovery'}},
                ]),
          200,
        ));
    final m = cloud(h, w,
        settings: kCloudSettings.copyWith(mode: CoachMode.generalOnly));
    await m.repository.addMemory('Training for a half marathon on 15 Nov');
    final today = DayKey.of(kEvalNow);
    final first = await m.service.ask(
      'How is Recovery calculated?',
      context: AskContext(
        screen: 'sleep',
        date: today,
        insightId: 'sleep:$today',
        seedText: 'You slept 6h 43m',
        seedRefs: [
          SourceRef(id: 'r1', label: 'Asleep', value: 403, unit: 'min', date: today),
        ],
      ),
    );
    await m.service.ask('And what about HRV?',
        conversationId: first.conversationId);
    final tools = {
      for (final b in w.bodies)
        for (final t in (jsonDecode(b)['tools'] as List? ?? const []))
          t['name'] as String,
    };
    check('general-only: only get_methodology offered',
        tools.length == 1 && tools.single == 'get_methodology', '$tools');
    final all = w.bodies.join('\n');
    check('general-only: no card seed sent',
        !all.contains('get_insight_card') && !all.contains('6h 43m'));
    check('general-only: no memory sent', !all.contains('half marathon'));
    check('general-only: no earlier messages replayed',
        !w.bodies.last.contains('How is Recovery calculated?'));
    check('general-only: no data dates in the prompt',
        all.contains('Latest day with data: none') &&
            !all.contains('Asked from'));
    final results = toolResultTexts(w.bodies);
    check('general-only: tool results are methodology only',
        results.every((r) => r.contains('"topic"')), '$results');
  });

  test('Google Health API values never reach a cloud payload', () async {
    final h = await fixtureRepo(
      (rs) => fromGoogleHealth(rs, {Metric.hrv, Metric.spo2}),
    );
    final today = DayKey.of(kEvalNow);
    final hrv = [
      for (final b in await h.range(DayKey.add(today, -29), today))
        if (b.record.hrvRmssd != null) b.record.hrvRmssd!.round(),
    ];
    final w = Wire((body, n) => http.Response(
          hasToolResults(body)
              ? reply(text: 'Your HRV values stay on the phone.')
              : reply(tools: [
                  {
                    'name': 'get_range',
                    'input': {
                      'metric': 'hrv',
                      'from': DayKey.add(today, -29),
                      'to': today,
                    },
                  },
                  {'name': 'get_day', 'input': {'date': today}},
                  {'name': 'get_health_monitor', 'input': {'date': today}},
                  {'name': 'get_training_load', 'input': {'date': today}},
                ]),
          200,
        ));
    final m = cloud(h, w);
    await m.service.ask('Is my HRV trending?');
    final all = toolResultTexts(w.bodies).join('\n');
    final leaked = [
      for (final v in hrv.toSet())
        if (all.contains('"value":$v,"unit":"ms"')) v,
    ];
    check('GHAPI: no HRV value in any payload', leaked.isEmpty, 'leaked $leaked');
    check('GHAPI: no Recovery derived from it',
        !RegExp(r'"recovery":\{"score"').hasMatch(all));
    check('GHAPI: the payload says values were withheld',
        all.contains('withheld') && all.contains('Google Health API'));
    check('GHAPI: no strain target (a fixed factor × Recovery)',
        !all.contains('"target":{') && !all.contains('"strainTarget":{"value"'));
    check('GHAPI: no Health Monitor alert or reason built from it',
        !RegExp(r'"alert":(true|false)').hasMatch(all) &&
            !all.contains('"reason":'));
  });

  test('on-device answers are never replayed to a cloud model', () async {
    final h = await fixtureRepo((rs) => fromGoogleHealth(rs, {Metric.hrv}));
    final w = Wire((body, n) =>
        http.Response(reply(text: 'I can look that up for you.'), 200));
    final m = cloud(h, w, settings: const CoachSettings());
    final first = await m.service.ask('What was my HRV today?');
    expect(first.text, contains('ms'), reason: 'on-device shows it locally');
    await m.repository.saveSettings(kCloudSettings);
    await m.service.ask('And how did I sleep?',
        conversationId: first.conversationId);
    final all = w.bodies.join('\n');
    check('history: the on-device answer never reaches the cloud',
        w.requests.isNotEmpty &&
            !all.contains('What was my HRV today?') &&
            !all.contains(first.text.split('[').first.trim()),
        all.length > 300 ? all.substring(0, 300) : all);
  });

  test('the API key is only in the header', () async {
    final h = await fixtureRepo((_) {});
    final ok = Wire((body, n) => http.Response(
          hasToolResults(body)
              ? reply(text: 'Your recovery today is in the data.')
              : reply(tools: [
                  {'name': 'get_today_summary', 'input': <String, dynamic>{}},
                ]),
          200,
        ));
    final m = cloud(h, ok);
    final msg = await m.service.ask('What drove my recovery today?');
    check('key: x-api-key header on every request',
        ok.requests.every((r) => r.headers['x-api-key'] == kKey));
    check('key: never in a request body or URL',
        ok.requests.every((r) => !r.body.contains(kKey) &&
            !r.url.toString().contains(kKey)));
    check('key: never in the stored chat',
        !jsonEncode(msg.toJson()).contains(kKey) &&
            !(await m.repository.messages(msg.conversationId))
                .any((x) => jsonEncode(x.toJson()).contains(kKey)));
    final settingsJson = await m.repository.store
        .getValue(CoachRepositoryImpl.settingsKey);
    check('key: never in stored settings',
        !(settingsJson ?? '').contains(kKey));

    // A provider error that echoes the key back.
    final bad = Wire((body, n) => http.Response(
          jsonEncode({
            'type': 'error',
            'error': {
              'type': 'authentication_error',
              'message': 'invalid x-api-key: $kKey',
            },
          }),
          401,
        ));
    final m2 = cloud(h, bad);
    final err = await m2.service.ask('What drove my recovery today?');
    // Model fallback (PRODUCT_PLAN §7): a rejected key is account-wide, so
    // the question is answered on this phone and the reason is recorded;
    // the key still appears nowhere.
    check('key: never in error text',
        err.fallbackReason == CoachErrorKind.invalidKey.name &&
            err.answeredBy == ChatMessage.onDevice &&
            !err.text.contains(kKey) &&
            !jsonEncode(err.toJson()).contains(kKey),
        err.text);
  });

  test('SentPayload is exactly what was sent', () async {
    final h = await fixtureRepo((_) {});
    final w = Wire((body, n) => http.Response(
          hasToolResults(body)
              ? reply(text: 'Here is your week.')
              : reply(tools: [
                  {'name': 'get_today_summary', 'input': <String, dynamic>{}},
                  {
                    'name': 'get_workouts',
                    'input': {
                      'from': DayKey.add(DayKey.of(kEvalNow), -6),
                      'to': DayKey.of(kEvalNow),
                    },
                  },
                ]),
          200,
        ));
    final m = cloud(h, w);
    final msg = await m.service.ask('How was my week?');
    final s = msg.sent!;
    check('sent: byte count equals the request bodies',
        s.bytes == w.bytes && s.approxChars == w.bytes, '${s.bytes} vs ${w.bytes}');
    check('sent: request count matches', s.requests == w.requests.length);
    check('sent: tools called match the wire',
        s.toolsCalled.toSet().containsAll({'get_today_summary', 'get_workouts'}) &&
            s.toolsCalled.length == 2,
        '${s.toolsCalled}');
  });

  test('memory is never sent when memory is off', () async {
    final h = await fixtureRepo((_) {});
    final w = Wire((body, n) => http.Response(
          hasToolResults(body)
              ? reply(text: 'Noted.')
              : reply(tools: [
                  {'name': 'get_memories', 'input': <String, dynamic>{}},
                ]),
          200,
        ));
    final m = cloud(h, w);
    await m.repository.addMemory('Training for a half marathon on 15 Nov');
    await m.repository.setMemoryEnabled(false);
    await m.service.ask('What should I focus on?');
    final all = w.bodies.join('\n');
    check('memory off: memory tools not offered',
        !jsonEncode(jsonDecode(w.bodies.first)['tools']).contains('get_memories'));
    check('memory off: memory text never sent', !all.contains('half marathon'));
  });

  test('all privacy invariants hold', () {
    for (final r in rows) {
      expect(r.ok, isTrue, reason: r.line);
    }
  });
}
