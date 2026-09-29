// The Recovery and readiness explain sheets: the exact formulas, the
// constants read from the engine (never retyped), and the sources. When an
// input comes from WHOOP or Oura, a line says this is not that app's own
// score and links to Methodology ("Other apps' scores").

import 'package:flutter/material.dart';

import '../../../app/route_names.dart';
import '../../../design/design.dart';
import '../../../domain/engine/health_monitor.dart';
import '../../../domain/engine/readiness.dart';
import '../../../domain/engine/engine.dart' show EngineConfig;
import '../../../domain/engine/recovery.dart';
import '../../../domain/engine/source_apps.dart';
import '../recovery_view_model.dart';

typedef RE = RecoveryEngine;

const _cfg = EngineConfig();

String _w(String key) =>
    ((RecoveryEngine.weights[key] ?? 0) * 100).round().toString();

/// "This differs from WHOOP’s own Recovery; here’s why." (and Oura’s
/// Readiness), once for each of those apps that supplied a Recovery input.
List<String> vendorScoreLines(RecoveryState? s) {
  final origins = {
    for (final i in s?.inputs ?? const <InputVm>[]) i.provenance?.origin,
  };
  return [
    if (origins.contains(SourceApps.whoop))
      'This differs from WHOOP’s own Recovery; here’s why.',
    if (origins.contains(SourceApps.oura))
      'This differs from Oura’s Readiness; here’s why.',
  ];
}

Future<void> showRecoveryExplain(BuildContext context, {RecoveryState? state}) {
  final s = state;
  final score = s?.result?.score;
  final vendor = vendorScoreLines(s);
  return showExplainSheet<void>(
    context,
    title: score == null ? 'How Recovery works' : 'Recovery $score',
    lede:
        'Recovery compares last night with your own recent nights, not with '
        'anyone else. Every number below is computed on this phone.',
    children: [
      if (vendor.isNotEmpty)
        ExplainSection(
          title: 'Not the app’s own score',
          body: vendor.join(' '),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Why they differ',
              kind: AppButtonKind.quiet,
              compact: true,
              icon: Icons.menu_book_outlined,
              onTap: () => Navigator.of(context).pushNamed(Routes.methodology),
            ),
          ),
        ),
      if (s != null && s.contributions.isNotEmpty)
        ExplainSection(
          title: 'This night\'s inputs',
          child: ContributionBars(
            items: s.contributions,
            color: DomainColors.recoveryZone(s.result!.zone),
            total: s.result!.score.toDouble(),
            totalLabel: 'Recovery',
          ),
        ),
      ExplainSection(
        title: 'Weights',
        body:
            'HRV ${_w('hrv')} · resting HR ${_w('rhr')} · sleep performance '
            '${_w('sleep')} · respiratory rate ${_w('resp')}. An input that '
            'did not arrive is left out and the others are scaled up so the '
            'weights still sum to 100: no number is guessed.',
      ),
      ExplainSection(
        title: 'Each input, scored 0 to 1',
        body:
            'Each input is compared with your baseline: the last '
            '${_cfg.baselineWindowDays} nights measured the same way (a '
            'change of source starts a new baseline). z is how many standard '
            'deviations tonight sits from your mean.',
        formula:
            'HRV:  z = (ln RMSSD − mean ln) / max(SD ln, ${numText(RE.hrvMinSd)})\n'
            '      score = 1 / (1 + e^(−${numText(RE.hrvLogisticSlope)}·z))\n'
            'Resting HR:  z = (bpm − mean) / max(SD, ${numText(RE.rhrMinSd)})\n'
            '      score = 1 / (1 + e^(${numText(RE.rhrLogisticSlope)}·z))\n'
            'Sleep:  score = clamp(performance / 100, '
            '${numText(RE.sleepMinScore)}, 1)\n'
            'Respiratory rate:  z = (rate − mean) / max(SD, '
            '${numText(RE.respMinSd)})\n'
            '      score = clamp(${numText(RE.respMaxScore)} − max(0, z − '
            '${numText(RE.respZAllowance)}) × ${numText(RE.respSlope)}, '
            '${numText(RE.respMinScore)}, ${numText(RE.respMaxScore)})',
      ),
      ExplainSection(
        title: 'Penalties',
        body:
            'Two warning signs subtract after weighting: overnight SpO₂ '
            'minimum below ${numText(RE.spo2PenaltyBelow)} % '
            '(−${numText(RE.spo2Penalty)}), and skin temperature more than '
            '${numText(RE.skinTempPenaltyZ)} standard deviations above your '
            'baseline (−${numText(RE.skinTempPenalty)}). Respiratory rate only '
            'costs points when it is raised, never when it is low.',
      ),
      ExplainSection(
        title: 'Score and zones',
        formula:
            'recovery = clamp(100 × Σ weight × score − penalties, '
            '${numText(RE.minScore)}, ${numText(RE.maxScore)})\n'
            'green ≥ ${RE.greenFrom} · yellow ${RE.yellowFrom}–'
            '${RE.greenFrom - 1} · red < ${RE.yellowFrom}',
      ),
      ExplainSection(
        title: 'Calibration',
        body:
            'Until an input has a baseline it scores a neutral '
            '${numText(RE.neutralScore)}. Recovery shows Calibrating until HRV '
            'and resting HR each have ${RE.reliableNights} nights, and '
            'Provisional until ${_cfg.calibrationNeedNights} nights; the '
            'banner counts them.',
      ),
      ExplainSection(
        title: 'Sources',
        body:
            'Formula ported from Pulse (Luraxx/pulse, Apache-2.0), an '
            'open-source take on the HRV-led, baseline-relative approach '
            'WHOOP describes. ln-transformed RMSSD follows Plews et al. '
            '(Sports Med 2013) and Buchheit (Front Physiol 2014); RMSSD is '
            'defined by the Task Force of the ESC and NASPE (Circulation '
            '1996).',
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Full methodology',
            kind: AppButtonKind.quiet,
            compact: true,
            icon: Icons.menu_book_outlined,
            onTap: () => Navigator.of(context).pushNamed(Routes.methodology),
          ),
        ),
      ),
    ],
  );
}

