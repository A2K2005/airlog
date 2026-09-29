// Health Connect sync: first-run backfill → changes token → incremental
// upserts + deletions; expired / unusable token → full re-read.
//
// Per-type isolation (pattern from Pulse `Core/Sync/SyncEngine.swift`,
// Luraxx/pulse @ 1f8975c, Apache-2.0, see third_party/pulse/NOTICE): every type is read in its own try/catch and writes
// its own SyncLogEntry; one failing type never blocks the rest.

import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../common/source_exception.dart';
import '../common/time.dart';
import '../db/raw_rows.dart';
import '../db/stores.dart';
import '../services/health_connect/hc_mapper.dart';
import '../services/health_connect/hc_types.dart';

const String kHcTokenScope = 'changes';
const String kHcTokenTypesKey = 'hc.token_types';
const String kHcMetadataPendingKey = 'hc.metadata_pending';

class HcSync {
  HcSync({
    required this.hc,
    required this.raw,
    required this.app,
    required this.clock,
    this.contextEnabled = false,
    this.backfillDays = 30,
    this.historyBackfillDays = 90,
  });

  final HealthConnectSource hc;
  final RawStore raw;
  final AppStore app;
  final Clock clock;
  final bool contextEnabled;
  final int backfillDays;
  final int historyBackfillDays;

  final List<SyncLogEntry> _log = [];
  bool _readFailed = false;
  bool _background = false;

  void _note(String type, String status, {int records = 0, String? message}) =>
      _log.add(
        SyncLogEntry(
          at: clock(),
          source: SourceKind.healthConnect,
          dataType: type,
          status: status,
          records: records,
          message: message,
        ),
      );

  /// Runs one sync. Returns the dirty day keys; appends log lines to [log].
  Future<Set<String>> run(
    List<SyncLogEntry> log, {
    bool background = false,
  }) async {
    _log.clear();
    _readFailed = false;
    _background = background;
    final dirty = <String>{};
    try {
      final avail = await hc.availability();
      if (avail != HcAvailability.available) {
        _note(
          'health_connect',
          'skipped',
          message: 'Health Connect ${avail.name}',
        );
        return dirty;
      }
      final perms = await hc.permissionState();
      if (background && !perms.backgroundGranted) {
        _note(
          'health_connect',
          'denied',
          message: 'Background reads not granted; syncing when the app opens',
        );
        return dirty;
      }
      final granted = <HcType>[];
      for (final t in HcType.stored) {
        if (!perms.granted.contains(t.key)) {
          _note(t.key, 'denied', message: 'Permission not granted');
          continue;
        }
        if (!await hc.supports(t)) {
          _note(
            t.key,
            'skipped',
            message: 'Not supported by this Health Connect version',
          );
          continue;
        }
        granted.add(t);
      }
      if (granted.isEmpty) return dirty;

      final typeNames =
          (granted.where((t) => t != HcType.vo2max).map((t) => t.key).toList()
                ..sort())
              .join(',');
      final tokenTypes =
          '$typeNames|history=${perms.historyGranted}|context=$contextEnabled';
      final saved = await app.token(SourceKind.healthConnect, kHcTokenScope);
      final savedTypes = await app.getSetting(kHcTokenTypesKey);
      final metadataPending =
          !background && await app.getSetting(kHcMetadataPendingKey) != null;
      if (saved == null || savedTypes != tokenTypes || metadataPending) {
        dirty.addAll(
          await _full(
            granted,
            perms.historyGranted,
            tokenTypes,
            reason: saved == null ? 'first sync' : 'permissions changed',
          ),
        );
      } else {
        dirty.addAll(
          await _incremental(granted, saved, perms.historyGranted, tokenTypes),
        );
      }
    } catch (e) {
      _note('health_connect', 'error', message: '$e');
    } finally {
      log.addAll(_log);
    }
    return dirty;
  }

  List<HcType> _tokenTypes(List<HcType> granted) => [
    for (final t in granted)
      if (t != HcType.vo2max) t,
  ];

  Future<Set<String>> _full(
    List<HcType> granted,
    bool history,
    String tokenTypes, {
    required String reason,
  }) async {
    final dirty = <String>{};
    final now = clock();
    // Token first, so changes made while we read are not lost.
    final token = await hc.changesToken(_tokenTypes(granted));
    final days = history ? historyBackfillDays : backfillDays;
    final from = DayKey.start(DayKey.add(DayKey.of(now), -(days - 1)));
    for (final type in granted) {
      dirty.addAll(await _readWindow(type, from, now, label: reason));
    }
    if (!_readFailed && token != null && token.isNotEmpty) {
      await app.setToken(SourceKind.healthConnect, kHcTokenScope, token);
      await app.setSetting(kHcTokenTypesKey, tokenTypes);
      if (!_background) await app.setSetting(kHcMetadataPendingKey, null);
    } else {
      await app.setToken(SourceKind.healthConnect, kHcTokenScope, null);
      _note(
        'changes_token',
        'error',
        message: 'Could not create a changes token; next sync re-reads',
      );
    }
    return dirty;
  }

