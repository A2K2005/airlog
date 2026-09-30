// ScatterConsistency — bed and wake times across nights.
//
// Each night is a column: a faint bar for the time asleep, a dot at bedtime
// and a dot at wake. Time runs DOWN the y axis (evening at the top), so a
// consistent schedule is two flat rows of dots and drift is visible at once.
// The dashed lines are the medians of the nights shown.

import 'dart:math';

import 'package:flutter/material.dart';

import '../format.dart' show clockText;
import '../tokens/tokens.dart';
import 'axis.dart';
import 'frame.dart';

/// One night's sleep window.
class NightWindow {
  const NightWindow(this.bed, this.wake);
  final DateTime bed;
  final DateTime wake;
}

class ScatterConsistency extends StatelessWidget {
  const ScatterConsistency({
    super.key,
    required this.nights,
    this.title = 'Bed and wake times',
    this.xLabels = const [],
    this.height = 170,
    this.semanticsLabel,
    this.emptyMessage = 'No nights recorded in this period',
  });

  /// DENSE, oldest first, one slot per night; null = no sleep recorded.
  final List<NightWindow?> nights;
  final String title;
  final List<String> xLabels;
  final double height;
  final String? semanticsLabel;
  final String emptyMessage;

  /// Minutes since the NOON before the night (so 23:00 → 660, 07:00 → 1140).
  static double sinceNoon(DateTime t) {
    final m = t.hour * 60 + t.minute + t.second / 60;
    return m >= 720 ? m - 720 : m + 720;
  }

  static double? _median(List<double> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }

  /// Plotted value: negative minutes-since-noon (so later is lower).
  static String _fmt(double v) => clockHm(720 - v);
  static String _fmt12(double v) => axisClock(720 - v, use24h: false);

  /// [use24h]: the phone's clock setting; 12-hour ticks read "11 pm".
  static AxisSpec? axisFor(List<double> plotted, {bool use24h = true}) {
    final v = finiteOnly(plotted);
    if (v.isEmpty) return null;
    var lo = (v.reduce(min) / 60).floorToDouble() * 60;
    var hi = (v.reduce(max) / 60).ceilToDouble() * 60;
    if (hi - lo < 120) {
      lo -= 60;
      hi += 60;
    }
    final spanH = (hi - lo) / 60;
    var step = 1;
    for (final s in const [1, 2, 3, 4, 6]) {
      step = s;
      if ((spanH / s).ceil() + 1 <= 6) break;
    }
    final k = (spanH / step).ceil();
    hi = lo + k * step * 60;
    return AxisSpec(
      min: lo,
      max: hi,
      ticks: k + 1,
      format: use24h ? _fmt : _fmt12,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    String clock(double m) => clockText(m, use24h: h24);
    final real = [
      for (final n in nights)
        if (n != null && n.wake.isAfter(n.bed)) n,
    ];
    final beds = [for (final n in real) sinceNoon(n.bed)];
    final wakes = [for (final n in real) sinceNoon(n.wake)];
    final a = axisFor([
      for (final b in beds) -b,
      for (final w in wakes) -w,
    ], use24h: h24);
    final empty = real.isEmpty || a == null;
    final mb = _median(beds), mw = _median(wakes);
    final bedInk = p.mark(DomainColors.sleep);
    final wakeInk = p.mark(C.amber);
    String spoken() {
      if (semanticsLabel != null) return semanticsLabel!;
      if (empty) return '$title. $emptyMessage';
      final bLo = beds.reduce(min), bHi = beds.reduce(max);
      final wLo = wakes.reduce(min), wHi = wakes.reduce(max);
      return '$title across ${real.length} nights. '
          'Bedtime from ${clock(bLo + 720)} to ${clock(bHi + 720)}, '
          'typically ${clock(mb! + 720)}. '
          'Wake from ${clock(wLo + 720)} to ${clock(wHi + 720)}, '
          'typically ${clock(mw! + 720)}.';
    }

    return ChartFrame(
      title: title,
      unit: '',
      height: height,
      yAxis: empty ? null : a,
      xLabels: xLabels,
      semanticsLabel: spoken(),
      legend: empty ? const [] : [('Bedtime', bedInk), ('Wake', wakeInk)],
      footnote: empty
          ? null
          : 'Dashed lines: your typical bedtime ${clock(mb! + 720)} and wake '
                'time ${clock(mw! + 720)}',
      empty: empty ? NoData(message: emptyMessage) : null,
      child: empty
          ? const SizedBox.shrink()
          : CustomPaint(
              size: Size.infinite,
              painter: ScatterConsistencyPainter(
                nights: nights,
                axis: a,
                bedInk: bedInk,
                wakeInk: wakeInk,
                barInk: p.wash(DomainColors.sleep, strength: .9),
                medianInk: p.ink3,
                medianBed: mb == null ? null : -mb,
                medianWake: mw == null ? null : -mw,
              ),
            ),
    );
  }
}

class ScatterConsistencyPainter extends CustomPainter {
  ScatterConsistencyPainter({
    required this.nights,
    required this.axis,
    required this.bedInk,
    required this.wakeInk,
    required this.barInk,
    required this.medianInk,
    this.medianBed,
    this.medianWake,
  });

  final List<NightWindow?> nights;
  final AxisSpec axis;
  final Color bedInk, wakeInk, barInk, medianInk;
  final double? medianBed, medianWake;

  @override
  void paint(Canvas cv, Size s) {
    if (nights.isEmpty || s.width <= 0 || s.height <= 0) return;
    double y(double v) => s.height - axis.t(v) * s.height;
    final slot = s.width / nights.length;
    final r = min(3.5, max(slot * .28, 1.6));
    final dash = Paint()
      ..color = medianInk.withValues(alpha: .8)
      ..strokeWidth = 1;
    for (final m in [medianBed, medianWake]) {
      if (m == null || !m.isFinite) continue;
      final yy = y(m);
      for (var xx = 0.0; xx < s.width; xx += 7) {
        cv.drawLine(Offset(xx, yy), Offset(min(xx + 3.5, s.width), yy), dash);
      }
    }
    for (var i = 0; i < nights.length; i++) {
      final n = nights[i];
      if (n == null || !n.wake.isAfter(n.bed)) continue;
      final x = slot * (i + .5);
      final yb = y(-ScatterConsistency.sinceNoon(n.bed));
      final yw = y(-ScatterConsistency.sinceNoon(n.wake));
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - r, min(yb, yw), x + r, max(yb, yw)),
          Radius.circular(r),
        ),
        Paint()..color = barInk,
      );
      cv.drawCircle(Offset(x, yb), r, Paint()..color = bedInk);
      cv.drawCircle(Offset(x, yw), r, Paint()..color = wakeInk);
    }
  }

  @override
  bool shouldRepaint(covariant ScatterConsistencyPainter o) =>
      o.nights != nights || o.axis != axis || o.bedInk != bedInk;
}
