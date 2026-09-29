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
