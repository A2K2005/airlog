// Trends view-model: 90 days loaded once, sliced to the chosen 7/30/90-day
// window. Series are DENSE (one slot per calendar day, null where nothing was
// measured) because the charts and Engine.trend treat the index as elapsed
// days. Bands come only from the engine (HealthMetricStatus lower/upper);
// arrows only from Engine.trend (significant or nothing).

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/design.dart';
import '../../domain/day_key.dart';
import '../../domain/engine/engine.dart';
import '../../domain/engine/source_apps.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import '../../app/platform_services.dart';

const kTrendDays = 90;

class TrendsData {
  const TrendsData({
    required this.latest,
    required this.today,
    required this.keys,
    required this.days,
  });
  final String latest;
  final String today;

  /// kTrendDays calendar days ending at [latest], oldest first.
  final List<String> keys;
  final List<DayBundle?> days;
}

final trendsDataProvider = FutureProvider<TrendsData?>((ref) async {
  ref.watch(revisionProvider.select((r) => r.value));
  final latest = await ref.watch(latestDateProvider.future);
  if (latest == null) return null;
  final repo = ref.watch(healthRepositoryProvider);
  final today = DayKey.of(ref.watch(clockProvider)());
  final from = DayKey.add(latest, -(kTrendDays - 1));
  final list = await repo.range(from, latest);
  // Keep only the nightly scalars + provenance: 90 days of 1-minute heart
  // rate would otherwise stay in memory for as long as the tab lives.
  final by = {for (final b in list) b.date: _slim(b)};
  final keys = DayKey.range(from, latest);
  return TrendsData(
    latest: latest,
    today: today,
    keys: keys,
    days: [for (final k in keys) by[k]],
  );
}, retry: noRetry);

DayBundle _slim(DayBundle b) {
  final r = b.record;
  return DayBundle(
    DayRecord(
      date: r.date,
      hrvRmssd: r.hrvRmssd,
      restingHr: r.restingHr,
      respiratoryRate: r.respiratoryRate,
      spo2Avg: r.spo2Avg,
      spo2Min: r.spo2Min,
      skinTempDelta: r.skinTempDelta,
      vo2max: r.vo2max,
      steps: r.steps,
      weightKg: r.weightKg,
      provenance: r.provenance,
      lastDataAt: r.lastDataAt,
    ),
    b.result,
  );
}

class TrendsRange extends Notifier<int> {
  @override
  int build() => 30;
  void set(int days) => state = days;
}

final trendsRangeProvider = NotifierProvider<TrendsRange, int>(TrendsRange.new);

/// One metric chart.
class MetricTrend {
  const MetricTrend({
    required this.title,
    required this.unit,
    required this.values,
    required this.color,
    required this.trend,
    required this.upIsGood,
    required this.format,
    this.mean,
    this.lower,
    this.upper,
    this.footnote,
    this.provenance,
    this.sourceChanges = const [],
    this.sourceChangeSlots = const [],
    this.metricName,
    this.axis,
  });
  final String title;
  final String unit;
  final List<double?> values;
  final Color color;
  final TrendResult trend;
  final bool? upIsGood;
  final String Function(double) format;
  final double? mean, lower, upper;
  final String? footnote;
  final Provenance? provenance;

  /// Days on which the metric's definition changed (a new baseline starts).
  final List<String> sourceChanges;

  /// The same days as chart x positions, 0…1 of the window (slot / (n − 1)),
  /// drawn as dotted verticals.
  List<double> get sourceChangeMarks {
    final n = values.length;
    if (n < 2) return const [];
    return [for (final i in sourceChangeSlots) i / (n - 1)];
  }

  /// Slot indices (into [values]) of [sourceChanges].
  final List<int> sourceChangeSlots;
  final String? metricName;

  /// A pinned scale (sleep: whole hours); null = derived by the chart.
  final AxisSpec? axis;

  bool get hasValues => values.any((v) => v != null && v.isFinite);
}

class AverageRow {
  const AverageRow(this.label, this.unit, this.cells);
  final String label;
  final String unit;

  /// Formatted mean for the last 7 / 30 / 90 days, null = nothing measured.
  final List<String?> cells;
}

class TrendsView {
  const TrendsView({
    required this.days,
    required this.xLabels,
    required this.recovery,
    required this.strain,
    required this.recoveryTrend,
    required this.strainTrend,
    required this.metrics,
    required this.averages,
    this.load,
    this.vo2,
    this.lastKey = '',
  });

  /// The newest day of the window (yyyy-MM-dd). [redesign, additive]
  final String lastKey;

