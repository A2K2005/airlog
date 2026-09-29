// Baselines keyed by definition, origin app and device. [ours]
//
// Pulse builds each baseline from the last 30 non-null values of a metric
// (RecoveryEngine.swift:50-53, HealthMonitor.swift:275). We keep that window
// but add one rule (ARCHITECTURE.md §3): a history day only counts if the
// metric's provenance belongs to the CURRENT segment ([Segment]): same
// source and definition, same origin app (Provenance.origin), and the same
// device when both days know it (Provenance.baselineKey,
// "definition@origin#device"). Switching a metric's source (Health Connect
// all-night RMSSD → Google Health deep-sleep RMSSD), its app (Fitbit →
// Samsung Health) or its device (a Fitbit Air and a Pixel Watch under the
// same app) therefore starts a fresh baseline instead of pooling two
// different measurements (decisions "Any app" and "Product-critic review",
// 2026-09-29).
//
// Rules:
//   * The segment is today's provenance when today reports the metric, else
//     that of the most recent history day that did.
//   * Device metadata is not always present (Health Connect background
//     reads carry none), so an unknown device never splits a segment: a day
//     without one takes the most recent known device of the same app
//     (carried forward); before any device is known it matches any device
//     of that app.
//   * Missing provenance is its own segment (null == null), so data without
//     provenance (Pulse fixtures, old rows) behaves exactly as Pulse.
//   * Window = the N most recent matching values, by count (not calendar).

import '../models.dart';
import 'inputs.dart';

typedef MetricValue = double? Function(DayRecord r);

/// The sanitised reader used for each baseline-bearing metric.
MetricValue valueReader(Metric m) => switch (m) {
  Metric.hrv => Inputs.hrv,
  Metric.restingHr => Inputs.rhr,
  Metric.respiratoryRate => Inputs.resp,
  Metric.spo2 => Inputs.spo2Avg,
  Metric.skinTemp => Inputs.skinTemp,
  Metric.vo2max => Inputs.vo2max,
  Metric.sleepingHr => Inputs.sleepingHr,
  _ => (DayRecord _) => null,
};

/// One baseline segment: which measurement from which app (and device).
class Segment {
  const Segment(this.prov);

  /// Null = data without provenance.
  final Provenance? prov;

  /// "definition@origin#device" (see Provenance.baselineKey).
  String? get key => prov?.baselineKey;

  /// Whether a day with provenance [p] belongs to this segment.
  bool matches(Provenance? p) {
    final s = prov;
    if (s == null || p == null) return s == null && p == null;
    if (s.source != p.source ||
        s.definition != p.definition ||
        s.origin != p.origin) {
      return false;
    }
    final a = s.device, b = p.device;
    return a == null || b == null || a == b;
  }
}

abstract final class Baselines {
  /// Provenance of [metric] on each day of [days] (oldest first), with an
  /// unknown device carried forward from the most recent earlier day of the
  /// same app that reported one (a night without device metadata belongs to
  /// the device that app was using then). Cached per list instance: the
  /// engine passes each day's history list to many calls.
  static List<Provenance?> effective(List<DayRecord> days, Metric metric) {
    final cache = _cache[days] ??= {};
    return cache[metric] ??= _effective(days, metric);
  }

  static final Expando<Map<Metric, List<Provenance?>>> _cache = Expando();

  static String _app(Provenance p) =>
      '${p.source.code}|${p.definition}|${p.origin}';

  static List<Provenance?> _effective(List<DayRecord> days, Metric metric) {
    final out = List<Provenance?>.filled(days.length, null);
    final lastDevice = <String, String>{};
    for (var i = 0; i < days.length; i++) {
      final p = days[i].provenance[metric];
      if (p == null) continue;
      if (p.device != null) {
        lastDevice[_app(p)] = p.device!;
        out[i] = p;
        continue;
      }
      out[i] = _withDevice(p, lastDevice[_app(p)]);
    }
    return out;
  }

  static Provenance _withDevice(Provenance p, String? device) =>
      device == null || p.device != null
      ? p
      : Provenance(p.source, p.definition, origin: p.origin, device: device);

  /// [today]'s provenance of [metric] with its device carried forward from
  /// [historyAsc] when unknown.
  static Provenance? effectiveToday(
    DayRecord today,
    List<DayRecord> historyAsc,
    Metric metric,
  ) {
    final p = today.provenance[metric];
    if (p == null || p.device != null) return p;
    final eff = effective(historyAsc, metric);
    final app = _app(p);
    for (var i = eff.length - 1; i >= 0; i--) {
      final q = eff[i];
      if (q == null || _app(q) != app) continue;
      return _withDevice(p, q.device);
    }
    return p;
  }

