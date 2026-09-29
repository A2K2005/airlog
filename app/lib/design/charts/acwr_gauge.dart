// AcwrGauge — acute:chronic training-load ratio on a fixed 0.5–2.0 scale.
//
// The band edges are the domain's documented LoadState cut-points
// (results.dart, TrainingLoad.ratio: <0.8 detraining, 0.8–1.3 optimal,
// 1.3–1.5 elevated, >1.5 high). The STATE shown comes from the engine
// (TrainingLoad.state); the gauge only places the marker.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/results.dart';
import '../tokens/tokens.dart';
import 'axis.dart';
import 'frame.dart';

class AcwrGauge extends StatelessWidget {
  const AcwrGauge({
    super.key,
    required this.ratio,
    this.state,
    this.acute,
    this.chronic,
    this.title = 'Training load',
    this.semanticsLabel,
    this.emptyMessage = 'Needs 4 weeks of strain history',
  });

  factory AcwrGauge.fromLoad(
    TrainingLoad? load, {
    Key? key,
    String? title = 'Training load',
    String? semanticsLabel,
  }) => AcwrGauge(
    key: key,
    ratio: load?.ratio,
    state: load?.state,
    acute: load?.acute7,
    chronic: load?.chronic28,
    title: title,
    semanticsLabel: semanticsLabel,
  );

  final double? ratio;
  final LoadState? state;

  /// Mean daily strain, last 7 / last 28 days.
  final double? acute, chronic;

  /// Printed above the gauge whenever it is non-null, in both the empty and
  /// the measured state (the card never needs its own header).
  final String? title;
  final String? semanticsLabel;
  final String emptyMessage;

  static const lo = 0.5, hi = 2.0;

  /// Mirrors the documented LoadState cut-points.
  static const bands = <(double, double, LoadState)>[
    (0.5, 0.8, LoadState.detraining),
    (0.8, 1.3, LoadState.optimal),
    (1.3, 1.5, LoadState.elevated),
    (1.5, 2.0, LoadState.high),
  ];

  static String stateLabel(LoadState s) => switch (s) {
    LoadState.detraining => 'Detraining',
    LoadState.optimal => 'Optimal',
    LoadState.elevated => 'Elevated',
    LoadState.high => 'High',
  };

  static double frac(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

  bool get _has => ratio != null && ratio!.isFinite;

  String get _name => title ?? 'Training load';

  Widget _title(P p) => Text(
    title!,
    style: F.bodySm.copyWith(color: p.ink, fontWeight: FontWeight.w700),
  );

  String _spoken() {
    if (semanticsLabel != null) return semanticsLabel!;
    if (!_has) return '$_name. $emptyMessage';
    return [
      '$_name: acute to chronic ratio ${ratio!.toStringAsFixed(2)}',
      if (state != null) stateLabel(state!),
      if (acute != null && chronic != null)
        '7-day mean strain ${axisFixed(acute!)}, 28-day mean ${axisFixed(chronic!)}',
      'Optimal range 0.8 to 1.3',
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    if (!_has) {
      return Semantics(
        container: true,
        label: _spoken(),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[_title(p), const SizedBox(height: S.x4)],
              Center(child: NoData(message: emptyMessage)),
            ],
          ),
        ),
      );
    }
    final r = ratio!;
    final activeInk = state == null ? p.ink : p.on(DomainColors.load(state!));
    return Semantics(
      container: true,
      label: _spoken(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[_title(p), const SizedBox(height: S.x3)],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(r.toStringAsFixed(2), style: F.n32.copyWith(color: p.ink)),
                const SizedBox(width: S.x2),
                if (state != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      stateLabel(state!),
                      style: F.bodySm.copyWith(
                        color: activeInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                // Expanded (not Spacer + Flexible): the readout gets the whole
                // remaining width, so right-aligned text sits on the edge.
                if (acute != null && chronic != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '7d ${axisFixed(acute!)} · 28d ${axisFixed(chronic!)}',
                        style: F.tab(F.cap).copyWith(color: p.ink2),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: S.x3),
            SizedBox(
              height: 22,
              child: CustomPaint(
                size: Size.infinite,
                painter: AcwrPainter(ratio: r, active: state, p: p),
              ),
            ),
            const SizedBox(height: S.x1 + 2),
            LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth.isFinite ? box.maxWidth : 0.0;
                final tick = F
                    .tab(F.over)
                    .copyWith(color: p.ink3, letterSpacing: .2);
                const edges = [0.5, 0.8, 1.3, 1.5, 2.0];
                return SizedBox(
                  height: 16,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final e in edges)
                        Positioned(
                          left: e == lo
                              ? 0
                              : e == hi
                              ? null
                              : max(0, frac(e) * w - 12),
                          right: e == hi ? 0 : null,
                          width: e == lo || e == hi ? null : 24,
                          child: Text(
                            e.toStringAsFixed(1),
                            style: tick,
                            textAlign: e == lo
                                ? TextAlign.left
                                : e == hi
                                ? TextAlign.right
                                : TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class AcwrPainter extends CustomPainter {
  AcwrPainter({required this.ratio, required this.active, required this.p});
  final double ratio;
  final LoadState? active;
  final P p;

  @override
  void paint(Canvas cv, Size s) {
    if (s.width <= 0 || s.height <= 0) return;
    const barH = 8.0;
    final top = (s.height - barH) / 2;
    for (final (a, b, st) in AcwrGauge.bands) {
      final l = AcwrGauge.frac(a) * s.width, r = AcwrGauge.frac(b) * s.width;
      final pig = DomainColors.load(st);
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(l + 1.5, top, max(r - 1.5, l + 2), top + barH),
          const Radius.circular(barH / 2),
        ),
        Paint()
          ..color = st == active
              ? p.mark(pig)
              : p.mark(pig).withValues(alpha: p.dark ? .30 : .26),
      );
    }
    if (!ratio.isFinite) return;
    final x = AcwrGauge.frac(ratio) * s.width;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x, s.height / 2),
        width: 4,
        height: s.height,
      ),
      const Radius.circular(2),
    );
    cv.drawRRect(rect.inflate(2), Paint()..color = p.card);
    cv.drawRRect(rect, Paint()..color = p.ink);
  }

  @override
  bool shouldRepaint(covariant AcwrPainter o) =>
      o.ratio != ratio || o.active != active || o.p.dark != p.dark;
}
