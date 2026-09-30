// Recovery detail (pushed; owns its Scaffold). The score, what it means,
// exactly how it was built, each input inside its 30-night band, the 7-night
// HRV trend and the last 30 scores. Everything is one tap from its formula.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart';
import '../../app/insight_card.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/coach/insight_contracts.dart' show InsightKind;
import 'recovery_view_model.dart';
import 'widgets/recovery_explain.dart';
import 'widgets/recovery_widgets.dart';

class RecoveryScreen extends ConsumerWidget {
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = P.of(context);
    final async = ref.watch(recoveryViewModelProvider);
    final vm = ref.read(recoveryViewModelProvider.notifier);
    final s = async.value;

    final List<Widget> body;
    if (s != null) {
      body = _content(context, s, vm);
    } else if (async.hasError) {
      body = [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Couldn’t load Recovery',
          body: 'Airlog couldn’t open your saved data. Nothing was changed.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(recoveryViewModelProvider),
        ),
      ];
    } else {
      body = const [
        Center(
          child: ScoreRing(
            key: ValueKey('recovery-hero'),
            label: 'Recovery',
            color: C.recGreen,
            state: RingState.loading,
            size: 164,
          ),
        ),
        SizedBox(height: S.x6),
        AppCard(child: SkeletonLines(lines: 5)),
      ];
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text(
          s?.result?.withoutHrv == true ? 'Recovery · without HRV' : 'Recovery',
        ),
        actions: [
          AppIconButton(
            icon: Icons.info_outline_rounded,
            semanticLabel: 'How Recovery works',
            onTap: () => showRecoveryExplain(context, state: s),
          ),
          const SizedBox(width: S.x2),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x1, S.gutter, S.x12),
        children: body,
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    RecoveryState s,
    RecoveryViewModel vm,
  ) {
    final p = P.of(context);
    final switcher = s.date == null
        ? null
        : Center(
            child: DaySwitcher(
              date: s.date!,
              latest: s.latest,
              earliest: s.earliest,
              today: s.today,
              onShift: vm.shift,
            ),
          );
    switch (s.content) {
      case RecoveryContent.noData:
        return const [
          EmptyState(
            icon: Icons.favorite_border_rounded,
            title: 'No Recovery yet',
            body:
                'Wear your tracker to bed tonight. Your first Recovery shows '
                'up in the morning.',
          ),
        ];
      case RecoveryContent.emptyDay:
        return [
          ?switcher,
          const EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'Nothing recorded',
            body: 'No data arrived for this day.',
          ),
        ];
      case RecoveryContent.ready:
        break;
    }
    final rec = s.result;
    final zoneColor = rec == null
        ? C.recGreen
        : DomainColors.recoveryZone(rec.zone);
    Widget gap([double h = S.x4]) => SizedBox(height: h);
    Widget section(String title, String? subtitle) => Padding(
      padding: const EdgeInsets.only(top: S.x6, bottom: S.x3),
      child: SectionHeader(title: title, subtitle: subtitle),
    );

    final children = <Widget>[
      ?switcher,
      if (s.date != null)
        InsightFeed(
          date: s.date!,
          kinds: const {InsightKind.recovery},
          hostRoute: Routes.recovery,
          padding: const EdgeInsets.only(top: S.x3),
        ),
      gap(S.x3),
      Center(
        child: ScoreRing(
          key: const ValueKey('recovery-hero'),
          label: 'Recovery',
          color: zoneColor,
          value: rec?.score.toDouble(),
          unit: '%',
          state: s.ringState,
          caption: s.ringCaption,
          progress: s.calibration?.progress,
          size: 164,
        ),
      ),
      if (rec != null) ...[
        gap(S.x3),
        Center(
          child: StatePill(label: s.headline!, color: zoneColor),
        ),
        gap(S.x3),
        Text(
          s.meaning!,
          textAlign: TextAlign.center,
          style: F.tab(F.body).copyWith(color: p.ink2),
        ),
      ],
      Center(
        child: AskAboutThis(screen: 'recovery', date: s.date),
      ),
      if (s.calibration != null) ...[
        gap(),
        CalibrationBanner.of(s.calibration!),
      ],
      if (rec != null) ...[
        section(
          'What made your score',
          'Points from each signal, out of its share',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ContributionBars(
                items: s.contributions,
                color: zoneColor,
                total: rec.score.toDouble(),
                totalLabel: 'Recovery',
              ),
              for (final note in [?s.reweightNote, ?s.neutralNote]) ...[
                gap(S.x3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.balance_rounded,
                        size: 15,
                        color: p.ink3,
                      ),
                    ),
                    const SizedBox(width: S.x2),
                    Expanded(
                      child: Text(note, style: F.cap.copyWith(color: p.ink2)),
                    ),
                  ],
                ),
              ],
              gap(S.x2),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: 'See the formula',
                  kind: AppButtonKind.quiet,
                  compact: true,
                  icon: Icons.functions_rounded,
                  onTap: () => showRecoveryExplain(context, state: s),
                ),
              ),
            ],
          ),
        ),
      ],
      if (rec == null)
        for (final n in s.notes) ...[gap(), StatusCard.fromNote(n)],
      section(
        'Your signals vs your usual',
        'Last ${s.inputs.isEmpty ? 30 : s.inputs.first.values.length} nights. '
            'The shaded area is your usual range.',
      ),
      for (var i = 0; i < s.inputs.length; i++) ...[
        if (i > 0) gap(S.x3),
        InputCard(input: s.inputs[i], date: s.date!),
      ],
      section('Your HRV this week', 'Average of the last 7 nights'),
      ReadinessCard(
        readiness: s.readiness,
        missing: s.readinessMissing,
        onExplain: () => showReadinessExplain(context, s.readiness),
      ),
      section('Recovery history', null),
      AppCard(
        child: RecoveryHistory(
          scores: s.history,
          zones: s.historyZones,
          date: s.date!,
        ),
      ),
      if (rec != null && s.notes.isNotEmpty) ...[
        section('About this night\'s data', null),
        for (var i = 0; i < s.notes.length; i++) ...[
          if (i > 0) gap(S.x3),
          StatusCard.fromNote(s.notes[i]),
        ],
      ],
      gap(S.x6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: p.ink3),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(
              ExplainSheet.defaultFootnote,
              style: F.cap.copyWith(color: p.ink3),
            ),
          ),
        ],
      ),
    ];
    return children;
  }
}
