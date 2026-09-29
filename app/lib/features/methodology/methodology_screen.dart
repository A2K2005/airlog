// How scores work: every formula, constant, input, provenance rule and
// citation. Constants are read from the engine itself (RecoveryEngine,
// StrainEngine, HealthMonitor, Readiness, TrendEngine, HrvTools, SleepConfig,
// EngineConfig), so this page cannot drift from the maths it describes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/design.dart';
import '../../domain/engine/engine.dart' show EngineConfig, SleepConfig;
import '../../domain/engine/health_monitor.dart' show HealthMonitor;
import '../../domain/engine/hrv_tools.dart' show HrvTools;
import '../../domain/engine/load_and_trends.dart'
    show TrainingLoadEngine, TrendEngine;
import '../../domain/engine/readiness.dart' show Readiness;
import '../../domain/engine/recovery.dart' show RecoveryEngine;
import '../../domain/engine/sleep.dart' show SleepEngine;
import '../../domain/engine/strain.dart' show StrainEngine;
import '../../domain/engine/stats.dart' show Stats;
import '../../domain/engine/strain_fallback.dart' show StrainDay;
import '../../domain/engine/trimp.dart' show Trimp;
import '../../domain/results.dart';
import '../../app/platform_services.dart';

typedef _R = RecoveryEngine;

String _pct(double f) => '${(f * 100).round()} %';
String _n(double v) => numText(v);
String _hm(double minutes) {
  final m = minutes.round(), h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h ${r.toString().padLeft(2, '0')} min';
}

class MethodologyScreen extends ConsumerStatefulWidget {
  const MethodologyScreen({super.key});

  @override
  ConsumerState<MethodologyScreen> createState() => _MethodologyScreenState();
}

class _MethodologyScreenState extends ConsumerState<MethodologyScreen> {
  static const _sections = [
    'Honesty rules',
    'Recovery',
    'Strain',
    'Sleep',
    'Health Monitor',
    'HRV readiness',
    'Load and trends',
    'Live sessions',
    'Sources and baselines',
    'Other apps’ scores',
    'Citations',
    'Credits',
  ];
  final _keys = {for (final s in _sections) s: GlobalKey()};

