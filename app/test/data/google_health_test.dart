// Google Health API: tolerant parsing (field names are UNVERIFIED — these
// fixtures use the names from the official REST reference where it has them
// and Pulse's guesses elsewhere), client throttling/retries, and sync
// isolation. No network.

import 'dart:convert';

import 'package:airlog/data/db/memory_stores.dart';
import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/services/google_health/ghapi_mapping.dart';
import 'package:airlog/data/services/google_health/google_auth.dart';
import 'package:airlog/data/services/google_health/google_health_client.dart';
import 'package:airlog/data/services/google_health/google_health_source.dart';
import 'package:airlog/data/services/google_health/json_extract.dart';
import 'package:airlog/data/sync/ghapi_sync.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final now = DateTime(2026, 9, 28, 12);

void main() {
  group('config', () {
    test('no client id → not configured', () {
      expect(const GoogleOAuthConfig(clientId: '').configured, isFalse);
    });
    test('redirect = reversed client id scheme', () {
      const c = GoogleOAuthConfig(
        clientId: '123-abc.apps.googleusercontent.com',
      );
      expect(c.configured, isTrue);
      expect(
        c.redirectUrl,
        'com.googleusercontent.apps.123-abc:/oauthredirect',
      );
    });
  });

  group('parsing', () {
    final p = GhParser(now);

    test('daily HRV: average + deep-sleep RMSSD with civil date', () {
      final pts = [
        {
          'name':
              'users/me/dataTypes/daily-heart-rate-variability/dataPoints/1',
          'dailyHeartRateVariability': {
            'date': {'year': 2026, 'month': 9, 'day': 27},
            'averageHeartRateVariabilityMilliseconds': 44.5,
            'deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds': 58.1,
          },
        },
      ];
      final avg = p.daily(pts, GhMap.hrvDaily, ScalarKind.hrvDaily);
      final deep = p.daily(
        pts,
        GhMap.hrvDaily,
        ScalarKind.hrvDeepSleep,
        keys: GhMap.hrvDeepSleepKeys,
      );
      expect(avg.single.value, 44.5);
      expect(avg.single.day, '2026-09-27');
      expect(deep.single.value, 58.1);
      expect(deep.single.source, SourceKind.googleHealthApi);
    });

    test('sleep session with stages and summary', () {
      final s = p.sleep({
        'name': 'sleep/abc',
        'sleep': {
          'interval': {
            'startTime': '2026-09-26T17:30:00Z',
            'endTime': '2026-09-27T01:30:00Z',
          },
          'stages': [
            {
              'startTime': '2026-09-26T17:30:00Z',
              'endTime': '2026-09-26T20:00:00Z',
              'type': 'LIGHT',
            },
            {
              'startTime': '2026-09-26T20:00:00Z',
              'endTime': '2026-09-26T21:00:00Z',
              'type': 'DEEP',
            },
            {
              'startTime': '2026-09-26T21:00:00Z',
              'endTime': '2026-09-27T01:30:00Z',
              'type': 'REM',
            },
          ],
          'summary': {'minutesAsleep': 470, 'minutesAwake': 10},
        },
      })!;
      expect(s.sourceRecordId, 'sleep/abc');
      expect(s.stages.map((x) => x.stage), [
        SleepStage.light,
        SleepStage.deep,
        SleepStage.rem,
      ]);
      expect(s.minutesAsleep, 470);
    });

    test('samples tolerate nesting and alternative keys', () {
      final got = p.samples([
        {
          'heartRate': {
            'sampleTime': {'physicalTime': '2026-09-27T06:00:00Z'},
            'beatsPerMinute': 58,
          },
        },
        {
          'heartRate': {'physicalTime': '2026-09-27T06:01:00Z', 'bpm': '59'},
        },
        {
          'heartRate': {'nothing': true},
        },
      ], GhMap.heartRate);
      expect(got.map((x) => x.$2), [58, 59]);
    });

    test('JsonExtract helpers', () {
      expect(
        JsonExtract.snakeCase('heartRateVariability'),
        'heart_rate_variability',
      );
      expect(
        JsonExtract.civilDate({'year': 2026, 'month': 1, 'day': 2}),
        '2026-01-02',
      );
      expect(
        JsonExtract.firstNumber(
          {
            'a': {
              'b': {'c': 3},
            },
          },
          ['x', 'c'],
        ),
        3,
      );
    });
  });

  group('client', () {
    test(
      'throttles to ≤ 5 requests/s, retries 429 and refreshes on 401',
      () async {
        var calls = 0;
        final waits = <Duration>[];
        var clock = now;
        final mock = MockClient((req) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              'slow down',
              429,
              headers: {'retry-after': '1'},
            );
          }
          if (calls == 2) return http.Response('expired', 401);
          return http.Response(
            jsonEncode({
              'dataPoints': [
                {'x': 1},
              ],
            }),
            200,
          );
        });
        var refreshed = 0;
        final c = GoogleHealthClient(
          accessToken: () async => 'a',
          refreshToken: () async {
            refreshed++;
            return 'b';
          },
          client: mock,
          clock: () => clock,
          sleep: (d) async {
            waits.add(d);
            clock = clock.add(d);
          },
        );
        final pts = await c.dataPoints(
          GhMap.rhrDaily,
          now.subtract(const Duration(days: 3)),
          now,
        );
        expect(pts, hasLength(1));
        expect(calls, 3);
        expect(refreshed, 1);
        expect(
          waits.every(
            (w) => w >= const Duration(milliseconds: 200) || w == Duration.zero,
          ),
          isTrue,
        );
        expect(
          waits.any((w) => w >= const Duration(seconds: 1)),
          isTrue,
          reason: 'Retry-After honoured',
        );
      },
    );

    test(
      '400 on one read variant falls back to the next and remembers it',
      () async {
        final paths = <String>[];
        final mock = MockClient((req) async {
          paths.add(req.url.path);
          if (req.url.path.endsWith(':reconcile')) {
            return http.Response('bad', 400);
          }
          return http.Response(jsonEncode({'dataPoints': []}), 200);
        });
        final c = GoogleHealthClient(
          accessToken: () async => 'a',
          refreshToken: () async => 'a',
          client: mock,
          minInterval: Duration.zero,
        );
        await c.dataPoints(
          GhMap.sleep,
          now.subtract(const Duration(days: 1)),
          now,
        );
        await c.dataPoints(
          GhMap.sleep,
          now.subtract(const Duration(days: 1)),
          now,
        );
        expect(paths.where((x) => x.endsWith(':reconcile')), hasLength(1));
        expect(paths, hasLength(3));
      },
    );
  });

  group('sync', () {
    test(
      'one failing type never blocks the rest; HR only where HC lacks it',
      () async {
        final raw = MemoryRawStore();
        final app = MemoryAppStore();
        final gh = _FakeGh();
        final log = <SyncLogEntry>[];
        await GhSync(gh: gh, raw: raw, app: app, clock: () => now).run(log);
        expect(
          log.firstWhere((e) => e.dataType == 'oxygen-saturation').status,
          'error',
        );
        expect(
          log
              .firstWhere((e) => e.dataType == 'daily-resting-heart-rate')
              .status,
          'ok',
        );
        final rows = await raw.load(DateTime(2000), DateTime(2100));
        expect(
          rows.scalars.where((s) => s.scalar == ScalarKind.rhr),
          isNotEmpty,
        );
        expect(
          gh.hrDays,
          hasLength(7),
          reason: 'no HC HR stored → fallback for 7 days',
        );
        expect(
          await app.getSetting(kGhLastSyncKey),
          isNull,
          reason: 'a failure keeps the window',
        );
      },
    );

    test('not configured → skipped', () async {
      final log = <SyncLogEntry>[];
      await GhSync(
        gh: _FakeGh(configured: false),
        raw: MemoryRawStore(),
        app: MemoryAppStore(),
        clock: () => now,
      ).run(log);
      expect(log.single.status, 'skipped');
    });
  });
}

