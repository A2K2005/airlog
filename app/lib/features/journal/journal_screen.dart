// Journal (pushed; owns its Scaffold). Tag the evening in a few taps (saved
// immediately), then see which habits are associated with the next
// morning's Recovery in your own data: clear links as tiles with the gap in
// dot matrix, maybes as rows, and the habits that need more days as chips.
// The caveat and the method live behind ⓘ.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/screen_kit.dart' show IconBadge, InfoButton;
import '../../design/design.dart';
import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/results.dart';
import 'journal_view_model.dart';

class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = P.of(context);
    final async = ref.watch(journalViewModelProvider);
    final vm = ref.read(journalViewModelProvider.notifier);
    final s = async.value;

    final List<Widget> body;
    if (s != null) {
      body = _content(context, s, vm);
    } else if (async.hasError) {
      body = [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Couldn’t open the journal',
          body: 'Airlog couldn’t open your saved entries. Nothing was changed.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(journalViewModelProvider),
        ),
      ];
    } else {
      body = const [
        AppCard(child: SkeletonLines(lines: 4)),
        SizedBox(height: S.x4),
        AppCard(child: SkeletonLines(lines: 3)),
      ];
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text('Journal'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x1, S.gutter, S.x12),
        children: body,
      ),
    );
  }

  static IconData iconFor(JournalFactor f) => switch (f) {
    JournalFactor.alcohol => Icons.wine_bar_outlined,
    JournalFactor.lateCaffeine => Icons.coffee_outlined,
    JournalFactor.lateMeal => Icons.restaurant_outlined,
    JournalFactor.stress => Icons.psychology_alt_outlined,
    JournalFactor.sick => Icons.sick_outlined,
    JournalFactor.screenBeforeBed => Icons.smartphone_outlined,
    JournalFactor.exercised => Icons.fitness_center_outlined,
    JournalFactor.travel => Icons.flight_outlined,
    JournalFactor.meditation => Icons.self_improvement_outlined,
  };

  static const _min = JournalViewModel.minDays;

  List<Widget> _content(
    BuildContext context,
    JournalState s,
    JournalViewModel vm,
  ) {
    final p = P.of(context);
    final n = s.entry.factors.length;
    const caveat = InfoButton(
      title: 'A link, not a cause',
      lede:
          'These are differences in your own data, not proof that one thing '
          'causes another. Other things often change on the same days.',
      footnote: ExplainSheet.defaultFootnote,
      children: [
        ExplainSection(
          title: 'Clear and Maybe',
          body:
              '“Clear” means the gap is more than twice its likely error '
              '(Welch’s test). “Maybe” has enough days, but the gap could '
              'still be chance.',
        ),
        ExplainSection(
          title: 'How many days',
          body:
              'Each habit needs $_min tagged days with it and $_min without, '
              'each followed by a Recovery score.',
        ),
      ],
    );
    return [
      Center(
        child: DaySwitcher(
          date: s.date,
          latest: s.today,
          today: s.clockDay ?? s.today,
          onShift: vm.shift,
        ),
      ),
      if (s.week.length == 7)
        Padding(
          padding: const EdgeInsets.only(top: S.x3),
          child: Center(child: consistencyTile(s)),
        ),
      const SizedBox(height: S.x4),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      s.isToday
                          ? 'What happened this evening?'
                          : 'What happened that evening?',
                      style: F.t2.copyWith(color: p.ink),
                    ),
                  ),
                ),
                const InfoButton(
                  title: 'Tagging your evening',
                  children: [
                    ExplainSection(
                      title: 'How it works',
                      body:
                          'Tap all that fit. Airlog checks each one against '
                          'your Recovery the next morning.',
                    ),
                    ExplainSection(
                      title: 'Ordinary evenings count',
                      body:
                          'Tag the ordinary evenings too. Patterns need days '
                          'with and without each habit.',
                    ),
                  ],
                ),
              ],
            ),
            Text(
              'Tap all that fit.',
              style: F.bodySm.copyWith(color: p.ink2),
            ),
            const SizedBox(height: S.x4),
            Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              children: [
                for (final f in JournalFactor.values)
                  FactorChip(
                    key: ValueKey('factor-${f.name}'),
                    label: f.label,
                    icon: iconFor(f),
                    selected: s.entry.factors.contains(f),
                    onTap: () => vm.toggle(f),
                  ),
              ],
            ),
            const SizedBox(height: S.x4),
            Row(
              children: [
                Icon(
                  s.saveError
                      ? Icons.error_outline_rounded
                      : Icons.lock_outline_rounded,
                  size: 14,
                  color: s.saveError ? p.on(C.amber) : p.ink3,
                ),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(
                    s.saveError
                        ? 'Couldn’t save that. Tap it again.'
                        : n == 0
                        ? 'Saved on this phone as you tap.'
                        : '$n tagged · saved on this phone',
                    style: F
                        .tab(F.cap)
                        .copyWith(color: s.saveError ? p.on(C.amber) : p.ink3),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: S.x8),
      const Row(
        children: [
          Expanded(child: SectionHeader(title: 'What moves your Recovery')),
          caveat,
        ],
      ),
      Text(
        'A link, not a cause.',
        style: F.bodySm.copyWith(color: p.ink2),
      ),
      const SizedBox(height: S.x3),
      if (!s.hasInsights)
        const AppCard(
          child: EmptyState(
            icon: Icons.insights_outlined,
            title: 'Patterns take a few weeks',
            body:
                'Each habit needs $_min tagged days with it and $_min without, '
                'each followed by a Recovery score. Keep tagging your '
                'evenings, even the ordinary ones.',
          ),
        )
      else ...[
        if (s.solid.isEmpty)
          Text(
            'No clear links yet. So far, every difference could be chance.',
            style: F.bodySm.copyWith(color: p.ink2),
          )
        else
          for (var i = 0; i < s.solid.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x3),
            InsightTile(insight: s.solid[i]),
          ],
        if (s.emerging.isNotEmpty) ...[
          const SizedBox(height: S.x6),
          const SectionHeader(
            title: 'Maybe',
            subtitle: 'Enough days, but it could still be chance',
          ),
          const SizedBox(height: S.x3),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < s.emerging.length; i++) ...[
                  if (i > 0) Divider(height: S.x5, color: p.line),
                  InsightRow(insight: s.emerging[i]),
                ],
              ],
            ),
          ),
        ],
      ],
      if (s.hasInsights && s.missing.isNotEmpty) ...[
        const SizedBox(height: S.x6),
        const OverLabel('Not enough days yet'),
        const SizedBox(height: S.x2),
        Wrap(
          spacing: S.x2,
          runSpacing: S.x2,
          children: [
            for (final f in s.missing)
              MetricChip(
                label: f.label,
                icon: iconFor(f),
                style: MetricChipStyle.muted,
              ),
          ],
        ),
        const SizedBox(height: S.x2),
        Text(
          'Each needs $_min days with it and $_min without.',
          style: F.cap.copyWith(color: p.ink3),
        ),
      ],
    ];
  }
}

