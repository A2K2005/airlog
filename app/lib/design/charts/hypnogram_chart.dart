// HypnogramChart — the night's stages on four labelled lanes over clock time,
// with time-per-stage in the key. Wraps the ported Hypnogram painter.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/models.dart' show SleepStage, StageSpan;
import '../tokens/tokens.dart';
import 'axis.dart';
import 'frame.dart';
import 'painters.dart';

class HypnogramChart extends StatelessWidget {
  const HypnogramChart({
    super.key,
    required this.stages,
    this.start,
    this.end,
    this.title = 'Sleep stages',
    this.height = 132,
    this.semanticsLabel,
    this.emptyMessage = 'No stage data for this night',
  });

  final List<StageSpan> stages;

  /// Window (default: first span start → last span end).
  final DateTime? start, end;
  final String title;
  final double height;
  final String? semanticsLabel;
  final String emptyMessage;

  static Map<SleepStage, double> minutesByStage(List<StageSpan> spans) {
    final m = <SleepStage, double>{};
    for (final s in spans) {
      m[s.stage] = (m[s.stage] ?? 0) + s.minutes;
    }
    return m;
  }

  String _spoken((DateTime, DateTime)? w, Map<SleepStage, double> mins) {
    if (semanticsLabel != null) return semanticsLabel!;
    if (w == null) return '$title. $emptyMessage';
    return '$title from ${clockOf(w.$1)} to ${clockOf(w.$2)}. '
        '${[for (final s in Hypnogram.lanes) '${Hypnogram.label(s)} ${axisHm(mins[s] ?? 0)}'].join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final w = Hypnogram.window(stages, start: start, end: end);
    final mins = minutesByStage(stages);
    final cols = Hypnogram.cols(p);
    final tick = F.tab(F.over).copyWith(color: p.ink3, letterSpacing: .2);
    final laneStyle = F.cap.copyWith(color: p.ink2);
    final scaler = MediaQuery.textScalerOf(context);
    var gutter = 0.0;
    for (final s in Hypnogram.lanes) {
      final tp = TextPainter(
        text: TextSpan(text: Hypnogram.label(s), style: laneStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      gutter = max(gutter, tp.width);
    }
    final header = Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: F.bodySm.copyWith(color: p.ink, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (w != null)
          Text(
            '${clockOf(w.$1)} – ${clockOf(w.$2)}',
            style: F.tab(F.cap).copyWith(color: p.ink3),
          ),
      ],
    );

    return Semantics(
      container: true,
      label: _spoken(w, mins),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: S.x3),
            if (w == null)
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: height),
                child: Center(child: NoData(message: emptyMessage)),
              )
            else ...[
              SizedBox(
                height: height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: gutter,
                      child: Column(
                        children: [
                          for (final s in Hypnogram.lanes)
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  Hypnogram.label(s),
                                  style: laneStyle,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: p.line),
                            bottom: BorderSide(color: p.line),
                          ),
                        ),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: Hypnogram(
                            stages,
                            p,
                            start: w.$1,
                            end: w.$2,
                            t: animate(context, 1),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: S.x2, left: gutter + S.x3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(clockOf(w.$1), style: tick, maxLines: 1),
                    ),
                    Expanded(
                      child: Text(
                        clockOf(w.$1.add(w.$2.difference(w.$1) * .5)),
                        style: tick,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        clockOf(w.$2),
                        style: tick,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: S.x3),
              Wrap(
                spacing: S.x4,
                runSpacing: S.x1,
                children: [
                  for (final s in Hypnogram.lanes)
                    LegendSwatch(
                      label: '${Hypnogram.label(s)} ${axisHm(mins[s] ?? 0)}',
                      color: cols[s]!,
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
