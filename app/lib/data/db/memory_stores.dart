// In-memory RawStore / AppStore (no sqflite). Used by
// InMemoryHealthRepository for widget and golden tests, and by data tests.
// Every operation also has a synchronous twin (…Sync) so the in-memory demo
// repository can be fully built inside a synchronous factory (no timers, no
// pending futures in widget tests).

import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import '../common/time.dart';
import 'hr_buckets.dart';
import 'raw_rows.dart';
import 'stores.dart';

typedef _Key = (SourceKind, String);

class MemoryRawStore implements RawStore {
  final Map<_Key, RawHrRow> _hr = {};
  final Map<_Key, RawHrvRow> _hrv = {};
  final Map<_Key, RawSleepRow> _sleep = {};
  final Map<_Key, RawWorkoutRow> _workouts = {};
  final Map<_Key, RawScalarRow> _scalars = {};

  /// (source, origin, day) → source_record_ids of that day's raw samples.
  final Map<HrDayKey, Set<String>> _hrIndex = {};
  final Map<HrDayKey, HrDay> _hrDays = {};

  Map<_Key, RawRow> _mapFor(RawKind k) => switch (k) {
    RawKind.hr => _hr,
    RawKind.hrv => _hrv,
    RawKind.sleep => _sleep,
    RawKind.workout => _workouts,
    RawKind.scalar => _scalars,
  };

  static HrDayKey _hrKey(RawHrRow r) => (r.source, hrOrigin(r), dayKeyOf(r.t));

  void _putHr(RawHrRow r, Set<HrDayKey> dirtyHr) {
    final key = (r.source, r.sourceRecordId);
    final old = _hr[key];
    if (old != null) {
      final od = _hrKey(old);
      _hrIndex[od]?.remove(r.sourceRecordId);
      dirtyHr.add(od);
    }
    _hr[key] = r;
    final d = _hrKey(r);
    _hrIndex.putIfAbsent(d, () => {}).add(r.sourceRecordId);
    dirtyHr.add(d);
  }

  void _removeHr(_Key key, Set<HrDayKey> dirtyHr) {
    final old = _hr.remove(key);
    if (old == null) return;
    final d = _hrKey(old);
    _hrIndex[d]?.remove(old.sourceRecordId);
    dirtyHr.add(d);
  }

  void _rebuild(Set<HrDayKey> dirtyHr) {
    for (final d in dirtyHr) {
      final ids = _hrIndex[d];
      if (ids == null || ids.isEmpty) {
        _hrDays.remove(d);
        _hrIndex.remove(d);
        continue;
      }
      final rows = [for (final id in ids) _hr[(d.$1, id)]!];
      _hrDays[d] = buildHrDay(d.$1, d.$3, rows, origin: d.$2);
    }
  }

  Set<String> upsertSync(RawRows batch) {
    final days = <String>{};
    final dirtyHr = <HrDayKey>{};
    for (final r in batch.hr) {
      _putHr(r, dirtyHr);
      days.add(dayKeyOf(r.t));
      days.add(nightKey(r.t));
    }
    void put<T extends RawRow>(Map<_Key, T> m, List<T> rows) {
      for (final r in rows) {
        final key = (r.source, r.sourceRecordId);
        final old = m[key];
        if (old != null) days.addAll(daysTouched(old.start, old.end));
        m[key] = r;
        days.addAll(daysTouched(r.start, r.end));
      }
    }

    put(_hrv, batch.hrv);
    put(_sleep, batch.sleep);
    put(_workouts, batch.workouts);
    put(_scalars, batch.scalars);
    _rebuild(dirtyHr);
    return days;
  }

  Set<String> replaceWindowSync(
    SourceKind source,
    RawKind kind,
    DateTime from,
    DateTime to,
    RawRows batch, {
    ScalarKind? scalar,
  }) {
    final keep = {
      for (final r in batch.ofKind(kind, scalar: scalar)) r.sourceRecordId,
    };
    final days = <String>{};
    final dirtyHr = <HrDayKey>{};
    final m = _mapFor(kind);
    final doomed = <_Key>[];
    for (final e in m.entries) {
      final r = e.value;
      if (r.source != source) continue;
      if (scalar != null && r is RawScalarRow && r.scalar != scalar) continue;
      if (r.start.isBefore(from) || !r.start.isBefore(to)) continue;
      if (keep.contains(r.sourceRecordId)) continue;
      doomed.add(e.key);
      days.addAll(daysTouched(r.start, r.end));
    }
    for (final k in doomed) {
      if (kind == RawKind.hr) {
        _removeHr(k, dirtyHr);
      } else {
        m.remove(k);
      }
    }
    _rebuild(dirtyHr);
    days.addAll(upsertSync(batch));
    return days;
  }

