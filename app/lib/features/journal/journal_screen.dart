// Journal (pushed; owns its Scaffold). Tag the evening in a few taps (saved
// immediately), then see which factors move the next morning's Recovery in
// your own data, with how sure the numbers are.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          title: 'Could not open the journal',
          body: 'The stored entries could not be read. Nothing was changed.',
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

  List<Widget> _content(
    BuildContext context,
    JournalState s,
    JournalViewModel vm,
  ) {
    final p = P.of(context);
    final n = s.entry.factors.length;
    Widget section(String title, String? subtitle) => Padding(
      padding: const EdgeInsets.only(top: S.x8, bottom: S.x3),
      child: SectionHeader(title: title, subtitle: subtitle),
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
            Text(
              s.isToday
                  ? 'What applies this evening?'
                  : 'What applied that evening?',
              style: F.t2.copyWith(color: p.ink),
            ),
            const SizedBox(height: S.x1),
            Text(
              'Tap everything that fits. Airlog compares it with the next '
              'morning\'s Recovery.',
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
                        ? 'Could not save the last change. Tap again to retry.'
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
      if (!s.hasInsights) ...[
        section('What moves your recovery', null),
        const AppCard(
          child: EmptyState(
            icon: Icons.insights_outlined,
            title: 'Patterns take a few weeks',
            body:
                'Each factor needs at least ${JournalViewModel.minDays} tagged '
                'days with it and ${JournalViewModel.minDays} without, each '
                'followed by a Recovery score. Keep tagging your evenings, '
                'including the ordinary ones.',
          ),
        ),
      ] else ...[
        section(
          'What moves your recovery',
          'Next-morning Recovery, days with a factor vs days without',
        ),
        if (s.solid.isEmpty)
          Text(
            'No clear effects yet: every difference so far is within day-to-day '
            'noise.',
            style: F.bodySm.copyWith(color: p.ink2),
          )
        else
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < s.solid.length; i++) ...[
                  if (i > 0) Divider(height: S.x6, color: p.line),
                  InsightRow(insight: s.solid[i]),
                ],
              ],
            ),
          ),
        if (s.emerging.isNotEmpty) ...[
          section(
            'Emerging',
            'Enough days, but the difference is still within noise',
          ),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < s.emerging.length; i++) ...[
                  if (i > 0) Divider(height: S.x5, color: p.line),
                  InsightRow(insight: s.emerging[i], compact: true),
                ],
              ],
            ),
          ),
        ],
        if (s.missing.isNotEmpty) ...[
          const SizedBox(height: S.x4),
          Text(
            'Not enough days yet: ${s.missing.map((f) => f.label).join(', ')}. '
            'Each needs ${JournalViewModel.minDays} days with it and '
            '${JournalViewModel.minDays} without.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ],
      const SizedBox(height: S.x6),
      AppCard(
        tone: CardTone.inset,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.balance_rounded, size: 18, color: p.ink2),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Correlation, not causation',
                    style: F.bodySm.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'These are differences in your own data, not proof of '
                    'cause: other things often change on the same days. '
                    '"Solid" means the gap is more than twice its standard '
                    'error (Welch).',
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

/// "Alcohol is associated with 24 points lower recovery the next day", its confidence and group sizes,
/// and the two averages as bars on one 0–100 scale.
class InsightRow extends StatelessWidget {
  const InsightRow({super.key, required this.insight, this.compact = false});
  final FactorInsight insight;

  /// Emerging rows: no bars (the difference is within noise anyway).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final i = insight;
    final solid = i.confidence == InsightConfidence.solid;
    final down = i.delta < 0;
    final tone = !solid ? C.neutral : (down ? C.amber : C.health);
    final d = i.delta.round();
    Widget bar(String label, double v, Color c) => Row(
      children: [
        const SizedBox(width: 36 + S.x3),
        SizedBox(
          width: 58,
          child: Text(label, style: F.cap.copyWith(color: p.ink3)),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Align(
              alignment: Alignment.centerLeft,
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
          width: 36,
          child: Text(
            '${v.round()} %',
            textAlign: TextAlign.end,
            style: F.tab(F.cap).copyWith(color: p.ink2),
          ),
        ),
      ],
    );
    return Semantics(
      container: true,
      label:
          '${JournalMapper.headline(i)}. ${solid ? 'Solid' : 'Emerging'}. '
          '${JournalMapper.detail(i)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: solid ? p.wash(tone) : p.card2,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    JournalScreen.iconFor(i.factor),
                    size: 18,
                    color: solid ? p.on(tone) : p.ink2,
                  ),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${i.factor.label} is associated with ',
                            ),
                            TextSpan(
                              text:
                                  '${d.abs()} ${d.abs() == 1 ? 'point' : 'points'} '
                                  '${d >= 0 ? 'higher' : 'lower'}',
                              style: TextStyle(
                                color: solid ? p.on(tone) : p.ink,
                              ),
                            ),
                            const TextSpan(text: ' recovery the next day'),
                          ],
                        ),
                        style: F.tab(F.head).copyWith(color: p.ink),
                      ),
                      const SizedBox(height: S.x1),
                      Wrap(
                        spacing: S.x2,
                        runSpacing: S.x1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatePill(
                            label: solid ? 'Solid' : 'Emerging',
                            color: tone,
                          ),
                          Text(
                            '${i.daysWith} vs ${i.daysWithout} days',
                            style: F.tab(F.cap).copyWith(color: p.ink3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: S.x3),
              bar('With', i.avgWith, p.mark(solid ? tone : C.neutral)),
              const SizedBox(height: S.x2),
              bar('Without', i.avgWithout, p.ink3),
            ],
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