  /// Reads [type] over [from, to) in chunks and replaces the stored window.
  Future<Set<String>> _readWindow(
    HcType type,
    DateTime from,
    DateTime to, {
    String? label,
  }) async {
    final dirty = <String>{};
    final chunk = type == HcType.heartRate
        ? const Duration(days: 1)
        : const Duration(days: 7);
    var kept = 0, foreign = 0, future = 0, failed = 0;
    Object? lastErr;
    var a = from;
    while (a.isBefore(to)) {
      var b = type == HcType.heartRate
          ? DayKey.end(DayKey.of(a))
          : a.add(chunk);
      if (b.isAfter(to)) b = to;
      try {
        final recs = await hc.read(type, a, b);
        final m = mapHcRecords(
          recs,
          now: clock(),
          ingestedAt: clock(),
          contextEnabled: contextEnabled,
        );
        foreign += m.foreign;
        future += m.future;
        // SpO2 stores two rows (night mean + minimum) per sample.
        kept += type == HcType.spo2
            ? m.rows.scalars.where((s) => s.scalar == ScalarKind.spo2Avg).length
            : m.rows.length;
        dirty.addAll(await _replace(type, a, b, m.rows));
      } catch (e) {
        failed++;
        _readFailed = true;
        lastErr = e is SourceException ? e.cause : e;
      }
      a = b;
    }
    final parts = <String>[
      ?label,
      if (foreign > 0) 'skipped $foreign (context sources off)',
      if (future > 0) 'dropped $future future-dated',
      if (failed > 0) '$failed chunk(s) failed: $lastErr',
    ];
    _note(
      type.key,
      failed > 0 ? 'error' : (kept == 0 ? 'empty' : 'ok'),
      records: kept,
      message: parts.isEmpty ? null : parts.join('; '),
    );
    return dirty;
  }

  Future<Set<String>> _replace(
    HcType type,
    DateTime a,
    DateTime b,
    RawRows rows,
  ) async {
    final dirty = <String>{};
    Future<void> rep(SourceKind s, RawKind k, {ScalarKind? scalar}) async {
      final part = RawRows(
        hr: [
          for (final r in rows.hr)
            if (r.source == s) r,
        ],
        hrv: [
          for (final r in rows.hrv)
            if (r.source == s) r,
        ],
        sleep: [
          for (final r in rows.sleep)
            if (r.source == s) r,
        ],
        workouts: [
          for (final r in rows.workouts)
            if (r.source == s) r,
        ],
        scalars: [
          for (final r in rows.scalars)
            if (r.source == s && (scalar == null || r.scalar == scalar)) r,
        ],
      );
      dirty.addAll(await raw.replaceWindow(s, k, a, b, part, scalar: scalar));
    }

    switch (type) {
      case HcType.heartRate:
        await rep(SourceKind.healthConnect, RawKind.hr);
      case HcType.hrv:
        await rep(SourceKind.healthConnect, RawKind.hrv);
      case HcType.sleep:
        await rep(SourceKind.healthConnect, RawKind.sleep);
      case HcType.exercise:
        await rep(SourceKind.healthConnect, RawKind.workout);
      case HcType.restingHr:
        await rep(
          SourceKind.healthConnect,
          RawKind.scalar,
          scalar: ScalarKind.rhr,
        );
      case HcType.respiratoryRate:
        await rep(
          SourceKind.healthConnect,
          RawKind.scalar,
          scalar: ScalarKind.resp,
        );
      case HcType.skinTemp:
        await rep(
          SourceKind.healthConnect,
          RawKind.scalar,
          scalar: ScalarKind.skinTempDelta,
        );
      case HcType.vo2max:
        await rep(
          SourceKind.healthConnect,
          RawKind.scalar,
          scalar: ScalarKind.vo2max,
        );
      case HcType.spo2:
        // Each sample is stored twice (night mean + night minimum).
        await rep(
          SourceKind.healthConnect,
          RawKind.scalar,
          scalar: ScalarKind.spo2Avg,
        );
        await rep(
          SourceKind.healthConnect,
          RawKind.scalar,
          scalar: ScalarKind.spo2Min,
        );
      case HcType.steps:
        await rep(
          SourceKind.healthConnect,
          RawKind.scalar,
          scalar: ScalarKind.steps,
        );
      case HcType.weight:
        // Context-only type (never scored): stored as context rows.
        if (contextEnabled) {
          await rep(
            SourceKind.context,
            RawKind.scalar,
            scalar: ScalarKind.weight,
          );
        }
      case HcType.distance:
      case HcType.totalCalories:
        break;
    }
    return dirty;
  }