  Set<String> deleteRecordsSync(SourceKind source, Iterable<String> recordIds) {
    final ids = recordIds.toSet();
    final days = <String>{};
    final dirtyHr = <HrDayKey>{};
    for (final kind in RawKind.values) {
      final m = _mapFor(kind);
      final doomed = [
        for (final e in m.entries)
          if (e.value.source == source && ids.contains(e.value.recordId)) e.key,
      ];
      for (final k in doomed) {
        final r = m[k]!;
        days.addAll(daysTouched(r.start, r.end));
        if (kind == RawKind.hr) {
          _removeHr(k, dirtyHr);
        } else {
          m.remove(k);
        }
      }
    }
    _rebuild(dirtyHr);
    return days;
  }

  RawRows loadSync(
    DateTime from,
    DateTime to, {
    Set<SourceKind>? sources,
    bool includeRawHr = false,
  }) {
    bool ok(RawRow r) =>
        (sources == null || sources.contains(r.source)) &&
        !r.end.isBefore(from) &&
        r.start.isBefore(to);
    final fromDay = DayKey.of(from), toDay = DayKey.of(to);
    final out = RawRows(
      hrv: _hrv.values.where(ok).toList()..sort((a, b) => a.t.compareTo(b.t)),
      sleep: _sleep.values.where(ok).toList()
        ..sort((a, b) => a.start.compareTo(b.start)),
      workouts: _workouts.values.where(ok).toList()
        ..sort((a, b) => a.start.compareTo(b.start)),
      scalars: _scalars.values.where(ok).toList()
        ..sort((a, b) => a.start.compareTo(b.start)),
      hrDays: [
        for (final e in _hrDays.entries)
          if ((sources == null || sources.contains(e.key.$1)) &&
              e.key.$3.compareTo(fromDay) >= 0 &&
              e.key.$3.compareTo(toDay) <= 0)
            e.value,
      ]..sort((a, b) => a.date.compareTo(b.date)),
    );
    if (includeRawHr) {
      out.hr.addAll(
        _hr.values.where(ok).toList()..sort((a, b) => a.t.compareTo(b.t)),
      );
    }
    return out;
  }

  (DateTime, DateTime)? spanSync({Set<SourceKind>? sources}) {
    DateTime? lo, hi;
    void see(RawRow r) {
      if (sources != null && !sources.contains(r.source)) return;
      if (lo == null || r.start.isBefore(lo!)) lo = r.start;
      if (hi == null || r.end.isAfter(hi!)) hi = r.end;
    }

    for (final kind in RawKind.values) {
      _mapFor(kind).values.forEach(see);
    }
    for (final d in _hrDays.values) {
      if (sources != null && !sources.contains(d.source)) continue;
      if (lo == null || d.dayStart.isBefore(lo!)) lo = d.dayStart;
      final l = d.lastT;
      if (l != null && (hi == null || l.isAfter(hi!))) hi = l;
    }
    return lo == null || hi == null ? null : (lo!, hi!);
  }

  @override
  Future<Set<String>> upsert(RawRows batch) async => upsertSync(batch);

  @override
  Future<Set<String>> replaceWindow(
    SourceKind source,
    RawKind kind,
    DateTime from,
    DateTime to,
    RawRows batch, {
    ScalarKind? scalar,
  }) async => replaceWindowSync(source, kind, from, to, batch, scalar: scalar);

  @override
  Future<Set<String>> deleteRecords(
    SourceKind source,
    Iterable<String> recordIds,
  ) async => deleteRecordsSync(source, recordIds);

  @override
  Future<RawRows> load(
    DateTime from,
    DateTime to, {
    Set<SourceKind>? sources,
    bool includeRawHr = false,
  }) async => loadSync(from, to, sources: sources, includeRawHr: includeRawHr);

  @override
  Future<(DateTime, DateTime)?> span({Set<SourceKind>? sources}) async =>
      spanSync(sources: sources);

  @override
  Future<Map<String, int>> counts({Set<SourceKind>? sources}) async {
    int c(Map<_Key, RawRow> m) => m.values
        .where((r) => sources == null || sources.contains(r.source))
        .length;
    return {
      'raw_hr': c(_hr),
      'hr_day': _hrDays.keys
          .where((k) => sources == null || sources.contains(k.$1))
          .length,
      'raw_hrv': c(_hrv),
      'raw_sleep': c(_sleep),
      'raw_workout': c(_workouts),
      'raw_scalar': c(_scalars),
    };
  }

  /// In memory the raw samples are the bucket source of truth, so pruning
  /// is a no-op (the sqlite store keeps buckets and drops old raw rows).
  @override
  Future<void> pruneRawHr(DateTime before) async {}

  void wipeSync({Set<SourceKind>? sources}) {
    bool hit(SourceKind s) => sources == null || sources.contains(s);
    for (final kind in RawKind.values) {
      _mapFor(kind).removeWhere((k, _) => hit(k.$1));
    }
    _hrIndex.removeWhere((k, _) => hit(k.$1));
    _hrDays.removeWhere((k, _) => hit(k.$1));
  }

  @override
  Future<void> wipe({Set<SourceKind>? sources}) async =>
      wipeSync(sources: sources);

