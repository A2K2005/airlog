// get_methodology: short, general explanations of how Airlog computes its
// scores. The constants are read from the engine itself, so the coach can't
// drift from the maths. General knowledge only: no user data, so this tool
// is allowed in CoachMode.generalOnly. Every number in these texts is a
// methodology constant the verifier accepts. Pure Dart.

import '../engine/engine.dart';
import '../engine/health_monitor.dart';
import '../engine/journal.dart';
import '../engine/load_and_trends.dart';
import '../engine/readiness.dart';
import '../engine/recovery.dart';
import '../engine/sleep.dart';
import '../engine/strain.dart';
import 'format.dart';
import 'refs.dart';

enum MethodologyTopic {
  recovery,
  hrv,
  restingHr,
  sleep,
  sleepNeed,
  sleepDebt,
  strain,
  strainTarget,
  heartRateZones,
  trainingLoad,
  healthMonitor,
  journal,
  trends,
  calibration,
  spo2,
  dataSources;

  /// Wire name (snake_case) used in the tool schema.
  String get wire => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m.group(0)!.toLowerCase()}',
  );

  static MethodologyTopic? fromWire(String s) {
    for (final t in values) {
      if (t.wire == s) return t;
    }
    return null;
  }
}

abstract final class Methodology {
  static String _pct(double f) => '${(f * 100).round()}%';

