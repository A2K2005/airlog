// Recovery detail building blocks: one input in its band, the Plews
// readiness gauge, the 30-day history bars.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/day_key.dart';
import '../../../domain/results.dart';
import '../recovery_view_model.dart';

/// "28 Aug · 12 Sep · 26 Sep" for a dense window ending on [date].
List<String> windowLabels(String date, int n) {
  final first = DayKey.add(date, -(n - 1));
  return [dayMonth(first), dayMonth(DayKey.add(first, n ~/ 2)), dayMonth(date)];
}

/// One recovery input over 30 nights inside its personal band.
class InputCard extends StatelessWidget {
  const InputCard({super.key, required this.input, required this.date});
  final InputVm input;
  final String date;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final i = input;
    final pill = switch (i.state) {
      BandState.inRange => (
        'In your usual range',
        DomainColors.band(BandState.inRange),
      ),
      BandState.above => (
        'Above your usual range',
        DomainColors.band(BandState.above),
      ),
      BandState.below => (
        'Below your usual range',
        DomainColors.band(BandState.below),
      ),
      BandState.calibrating => ('Learning', C.neutral),
      BandState.noData || null => null,
    };
    final fmt = i.decimals == 0 ? axisInt : axisFixed;
    final axis = AxisSpec.of(
      [...i.values, i.lower, i.upper, if (i.mean != null) i.mean],
      ticks: 4,
      format: fmt,
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BaselineBandChart(
            title: i.label,
            unit: i.unit,
            // The trailing readout already carries the unit.
            showUnit: i.today == null,
            trailing: i.today == null
                ? null
                : Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: i.fmt(i.today!),
                          style: F.n24.copyWith(color: p.ink),
                        ),
                        TextSpan(
                          text: ' ${i.unit}',
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                  ),
            values: i.values,
            color: i.key == 'sleep' ? DomainColors.sleep : DomainColors.health,
            mean: i.mean,
            lower: i.lower,
            upper: i.upper,
            axis: axis,
            xLabels: windowLabels(date, i.values.length),
            format: fmt,
            semanticsLabel: [
              '${i.label} over the last ${i.values.length} nights, ${i.unit}',
              ?denseSummary(i.values, format: fmt, unit: i.unit),
              if (i.lower != null && i.upper != null)
                'usual range ${i.fmt(i.lower!)} to ${i.fmt(i.upper!)}',
            ].join('. '),
            footnote:
                i.footnote ??
                (i.lower != null && i.upper != null
                    ? 'Shaded: your usual range, ${i.fmt(i.lower!)}–'
                          '${i.fmt(i.upper!)} ${i.unit}. Dashed line: your '
                          'usual.'
                    : null),
          ),
          const SizedBox(height: S.x3),
          Wrap(
            spacing: S.x3,
            runSpacing: S.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (pill != null)
                StatePill(label: pill.$1, color: pill.$2, tinted: false),
              Text(i.line, style: F.tab(F.cap).copyWith(color: p.ink2)),
            ],
          ),
          if (i.provenance != null) ...[
            const SizedBox(height: S.x3),
            Align(
              alignment: Alignment.centerLeft,
              child: ProvenanceChip.of(i.provenance!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Plews readiness: the 7-night lnRMSSD average against the smallest
/// worthwhile change band, drawn in milliseconds.
class ReadinessCard extends StatelessWidget {
  const ReadinessCard({
    super.key,
    required this.readiness,
    required this.missing,
    this.onExplain,
  });
  final ReadinessVm? readiness;
  final String? missing;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final r = readiness;
    return AppCard(
      onTap: onExplain,
      semanticLabel: r == null
          ? '7-night HRV. ${missing ?? ''}'
          : '7-night HRV: ${r.headline}. ${r.body} Night-to-night swing '
                '${r.cv.toStringAsFixed(1)} percent. Tap for how this works.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: S.x3,
              runSpacing: S.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '7-night HRV',
                  style: F.bodySm.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (r != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x2 + 2,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: p.wash(
                        r.state == SwcState.below ? C.amber : C.health,
                      ),
                      borderRadius: R.rPill,
                    ),
                    child: Text(
                      r.headline,
                      style: F.cap.copyWith(
                        color: p.on(
                          r.state == SwcState.below ? C.amber : C.health,
                        ),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: S.x2),
            if (r == null)
              Text(missing ?? '', style: F.bodySm.copyWith(color: p.ink2))
            else ...[
              Text(r.body, style: F.tab(F.bodySm).copyWith(color: p.ink2)),
              const SizedBox(height: S.x4),
              SwcGauge(readiness: r),
              const SizedBox(height: S.x3),
              Wrap(
                spacing: S.x3,
                runSpacing: S.x2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Night-to-night swing ${r.cv.toStringAsFixed(1)}%',
                    style: F.tab(F.cap).copyWith(color: p.ink3),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'How this works',
                        style: F.cap.copyWith(
                          color: p.ink2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: p.ink3,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A horizontal scale in ms: the normal-variation band shaded, the baseline
/// ticked, the 7-night average as a dot.
class SwcGauge extends StatelessWidget {
  const SwcGauge({super.key, required this.readiness});
  final ReadinessVm readiness;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final r = readiness;
    final lo = math.min(r.lowerMs, r.rollingMs);
    final hi = math.max(r.upperMs, r.rollingMs);
    final pad = math.max((hi - lo) * .35, 2.0);
    final min = lo - pad, max = hi + pad;
    double t(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);
    final tick = F.tab(F.cap).copyWith(color: p.ink3);
    final dot = r.state == SwcState.below ? C.amber : C.health;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final scaler = MediaQuery.textScalerOf(context);
        Widget label(double v, String s, {TextAlign align = TextAlign.center}) {
          final x = t(v) * w;
          final measure = TextPainter(
            text: TextSpan(text: s, style: tick),
            textScaler: scaler,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: w);
          final labelWidth = math.min(w, math.max(80.0, measure.width + 2));
          measure.dispose();
          return Positioned(
            left: (x - labelWidth / 2).clamp(
              0.0,
              math.max(0.0, w - labelWidth),
            ),
            width: labelWidth,
            top: 0,
            child: Text(s, style: tick, textAlign: align, maxLines: 1),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 22,
              child: CustomPaint(
                painter: _GaugePainter(
                  band: (t(r.lowerMs), t(r.upperMs)),
                  mean: t(r.baselineMs),
                  value: t(r.rollingMs),
                  track: p.track,
                  bandInk: p.wash(C.health, strength: 1),
                  bandEdge: p.mark(C.health),
                  meanInk: p.ink3,
                  dotInk: p.mark(dot),
                  knockout: p.card,
                ),
              ),
            ),
            const SizedBox(height: S.x1),
            SizedBox(
              height: scaler.scale(18),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  label(r.lowerMs, '${r.lowerMs.round()}'),
                  label(r.upperMs, '${r.upperMs.round()} ms'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.band,
    required this.mean,
    required this.value,
    required this.track,
    required this.bandInk,
    required this.bandEdge,
    required this.meanInk,
    required this.dotInk,
    required this.knockout,
  });
  final (double, double) band;
  final double mean, value;
  final Color track, bandInk, bandEdge, meanInk, dotInk, knockout;

  @override
  void paint(Canvas cv, Size s) {
    final cy = s.height / 2;
    const h = 8.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, cy - h / 2, s.width, h),
      const Radius.circular(h / 2),
    );
    cv.drawRRect(r, Paint()..color = track);
    final b0 = band.$1 * s.width, b1 = band.$2 * s.width;
    cv.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(b0, cy - h / 2, math.max(b1, b0 + 2), cy + h / 2),
        const Radius.circular(h / 2),
      ),
      Paint()..color = bandInk,
    );
    final edge = Paint()
      ..color = bandEdge
      ..strokeWidth = 1.5;
    for (final x in [b0, b1]) {
      cv.drawLine(Offset(x, cy - h / 2 - 3), Offset(x, cy + h / 2 + 3), edge);
    }
    final mx = mean * s.width;
    cv.drawLine(
      Offset(mx, cy - h / 2),
      Offset(mx, cy + h / 2),
      Paint()
        ..color = meanInk
        ..strokeWidth = 1,
    );
    final vx = value * s.width;
    cv.drawCircle(Offset(vx, cy), 8, Paint()..color = knockout);
    cv.drawCircle(Offset(vx, cy), 6, Paint()..color = dotInk);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) =>
      o.band != band ||
      o.mean != mean ||
      o.value != value ||
      o.dotInk != dotInk ||
      o.track != track;
}

/// The last 30 days of Recovery, one bar per day coloured by zone.
class RecoveryHistory extends StatelessWidget {
  const RecoveryHistory({
    super.key,
    required this.scores,
    required this.zones,
    required this.date,
  });
  final List<double?> scores;
  final List<RecoveryZone?> zones;
  final String date;

  static const axis = AxisSpec(min: 0, max: 100, ticks: 3, format: axisInt);

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final real = scores.whereType<double>().toList();
    final colours = [
      for (final z in zones)
        p.mark(DomainColors.recoveryZone(z ?? RecoveryZone.yellow)),
    ];
    final avg = real.isEmpty
        ? null
        : real.reduce((a, b) => a + b) / real.length;
    final counts = {
      for (final z in RecoveryZone.values) z: zones.where((x) => x == z).length,
    };
    return ChartFrame(
      title: 'Last ${scores.length} days',
      unit: '%',
      height: 120,
      yAxis: real.isEmpty ? null : axis,
      xLabels: windowLabels(date, scores.length),
      series: scores,
      legend: [
        ('Good ${counts[RecoveryZone.green]}', p.mark(C.recGreen)),
        ('Fair ${counts[RecoveryZone.yellow]}', p.mark(C.recYellow)),
        ('Low ${counts[RecoveryZone.red]}', p.mark(C.recRed)),
      ],
      footnote: avg == null ? null : 'Average ${avg.round()}%',
      empty: real.isEmpty
          ? const NoData(message: 'No Recovery scores in this period')
          : null,
      child: CustomPaint(
        size: Size.infinite,
        painter: Bars(scores, p.mark(C.recGreen), colors: colours, axis: axis),
      ),
    );
  }
}