  @override
  Future<void> close() async {}
}

class MemoryAppStore implements AppStore {
  final Map<(DataMode, String), DayRecord> _records = {};
  final Map<(DataMode, String), DayResult> _results = {};
  final Map<(DataMode, String), JournalEntry> _journal = {};
  final Map<String, String> _settings = {};
  final List<SyncLogEntry> _log = [];
  final Map<(SourceKind, String), String> _tokens = {};

  void putDaysSync(
    DataMode mode,
    List<DayRecord> records,
    List<DayResult> results, {
    String? clearFrom,
  }) {
    if (clearFrom != null) {
      _records.removeWhere(
        (k, _) => k.$1 == mode && k.$2.compareTo(clearFrom) >= 0,
      );
      _results.removeWhere(
        (k, _) => k.$1 == mode && k.$2.compareTo(clearFrom) >= 0,
      );
    }
    for (final r in records) {
      _records[(mode, r.date)] = r;
    }
    for (final r in results) {
      _results[(mode, r.date)] = r;
    }
  }

  void putJournalSync(DataMode mode, JournalEntry e) =>
      _journal[(mode, e.date)] = e;

  @override
  Future<void> putDays(
    DataMode mode,
    List<DayRecord> records,
    List<DayResult> results, {
    String? clearFrom,
  }) async => putDaysSync(mode, records, results, clearFrom: clearFrom);

  @override
  Future<DayRecord?> record(DataMode mode, String date) async =>
      _records[(mode, date)];

  @override
  Future<List<DayRecord>> records(
    DataMode mode,
    String from,
    String to,
  ) async =>
      (_records.entries
          .where(
            (e) =>
                e.key.$1 == mode &&
                e.key.$2.compareTo(from) >= 0 &&
                e.key.$2.compareTo(to) <= 0,
          )
          .map((e) => e.value)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date)));

  @override
  Future<DayResult?> result(DataMode mode, String date) async =>
      _results[(mode, date)];

  @override
  Future<List<DayResult>> results(
    DataMode mode,
    String from,
    String to,
  ) async =>
      (_results.entries
          .where(
            (e) =>
                e.key.$1 == mode &&
                e.key.$2.compareTo(from) >= 0 &&
                e.key.$2.compareTo(to) <= 0,
          )
          .map((e) => e.value)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date)));

  String? _edge(DataMode mode, bool latest) {
    String? best;
    for (final k in _records.keys) {
      if (k.$1 != mode) continue;
      if (best == null ||
          (latest ? k.$2.compareTo(best) > 0 : k.$2.compareTo(best) < 0)) {
        best = k.$2;
      }
    }
    return best;
  }

  @override
  Future<String?> latestDate(DataMode mode) async => _edge(mode, true);

  @override
  Future<String?> earliestDate(DataMode mode) async => _edge(mode, false);

  @override
  Future<bool> hasStaleResults(DataMode mode, int algo) async => _results
      .entries
      .any((e) => e.key.$1 == mode && e.value.algoVersion != algo);

  @override
  Future<void> clearDays(DataMode mode) async {
    _records.removeWhere((k, _) => k.$1 == mode);
    _results.removeWhere((k, _) => k.$1 == mode);
  }

  @override
  Future<JournalEntry?> journal(DataMode mode, String date) async =>
      _journal[(mode, date)];

  @override
  Future<void> putJournal(DataMode mode, JournalEntry entry) async =>
      putJournalSync(mode, entry);

  @override
  Future<Map<String, JournalEntry>> journals(DataMode mode) async => {
    for (final e in _journal.entries)
      if (e.key.$1 == mode) e.key.$2: e.value,
  };

  @override
  Future<void> clearJournal(DataMode mode) async =>
      _journal.removeWhere((k, _) => k.$1 == mode);

  String? getSettingSync(String key) => _settings[key];
  void setSettingSync(String key, String? value) =>
      value == null ? _settings.remove(key) : _settings[key] = value;

  @override
  Future<String?> getSetting(String key) async => getSettingSync(key);

  @override
  Future<void> setSetting(String key, String? value) async =>
      setSettingSync(key, value);

  @override
  Future<void> addLog(List<SyncLogEntry> entries) async {
    _log.addAll(entries);
    if (_log.length > 2000) _log.removeRange(0, _log.length - 2000);
  }

  @override
  Future<List<SyncLogEntry>> logs({int limit = 200}) async =>
      _log.reversed.take(limit).toList();

  @override
  Future<String?> token(SourceKind source, String scope) async =>
      _tokens[(source, scope)];

  @override
  Future<void> setToken(SourceKind source, String scope, String? token) async =>
      token == null
      ? _tokens.remove((source, scope))
      : _tokens[(source, scope)] = token;

  @override
  Future<void> wipe() async {
    _records.clear();
    _results.clear();
    _journal.clear();
    _log.clear();
    _tokens.clear();
  }

  @override
  Future<void> close() async {}
}
