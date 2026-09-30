// The metric cards under a coach answer: a picture of one cited number, in
// the app's tile language (a glow surface, dot-matrix numerals, tile inks).
//
// Principle 6: a card prints only the cited SourceRef and its AnswerVisual,
// both from the answer's own tool results. It never computes a number. The
// tier follows the data, and no honest data means no card:
//
//   trend   ≥ 3 days of a series      full width, a sparkline against the
//                                      usual range or the dotted usual line
//   range   the usual range            half width, the Today tiles' knob line
//   usual   the usual (a mean) only    half width, "Usual 58 ms"
//   value   the number only            half width, the number and its day
//
// Labels are the metric's short name on one line (never the ref's long
// label), so nothing is cut ("Recove…").

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/coach/coach_contracts.dart';
import '../../../domain/coach/format.dart';

enum MetricTier { trend, range, usual, value }

/// The short name a card prints for [metric].
String metricName(String metric) => switch (metric) {
  'recovery' => 'Recovery',
  'hrv' => 'HRV',
  'resting_hr' => 'Resting HR',
  'respiratory_rate' => 'Breathing',
  'spo2' => 'Blood oxygen',
  'skin_temp' => 'Skin temp',
  'sleep_duration' => 'Sleep',
  'sleep_performance' => 'Sleep goal',
  'strain' => 'Strain',
  'steps' => 'Steps',
  _ => metric,
};

/// A cited value as text: "64%", "52 ms", "6h 40m", "23:35".
String readingOf(SourceRef r) {
  final v = r.value;
  if (v == null) return DotMatrixNumber.missing;
  return CoachFormat.value(v, r.unit);
}

/// [value] in [ref]'s unit ("58 ms", "7h 50m").
String readingIn(double value, SourceRef ref) =>
    CoachFormat.value(value, ref.unit);

/// The day or span a ref belongs to: "Mon 28 Sep", "Average · 1 to 28 Sep".
String captionOf(SourceRef r) {
  final d = r.date;
  if (d != null) {
    try {
      return shortDay(d);
    } catch (_) {}
  }
  final parts = r.label.split(' · ');
  if (parts.length < 2) return '';
  final rest = parts.sublist(1).join(' · ');
  final head = parts.first.toLowerCase();
  return head.contains('mean') || head.contains('average')
      ? 'Average · $rest'
      : rest;
}

/// A reading with its digits in dot numerals and its letters in the UI
/// face: "6h 40m" → dots "6", "h", dots " 40", "m".
class DotReading extends StatelessWidget {
  const DotReading(
    this.text, {
    super.key,
    this.style = F.dot32,
    this.unitStyle = F.tileLabel,
    this.color = TileInk.primary,
  });

  final String text;
  final TextStyle style;
  final TextStyle unitStyle;
  final Color color;

  static const _dotChars = '0123456789.,:%+-−';

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final b = StringBuffer();
    bool? dot;
    void flush() {
      if (b.isEmpty) return;
      final s = b.toString();
      final isDot = dot ?? false;
      spans.add(
        TextSpan(
          text: isDot ? DotMatrixNumber.safe(s) : s,
          style: isDot
              ? style.copyWith(color: color)
              : unitStyle.copyWith(color: TileInk.unit),
        ),
      );
      b.clear();
    }

