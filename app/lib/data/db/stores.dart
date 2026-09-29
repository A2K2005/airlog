// Storage interfaces. Two implementations each: sqflite (the app) and
// in-memory (InMemoryHealthRepository for widget/golden tests), so the
// repository, sync and resolver code is identical in both.

import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import 'raw_rows.dart';

/// Raw HR samples are kept this long (diagnostics, rebuilds after
/// deletions). The 1-minute buckets are kept forever.
const Duration kRawHrRetention = Duration(days: 14);

abstract class RawStore {
  /// Idempotent upsert keyed by (source, source_record_id). Returns the day
  /// keys whose resolved record may have changed.
  Future<Set<String>> upsert(RawRows batch);

  /// Full re-read semantics for one source + kind: every stored row of that
  /// kind whose start lies in [from, to) and is not in [batch] is deleted,
  /// then [batch] is upserted. Handles missed deletions / rewritten nights.
  Future<Set<String>> replaceWindow(
    SourceKind source,
    RawKind kind,
    DateTime from,
    DateTime to,
    RawRows batch, {
    ScalarKind? scalar,
  });

  /// Deletes every row (all raw tables) whose upstream record id is in
  /// [recordIds]. Returns affected day keys.
  Future<Set<String>> deleteRecords(
    SourceKind source,
    Iterable<String> recordIds,
  );

  /// Rows overlapping [from, to). HR comes as [HrDay]s; raw HR samples only
  /// when [includeRawHr].
  Future<RawRows> load(
    DateTime from,
    DateTime to, {
    Set<SourceKind>? sources,
    bool includeRawHr = false,
  });

  /// Oldest and newest instant of any row of [sources] (null when empty).
  Future<(DateTime, DateTime)?> span({Set<SourceKind>? sources});

  /// Row counts per table (diagnostics, export).
  Future<Map<String, int>> counts({Set<SourceKind>? sources});

  Future<void> pruneRawHr(DateTime before);

  /// Deletes raw rows of [sources] (all when null).
  Future<void> wipe({Set<SourceKind>? sources});

  Future<void> close();
}

/// Everything that is not raw: resolved records, scores, journal, settings,
/// sync log and change tokens. Day rows are kept per [DataMode] so demo and
/// live data never mix (switching modes keeps both).
abstract class AppStore {
  Future<void> putDays(
    DataMode mode,
    List<DayRecord> records,
    List<DayResult> results, {
    String? clearFrom,
  });
  Future<DayRecord?> record(DataMode mode, String date);
  Future<List<DayRecord>> records(DataMode mode, String from, String to);
  Future<DayResult?> result(DataMode mode, String date);
  Future<List<DayResult>> results(DataMode mode, String from, String to);
  Future<String?> latestDate(DataMode mode);
  Future<String?> earliestDate(DataMode mode);

  /// True if any stored result has an algo version other than [algo].
  Future<bool> hasStaleResults(DataMode mode, int algo);
  Future<void> clearDays(DataMode mode);

  Future<JournalEntry?> journal(DataMode mode, String date);
  Future<void> putJournal(DataMode mode, JournalEntry entry);
  Future<Map<String, JournalEntry>> journals(DataMode mode);
  Future<void> clearJournal(DataMode mode);

  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String? value);

  Future<void> addLog(List<SyncLogEntry> entries);
  Future<List<SyncLogEntry>> logs({int limit = 200});

  Future<String?> token(SourceKind source, String scope);
  Future<void> setToken(SourceKind source, String scope, String? token);

  /// Deletes days, results, journal, log and tokens; keeps settings.
  Future<void> wipe();
  Future<void> close();
}