  void _jump(String s) {
    final c = _keys[s]?.currentContext;
    if (c == null) return;
    Scrollable.ensureVisible(
      c,
      duration: motion(context, Motion.slow),
      curve: Motion.move,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final open = ref.read(linkOpenerProvider);
    const sleep = SleepConfig();
    const cfg = EngineConfig();
    final w = RecoveryEngine.weights;

    Widget section(String title, List<Widget> children) => Padding(
      key: _keys[title],
      padding: const EdgeInsets.only(top: S.x8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: F.t1.copyWith(color: p.ink)),
          ),
          const SizedBox(height: S.x3),
          ...children,
        ],
      ),
    );
    Widget para(String s) => Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Text(s, style: F.body.copyWith(color: p.ink2)),
    );
    Widget formula(String s) => Container(
      margin: const EdgeInsets.only(bottom: S.x3),
      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
      child: Text(
        s,
        style: F
            .tab(F.bodySm)
            .copyWith(color: p.ink, fontWeight: FontWeight.w600),
      ),
    );
    Widget table(
      List<String> head,
      List<List<String>> rows, {
      List<int>? flex,
    }) {
      final fl = flex ?? List.filled(head.length, 1);
      return Container(
        margin: const EdgeInsets.only(bottom: S.x3),
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < head.length; i++)
                  Expanded(
                    flex: fl[i],
                    child: Text(
                      head[i].toUpperCase(),
                      textAlign: i == 0 ? TextAlign.start : TextAlign.end,
                      style: F.over.copyWith(color: p.ink3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: S.x2),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    for (var i = 0; i < r.length; i++)
                      Expanded(
                        flex: fl[i],
                        child: Text(
                          r[i],
                          textAlign: i == 0 ? TextAlign.start : TextAlign.end,
                          style: F
                              .tab(F.bodySm)
                              .copyWith(
                                color: i == 0 ? p.ink : p.ink2,
                                fontWeight: i == 0
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final floors = {
      for (final k in HealthMetricKind.values)
        k: HealthMonitor.minimumHalfWidth(k),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('How scores work'),
        actions: SampleDataChip.action(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Every number, explained',
              style: F.display.copyWith(color: p.ink),
            ),
            const SizedBox(height: S.x3),
            Text(
              'Each score comes from a published method and your own '
              'baseline, computed on this phone. This page lists all of it: '
              'formulas, constants, inputs and sources. The constants are read '
              'from the engine itself, so the page and the maths cannot '
              'disagree.',
              style: F.body.copyWith(color: p.ink2),
            ),
            const SizedBox(height: S.x3),
            const Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              children: [
                StatePill(label: 'Algorithm v$kAlgoVersion', color: C.health),
                StatePill(label: 'Not medical advice', color: C.neutral),
                StatePill(label: 'Not WHOOP’s formula', color: C.neutral),
              ],
            ),
            const SizedBox(height: S.x5),
            AppCard(
              tone: CardTone.inset,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OverLabel('Contents'),
                  const SizedBox(height: S.x2),
                  Wrap(
                    spacing: S.x4,
                    children: [
                      for (final s in _sections)
                        AppButton(
                          label: s,
                          kind: AppButtonKind.quiet,
                          compact: true,
                          onTap: () => _jump(s),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            section('Honesty rules', [
              const BulletLine(
                'A missing input shows a card that says what is '
                'missing, why, and how to fix it. Airlog never shows a '
                'guessed number.',
                strong: 'No guesses.',
              ),
              BulletLine(
                'Scores are “calibrating” for the first '
                '${_R.reliableNights} nights and “provisional” until '
                '${cfg.calibrationNeedNights}; the baseline banner says '
                'which.',
                strong: 'Calibration is visible.',
              ),
              const BulletLine(
                'A trend arrow appears only for a statistically '
                'significant change. No arrow means no reliable change.',
                strong: 'Arrows are earned.',
              ),
              const BulletLine(
                'Each metric comes from one source at a time, never '
                'an average. A new source starts a new baseline.',
                strong: 'One source per metric.',
              ),
              const BulletLine(
                'Every stored result carries the algorithm version, so '
                'history can be recomputed when a constant changes.',
                strong: 'Versioned.',
              ),
            ]),

            section('Recovery', [
              para(
                'How ready you are today, from last night against your own '
                'baseline: the ${cfg.baselineWindowDays} most recent nights '
                'measured the same way. Each input becomes a 0–1 sub-score; '
                'the weighted sum is the score. Missing inputs are left out '
                'and the other weights re-normalised. No score at all without '
                'HRV or resting heart rate.',
              ),
              formula(
                'recovery = 100 × Σ weightᵢ × sub-scoreᵢ − penalties   '
                '(${_n(_R.minScore)} … ${_n(_R.maxScore)})',
              ),
              table(
                ['Input', 'Weight', 'Sub-score'],
                [
                  [
                    'HRV',
                    _pct(w['hrv']!),
                    'logistic(${_n(_R.hrvLogisticSlope)} × z), z on ln RMSSD',
                  ],
                  [
                    'Resting HR',
                    _pct(w['rhr']!),
                    'logistic(−${_n(_R.rhrLogisticSlope)} × z)',
                  ],
                  [
                    'Sleep',
                    _pct(w['sleep']!),
                    'performance, ${_n(_R.sleepMinScore)} … 1',
                  ],
                  [
                    'Respiratory rate',
                    _pct(w['resp']!),
                    'only a raised rate costs',
                  ],
                ],
                flex: [4, 3, 6],
              ),
              para(
                'Penalties after weighting: overnight SpO₂ minimum below '
                '${_n(_R.spo2PenaltyBelow)} % costs ${_n(_R.spo2Penalty)} '
                'points; skin temperature more than '
                '${_n(_R.skinTempPenaltyZ)} SD above your baseline (minimum '
                'SD ${_n(_R.skinTempMinSd)} °C) costs '
                '${_n(_R.skinTempPenalty)}. Zones: green from '
                '${_R.greenFrom}, yellow ${_R.yellowFrom}–${_R.greenFrom - 1}, '
                'red below ${_R.yellowFrom}. HRV uses a minimum SD of '
                '${_n(_R.hrvMinSd)} on the log scale, resting HR '
                '${_n(_R.rhrMinSd)} bpm and respiratory rate '
                '${_n(_R.respMinSd)} /min, so a very steady baseline cannot '
                'make one night look dramatic. Respiratory rate scores '
                '${_n(_R.respMaxScore)} until it is '
                '${_n(_R.respZAllowance)} SD above your mean, then loses '
                '${_n(_R.respSlope)} per SD (never below '
                '${_n(_R.respMinScore)}). An input without a baseline yet '
                'scores a neutral ${_n(_R.neutralScore)}.',
              ),
            ]),

            section('Strain', [
              para(
                'How hard your heart worked, on a 0–21 scale. Each minute '
                'of heart rate is placed by its share of your heart-rate '
                'reserve (Karvonen); harder minutes weigh much more.',
              ),
              formula(
                '%HRR = (HR − resting) ÷ (max − resting)\n'
                'max = your override, else '
                '${_n(StrainEngine.tanakaIntercept)} − '
                '${_n(StrainEngine.tanakaSlope)} × age (Tanaka)',
              ),
              table(
                ['Load zone', 'From', 'Weight'],
                [
                  for (var i = 0; i < StrainEngine.zoneLowerBounds.length; i++)
                    [
                      StrainEngine.zoneLabels[i],
                      _pct(StrainEngine.zoneLowerBounds[i]),
                      '× ${_n(StrainEngine.zoneWeights[i])}',
                    ],
                ],
                flex: [5, 3, 3],
              ),
              formula(
                'strain = ${_n(StrainEngine.scaleMax)} × '
                '(1 − e^(−load ÷ ${_n(cfg.strainTau)}))',
              ),
              para(
                'The zones on the charts are the familiar display bands: '
                '${StrainEngine.displayZoneLowerBounds.map(_pct).join(' / ')} '
                'of reserve for zones 1–5.',
              ),
              para(
                'Sparse heart rate: if fewer than '
                '${_pct(StrainDay.minCoverage)} of waking minutes have a '
                'reading (or fewer than ${StrainDay.minSamples} samples), '
                'zones would under-count, so the day gets no strain score: '
                'the screen lists what was measured instead (workouts and '
                'steps). A single workout without heart rate inside it uses '
                'its own average HR and is labelled “Estimated”.',
              ),
              para(
                'Target: ${_n(StrainEngine.targetFactor)} × the morning’s '
                'recovery, kept between ${_n(StrainEngine.targetMin)} and '
                '${_n(StrainEngine.targetMax)}. Cross-check: Banister TRIMP '
                'over the same minutes, weighted '
                '${_n(Trimp.maleA)}·e^(${_n(Trimp.maleB)}x) (male) or '
                '${_n(Trimp.femaleA)}·e^(${_n(Trimp.femaleB)}x) (female), '
                'the mean of both when not specified.',
              ),
            ]),

            section('Sleep', [
              formula(
                'target = ${_hm(sleep.baselineNeedMinutes)} '
                '+ ${_pct(sleep.debtRepayFraction)} of debt '
                '+ up to ${_n(sleep.strainNeedBoostMaxMinutes)} min for strain '
                'above ${_n(SleepEngine.strainBoostFrom)}\n'
                'boost = clamp((strain − ${_n(SleepEngine.strainBoostFrom)}) ÷ '
                '${_n(SleepEngine.strainBoostSpan)}, 0, 1) × '
                '${_n(sleep.strainNeedBoostMaxMinutes)} min',
              ),
              para(
                'The target is kept between '
                '${_n(SleepEngine.needBelowBaselineMinutes)} minutes under and '
                '${_n(SleepEngine.needAboveBaselineMinutes)} minutes over '
                'the baseline. Performance is sleep ÷ target (naps count). '
                'Debt carries forward night to night, gains at most '
                '${_n(sleep.maxDebtGainPerNightMinutes)} min a night and is '
                'capped at ${_hm(sleep.maxDebtMinutes)}. Consistency compares '
                'bed and wake times over the last '
                '${SleepEngine.consistencyWindow} nights: 100 % is the same '
                'times, 0 % an average shift of '
                '${_n(SleepEngine.consistencyZeroMinutes)} minutes. Tonight’s '
                'bedtime is your average wake time over the last '
                '${SleepEngine.bedtimeWakeDays} days minus the projected '
                'target.',
              ),
            ]),

            section('Health Monitor', [
              para(
                'Each overnight signal is compared with your usual range: '
                'baseline ± ${_n(HealthMonitor.bandSd)} SD (about 90 % of '
                'your nights), never narrower than a floor, so a very steady '
                'metric is not over-sensitive.',
              ),
              table(
                ['Metric', 'Floor ±'],
                [
                  for (final e in floors.entries)
                    [e.key.label, '${_n(e.value)} ${e.key.unit}'],
                ],
                flex: [5, 3],
              ),
              para(
                'Each range is built from the last '
                '${cfg.baselineWindowDays} nights measured the same way and '
                'appears after ${_R.reliableNights} of them. SpO₂ has only a '
                'floor, never below ${_n(HealthMonitor.spo2HardFloor)} %.',
              ),
              para(
                'An alert needs two metrics out of range on the same day, or '
                'one for two days running. Out of range is shown in amber, '
                'never alarm red: it is a prompt to look, not a diagnosis.',
              ),
            ]),

            section('HRV readiness', [
              para(
                'Following Plews et al.: the ${Readiness.minWindowNights}+ '
                'nights of the last week are averaged on the log scale and '
                'compared with your smallest worthwhile change, baseline '
                '± ${_n(Readiness.swcFactor)} SD of ln RMSSD (needs '
                '${Readiness.minBaselineNights} baseline nights). The weekly '
                'coefficient of variation is shown alongside; a rising one '
                'flags instability even when the mean looks normal.',
              ),
            ]),

            section('Load and trends', [
              para(
                'Training load is the acute:chronic ratio: mean daily strain '
                'over ${TrainingLoadEngine.acuteDays} days ÷ over '
                '${TrainingLoadEngine.chronicDays} days, needing '
                '${TrainingLoadEngine.minDays} days of strain. Below '
                '${_n(TrainingLoadEngine.optimalFrom)} detraining, '
                '${_n(TrainingLoadEngine.optimalFrom)}–'
                '${_n(TrainingLoadEngine.optimalTo)} steady, '
                '${_n(TrainingLoadEngine.optimalTo)}–'
                '${_n(TrainingLoadEngine.elevatedTo)} elevated, above '
                '${_n(TrainingLoadEngine.elevatedTo)} high (Gabbett 2016). Days '
                'without data are skipped, not counted as rest.',
              ),
              para(
                'Trends use the Mann–Kendall test (two-sided, |Z| > '
                '${TrendEngine.zCritical.toStringAsFixed(2)}, p < 0.05, at '
                'least ${TrendEngine.minN} measured days) with Sen’s slope for '
                'the size.',
              ),
            ]),

            section('Live sessions', [
              formula(
                'HRR-60 = HR at Stop − HR 60 s later   (readings within ±10 s)',
              ),
              para(
                'Heart-rate recovery after a workout, from 1-second Bluetooth '
                'heart rate (Cole et al. 1999). The live screen keeps '
                'recording for 60 s after Stop to measure it.',
              ),
              para(
                'HRV check: beat-to-beat (RR) intervals are cleaned first '
                '(${_n(HrvTools.minRrMs)}–${_n(HrvTools.maxRrMs)} ms, no jump '
                'over ${_pct(HrvTools.maxRelativeJump)} from the previous '
                'good beat). RMSSD (Task Force 1996) needs '
                '${HrvTools.minCleanForRmssd} clean intervals. Only '
                'available when your tracker sends RR intervals.',
              ),
            ]),

            section('Sources and baselines', [
              table(
                ['Metric', 'First available wins'],
                const [
                  [
                    'HRV',
                    'Google Health deep-sleep RMSSD › Health Connect sleep-mean RMSSD',
                  ],
                  [
                    'Resting HR, sleep, breathing, skin temp, workouts, steps, HR',
                    'Health Connect › Google Health API › Takeout',
                  ],
                  [
                    'SpO₂',
                    'Health Connect (overnight, from any app), else Google Health API',
                  ],
                  ['Live heart rate', 'Bluetooth only'],
                ],
                flex: [4, 5],
              ),
              para(
                'Within Health Connect each metric comes from one app at a '
                'time (your pick in Settings → Sources, or the automatic '
                'one), never a mix. Each value carries its source, definition '
                'and app; a baseline is built only from nights measured the '
                'same way by the same app as today, so a change of app, or '
                'from all-night to deep-sleep HRV, starts a new baseline '
                'instead of mixing the two. Demo and live data are stored '
                'apart.',
              ),
              para(
                'Calibration: fewer than ${_R.reliableNights} baseline '
                'nights = calibrating; ${_R.reliableNights}–'
                '${cfg.calibrationNeedNights - 1} = provisional; '
                '${cfg.calibrationNeedNights} or more = established. A '
                'baseline needs at least ${Stats.minBaselineValues} nights '
                'before it exists at all.',
              ),
            ]),

            section('Other apps’ scores', [
              para(
                'WHOOP’s Recovery and Oura’s Readiness are those apps’ own '
                'scores. Airlog does not show or copy them. It computes its '
                'own Recovery from the measurements the app writes to Health '
                'Connect (HRV, resting heart rate, sleep, breathing), with '
                'the same published formula for every device and your '
                'baseline on this phone.',
              ),
              para(
                'So the two numbers differ. The apps’ formulas, weights and '
                'baselines are their own and unpublished, and they may use '
                'measurements they do not write to Health Connect. Neither '
                'number is wrong: compare Airlog’s Recovery with itself over '
                'time, not with the other app’s score.',
              ),
            ]),

            section('Citations', const [
              BulletLine(
                'Karvonen MJ, Kentala E, Mustala O (1957). The effects '
                'of training on heart rate; a longitudinal study. Ann Med Exp '
                'Biol Fenn.',
              ),
              BulletLine(
                'Banister EW (1991). Modeling elite athletic '
                'performance. In: Physiological Testing of the '
                'High-Performance Athlete.',
              ),
              BulletLine(
                'Morton RH, Fitz-Clarke JR, Banister EW (1990). '
                'Modeling human performance in running. J Appl Physiol.',
              ),
              BulletLine(
                'Tanaka H, Monahan KD, Seals DR (2001). Age-predicted '
                'maximal heart rate revisited. J Am Coll Cardiol.',
              ),
              BulletLine(
                'Cole CR et al. (1999). Heart-rate recovery immediately '
                'after exercise as a predictor of mortality. N Engl J Med.',
              ),
              BulletLine(
                'Plews DJ et al. (2012). Heart rate variability in elite '
                'triathletes: is variation in variability the key to '
                'effective training? Eur J Appl Physiol.',
              ),
              BulletLine(
                'Plews DJ et al. (2013). Training adaptation and heart '
                'rate variability in elite endurance athletes: opening the '
                'door to effective monitoring. Sports Med.',
              ),
              BulletLine(
                'Task Force of the ESC and NASPE (1996). Heart rate '
                'variability: standards of measurement, physiological '
                'interpretation and clinical use. Circulation.',
              ),
              BulletLine(
                'Gabbett TJ (2016). The training-injury prevention '
                'paradox. Br J Sports Med.',
              ),
              BulletLine(
                'WHOOP’s public articles on recovery, strain and sleep '
                'were read for inspiration only. No WHOOP formula or code is '
                'used, and the numbers are not comparable.',
              ),
            ]),

            section('Credits', [
              para(
                'Airlog stands on two open-source projects. Ported files '
                'name their origin in a header.',
              ),
              _Credit(
                title: 'Pulse (Apache-2.0)',
                body:
                    'Recovery, Strain, Sleep, Health Monitor and journal '
                    'formulas and constants; the demo-data idea; the '
                    'sync-log pattern.',
                onTap: () => open(Uri.parse('https://github.com/Luraxx/pulse')),
              ),
              const SizedBox(height: S.x3),
              _Credit(
                title: 'Edge (MIT)',
                body:
                    'Chart painters, the theme and contrast solver, the '
                    'motion gate and the Bluetooth heart-rate parser. Type: DM '
                    'Sans (OFL) and Subway Ticker Grid (K-Type, personal-use '
                    'licence).',
                onTap: () =>
                    open(Uri.parse('https://github.com/OpenStrap/edge')),
              ),
              const SizedBox(height: S.x4),
              Text(
                'WHOOP is a trademark of WHOOP, Inc. Google, Fitbit, Fitbit '
                'Air and Google Health are trademarks of Google LLC. Airlog is '
                'independent and not affiliated with any of them.',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit({required this.title, required this.body, required this.onTap});
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      onTap: onTap,
      semanticLabel: '$title. $body. Opens the project page.',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: F.head.copyWith(color: p.ink)),
                  const SizedBox(height: 2),
                  Text(body, style: F.bodySm.copyWith(color: p.ink2)),
                ],
              ),
            ),
            const SizedBox(width: S.x2),
            Icon(Icons.open_in_new_rounded, size: 18, color: p.ink3),
          ],
        ),
      ),
    );
  }
}
