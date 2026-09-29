// Ported from Luraxx/pulse Core/Metrics/HealthMonitor.swift (Apache-2.0, see
// third_party/pulse/NOTICE). Changes: Dart port; English messages (Pulse
// Language.swift:112-131, streak message keeps the day count as Pulse's
// German original does); baselines are keyed by definition@origin (baselines.dart);
// body temperature → skin-temperature delta; each status carries today's
// provenance; the alert rules are factored out ([HealthMonitor.alertFrom])
// so the Engine can feed them the same statuses the cards display.

import '../models.dart';
import '../results.dart';
import 'baselines.dart';
import 'inputs.dart';
import 'stats.dart';

/// Proactive warning. Pulse HealthMonitor.swift:142-147.
class HealthAlert {
  const HealthAlert(this.kinds, this.message, {this.isWarning = true});
  final List<HealthMetricKind> kinds;
  final String message;
  final bool isWarning;
}

abstract final class HealthMonitor {
  /// ±1.65 SD ≈ a 90 % two-tailed band. Pulse HealthMonitor.swift:83.
  static const double bandSd = 1.65;

  /// SpO₂: only a LOW value matters, and the floor never drops below this
  /// (%). Pulse HealthMonitor.swift:87-91.
  static const double spo2HardFloor = 90;

  /// [ours] Fixed, non-diagnostic copy for a vital outside its band (the
  /// TodayPlan check-in action and any screen that mirrors it). It names a
  /// pattern in the user's own numbers; it never names a condition.
  static const String checkInTitle = 'Notice how you feel today';
  static const String checkInNote =
      'a pattern in your numbers, not a diagnosis';

  /// Minimum half-widths so a very stable baseline is not over-sensitive.
  /// Pulse HealthMonitor.swift:47-56.
  static double minimumHalfWidth(HealthMetricKind k) => switch (k) {
    HealthMetricKind.restingHr => 3,
    HealthMetricKind.hrv => 10,
    HealthMetricKind.respiratoryRate => 0.8,
    HealthMetricKind.spo2 => 1.5,
    HealthMetricKind.skinTemp => 0.4,
  };

  static Metric metricOf(HealthMetricKind k) => switch (k) {
    HealthMetricKind.restingHr => Metric.restingHr,
    HealthMetricKind.hrv => Metric.hrv,
    HealthMetricKind.respiratoryRate => Metric.respiratoryRate,
    HealthMetricKind.spo2 => Metric.spo2,
    HealthMetricKind.skinTemp => Metric.skinTemp,
  };

  /// Pulse HealthMonitor.swift:113-121.
  static double? valueOf(HealthMetricKind k, DayRecord r) => switch (k) {
    HealthMetricKind.restingHr => Inputs.rhr(r),
    HealthMetricKind.hrv => Inputs.hrv(r),
    HealthMetricKind.respiratoryRate => Inputs.resp(r),
    HealthMetricKind.spo2 => Inputs.spo2Avg(r),
    HealthMetricKind.skinTemp => Inputs.skinTemp(r),
  };

  /// Every nightly metric against its personal band (mean ± max(1.65·SD,
  /// floor)). Pulse HealthMonitor.swift:70-111. [history] oldest first.
  static List<HealthMetricStatus> evaluate(
    DayRecord today,
    List<DayRecord> history, {
    int window = 30,
  }) {
    return [
      for (final kind in HealthMetricKind.values)
        _evaluate(kind, today, history, window),
    ];
  }

