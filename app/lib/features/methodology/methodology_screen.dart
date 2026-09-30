// How scores work: every score as a tile that shows what goes into it (the
// weights, the multipliers, the minutes, the bands), with the maths one ⓘ
// away. The formulas, constants and tables in the sheets are read from the
// engine itself (RecoveryEngine, StrainEngine, HealthMonitor, Readiness,
// TrendEngine, HrvTools, SleepConfig, EngineConfig), so the page cannot
// drift from the maths it describes. Method names and citations live in
// the sheets, never on the page.

import 'package:flutter/material.dart';

import '../../app/route_names.dart';
import '../../app/screen_kit.dart' show IconBadge, InfoButton;
import '../../design/design.dart';
import '../../domain/engine/engine.dart' show EngineConfig, SleepConfig;
import '../../domain/engine/health_monitor.dart' show HealthMonitor;
import '../../domain/engine/hrv_tools.dart' show HrvTools;
import '../../domain/engine/load_and_trends.dart'
    show TrainingLoadEngine, TrendEngine;
import '../../domain/engine/readiness.dart' show Readiness;
import '../../domain/engine/recovery.dart' show RecoveryEngine;
import '../../domain/engine/sleep.dart' show SleepEngine;
import '../../domain/engine/stats.dart' show Stats;
import '../../domain/engine/strain.dart' show StrainEngine;
import '../../domain/engine/strain_fallback.dart' show StrainDay;
import '../../domain/engine/trimp.dart' show Trimp;
import '../../domain/results.dart';

typedef _R = RecoveryEngine;
typedef _L = TrainingLoadEngine;

String _pct(double f) => '${(f * 100).round()}%';
String _n(double v) => numText(v);

String _signal(HealthMetricKind k) => switch (k) {
  HealthMetricKind.restingHr => 'Resting HR',
  HealthMetricKind.hrv => 'HRV',
  HealthMetricKind.respiratoryRate => 'Breathing rate',
  HealthMetricKind.spo2 => 'Blood oxygen',
  HealthMetricKind.skinTemp => 'Skin temperature',
};

class MethodologyScreen extends StatelessWidget {
  const MethodologyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    const sleep = SleepConfig();
    const cfg = EngineConfig();
    final w = RecoveryEngine.weights;

