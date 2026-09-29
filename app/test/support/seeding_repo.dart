// A repository that behaves like the real one on first launch: while the demo
// is being seeded it reports SyncStatus(phase: syncing, message: …) and every
// read waits; [finish] releases the reads (answered by the wrapped demo
// repository), flips the status to idle and bumps the revision.

import 'dart:async';

import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';

class SeedingRepo implements HealthRepository {
  SeedingRepo(this.inner, {this.message = 'Preparing 90 days of sample data…'});

  final HealthRepository inner;
  final String? message;

  final _gate = Completer<void>();
  final _status = StreamController<SyncStatus>.broadcast();
  final _revs = StreamController<int>.broadcast();
  var _rev = 1;
  late SyncStatus _now = SyncStatus(phase: SyncPhase.syncing, message: message);

  /// Seeding done: reads answer, status goes idle, the revision bumps.
  Future<void> finish() async {
    if (!_gate.isCompleted) _gate.complete();
    _now = SyncStatus(
      phase: SyncPhase.idle,
      lastSyncAt: inner.syncStatus.lastSyncAt,
      lastDataAt: inner.syncStatus.lastDataAt,
    );
    _status.add(_now);
    _revs.add(++_rev);
  }

  Future<T> _after<T>(Future<T> Function() read) async {
    await _gate.future;
    return read();
  }

  @override
  DataMode get mode => DataMode.demo;
  @override
  Future<void> setMode(DataMode mode) async {}
  @override
  int get revision => _rev;
  @override
  Stream<int> get revisions => _revs.stream;
  @override
  SyncStatus get syncStatus => _now;
  @override
  Stream<SyncStatus> get syncStatusChanges => _status.stream;

  @override
  Future<String?> latestDate() => _after(inner.latestDate);
  @override
  Future<DayBundle?> day(String date) => _after(() => inner.day(date));
  @override
  Future<List<DayBundle>> range(String from, String to) =>
      _after(() => inner.range(from, to));
  @override
  Future<JournalEntry> journal(String date) =>
      _after(() => inner.journal(date));
  @override
  Future<List<FactorInsight>> journalInsights() =>
      _after(inner.journalInsights);
  @override
  Future<UserProfile> profile() => _after(inner.profile);
  @override
  Future<void> syncNow() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SeedingRepo: ${invocation.memberName}');

  // Any-app sources (contract 2026-09-29). Placeholder; the Data agent
  // implements these for real in HealthRepositoryImpl.
  @override
  Future<List<SourceApp>> detectedSources() async => const [];

  @override
  Future<Map<Metric, SourceChoice>> sourceChoices() async => const {};

  @override
  Future<void> setSourceChoice(Metric metric, String? origin) async {}
}
