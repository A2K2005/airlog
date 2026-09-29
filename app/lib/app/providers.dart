// Composition root for dependency injection (Riverpod).
//
// CONTRACT FILE — the only place features/ get their dependencies from.
// main.dart overrides the two root providers with the real data layer;
// tests override them with fakes. Additive changes only.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/coach/coach_contracts.dart';
import '../domain/coach/insight_contracts.dart';
import '../domain/day_key.dart';
import '../domain/repositories.dart';

/// Root data dependency. Overridden in main.dart (and in tests).
final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => throw UnimplementedError('healthRepositoryProvider not overridden'),
);

/// Live Bluetooth heart rate. Overridden in main.dart (and in tests).
final liveHrServiceProvider = Provider<LiveHrService>(
  (ref) => throw UnimplementedError('liveHrServiceProvider not overridden'),
);

/// Repository revision. View-models `ref.watch` this to reload after sync.
final revisionProvider = StreamProvider<int>((ref) async* {
  final repo = ref.watch(healthRepositoryProvider);
  yield repo.revision;
  yield* repo.revisions;
});

/// Sync state for the freshness line and pull-to-refresh.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final repo = ref.watch(healthRepositoryProvider);
  yield repo.syncStatus;
  yield* repo.syncStatusChanges;
});

/// Newest day with data (null when the store is empty).
final latestDateProvider = FutureProvider<String?>((ref) async {
  ref.watch(revisionProvider);
  return ref.watch(healthRepositoryProvider).latestDate();
});

/// The day Today / Sleep / Strain are showing. null = follow the latest day.
class SelectedDate extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? date) => state = date;

  void shift(int days, {required String latest}) {
    final base = state ?? latest;
    final next = DayKey.add(base, days);
    state = next.compareTo(latest) >= 0 ? null : next;
  }
}

final selectedDateProvider = NotifierProvider<SelectedDate, String?>(
  SelectedDate.new,
);

/// The resolved date key the day screens should render.
final focusedDateProvider = FutureProvider<String?>((ref) async {
  final picked = ref.watch(selectedDateProvider);
  if (picked != null) return picked;
  return ref.watch(latestDateProvider.future);
});

/// Demo vs live, for the persistent DemoBadge in the shell. [ui, additive]
/// Re-read on every revision bump (switching mode is expected to bump it).
final dataModeProvider = Provider<DataMode>((ref) {
  ref.watch(revisionProvider);
  return ref.watch(healthRepositoryProvider).mode;
});

/// The wall clock. Screens read "today", "12 min ago" and the evening journal
/// prompt from it, never from `DateTime.now()` directly, so tests and goldens
/// can pin time (override with the same `now` the demo repository uses).
/// [screens, additive]
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Shell tab indices, in NavigationBar order (see app/shell.dart `AppTab`).
/// [screens, additive]
abstract final class ShellTabs {
  static const today = 0;
  static const sleep = 1;
  static const strain = 2;
  static const trends = 3;
}

/// A request from a screen to switch the shell's tab (e.g. Today's Sleep ring
/// opens the Sleep tab). [seq] makes two requests for the same tab distinct.
/// [screens, additive]
class TabRequest {
  const TabRequest(this.index, this.seq);
  final int index;
  final int seq;
}

class TabRequests extends Notifier<TabRequest?> {
  @override
  TabRequest? build() => null;

  /// Asks the shell to show tab [index] (a [ShellTabs] value).
  void go(int index) => state = TabRequest(index, (state?.seq ?? 0) + 1);
}

/// The shell listens and switches tabs (no animation). [screens, additive]
final tabRequestProvider = NotifierProvider<TabRequests, TabRequest?>(
  TabRequests.new,
);

// ── AI coach (overridden in main.dart; tests override with fakes) ─────────

/// Coach persistence: settings, API keys (secure storage), chats, memory.
final coachRepositoryProvider = Provider<CoachRepository>(
  (ref) => throw UnimplementedError('coachRepositoryProvider not overridden'),
);

/// The ask/suggest use case the Coach screens call.
final coachServiceProvider = Provider<CoachService>(
  (ref) => throw UnimplementedError('coachServiceProvider not overridden'),
);

/// Proactive insight cards (Today feed, Sleep/Strain/Health). Overridden in
/// main.dart; see domain/coach/insight_contracts.dart for the rules.
final insightServiceProvider = Provider<InsightService>(
  (ref) => throw UnimplementedError('insightServiceProvider not overridden'),
);
