// Google Health API → raw rows (SourceKind.googleHealthApi).
//
// Parsing ideas from Pulse `Core/API/HealthAPIClient.swift` +
// `Core/Sync/SyncEngine.swift` (Luraxx/pulse @ 1f8975c, Apache-2.0, see
// third_party/pulse/NOTICE). Every field name comes from ghapi_mapping.dart.

import '../../../domain/day_key.dart';
import '../../../domain/models.dart';
import '../../common/time.dart';
import '../../db/raw_rows.dart';
import 'ghapi_mapping.dart';
import 'google_auth.dart';
import 'google_health_client.dart';
import 'json_extract.dart';

const String kGhOrigin = 'health.googleapis.com';

/// Rows plus how many raw points arrived (rawCount > 0 with no rows means a
/// field name in ghapi_mapping.dart is wrong).
class GhFetch {
  GhFetch(this.rows, this.rawCount);
  final RawRows rows;
  final int rawCount;
}

abstract class GoogleHealthSource {
  bool get configured;
  Future<bool> get signedIn;
  Future<bool> signIn();
  Future<void> signOut();

  Future<GhFetch> sleep(DateTime from, DateTime to);
  Future<GhFetch> hrvDaily(DateTime from, DateTime to);
  Future<GhFetch> hrvSamples(DateTime from, DateTime to);
  Future<GhFetch> spo2(DateTime from, DateTime to);
  Future<GhFetch> respiratoryRate(DateTime from, DateTime to);
  Future<GhFetch> skinTemp(DateTime from, DateTime to);
  Future<GhFetch> restingHr(DateTime from, DateTime to);
  Future<GhFetch> vo2max(DateTime from, DateTime to);
  Future<GhFetch> heartRate(DateTime from, DateTime to);
}

/// Pure JSON → rows parsing (tested without HTTP).
class GhParser {
  GhParser(this.ingestedAt);
  final DateTime ingestedAt;

  static Map<String, dynamic> payload(Map<String, dynamic> p, String key) {
    final v = p[key];
    return v is Map<String, dynamic> ? v : p;
  }

  String _id(Map<String, dynamic> p, String fallback) {
    final n = p['name'];
    return n is String && n.isNotEmpty ? n : fallback;
  }

  RawScalarRow _scalar(ScalarKind k, String id, String day, double v) {
    final t = DayKey.start(day).add(const Duration(hours: 6));
    return RawScalarRow(
      source: SourceKind.googleHealthApi,
      sourceRecordId: id,
      recordId: id,
      originPackage: kGhOrigin,
      ingestedAt: ingestedAt,
      scalar: k,
      start: t,
      value: v,
      day: day,
    );
  }

  String? _day(Map<String, dynamic> pl) {
    final d = JsonExtract.firstString(pl, GhMap.dateKeys);
    if (d != null && d.length >= 10) return d.substring(0, 10);
    final t = JsonExtract.firstDate(pl, const ['physicalTime', 'startTime']);
    return t == null ? null : DayKey.of(t);
  }

  List<RawScalarRow> daily(
    List<Map<String, dynamic>> pts,
    GhType t,
    ScalarKind k, {
    List<String>? keys,
  }) {
    final out = <RawScalarRow>[];
    for (final p in pts) {
      final pl = payload(p, t.payloadKey);
      final v = JsonExtract.firstNumber(pl, keys ?? t.valueKeys);
      final day = _day(pl);
      if (v == null || day == null) continue;
      out.add(_scalar(k, '${k.code}:$day', day, v));
    }
    return out;
  }