    for (final ch in text.split('')) {
      // Digits and number punctuation in dots; spaces, letters and "/"
      // (a unit's) in the UI face.
      final isDot = _dotChars.contains(ch);
      if (dot != null && isDot != dot) flush();
      dot = isDot;
      b.write(ch);
    }
    flush();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(children: spans),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.source,
    required this.visual,
    this.onTap,
  });

  final SourceRef source;
  final AnswerVisual visual;
  final VoidCallback? onTap;

  static const height = 132.0;

  static MetricTier tierOf(AnswerVisual v) {
    final points = v.series.where((p) => p.value != null).length;
    if (points >= 3) return MetricTier.trend;
    if (v.usualLow != null && v.usualHigh != null) return MetricTier.range;
    if (v.usual != null) return MetricTier.usual;
    return MetricTier.value;
  }

  /// The glow of the metric's own Today tile.
  static GlowRecipe glowFor(String metric) => switch (metric) {
    'recovery' => GlowRecipes.l5,
    'sleep_duration' || 'sleep_performance' => GlowRecipes.s5,
    'strain' => GlowRecipes.s2,
    'hrv' => GlowRecipes.s8,
    'resting_hr' => GlowRecipes.s6,
    'respiratory_rate' || 'spo2' => GlowRecipes.s7,
    'skin_temp' => GlowRecipes.s9,
    _ => GlowRecipes.m19,
  };

  static Color accentFor(String metric) => switch (metric) {
    'recovery' => C.recGreen,
    'sleep_duration' || 'sleep_performance' => C.sleep,
    'strain' || 'steps' => C.strain,
    _ => C.health,
  };

  /// "In range" / "Above usual" / "Below usual" from the Health Monitor's
  /// state, or null.
  static String? stateWord(String? state) => switch (state) {
    'in range' => 'In range',
    'above range' => 'Above usual',
    'below range' => 'Below usual',
    _ => null,
  };

  /// "Usual 58 ms", "Usual 58 ms · 10% below usual".
  static String? usualLine(AnswerVisual v, SourceRef r) {
    final u = v.usual;
    if (u == null) return null;
    final vs = v.vsUsualPct;
    final base = 'Usual ${readingIn(u, r)}';
    if (vs == null || vs.round() == 0) return base;
    final n = CoachFormat.number(vs.abs());
    return '$base · $n% ${vs < 0 ? 'below' : 'above'} usual';
  }

  /// Everything the card shows, as one sentence.
  static String spoken(SourceRef r, AnswerVisual v) {
    final parts = <String>[
      '${metricName(v.metric)}, ${readingOf(r)}',
      if (captionOf(r).isNotEmpty) captionOf(r),
      ?stateWord(v.state),
      ?usualLine(v, r),
    ];
    if (tierOf(v) == MetricTier.trend) {
      parts.add('Trend of the last ${v.series.length} days');
    }
    return '${parts.join('. ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final tier = tierOf(visual);
    final name = Text(
      metricName(visual.metric),
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: F.tileTitle.copyWith(color: TileInk.primary),
    );
    final caption = captionOf(source);
    // A span ("Average · Tue 15 Sep to Mon 28 Sep") may take two lines.
    final day = Text(
      caption,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: F.tileMicro.copyWith(color: TileInk.secondary),
    );
    final value = DotReading(readingOf(source));
    final Widget body = switch (tier) {
      MetricTier.trend => _trend(name, day, value),
      MetricTier.range => _half(name, day, value, _range()),
      MetricTier.usual => _half(
        name,
        day,
        value,
        Text(
          usualLine(visual, source)!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: F.tileLabel.copyWith(color: TileInk.unit),
        ),
      ),
      MetricTier.value => _half(name, day, value, null),
    };
    return GlowPanel(
      glow: glowFor(visual.metric),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(S.tilePad, 14, S.tilePad, 14),
      onTap: onTap,
      semanticLabel: '${spoken(source, visual)} Opens details.',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height - 28),
          child: body,
        ),
      ),
    );
  }

  Widget _half(Widget name, Widget day, Widget value, Widget? foot) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      name,
      day,
      const SizedBox(height: S.x3),
      value,
      if (foot != null) ...[const SizedBox(height: S.x1), foot],
    ],
  );

  Widget _range() {
    final pos = BaselinePosition.of(
      source.value,
      visual.usualLow,
      visual.usualHigh,
    );
    final word = stateWord(visual.state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pos != null)
          SizedBox(
            height: 12,
            child: CustomPaint(painter: _RangePainter(pos)),
          ),
        if (word != null)
          Text(
            word,
            maxLines: 1,
            style: F.tileLabel.copyWith(
              color: word == 'In range' ? TileInk.unit : C.amber,
            ),
          ),
      ],
    );
  }

  Widget _trend(Widget name, Widget day, Widget value) {
    final values = [for (final p in visual.series) p.value];
    final days = values.length;
    final hasRange = visual.usualLow != null && visual.usualHigh != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              name,
              day,
              const SizedBox(height: S.x3),
              value,
            ],
          ),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          flex: 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: S.x2),
              Sparkline(
                values: values,
                color: accentFor(visual.metric),
                height: 64,
                lower: hasRange ? visual.usualLow : null,
                upper: hasRange ? visual.usualHigh : null,
                mean: hasRange ? null : visual.usual,
              ),
              const SizedBox(height: S.x1),
              Text(
                visual.usual != null && !hasRange
                    ? 'Last $days days · usual dotted'
                    : 'Last $days days',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.tileMicro.copyWith(color: TileInk.secondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The usual range as a track with the band from 15 % to 85 % and today's
/// knob (the Today tiles' mark and formula).
class _RangePainter extends CustomPainter {
  const _RangePainter(this.pos);
  final double pos;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawRect(
      Rect.fromLTRB(0, y - 1, size.width, y + 1),
      Paint()..color = C.track,
    );
    canvas.drawRect(
      Rect.fromLTRB(size.width * .15, y - 1.5, size.width * .85, y + 1.5),
      Paint()..color = TileInk.tertiary,
    );
    paintKnob(canvas, Offset(size.width * pos, y));
  }

  @override
  bool shouldRepaint(_RangePainter o) => o.pos != pos;
}

/// Up to [max] metric cards: a trend takes a row; the others pair up.
class MetricCards extends StatelessWidget {
  const MetricCards({
    super.key,
    required this.message,
    required this.onOpen,
    this.max = 2,
  });

  final ChatMessage message;
  final void Function(SourceRef ref, AnswerVisual visual) onOpen;
  final int max;

  /// The cards [m] can show: its visuals joined to their cited refs.
  static List<(SourceRef, AnswerVisual)> of(ChatMessage m, {int max = 2}) {
    final byId = {for (final r in m.refs) r.id: r};
    return [
      for (final v in m.visuals)
        if (byId[v.refId]?.value != null) (byId[v.refId]!, v),
    ].take(max).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cards = of(message, max: max);
    final rows = <Widget>[];
    final half = <Widget>[];
    void pair() {
      if (half.isEmpty) return;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: half[0]),
              const SizedBox(width: S.x3),
              Expanded(child: half.length > 1 ? half[1] : const SizedBox()),
            ],
          ),
        ),
      );
      half.clear();
    }

    for (final (r, v) in cards) {
      final card = MetricCard(
        key: ValueKey('metric-${message.id}-${r.id}'),
        source: r,
        visual: v,
        onTap: () => onOpen(r, v),
      );
      if (MetricCard.tierOf(v) == MetricTier.trend) {
        pair();
        rows.add(card);
      } else {
        half.add(card);
        if (half.length == 2) pair();
      }
    }
    pair();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: S.x3),
          rows[i],
        ],
      ],
    );
  }
}
