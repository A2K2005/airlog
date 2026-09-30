// Ported from Luraxx/pulse Core/Metrics/RecoveryEngine.swift (Apache-2.0, see
// third_party/pulse/NOTICE). Changes: Dart port; English labels/details;
// baselines are definition-keyed (baselines.dart) instead of "last 30 values";
// Pulse's bodyTemp rule is applied to skinTempDelta; inputs are sanitised
// (inputs.dart); components also carry value / display-unit baseline / z,
// and penalties are itemised (contract fields marked [ours] in results.dart).

import 'dart:math' as math;

import '../models.dart';
import '../results.dart';
import 'baselines.dart';
import 'inputs.dart';
import 'stats.dart';

abstract final class RecoveryEngine {
  /// Pulse RecoveryEngine.swift:35-40.
  static const Map<String, double> weights = {
    'hrv': 0.40,
    'rhr': 0.25,
    'sleep': 0.25,
    'resp': 0.10,
  };

  // ── Named constants (Pulse RecoveryEngine.swift). The explain sheets and
  // the Methodology page read these, so the copy cannot drift from the maths.

  /// Sub-score of an input that has no baseline yet. Pulse :62, :75.
  static const double neutralScore = 0.5;

  /// HRV: score = logistic(slope · z), z on ln(RMSSD). Pulse :62-73.
  static const double hrvLogisticSlope = 1.1;

  /// HRV: minimum SD of ln(RMSSD) in the z-score. Pulse :66.
  static const double hrvMinSd = 0.03;

  /// Resting HR: score = logistic(−slope · z). Pulse :75-86.
  static const double rhrLogisticSlope = 1.1;

  /// Resting HR: minimum SD (bpm) in the z-score. Pulse :79.
  static const double rhrMinSd = 0.8;

  /// Sleep: performance / 100, clamped to [sleepMinScore, 1]. Pulse :88-91.
  static const double sleepMinScore = 0.1;

  /// Respiratory rate: minimum SD (/min) in the z-score. Pulse :97.
  static const double respMinSd = 0.25;

  /// Respiratory rate: the score ceiling (and the floor of the clamp).
  /// score = clamp(max − max(0, z − allowance) · slope, min, max). Pulse :98.
  static const double respMaxScore = 0.85;
  static const double respMinScore = 0.2;

  /// Respiratory rate: z tolerated before points are lost. Pulse :98.
  static const double respZAllowance = 0.3;

  /// Respiratory rate: points lost per SD beyond the allowance. Pulse :98.
  static const double respSlope = 0.2;

  /// Respiratory rate with no baseline yet. Pulse :94.
  static const double respNoBaselineScore = 0.65;

  /// Penalty: overnight SpO₂ minimum below this (%). Pulse :125-127.
  static const double spo2PenaltyBelow = 90;

  /// Points subtracted for the SpO₂ dip. Pulse :127.
  static const double spo2Penalty = 7;

  /// Penalty: skin temperature z above this. Pulse :128-131.
  static const double skinTempPenaltyZ = 1.8;

  /// Minimum SD (°C) of the skin-temperature z-score. Pulse :129.
  static const double skinTempMinSd = 0.15;

  /// Points subtracted for the raised skin temperature. Pulse :130.
  static const double skinTempPenalty = 5;

  /// Final score clamp. Pulse :133.
  static const double minScore = 1, maxScore = 99;

  /// Zone cut-points, mirroring `RecoveryResult.zoneFor` (results.dart):
  /// green ≥ [greenFrom], yellow ≥ [yellowFrom], red below.
  static const int greenFrom = 67, yellowFrom = 34;

  /// Baseline nights before an input stops calibrating, mirroring
  /// `Baseline.isReliable` (results.dart). Pulse :135-140.
  static const int reliableNights = 5;

  /// [ours] Confidence cut-points on the reporting share of the model
  /// weight (see RecoveryConfidence): high needs HRV and ≥ [highCoverage]
  /// (all four inputs, or all but respiratory rate); below [lowCoverage]
  /// (e.g. resting HR alone, 0.25) the confidence is low.
  static const double highCoverage = 0.9;
  static const double lowCoverage = 0.5;

  /// Confidence for a score built from [coverage] of the model weight.
  static RecoveryConfidence confidenceFor({
    required bool hasHrv,
    required double coverage,
  }) {
    if (coverage < lowCoverage - 1e-9) return RecoveryConfidence.low;
    if (!hasHrv || coverage < highCoverage - 1e-9) {
      return RecoveryConfidence.reduced;
    }
    return RecoveryConfidence.high;
  }

