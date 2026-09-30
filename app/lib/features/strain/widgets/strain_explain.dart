// "How Strain works" — every constant is read from the engine
// (StrainEngine, EngineConfig), so this sheet cannot drift from the maths.

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/engine/engine.dart' show EngineConfig;
import '../../../domain/engine/strain.dart' show StrainEngine;
import '../../../domain/engine/strain_fallback.dart' show StrainDay;
import '../../../domain/engine/trimp.dart' show Trimp;
import '../../../domain/results.dart';
import '../strain_view_model.dart';
import 'strain_widgets.dart';

Future<void> showStrainExplain(BuildContext context, StrainView v) {
  final s = v.strain;
  final rhr = s?.restingHrUsed;
  final maxHr = s?.maxHrUsed;
  final tau = const EngineConfig().strainTau;
  String pct(double f) => '${(f * 100).round()} %';
  final override = v.profile.maxHrOverride != null;
  final top = numText(StrainEngine.scaleMax);
  final factor = numText(StrainEngine.targetFactor);
  final tMin = numText(StrainEngine.targetMin);
  final tMax = numText(StrainEngine.targetMax);
  return showExplainSheet<void>(
    context,
    title: s == null || v.noInput ? 'Strain' : 'Strain ${strain1(s.strain)}',
    lede:
        'How hard your heart worked across the day, on a 0–21 scale that '
        'gets harder to climb the higher you go. Minutes spent near your '
        'maximum count many times more than easy ones.',
    children: [
      ExplainSection(
        title: 'Heart-rate zones',
        body:
            'Each minute is placed by how close your heart rate was to your '
            'max, counting up from your resting heart rate (the Karvonen '
            'method). '
            '${rhr == null || maxHr == null ? '' : 'For this day: resting ${rhr.round()} bpm, max ${maxHr.round()} bpm '}'
            '${override ? '(your own max).' : '(predicted: ${numText(StrainEngine.tanakaIntercept)} − ${numText(StrainEngine.tanakaSlope)} × age, Tanaka 2001).'}',
        formula: rhr == null || maxHr == null
            ? '%HRR = (HR − resting) ÷ (max − resting)'
            : '%HRR = (HR − ${rhr.round()}) ÷ (${maxHr.round()} − ${rhr.round()})',
      ),
      ExplainSection(
        title: 'How minutes count',
        body:
            'Harder minutes count for much more. Six scoring bands (from '
            'Pulse) set the number. The five zones on the chart are simpler '
            'bands for display.',
        child: _LoadTable(minutes: s?.loadZoneMinutes ?? const [], pct: pct),
      ),
      ExplainSection(
        title: 'The 0–$top scale',
        body:
            'Load is squeezed onto 0–$top so the first hour of effort moves '
            'the score a lot and the fifth hour very little.',
        formula: s == null || v.noInput
            ? 'strain = $top × (1 − e^(−load ÷ ${tau.round()}))'
            : 'strain = $top × (1 − e^(−${s.rawLoad.toStringAsFixed(0)} ÷ ${tau.round()})) = ${strain1(s.strain)}',
      ),
      ExplainSection(
        title: 'Effort goal',
        body:
            'Your goal for the day is $factor × that morning’s Recovery, kept '
            'between $tMin and $tMax (from Pulse). Today shows it as a range: '
            'the goal ± ${numText(StrainEngine.targetBand)}. Low '
            'Recovery means a lighter goal. It’s a guide, not a rule.',
        formula: v.recovery == null || v.target == null
            ? 'target = $factor × recovery, $tMin … $tMax'
            : 'target = $factor × ${v.recovery} = ${strain1(v.target!)}',
      ),
      ExplainSection(
        title: 'Second opinion (TRIMP)',
        body:
            'A different way to count the same minutes of effort (Banister '
            '1991; Morton et al. 1990). It never replaces Strain. If the two '
            'disagree a lot, your zones may need a look.'
            '${s?.trimp == null ? '' : ' Second opinion (TRIMP) this day: ${s!.trimp!.round()}.'}',
        formula:
            'TRIMP = Σ minutes × x × '
            '${numText(Trimp.maleA)}·e^(${numText(Trimp.maleB)}x)   (x = %HRR)',
      ),
      ExplainSection(
        title: 'When heart rate is patchy',
        body:
            'If fewer than ${pct(StrainDay.minCoverage)} of waking minutes '
            'have heart rate, zones would under-count, so there is no strain '
            'score for the day: the screen lists your workouts and steps '
            'instead. A single workout without heart rate inside it uses its '
            'own average heart rate and says “Estimate”.',
      ),
      const ExplainSection(
        title: 'Sources',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BulletLine(
              'Karvonen MJ et al. (1957). The effects of training on '
              'heart rate; a longitudinal study.',
            ),
            BulletLine(
              'Tanaka H, Monahan KD, Seals DR (2001). Age-predicted '
              'maximal heart rate revisited. J Am Coll Cardiol.',
            ),
            BulletLine(
              'Banister EW (1991). Modeling elite athletic '
              'performance.',
            ),
            BulletLine(
              'Zone weights and the 0–21 scale are ported from Pulse '
              '(Apache-2.0). It isn’t any tracker maker’s own formula.',
            ),
          ],
        ),
      ),
    ],
  );
}

class _LoadTable extends StatelessWidget {
  const _LoadTable({required this.minutes, required this.pct});
  final List<double> minutes;
  final String Function(double) pct;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final head = F.over.copyWith(color: p.ink3);
    final cell = F.tab(F.bodySm).copyWith(color: p.ink);
    final n = StrainEngine.zoneLowerBounds.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(flex: 5, child: Text('ZONE', style: head)),
              Expanded(flex: 3, child: Text('FROM', style: head)),
              Expanded(
                flex: 3,
                child: Text('WEIGHT', style: head, textAlign: TextAlign.right),
              ),
              if (minutes.isNotEmpty)
                Expanded(
                  flex: 3,
                  child: Text('MIN', style: head, textAlign: TextAlign.right),
                ),
            ],
          ),
          const SizedBox(height: S.x2),
          for (var i = 0; i < n; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      StrainEngine.zoneLabels[i],
                      style: cell.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      pct(StrainEngine.zoneLowerBounds[i]),
                      style: cell.copyWith(color: p.ink2),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '× ${_w(StrainEngine.zoneWeights[i])}',
                      style: cell,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  if (minutes.isNotEmpty)
                    Expanded(
                      flex: 3,
                      child: Text(
                        i < minutes.length ? '${minutes[i].round()}' : '–',
                        style: cell,
                        textAlign: TextAlign.right,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _w(double w) =>
      w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toStringAsFixed(1);
}

/// The strain method in words, for other screens and tests.
String methodLabel(StrainMethod m) => switch (m) {
  StrainMethod.hrZones => 'From heart rate',
  StrainMethod.fallback =>
    'Estimate from workouts and steps (not enough heart rate)',
  StrainMethod.none => 'No data',
};
