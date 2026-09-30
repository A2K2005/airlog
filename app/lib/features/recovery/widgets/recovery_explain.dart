// The Recovery and readiness explain sheets: the exact formulas, the
// constants read from the engine (never retyped), and the sources. When an
// input comes from an app with its own recovery or readiness score, a line
// says this is not that app's score (without naming it) and links to
// Methodology ("Other apps' scores").

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

/// "This isn’t your tracker app’s own score. Here’s why." once, when an app
/// with its own recovery or readiness score supplied a Recovery input. The
/// app isn't named (no brand names in the UI).
List<String> vendorScoreLines(RecoveryState? s) {
  final origins = {
    for (final i in s?.inputs ?? const <InputVm>[]) i.provenance?.origin,
  };
  return [
    if (origins.contains(SourceApps.whoop) ||
        origins.contains(SourceApps.oura))
      'This isn’t your tracker app’s own score. Here’s why.',
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
        'anyone else’s. Everything below is worked out on this phone.',
    children: [
      if (vendor.isNotEmpty)
        ExplainSection(
          title: 'Not your app’s own score',
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
          title: 'This night’s signals',
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
            'HRV ${_w('hrv')} · resting heart rate ${_w('rhr')} · sleep '
            '${_w('sleep')} · breathing rate ${_w('resp')}. If a signal is '
            'missing, the others count for more, so the total is still 100. '
            'Nothing is guessed.',
      ),
      ExplainSection(
        title: 'Each signal, scored 0 to 1',
        body:
            'Each signal is compared with your usual: your last '
            '${_cfg.baselineWindowDays} nights, measured the same way. (z is '
            'how far last night was from your usual, in standard '
            'deviations.)',
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
            'Two warning signs subtract after weighting: overnight blood '
            'oxygen (SpO₂) below ${numText(RE.spo2PenaltyBelow)}% '
            '(−${numText(RE.spo2Penalty)}), and skin temperature more than '
            '${numText(RE.skinTempPenaltyZ)} standard deviations above your '
            'usual (−${numText(RE.skinTempPenalty)}). Breathing rate only '
            'costs points when it’s raised, never when it’s low.',
      ),
      ExplainSection(
        title: 'Score and levels',
        formula:
            'recovery = clamp(100 × Σ weight × score − penalties, '
            '${numText(RE.minScore)}, ${numText(RE.maxScore)})\n'
            'Good (green) ≥ ${RE.greenFrom} · Fair (yellow) ${RE.yellowFrom}–'
            '${RE.greenFrom - 1} · Low (red) < ${RE.yellowFrom}',
      ),
      ExplainSection(
        title: 'Learning',
        body:
            'Until Airlog knows a signal’s usual, it scores a neutral '
            '${numText(RE.neutralScore)}. Recovery says “Learning” until HRV '
            'and resting heart rate each have ${RE.reliableNights} nights, '
            'and “early estimate” until ${_cfg.calibrationNeedNights} '
            'nights. The banner counts them.',
      ),
      ExplainSection(
        title: 'Sources',
        body:
            'Formula ported from Pulse (Luraxx/pulse, Apache-2.0), an '
            'open-source take on the HRV-led approach that compares you with '
            'your own usual. ln-transformed RMSSD follows Plews et al. '
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
    title: '7-night HRV',
    lede:
        'One night of HRV jumps around. A 7-night average moves only when '
        'something real has changed.',
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
            'In your usual range: your HRV is steady. A whole week below it is '
            'a better reason to ease off than one low night. If the '
            'night-to-night swing keeps growing, your body may be less '
            'settled, even when the average looks fine.',
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
