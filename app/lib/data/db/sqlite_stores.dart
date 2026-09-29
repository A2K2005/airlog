// sqflite implementations of RawStore and AppStore.
//
// Tests open the same code through sqflite_common_ffi by passing
// `databaseFactoryFfi` to [AirlogDatabase.open].

import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import '../common/time.dart';
import 'hr_buckets.dart';
import 'raw_rows.dart';
import 'schema.dart';
import 'sql_rows.dart';
import 'stores.dart';
import 'write_guard.dart';

class AirlogDatabase {
  AirlogDatabase._();

  static const String fileName = 'airlog.db';

  /// Opens (creating / migrating) the app database.
  ///
  /// [version] and [migrations] exist for migration tests; production code
  /// uses the defaults. [singleInstance] false: a private connection that
  /// can be closed without closing anyone else's (the background worker
  /// shares the app's process; QA-01).
  static Future<Database> open({
    DatabaseFactory? factory,
    String? path,
    int version = kSchemaVersion,
    List<List<String>> migrations = kMigrations,
    bool singleInstance = true,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: singleInstance,
        onConfigure: (db) async {
          // Background (workmanager) isolate may write concurrently.
          await db.rawQuery('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, v) async {
          final b = db.batch();
          for (final s in kSchemaV1) {
            b.execute(s);
          }
          await b.commit(noResult: true);
          for (var from = 1; from < v; from++) {
            for (final s in migrations[from - 1]) {
              await db.execute(s);
            }
          }
        },
        onUpgrade: (db, oldV, newV) async {
          for (var from = oldV; from < newV; from++) {
            for (final s in migrations[from - 1]) {
              await db.execute(s);
            }
          }
        },
      ),
    );
  }
}

/// Runs [ops] in one transaction as one batch (a single platform-channel
/// round trip on Android). Used by the demo seed.
Future<void> runSqlOps(Database db, List<SqlOp> ops) =>
    guardedWrite(db, (tx) async {
      final b = tx.batch();
      for (final op in ops) {
        if (op.sql.startsWith('INSERT')) {
          b.rawInsert(op.sql, op.args);
        } else {
          b.execute(op.sql, op.args);
        }
      }
      await b.commit(noResult: true);
    });

String _in(int n) => List.filled(n, '?').join(',');

Iterable<List<T>> _chunks<T>(List<T> xs, int size) sync* {
  for (var i = 0; i < xs.length; i += size) {
    yield xs.sublist(i, i + size > xs.length ? xs.length : i + size);
  }
}

int _i(Object? v) => (v as num).toInt();
int? _iN(Object? v) => (v as num?)?.toInt();
double _d(Object? v) => (v as num).toDouble();
double? _dN(Object? v) => (v as num?)?.toDouble();
String? _s(Object? v) => v as String?;

class SqliteRawStore implements RawStore {
  SqliteRawStore(this.db, {this.clock = systemClock});

  final Database db;
  final Clock clock;

  String get _retentionDay => DayKey.of(clock().subtract(kRawHrRetention));

  bool _recent(String date) => date.compareTo(_retentionDay) >= 0;

  // ── Row mapping (columns: sql_rows.dart) ─────────────────────────────

  static RawHrRow _hrFrom(Map<String, Object?> m) => RawHrRow(
    source: SourceKind.fromCode(m['source'] as String),
    sourceRecordId: m['source_record_id'] as String,
    recordId: _s(m['record_id']),
    originPackage: _s(m['origin_package']),
    device: _s(m['device']),
    ingestedAt: fromMs(_i(m['ingested_at'])),
    t: fromMs(_i(m['t'])),
    bpm: _d(m['bpm']),
  );

  static RawHrvRow _hrvFrom(Map<String, Object?> m) => RawHrvRow(
    source: SourceKind.fromCode(m['source'] as String),
    sourceRecordId: m['source_record_id'] as String,
    recordId: _s(m['record_id']),
    originPackage: _s(m['origin_package']),
    device: _s(m['device']),
    ingestedAt: fromMs(_i(m['ingested_at'])),
    t: fromMs(_i(m['t'])),
    rmssd: _d(m['rmssd']),
    recordingMethod: _s(m['recording_method']),
  );

