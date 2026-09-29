// Lazily opened stores, so the first frame never waits for the database.
//
// DataModule builds these synchronously; the database opens on the first
// store call (HealthRepositoryImpl.start(), kicked off right after
// construction, and awaited by every repository read). A failed open is not
// cached: the next call retries, like start() itself.

import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import 'raw_rows.dart';
import 'stores.dart';

/// A value opened on first use and shared by the stores built on it.
class Lazy<T> {
  Lazy(this._open);
  final Future<T> Function() _open;
  Future<T>? _future;
  T? _value;

  /// The opened value, or null when [get] has not completed yet.
  T? get valueOrNull => _value;

  /// True once an open has been started (it may still be in flight).
  bool get started => _future != null;

  Future<T> get() => _future ??= _open().then(
    (v) => _value = v,
    onError: (Object e, StackTrace st) {
      _future = null;
      Error.throwWithStackTrace(e, st);
    },
  );

  /// Waits for an in-flight open (ignoring its failure); null if never
  /// started.
  Future<T?> settled() async {
    final f = _future;
    if (f == null) return null;
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }
}

class DeferredRawStore implements RawStore {
  DeferredRawStore(this._store);
  final Future<RawStore> Function() _store;

  @override
  Future<Set<String>> upsert(RawRows batch) async =>
      (await _store()).upsert(batch);

  @override
  Future<Set<String>> replaceWindow(
    SourceKind source,
    RawKind kind,
    DateTime from,
    DateTime to,
    RawRows batch, {
    ScalarKind? scalar,
  }) async => (await _store()).replaceWindow(
    source,
    kind,
    from,
    to,
    batch,
    scalar: scalar,
  );

  @override
  Future<Set<String>> deleteRecords(
    SourceKind source,
    Iterable<String> recordIds,
  ) async => (await _store()).deleteRecords(source, recordIds);

  @override
  Future<RawRows> load(
    DateTime from,
    DateTime to, {
    Set<SourceKind>? sources,
    bool includeRawHr = false,
  }) async => (await _store()).load(
    from,
    to,
    sources: sources,
    includeRawHr: includeRawHr,
  );

  @override
  Future<(DateTime, DateTime)?> span({Set<SourceKind>? sources}) async =>
      (await _store()).span(sources: sources);

  @override
  Future<Map<String, int>> counts({Set<SourceKind>? sources}) async =>
      (await _store()).counts(sources: sources);

  @override
  Future<void> pruneRawHr(DateTime before) async =>
      (await _store()).pruneRawHr(before);

  @override
  Future<void> wipe({Set<SourceKind>? sources}) async =>
      (await _store()).wipe(sources: sources);

  @override
  Future<void> close() async => (await _store()).close();
}

class DeferredAppStore implements AppStore {
  DeferredAppStore(this._store);
  final Future<AppStore> Function() _store;

  @override
  Future<T> mutate<T>(Future<T> Function() body, {DataMode? mode}) async =>
      (await _store()).mutate(body, mode: mode);

  @override
  Future<List<DayBundle>> bundles(
    DataMode mode,
    String from,
    String to,
  ) async => (await _store()).bundles(mode, from, to);

  @override
  Future<void> putDays(
    DataMode mode,
    List<DayRecord> records,
    List<DayResult> results, {
    String? clearFrom,
  }) async =>
      (await _store()).putDays(mode, records, results, clearFrom: clearFrom);

  @override
  Future<DayRecord?> record(DataMode mode, String date) async =>
      (await _store()).record(mode, date);

  @override
  Future<List<DayRecord>> records(
    DataMode mode,
    String from,
    String to,
  ) async => (await _store()).records(mode, from, to);

  @override
  Future<DayResult?> result(DataMode mode, String date) async =>
      (await _store()).result(mode, date);

  @override
  Future<List<DayResult>> results(
    DataMode mode,
    String from,
    String to,
  ) async => (await _store()).results(mode, from, to);

  @override
  Future<String?> latestDate(DataMode mode) async =>
      (await _store()).latestDate(mode);

  @override
  Future<String?> earliestDate(DataMode mode) async =>
      (await _store()).earliestDate(mode);

  @override
  Future<bool> hasStaleResults(DataMode mode, int algo) async =>
      (await _store()).hasStaleResults(mode, algo);

  @override
  Future<void> clearDays(DataMode mode) async =>
      (await _store()).clearDays(mode);

  @override
  Future<JournalEntry?> journal(DataMode mode, String date) async =>
      (await _store()).journal(mode, date);

  @override
  Future<void> putJournal(DataMode mode, JournalEntry entry) async =>
      (await _store()).putJournal(mode, entry);

  @override
  Future<Map<String, JournalEntry>> journals(DataMode mode) async =>
      (await _store()).journals(mode);

  @override
  Future<void> clearJournal(DataMode mode) async =>
      (await _store()).clearJournal(mode);

  @override
  Future<String?> getSetting(String key) async =>
      (await _store()).getSetting(key);

  @override
  Future<void> setSetting(String key, String? value) async =>
      (await _store()).setSetting(key, value);

  @override
  Future<void> addLog(List<SyncLogEntry> entries) async =>
      (await _store()).addLog(entries);

  @override
  Future<List<SyncLogEntry>> logs({int limit = 200}) async =>
      (await _store()).logs(limit: limit);

  @override
  Future<String?> token(SourceKind source, String scope) async =>
      (await _store()).token(source, scope);

  @override
  Future<void> setToken(SourceKind source, String scope, String? token) async =>
      (await _store()).setToken(source, scope, token);

  @override
  Future<void> wipe() async => (await _store()).wipe();

  @override
  Future<void> close() async => (await _store()).close();
}
