// What Coach knows (pushed): the facts the user confirmed, grouped by the
// seven categories. Add, edit (with an optional "until" day for a temporary
// fact) and delete; the memory switch; delete all. Never health numbers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/copy.dart';
import '../../app/providers.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/personal_context.dart';
import '../../domain/day_key.dart';
import 'coach_memory_view_model.dart';

class CoachMemoryScreen extends ConsumerWidget {
  const CoachMemoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = P.of(context);
    final async = ref.watch(coachMemoryProvider);
    final vm = ref.read(coachMemoryProvider.notifier);
    final s = async.value;
    final today = DayKey.of(ref.watch(currentTimeProvider));

    Future<void> edit([MemoryFact? f]) async {
      final r = await showFactSheet(context, fact: f, today: today);
      if (r == null) return;
      final ok = f == null
          ? await vm.add(r.text, r.category, r.until)
          : await vm.edit(f.id, r.text, r.category, r.until);
      if (context.mounted && !ok) snack(context, 'Could not save. Try again.');
    }

    Future<void> deleteAll() async {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: dialogMotion(context),
        builder: (d) => AlertDialog(
          title: const Text('Delete every memory?'),
          content: const Text(
            'Coach forgets everything you confirmed. Your chats stay. It '
            'cannot be undone.',
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
        snack(context, ok ? 'All memories deleted.' : 'Could not delete.');
      }
    }

    final List<Widget> body;
    if (s == null && async.hasError) {
      body = [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load memories',
          body: 'The memories stored on this phone could not be read.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(coachMemoryProvider),
        ),
      ];
    } else if (s == null) {
      body = const [AppCard(child: SkeletonLines(lines: 4))];
    } else {
      body = [
        AppCard(
          tone: CardTone.inset,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: p.ink2),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(
                  CoachCopy.memoryAbout,
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        AppCard(
          padding: const EdgeInsets.fromLTRB(S.card, S.x2, S.x3, S.x2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Use memories', style: F.head.copyWith(color: p.ink)),
                    const SizedBox(height: 2),
                    Text(
                      s.enabled
                          ? 'Coach may use these facts and suggest new ones.'
                          : 'Off: Coach never reads these or suggests new '
                                'ones.',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: 'Use memories',
                child: Switch(value: s.enabled, onChanged: vm.setEnabled),
              ),
            ],
          ),
        ),
        if (s.facts.isEmpty) ...[
          const SizedBox(height: S.x3),
          const EmptyState(
            icon: Icons.bookmark_border_rounded,
            title: 'Nothing yet',
            body:
                'When Coach offers to remember something, it appears here '
                'only after you tap Remember. You can add a fact yourself '
                'too.',
          ),
        ],
        for (final (cat, facts) in s.groups) ...[
          const SizedBox(height: S.x5),
          OverLabel(cat.label),
          const SizedBox(height: S.x2),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: S.x1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < facts.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: S.hair, color: p.line),
                  _FactRow(
                    key: ValueKey('fact-${facts[i].id}'),
                    fact: facts[i],
                    today: today,
                    onEdit: () => edit(facts[i]),
                    onDelete: () async {
                      final ok = await vm.delete(facts[i].id);
                      if (context.mounted) {
                        snack(context, ok ? 'Forgotten.' : 'Could not delete.');
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: S.x5),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Add a fact',
            icon: Icons.add_rounded,
            kind: AppButtonKind.secondary,
            onTap: () => edit(),
          ),
        ),
        if (s.facts.isNotEmpty) ...[
          const SizedBox(height: S.x4),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Delete all memories',
              icon: Icons.delete_outline_rounded,
              kind: AppButtonKind.quiet,
              accent: C.recRed,
              onTap: deleteAll,
            ),
          ),
        ],
      ];
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text('What Coach knows'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: body,
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    super.key,
    required this.fact,
    required this.today,
    required this.onEdit,
    required this.onDelete,
  });

  final MemoryFact fact;
  final String today;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final until = fact.expiresOn;
    final ended = CoachMemoryState.expired(fact, today);
    final confirmed = DayKey.of(fact.updatedAt ?? fact.createdAt);
    final needsReview = MemoryContext.needsReview(fact, today);
    final note = ended
        ? 'Ended ${shortDay(until!)} · no longer used'
        : 'Confirmed ${shortDay(confirmed)}'
              '${until == null ? '' : ' · Until ${shortDay(until)}'}'
              '${needsReview ? ' · Review whether this still applies' : ''}';
    return Row(
      children: [
        Expanded(
          child: Pressable(
            onTap: onEdit,
            scale: .985,
            semanticLabel: '${fact.text}. $note. Edit',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.card, S.x3, 0, S.x3),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fact.text,
                        style: F.body.copyWith(color: ended ? p.ink3 : p.ink),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          note,
                          style: F.tab(F.cap).copyWith(color: p.ink3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AppIconButton(
          icon: Icons.delete_outline_rounded,
          semanticLabel: 'Forget “${fact.text}”',
          color: p.ink2,
          onTap: onDelete,
        ),
        const SizedBox(width: S.x1),
      ],
    );
  }
}