class _FakeGh implements GoogleHealthSource {
  _FakeGh({this.configured = true});
  @override
  final bool configured;
  final hrDays = <DateTime>[];
  GhFetch empty() => GhFetch(RawRows(), 0);

  @override
  Future<bool> get signedIn async => true;
  @override
  Future<bool> signIn() async => true;
  @override
  Future<void> signOut() async {}
  @override
  Future<GhFetch> sleep(DateTime from, DateTime to) async => empty();
  @override
  Future<GhFetch> hrvDaily(DateTime from, DateTime to) async => empty();
  @override
  Future<GhFetch> hrvSamples(DateTime from, DateTime to) async => empty();
  @override
  Future<GhFetch> spo2(DateTime from, DateTime to) async =>
      throw StateError('HTTP 403');
  @override
  Future<GhFetch> respiratoryRate(DateTime from, DateTime to) async => empty();
  @override
  Future<GhFetch> skinTemp(DateTime from, DateTime to) async => empty();
  @override
  Future<GhFetch> restingHr(DateTime from, DateTime to) async => GhFetch(
    RawRows(
      scalars: [
        RawScalarRow(
          source: SourceKind.googleHealthApi,
          sourceRecordId: 'rhr:2026-09-27',
          ingestedAt: now,
          scalar: ScalarKind.rhr,
          start: DateTime(2026, 9, 27, 6),
          value: 55,
          day: '2026-09-27',
        ),
      ],
    ),
    1,
  );
  @override
  Future<GhFetch> vo2max(DateTime from, DateTime to) async => empty();
  @override
  Future<GhFetch> heartRate(DateTime from, DateTime to) async {
    hrDays.add(from);
    return empty();
  }
}
