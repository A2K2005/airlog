// In-memory CoachRepository for tests, goldens and evals: the real
// CoachRepositoryImpl over MemoryCoachStore + MemorySecretStore (no
// sqflite, no keystore, no network unless a client factory adds one).

import '../../domain/coach/coach_contracts.dart';
import 'coach_repository_impl.dart';
import 'coach_store.dart';
import 'secret_store.dart';

class InMemoryCoachRepository extends CoachRepositoryImpl {
  InMemoryCoachRepository({
    CoachSettings settings = const CoachSettings(),
    super.clock,
    super.clients,
    Map<CoachProvider, String> keys = const {},
  }) : super(
         store: MemoryCoachStore(),
         secrets: MemorySecretStore()
           ..values.addAll({
             for (final e in keys.entries)
               CoachRepositoryImpl.secretKeyFor(e.key): e.value,
           }),
         initialSettings: settings,
       );

  MemoryCoachStore get memoryStore => store as MemoryCoachStore;
  MemorySecretStore get memorySecrets => secrets as MemorySecretStore;
}