/// A factor toggle: tinted and ticked when on. Press feedback only.
class FactorChip extends StatelessWidget {
  const FactorChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final fill = p.fill(DomainColors.sleep);
    final ink = selected ? p.onFill(DomainColors.sleep) : p.ink;
    return Pressable(
      selected: selected,
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: S.x3,
          vertical: S.x2 + 2,
        ),
        decoration: BoxDecoration(
          color: selected ? fill : p.card2,
          borderRadius: R.rPill,
          border: Border.all(color: selected ? fill : p.line),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? Icons.check_rounded : icon, size: 17, color: ink),
              const SizedBox(width: S.x2),
              Flexible(
                child: Text(
                  label,
                  style: F.bodySm.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sentence for an insight, with the gap in the tone's ink.
Widget _sentence(BuildContext context, FactorInsight i, Color? tone) {
  final p = P.of(context);
  final d = i.delta.round();
  if (d == 0) {
    return Text(
      JournalMapper.headline(i),
      style: F.head.copyWith(color: p.ink),
    );
  }
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '${i.factor.label} is associated with '),
        TextSpan(
          text:
              '${d.abs()} ${d.abs() == 1 ? 'point' : 'points'} '
              '${d > 0 ? 'higher' : 'lower'}',
          style: TextStyle(color: tone ?? p.ink),
        ),
        const TextSpan(text: ' Recovery the next day.'),
      ],
    ),
    style: F.tab(F.head).copyWith(color: p.ink),
  );
}