Future<void> showReadinessExplain(BuildContext context, ReadinessVm? r) {
  final factor = Readiness.swcFactor;
  return showExplainSheet<void>(
    context,
    title: '7-night HRV trend',
    lede:
        'One night\'s HRV is noisy. The 7-night average moves only when '
        'something real has changed, so it is judged against a band of normal '
        'variation rather than a single cut-off.',
    children: [
      ExplainSection(
        title: 'Method',
        body:
            'The average of ln(RMSSD) over the last 7 calendar nights (at '
            'least ${Readiness.minWindowNights}) is compared with your '
            'baseline mean ± $factor × SD of ln(RMSSD), the smallest '
            'worthwhile change. The baseline needs '
            '${Readiness.minBaselineNights} nights. The screen shows the '
            'values converted back to milliseconds.',
        formula:
            'rolling = mean(ln RMSSD, 7 nights)\n'
            'band = baseline mean ± $factor × SD\n'
            'CV = SD / mean of the 7 ln values × 100',
      ),
      if (r != null)
        ExplainSection(
          title: 'Your numbers (ln scale)',
          formula:
              'rolling ${r.swc.lnRmssd7d.toStringAsFixed(3)} '
              '(${r.rollingMs.round()} ms)\n'
              'band ${r.swc.swcLower.toStringAsFixed(3)}–'
              '${r.swc.swcUpper.toStringAsFixed(3)} '
              '(${r.lowerMs.round()}–${r.upperMs.round()} ms)\n'
              'CV ${r.cv.toStringAsFixed(1)} %',
        ),
      const ExplainSection(
        title: 'Reading it',
        body:
            'Inside the band: your HRV is steady. A week below the band is a '
            'more reliable reason to ease off than one low night. A rising '
            'day-to-day variation can flag instability even when the average '
            'looks normal.',
      ),
      const ExplainSection(
        title: 'Sources',
        body:
            'Plews, Laursen, Stanley, Kilding, Buchheit: Training adaptation '
            'and heart rate variability in elite endurance athletes (Sports '
            'Med 2013). Plews et al., Eur J Appl Physiol 2012. Smallest '
            'worthwhile change after Hopkins (Sportscience 2004). The Health '
            'Monitor band uses ± ${HealthMonitor.bandSd} SD instead: a '
            'different question (is tonight unusual?).',
      ),
    ],
  );
}
