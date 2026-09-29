// CSV + JSON export of raw rows, resolved days, scores and journal.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import '../db/raw_rows.dart';

String _csvCell(Object? v) {
  if (v == null) return '';
  final s = v is DateTime ? v.toUtc().toIso8601String() : '$v';
  return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String toCsv(List<String> header, Iterable<List<Object?>> rows) {
  final b = StringBuffer()..writeln(header.join(','));
  for (final r in rows) {
    b.writeln(r.map(_csvCell).join(','));
  }
  return b.toString();
}

Future<ExportResult> writeExport({
  required Directory dir,
  required RawRows raw,
  required List<DayRecord> records,
  required List<DayResult> results,
  required Map<String, JournalEntry> journal,
  required DataMode mode,
}) async {
  await dir.create(recursive: true);
  final files = <String>[];
  Future<void> write(String name, String content) async {
    final f = File(p.join(dir.path, name));
    await f.writeAsString(content);
    files.add(f.path);
  }

  const meta = [
    'source',
    'source_record_id',
    'record_id',
    'origin_package',
    'device',
  ];
  List<Object?> m(RawRow r) => [
    r.source.code,
    r.sourceRecordId,
    r.recordId,
    r.originPackage,
    r.device,
  ];

  await write(
    'raw_hr.csv',
    toCsv([...meta, 't', 'bpm'], raw.hr.map((r) => [...m(r), r.t, r.bpm])),
  );
  await write(
    'hr_minutes.csv',
    toCsv(
      ['source', 'date', 'minute_start', 'bpm'],
      [
        for (final d in raw.hrDays)
          for (final s in d.toSamples()) [d.source.code, d.date, s.t, s.bpm],
      ],
    ),
  );
  await write(
    'raw_hrv.csv',
    toCsv([
      ...meta,
      't',
      'rmssd_ms',
    ], raw.hrv.map((r) => [...m(r), r.t, r.rmssd])),
  );
  await write(
    'raw_sleep.csv',
    toCsv(
      [...meta, 'start', 'end', 'minutes_asleep', 'minutes_awake', 'stages'],
      raw.sleep.map(
        (r) => [
          ...m(r),
          r.start,
          r.end,
          r.minutesAsleep,
          r.minutesAwake,
          r.stages
              .map((s) => '${s.stage.name}:${s.minutes.toStringAsFixed(1)}')
              .join(' '),
        ],
      ),
    ),
  );
  await write(
    'raw_workouts.csv',
    toCsv(
      [
        ...meta,
        'start',
        'end',
        'name',
        'activity_type',
        'avg_hr',
        'calories',
        'distance_m',
      ],
      raw.workouts.map(
        (r) => [
          ...m(r),
          r.start,
          r.end,
          r.name,
          r.activityType,
          r.avgHr,
          r.calories,
          r.distanceM,
        ],
      ),
    ),
  );
  await write(
    'raw_scalars.csv',
    toCsv(
      [...meta, 'kind', 'start', 'end', 'value', 'day'],
      raw.scalars.map(
        (r) => [...m(r), r.scalar.code, r.start, r.end, r.value, r.day],
      ),
    ),
  );
  await write(
    'days.csv',
    toCsv(
      [
        'date',
        'recovery',
        'strain',
        'sleep_min',
        'hrv_ms',
        'rhr',
        'resp',
        'skin_temp_delta',
        'spo2',
        'steps',
        'hrv_definition',
        'sleeping_hr_4h', // never resting HR (HRV ladder S1)
      ],
      [
        for (final r in records)
          () {
            final res = results.where((x) => x.date == r.date).firstOrNull;
            return [
              r.date,
              res?.recovery?.score,
              res?.strain?.strain.toStringAsFixed(1),
              r.totalSleepMinutes.round(),
              r.hrvRmssd?.toStringAsFixed(1),
              r.restingHr?.toStringAsFixed(1),
              r.respiratoryRate?.toStringAsFixed(2),
              r.skinTempDelta?.toStringAsFixed(2),
              r.spo2Avg?.toStringAsFixed(1),
              r.steps,
              r.definitionOf(Metric.hrv),
              r.sleepingHr4h?.toStringAsFixed(1),
            ];
          }(),
      ],
    ),
  );
  const enc = JsonEncoder.withIndent('  ');
  await write(
    'airlog_export.json',
    enc.convert({
      'mode': mode.name,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'algoVersion': kAlgoVersion,
      'days': [for (final r in records) (r.toJson()..remove('hrSamples'))],
      'results': [for (final r in results) r.toJson()],
      'journal': [for (final j in journal.values) j.toJson()],
    }),
  );
  return ExportResult(files: files, directory: dir.path);
}