/// A clear link as its own tile: the gap in dot matrix, the sentence, and
/// the two averages as bars on one 0–100 scale.
class InsightTile extends StatelessWidget {
  const InsightTile({super.key, required this.insight});
  final FactorInsight insight;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final i = insight;
    final d = i.delta.round();
    final tone = d < 0 ? C.amber : C.health;
    Widget bar(String label, double v, Color c) => Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: F.cap.copyWith(color: p.ink3)),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                width: box.maxWidth * (v / 100).clamp(.02, 1.0),
                height: 6,
                decoration: BoxDecoration(color: c, borderRadius: R.rPill),
              ),
            ),
          ),
        ),
        const SizedBox(width: S.x2),
        SizedBox(
          width: 40,
          child: Text(
            '${v.round()}%',
            textAlign: TextAlign.end,
            style: F.tab(F.cap).copyWith(color: p.ink2),
          ),
        ),
      ],
    );
    return AppCard(
      semanticLabel:
          '${JournalMapper.headline(i)}. Clear. ${JournalMapper.detail(i)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(icon: JournalScreen.iconFor(i.factor), accent: tone),
                const SizedBox(width: S.x3),
                Expanded(
                  child: DotStat(
                    value: '${d.abs()}',
                    unit: d == 0
                        ? 'pts'
                        : (d > 0 ? 'pts higher' : 'pts lower'),
                    color: p.on(tone),
                    style: F.dot36,
                  ),
                ),
                const SizedBox(width: S.x2),
                StatePill(label: 'Clear', color: tone),
              ],
            ),
            const SizedBox(height: S.x3),
            _sentence(context, i, p.on(tone)),
            const SizedBox(height: S.x3),
            bar('With', i.avgWith, p.mark(tone)),
            const SizedBox(height: S.x2),
            bar('Without', i.avgWithout, p.ink3),
            const SizedBox(height: S.x3),
            Text(
              '${i.daysWith} days with · ${i.daysWithout} without',
              style: F.tab(F.cap).copyWith(color: p.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

/// A maybe: the sentence, its pill and group sizes, no bars (the gap could
/// still be chance).
class InsightRow extends StatelessWidget {
  const InsightRow({super.key, required this.insight});
  final FactorInsight insight;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final i = insight;
    return Semantics(
      container: true,
      label: '${JournalMapper.headline(i)}. Maybe. ${JournalMapper.detail(i)}.',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: JournalScreen.iconFor(i.factor), size: 32),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sentence(context, i, null),
                  const SizedBox(height: S.x1),
                  Wrap(
                    spacing: S.x2,
                    runSpacing: S.x1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatePill.tone(PillTone.off, 'Maybe'),
                      Text(
                        '${i.daysWith} days with · ${i.daysWithout} without',
                        style: F.tab(F.cap).copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Medium/14 filled with the last seven evenings: Consistency, "X of 7
/// days" (never a streak: PRODUCT_PLAN adopts consistency instead).
WeekDotsTile consistencyTile(JournalState s) {
  const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  final n = s.loggedThisWeek;
  return WeekDotsTile(
    title: 'Consistency',
    trailing: '$n of 7 days',
    letters: [for (final w in s.week) letters[DayKey.start(w.$1).weekday - 1]],
    numbers: [for (final w in s.week) '${DayKey.start(w.$1).day}'],
    marks: [
      for (final w in s.week)
        w.$2 ? DayMark.done : (w.$1 == s.date ? DayMark.today : DayMark.open),
    ],
    page: 0,
    pages: 1,
    semanticLabel: 'Consistency: $n of the last 7 evenings logged.',
  );
}
