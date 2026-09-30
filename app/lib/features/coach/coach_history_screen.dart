// Conversations (pushed): a search field, the chats grouped as topic cards
// (Sleep, Recovery, Training, Journal, General, each with its count and
// latest day; a topic comes from the tools a chat's answers used), then the
// list, newest first, filtered by the chosen topic and the search. Swipe or
// tap the bin to delete one; "Delete all" asks first. Tapping a chat
// reopens it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart';
import '../../app/route_names.dart';
import '../../app/screen_kit.dart' show IconBadge;
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/topics.dart';
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
    final s = async.value;
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
        snack(context, ok ? 'Conversation deleted.' : 'Couldn’t delete it.');
      }
    }

    Future<void> deleteAll() async {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: dialogMotion(context),
        builder: (d) => AlertDialog(
          title: const Text('Delete every conversation?'),
          content: const Text(
            'Every chat on this phone will be deleted. What Coach knows '
            'stays. This can’t be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(
                'Delete all chats',
                style: F.head.copyWith(color: P.of(d).on(C.recRed)),
              ),
            ),
          ],
        ),
      );
      if (yes != true) return;
      final ok = await vm.deleteAll();
      if (context.mounted) {
        snack(context, ok ? 'All conversations deleted.' : 'Couldn’t delete.');
      }
    }

    final List<Widget> body;
    if (s == null && async.hasError) {
      body = [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Couldn’t load conversations',
          body: 'Airlog couldn’t open your saved chats.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(coachHistoryProvider),
        ),
      ];
    } else if (s == null) {
      body = const [AppCard(child: SkeletonLines(lines: 3))];
    } else if (s.items.isEmpty) {
      body = const [
        EmptyState(
          icon: Icons.forum_outlined,
          title: 'No conversations',
          body: 'Chats with the coach are kept here, on this phone only.',
        ),
      ];
    } else {
      final groups = s.byTopic;
      final shown = s.shown;
      final topics = groups.keys.toList();
      body = [
        TextField(
          key: const ValueKey('history-search'),
          onChanged: vm.search,
          textInputAction: TextInputAction.search,
          style: F.body.copyWith(color: p.ink),
          decoration: InputDecoration(
            hintText: 'Search chats',
            hintStyle: F.body.copyWith(color: p.ink3),
            prefixIcon: Icon(Icons.search_rounded, color: p.ink3),
            isDense: true,
            filled: true,
            fillColor: p.card,
            border: OutlineInputBorder(
              borderRadius: R.rLg,
              borderSide: BorderSide(color: p.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: R.rLg,
              borderSide: BorderSide(color: p.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: R.rLg,
              borderSide: BorderSide(color: p.ink2),
            ),
          ),
        ),
        const SizedBox(height: S.x4),
        for (var i = 0; i < topics.length; i += 2) ...[
          if (i > 0) const SizedBox(height: S.x3),
          EnterFade(
            index: i ~/ 2,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _TopicCard(
                      topic: topics[i],
                      chats: groups[topics[i]]!,
                      selected: s.topic == topics[i],
                      onTap: () => vm.pickTopic(topics[i]),
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: i + 1 < topics.length
                        ? _TopicCard(
                            topic: topics[i + 1],
                            chats: groups[topics[i + 1]]!,
                            selected: s.topic == topics[i + 1],
                            onTap: () => vm.pickTopic(topics[i + 1]),
                          )
                        : const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: S.x6),
        Row(
          children: [
            Expanded(
              child: OverLabel(
                s.topic == null ? 'Recent' : '${s.topic!.label} chats',
              ),
            ),
            if (s.topic != null)
              AppButton(
                key: const ValueKey('history-all'),
                label: 'Show all',
                kind: AppButtonKind.quiet,
                compact: true,
                onTap: () => vm.pickTopic(s.topic!),
              ),
          ],
        ),
        const SizedBox(height: S.x2),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x4),
            child: Text(
              'No chats match.',
              style: F.bodySm.copyWith(color: p.ink2),
            ),
          ),
        for (final item in shown)
          Padding(
            key: ValueKey('conv-${item.conversation.id}'),
            padding: const EdgeInsets.only(bottom: S.x2),
            child: _ChatRow(
              item: item,
              onOpen: () => open(item.conversation),
              onDelete: () => delete(item.conversation),
            ),
          ),
        const SizedBox(height: S.x2),
        Text(
          'Stored on this phone only. Deleting a chat never deletes what '
          'Coach knows.',
          style: F.cap.copyWith(color: p.ink3),
        ),
      ];
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text('Conversations'),
        // Part of the chat: no data-mode label (shown app-wide).
        actions: [
          AppIconButton(
            icon: Icons.delete_sweep_outlined,
            semanticLabel: 'Delete all chats',
            onTap: s == null || s.items.isEmpty ? null : deleteAll,
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

/// One topic: its icon, name, count in dots and latest day.
class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.chats,
    required this.selected,
    required this.onTap,
  });

  final ChatTopic topic;
  final List<CoachChatItem> chats;
  final bool selected;
  final VoidCallback onTap;

  static (IconData, Color?) lookOf(ChatTopic t) => switch (t) {
    ChatTopic.sleep => (Icons.bedtime_outlined, C.sleep),
    ChatTopic.recovery => (Icons.favorite_border_rounded, C.recGreen),
    ChatTopic.training => (Icons.bolt_rounded, C.strain),
    ChatTopic.journal => (Icons.edit_note_rounded, C.lime),
    ChatTopic.general => (Icons.auto_awesome_outlined, null),
  };

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final (icon, accent) = lookOf(topic);
    final n = chats.length;
    final latest = chats.first.conversation.updatedAt;
    final day = shortDay(DayKey.of(latest));
    return Pressable(
      key: ValueKey('topic-${topic.name}'),
      onTap: onTap,
      selected: selected,
      scale: .98,
      semanticLabel:
          '${topic.label}: $n ${n == 1 ? 'chat' : 'chats'}, latest $day. '
          '${selected ? 'Showing these. Tap to show all.' : 'Show these.'}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(S.x4),
          decoration: BoxDecoration(
            color: selected && accent != null
                ? Color.alphaBlend(p.wash(accent), p.card)
                : p.card,
            borderRadius: R.rCard,
            border: Border.all(
              color: selected ? p.ink : p.line,
              width: selected ? 2 : S.hair,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(icon: icon, accent: accent, size: 32),
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      DotMatrixNumber('$n', style: F.dot28, color: p.ink),
                      const SizedBox(width: S.x1),
                      Text(
                        n == 1 ? 'chat' : 'chats',
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              Text(
                topic.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.head.copyWith(color: p.ink),
              ),
              const SizedBox(height: 2),
              Text(
                'Latest $day',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.tab(F.cap).copyWith(color: p.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One chat: its title, topic and time; swipe or the bin deletes it.
class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.item,
    required this.onOpen,
    required this.onDelete,
  });

  final CoachChatItem item;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final c = item.conversation;
    final meta =
        '${item.topic.label} · ${CoachHistoryScreen.when(c.updatedAt)}';
    return Dismissible(
      key: ValueKey('dismiss-${c.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: S.x5),
        decoration: BoxDecoration(
          color: p.wash(C.recRed),
          borderRadius: R.rCard,
        ),
        child: Icon(Icons.delete_outline_rounded, color: p.on(C.recRed)),
      ),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(S.card, S.x1, S.x1, S.x1),
        child: Row(
          children: [
            Expanded(
              child: Pressable(
                onTap: onOpen,
                scale: .985,
                semanticLabel: '${c.title}, $meta. Opens the chat',
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
                          meta,
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
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