  final int days;
  final List<String> xLabels;
  final List<double?> recovery, strain;
  final TrendResult recoveryTrend, strainTrend;
  final List<MetricTrend> metrics;
  final List<AverageRow> averages;
  final TrainingLoad? load;
  final MetricTrend? vo2;

  bool get anyArrow =>
      TrendArrow.visible(recoveryTrend) ||
      TrendArrow.visible(strainTrend) ||
      metrics.any((m) => TrendArrow.visible(m.trend)) ||
      (vo2 != null && TrendArrow.visible(vo2!.trend));
}

final trendsViewProvider = Provider<AsyncValue<TrendsView?>>((ref) {
  final data = ref.watch(trendsDataProvider);
  final n = ref.watch(trendsRangeProvider);
  return data.whenData((d) => d == null ? null : buildTrendsView(d, n));
});

/// VO₂ max is the source app's own estimate, never Airlog's (principle 6):
/// "VO₂ max (Samsung Health’s estimate)" when the app is known, else
/// "VO₂ max (your tracker’s estimate)".
String vo2Title(Provenance? p) {
  final app = SourceApps.knownName(p?.origin);
  return 'VO₂ max (${app ?? 'your tracker'}’s estimate)';
}

double? _mean(Iterable<double?> xs) {
  var s = 0.0, n = 0;
  for (final x in xs) {
    if (x == null || !x.isFinite) continue;
    s += x;
    n++;
  }
  return n == 0 ? null : s / n;
}

/// Slots in [window] where [m]'s definition differs from the previous
/// measured day's (a new baseline starts there).
List<int> _sourceChangeSlots(List<DayBundle?> window, Metric m) {
  final out = <int>[];
  String? prev;
  for (var i = 0; i < window.length; i++) {
    final b = window[i];
    // The baseline key (definition + origin + device): a change of app or
    // device starts a new baseline, so it is drawn as a source change.
    final d = b?.record.provenance[m]?.baselineKey;
    if (d == null) continue;
    if (prev != null && d != prev) out.add(i);
    prev = d;
  }
  return out;
}

List<String> _dates(List<DayBundle?> window, List<int> slots) => [
  for (final i in slots) window[i]!.date,
];

