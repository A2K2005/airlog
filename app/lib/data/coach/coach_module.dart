// Composition of the coach: CoachRepositoryImpl (SQLite + secure storage),
// CoachServiceImpl (the ask use case, pure Dart) and InsightServiceImpl
// (cards). DataModule builds the SQLite one; tests and goldens use
// [CoachModule.inMemory] over InMemoryHealthRepository.demo().

import 'package:sqflite/sqflite.dart' show Database;

import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/coach_service.dart';
import '../../domain/coach/insight_contracts.dart';
import '../../domain/repositories.dart';
import 'coach_repository_impl.dart';
import 'coach_store.dart';
import 'in_memory_coach_repository.dart';
import 'insight_service_impl.dart';
import 'secret_store.dart';
import 'sqlite_coach_store.dart';

class CoachModule {
  CoachModule({
    required this.repository,
    required this.service,
    required this.insights,
  });

  final CoachRepositoryImpl repository;
  final CoachService service;
  final InsightServiceImpl insights;

  CoachRepository get coach => repository;
  InsightService get insightService => insights;

  /// The app: the shared (lazily opened) database + the Android keystore.
  factory CoachModule.sqlite(
    HealthRepository health,
    Future<Database> Function() db, {
    SecretStore secrets = const SecureSecretStore(),
  }) {
    final store = SqliteCoachStore(db);
    final repo = CoachRepositoryImpl(store: store, secrets: secrets);
    return CoachModule._compose(health, repo, store);
  }

  /// Tests, goldens, evals: memory stores, the offline engine by default.
  factory CoachModule.inMemory(
    HealthRepository health, {
    DateTime Function()? clock,
    CoachSettings settings = const CoachSettings(),
    LlmClientFactory? clients,
    Map<CoachProvider, String> keys = const {},
  }) {
    final repo = InMemoryCoachRepository(
      settings: settings,
      clock: clock,
      clients: clients,
      keys: keys,
    );
    return CoachModule._compose(health, repo, repo.memoryStore, clock: clock);
  }

  factory CoachModule._compose(
    HealthRepository health,
    CoachRepositoryImpl repo,
    CoachStore store, {
    DateTime Function()? clock,
  }) => CoachModule(
    repository: repo,
    service: CoachServiceImpl(health: health, coach: repo, clock: clock),
    insights: InsightServiceImpl(
      health: health,
      coach: repo,
      store: store,
      clock: clock,
    ),
  );
}