  List<(DateTime, double)> samples(List<Map<String, dynamic>> pts, GhType t) {
    final out = <(DateTime, double)>[];
    for (final p in pts) {
      final pl = payload(p, t.payloadKey);
      final v = JsonExtract.firstNumber(pl, t.valueKeys);
      final at = JsonExtract.firstDate(pl, t.timeKeys);
      if (v == null || at == null) continue;
      out.add((at, v));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  static SleepStage? stage(String? s) => switch ((s ?? '').toUpperCase()) {
    'AWAKE' || 'RESTLESS' || 'WAKE' => SleepStage.awake,
    'LIGHT' => SleepStage.light,
    'DEEP' => SleepStage.deep,
    'REM' => SleepStage.rem,
    'ASLEEP' => SleepStage.unknown,
    _ => null,
  };

  RawSleepRow? sleep(Map<String, dynamic> p) {
    final pl = payload(p, GhMap.sleep.payloadKey);
    Map<String, dynamic> interval = const {};
    for (final k in GhMap.sleepIntervalKeys) {
      final v = pl[k];
      if (v is Map<String, dynamic>) {
        interval = v;
        break;
      }
    }
    final start =
        JsonExtract.date(interval['startTime']) ??
        JsonExtract.firstDate(pl, const ['startTime']);
    final end =
        JsonExtract.date(interval['endTime']) ??
        JsonExtract.firstDate(pl, const ['endTime']);
    if (start == null || end == null || !end.isAfter(start)) return null;
    final stages = <StageSpan>[];
    final raw = pl[GhMap.sleepStagesKey];
    if (raw is List) {
      for (final s in raw.whereType<Map<String, dynamic>>()) {
        final a = JsonExtract.date(s['startTime']);
        final b = JsonExtract.date(s['endTime']);
        final st = stage(s[GhMap.sleepStageTypeKey] as String?);
        if (a == null || b == null || st == null || !b.isAfter(a)) continue;
        stages.add(StageSpan(st, a, b));
      }
      stages.sort((x, y) => x.start.compareTo(y.start));
    }
    Object? summary;
    for (final k in GhMap.sleepSummaryKeys) {
      summary ??= pl[k];
    }
    final asleep = JsonExtract.firstNumber(summary, GhMap.minutesAsleepKeys);
    final awake = JsonExtract.firstNumber(summary, GhMap.minutesAwakeKeys);
    bool? isMain;
    for (final k in GhMap.isMainSleepKeys) {
      final v = pl[k];
      if (v is bool) isMain = v;
    }
    final id = _id(p, 'sleep-${start.millisecondsSinceEpoch}');
    return RawSleepRow(
      source: SourceKind.googleHealthApi,
      sourceRecordId: id,
      recordId: id,
      originPackage: kGhOrigin,
      ingestedAt: ingestedAt,
      start: start,
      end: end,
      isMain: isMain,
      minutesAsleep: asleep,
      minutesAwake: awake,
      stages: stages,
    );
  }
}

class GoogleHealthApiSource implements GoogleHealthSource {
  GoogleHealthApiSource(
    this.auth, {
    GoogleHealthClient? client,
    Clock clock = systemClock,
  }) : _clock = clock,
       _client =
           client ??
           GoogleHealthClient(
             accessToken: auth.validAccessToken,
             refreshToken: auth.refresh,
             clock: clock,
           );

  final GoogleAuth auth;
  final GoogleHealthClient _client;
  final Clock _clock;

  GhParser get _p => GhParser(_clock());

  @override
  bool get configured => auth.config.configured;
  @override
  Future<bool> get signedIn => auth.signedIn;
  @override
  Future<bool> signIn() => auth.signIn();
  @override
  Future<void> signOut() => auth.signOut();

  @override
  Future<GhFetch> sleep(DateTime from, DateTime to) async {
    final pts = await _client.dataPoints(GhMap.sleep, from, to);
    return GhFetch(
      RawRows(sleep: [for (final p in pts) ?_p.sleep(p)]),
      pts.length,
    );
  }

  @override
  Future<GhFetch> hrvDaily(DateTime from, DateTime to) async {
    final pts = await _client.dataPoints(GhMap.hrvDaily, from, to);
    final p = _p;
    return GhFetch(
      RawRows(
        scalars: [
          ...p.daily(pts, GhMap.hrvDaily, ScalarKind.hrvDaily),
          ...p.daily(
            pts,
            GhMap.hrvDaily,
            ScalarKind.hrvDeepSleep,
            keys: GhMap.hrvDeepSleepKeys,
          ),
        ],
      ),
      pts.length,
    );
  }

  @override
  Future<GhFetch> hrvSamples(DateTime from, DateTime to) async {
    final pts = await _client.dataPoints(GhMap.hrvSamples, from, to);
    final now = _clock();
    return GhFetch(
      RawRows(
        hrv: [
          for (final (t, v) in _p.samples(pts, GhMap.hrvSamples))
            RawHrvRow(
              source: SourceKind.googleHealthApi,
              sourceRecordId: 'hrv:${t.millisecondsSinceEpoch}',
              recordId: 'hrv:${t.millisecondsSinceEpoch}',
              originPackage: kGhOrigin,
              ingestedAt: now,
              t: t,
              rmssd: v,
            ),
        ],
      ),
      pts.length,
    );
  }

  @override
  Future<GhFetch> spo2(DateTime from, DateTime to) async {
    // Intraday samples → nightly avg/min; daily aggregate as fallback.
    final pts = await _client.dataPoints(GhMap.spo2Samples, from, to);
    final p = _p;
    final byNight = <String, List<double>>{};
    for (final (t, v) in p.samples(pts, GhMap.spo2Samples)) {
      final h = t.hour;
      if (h >= 10 && h < 20) continue; // overnight only
      byNight.putIfAbsent(nightKey(t), () => []).add(v);
    }
    final rows = RawRows();
    for (final e in byNight.entries) {
      rows.scalars.add(
        p._scalar(
          ScalarKind.spo2Avg,
          'spo2_avg:${e.key}',
          e.key,
          mean(e.value),
        ),
      );
      rows.scalars.add(
        p._scalar(
          ScalarKind.spo2Min,
          'spo2_min:${e.key}',
          e.key,
          e.value.reduce((a, b) => a < b ? a : b),
        ),
      );
    }
    var raw = pts.length;
    if (byNight.isEmpty) {
      final d = await _client.dataPoints(GhMap.spo2Daily, from, to);
      raw += d.length;
      rows.scalars
        ..addAll(p.daily(d, GhMap.spo2Daily, ScalarKind.spo2Avg))
        ..addAll(
          p.daily(
            d,
            GhMap.spo2Daily,
            ScalarKind.spo2Min,
            keys: GhMap.spo2MinKeys,
          ),
        );
    }
    return GhFetch(rows, raw);
  }

  @override
  Future<GhFetch> respiratoryRate(DateTime from, DateTime to) async {
    final pts = await _client.dataPoints(GhMap.respDaily, from, to);
    return GhFetch(
      RawRows(scalars: _p.daily(pts, GhMap.respDaily, ScalarKind.resp)),
      pts.length,
    );
  }

  @override
  Future<GhFetch> skinTemp(DateTime from, DateTime to) async {
    final pts = await _client.dataPoints(GhMap.skinTempDaily, from, to);
    final p = _p;
    final rows = RawRows();
    for (final pt in pts) {
      final pl = GhParser.payload(pt, GhMap.skinTempDaily.payloadKey);
      final nightly = JsonExtract.firstNumber(
        pl,
        GhMap.skinTempDaily.valueKeys,
      );
      final base = JsonExtract.firstNumber(pl, GhMap.skinTempBaselineKeys);
      final day = p._day(pl);
      if (nightly == null || base == null || day == null) continue;
      rows.scalars.add(
        p._scalar(ScalarKind.skinTempDelta, 'skin:$day', day, nightly - base),
      );
    }
    return GhFetch(rows, pts.length);
  }

  @override
  Future<GhFetch> restingHr(DateTime from, DateTime to) async {
    final pts = await _client.dataPoints(GhMap.rhrDaily, from, to);
    return GhFetch(
      RawRows(scalars: _p.daily(pts, GhMap.rhrDaily, ScalarKind.rhr)),
      pts.length,
    );
  }

  @override
  Future<GhFetch> vo2max(DateTime from, DateTime to) async {
    final pts = await _client.dataPoints(GhMap.vo2Daily, from, to);
    return GhFetch(
      RawRows(scalars: _p.daily(pts, GhMap.vo2Daily, ScalarKind.vo2max)),
      pts.length,
    );
  }

  @override
  Future<GhFetch> heartRate(DateTime from, DateTime to) async {
    final pts = await _client.dataPoints(GhMap.heartRate, from, to);
    final now = _clock();
    return GhFetch(
      RawRows(
        hr: [
          for (final (t, v) in _p.samples(pts, GhMap.heartRate))
            RawHrRow(
              source: SourceKind.googleHealthApi,
              sourceRecordId: 'hr:${t.millisecondsSinceEpoch}',
              recordId: 'hr:${DayKey.of(t)}',
              originPackage: kGhOrigin,
              ingestedAt: now,
              t: t,
              bpm: v,
            ),
        ],
      ),
      pts.length,
    );
  }
}