TrendsView buildTrendsView(TrendsData d, int days) {
  final n = days.clamp(1, d.keys.length);
  final keys = d.keys.sublist(d.keys.length - n);
  final w = d.days.sublist(d.days.length - n);
  DayBundle? latestBundle;
  for (final b in d.days.reversed) {
    if (b != null) {
      latestBundle = b;
      break;
    }
  }
  final xLabels = <String>[
    dayMonth(keys.first),
    if (n > 2) dayMonth(keys[(n - 1) ~/ 2]),
    if (n > 1) keys.last == d.today ? 'Today' : dayMonth(keys.last),
  ];

  List<double?> series(double? Function(DayBundle b) f) => [
    for (final b in w) b == null ? null : f(b),
  ];

  final recovery = series((b) => b.result.recovery?.score.toDouble());
  // Today's strain is still accumulating: it is not a reading yet, so it
  // counts neither as "latest" nor toward an arrow (QA-12).
  final strain = series((b) {
    if (b.date == d.today) return null;
    final s = b.result.strain;
    return s == null || s.method == StrainMethod.none ? null : s.strain;
  });

  HealthMetricStatus? status(HealthMetricKind k) {
    for (final m
        in latestBundle?.result.health.metrics ??
            const <HealthMetricStatus>[]) {
      if (m.kind == k) return m;
    }
    return null;
  }

  MetricTrend band(
    HealthMetricKind kind,
    Metric metric,
    String title,
    Color color,
    bool? upIsGood,
    String Function(double) format,
    double? Function(DayBundle b) f,
  ) {
    final v = series(f);
    final st = status(kind);
    return MetricTrend(
      title: title,
      unit: kind.unit,
      values: v,
      color: color,
      trend: Engine.trend(v),
      upIsGood: upIsGood,
      format: format,
      mean: st?.baseline?.mean,
      lower: st?.lower,
      upper: st?.upper,
      provenance: latestBundle?.record.provenance[metric],
      sourceChanges: _dates(w, _sourceChangeSlots(w, metric)),
      sourceChangeSlots: _sourceChangeSlots(w, metric),
      metricName: title,
    );
  }

  final sleep = series((b) {
    final s = b.result.sleep;
    return s == null || !s.hasData ? null : s.sleptMinutes;
  });
  final need = _mean(
    series((b) {
      final s = b.result.sleep;
      return s == null || !s.hasData ? null : s.needMinutes;
    }),
  );

  final metrics = <MetricTrend>[
    band(
      HealthMetricKind.hrv,
      Metric.hrv,
      'Heart rate variability',
      C.health,
      true,
      axisInt,
      (b) => b.record.hrvRmssd,
    ),
    band(
      HealthMetricKind.restingHr,
      Metric.restingHr,
      'Resting heart rate',
      C.sky,
      false,
      axisInt,
      (b) => b.record.restingHr,
    ),
    MetricTrend(
      title: 'Sleep duration',
      unit: 'hours',
      values: sleep,
      axis: AxisSpec.of([...sleep, need], ticks: 4, format: axisHm, step: 120),
      color: C.sleep,
      trend: Engine.trend(sleep),
      upIsGood: true,
      format: axisHm,
      mean: need,
      footnote: need == null
          ? null
          : 'Dashed line: your average sleep target here (${axisHm(need)}). '
                'Duration has no personal band.',
      provenance: latestBundle?.record.provenance[Metric.sleep],
      sourceChanges: _dates(w, _sourceChangeSlots(w, Metric.sleep)),
      sourceChangeSlots: _sourceChangeSlots(w, Metric.sleep),
      metricName: 'Sleep duration',
    ),
    band(
      HealthMetricKind.respiratoryRate,
      Metric.respiratoryRate,
      'Respiratory rate',
      C.indigo,
      null,
      axisFixed,
      (b) => b.record.respiratoryRate,
    ),
    band(
      HealthMetricKind.skinTemp,
      Metric.skinTemp,
      'Skin temperature change',
      C.orange,
      null,
      axisFixed,
      (b) => b.record.skinTempDelta,
    ),
  ];

  final strainByDay = <String, double>{
    for (final b in d.days)
      if (b != null &&
          b.result.strain != null &&
          b.result.strain!.method != StrainMethod.none)
        b.date: b.result.strain!.strain,
  };
  TrainingLoad? load;
  try {
    load = Engine.trainingLoad(strainByDay, d.latest);
  } catch (_) {}

  final vo2All = [for (final b in d.days) b?.record.vo2max];
  MetricTrend? vo2;
  if (vo2All.any((v) => v != null)) {
    final v = series((b) => b.record.vo2max);
    // The newest day that says where VO₂ max came from.
    Provenance? prov;
    for (final b in d.days.reversed) {
      prov = b?.record.provenance[Metric.vo2max];
      if (prov != null) break;
    }
    vo2 = MetricTrend(
      title: vo2Title(prov),
      unit: 'ml/kg/min',
      values: v,
      color: C.lavender,
      trend: Engine.trend(v),
      upIsGood: true,
      format: axisInt,
      provenance: prov,
      metricName: 'VO₂ max',
    );
  }

  List<String?> avg(
    double? Function(DayBundle b) f,
    String Function(double) fmt,
  ) => [
    for (final span in const [7, 30, 90])
      (() {
        final m = _mean([
          for (final b in d.days.sublist(
            d.days.length - span.clamp(1, d.days.length),
          ))
            if (b != null) f(b),
        ]);
        return m == null ? null : fmt(m);
      })(),
  ];

  final averages = <AverageRow>[
    AverageRow(
      'Recovery',
      '%',
      avg((b) => b.result.recovery?.score.toDouble(), axisInt),
    ),
    AverageRow(
      'Strain',
      '',
      avg((b) {
        if (b.date == d.today) return null;
        final s = b.result.strain;
        return s == null || s.method == StrainMethod.none ? null : s.strain;
      }, axisFixed),
    ),
    AverageRow('HRV', 'ms', avg((b) => b.record.hrvRmssd, axisInt)),
    AverageRow('Resting HR', 'bpm', avg((b) => b.record.restingHr, axisInt)),
    AverageRow(
      'Sleep',
      '',
      avg((b) {
        final s = b.result.sleep;
        return s == null || !s.hasData ? null : s.sleptMinutes;
      }, axisHm),
    ),
    AverageRow(
      'Respiratory rate',
      '/min',
      avg((b) => b.record.respiratoryRate, axisFixed),
    ),
    // Weight is optional (its own Health Connect permission): a row only
    // when some was granted and recorded.
    if (d.days.any((b) => b?.record.weightKg != null))
      AverageRow('Weight', 'kg', avg((b) => b.record.weightKg, axisFixed)),
  ];

  return TrendsView(
    lastKey: keys.last,
    days: n,
    xLabels: xLabels,
    recovery: recovery,
    strain: strain,
    recoveryTrend: Engine.trend(recovery),
    strainTrend: Engine.trend(strain),
    metrics: metrics,
    averages: averages,
    load: load,
    vo2: vo2,
  );
}
