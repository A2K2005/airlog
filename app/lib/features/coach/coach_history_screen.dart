// Conversations (pushed): every stored chat, newest first. Swipe or tap the
// bin to delete one; "Delete all" asks first. Tapping a chat reopens it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/day_key.dart';
import 'coach_history_view_model.dart';

/// Route arguments: opened from the chat, a tap returns the conversation id
/// to it instead of opening a new chat page.
enum CoachHistoryArgs { pick }

class CoachHistoryScreen extends ConsumerWidget {
  const CoachHistoryScreen({super.key});

  static String when(DateTime t) => '${shortDay(DayKey.of(t))} · ${clockOf(t)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = P.of(context);
    final async = ref.watch(coachHistoryProvider);
    final vm = ref.read(coachHistoryProvider.notifier);
    final list = async.value;
    final pick =
        ModalRoute.of(context)?.settings.arguments == CoachHistoryArgs.pick;

    void open(Conversation c) {
      if (pick) {
        Navigator.of(context).pop(c.id);
      } else {
        Navigator.of(context).pushReplacementNamed(
          Routes.coach,
          arguments: CoachArgs(conversationId: c.id),
        );
      }
    }

    Future<void> delete(Conversation c) async {
      final ok = await vm.delete(c.id);
      if (context.mounted) {
        snack(context, ok ? 'Conversation deleted.' : 'Could not delete it.');
      }
    }

    Future<void> deleteAll() async {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: dialogMotion(context),
        builder: (d) => AlertDialog(
          title: const Text('Delete every conversation?'),
          content: const Text(
            'Every chat stored on this phone is erased. What Coach knows '
            '(your confirmed memories) stays. It cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(
                'Delete all',
                style: F.head.copyWith(color: P.of(d).on(C.recRed)),
              ),
            ),
          ],
        ),
      );
      if (yes != true) return;
      final ok = await vm.deleteAll();
      if (context.mounted) {
        snack(context, ok ? 'All conversations deleted.' : 'Could not delete.');
      }
    }

    final List<Widget> body;
    if (list == null && async.hasError) {
      body = [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load conversations',
          body: 'The chats stored on this phone could not be read.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(coachHistoryProvider),
        ),
      ];
    } else if (list == null) {
      body = const [AppCard(child: SkeletonLines(lines: 3))];
    } else if (list.isEmpty) {
      body = const [
        EmptyState(
          icon: Icons.forum_outlined,
          title: 'No conversations',
          body: 'Chats with the coach are kept here, on this phone only.',
        ),
      ];
    } else {
      body = [
        Text(
          'Stored on this phone only. Deleting a chat never deletes what '
          'Coach knows.',
          style: F.bodySm.copyWith(color: p.ink2),
        ),
        const SizedBox(height: S.x3),
        for (final c in list)
          Padding(
            key: ValueKey('conv-${c.id}'),
            padding: const EdgeInsets.only(bottom: S.x2),
            child: Dismissible(
              key: ValueKey('dismiss-${c.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => delete(c),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: S.x5),
                decoration: BoxDecoration(
                  color: p.wash(C.recRed),
                  borderRadius: R.rCard,
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: p.on(C.recRed),
                ),
              ),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(S.card, S.x1, S.x1, S.x1),
                child: Row(
                  children: [
                    Expanded(
                      child: Pressable(
                        onTap: () => open(c),
                        scale: .985,
                        semanticLabel:
                            '${c.title}, ${when(c.updatedAt)}. Opens the chat',
                        child: ExcludeSemantics(
                          child: SizedBox(
                            width: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: F.head.copyWith(color: p.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  when(c.updatedAt),
                                  style: F.tab(F.cap).copyWith(color: p.ink3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.delete_outline_rounded,
                      semanticLabel: 'Delete ${c.title}',
                      color: p.ink2,
                      onTap: () => delete(c),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ];
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text('Conversations'),
        actions: [
          ...SampleDataChip.action(context),
          AppIconButton(
            icon: Icons.delete_sweep_outlined,
            semanticLabel: 'Delete all conversations',
            onTap: list == null || list.isEmpty ? null : deleteAll,
          ),
          const SizedBox(width: S.x2),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: body,
      ),
    );
  }
}