  /// {topic, text, constants: {...fact maps}}.
  static Map<String, dynamic> build(MethodologyTopic t, RefSink sink) {
    const route = CoachRoutes.methodology;
    final w = RecoveryEngine.weights;
    const sleepCfg = SleepConfig();
    Map<String, dynamic> k(String label, double v, String unit, [int d = 0]) =>
        sink.fact(label, v, unit, route: route, decimals: d);

    switch (t) {
      case MethodologyTopic.recovery:
        return {
          'topic': t.wire,
          'text':
              'Recovery (1–99%) compares last night with your own baseline. '
              'Weights: HRV ${_pct(w['hrv']!)}, resting heart rate '
              '${_pct(w['rhr']!)}, sleep performance ${_pct(w['sleep']!)}, '
              'respiratory rate ${_pct(w['resp']!)}; missing inputs are '
              're-weighted, never counted as zero. Zones: green from 67%, '
              'yellow 34–66%, red below 34%. Penalties: overnight SpO₂ '
              'below ${RecoveryEngine.spo2PenaltyBelow.round()}% costs '
              '${RecoveryEngine.spo2Penalty.round()} points, skin '
              'temperature well above baseline costs '
              '${RecoveryEngine.skinTempPenalty.round()} points.',
          'constants': {
            'hrvWeight': k('Recovery weight · HRV', w['hrv']! * 100, '%'),
            'rhrWeight': k(
              'Recovery weight · resting HR',
              w['rhr']! * 100,
              '%',
            ),
            'sleepWeight': k('Recovery weight · sleep', w['sleep']! * 100, '%'),
            'respWeight': k(
              'Recovery weight · respiratory rate',
              w['resp']! * 100,
              '%',
            ),
            'greenFrom': k('Recovery green zone from', 67, '%'),
          },
        };
      case MethodologyTopic.hrv:
        return {
          'topic': t.wire,
          'text':
              'HRV (heart-rate variability, RMSSD in ms) is the variation '
              'between heartbeats during sleep. Higher than your own '
              'baseline usually means a well-recovered nervous system; a '
              'drop can follow hard training, alcohol, poor sleep or '
              'illness. Only compare it with your own baseline: normal '
              'values differ a lot between people. It is '
              '${_pct(w['hrv']!)} of Recovery.',
          'constants': {
            'weight': k('Recovery weight · HRV', w['hrv']! * 100, '%'),
          },
        };
      case MethodologyTopic.restingHr:
        return {
          'topic': t.wire,
          'text':
              'Resting heart rate is your lowest sustained heart rate, '
              'measured overnight. A rise above your baseline can follow '
              'hard training, alcohol, heat, stress or illness. It is '
              '${_pct(w['rhr']!)} of Recovery.',
          'constants': {
            'weight': k('Recovery weight · resting HR', w['rhr']! * 100, '%'),
          },
        };
      case MethodologyTopic.sleep:
        return {
          'topic': t.wire,
          'text':
              'Sleep performance is the time asleep as a share of your sleep '
              'need (capped at 100%). Efficiency is time asleep as a share of '
              'time in bed. Consistency (0–100%) compares your bed and wake '
              'times over the last ${SleepEngine.consistencyWindow} nights: '
              'an average shift of '
              '${SleepEngine.consistencyZeroMinutes.round()} min or more '
              'scores 0%. A night belongs to the day you wake up.',
          'constants': <String, dynamic>{},
        };
      case MethodologyTopic.sleepNeed:
        return {
          'topic': t.wire,
          'text':
              'Sleep need starts from a baseline of '
              '${CoachFormat.duration(sleepCfg.baselineNeedMinutes)}, plus '
              'a share of your sleep debt and up to '
              '${sleepCfg.strainNeedBoostMaxMinutes.round()} min more after '
              'a high-strain day.',
          'constants': {
            'baseline': k(
              'Sleep need baseline',
              sleepCfg.baselineNeedMinutes,
              'min',
            ),
            'strainBoost': k(
              'Sleep need · max strain boost',
              sleepCfg.strainNeedBoostMaxMinutes,
              'min',
            ),
          },
        };
      case MethodologyTopic.sleepDebt:
        return {
          'topic': t.wire,
          'text':
              'Sleep debt is the running shortfall between sleep need and '
              'sleep, carried from night to night. Each night adds at most '
              '${CoachFormat.duration(sleepCfg.maxDebtGainPerNightMinutes)}, '
              'the total is capped at '
              '${CoachFormat.duration(sleepCfg.maxDebtMinutes)}, and '
              '${_pct(sleepCfg.debtRepayFraction)} of the debt is added to '
              'the next night\'s need.',
          'constants': {
            'cap': k('Sleep debt cap', sleepCfg.maxDebtMinutes, 'min'),
            'repay': k(
              'Sleep debt share added to need',
              sleepCfg.debtRepayFraction * 100,
              '%',
            ),
          },
        };
      case MethodologyTopic.strain:
        return {
          'topic': t.wire,
          'text':
              'Strain (0–21) is cardiovascular load from your heart rate: '
              'minutes in heart-rate-reserve zones, weighted by intensity, on '
              'a curve that gets harder to climb near the top. With sparse '
              'heart rate it is estimated from workouts and steps, and the '
              'app says so.',
          'constants': {
            'max': k('Strain scale maximum', StrainEngine.scaleMax, 'strain'),
          },
        };
      case MethodologyTopic.strainTarget:
        return {
          'topic': t.wire,
          'text':
              'The daily strain target scales with this morning\'s Recovery: '
              '${StrainEngine.targetFactor} × Recovery, kept between '
              '${CoachFormat.number(StrainEngine.targetMin, decimals: 1)} and '
              '${CoachFormat.number(StrainEngine.targetMax, decimals: 1)}. '
              'Without a Recovery score there is no target.',
          'constants': {
            'min': k(
              'Strain target minimum',
              StrainEngine.targetMin,
              'strain',
              1,
            ),
            'max': k(
              'Strain target maximum',
              StrainEngine.targetMax,
              'strain',
              1,
            ),
          },
        };
      case MethodologyTopic.heartRateZones:
        return {
          'topic': t.wire,
          'text':
              'Heart-rate zones use heart-rate reserve (Karvonen): zone 1 is '
              '50–60%, zone 2 60–70%, zone 3 70–80%, zone 4 80–90% and '
              'zone 5 90–100% of the range between resting and max heart '
              'rate. Max heart rate is ${StrainEngine.tanakaIntercept.round()} '
              '− ${StrainEngine.tanakaSlope} × age (Tanaka) unless you set '
              'your own.',
          'constants': <String, dynamic>{},
        };
      case MethodologyTopic.trainingLoad:
        return {
          'topic': t.wire,
          'text':
              'Training load compares your mean daily strain over the last '
              '${TrainingLoadEngine.acuteDays} days (acute) with the last '
              '${TrainingLoadEngine.chronicDays} days (chronic). The ratio '
              'is below ${TrainingLoadEngine.optimalFrom} for detraining, '
              'up to ${TrainingLoadEngine.optimalTo} optimal, up to '
              '${TrainingLoadEngine.elevatedTo} elevated, above that high. '
              'It needs ${TrainingLoadEngine.minDays} days of strain; days '
              'without data are skipped, not counted as rest.',
          'constants': {
            'optimalTo': k(
              'Training load optimal up to',
              TrainingLoadEngine.optimalTo,
              'ratio',
              2,
            ),
          },
        };
      case MethodologyTopic.healthMonitor:
        return {
          'topic': t.wire,
          'text':
              'The Health Monitor puts each overnight metric (resting heart '
              'rate, HRV, respiratory rate, SpO₂, skin temperature) in a band '
              'of ±${HealthMonitor.bandSd} SD around your own baseline. It '
              'flags when 2 or more metrics are out of range, or 1 metric for '
              '2 days in a row. It is not a diagnosis: heat, alcohol, hard '
              'training, travel or illness can all shift these.',
          'constants': <String, dynamic>{},
        };
      case MethodologyTopic.journal:
        return {
          'topic': t.wire,
          'text':
              'Journal insights compare next-day Recovery on days with and '
              'without a factor, once there are at least '
              '${JournalEngine.minDaysPerGroup} days of each. "Solid" means '
              'the difference is larger than twice its standard error; '
              '"emerging" means it could still be noise. These are '
              'associations, not proof of cause.',
          'constants': <String, dynamic>{},
        };
      case MethodologyTopic.trends:
        return {
          'topic': t.wire,
          'text':
              'A trend is reported only when it is statistically significant '
              '(Mann-Kendall test, p < 0.05, at least ${TrendEngine.minN} '
              'days of data); the slope is the median day-to-day change. '
              'Otherwise the metric is described as having no clear trend.',
          'constants': <String, dynamic>{},
        };
      case MethodologyTopic.calibration:
        return {
          'topic': t.wire,
          'text':
              'Scores compare you with your own baseline, which needs time: '
              'with fewer than 5 nights Recovery is provisional, and the '
              'baseline is established after 14 nights. Readiness (HRV '
              'trend) needs ${Readiness.minBaselineNights} nights.',
          'constants': <String, dynamic>{},
        };
      case MethodologyTopic.spo2:
        return {
          'topic': t.wire,
          'text':
              'SpO₂ is blood-oxygen saturation measured overnight. Only a low '
              'value matters: the Health Monitor never sets its floor below '
              '${HealthMonitor.spo2HardFloor.round()}%, and a night dipping '
              'below ${RecoveryEngine.spo2PenaltyBelow.round()}% takes '
              '${RecoveryEngine.spo2Penalty.round()} points off Recovery. '
              'SpO₂ comes from Health Connect when Fitbit writes it there, '
              'otherwise from the Google Health API (Enhanced mode).',
          'constants': {
            'floor': k(
              'SpO₂ penalty threshold',
              RecoveryEngine.spo2PenaltyBelow,
              '%',
            ),
          },
        };
      case MethodologyTopic.dataSources:
        return {
          'topic': t.wire,
          'text':
              'Airlog reads your Fitbit Air data from Health Connect on the '
              'phone (optionally the Google Health API in Enhanced mode) and '
              'computes every score on the phone. For each metric and day it '
              'uses one source, never an average. Hours when the band was '
              'off or charging have no data; they are never treated as sleep '
              'or rest.',
          'constants': <String, dynamic>{},
        };
    }
  }
}
