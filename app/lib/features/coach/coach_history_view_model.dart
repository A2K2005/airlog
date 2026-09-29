// Conversations: the stored list, delete one, delete all.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform_services.dart';
import '../../app/providers.dart';
import '../../domain/coach/coach_contracts.dart';

class CoachHistoryViewModel extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    final list = await ref.watch(coachRepositoryProvider).conversations();
    return [...list]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  CoachRepository get _repo => ref.read(coachRepositoryProvider);

  Future<bool> delete(String id) async {
    final cur = state.value;
    if (cur != null) {
      state = AsyncData([
        for (final c in cur)
          if (c.id != id) c,
      ]);
    }
    try {
      await _repo.deleteConversation(id);
      return true;
    } catch (_) {
      if (ref.mounted) ref.invalidateSelf();
      return false;
    }
  }

  Future<bool> deleteAll() async {
    try {
      await _repo.deleteAllConversations();
      if (ref.mounted) state = const AsyncData([]);
      return true;
    } catch (_) {
      if (ref.mounted) ref.invalidateSelf();
      return false;
    }
  }
}

final coachHistoryProvider =
    AsyncNotifierProvider.autoDispose<
      CoachHistoryViewModel,
      List<Conversation>
    >(CoachHistoryViewModel.new, retry: noRetry);