  Future<Set<String>> _incremental(
    List<HcType> granted,
    String token,
    bool history,
    String tokenTypes,
  ) async {
    final dirty = <String>{};
    final latestUpserts = <String, List<HcRecord>>{};
    final deleted = <String>{};
    var next = token;
    for (var page = 0; page < 100; page++) {
      final resp = await hc.changes(next);
      if (resp == null || resp.expired) {
        await app.setToken(SourceKind.healthConnect, kHcTokenScope, null);
        _note(
          'changes_token',
          resp == null ? 'error' : 'skipped',
          message: resp == null
              ? 'Changes call failed; doing a full re-read'
              : 'Changes token expired; doing a full re-read',
        );
        return _full(granted, history, tokenTypes, reason: 'token expired');
      }
      final removed = resp.deletedIds.toSet();
      if (resp.upserts.any((r) => removed.contains(r.id))) {
        // The plugin splits a page into two lists and loses event ordering.
        // An authoritative window read resolves this ambiguous page safely.
        return _full(granted, history, tokenTypes, reason: 'ambiguous changes');
      }
      for (final id in resp.upserts.map((r) => r.id).toSet()) {
        deleted.remove(id);
        latestUpserts[id] = resp.upserts.where((r) => r.id == id).toList();
      }
      for (final id in removed) {
        latestUpserts.remove(id);
        deleted.add(id);
      }
      next = resp.nextToken;
      if (!resp.hasMore) break;
    }
    final upserts = latestUpserts.values.expand((records) => records).toList();

    // Deletions carry only a record id (no type): delete across every table.
    if (deleted.isNotEmpty) {
      dirty.addAll(await raw.deleteRecords(SourceKind.healthConnect, deleted));
      dirty.addAll(await raw.deleteRecords(SourceKind.context, deleted));
    }

    // Sleep upserts arrive as the session only (no stages): re-read the
    // night with stages and replace that window.
    final sleepWindows = <(DateTime, DateTime)>[];
    final plain = <HcRecord>[];
    for (final u in upserts) {
      if (u.type == HcType.sleep) {
        sleepWindows.add((
          u.start.subtract(const Duration(hours: 12)),
          u.end.add(const Duration(hours: 12)),
        ));
      } else {
        plain.add(u);
      }
    }
    final m = mapHcRecords(
      plain,
      now: clock(),
      ingestedAt: clock(),
      contextEnabled: contextEnabled,
    );
    if (_background && m.rows.all.any((r) => r.device == null)) {
      await app.setSetting(kHcMetadataPendingKey, 'true');
    }
    // An upsert replaces the whole record: drop its old rows first (a
    // shortened HeartRateRecord must not leave stale samples).
    final ids = {for (final r in plain) r.id};
    if (ids.isNotEmpty) {
      dirty.addAll(await raw.deleteRecords(SourceKind.healthConnect, ids));
      dirty.addAll(await raw.deleteRecords(SourceKind.context, ids));
      dirty.addAll(await raw.upsert(m.rows));
    }
    // Old HR corrections cannot be reconstructed from pruned raw samples.
    // The store retains record→day metadata and invalidates those buckets.
    if (granted.contains(HcType.heartRate)) {
      final before = DayKey.of(clock().subtract(kRawHrRetention));
      for (final day in dirty.toList()..sort()) {
        if (day.compareTo(before) >= 0) continue;
        dirty.addAll(
          await _readWindow(
            HcType.heartRate,
            DayKey.start(day),
            DayKey.end(day),
            label: 'historical correction',
          ),
        );
      }
    }
    for (final w in _mergeWindows(sleepWindows)) {
      if (granted.contains(HcType.sleep)) {
        dirty.addAll(
          await _readWindow(HcType.sleep, w.$1, w.$2, label: 'rewritten night'),
        );
      }
    }

    // VO2 max is not covered by the plugin's changes token: re-read 7 days.
    if (granted.contains(HcType.vo2max)) {
      final now = clock();
      dirty.addAll(
        await _readWindow(
          HcType.vo2max,
          DayKey.start(DayKey.add(DayKey.of(now), -6)),
          now,
        ),
      );
    }

    final byType = <String, int>{};
    for (final u in upserts) {
      byType.update(u.type.key, (v) => v + 1, ifAbsent: () => 1);
    }
    _note(
      'changes',
      upserts.isEmpty && deleted.isEmpty ? 'empty' : 'ok',
      records: upserts.length + deleted.length,
      message: [
        ...byType.entries.map((e) => '${e.key} ${e.value}'),
        if (deleted.isNotEmpty) '${deleted.length} deleted',
        if (m.foreign > 0) 'skipped ${m.foreign} (context sources off)',
        if (m.future > 0) 'dropped ${m.future} future-dated',
      ].join(', '),
    );
    if (!_readFailed) {
      await app.setToken(SourceKind.healthConnect, kHcTokenScope, next);
    }
    return dirty;
  }

  static List<(DateTime, DateTime)> _mergeWindows(
    List<(DateTime, DateTime)> ws,
  ) {
    if (ws.isEmpty) return const [];
    final s = [...ws]..sort((a, b) => a.$1.compareTo(b.$1));
    final out = <(DateTime, DateTime)>[s.first];
    for (final w in s.skip(1)) {
      final last = out.last;
      if (!w.$1.isAfter(last.$2)) {
        out[out.length - 1] = (last.$1, w.$2.isAfter(last.$2) ? w.$2 : last.$2);
      } else {
        out.add(w);
      }
    }
    return out;
  }
}