  static RawSleepRow _sleepFrom(Map<String, Object?> m, List<StageSpan> st) =>
      RawSleepRow(
        source: SourceKind.fromCode(m['source'] as String),
        sourceRecordId: m['source_record_id'] as String,
        recordId: _s(m['record_id']),
        originPackage: _s(m['origin_package']),
        device: _s(m['device']),
        ingestedAt: fromMs(_i(m['ingested_at'])),
        start: fromMs(_i(m['start'])),
        end: fromMs(_i(m['end'])),
        isMain: m['is_main'] == null ? null : _i(m['is_main']) == 1,
        minutesAsleep: _dN(m['minutes_asleep']),
        minutesAwake: _dN(m['minutes_awake']),
        writtenAt: m['written_at'] == null ? null : fromMs(_i(m['written_at'])),
        stages: st,
      );

  static RawWorkoutRow _workoutFrom(Map<String, Object?> m) => RawWorkoutRow(
    source: SourceKind.fromCode(m['source'] as String),
    sourceRecordId: m['source_record_id'] as String,
    recordId: _s(m['record_id']),
    originPackage: _s(m['origin_package']),
    device: _s(m['device']),
    ingestedAt: fromMs(_i(m['ingested_at'])),
    start: fromMs(_i(m['start'])),
    end: fromMs(_i(m['end'])),
    name: m['name'] as String,
    activityType: _s(m['activity_type']),
    avgHr: _dN(m['avg_hr']),
    calories: _dN(m['calories']),
    distanceM: _dN(m['distance_m']),
  );

  static RawScalarRow _scalarFrom(Map<String, Object?> m) => RawScalarRow(
    source: SourceKind.fromCode(m['source'] as String),
    sourceRecordId: m['source_record_id'] as String,
    recordId: _s(m['record_id']),
    originPackage: _s(m['origin_package']),
    device: _s(m['device']),
    ingestedAt: fromMs(_i(m['ingested_at'])),
    scalar: ScalarKind.fromCode(m['kind'] as String),
    start: fromMs(_i(m['start'])),
    end: fromMs(_i(m['end'])),
    value: _d(m['value']),
    day: _s(m['day']),
  );

  static HrDay _hrDayFrom(Map<String, Object?> m) => HrDay(
    source: SourceKind.fromCode(m['source'] as String),
    origin: _s(m['origin']) ?? '',
    date: m['date'] as String,
    dayStart: fromMs(_i(m['day_start'])),
    tenths: decodeTenths(m['minutes'] as Uint8List),
    device: _s(m['device']),
    samples: _i(m['samples']),
    lastT: m['last_t'] == null ? null : fromMs(_i(m['last_t'])),
  );

  // ── Writes ─────────────────────────────────────────────────────────────

