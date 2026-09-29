// Row ↔ column mapping for the sqlite tables, plus a multi-row INSERT
// builder. Pure Dart (no sqflite import), so the demo seed can build its
// whole write payload inside a worker isolate and the UI isolate only does
// the I/O.

import 'dart:convert';
import 'dart:math' as math;

import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import '../common/time.dart';
import 'hr_buckets.dart';
import 'raw_rows.dart';

/// SQLite on Android < 11 is built with SQLITE_MAX_VARIABLE_NUMBER = 999.
const int kMaxSqlVariables = 999;

/// One statement of a bulk write.
class SqlOp {
  const SqlOp(this.sql, [this.args = const []]);
  final String sql;
  final List<Object?> args;
}

abstract final class SqlRows {
  static const Map<RawKind, String> rawTables = {
    RawKind.hr: 'raw_hr',
    RawKind.hrv: 'raw_hrv',
    RawKind.sleep: 'raw_sleep',
    RawKind.workout: 'raw_workout',
    RawKind.scalar: 'raw_scalar',
  };

  static Map<String, Object?> _base(RawRow r) => {
    'source': r.source.code,
    'source_record_id': r.sourceRecordId,
    'record_id': r.recordId,
    'origin_package': r.originPackage,
    'device': r.device,
    'ingested_at': ms(r.ingestedAt),
  };

  /// Columns of [r] for its raw table (sleep stages: [stageColumns]).
  static Map<String, Object?> raw(RawRow r) {
    final base = _base(r);
    return switch (r) {
      RawHrRow() => {...base, 't': ms(r.t), 'bpm': r.bpm},
      RawHrvRow() => {
        ...base,
        't': ms(r.t),
        'rmssd': r.rmssd,
        'recording_method': r.recordingMethod,
      },
      RawSleepRow() => {
        ...base,
        'start': ms(r.start),
        'end': ms(r.end),
        'is_main': r.isMain == null ? null : (r.isMain! ? 1 : 0),
        'minutes_asleep': r.minutesAsleep,
        'minutes_awake': r.minutesAwake,
        'written_at': r.writtenAt == null ? null : ms(r.writtenAt!),
      },
      RawWorkoutRow() => {
        ...base,
        'start': ms(r.start),
        'end': ms(r.end),
        'name': r.name,
        'activity_type': r.activityType,
        'avg_hr': r.avgHr,
        'calories': r.calories,
        'distance_m': r.distanceM,
      },
      RawScalarRow() => {
        ...base,
        'kind': r.scalar.code,
        'start': ms(r.start),
        'end': ms(r.end),
        'value': r.value,
        'day': r.day,
      },
      _ => throw ArgumentError('unknown raw row ${r.runtimeType}'),
    };
  }

  static List<Map<String, Object?>> stages(RawSleepRow r) => [
    for (final s in r.stages)
      {
        'source': r.source.code,
        'session_id': r.sourceRecordId,
        'start': ms(s.start),
        'end': ms(s.end),
        'stage': s.stage.name,
      },
  ];

  static Map<String, Object?> hrDay(HrDay d, int nowMs) => {
    'source': d.source.code,
    'origin': d.origin,
    'date': d.date,
    'day_start': ms(d.dayStart),
    'minutes': encodeTenths(d.tenths),
    'samples': d.samples,
    'last_t': d.lastT == null ? null : ms(d.lastT!),
    'device': d.device,
    'updated_at': nowMs,
  };

  static Map<String, Object?> dayRecord(
    DataMode mode,
    DayRecord r,
    int nowMs,
  ) => {
    'mode': mode.name,
    'date': r.date,
    // Serialise WITHOUT the samples (DayRecord.toJson would ISO-format
    // every one of ~1 440 samples just to drop them); they go in the blob.
    'json': jsonEncode(
      (r.hrSamples.isEmpty ? r : withHrSamples(r, const [])).toJson()
        ..remove('hrSamples'),
    ),
    'hr': r.hrSamples.isEmpty ? null : encodeSamples(r.date, r.hrSamples),
    'updated_at': nowMs,
  };

  static Map<String, Object?> dayResult(DataMode mode, DayResult r) => {
    'mode': mode.name,
    'date': r.date,
    'algo_version': r.algoVersion,
    'computed_at': ms(r.computedAt),
    'json': jsonEncode(r.toJson()),
  };

  static Map<String, Object?> journal(
    DataMode mode,
    JournalEntry e,
    int nowMs,
  ) => {
    'mode': mode.name,
    'date': e.date,
    'json': jsonEncode(e.toJson()),
    'updated_at': nowMs,
  };

  static String _q(String col) => '"$col"';

  /// A SQL literal for [v], or null when [v] must stay a bound parameter.
  static String? _literal(Object? v) => switch (v) {
    null => 'NULL',
    int() => '$v',
    String() when v.length <= 200 => "'${v.replaceAll("'", "''")}'",
    _ => null,
  };

  /// Multi-row `INSERT OR REPLACE` statements for [rows] (all with the same
  /// keys). Columns whose value is identical across a chunk are written
  /// ONCE per statement as literals and only the varying columns are bound:
  ///
  ///   INSERT OR REPLACE INTO t (a, b, c) SELECT 'demo', column1, column2
  ///   FROM (VALUES (?, ?), (?, ?), …)
  ///
  /// so a chunk of HR samples marshals just (id, t, bpm) per row over the
  /// platform channel and fits more rows under [maxVars]. (VALUES as a
  /// subquery needs SQLite 3.8.8+; Android 8 / minSdk 26 ships 3.18.)
  static List<SqlOp> insertAll(
    String table,
    List<Map<String, Object?>> rows, {
    int maxVars = kMaxSqlVariables,
    int maxRows = 500,
  }) {
    if (rows.isEmpty) return const [];
    final cols = rows.first.keys.toList();
    final into = 'INSERT OR REPLACE INTO $table (${cols.map(_q).join(', ')}) ';

    List<String?> constsOf(int from, int n) {
      final out = [
        for (final c in cols)
          () {
            final v = rows[from][c];
            final lit = _literal(v);
            if (lit == null) return null;
            for (var k = from + 1; k < from + n; k++) {
              if (rows[k][c] != v) return null;
            }
            return lit;
          }(),
      ];
      // Keep at least one bound column so every row has a VALUES tuple.
      if (out.every((x) => x != null)) out[0] = null;
      return out;
    }

    int varyingOf(List<String?> c) => c.where((x) => x == null).length;

    final out = <SqlOp>[];
    var i = 0;
    while (i < rows.length) {
      var n = math.min(maxRows, rows.length - i);
      var consts = constsOf(i, n);
      var v = varyingOf(consts);
      if (v * n > maxVars) {
        // Shrink to fit; a shorter chunk may have more constant columns.
        n = maxVars ~/ v;
        consts = constsOf(i, n);
        v = varyingOf(consts);
      }
      final args = <Object?>[];
      for (var k = i; k < i + n; k++) {
        final r = rows[k];
        for (var j = 0; j < cols.length; j++) {
          if (consts[j] == null) args.add(r[cols[j]]);
        }
      }
      final tuple = '(${List.filled(v, '?').join(', ')})';
      final values = 'VALUES ${List.filled(n, tuple).join(', ')}';
      if (v == cols.length) {
        out.add(SqlOp('$into$values', args));
      } else {
        var bound = 0;
        final select = [for (final c in consts) c ?? 'column${++bound}']
            .join(', ');
        out.add(SqlOp('${into}SELECT $select FROM ($values)', args));
      }
      i += n;
    }
    return out;
  }
}
