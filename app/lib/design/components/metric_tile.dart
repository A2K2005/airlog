// MetricTile — one number, glanceable, for the Health Monitor grid.
//
// label → value + unit → band state + delta vs baseline → optional trend →
// provenance. A missing value says so in words ("No data"); it never renders
// a dash that could be mistaken for a zero.

import 'package:flutter/material.dart';

import '../../domain/results.dart';
import '../format.dart';
import '../tokens/tokens.dart';
import 'provenance_chip.dart';
import 'surfaces.dart';

enum BandStatus {
  /// Inside the personal band.
  inBand,
  above,
  below,

  /// Baseline not established yet.
  calibrating,

  /// No value today.
  noData,

  /// No band concept for this metric (e.g. steps).
  none,
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    this.value,
    this.unit,
    this.delta,
    this.band = BandStatus.none,
    this.caption,
    this.chart,
    this.provenance,
    this.onTap,
    this.accent = C.health,
    this.semanticsLabel,
  });

  /// Maps the engine's HealthMetricStatus (value, baseline, band edges,
  /// state, provenance). [decimals] defaults per metric kind.
  ///
  /// The delta line: "+4 vs usual 48"; for a signed metric (a change from
  /// the band's own baseline, e.g. skin temperature) every number carries a
  /// sign and the delta its unit: "+0.1 °C vs usual +0.1". A delta that
  /// rounds to zero reads "Same as usual".
  factory MetricTile.health(
    HealthMetricStatus s, {
    Key? key,
    VoidCallback? onTap,
    Widget? chart,
    int? decimals,
  }) {
    final d = decimals ?? defaultDecimals(s.kind);
    final v = s.value;
    final mean = s.baseline?.mean;
    return MetricTile(
      key: key,
      label: s.kind.title,
      value: v == null || !v.isFinite
          ? null
          : valueText(s.kind, v, decimals: d),
      unit: s.kind.displayUnit,
      delta: s.state == BandState.calibrating
          ? null
          : deltaText(s.kind, v, mean, decimals: d),
      band: switch (s.state) {
        BandState.inRange => BandStatus.inBand,
        BandState.above => BandStatus.above,
        BandState.below => BandStatus.below,
        BandState.noData => BandStatus.noData,
        BandState.calibrating => BandStatus.calibrating,
      },
      provenance: s.provenance == null
          ? null
          : ProvenanceChip.of(s.provenance!, plain: true),
      chart: chart,
      onTap: onTap,
    );
  }

  static int defaultDecimals(HealthMetricKind k) => switch (k) {
    HealthMetricKind.restingHr => 0,
    HealthMetricKind.hrv => 0,
    HealthMetricKind.respiratoryRate => 1,
    HealthMetricKind.spo2 => 0,
    HealthMetricKind.skinTemp => 1,
  };

  /// Metrics whose value is itself a change (skin temperature): shown with
  /// a sign, "+0.3" / "−0.2".
  static bool isSigned(HealthMetricKind k) => k == HealthMetricKind.skinTemp;

  /// The tile's number in the metric's own precision: "54", "14.2", "+0.3".
  /// Use it wherever the same metric is written out (alerts, sheets), so
  /// every screen agrees.
  static String valueText(HealthMetricKind k, double v, {int? decimals}) {
    final d = decimals ?? defaultDecimals(k);
    return isSigned(k) ? signed(v, d) : signed(v, d, plus: false);
  }

  /// "+4 vs usual 48", "−0.2 °C vs usual +0.1", "About usual"; null
  /// without a value or a baseline.
  static String? deltaText(
    HealthMetricKind k,
    double? v,
    double? mean, {
    int? decimals,
  }) {
    if (v == null || !v.isFinite || mean == null || !mean.isFinite) {
      return null;
    }
    final d = decimals ?? defaultDecimals(k);
    // From the ROUNDED numbers, so the line's arithmetic matches what the
    // tile prints (54 vs usual 54 is never "+1").
    double r(double x) => double.parse(x.toStringAsFixed(d));
    final dv = signed(r(v) - r(mean), d);
    final usual = valueText(k, mean, decimals: d);
    if (!dv.startsWith('+') && !dv.startsWith('−')) return 'About usual';
    return isSigned(k)
        ? '$dv ${k.unit} vs usual $usual'
        : '$dv vs usual $usual';
  }

  final String label;

  /// Pre-formatted value ("54", "14.2"); null = no data today.
  final String? value;
  final String? unit;

  /// "+4 vs usual 48" (pre-formatted; tabular figures are applied).
  final String? delta;
  final BandStatus band;

  /// Extra line (e.g. "Calibrating · 3 of 5 nights").
  final String? caption;

  /// Optional trend slot (e.g. a Sparkline).
  final Widget? chart;

  /// Provenance slot (usually a ProvenanceChip).
  final Widget? provenance;
  final VoidCallback? onTap;

  /// Accent pigment for the in-band state.
  final Color accent;
  final String? semanticsLabel;

  static String bandLabel(BandStatus b) => switch (b) {
    BandStatus.inBand => 'In your usual range',
    BandStatus.above => 'Above your usual range',
    BandStatus.below => 'Below your usual range',
    BandStatus.calibrating => 'Learning',
    BandStatus.noData => 'No data',
    BandStatus.none => '',
  };

  Color _bandPigment() => switch (band) {
    BandStatus.inBand => accent,
    BandStatus.above || BandStatus.below => C.amber,
    _ => C.neutral,
  };

  String _spoken() {
    if (semanticsLabel != null) return semanticsLabel!;
    return [
      label,
      if (value != null) '$value ${unit ?? ''}'.trim() else 'no data today',
      if (bandLabel(band).isNotEmpty && value != null) bandLabel(band),
      ?delta,
      ?caption,
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final v = value;
    final showBand =
        band != BandStatus.none && !(band == BandStatus.noData && v == null);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x3 + 2),
      child: Semantics(
        container: true,
        label: _spoken(),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: F.cap.copyWith(
                  color: p.ink2,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: S.x2),
              if (v != null)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 3,
                  children: [
                    Text(v, style: F.n32.copyWith(color: p.ink)),
                    if (unit != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          unit!,
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ),
                  ],
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'No data',
                    style: F.body.copyWith(
                      color: p.ink3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (showBand) ...[
                const SizedBox(height: S.x2),
                StatePill(
                  label: bandLabel(band),
                  color: _bandPigment(),
                  tinted: false,
                ),
              ],
              if (delta != null) ...[
                const SizedBox(height: 3),
                Text(
                  delta!,
                  style: F.tab(F.cap).copyWith(color: p.ink2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (caption != null) ...[
                const SizedBox(height: 3),
                Text(
                  caption!,
                  style: F.cap.copyWith(color: p.ink3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (chart != null) ...[const SizedBox(height: S.x3), chart!],
              if (provenance != null) ...[
                const SizedBox(height: S.x3),
                provenance!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
