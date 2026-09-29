// ZoneTimeline — heart rate across a window, each stretch coloured by zone.
//
// Zone floors come from the caller (computed by the engine: Engine.zoneFor /
// the Karvonen thresholds it used). The widget only compares a bpm with those
// floors to pick a colour; it never decides what a zone is.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/models.dart' show HrSample;
import '../tokens/tokens.dart';
import 'axis.dart';
import 'frame.dart';

class ZoneTimeline extends StatelessWidget {
  const ZoneTimeline({
    super.key,
    required this.samples,
    required this.start,
    required this.end,
    required this.zoneFloors,
    this.title = 'Heart rate',
    this.workouts = const [],
    this.rest = const [],
    this.maxGapMinutes = 10,
    this.height = 150,
    this.axis,
    this.semanticsLabel,
    this.emptyMessage = 'No heart-rate samples for this window',
  });

  final List<HrSample> samples;
  final DateTime start, end;

  /// bpm at which zones 1…5 begin, ascending (5 values). Below the first is
  /// zone 0 (rest).
  final List<double> zoneFloors;
  final String title;

  /// Exercise sessions, drawn as blocks on the top edge.
  final List<(DateTime, DateTime)> workouts;

  /// Sleep, drawn as a faint full-height tint.
  final List<(DateTime, DateTime)> rest;

  /// Samples further apart than this many minutes are not joined (a gap
  /// stays a gap).
  final int maxGapMinutes;
  final double height;
  final AxisSpec? axis;
  final String? semanticsLabel;
  final String emptyMessage;

  List<HrSample> get _inWindow => [
    for (final s in samples)
      if (s.bpm.isFinite && !s.t.isBefore(start) && !s.t.isAfter(end)) s,
  ]..sort((a, b) => a.t.compareTo(b.t));

  static int zoneOf(double bpm, List<double> floors) {
    var z = 0;
    for (final f in floors) {
      if (bpm >= f) z++;
    }
    return z.clamp(0, 5);
  }

  List<String> _xLabels() {
    final total = end.difference(start);
    if (total.inMinutes <= 0) return const [];
    return [for (var i = 0; i <= 4; i++) clockOf(start.add(total * (i / 4)))];
  }

  String _spoken(List<HrSample> s) {
    if (semanticsLabel != null) return semanticsLabel!;
    if (s.isEmpty) return '$title. $emptyMessage';
    var lo = s.first, hi = s.first;
    for (final x in s) {
      if (x.bpm < lo.bpm) lo = x;
      if (x.bpm > hi.bpm) hi = x;
    }
    return '$title, beats per minute, ${clockOf(start)} to ${clockOf(end)}. '
        'Lowest ${lo.bpm.round()}, peak ${hi.bpm.round()} at ${clockOf(hi.t)}, '
        'peak zone ${zoneOf(hi.bpm, zoneFloors)}.';
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final s = _inWindow;
    final validWindow = end.isAfter(start);
    final floors = [
      for (final f in zoneFloors)
        if (f.isFinite) f,
    ]..sort();
    final bpm = [for (final x in s) x.bpm];
    final spread = bpm.isEmpty ? 0.0 : bpm.reduce(max) - bpm.reduce(min);
    final a = axis ?? AxisSpec.of(bpm, ticks: 3, step: spread > 80 ? 40 : 20);
    final empty = s.isEmpty || a == null || !validWindow;
    final ink = [for (var i = 0; i <= 5; i++) p.mark(DomainColors.hrZone(i))];
    final present = <int>{for (final x in s) zoneOf(x.bpm, floors)};
    return ChartFrame(
      title: title,
      unit: 'bpm',
      height: height,
      yAxis: empty ? null : a,
      xLabels: empty ? const [] : _xLabels(),
      semanticsLabel: _spoken(s),
      legend: empty
          ? const []
          : [
              for (var z = 0; z <= 5; z++)
                if (present.contains(z)) (z == 0 ? 'Rest' : 'Zone $z', ink[z]),
            ],
      empty: empty ? NoData(message: emptyMessage) : null,
      child: empty
          ? const SizedBox.shrink()
          : CustomPaint(
              size: Size.infinite,
              painter: ZoneTimelinePainter(
                samples: s,
                start: start,
                end: end,
                floors: floors,
                axis: a,
                zoneInk: ink,
                floorInk: p.ink3,
                blockInk: p.mark(DomainColors.strain),
                restInk: p.wash(DomainColors.sleep),
                maxGapMinutes: maxGapMinutes,
                workouts: workouts,
                rest: rest,
              ),
            ),
    );
  }
}

