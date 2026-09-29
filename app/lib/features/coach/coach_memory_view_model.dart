// "What Coach knows": the confirmed memories, the memory switch, add / edit
// / delete one, delete all.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform_services.dart';
import '../../app/providers.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/day_key.dart';
import 'coach_providers.dart';

class CoachMemoryState {
  const CoachMemoryState({required this.facts, required this.enabled});
  final List<MemoryFact> facts;
  final bool enabled;

  /// The categories that hold a fact, in the contract's order.
  List<(MemoryCategory, List<MemoryFact>)> get groups => [
    for (final c in MemoryCategory.values)
      if (facts.any((f) => f.category == c))
        (
          c,
          [
            for (final f in facts)
              if (f.category == c) f,
          ],
        ),
  ];

  /// True once a temporary fact's day has passed (the coach stops using it).
  static bool expired(MemoryFact f, String today) =>
      f.expiresOn != null && f.expiresOn!.compareTo(today) < 0;
}

class CoachMemoryViewModel extends AsyncNotifier<CoachMemoryState> {
  @override
  Future<CoachMemoryState> build() async {
    final repo = ref.watch(coachRepositoryProvider);
    final facts = await repo.memories();
    final on = await repo.memoryEnabled();
    return CoachMemoryState(
      facts: [...facts]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      enabled: on,
    );
  }

  CoachRepository get _repo => ref.read(coachRepositoryProvider);
  String get today => DayKey.of(ref.read(clockProvider)());

  Future<bool> _run(Future<void> Function() job) async {
    try {
      await job();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (ref.mounted) {
        ref.invalidateSelf();
        ref.invalidate(coachConfigProvider);
      }
    }
  }

  Future<bool> add(String text, MemoryCategory category, String? until) {
    final t = text.trim();
    if (t.isEmpty) return Future.value(false);
    return _run(() => _repo.addMemory(t, category: category, expiresOn: until));
  }

  Future<bool> edit(
    String id,
    String text,
    MemoryCategory category,
    String? until,
  ) {
    final t = text.trim();
    if (t.isEmpty) return Future.value(false);
    return _run(
      () => _repo.updateMemory(id, t, category: category, expiresOn: until),
    );
  }

  Future<bool> delete(String id) => _run(() => _repo.deleteMemory(id));

  Future<bool> deleteAll() => _run(() async {
    for (final f in await _repo.memories()) {
      await _repo.deleteMemory(f.id);
    }
  });

  Future<bool> setEnabled(bool on) async {
    final cur = state.value;
    if (cur != null) {
      state = AsyncData(CoachMemoryState(facts: cur.facts, enabled: on));
    }
    return _run(() => _repo.setMemoryEnabled(on));
  }
}

final coachMemoryProvider =
    AsyncNotifierProvider.autoDispose<CoachMemoryViewModel, CoachMemoryState>(
      CoachMemoryViewModel.new,
      retry: noRetry,
    );