  /// [ours, HRV ladder S1] Sleeping HR's component and label. It takes
  /// resting HR's weight only when resting HR is absent and the source app
  /// never shares it; scored like resting HR against ITS OWN baseline.
  static const String sleepingHrKey = 'sleep_hr';
  static const String sleepingHrLabel = 'Sleeping HR (4 h mean)';

  /// Pulse RecoveryEngine.swift:42-153. [history] must be oldest first and
  /// strictly before [today]. [sleepPerformance] is last night's sleep
  /// performance (0..100) or null when there is no sleep data (then the
  /// sleep component is dropped and the rest re-weighted).
  /// [sleepingHrForRhr]: the app never shares resting HR, so sleeping HR
  /// may take its slot (confidence is then pinned at reduced).
  static RecoveryResult? compute({
    required DayRecord today,
    required List<DayRecord> history,
    double? sleepPerformance,
    int window = 30,
    bool sleepingHrForRhr = false,
  }) {
    final hrv = Inputs.hrv(today);
    final rhr = Inputs.rhr(today);
    final shr = rhr == null && sleepingHrForRhr
        ? Inputs.sleepingHr(today)
        : null;
    // Pulse :48 — no score without HRV or resting HR (or, ours, sleeping HR
    // in resting HR's slot).
    if (hrv == null && rhr == null && shr == null) return null;
    final resp = Inputs.resp(today);
    final temp = Inputs.skinTemp(today);
    final perf = finiteOrNull(sleepPerformance);

    List<double> seg(Metric m) =>
        Baselines.segmentValues(today, history, m, window: window);

    // Pulse :50-58 — HRV baseline on ln(RMSSD).
    final hrvRaw = seg(Metric.hrv);
    final hrvBaseline = Stats.baseline([for (final v in hrvRaw) math.log(v)]);
    final hrvDisplayBaseline = Stats.baseline(hrvRaw);
    final rhrBaseline = Stats.baseline(seg(Metric.restingHr));
    final respBaseline = Stats.baseline(seg(Metric.respiratoryRate));
    final tempBaseline = Stats.baseline(seg(Metric.skinTemp));

    final raw = <RecoveryComponent>[];

    // Pulse :62-73 — HRV: logistic(z · 1.1), z on ln scale with minSD 0.03.
    if (hrv != null) {
      var score = neutralScore;
      var detail = '${_f0(hrv)} ms';
      double? z;
      if (hrvBaseline != null) {
        z = hrvBaseline.z(math.log(hrv), minSd: hrvMinSd);
        score = Stats.logistic(z * hrvLogisticSlope);
        // "Usual" HRV is the plain mean of the baseline nights in ms (the
        // same number every screen shows); ln is only used inside z.
        final usual = hrvDisplayBaseline?.mean;
        detail = usual == null
            ? '${_f0(hrv)} ms'
            : '${_f0(hrv)} ms · baseline ${_f0(usual)} ms';
      }
      raw.add(_c('hrv', 'HRV', score, detail, hrv, hrvDisplayBaseline, z));
    }

    // Pulse :75-86 — resting HR: logistic(−z · 1.1), minSD 0.8.
    if (rhr != null) {
      var score = neutralScore;
      var detail = '${_f0(rhr)} bpm';
      double? z;
      if (rhrBaseline != null) {
        z = rhrBaseline.z(rhr, minSd: rhrMinSd);
        score = Stats.logistic(-z * rhrLogisticSlope);
        detail = '${_f0(rhr)} bpm · baseline ${_f0(rhrBaseline.mean)}';
      }
      raw.add(_c('rhr', 'Resting HR', score, detail, rhr, rhrBaseline, z));
    }

    // [ours] Sleeping HR in resting HR's slot: logistic(−z · 1.1), min SD
    // 0.8 bpm, against its own baseline.
    Baseline? shrBaseline;
    if (shr != null) {
      shrBaseline = Stats.baseline(seg(Metric.sleepingHr));
      var score = neutralScore;
      var detail = '${_f0(shr)} bpm';
      double? z;
      if (shrBaseline != null) {
        z = shrBaseline.z(shr, minSd: rhrMinSd);
        score = Stats.logistic(-z * rhrLogisticSlope);
        detail = '${_f0(shr)} bpm · baseline ${_f0(shrBaseline.mean)}';
      }
      raw.add(
        _c(sleepingHrKey, sleepingHrLabel, score, detail, shr, shrBaseline, z),
      );
    }

    // Pulse :88-91 — sleep performance, clamped to 0.1..1.
    if (perf != null) {
      final score = Stats.clamp(perf / 100, sleepMinScore, 1.0);
      raw.add(
        _c(
          'sleep',
          'Sleep',
          score,
          '${_f0(perf)} % performance',
          perf,
          null,
          null,
        ),
      );
    }

    // Pulse :93-104 — respiratory rate: only an ELEVATED rate costs points.
    if (resp != null) {
      var score = respNoBaselineScore;
      var detail = '${_f1(resp)} /min';
      double? z;
      if (respBaseline != null) {
        z = respBaseline.z(resp, minSd: respMinSd);
        score = Stats.clamp(
          respMaxScore - math.max(0, z - respZAllowance) * respSlope,
          respMinScore,
          respMaxScore,
        );
        detail = '${_f1(resp)} /min · baseline ${_f1(respBaseline.mean)}';
      }
      raw.add(
        _c('resp', 'Respiratory rate', score, detail, resp, respBaseline, z),
      );
    }

    // Pulse :106-121 — re-weight the components that are present.
    double baseWeight(String key) =>
        weights[key] ?? (key == sleepingHrKey ? weights['rhr']! : 0);
    final totalWeight = raw.fold(0.0, (a, c) => a + baseWeight(c.key));
    if (totalWeight <= 0) return null;

    final components = <RecoveryComponent>[];
    var weighted = 0.0;
    for (final c in raw) {
      final w = baseWeight(c.key) / totalWeight;
      weighted += c.score01 * w;
      components.add(
        RecoveryComponent(
          key: c.key,
          label: c.label,
          score01: c.score01,
          weight: w,
          detail: c.detail,
          value: c.value,
          baseline: c.baseline,
          z: c.z,
        ),
      );
    }

    var score = weighted * 100;

    // Pulse :125-131 — warning-sign penalties after weighting.
    final penalties = <RecoveryPenalty>[];
    final spo2Min = Inputs.spo2Min(today);
    if (spo2Min != null && spo2Min < spo2PenaltyBelow) {
      score -= spo2Penalty;
      penalties.add(
        RecoveryPenalty(
          'spo2',
          'Blood oxygen dipped to ${_f0(spo2Min)}% overnight',
          spo2Penalty,
        ),
      );
    }
    if (temp != null &&
        tempBaseline != null &&
        tempBaseline.z(temp, minSd: skinTempMinSd) > skinTempPenaltyZ) {
      score -= skinTempPenalty;
      penalties.add(
        const RecoveryPenalty(
          'skin_temp',
          'Skin temperature well above your usual',
          skinTempPenalty,
        ),
      );
    }

    // [ours] Without HRV the score above is still Pulse's re-weighting of
    // the inputs that did report (never an HRV guess); it is labelled and
    // its confidence lowered.
    final coverage = Stats.clamp(totalWeight, 0, 1);

    // Pulse :133-134 — clamp 1..99, zones ≥67 / 34–66 / <34.
    final finalScore = Stats.clamp(
      finiteOr(score, minScore),
      minScore,
      maxScore,
    ).round();
    final zone = RecoveryResult.zoneFor(finalScore);

    // Pulse :135-140 — calibrating only for metrics that actually report.
    final hrvUncalibrated = hrv != null && !(hrvBaseline?.isReliable ?? false);
    final rhrUncalibrated =
        (rhr != null && !(rhrBaseline?.isReliable ?? false)) ||
        (shr != null && !(shrBaseline?.isReliable ?? false));

    return RecoveryResult(
      score: finalScore,
      zone: zone,
      components: components,
      penalties: penalties,
      calibrating: hrvUncalibrated || rhrUncalibrated,
      hrvValue: hrv,
      hrvBaseline: hrvDisplayBaseline,
      rhrValue: rhr,
      rhrBaseline: rhrBaseline,
      withoutHrv: hrv == null,
      coverage: coverage,
      // Sleeping HR standing in for resting HR: pinned at reduced.
      confidence: shr != null
          ? (coverage < lowCoverage
                ? RecoveryConfidence.low
                : RecoveryConfidence.reduced)
          : confidenceFor(hasHrv: hrv != null, coverage: coverage),
    );
  }

  static RecoveryComponent _c(
    String key,
    String label,
    double score,
    String detail,
    double? value,
    Baseline? baseline,
    double? z,
  ) => RecoveryComponent(
    key: key,
    label: label,
    score01: finiteOr(score, neutralScore),
    weight: 0,
    detail: detail,
    value: value,
    baseline: baseline,
    z: finiteOrNull(z),
  );

  static String _f0(double v) => v.toStringAsFixed(0);
  static String _f1(double v) => v.toStringAsFixed(1);
}
