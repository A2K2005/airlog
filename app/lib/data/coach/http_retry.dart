// Retry for the cloud coach's raw-HTTP clients (claude_client.dart,
// gemini_client.dart): a transient "busy" answer is tried again, at most
// twice, before it becomes an error the user sees.
//
//   * Retried: 429 (per-minute rate limit), 503 (Gemini "high demand"),
//     529 (Anthropic "overloaded"). Nothing else: a 400/401/402/500 will not
//     change on a second try, and a network error or timeout is the
//     caller's to report.
//   * Never retried: a 429 whose quota is exhausted for the DAY (Gemini's
//     google.rpc.QuotaFailure "…PerDay…" quota ids, or a message saying
//     "per day" / "daily"). Waiting seconds cannot help; [isDailyQuota]
//     lets the clients report it as quotaExceeded instead.
//   * The wait: the server's own hint when it gives one (a `Retry-After`
//     header in seconds or as an HTTP date, or Gemini's
//     google.rpc.RetryInfo `retryDelay`, e.g. "12s"), else about 2 s, then
//     6 s, with ±25 % jitter so parallel clients do not retry in lock-step.
//   * The whole request (tries and waits) stays inside [RetryPolicy.budget],
//     below CoachServiceImpl.requestTimeout (150 s): a wait that would end
//     past the budget is not taken, and the last answer is returned as is.
//
// Pure: no printing or logging; the sleep and the randomness are injected so
// tests never wait.

import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math' show Random;

import 'package:http/http.dart' as http;

class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 2,
    this.backoff = const [Duration(seconds: 2), Duration(seconds: 6)],
    this.jitter = 0.25,
    this.budget = const Duration(seconds: 140),
  });

  /// Retries after the first try (so at most `maxRetries + 1` requests).
  final int maxRetries;

  /// Waits when the server gives no hint; the last one repeats.
  final List<Duration> backoff;

  /// ± fraction applied to [backoff] waits.
  final double jitter;

  /// Tries plus waits never start past this (the service times the whole
  /// request out at 150 s).
  final Duration budget;

  /// No retries (tests that count requests exactly).
  static const none = RetryPolicy(maxRetries: 0);
}

/// Sends [send] and retries a transient failure per [policy]. Returns the
/// last response (the caller maps a non-2xx to its error).
Future<http.Response> sendWithRetry(
  Future<http.Response> Function() send, {
  RetryPolicy policy = const RetryPolicy(),
  Future<void> Function(Duration)? sleep,
  Random? random,
  DateTime Function()? now,
}) async {
  final wait = sleep ?? (d) => Future<void>.delayed(d);
  final rnd = random ?? Random();
  final clock = now ?? DateTime.now;
  final watch = Stopwatch()..start();
  var res = await send();
  for (var i = 0; i < policy.maxRetries && isRetryable(res); i++) {
    final d = retryDelay(res, i, policy, rnd, clock());
    if (watch.elapsed + d > policy.budget) break;
    await wait(d);
    res = await send();
  }
  return res;
}

/// 429 (unless the day's quota is gone), 503 and 529.
bool isRetryable(http.Response res) => switch (res.statusCode) {
  503 || 529 => true,
  429 => !isDailyQuota(res),
  _ => false,
};

/// A 429 whose quota is exhausted until tomorrow, not for the minute.
bool isDailyQuota(http.Response res) {
  if (res.statusCode != 429) return false;
  final e = _error(res);
  if (e == null) return false;
  final details = e['details'];
  if (details is List) {
    for (final d in details) {
      if (d is! Map) continue;
      final violations = d['violations'];
      if (violations is! List) continue;
      for (final v in violations) {
        if (v is! Map) continue;
        final id = '${v['quotaId'] ?? ''} ${v['quotaMetric'] ?? ''}'
            .toLowerCase();
        if (id.contains('perday') || id.contains('per_day')) return true;
      }
    }
  }
  final m = '${e['message'] ?? ''}'.toLowerCase();
  return m.contains('per day') || m.contains('daily') || m.contains('perday');
}

/// How long to wait before retry number [attempt] (0-based).
Duration retryDelay(
  http.Response res,
  int attempt,
  RetryPolicy policy,
  Random random,
  DateTime now,
) {
  final hint = serverDelay(res, now);
  if (hint != null) return hint;
  if (policy.backoff.isEmpty) return Duration.zero;
  final base = policy.backoff[attempt.clamp(0, policy.backoff.length - 1)];
  final f = 1 + policy.jitter * (2 * random.nextDouble() - 1);
  return Duration(milliseconds: (base.inMilliseconds * f).round());
}

/// The server's own wait: `Retry-After` (seconds or an HTTP date), else
/// Gemini's google.rpc.RetryInfo `retryDelay` ("12s", "1.5s"). Null = none.
Duration? serverDelay(http.Response res, DateTime now) {
  final h = res.headers['retry-after']?.trim();
  if (h != null && h.isNotEmpty) {
    final s = double.tryParse(h);
    if (s != null && s >= 0) {
      return Duration(milliseconds: (s * 1000).round());
    }
    try {
      final at = HttpDate.parse(h);
      final d = at.difference(now.toUtc());
      return d.isNegative ? Duration.zero : d;
    } catch (_) {}
  }
  final e = _error(res);
  final details = e?['details'];
  if (details is List) {
    for (final d in details) {
      if (d is! Map) continue;
      final r = d['retryDelay'];
      if (r is String) {
        final m = RegExp(r'^\s*(\d+(?:\.\d+)?)s\s*$').firstMatch(r);
        if (m != null) {
          return Duration(
            milliseconds: (double.parse(m.group(1)!) * 1000).round(),
          );
        }
      }
    }
  }
  return null;
}

Map<dynamic, dynamic>? _error(http.Response res) {
  try {
    final j = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    final e = j is Map ? j['error'] : null;
    return e is Map ? e : null;
  } on FormatException {
    return null;
  }
}
