// A minimal HealthRepository for shell / route tests: answers the handful of
// members the shell reads and throws for anything else, so a test that
// accidentally depends on data fails loudly.

import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';

class FakeRepo implements HealthRepository {
  FakeRepo({this.mode = DataMode.demo});

  @override
  DataMode mode;

  @override
  int get revision => 1;

  @override
  Stream<int> get revisions => const Stream.empty();

  @override
  SyncStatus get syncStatus => const SyncStatus(phase: SyncPhase.idle);

  @override
  Stream<SyncStatus> get syncStatusChanges => const Stream.empty();

  @override
  Future<String?> latestDate() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeRepo: ${invocation.memberName}');

  // Any-app sources (contract 2026-09-29). Placeholder; the Data agent
  // implements these for real in HealthRepositoryImpl.
  @override
  Future<List<SourceApp>> detectedSources() async => const [];

  @override
  Future<Map<Metric, SourceChoice>> sourceChoices() async => const {};

  @override
  Future<void> setSourceChoice(Metric metric, String? origin) async {}
}
