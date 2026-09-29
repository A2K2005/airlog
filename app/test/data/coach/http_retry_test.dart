// http_retry.dart: which answers are retried, how long to wait, and the
// time budget. A fake sender and sleep: nothing waits for real.

import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math' show Random;

import 'package:airlog/data/coach/http_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

http.Response _res(
  int status, {
  Object? body,
  Map<String, String> headers = const {},
}) => http.Response.bytes(
  utf8.encode(body == null ? '' : jsonEncode(body)),
  status,
  headers: headers,
);

Map<String, dynamic> _quota(String quotaId, {String? retryDelay}) => {
  'error': {
    'code': 429,
    'status': 'RESOURCE_EXHAUSTED',
    'message': 'You exceeded your current quota.',
    'details': [
      {
        '@type': 'type.googleapis.com/google.rpc.QuotaFailure',
        'violations': [
          {'quotaId': quotaId},
        ],
      },
      if (retryDelay != null)
        {
          '@type': 'type.googleapis.com/google.rpc.RetryInfo',
          'retryDelay': retryDelay,
        },
    ],
  },
};

void main() {
  final now = DateTime.utc(2026, 9, 29, 12);
  const policy = RetryPolicy();

  group('isRetryable', () {
    test('429 / 503 / 529 yes; others no', () {
      for (final s in [429, 503, 529]) {
        expect(isRetryable(_res(s)), isTrue, reason: '$s');
      }
      for (final s in [200, 400, 401, 402, 403, 404, 500, 502]) {
        expect(isRetryable(_res(s)), isFalse, reason: '$s');
      }
    });

    test('a 429 for the day is not retried; per minute is', () {
      final day = _res(
        429,
        body: _quota('GenerateRequestsPerDayPerProjectPerModel-FreeTier'),
      );
      final minute = _res(
        429,
        body: _quota('GenerateRequestsPerMinutePerProjectPerModel-FreeTier'),
      );
      expect(isDailyQuota(day), isTrue);
      expect(isRetryable(day), isFalse);
      expect(isDailyQuota(minute), isFalse);
      expect(isRetryable(minute), isTrue);
      // A message saying so counts too.
      final msg = _res(
        429,
        body: {
          'error': {'message': 'Daily request limit reached for this key.'},
        },
      );
      expect(isDailyQuota(msg), isTrue);
      // A 503 is never a daily quota.
      expect(isDailyQuota(_res(503, body: _quota('PerDay'))), isFalse);
    });
  });

  group('retryDelay', () {
    test('Retry-After in seconds, or as an HTTP date', () {
      final secs = _res(429, headers: {'retry-after': '9'});
      expect(
        retryDelay(secs, 0, policy, Random(1), now),
        const Duration(seconds: 9),
      );
      final date = _res(
        503,
        headers: {
          'retry-after': HttpDate.format(now.add(const Duration(seconds: 30))),
        },
      );
      expect(
        retryDelay(date, 0, policy, Random(1), now),
        const Duration(seconds: 30),
      );
    });

    test('Gemini RetryInfo.retryDelay, fractional seconds too', () {
      final r = _res(429, body: _quota('PerMinute', retryDelay: '12.5s'));
      expect(
        retryDelay(r, 0, policy, Random(1), now),
        const Duration(milliseconds: 12500),
      );
    });

    test('no hint: ~2 s then ~6 s, jittered within ±25 %', () {
      final rnd = Random(7);
      for (var i = 0; i < 50; i++) {
        final a = retryDelay(_res(503), 0, policy, rnd, now).inMilliseconds;
        final b = retryDelay(_res(503), 1, policy, rnd, now).inMilliseconds;
        expect(a, inInclusiveRange(1500, 2500));
        expect(b, inInclusiveRange(4500, 7500));
      }
    });
  });

  group('sendWithRetry', () {
    test('retries until OK, at most twice', () async {
      final waits = <Duration>[];
      var calls = 0;
      final ok = await sendWithRetry(
        () async => ++calls < 3 ? _res(503) : _res(200),
        sleep: (d) async => waits.add(d),
      );
      expect(ok.statusCode, 200);
      expect(calls, 3);
      expect(waits, hasLength(2));

      calls = 0;
      final busy = await sendWithRetry(() async {
        calls++;
        return _res(529);
      }, sleep: (_) async {});
      expect(busy.statusCode, 529);
      expect(calls, 3);
    });

    test('a wait that would pass the budget is not taken', () async {
      var calls = 0;
      final r = await sendWithRetry(() async {
        calls++;
        return _res(429, headers: {'retry-after': '200'});
      }, sleep: (_) async => fail('must not wait'));
      expect(r.statusCode, 429);
      expect(calls, 1);
    });

    test('RetryPolicy.none sends once', () async {
      var calls = 0;
      await sendWithRetry(
        () async {
          calls++;
          return _res(503);
        },
        policy: RetryPolicy.none,
        sleep: (_) async => fail('must not wait'),
      );
      expect(calls, 1);
    });
  });
}