/// The add / edit sheet's result.
typedef FactDraft = ({String text, MemoryCategory category, String? until});

Future<FactDraft?> showFactSheet(
  BuildContext context, {
  MemoryFact? fact,
  required String today,
}) => showModalBottomSheet<FactDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: sheetMotion(context),
  builder: (_) => _FactSheet(fact: fact, today: today),
);

class _FactSheet extends StatefulWidget {
  const _FactSheet({required this.fact, required this.today});
  final MemoryFact? fact;
  final String today;

  @override
  State<_FactSheet> createState() => _FactSheetState();
}

class _FactSheetState extends State<_FactSheet> {
  late final _text = TextEditingController(text: widget.fact?.text ?? '');
  late MemoryCategory _cat =
      widget.fact?.category ?? MemoryCategory.preferences;
  late String? _until = widget.fact?.expiresOn;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickUntil() async {
    final start = DayKey.start(widget.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: _until == null
          ? DateTime(start.year, start.month, start.day + 7)
          : _until!.compareTo(widget.today) < 0
          ? start
          : DayKey.start(_until!),
      firstDate: start,
      lastDate: DateTime(start.year + 2, start.month, start.day),
    );
    if (picked != null) setState(() => _until = DayKey.of(picked));
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x5, S.gutter, S.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.fact == null ? 'Add a fact' : 'Edit fact',
                style: F.t1.copyWith(color: p.ink),
              ),
            ),
            const SizedBox(height: S.x1),
            Text(
              'Something about you, not a number: a goal, an event, a '
              'preference.',
              style: F.bodySm.copyWith(color: p.ink2),
            ),
            const SizedBox(height: S.x4),
            TextField(
              key: const ValueKey('fact-text'),
              controller: _text,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: F.body.copyWith(color: p.ink),
              decoration: const InputDecoration(
                labelText: 'Fact',
                hintText: 'e.g. Training for a half marathon',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: S.x4),
            const OverLabel('Category'),
            const SizedBox(height: S.x1),
            Wrap(
              spacing: S.x2,
              children: [
                for (final c in MemoryCategory.values)
                  Pressable(
                    key: ValueKey('cat-${c.name}'),
                    onTap: () => setState(() => _cat = c),
                    selected: c == _cat,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: S.x3,
                        vertical: S.x1 + 2,
                      ),
                      decoration: BoxDecoration(
                        color: c == _cat ? p.ink : C.clear,
                        borderRadius: R.rPill,
                        border: Border.all(color: c == _cat ? p.ink : p.line),
                      ),
                      child: Text(
                        c.label,
                        style: F.cap.copyWith(
                          color: c == _cat ? p.inkInverse : p.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: S.x3),
            const OverLabel('Until (optional)'),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _until == null
                        ? 'No end: kept until you delete it'
                        : 'Used until ${shortDay(_until!)}',
                    style: F.tab(F.bodySm).copyWith(color: p.ink2),
                  ),
                ),
                AppButton(
                  label: _until == null ? 'Pick a day' : 'Change',
                  kind: AppButtonKind.quiet,
                  compact: true,
                  onTap: _pickUntil,
                ),
                if (_until != null) ...[
                  const SizedBox(width: S.x3),
                  AppButton(
                    label: 'Clear',
                    kind: AppButtonKind.quiet,
                    compact: true,
                    onTap: () => setState(() => _until = null),
                  ),
                ],
              ],
            ),
            const SizedBox(height: S.x4),
            AppButton(
              label: 'Save',
              expand: true,
              onTap: _text.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop((
                      text: _text.text.trim(),
                      category: _cat,
                      until: _until,
                    )),
            ),
          ],
        ),
      ),
    );
  }
}
