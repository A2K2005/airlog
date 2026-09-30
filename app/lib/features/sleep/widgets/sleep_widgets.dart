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
        : '${change > 0 ? 'up' : 'down'} ${sleepHm(change.abs())} last night';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sleep goal and missed sleep',
            style: F.head.copyWith(color: p.ink),
          ),
          const SizedBox(height: S.x2),
          Text(
            'Missed sleep: ${sleepHm(a.debtAfterMinutes)}'
            '${a.debtAfterMinutes >= _cfg.maxDebtMinutes - .5 ? ' (the most Airlog counts)' : ''}',
            style: F.tab(F.bodySm).copyWith(color: p.ink2),
          ),
          if (changeText != null)
            Text(changeText, style: F.tab(F.cap).copyWith(color: p.ink3)),
          if (a.napMinutes >= 1)
            Text(
              'Includes ${sleepHm(a.napMinutes)} of naps.',
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
                  label: 'How your sleep goal is set',
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
      ('Usual need', b.baselineMinutes, DomainColors.sleep),
      ('Catch-up', b.debtMinutes, C.amber),
      ('Extra after a hard day', b.strainMinutes, DomainColors.strain),
    ];
    final spoken =
        'Sleep goal ${sleepHm(need)}: usual need '
        '${sleepHm(b.baselineMinutes)}, catch-up ${sleepHm(b.debtMinutes)}, '
        'extra after a hard day ${sleepHm(b.strainMinutes)}. You slept '
        '${sleepHm(slept)}.';
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
          'Deep + REM',
          a.hasStageData ? sleepHm(a.restorativeMinutes) : 'No stage data',
          restorativePct == null
              ? 'of your sleep'
              : '${restorativePct!.round()}% of your sleep',
        ),
        const SizedBox(width: S.x3),
        stat(
          'Asleep in bed',
          a.efficiency == null ? '–' : '${a.efficiency!.round()}%',
          'of your time in bed',
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
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
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
                    '${clockTextOf(n.start, use24h: h24)}–'
                    '${clockTextOf(n.end, use24h: h24)}',
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
            'Naps count toward your sleep goal.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}

/// "Try to be asleep by 11:35 pm…" for the coming night.
class BedtimeCard extends StatelessWidget {
  const BedtimeCard({super.key, required this.bedtime, this.onExplain});
  final BedtimeVm bedtime;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final b = bedtime;
    final ink = p.on(DomainColors.sleep);
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final bed = b.bedMinutes == null
        ? b.bedtime
        : clockText(b.bedMinutes!, use24h: h24);
    final wake = b.wakeMinutes == null
        ? b.wake
        : clockText(b.wakeMinutes!, use24h: h24);
    final catchUp = b.debtShareMinutes >= 1
        ? ', with ${sleepHm(b.debtShareMinutes)} extra to catch up'
        : '';
    final body =
        'That gives you ${sleepHm(b.needMinutes)} of sleep before you usually '
        'wake up at $wake$catchUp.';
    return AppCard(
      tone: CardTone.tinted,
      accent: DomainColors.sleep,
      onTap: onExplain,
      semanticLabel: 'Tonight: try to be asleep by $bed. $body',
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
                        const TextSpan(text: 'Try to be asleep by '),
                        TextSpan(
                          text: bed,
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
    title: 'Sleep goal',
    lede:
        'How much sleep suits tonight: your usual need, plus some catch-up '
        'for missed sleep, plus a little extra after a hard day.',
    children: [
      if (a != null && b != null)
        ExplainSection(
          title: 'This night',
          formula:
              'usual need ${sleepHm(b.baselineMinutes)}\n'
              '+ catch-up ${sleepHm(b.debtMinutes)}\n'
              '+ extra after a hard day ${sleepHm(b.strainMinutes)}\n'
              '= goal ${sleepHm(a.needMinutes)} · slept '
              '${sleepHm(a.sleptMinutes)} → ${a.performance.round()}%',
        ),
      ExplainSection(
        title: 'Sleep goal',
        body:
            'Your usual need is $base. Add $repay% of your missed sleep, and '
            'up to $boost extra when yesterday’s Strain was above $from (the '
            'full $boost at '
            '${numText(SleepEngine.strainBoostFrom + SleepEngine.strainBoostSpan)}). '
            'The goal always stays between $lo and $hi.',
        formula:
            'target = clamp($base + $repay % × debt + boost, $lo, $hi)\n'
            'boost = clamp((strain − $from) / $span, 0, 1) × $boost',
      ),
      ExplainSection(
        title: 'Missed sleep',
        body:
            'Each night, any sleep you missed is added. Sleeping longer than '
            'your goal pays it back. It never goes above $maxDebt, and it '
            'grows by at most $perNight in one night. A night with no data '
            'leaves it as it was.',
      ),
      ExplainSection(
        title: 'Sleep % and consistency',
        body:
            'Your sleep % is how much of your goal you slept, naps included, '
            'up to 100%. Consistency compares your bed and wake times with '
            'your last ${SleepEngine.consistencyWindow} nights: 100% means '
            'the same times, and it reaches 0% when they’re '
            '${numText(SleepEngine.consistencyZeroMinutes)} minutes off on '
            'average.',
      ),
      const ExplainSection(
        title: 'Tonight’s bedtime',
        body:
            'Your usual wake-up time over the last '
            '${SleepEngine.bedtimeWakeDays} days, minus tonight’s sleep goal. '
            'It’s when to be asleep, so get into bed a little earlier.',
      ),
      const ExplainSection(
        title: 'Sources',
        body:
            'Ported from Pulse (Luraxx/pulse, Apache-2.0) SleepEngine. Sleep '
            'stages come from your tracker, through Health Connect.',
      ),
    ],
  );
}