    Widget line(String s) => SettingsBlock(
      bottom: 0,
      child: Text(s, style: F.bodySm.copyWith(color: p.ink2)),
    );
    Widget labelled(String over, Widget child) => SettingsBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [OverLabel(over), const SizedBox(height: S.x2), child],
      ),
    );
    InfoButton info(
      String title,
      String lede,
      List<Widget> sections, {
      String? semanticLabel,
    }) => InfoButton(
      title: title,
      lede: lede,
      footnote: ExplainSheet.defaultFootnote,
      semanticLabel: semanticLabel,
      children: sections,
    );

    final tiles = <Widget>[
      // ── Honesty rules ─────────────────────────────────────────────────
      SettingsTile(
        title: 'Honesty rules',
        icon: Icons.verified_outlined,
        accent: C.health,
        dividers: false,
        info: info(
          'Honesty rules',
          'Every score uses a published method and your own usual, worked '
              'out on this phone. The numbers in these sheets come straight '
              'from the app’s code, so they always match what you see.',
          [
            ExplainSection(
              title: 'The rules',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BulletLine(
                    'When something is missing, a card says what, why, and '
                    'how to fix it. Airlog never shows a guessed number.',
                    strong: 'No guesses.',
                  ),
                  BulletLine(
                    'Scores say “Learning” for the first ${_R.reliableNights} '
                    'nights and “early estimate” until night '
                    '${cfg.calibrationNeedNights}. The banner on Today says '
                    'which.',
                    strong: 'Learning is shown.',
                  ),
                  const BulletLine(
                    'A trend arrow shows only for a real change, tested with '
                    'statistics. No arrow means no clear change.',
                    strong: 'Arrows are earned.',
                  ),
                  const BulletLine(
                    'Each measurement comes from one app at a time, never an '
                    'average. A new app means Airlog learns your usual again.',
                    strong: 'One app per measurement.',
                  ),
                  const BulletLine(
                    'Every saved score records its formula version, so your '
                    'history can be worked out again if the formula changes.',
                    strong: 'Versioned.',
                  ),
                ],
              ),
            ),
          ],
        ),
        children: const [
          SettingsBlock(
            child: _RuleGrid([
              (Icons.help_outline_rounded, 'No guesses'),
              (Icons.hourglass_top_rounded, 'Learning is shown'),
              (Icons.trending_up_rounded, 'Arrows are earned'),
              (Icons.looks_one_outlined, 'One app per measurement'),
              (Icons.history_rounded, 'Versioned'),
            ]),
          ),
        ],
      ),

      // ── Recovery ──────────────────────────────────────────────────────
      SettingsTile(
        glow: GlowRecipes.l5,
        title: 'Recovery',
        icon: Icons.wb_twilight_rounded,
        accent: C.recGreen,
        dividers: false,
        info: info(
          'How Recovery works',
          'In short: how ready you are today, from last night compared with '
              'your usual. Your usual is your ${cfg.baselineWindowDays} most '
              'recent nights, measured the same way. Each signal gets a score '
              'from 0 to 1, and the weighted total is your Recovery. If a '
              'signal is missing, the others count for more. There’s no score '
              'at all without HRV or resting heart rate.',
          [
            ExplainSection(
              title: 'Formula',
              formula:
                  'recovery = 100 × Σ weightᵢ × sub-scoreᵢ − penalties   '
                  '(${_n(_R.minScore)} … ${_n(_R.maxScore)})',
            ),
            ExplainSection(
              title: 'Signals',
              child: _Table(
                ['Signal', 'Weight', 'Sub-score'],
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
                    'Breathing rate',
                    _pct(w['resp']!),
                    'only a raised rate costs points',
                  ],
                ],
                flex: const [4, 3, 6],
              ),
            ),
            ExplainSection(
              title: 'Penalties and limits',
              body:
                  'Penalties after weighting: overnight blood oxygen (SpO₂) '
                  'below ${_n(_R.spo2PenaltyBelow)}% costs '
                  '${_n(_R.spo2Penalty)} points; skin temperature more than '
                  '${_n(_R.skinTempPenaltyZ)} SD above your usual (minimum SD '
                  '${_n(_R.skinTempMinSd)} °C) costs '
                  '${_n(_R.skinTempPenalty)}. Levels: Good (green) from '
                  '${_R.greenFrom}, Fair (yellow) '
                  '${_R.yellowFrom}–${_R.greenFrom - 1}, Low (red) below '
                  '${_R.yellowFrom}. HRV uses a minimum SD of '
                  '${_n(_R.hrvMinSd)} on the log scale, resting heart rate '
                  '${_n(_R.rhrMinSd)} bpm and breathing rate '
                  '${_n(_R.respMinSd)} /min, so a very steady usual can’t make '
                  'one night look dramatic. Breathing rate scores '
                  '${_n(_R.respMaxScore)} until it’s '
                  '${_n(_R.respZAllowance)} SD above your usual, then loses '
                  '${_n(_R.respSlope)} per SD (never below '
                  '${_n(_R.respMinScore)}). A signal Airlog hasn’t learned yet '
                  'scores a neutral ${_n(_R.neutralScore)}.',
            ),
          ],
        ),
        children: [
          line('How ready your body is today, from 1 to 99%.'),
          labelled(
            'What counts',
            InputWeightBar(
              parts: [
                WeightPart(
                  'HRV',
                  w['hrv']!,
                  C.recGreen,
                  valueText: _pct(w['hrv']!),
                ),
                WeightPart(
                  'Resting heart rate',
                  w['rhr']!,
                  C.health,
                  valueText: _pct(w['rhr']!),
                ),
                WeightPart(
                  'Sleep',
                  w['sleep']!,
                  C.sleep,
                  valueText: _pct(w['sleep']!),
                ),
                WeightPart(
                  'Breathing rate',
                  w['resp']!,
                  C.sky,
                  valueText: _pct(w['resp']!),
                ),
              ],
            ),
          ),
          labelled(
            'Can take points off',
            Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              children: [
                MetricChip(
                  label: 'Blood oxygen below ${_n(_R.spo2PenaltyBelow)}%',
                  style: MetricChipStyle.penalty,
                ),
                const MetricChip(
                  label: 'Skin temperature well above usual',
                  style: MetricChipStyle.penalty,
                ),
              ],
            ),
          ),
          labelled(
            'Levels',
            BandScale(
              bands: [
                ScaleBand(
                  'Low',
                  '${_n(_R.minScore)}–${_R.yellowFrom - 1}',
                  C.recRed,
                ),
                const ScaleBand(
                  'Fair',
                  '${_R.yellowFrom}–${_R.greenFrom - 1}',
                  C.recYellow,
                ),
                ScaleBand(
                  'Good',
                  '${_R.greenFrom}–${_n(_R.maxScore)}',
                  C.recGreen,
                ),
              ],
            ),
          ),
        ],
      ),

      // ── Strain ────────────────────────────────────────────────────────
      SettingsTile(
        glow: GlowRecipes.l6,
        title: 'Strain',
        icon: Icons.bolt_rounded,
        accent: DomainColors.strain,
        dividers: false,
        info: info(
          'How Strain works',
          'In short: how hard your heart worked today, from 0 to 21. Each '
              'minute of heart rate is placed by how close it was to your max, '
              'counting up from your resting heart rate (Karvonen). Harder '
              'minutes count for much more.',
          [
            ExplainSection(
              title: 'Heart-rate reserve',
              formula:
                  '%HRR = (HR − resting) ÷ (max − resting)\n'
                  'max = your override, else '
                  '${_n(StrainEngine.tanakaIntercept)} − '
                  '${_n(StrainEngine.tanakaSlope)} × age (Tanaka)',
            ),
            ExplainSection(
              title: 'Scoring bands',
              child: _Table(
                ['Scoring band', 'From', 'Weight'],
                [
                  for (var i = 0; i < StrainEngine.zoneLowerBounds.length; i++)
                    [
                      StrainEngine.zoneLabels[i],
                      _pct(StrainEngine.zoneLowerBounds[i]),
                      '× ${_n(StrainEngine.zoneWeights[i])}',
                    ],
                ],
                flex: const [5, 3, 3],
              ),
            ),
            ExplainSection(
              title: 'Scale',
              formula:
                  'strain = ${_n(StrainEngine.scaleMax)} × '
                  '(1 − e^(−load ÷ ${_n(cfg.strainTau)}))',
            ),
            ExplainSection(
              title: 'Chart zones',
              body:
                  'The five zones on the charts are simpler display bands. '
                  'They start at '
                  '${StrainEngine.displayZoneLowerBounds.map(_pct).join(' / ')} '
                  'of your heart-rate reserve (zones 1–5).',
            ),
            ExplainSection(
              title: 'Patchy heart rate',
              body:
                  'If fewer than ${_pct(StrainDay.minCoverage)} of waking '
                  'minutes have a reading (or fewer than '
                  '${StrainDay.minSamples} readings), zones would undercount, '
                  'so the day gets no Strain score. The screen lists what was '
                  'measured instead (workouts and steps). A single workout '
                  'with no heart rate inside it uses its own average heart '
                  'rate and is labelled “Estimated”.',
            ),
            ExplainSection(
              title: 'Effort goal and second opinion',
              body:
                  'Effort goal: ${_n(StrainEngine.targetFactor)} × the '
                  'morning’s Recovery, kept between '
                  '${_n(StrainEngine.targetMin)} and '
                  '${_n(StrainEngine.targetMax)}. Second opinion: Banister '
                  'TRIMP over the same minutes, weighted '
                  '${_n(Trimp.maleA)}·e^(${_n(Trimp.maleB)}x) (male) or '
                  '${_n(Trimp.femaleA)}·e^(${_n(Trimp.femaleB)}x) (female), '
                  'the mean of both when sex isn’t set. It doesn’t change any '
                  'score.',
            ),
          ],
        ),
        children: [
          line('How hard your heart worked today, from 0 to 21.'),
          labelled(
            'Harder minutes count more',
            WeightStepBars(
              color: DomainColors.strain,
              weightText: (v) => '×${_n(v)}',
              steps: [
                for (var i = 0; i < StrainEngine.zoneLowerBounds.length; i++)
                  (
                    StrainEngine.zoneLabels[i],
                    'from ${_pct(StrainEngine.zoneLowerBounds[i])}',
                    StrainEngine.zoneWeights[i],
                  ),
              ],
            ),
          ),
          labelled(
            'Effort goal',
            Text(
              'Your Recovery × ${_n(StrainEngine.targetFactor)}, kept between '
              '${_n(StrainEngine.targetMin)} and '
              '${_n(StrainEngine.targetMax)}.',
              style: F.bodySm.copyWith(color: p.ink),
            ),
          ),
        ],
      ),

      // ── Sleep ─────────────────────────────────────────────────────────
      SettingsTile(
        glow: GlowRecipes.l1,
        title: 'Sleep',
        icon: Icons.bedtime_outlined,
        accent: C.sleep,
        dividers: false,
        info: info(
          'How your sleep goal is set',
          'In short: your sleep goal, missed sleep, and how regular your sleep '
              'is.',
          [
            ExplainSection(
              title: 'Formula',
              formula:
                  'goal = ${durationWords(sleep.baselineNeedMinutes)} '
                  '+ ${_pct(sleep.debtRepayFraction)} of missed sleep '
                  '+ up to ${_n(sleep.strainNeedBoostMaxMinutes)} min for '
                  'Strain above ${_n(SleepEngine.strainBoostFrom)}\n'
                  'boost = clamp((strain − ${_n(SleepEngine.strainBoostFrom)}) '
                  '÷ ${_n(SleepEngine.strainBoostSpan)}, 0, 1) × '
                  '${_n(sleep.strainNeedBoostMaxMinutes)} min',
            ),
            ExplainSection(
              title: 'Details',
              body:
                  'The goal stays between '
                  '${_n(SleepEngine.needBelowBaselineMinutes)} minutes under '
                  'and ${_n(SleepEngine.needAboveBaselineMinutes)} minutes '
                  'over your usual need. Your sleep % is sleep ÷ goal (naps '
                  'count). Missed sleep carries over from night to night, '
                  'grows by at most ${_n(sleep.maxDebtGainPerNightMinutes)} '
                  'min a night, and never goes above '
                  '${durationWords(sleep.maxDebtMinutes)}. Consistency '
                  'compares bed and wake times over the last '
                  '${SleepEngine.consistencyWindow} nights: 100% means the '
                  'same times, 0% means '
                  '${_n(SleepEngine.consistencyZeroMinutes)} minutes off on '
                  'average. Tonight’s bedtime is your usual wake-up time over '
                  'the last ${SleepEngine.bedtimeWakeDays} days, minus the '
                  'sleep goal.',
            ),
          ],
        ),
        children: [
          line('Your sleep goal for tonight.'),
          SettingsBlock(
            child: InputWeightBar(
              parts: [
                WeightPart(
                  'Usual need',
                  sleep.baselineNeedMinutes,
                  C.sleep,
                  valueText: durationWords(sleep.baselineNeedMinutes),
                ),
                WeightPart(
                  'Catch-up',
                  sleep.debtRepayFraction * sleep.maxDebtMinutes,
                  C.sleep,
                  valueText: '${_pct(sleep.debtRepayFraction)} of missed sleep',
                  hatched: true,
                ),
                WeightPart(
                  'Hard day',
                  sleep.strainNeedBoostMaxMinutes,
                  C.violet,
                  valueText:
                      'up to ${_n(sleep.strainNeedBoostMaxMinutes)} min',
                  hatched: true,
                ),
              ],
            ),
          ),
        ],
      ),

      // ── Overnight signals ─────────────────────────────────────────────
      SettingsTile(
        glow: GlowRecipes.m5,
        title: 'Overnight signals',
        icon: Icons.monitor_heart_outlined,
        accent: C.sky,
        dividers: false,
        info: info(
          'Overnight signals',
          'In short: five overnight readings, each checked against your usual '
              'range. The range is your usual ± '
              '${_n(HealthMonitor.bandSd)} SD (about 9 in 10 of your nights), '
              'and never narrower than a set floor, so a very steady signal '
              'isn’t too touchy.',
          [
            ExplainSection(
              title: 'Floors',
              child: _Table(
                ['Signal', 'Floor ±'],
                [
                  for (final k in HealthMetricKind.values)
                    [
                      _signal(k),
                      '${_n(HealthMonitor.minimumHalfWidth(k))} ${k.unit}',
                    ],
                ],
                flex: const [5, 3],
              ),
            ),
            ExplainSection(
              title: 'Your usual range',
              body:
                  'Each range comes from your last ${cfg.baselineWindowDays} '
                  'nights measured the same way, and shows up after '
                  '${_R.reliableNights} of them. Blood oxygen (SpO₂) has only '
                  'a floor, never below ${_n(HealthMonitor.spo2HardFloor)}%.',
            ),
            const ExplainSection(
              title: 'When a card appears',
              body:
                  'A card appears when two signals are out of range on the '
                  'same day, or one is out for two days running. Out of range '
                  'shows in amber, never alarm red: it’s a prompt to look, not '
                  'a diagnosis.',
            ),
          ],
        ),
        children: [
          line('Five readings from your sleep, each checked against your usual.'),
          SettingsBlock(
            child: Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              children: [
                for (final k in HealthMetricKind.values)
                  MetricChip(label: _signal(k)),
              ],
            ),
          ),
          line(
            'A card shows when 2 are out of range on one day, or 1 for 2 days.',
          ),
          const SizedBox(height: S.x3),
        ],
      ),

      // ── HRV this week ─────────────────────────────────────────────────
      SettingsTile(
        glow: GlowRecipes.m12,
        title: 'HRV this week',
        icon: Icons.show_chart_rounded,
        accent: C.health,
        dividers: false,
        info: info(
          'HRV this week',
          'In short: your 7-night HRV average, compared with your usual. '
              'Following Plews et al., the ${Readiness.minWindowNights}+ '
              'nights of the last week are averaged on the log scale and '
              'compared with your smallest worthwhile change: your usual ± '
              '${_n(Readiness.swcFactor)} SD of ln RMSSD (after '
              '${Readiness.minBaselineNights} nights). The night-to-night '
              'swing (coefficient of variation) shows alongside. If it keeps '
              'rising, your body may be less settled even when the average '
              'looks fine.',
          const [],
        ),
        children: [
          line('Your 7-night HRV average, compared with your usual.'),
          const SizedBox(height: S.x3),
        ],
      ),

      // ── Training load ─────────────────────────────────────────────────
      SettingsTile(
        glow: GlowRecipes.m20,
        title: 'Training load',
        icon: Icons.trending_up_rounded,
        accent: C.health,
        dividers: false,
        info: info(
          'Training load and trends',
          'In short: your last 7 days compared with your last 4 weeks. '
              'Training load is the acute:chronic ratio: average daily Strain '
              'over ${_L.acuteDays} days ÷ over ${_L.chronicDays} days, after '
              '${_L.minDays} days of Strain. Below ${_n(_L.optimalFrom)}: '
              'less than usual. ${_n(_L.optimalFrom)}–${_n(_L.optimalTo)}: '
              'about usual. ${_n(_L.optimalTo)}–${_n(_L.elevatedTo)}: more '
              'than usual. Above ${_n(_L.elevatedTo)}: much more than usual '
              '(Gabbett 2016). Days without data are skipped, not counted as '
              'rest.',
          [
            ExplainSection(
              title: 'Trends',
              body:
                  'A trend arrow shows only for a real change. Trends use the '
                  'Mann–Kendall test (two-sided, |Z| > '
                  '${TrendEngine.zCritical.toStringAsFixed(2)}, p < 0.05, at '
                  'least ${TrendEngine.minN} measured days) with Sen’s slope '
                  'for the size.',
            ),
          ],
        ),
        children: [
          line('Your last 7 days compared with your last 4 weeks.'),
          SettingsBlock(
            child: BandScale(
              bands: [
                ScaleBand(
                  'Less than usual',
                  'below ${_n(_L.optimalFrom)}',
                  DomainColors.load(LoadState.detraining),
                ),
                ScaleBand(
                  'About usual',
                  '${_n(_L.optimalFrom)}–${_n(_L.optimalTo)}',
                  DomainColors.load(LoadState.optimal),
                ),
                ScaleBand(
                  'More than usual',
                  '${_n(_L.optimalTo)}–${_n(_L.elevatedTo)}',
                  DomainColors.load(LoadState.elevated),
                ),
                ScaleBand(
                  'Much more than usual',
                  'above ${_n(_L.elevatedTo)}',
                  DomainColors.load(LoadState.high),
                ),
              ],
            ),
          ),
        ],
      ),

      // ── Live heart rate ───────────────────────────────────────────────
      SettingsTile(
        glow: GlowRecipes.m16,
        title: 'Live heart rate',
        icon: Icons.favorite_border_rounded,
        accent: C.recRed,
        dividers: false,
        info: info(
          'Live heart rate',
          'In short: how fast your heart rate drops after a workout, and the '
              'HRV check.',
          [
            const ExplainSection(
              title: 'Heart-rate recovery',
              formula:
                  'HRR-60 = HR at Stop − HR 60 s later   (readings within '
                  '±10 s)',
              body:
                  'Heart-rate recovery comes from second-by-second Bluetooth '
                  'heart rate (Cole et al. 1999). The live screen keeps '
                  'recording for 60 s after you tap Stop to measure it.',
            ),
            ExplainSection(
              title: 'HRV check',
              body:
                  'Beat-to-beat (RR) intervals are cleaned first '
                  '(${_n(HrvTools.minRrMs)}–${_n(HrvTools.maxRrMs)} ms, no '
                  'jump over ${_pct(HrvTools.maxRelativeJump)} from the '
                  'previous good beat). RMSSD (Task Force 1996) needs '
                  '${HrvTools.minCleanForRmssd} clean intervals. It only works '
                  'when your tracker sends RR intervals.',
            ),
          ],
        ),
        children: [
          line('Heart-rate recovery: how far your heart rate drops in 1 minute.'),
          line('HRV check: 2 minutes sitting still.'),
          const SizedBox(height: S.x3),
        ],
      ),

      // ── Your usual ────────────────────────────────────────────────────
      SettingsTile(
        glow: GlowRecipes.m8,
        title: 'Your usual',
        icon: Icons.tune_rounded,
        accent: C.lavender,
        dividers: false,
        info: info(
          'Data sources and your usual',
          'Within Health Connect, each measurement comes from one app at a '
              'time (your pick in Settings → Data sources, or the automatic '
              'one), never a mix. Your usual is built only from nights '
              'measured the same way by the same app as today. So if you '
              'switch apps, or go from all-night to deep-sleep HRV, Airlog '
              'learns your usual again instead of mixing the two. Sample data '
              'and your data are stored apart.',
          [
            const ExplainSection(
              title: 'Where it comes from',
              child: _Table(
                ['Measurement', 'Where it comes from (first available)'],
                [
                  [
                    'HRV',
                    'Enhanced mode deep-sleep HRV › Health Connect overnight '
                        'HRV',
                  ],
                  [
                    'Resting heart rate, sleep, breathing, skin temperature, '
                        'workouts, steps, heart rate',
                    'Health Connect › Enhanced mode',
                  ],
                  [
                    'Blood oxygen',
                    'Health Connect (overnight, from any app), else Enhanced '
                        'mode',
                  ],
                  ['Live heart rate', 'Bluetooth only'],
                ],
                flex: [4, 5],
              ),
            ),
            ExplainSection(
              title: 'Learning',
              body:
                  'Fewer than ${_R.reliableNights} nights = “Learning”; '
                  '${_R.reliableNights}–${cfg.calibrationNeedNights - 1} = '
                  '“early estimate”; ${cfg.calibrationNeedNights} or more = '
                  'settled. Airlog needs at least ${Stats.minBaselineValues} '
                  'nights before it has a usual at all.',
            ),
          ],
        ),
        children: [
          line('One app per measurement. Switching apps starts learning again.'),
          SettingsBlock(
            child: BandScale(
              bands: [
                const ScaleBand(
                  'Learning',
                  '0–${_R.reliableNights - 1} nights',
                  C.neutral,
                ),
                ScaleBand(
                  'Early estimate',
                  '${_R.reliableNights}–${cfg.calibrationNeedNights - 1}',
                  C.amber,
                ),
                ScaleBand(
                  'Settled',
                  '${cfg.calibrationNeedNights}+',
                  C.health,
                ),
              ],
            ),
          ),
        ],
      ),

      // ── Other apps' scores ────────────────────────────────────────────
      SettingsTile(
        title: 'Other apps’ scores',
        icon: Icons.apps_rounded,
        dividers: false,
        info: info(
          'Other apps’ scores',
          'Some trackers’ apps show their own recovery or readiness score. '
              'Airlog doesn’t show or copy them. It works out its own Recovery '
              'from the measurements the app shares with Health Connect, with '
              'the same published formula for every device and your usual on '
              'this phone.',
          const [
            ExplainSection(
              title: 'Why the numbers differ',
              body:
                  'Those apps’ formulas, weights and baselines are their own '
                  'and unpublished, and they may use measurements they don’t '
                  'share with Health Connect. Neither number is wrong: compare '
                  'Airlog’s Recovery with itself over time, not with the other '
                  'app’s score.',
            ),
          ],
        ),
        children: [
          line('Other apps’ scores are their own. Compare Airlog with itself.'),
          const SizedBox(height: S.x3),
        ],
      ),

      // ── Research, licences ────────────────────────────────────────────
      SettingsTile(
        children: [
          SettingsRow(
            icon: Icons.menu_book_outlined,
            title: 'Research behind the scores',
            onTap: () => showExplainSheet<void>(
              context,
              title: 'Research behind the scores',
              lede: 'The published methods Airlog uses.',
              footnote: null,
              children: const [
                ExplainSection(
                  title: 'Citations',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BulletLine(
                        'Karvonen MJ, Kentala E, Mustala O (1957). The effects '
                        'of training on heart rate; a longitudinal study. Ann '
                        'Med Exp Biol Fenn.',
                      ),
                      BulletLine(
                        'Banister EW (1991). Modeling elite athletic '
                        'performance. In: Physiological Testing of the '
                        'High-Performance Athlete.',
                      ),
                      BulletLine(
                        'Morton RH, Fitz-Clarke JR, Banister EW (1990). '
                        'Modeling human performance in running. J Appl '
                        'Physiol.',
                      ),
                      BulletLine(
                        'Tanaka H, Monahan KD, Seals DR (2001). Age-predicted '
                        'maximal heart rate revisited. J Am Coll Cardiol.',
                      ),
                      BulletLine(
                        'Cole CR et al. (1999). Heart-rate recovery '
                        'immediately after exercise as a predictor of '
                        'mortality. N Engl J Med.',
                      ),
                      BulletLine(
                        'Plews DJ et al. (2012). Heart rate variability in '
                        'elite triathletes: is variation in variability the '
                        'key to effective training? Eur J Appl Physiol.',
                      ),
                      BulletLine(
                        'Plews DJ et al. (2013). Training adaptation and heart '
                        'rate variability in elite endurance athletes: opening '
                        'the door to effective monitoring. Sports Med.',
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
                    ],
                  ),
                ),
              ],
            ),
          ),
          SettingsRow(
            icon: Icons.gavel_rounded,
            title: 'Licences and credits',
            onTap: () => Navigator.of(context).pushNamed(Routes.licenses),
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('How scores work'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Every score, at a glance',
              style: F.t1.copyWith(color: p.ink),
            ),
          ),
          const SizedBox(height: S.x2),
          Text(
            'Worked out on this phone, from your own data.',
            style: F.body.copyWith(color: p.ink2),
          ),
          const SizedBox(height: S.x3),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              StatePill.tone(PillTone.good, 'Formula version $kAlgoVersion'),
              StatePill.tone(PillTone.off, 'Our own formula'),
              StatePill.tone(PillTone.off, 'Not medical advice'),
            ],
          ),
          const SizedBox(height: S.x5),
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x3),
            EnterFade(index: i, child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

/// The honesty rules as icon cells, two per row (one at large text).
class _RuleGrid extends StatelessWidget {
  const _RuleGrid(this.rules);
  final List<(IconData, String)> rules;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final one = bigText(context) || c.maxWidth < 280;
        final width = one ? c.maxWidth : (c.maxWidth - S.x3) / 2;
        return Wrap(
          spacing: S.x3,
          runSpacing: S.x3,
          children: [
            for (final (icon, label) in rules)
              SizedBox(
                width: width,
                child: Row(
                  children: [
                    IconBadge(icon: icon, size: 28),
                    const SizedBox(width: S.x2),
                    Expanded(
                      child: Text(
                        label,
                        style: F.bodySm.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A small table inside a sheet: an over-label header row, the first column
/// bold, the rest right-aligned in tabular figures.
class _Table extends StatelessWidget {
  const _Table(this.head, this.rows, {this.flex});
  final List<String> head;
  final List<List<String>> rows;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final fl = flex ?? List.filled(head.length, 1);
    return Container(
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
                crossAxisAlignment: CrossAxisAlignment.start,
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
}