  static HealthMetricStatus _evaluate(
    HealthMetricKind kind,
    DayRecord today,
    List<DayRecord> history,
    int window,
  ) {
    final metric = metricOf(kind);
    final value = valueOf(kind, today);
    final provenance = today.provenance[metric];
    final seg = Baselines.segment(today, history, metric);
    final values = seg.exists
        ? Baselines.values(
            history,
            metric,
            seg.seg,
            window: window,
            value: (r) => valueOf(kind, r),
          )
        : const <double>[];
    final baseline = Stats.baseline(values);

    if (value == null) {
      return HealthMetricStatus(
        kind: kind,
        state: BandState.noData,
        baseline: baseline,
        provenance: provenance,
      );
    }
    if (baseline == null || !baseline.isReliable) {
      return HealthMetricStatus(
        kind: kind,
        state: BandState.calibrating,
        value: value,
        baseline: baseline,
        provenance: provenance,
      );
    }

    final halfWidth = _max(bandSd * baseline.sd, minimumHalfWidth(kind));
    double? lower = baseline.mean - halfWidth;
    double? upper = baseline.mean + halfWidth;
    // SpO₂: only LOW matters, hard floor 90 %. Pulse :87-91.
    if (kind == HealthMetricKind.spo2) {
      lower = _max(spo2HardFloor, baseline.mean - halfWidth);
      upper = null;
    }

    final BandState state;
    if (value < lower) {
      state = BandState.below;
    } else if (upper != null && value > upper) {
      state = BandState.above;
    } else {
      state = BandState.inRange;
    }
    return HealthMetricStatus(
      kind: kind,
      state: state,
      value: value,
      baseline: baseline,
      lower: lower,
      upper: upper,
      provenance: provenance,
    );
  }

  static double _max(double a, double b) => a > b ? a : b;

  /// Deviation in the "bad" direction (infection / overtraining sign)?
  /// HRV & SpO₂ low, the rest high. Pulse HealthMonitor.swift:127-132.
  static bool isConcerning(HealthMetricStatus s) => switch (s.kind) {
    HealthMetricKind.hrv || HealthMetricKind.spo2 => s.state == BandState.below,
    _ => s.state == BandState.above,
  };

  /// Pulse HealthMonitor.swift:134-139 (English, Language.swift:121-125).
  static String directionWord(HealthMetricKind k) => switch (k) {
    HealthMetricKind.hrv || HealthMetricKind.spo2 => 'low',
    _ => 'elevated',
  };

  /// Pulse's alert over a chronological record list (its app passes the
  /// last 10 calendar days). Needs ≥ 6 records; each of the last
  /// [lookback] + 1 records is evaluated against the records before it
  /// INSIDE the list. Pulse HealthMonitor.swift:153-195.
  static HealthAlert? alert(List<DayRecord> records, {int lookback = 3}) {
    if (records.length < 6) return null;
    final n = records.length;
    final start = n - (lookback + 1) > 1 ? n - (lookback + 1) : 1;
    final daily = <Set<HealthMetricKind>>[
      for (var i = start; i < n; i++)
        concerningKinds(evaluate(records[i], records.sublist(0, i))),
    ];
    return alertFrom(daily);
  }

  static Set<HealthMetricKind> concerningKinds(
    List<HealthMetricStatus> statuses,
  ) => {
    for (final s in statuses)
      if (isConcerning(s)) s.kind,
  };

  /// The two alert rules over per-day concerning sets (oldest first, today
  /// last). Pulse HealthMonitor.swift:165-194.
  static HealthAlert? alertFrom(List<Set<HealthMetricKind>> daily) {
    if (daily.isEmpty || daily.last.isEmpty) return null;
    final today = daily.last;

    // Rule 1: several metrics outside the baseline today.
    if (today.length >= 2) {
      final kinds = today.toList()..sort((a, b) => a.label.compareTo(b.label));
      final names = kinds.map((k) => k.label).join(', ');
      return HealthAlert(
        kinds,
        '${kinds.length} values outside your baseline ($names). '
        'Notice how you feel; this pattern is not a diagnosis.',
      );
    }

    // Rule 2: one metric concerning for ≥ 2 consecutive days.
    HealthMetricKind? worst;
    var worstDays = 0;
    for (final kind in today) {
      var streak = 0;
      for (final set in daily.reversed) {
        if (set.contains(kind)) {
          streak++;
        } else {
          break;
        }
      }
      if (streak >= 2 && streak > worstDays) {
        worst = kind;
        worstDays = streak;
      }
    }
    if (worst != null) {
      return HealthAlert(
        [worst],
        '${worst.label} has been ${directionWord(worst)} for $worstDays days '
        '– prioritize recovery.',
      );
    }
    return null;
  }
}
