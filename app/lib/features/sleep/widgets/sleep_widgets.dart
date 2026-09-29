// Sleep building blocks: the slept-vs-need hero with the need's parts, the
// stage stats, naps, tonight's bedtime and the sleep-need explain sheet.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/engine/engine.dart' show SleepConfig;
import '../../../domain/engine/sleep.dart' show SleepEngine;
import '../../../domain/results.dart';
import '../sleep_view_model.dart';

const _cfg = SleepConfig();

/// Target breakdown and debt beneath the screen's single sleep summary.
class SleepHero extends StatelessWidget {
  const SleepHero({
    super.key,
    required this.analysis,
    this.debtChange,
    this.playKey,
    this.onExplain,
  });

  final SleepAnalysis analysis;
  final double? debtChange;
  final String? playKey;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final a = analysis;
    final b = a.needBreakdown;
    final change = debtChange;
    final changeText = change == null || change.abs() < 1
        ? null
        : '${change > 0 ? '+' : '−'}${sleepHm(change.abs())} last night';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Target and sleep debt', style: F.head.copyWith(color: p.ink)),
          const SizedBox(height: S.x2),
          Text(
            'Debt after the night ${sleepHm(a.debtAfterMinutes)}'
            '${a.debtAfterMinutes >= _cfg.maxDebtMinutes - .5 ? ' (the cap)' : ''}',
            style: F.tab(F.bodySm).copyWith(color: p.ink2),
          ),
          if (changeText != null)
            Text(changeText, style: F.tab(F.cap).copyWith(color: p.ink3)),
          if (a.napMinutes >= 1)
            Text(
              'Time asleep includes ${sleepHm(a.napMinutes)} of naps.',
              style: F.tab(F.cap).copyWith(color: p.ink3),
            ),
          if (b != null) ...[
            const SizedBox(height: S.x5),
            NeedBar(breakdown: b, slept: a.sleptMinutes),
            if (onExplain != null) ...[
              const SizedBox(height: S.x1),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: 'How the target is worked out',
                  kind: AppButtonKind.quiet,
                  compact: true,
                  icon: Icons.functions_rounded,
                  onTap: onExplain,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The need as three segments (baseline · debt share · strain boost) with a
/// tick where the night's sleep reached, and the parts written out.
class NeedBar extends StatelessWidget {
  const NeedBar({super.key, required this.breakdown, required this.slept});
  final SleepNeedBreakdown breakdown;
  final double slept;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final b = breakdown;
    final need = b.baselineMinutes + b.debtMinutes + b.strainMinutes;
    final scale = math.max(need, slept);
    final parts = [
      ('Baseline', b.baselineMinutes, DomainColors.sleep),
      ('Debt share', b.debtMinutes, C.amber),
      ('Strain boost', b.strainMinutes, DomainColors.strain),
    ];
    final spoken =
        'Target ${sleepHm(need)}: baseline ${sleepHm(b.baselineMinutes)}, '
        'debt share ${sleepHm(b.debtMinutes)}, strain boost '
        '${sleepHm(b.strainMinutes)}. Slept ${sleepHm(slept)}.';
    return Semantics(
      label: spoken,
      container: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final x = scale <= 0
                    ? 0.0
                    : (slept / scale).clamp(0.0, 1.0) * w;
                return SizedBox(
                  height: 34,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 12,
                        height: 10,
                        child: ClipRRect(
                          borderRadius: R.rPill,
                          child: Row(
                            children: [
                              for (final (_, m, c) in parts)
                                if (m > 0)
                                  Expanded(
                                    flex: math.max(
                                      1,
                                      (m / scale * 1000).round(),
                                    ),
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 2),
                                      color: p.mark(c),
                                    ),
                                  ),
                              if (scale > need)
                                Expanded(
                                  flex: math.max(
                                    1,
                                    ((scale - need) / scale * 1000).round(),
                                  ),
                                  child: ColoredBox(color: p.track),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: (x - 1).clamp(0.0, math.max(0.0, w - 2)),
                        top: 4,
                        width: 2,
                        height: 26,
                        child: ColoredBox(color: p.ink),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: S.x2),
            Wrap(
              spacing: S.x4,
              runSpacing: S.x1,
              children: [
                for (final (l, m, c) in parts)
                  LegendSwatch(label: '$l ${sleepHm(m)}', color: p.mark(c)),
                LegendSwatch(label: 'Slept ${sleepHm(slept)}', color: p.ink),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Restorative sleep, efficiency and time in bed, in one row.
class StageStats extends StatelessWidget {
  const StageStats({super.key, required this.analysis, this.restorativePct});
  final SleepAnalysis analysis;
  final double? restorativePct;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final a = analysis;
    final inBed = a.bedTime != null && a.wakeTime != null
        ? a.wakeTime!.difference(a.bedTime!).inMinutes.toDouble()
        : null;
    Widget stat(String label, String value, String? sub) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
          const SizedBox(height: S.x1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: F.n24.copyWith(color: p.ink)),
          ),
          if (sub != null)
            Text(sub, style: F.tab(F.cap).copyWith(color: p.ink3), maxLines: 2),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        stat(
          'Restorative',
          a.hasStageData ? sleepHm(a.restorativeMinutes) : 'Unavailable',
          restorativePct == null
              ? 'deep + REM'
              : 'deep + REM · ${restorativePct!.round()} %',
        ),
        const SizedBox(width: S.x3),
        stat(
          'Efficiency',
          a.efficiency == null ? '–' : '${a.efficiency!.round()} %',
          'asleep of in bed',
        ),
        const SizedBox(width: S.x3),
        stat('In bed', inBed == null ? '–' : sleepHm(inBed), null),
      ],
    );
  }
}

class NapsCard extends StatelessWidget {
  const NapsCard({super.key, required this.naps});
  final List<NapVm> naps;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            naps.length == 1 ? 'Nap' : 'Naps',
            style: F.bodySm.copyWith(color: p.ink, fontWeight: FontWeight.w700),
          ),
          for (final n in naps) ...[
            const SizedBox(height: S.x3),
            Row(
              children: [
                Icon(Icons.airline_seat_flat_outlined, size: 18, color: p.ink2),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(
                    '${clockOf(n.start)}–${clockOf(n.end)}',
                    style: F.tab(F.bodySm).copyWith(color: p.ink),
                  ),
                ),
                Text(
                  '${sleepHm(n.asleepMinutes)} asleep',
                  style: F.tab(F.cap).copyWith(color: p.ink2),
                ),
              ],
            ),
          ],
          const SizedBox(height: S.x3),
          Text(
            'Naps count toward the night\'s total and its performance.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}

/// "Aim to be asleep by 21:45…" for the coming night.
class BedtimeCard extends StatelessWidget {
  const BedtimeCard({super.key, required this.bedtime, this.onExplain});
  final BedtimeVm bedtime;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final b = bedtime;
    final ink = p.on(DomainColors.sleep);
    final debt = b.debtShareMinutes >= 1
        ? ', including ${sleepHm(b.debtShareMinutes)} toward your '
              '${sleepHm(b.debtMinutes)} of debt'
        : '';
    final body =
        'Tonight’s target is ${sleepHm(b.needMinutes)}$debt, and you usually '
        'wake at ${b.wake}.';
    return AppCard(
      tone: CardTone.tinted,
      accent: DomainColors.sleep,
      onTap: onExplain,
      semanticLabel: 'Tonight: aim to be asleep by ${b.bedtime}. $body',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: p.card, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(Icons.bedtime_rounded, size: 20, color: ink),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TONIGHT', style: F.over.copyWith(color: ink)),
                  const SizedBox(height: S.x1),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Aim to be asleep by '),
                        TextSpan(
                          text: b.bedtime,
                          style: F.n24.copyWith(color: p.ink),
                        ),
                      ],
                    ),
                    style: F.head.copyWith(color: p.ink),
                  ),
                  const SizedBox(height: S.x1),
                  Text(body, style: F.tab(F.bodySm).copyWith(color: p.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sleep need, debt, performance and consistency, with the engine's own
/// constants.
Future<void> showSleepNeedExplain(BuildContext context, SleepAnalysis? a) {
  final b = a?.needBreakdown;
  final base = sleepHm(_cfg.baselineNeedMinutes);
  final repay = (_cfg.debtRepayFraction * 100).round();
  final boost = sleepHm(_cfg.strainNeedBoostMaxMinutes);
  final maxDebt = sleepHm(_cfg.maxDebtMinutes);
  final perNight = sleepHm(_cfg.maxDebtGainPerNightMinutes);
  final lo = sleepHm(
    _cfg.baselineNeedMinutes - SleepEngine.needBelowBaselineMinutes,
  );
  final hi = sleepHm(
    _cfg.baselineNeedMinutes + SleepEngine.needAboveBaselineMinutes,
  );
  final from = numText(SleepEngine.strainBoostFrom);
  final span = numText(SleepEngine.strainBoostSpan);
  return showExplainSheet<void>(
    context,
    title: 'Sleep target',
    lede:
        'How much sleep a night asks for: a fixed baseline, plus part of any '
        'debt, plus a little more after a hard day.',
    children: [
      if (a != null && b != null)
        ExplainSection(
          title: 'This night',
          formula:
              'baseline ${sleepHm(b.baselineMinutes)}\n'
              '+ debt share ${sleepHm(b.debtMinutes)}\n'
              '+ strain boost ${sleepHm(b.strainMinutes)}\n'
              '= target ${sleepHm(a.needMinutes)} · slept '
              '${sleepHm(a.sleptMinutes)} → ${a.performance.round()} %',
        ),
      ExplainSection(
        title: 'Need',
        body:
            'Baseline $base. Add $repay % of the debt carried into the night, '
            'and up to $boost when the previous day\'s strain was above $from '
            '(the full $boost at '
            '${numText(SleepEngine.strainBoostFrom + SleepEngine.strainBoostSpan)}). '
            'The total stays between $lo and $hi.',
        formula:
            'target = clamp($base + $repay % × debt + boost, $lo, $hi)\n'
            'boost = clamp((strain − $from) / $span, 0, 1) × $boost',
      ),
      ExplainSection(
        title: 'Debt',
        body:
            'Each night adds (baseline + strain boost − slept) to the running '
            'debt, or pays it down when you sleep longer. It is capped at '
            '$maxDebt and can grow by at most $perNight in one night. A night '
            'without data leaves it unchanged.',
      ),
      ExplainSection(
        title: 'Performance and consistency',
        body:
            'Performance is sleep (naps included) against the target, capped at '
            '100 %. Consistency compares tonight\'s bed and wake times with '
            'your previous ${SleepEngine.consistencyWindow} main sleeps: 100 % '
            'is the same times, and it reaches 0 % at an average shift of '
            '${numText(SleepEngine.consistencyZeroMinutes)} minutes.',
      ),
      const ExplainSection(
        title: 'Tonight\'s bedtime',
        body:
            'Your average wake time over the last '
            '${SleepEngine.bedtimeWakeDays} days minus tonight\'s projected '
            'target. It is when to be asleep, so allow time to fall asleep.',
      ),
      const ExplainSection(
        title: 'Sources',
        body:
            'Ported from Pulse (Luraxx/pulse, Apache-2.0) SleepEngine. Stages '
            'are the band\'s own classification via Health Connect.',
      ),
    ],
  );
}