class ZoneTimelinePainter extends CustomPainter {
  ZoneTimelinePainter({
    required this.samples,
    required this.start,
    required this.end,
    required this.floors,
    required this.axis,
    required this.zoneInk,
    required this.floorInk,
    required this.blockInk,
    required this.restInk,
    required this.maxGapMinutes,
    this.workouts = const [],
    this.rest = const [],
  });

  final List<HrSample> samples; // sorted, inside the window, finite
  final DateTime start, end;
  final List<double> floors;
  final AxisSpec axis;
  final List<Color> zoneInk;
  final Color floorInk, blockInk, restInk;
  final int maxGapMinutes;
  final List<(DateTime, DateTime)> workouts, rest;

  @override
  void paint(Canvas cv, Size s) {
    final total = end.difference(start).inSeconds.toDouble();
    if (samples.isEmpty || total <= 0 || s.width <= 0 || s.height <= 0) return;
    double fx(DateTime t) =>
        (t.difference(start).inSeconds / total).clamp(0.0, 1.0) * s.width;
    double y(double v) => s.height - axis.t(v) * s.height;

    for (final (a, b) in rest) {
      final l = fx(a), r = fx(b);
      if (r - l < .5) continue;
      cv.drawRect(Rect.fromLTRB(l, 0, r, s.height), Paint()..color = restInk);
    }

    // The zone-1 floor only: the line between "resting" and "training".
    // Every zone above it is carried by the line's own colour and the key;
    // five stacked threshold lines were clutter.
    final dot = Paint()
      ..color = floorInk.withValues(alpha: .55)
      ..strokeWidth = 1;
    for (var i = 0; i < floors.length && i < 1; i++) {
      final f = floors[i];
      if (f <= axis.min || f >= axis.max) continue;
      final yy = y(f);
      for (var xx = 0.0; xx < s.width - 44; xx += 5) {
        cv.drawLine(Offset(xx, yy), Offset(xx + 2, yy), dot);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: 'Zone 1',
          style: F.over.copyWith(color: floorInk, letterSpacing: .2),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(cv, Offset(s.width - tp.width, yy - tp.height - 1));
    }

    // Bucket to ≤ 1 point per 1.5 px, mean bpm per bucket.
    final cols = max(1, (s.width / 1.5).floor());
    final sum = List<double>.filled(cols, 0), cnt = List<int>.filled(cols, 0);
    for (final x in samples) {
      final c = (fx(x.t) / s.width * (cols - 1)).round().clamp(0, cols - 1);
      sum[c] += x.bpm;
      cnt[c]++;
    }
    final colSec = total / cols;
    final joinCols = max(1, (maxGapMinutes * 60 / colSec).ceil());
    final pts = <(int, Offset, int)>[];
    for (var c = 0; c < cols; c++) {
      if (cnt[c] == 0) continue;
      final v = sum[c] / cnt[c];
      pts.add((
        c,
        Offset(cols == 1 ? s.width / 2 : c / (cols - 1) * s.width, y(v)),
        ZoneTimeline.zoneOf(v, floors),
      ));
    }
    Paint stroke(int z) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = zoneInk[z];
    var i = 0;
    while (i < pts.length) {
      var j = i;
      while (j + 1 < pts.length && pts[j + 1].$1 - pts[j].$1 <= joinCols) {
        j++;
      }
      if (i == j) {
        // An isolated reading: a dot, never a line to its neighbours.
        cv.drawCircle(pts[i].$2, 1.8, Paint()..color = zoneInk[pts[i].$3]);
      } else {
        // Segments grouped by the zone of their far end.
        var k = i;
        while (k < j) {
          final z = pts[k + 1].$3;
          final path = Path()..moveTo(pts[k].$2.dx, pts[k].$2.dy);
          while (k < j && pts[k + 1].$3 == z) {
            path.lineTo(pts[k + 1].$2.dx, pts[k + 1].$2.dy);
            k++;
          }
          cv.drawPath(path, stroke(z));
        }
      }
      i = j + 1;
    }

    for (final (a, b) in workouts) {
      final l = fx(a), r = fx(b);
      cv.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(l, 0, max(r - l, 2), 4), R.bar),
        Paint()..color = blockInk,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ZoneTimelinePainter o) =>
      o.samples != samples ||
      o.axis != axis ||
      o.start != start ||
      o.end != end ||
      o.floors != floors ||
      o.zoneInk != zoneInk;
}