  void _writeRow(Batch b, RawRow r) {
    b.insert(
      SqlRows.rawTables[r.kind]!,
      SqlRows.raw(r),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (r is RawSleepRow) {
      b.delete(
        'raw_sleep_stage',
        where: 'source = ? AND session_id = ?',
        whereArgs: [r.source.code, r.sourceRecordId],
      );
      for (final s in SqlRows.stages(r)) {
        b.insert(
          'raw_sleep_stage',
          s,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  static const _tables = SqlRows.rawTables;

  static const _timeCols = {
    RawKind.hr: ('t', 't'),
    RawKind.hrv: ('t', 't'),
    RawKind.sleep: ('start', '"end"'),
    RawKind.workout: ('start', '"end"'),
    RawKind.scalar: ('start', '"end"'),
  };

  /// Rebuilds / merges hr_day rows (one per source, origin and day) after
  /// raw HR changed.
  Future<void> _refreshHrDays(
    DatabaseExecutor tx,
    Map<HrDayKey, List<RawHrRow>> incoming, {
    DateTime? clearFrom,
    DateTime? clearTo,
  }) async {
    final now = ms(clock());
    for (final e in incoming.entries) {
      final (source, origin, date) = e.key;
      HrDay day;
      if (_recent(date)) {
        final rows = await tx.query(
          'raw_hr',
          where:
              "source = ? AND COALESCE(origin_package, '') = ? AND t >= ? "
              'AND t < ?',
          whereArgs: [
            source.code,
            origin,
            ms(DayKey.start(date)),
            ms(DayKey.end(date)),
          ],
        );
        day = buildHrDay(
          source,
          date,
          rows.map(_hrFrom).toList(),
          origin: origin,
        );
      } else {
        final old = await tx.query(
          'hr_day',
          where: 'source = ? AND origin = ? AND date = ?',
          whereArgs: [source.code, origin, date],
        );
        day = buildHrDay(
          source,
          date,
          e.value,
          origin: origin,
          base: old.isEmpty ? null : _hrDayFrom(old.first),
          clearFrom: clearFrom,
          clearTo: clearTo,
        );
      }
      if (day.minutesWithData == 0) {
        await tx.delete(
          'hr_day',
          where: 'source = ? AND origin = ? AND date = ?',
          whereArgs: [source.code, origin, date],
        );
        continue;
      }
      await tx.insert(
        'hr_day',
        SqlRows.hrDay(day, now),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<Set<String>> _upsertIn(
    Transaction tx,
    RawRows batch, {
    DateTime? hrClearFrom,
    DateTime? hrClearTo,
    Set<HrDayKey>? extraHrDays,
  }) async {
    final days = <String>{};
    final retention = DayKey.start(_retentionDay);
    // Existing interval rows may move (sleep rewritten 2 h later): mark the
    // old days dirty too.
    for (final kind in [RawKind.sleep, RawKind.workout, RawKind.scalar]) {
      final rows = batch.ofKind(kind).toList();
      final bySource = <SourceKind, List<String>>{};
      for (final r in rows) {
        bySource.putIfAbsent(r.source, () => []).add(r.sourceRecordId);
      }
      for (final e in bySource.entries) {
        for (final chunk in _chunks(e.value, 400)) {
          final old = await tx.rawQuery(
            'SELECT start, "end" FROM ${_tables[kind]} '
            'WHERE source = ? AND source_record_id IN (${_in(chunk.length)})',
            [e.key.code, ...chunk],
          );
          for (final o in old) {
            days.addAll(
              daysTouched(fromMs(_i(o['start'])), fromMs(_i(o['end']))),
            );
          }
        }
      }
    }
    final b = tx.batch();
    final hrByDay = <HrDayKey, List<RawHrRow>>{};
    for (final r in batch.hr) {
      final d = dayKeyOf(r.t);
      if (r.recordId != null) {
        b.insert('hr_record_day', {
          'source': r.source.code,
          'record_id': r.recordId,
          'origin': hrOrigin(r),
          'date': d,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      hrByDay.putIfAbsent((r.source, hrOrigin(r), d), () => []).add(r);
      days.add(d);
      days.add(nightKey(r.t));
      if (!r.t.isBefore(retention)) _writeRow(b, r);
    }
    for (final r in [
      ...batch.hrv,
      ...batch.sleep,
      ...batch.workouts,
      ...batch.scalars,
    ]) {
      _writeRow(b, r);
      days.addAll(daysTouched(r.start, r.end));
    }
    await b.commit(noResult: true);
    for (final k in extraHrDays ?? const <HrDayKey>{}) {
      hrByDay.putIfAbsent(k, () => []);
    }
    if (hrByDay.isNotEmpty) {
      await _refreshHrDays(
        tx,
        hrByDay,
        clearFrom: hrClearFrom,
        clearTo: hrClearTo,
      );
    }
    return days;
  }

  @override
  Future<Set<String>> upsert(RawRows batch) =>
      guardedWrite(db, (tx) => _upsertIn(tx, batch));

  @override
  Future<Set<String>> replaceWindow(
    SourceKind source,
    RawKind kind,
    DateTime from,
    DateTime to,
    RawRows batch, {
    ScalarKind? scalar,
  }) {
    return guardedWrite(db, (tx) async {
      final days = <String>{};
      final table = _tables[kind]!;
      final (startCol, endCol) = _timeCols[kind]!;
      var where = 'source = ? AND $startCol >= ? AND $startCol < ?';
      final args = <Object?>[source.code, ms(from), ms(to)];
      if (kind == RawKind.scalar && scalar != null) {
        where += ' AND kind = ?';
        args.add(scalar.code);
      }
      final old = await tx.rawQuery(
        'SELECT source_record_id, $startCol AS s, $endCol AS e, ingested_at '
        'FROM $table WHERE $where',
        args,
      );
      final keepIngested = <String, int>{};
      for (final o in old) {
        days.addAll(daysTouched(fromMs(_i(o['s'])), fromMs(_i(o['e']))));
        keepIngested[o['source_record_id'] as String] = _i(o['ingested_at']);
      }
      if (kind == RawKind.sleep && old.isNotEmpty) {
        final ids = [for (final o in old) o['source_record_id'] as String];
        for (final chunk in _chunks(ids, 400)) {
          await tx.delete(
            'raw_sleep_stage',
            where: 'source = ? AND session_id IN (${_in(chunk.length)})',
            whereArgs: [source.code, ...chunk],
          );
        }
      }
      await tx.delete(table, where: where, whereArgs: args);
      // Keep first-seen time for rows that survive the re-read.
      for (final r in batch.ofKind(kind, scalar: scalar)) {
        final t = keepIngested[r.sourceRecordId];
        if (t != null) r.ingestedAt = fromMs(t);
      }
      Set<HrDayKey>? hrDays;
      if (kind == RawKind.hr) {
        // Every origin's bucket in the window is rebuilt (or cleared).
        final existing = await tx.query(
          'hr_day',
          columns: ['origin', 'date'],
          where: 'source = ? AND date >= ? AND date <= ?',
          whereArgs: [source.code, DayKey.of(from), DayKey.of(to)],
        );
        hrDays = {
          for (final e in existing)
            (source, _s(e['origin']) ?? '', e['date'] as String),
        };
      }
      days.addAll(
        await _upsertIn(
          tx,
          batch,
          hrClearFrom: kind == RawKind.hr ? from : null,
          hrClearTo: kind == RawKind.hr ? to : null,
          extraHrDays: hrDays,
        ),
      );
      return days;
    });
  }

  @override
  Future<Set<String>> deleteRecords(
    SourceKind source,
    Iterable<String> recordIds,
  ) {
    final ids = recordIds.toSet().toList();
    if (ids.isEmpty) return Future.value(<String>{});
    return guardedWrite(db, (tx) async {
      final days = <String>{};
      final hrDays = <HrDayKey, List<RawHrRow>>{};
      for (final chunk in _chunks(ids, 400)) {
        final indexed = await tx.query(
          'hr_record_day',
          where: 'source = ? AND record_id IN (${_in(chunk.length)})',
          whereArgs: [source.code, ...chunk],
        );
        for (final row in indexed) {
          final date = row['date'] as String;
          days.add(date);
          days.add(DayKey.add(date, 1));
          if (!_recent(date)) {
            // Individual samples have expired. Invalidate the whole bucket;
            // HC sync rereads affected days before acknowledging the change.
            await tx.delete(
              'hr_day',
              where: 'source = ? AND origin = ? AND date = ?',
              whereArgs: [source.code, row['origin'], date],
            );
          }
        }
        await tx.delete(
          'hr_record_day',
          where: 'source = ? AND record_id IN (${_in(chunk.length)})',
          whereArgs: [source.code, ...chunk],
        );
      }
      for (final kind in RawKind.values) {
        final table = _tables[kind]!;
        final (startCol, endCol) = _timeCols[kind]!;
        for (final chunk in _chunks(ids, 400)) {
          final where = 'source = ? AND record_id IN (${_in(chunk.length)})';
          final args = [source.code, ...chunk];
          final old = await tx.rawQuery(
            'SELECT source_record_id, $startCol AS s, $endCol AS e, '
            "COALESCE(origin_package, '') AS o "
            'FROM $table WHERE $where',
            args,
          );
          if (old.isEmpty) continue;
          for (final o in old) {
            final s = fromMs(_i(o['s'])), e = fromMs(_i(o['e']));
            days.addAll(daysTouched(s, e));
            if (kind == RawKind.hr) {
              hrDays.putIfAbsent((
                source,
                o['o'] as String,
                DayKey.of(s),
              ), () => []);
            }
          }
          if (kind == RawKind.sleep) {
            final sids = [for (final o in old) o['source_record_id'] as String];
            await tx.delete(
              'raw_sleep_stage',
              where: 'source = ? AND session_id IN (${_in(sids.length)})',
              whereArgs: [source.code, ...sids],
            );
          }
          await tx.delete(table, where: where, whereArgs: args);
        }
      }
      // Only days with raw samples can be rebuilt; older buckets stay.
      hrDays.removeWhere((k, _) => !_recent(k.$3));
      if (hrDays.isNotEmpty) await _refreshHrDays(tx, hrDays);
      return days;
    });
  }

  // ── Reads ──────────────────────────────────────────────────────────────

  (String, List<Object?>) _srcFilter(
    Set<SourceKind>? sources, [
    String col = 'source',
  ]) {
    if (sources == null) return ('1 = 1', const []);
    if (sources.isEmpty) return ('1 = 0', const []);
    return (
      '$col IN (${_in(sources.length)})',
      [for (final s in sources) s.code],
    );
  }

  @override
  Future<RawRows> load(
    DateTime from,
    DateTime to, {
    Set<SourceKind>? sources,
    bool includeRawHr = false,
  }) async {
    final (sw, sa) = _srcFilter(sources);
    final f = ms(from), t = ms(to);
    final out = RawRows();
    final hrDays = await db.query(
      'hr_day',
      where: '$sw AND date >= ? AND date <= ?',
      whereArgs: [...sa, DayKey.of(from), DayKey.of(to)],
      orderBy: 'date',
    );
    out.hrDays.addAll(hrDays.map(_hrDayFrom));
    if (includeRawHr) {
      final hr = await db.query(
        'raw_hr',
        where: '$sw AND t >= ? AND t < ?',
        whereArgs: [...sa, f, t],
        orderBy: 't',
      );
      out.hr.addAll(hr.map(_hrFrom));
    }
    final hrv = await db.query(
      'raw_hrv',
      where: '$sw AND t >= ? AND t < ?',
      whereArgs: [...sa, f, t],
      orderBy: 't',
    );
    out.hrv.addAll(hrv.map(_hrvFrom));

    final sleep = await db.query(
      'raw_sleep',
      where: '$sw AND "end" >= ? AND start < ?',
      whereArgs: [...sa, f, t],
      orderBy: 'start',
    );
    if (sleep.isNotEmpty) {
      final (sw2, sa2) = _srcFilter(sources, 'st.source');
      final stages = await db.rawQuery(
        'SELECT st.* FROM raw_sleep_stage st JOIN raw_sleep s '
        'ON s.source = st.source AND s.source_record_id = st.session_id '
        'WHERE $sw2 AND s."end" >= ? AND s.start < ? ORDER BY st.start',
        [...sa2, f, t],
      );
      final bySession = <(String, String), List<StageSpan>>{};
      for (final s in stages) {
        bySession
            .putIfAbsent((
              s['source'] as String,
              s['session_id'] as String,
            ), () => [])
            .add(
              StageSpan(
                SleepStage.values.byName(s['stage'] as String),
                fromMs(_i(s['start'])),
                fromMs(_i(s['end'])),
              ),
            );
      }
      for (final m in sleep) {
        out.sleep.add(
          _sleepFrom(
            m,
            bySession[(
                  m['source'] as String,
                  m['source_record_id'] as String,
                )] ??
                const [],
          ),
        );
      }
    }
    final w = await db.query(
      'raw_workout',
      where: '$sw AND "end" >= ? AND start < ?',
      whereArgs: [...sa, f, t],
      orderBy: 'start',
    );
    out.workouts.addAll(w.map(_workoutFrom));
    final sc = await db.query(
      'raw_scalar',
      where: '$sw AND "end" >= ? AND start < ?',
      whereArgs: [...sa, f, t],
      orderBy: 'start',
    );
    out.scalars.addAll(sc.map(_scalarFrom));
    return out;
  }

  @override
  Future<(DateTime, DateTime)?> span({Set<SourceKind>? sources}) async {
    final (sw, sa) = _srcFilter(sources);
    int? lo, hi;
    void see(Object? a, Object? b) {
      final x = _iN(a), y = _iN(b);
      if (x != null && (lo == null || x < lo!)) lo = x;
      if (y != null && (hi == null || y > hi!)) hi = y;
    }

    for (final (table, s, e) in [
      ('raw_hrv', 't', 't'),
      ('raw_sleep', 'start', '"end"'),
      ('raw_workout', 'start', '"end"'),
      ('raw_scalar', 'start', '"end"'),
      ('hr_day', 'day_start', 'last_t'),
    ]) {
      final r = await db.rawQuery(
        'SELECT MIN($s) AS lo, MAX($e) AS hi FROM $table WHERE $sw',
        sa,
      );
      see(r.first['lo'], r.first['hi']);
    }
    if (lo == null || hi == null) return null;
    return (fromMs(lo!), fromMs(hi!));
  }

  @override
  Future<Map<String, int>> counts({Set<SourceKind>? sources}) async {
    final (sw, sa) = _srcFilter(sources);
    final out = <String, int>{};
    for (final table in kRawTables) {
      final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $table WHERE $sw',
        sa,
      );
      out[table] = _i(r.first['c']);
    }
    return out;
  }

  @override
  Future<void> pruneRawHr(DateTime before) async {
    await guardedWrite(db, (tx) async {
      await tx.delete('raw_hr', where: 't < ?', whereArgs: [ms(before)]);
    });
  }

  @override
  Future<void> wipe({Set<SourceKind>? sources}) async {
    final (sw, sa) = _srcFilter(sources);
    await guardedWrite(db, (tx) async {
      for (final table in kRawTables) {
        await tx.delete(table, where: sw, whereArgs: sa);
      }
    });
  }

  /// Streams every raw row of one table (export). Keys are column names.
  Future<List<Map<String, Object?>>> dumpTable(
    String table, {
    Set<SourceKind>? sources,
  }) {
    final (sw, sa) = _srcFilter(sources);
    return db.query(table, where: sw, whereArgs: sa);
  }

  @override
  Future<void> close() async {}
}

class SqliteAppStore implements AppStore {
  SqliteAppStore(this.db, {this.clock = systemClock});
  final Database db;
  final Clock clock;

  @override
  Future<T> mutate<T>(Future<T> Function() body, {DataMode? mode}) =>
      sqliteMutation(db, body, mode: mode?.name);

  @override
  Future<List<DayBundle>> bundles(DataMode mode, String from, String to) async {
    final rows = await db.rawQuery(
      'SELECT r.*, s.json AS result_json FROM day_record r '
      'JOIN day_result s ON r.mode = s.mode AND r.date = s.date '
      'WHERE r.mode = ? AND r.date >= ? AND r.date <= ? ORDER BY r.date',
      [mode.name, from, to],
    );
    return [
      for (final r in rows)
        DayBundle(_recordFrom(r), DayResult.fromJson(_json(r['result_json']))),
    ];
  }

  static Map<String, dynamic> _json(Object? s) =>
      jsonDecode(s as String) as Map<String, dynamic>;

  @override
  Future<void> putDays(
    DataMode mode,
    List<DayRecord> records,
    List<DayResult> results, {
    String? clearFrom,
  }) async {
    final now = ms(clock());
    await guardedWrite(db, (tx) async {
      if (clearFrom != null) {
        for (final t in ['day_record', 'day_result']) {
          await tx.delete(
            t,
            where: 'mode = ? AND date >= ?',
            whereArgs: [mode.name, clearFrom],
          );
        }
      }
      final b = tx.batch();
      for (final op in [
        ...SqlRows.insertAll('day_record', [
          for (final r in records) SqlRows.dayRecord(mode, r, now),
        ], maxRows: 50),
        ...SqlRows.insertAll('day_result', [
          for (final r in results) SqlRows.dayResult(mode, r),
        ], maxRows: 50),
      ]) {
        b.rawInsert(op.sql, op.args);
      }
      await b.commit(noResult: true);
      await tx.delete(
        'settings',
        where: 'key = ?',
        whereArgs: [pendingRecomputeKey(mode.name)],
      );
    });
  }

  static DayRecord _recordFrom(Map<String, Object?> m) {
    final r = DayRecord.fromJson(_json(m['json']));
    final hr = m['hr'];
    return hr is Uint8List
        ? withHrSamples(
            r,
            LazyHrSamples(r.date, hr, startMs: _iN(m['hr_start'])),
          )
        : r;
  }

  @override
  Future<DayRecord?> record(DataMode mode, String date) async {
    final rows = await db.query(
      'day_record',
      where: 'mode = ? AND date = ?',
      whereArgs: [mode.name, date],
    );
    return rows.isEmpty ? null : _recordFrom(rows.first);
  }

  @override
  Future<List<DayRecord>> records(DataMode mode, String from, String to) async {
    final rows = await db.query(
      'day_record',
      where: 'mode = ? AND date >= ? AND date <= ?',
      whereArgs: [mode.name, from, to],
      orderBy: 'date',
    );
    return rows.map(_recordFrom).toList();
  }

  @override
  Future<DayResult?> result(DataMode mode, String date) async {
    final rows = await db.query(
      'day_result',
      where: 'mode = ? AND date = ?',
      whereArgs: [mode.name, date],
    );
    return rows.isEmpty ? null : DayResult.fromJson(_json(rows.first['json']));
  }

  @override
  Future<List<DayResult>> results(DataMode mode, String from, String to) async {
    final rows = await db.query(
      'day_result',
      where: 'mode = ? AND date >= ? AND date <= ?',
      whereArgs: [mode.name, from, to],
      orderBy: 'date',
    );
    return [for (final r in rows) DayResult.fromJson(_json(r['json']))];
  }

  @override
  Future<String?> latestDate(DataMode mode) async {
    final r = await db.rawQuery(
      'SELECT MAX(date) AS d FROM day_record WHERE mode = ?',
      [mode.name],
    );
    return r.first['d'] as String?;
  }

  @override
  Future<String?> earliestDate(DataMode mode) async {
    final r = await db.rawQuery(
      'SELECT MIN(date) AS d FROM day_record WHERE mode = ?',
      [mode.name],
    );
    return r.first['d'] as String?;
  }

  @override
  Future<bool> hasStaleResults(DataMode mode, int algo) async {
    final r = await db.rawQuery(
      'SELECT 1 FROM day_result WHERE mode = ? AND algo_version != ? LIMIT 1',
      [mode.name, algo],
    );
    return r.isNotEmpty;
  }

  @override
  Future<void> clearDays(DataMode mode) async {
    await putDays(mode, const [], const [], clearFrom: '0000-00-00');
  }

  @override
  Future<JournalEntry?> journal(DataMode mode, String date) async {
    final rows = await db.query(
      'journal',
      where: 'mode = ? AND date = ?',
      whereArgs: [mode.name, date],
    );
    return rows.isEmpty
        ? null
        : JournalEntry.fromJson(_json(rows.first['json']));
  }

  @override
  Future<void> putJournal(DataMode mode, JournalEntry entry) async {
    await guardedWrite(db, (tx) async {
      await tx.insert('journal', {
        'mode': mode.name,
        'date': entry.date,
        'json': jsonEncode(entry.toJson()),
        'updated_at': ms(clock()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Bulk journal write (demo seeding).
  Future<void> putJournals(DataMode mode, List<JournalEntry> entries) async {
    await guardedWrite(db, (tx) async {
      final b = tx.batch();
      final now = ms(clock());
      for (final e in entries) {
        b.insert(
          'journal',
          SqlRows.journal(mode, e, now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await b.commit(noResult: true);
    });
  }

  @override
  Future<Map<String, JournalEntry>> journals(DataMode mode) async {
    final rows = await db.query(
      'journal',
      where: 'mode = ?',
      whereArgs: [mode.name],
    );
    return {
      for (final r in rows)
        r['date'] as String: JournalEntry.fromJson(_json(r['json'])),
    };
  }

  @override
  Future<void> clearJournal(DataMode mode) async {
    await guardedWrite(db, (tx) async {
      await tx.delete('journal', where: 'mode = ?', whereArgs: [mode.name]);
    });
  }

  @override
  Future<String?> getSetting(String key) async {
    final r = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  @override
  Future<void> setSetting(String key, String? value) async {
    await guardedWrite(db, (tx) async {
      if (value == null) {
        await tx.delete('settings', where: 'key = ?', whereArgs: [key]);
      } else {
        await tx.insert('settings', {
          'key': key,
          'value': value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> addLog(List<SyncLogEntry> entries) async {
    if (entries.isEmpty) return;
    await guardedWrite(db, (tx) async {
      final b = tx.batch();
      for (final e in entries) {
        b.insert('sync_log', {
          'at': ms(e.at),
          'source': e.source.code,
          'data_type': e.dataType,
          'status': e.status,
          'records': e.records,
          'message': e.message,
        });
      }
      // Keep the log bounded.
      b.rawDelete(
        'DELETE FROM sync_log WHERE id <= (SELECT MAX(id) FROM sync_log) - 2000',
      );
      await b.commit(noResult: true);
    });
  }

  @override
  Future<List<SyncLogEntry>> logs({int limit = 200}) async {
    final rows = await db.query('sync_log', orderBy: 'id DESC', limit: limit);
    return [
      for (final r in rows)
        SyncLogEntry(
          at: fromMs(_i(r['at'])),
          source: SourceKind.fromCode(r['source'] as String),
          dataType: r['data_type'] as String,
          status: r['status'] as String,
          records: _i(r['records']),
          message: r['message'] as String?,
        ),
    ];
  }

  @override
  Future<String?> token(SourceKind source, String scope) async {
    final r = await db.query(
      'change_tokens',
      where: 'source = ? AND scope = ?',
      whereArgs: [source.code, scope],
    );
    return r.isEmpty ? null : r.first['token'] as String;
  }

  @override
  Future<void> setToken(SourceKind source, String scope, String? token) async {
    await guardedWrite(db, (tx) async {
      if (token == null) {
        await tx.delete(
          'change_tokens',
          where: 'source = ? AND scope = ?',
          whereArgs: [source.code, scope],
        );
      } else {
        await tx.insert('change_tokens', {
          'source': source.code,
          'scope': scope,
          'token': token,
          'created_at': ms(clock()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> wipe() async {
    await guardedWrite(db, (tx) async {
      for (final t in [
        'day_record',
        'day_result',
        'journal',
        'sync_log',
        'change_tokens',
      ]) {
        await tx.delete(t);
      }
    });
  }

  @override
  Future<void> close() => db.close();
}
