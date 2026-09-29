// HTTP client for the Google Health API v4 (Enhanced mode).
//
// Ported from Pulse `Core/API/HealthAPIClient.swift` (Luraxx/pulse @
// 1f8975c, Apache-2.0, see third_party/pulse/NOTICE):
//   * one global throttle: ≤ 5 requests/s per user (Google: 300/min/user);
//     a 429 pushes the window back for every caller (Retry-After, else
//     exponential 2,4,8… capped at 60 s);
//   * 401 → one token refresh, then retry;
//   * each data type tries several read variants (reconcile → list with a
//     range filter → list with only a start filter) and remembers the one
//     that works, because the filter grammar per type is not fully
//     documented (UNVERIFIED, see ghapi_mapping.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../domain/day_key.dart';
import '../../../domain/models.dart';
import '../../common/source_exception.dart';
import '../../common/time.dart';
import 'ghapi_mapping.dart';
import 'json_extract.dart';

class GhHttpException implements Exception {
  GhHttpException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'HTTP $status: $body';
}

enum _Variant { reconcileRange, listRange, listFrom }

class GoogleHealthClient {
  GoogleHealthClient({
    required this.accessToken,
    required this.refreshToken,
    http.Client? client,
    this.minInterval = const Duration(milliseconds: 200),
    this.requestTimeout = const Duration(seconds: 20),
    this.clock = systemClock,
    Future<void> Function(Duration)? sleep,
  }) : _http = client ?? http.Client(),
       _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final Future<String> Function() accessToken;
  final Future<String> Function() refreshToken;
  final http.Client _http;
  final Duration minInterval;
  final Duration requestTimeout;
  final Clock clock;
  final Future<void> Function(Duration) _sleep;

  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, _Variant> _working = {};

  /// Requests issued (tests / diagnostics).
  int requests = 0;

  Future<void> _throttle() async {
    final now = clock();
    final slot = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = slot.add(minInterval);
    final wait = slot.difference(now);
    if (wait > Duration.zero) await _sleep(wait);
  }

  static Duration retryDelay(int attempt, String? retryAfter) {
    final s = double.tryParse(retryAfter ?? '');
    if (s != null && s > 0) {
      return Duration(milliseconds: (math.min(s, 60) * 1000).round());
    }
    return Duration(seconds: math.min(math.pow(2, attempt + 1).toInt(), 60));
  }

  Future<Map<String, dynamic>> getJson(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('${GhMap.baseUrl}$path')
        .replace(queryParameters: query.isEmpty ? null : query);
    var attempt = 0;
    var refreshed = false;
    while (true) {
      await _throttle();
      final token = await accessToken().timeout(requestTimeout);
      requests++;
      final res = await _http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(requestTimeout);
      final code = res.statusCode;
      if (code >= 200 && code < 300) {
        final j = jsonDecode(res.body);
        if (j is Map<String, dynamic>) return j;
        throw GhHttpException(code, 'not a JSON object');
      }
      if (code == 401 && !refreshed) {
        refreshed = true;
        await refreshToken().timeout(requestTimeout);
        continue;
      }
      if (code == 429 && attempt < 5) {
        final d = retryDelay(attempt++, res.headers['retry-after']);
        final until = clock().add(d);
        if (until.isAfter(_nextSlot)) _nextSlot = until;
        continue;
      }
      if ((code == 500 || code == 502 || code == 503 || code == 504) &&
          attempt < 3) {
        await _sleep(retryDelay(attempt++, res.headers['retry-after']));
        continue;
      }
      final body = res.body.length > 300
          ? res.body.substring(0, 300)
          : res.body;
      throw GhHttpException(code, body);
    }
  }

  static String _rfc3339(DateTime t) {
    final u = t.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
        'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
  }

  /// Every raw data point of [t] in [from, to) (paginated).
  Future<List<Map<String, dynamic>>> dataPoints(
    GhType t,
    DateTime from,
    DateTime to,
  ) async {
    final field = '${JsonExtract.snakeCase(t.payloadKey)}.${t.filterField}';
    final (a, b) = t.timeFilter == GhTimeFilter.civilDate
        ? (DayKey.of(from), DayKey.of(to))
        : (_rfc3339(from), _rfc3339(to));
    final range = '$field >= "$a" AND $field <= "$b"';
    final fromOnly = '$field >= "$a"';
    final variants = _working.containsKey(t.type)
        ? [_working[t.type]!]
        : _Variant.values;
    Object? last;
    for (final v in variants) {
      try {
        final pts = await _paginate(
          t.type,
          v == _Variant.listFrom ? fromOnly : range,
          reconcile: v == _Variant.reconcileRange,
        );
        _working[t.type] = v;
        return pts;
      } on GhHttpException catch (e) {
        if (e.status == 400 || e.status == 404) {
          last = e;
          continue;
        }
        rethrow;
      }
    }
    throw SourceException(
      SourceKind.googleHealthApi,
      t.type,
      'No read variant worked: $last',
    );
  }

  Future<List<Map<String, dynamic>>> _paginate(
    String type,
    String filter, {
    required bool reconcile,
  }) async {
    final out = <Map<String, dynamic>>[];
    String? page;
    var pages = 0;
    do {
      final j = await getJson(
        '/users/me/dataTypes/$type/dataPoints${reconcile ? ':reconcile' : ''}',
        {'filter': filter, 'pageSize': '1000', 'pageToken': ?page},
      );
      Object? pts;
      for (final k in GhMap.envelopeKeys) {
        pts ??= j[k];
      }
      if (pts is List) {
        out.addAll(pts.whereType<Map<String, dynamic>>());
      }
      page = null;
      for (final k in GhMap.nextPageKeys) {
        final v = j[k];
        if (v is String && v.isNotEmpty) page = v;
      }
      pages++;
    } while (page != null && pages < 60);
    if (page != null) {
      throw StateError(
        'Google Health response exceeded pagination limit; stored data retained',
      );
    }
    return out;
  }

  void close() => _http.close();
}