  /// The current segment of [metric], and whether any segment exists at all
  /// (today or history reports the metric).
  static ({bool exists, Segment seg}) segment(
    DayRecord today,
    List<DayRecord> historyAsc,
    Metric metric, [
    MetricValue? value,
  ]) {
    final read = value ?? valueReader(metric);
    if (read(today) != null) {
      return (
        exists: true,
        seg: Segment(effectiveToday(today, historyAsc, metric)),
      );
    }
    for (var i = historyAsc.length - 1; i >= 0; i--) {
      if (read(historyAsc[i]) == null) continue;
      return (exists: true, seg: Segment(effective(historyAsc, metric)[i]));
    }
    return (exists: false, seg: const Segment(null));
  }

  /// The [window] most recent values (returned oldest first) from history
  /// days that report [metric] inside [seg].
  static List<double> values(
    List<DayRecord> historyAsc,
    Metric metric,
    Segment seg, {
    int window = 30,
    MetricValue? value,
  }) {
    final read = value ?? valueReader(metric);
    final eff = effective(historyAsc, metric);
    final out = <double>[];
    for (var i = historyAsc.length - 1; i >= 0 && out.length < window; i--) {
      final v = read(historyAsc[i]);
      if (v == null || !seg.matches(eff[i])) continue;
      out.add(v);
    }
    return out.reversed.toList();
  }

  /// Segment values for [metric] as seen from [today].
  static List<double> segmentValues(
    DayRecord today,
    List<DayRecord> historyAsc,
    Metric metric, {
    int window = 30,
  }) {
    final s = segment(today, historyAsc, metric);
    if (!s.exists) return const [];
    return values(historyAsc, metric, s.seg, window: window);
  }

  /// Prior nights with HRV, resting HR (or sleeping HR standing in for it)
  /// in the current segment of each.
  /// Feeds `Calibration(haveNights:)`.
  static int calibrationNights(DayRecord today, List<DayRecord> historyAsc) {
    final hrv = segment(today, historyAsc, Metric.hrv);
    final rhr = segment(today, historyAsc, Metric.restingHr);
    final hrvEff = effective(historyAsc, Metric.hrv);
    final rhrEff = effective(historyAsc, Metric.restingHr);
    // Sleeping HR counts only where it stands in for resting HR.
    final shr = Inputs.rhr(today) == null && Inputs.sleepingHr(today) != null
        ? segment(today, historyAsc, Metric.sleepingHr)
        : (exists: false, seg: const Segment(null));
    final shrEff = effective(historyAsc, Metric.sleepingHr);
    var n = 0;
    for (var i = 0; i < historyAsc.length; i++) {
      final r = historyAsc[i];
      final hasHrv =
          hrv.exists && Inputs.hrv(r) != null && hrv.seg.matches(hrvEff[i]);
      final hasRhr =
          rhr.exists && Inputs.rhr(r) != null && rhr.seg.matches(rhrEff[i]);
      final hasShr =
          shr.exists &&
          Inputs.sleepingHr(r) != null &&
          shr.seg.matches(shrEff[i]);
      if (hasHrv || hasRhr || hasShr) n++;
    }
    return n;
  }

  /// If today's value of [metric] starts a new segment (the most recent
  /// history day with a value used a different definition, app or device),
  /// returns that day's provenance (null provenance → a synthetic "unknown"
  /// one).
  static Provenance? switchedFrom(
    DayRecord today,
    List<DayRecord> historyAsc,
    Metric metric,
  ) {
    final read = valueReader(metric);
    if (read(today) == null) return null;
    final seg = segment(today, historyAsc, metric).seg;
    final eff = effective(historyAsc, metric);
    for (var i = historyAsc.length - 1; i >= 0; i--) {
      if (read(historyAsc[i]) == null) continue;
      if (seg.matches(eff[i])) return null;
      return eff[i] ?? const Provenance(SourceKind.demo, 'unknown');
    }
    return null;
  }

  /// The current segment of [metric] started fewer than [within] nights
  /// ago, after a different segment: the provenance before, the one now,
  /// and the nights already in the new segment (before today).
  static ({Provenance? from, Provenance? to, int nights})? recentSwitch(
    DayRecord today,
    List<DayRecord> historyAsc,
    Metric metric, {
    required int within,
  }) {
    final read = valueReader(metric);
    final s = segment(today, historyAsc, metric);
    if (!s.exists) return null;
    final eff = effective(historyAsc, metric);
    var nights = 0;
    for (var i = historyAsc.length - 1; i >= 0; i--) {
      if (read(historyAsc[i]) == null) continue;
      if (s.seg.matches(eff[i])) {
        nights++;
        if (nights >= within) return null;
        continue;
      }
      return (from: eff[i], to: s.seg.prov, nights: nights);
    }
    return null;
  }
}
