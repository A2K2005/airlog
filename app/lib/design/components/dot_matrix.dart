// Dot-matrix numerals: text in the Subway Ticker Grid face (a 5×7 grid,
// K-Type), never a hand-drawn painter. The coarse "92" and the fine "56.7"
// of the design are the same face at different sizes.
//
// The face lacks en and em dashes (they have no ink), so a missing value is
// written with two hyphens ("--") and a negative number with U+2212, which
// the face draws as a five-dot bar. [DotMatrixNumber.missing] is the
// placeholder every tile shows while data is missing or calibrating.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'motion_widgets.dart';

class DotMatrixNumber extends StatelessWidget {
  const DotMatrixNumber(
    this.text, {
    super.key,
    this.style = F.dot32,
    this.color,
    this.semanticsLabel,
  });

  /// What the tile shows when there is no number yet.
  static const missing = '--';

  final String text;

  /// A dot-matrix step (F.dot72 … F.dot24, or F.n96 / n64 / n44).
  final TextStyle style;
  final Color? color;

  /// The plain value for screen readers ("56.7 milliseconds"). Defaults to
  /// the text, or "No value yet" for [missing].
  final String? semanticsLabel;

  /// Characters the face draws. Anything else would fall back to another
  /// font mid-number.
  static const glyphs = '0123456789.,:%+-−/ ';

  /// [text] with characters the face cannot draw replaced (en/em dashes →
  /// hyphen, minus → U+2212 kept, thin spaces → space).
  static String safe(String text) => text
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(' ', ' ')
      .replaceAll(' ', ' ')
      .replaceAll(' ', ' ');

  @override
  Widget build(BuildContext context) {
    final label =
        semanticsLabel ?? (text == missing ? 'No value yet' : text.trim());
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Text(
        safe(text),
        maxLines: 1,
        softWrap: false,
        style: style.copyWith(color: color ?? P.of(context).ink),
      ),
    );
  }
}

/// A dot-matrix number with its unit on the baseline and a caption below:
/// the "one number is the point" block of a flexible tile. The number row
/// scales down to fit (never overflows at 320 dp or large text); the
/// caption wraps. Values are unsigned: say the direction in [unit]
/// ("pts lower"), since the face draws a minus as a long bar.
class DotStat extends StatelessWidget {
  const DotStat({
    super.key,
    required this.value,
    this.unit,
    this.caption,
    this.color,
    this.style = F.dot32,
    this.semanticsLabel,
    this.swap = false,
  });

  final String value;
  final String? unit;
  final String? caption;
  final Color? color;
  final TextStyle style;

  /// Crossfade when [value] changes on the same screen (a sync). Never for
  /// a number that changes per keystroke or per second.
  final bool swap;

  /// The spoken value; defaults to "value unit, caption".
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final spoken =
        semanticsLabel ??
        [
          value == DotMatrixNumber.missing ? 'No value yet' : value,
          ?unit,
        ].join(' ') +
            (caption == null ? '' : ', $caption');
    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (swap)
                    FadeSwap(
                      swapKey: value,
                      child: DotMatrixNumber(value, style: style, color: color),
                    )
                  else
                    DotMatrixNumber(value, style: style, color: color),
                  if (unit != null) ...[
                    const SizedBox(width: S.x2),
                    Text(
                      unit!,
                      style: F.tileLabel.copyWith(color: TileInk.unit),
                    ),
                  ],
                ],
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: S.x1),
              Text(caption!, style: F.cap.copyWith(color: p.ink2)),
            ],
          ],
        ),
      ),
    );
  }
}
