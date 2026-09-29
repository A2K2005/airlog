// Type. Two faces, both bundled (nothing is fetched):
//
// * UI: DM Sans, the variable font (OFL). Picked by glyph comparison against
//   the design PNGs (docs/DESIGN_SYSTEM.md, "UI font"); swap the face by
//   changing [F.ui] alone. Flutter drives the `wght` axis from fontWeight;
//   the optical size axis (`opsz`) is set explicitly on every style to its
//   font size, as the design tool does.
// * Numerals: Subway Ticker Grid (K-Type), the 5×7 dot-matrix face every
//   hero number in the design is set in. Its dots sit on a 132-unit pitch,
//   99 units square, so a size s draws dots 0.099·s wide at a 0.132·s pitch.
//
// The design sets DM Sans Medium with −2 % tracking at 16 / 14 / 12 / 10 px;
// the tile ramp below is those steps. The older names (display … over,
// n96 … n18) are kept so every screen keeps compiling; they map onto the
// same faces and tracking.

import 'package:flutter/painting.dart';

abstract final class F {
  /// THE UI face. One token: change it here and every style follows.
  static const ui = 'DM Sans';

  /// The dot-matrix numeral face.
  static const numerals = 'Doto';

  static const _tab = [FontFeature.tabularFigures()];

  /// Glyphs DM Sans lacks (the subscript two of SpO₂ and VO₂) come from
  /// Manrope, bundled at one weight for exactly that.
  static const _fallback = ['Manrope'];

  // ── tile ramp (the design's own steps) ──────────────────────────────────

  /// The day's plan headline (the one large sentence on Today).
  static const tileHeadline = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w500,
    letterSpacing: -.48,
    fontVariations: [FontVariation('opsz', 24)],
  );

  /// Tile titles ("HRV Baseline").
  static const tileTitle = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: -.32,
    fontVariations: [FontVariation('opsz', 16)],
  );

  /// Status words ("Stabilizing", "Good") and 16 px values.
  static const tileStatus = tileTitle;

  /// Values and body copy inside tiles ("Medium", "High").
  static const tileBody = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -.28,
    fontVariations: [FontVariation('opsz', 14)],
  );

  /// Units and labels ("ms", "Average").
  static const tileLabel = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -.24,
    fontVariations: [FontVariation('opsz', 12)],
  );

  /// The smallest captions ("Stress Level", Readiness's bar labels).
  static const tileTiny = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 10,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -.16,
    fontVariations: [FontVariation('opsz', 9)],
  );

  /// Captions (Sleep's labels, axis times).
  static const tileMicro = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 10,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -.2,
    fontVariations: [FontVariation('opsz', 10)],
  );

  /// UI-face numbers inside tiles ("146", "5:44").
  static const tileNumber = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: -.4,
    fontVariations: [FontVariation('opsz', 20)],
    fontFeatures: _tab,
  );

  // ── dot-matrix steps (sizes measured on the PNGs) ───────────────────────

  static const dot72 = TextStyle(
    fontFamily: numerals,
    fontSize: 72,
    height: 1,
    fontFeatures: _tab,
  );
  static const dot48 = TextStyle(
    fontFamily: numerals,
    fontSize: 48,
    height: 1,
    fontFeatures: _tab,
  );
  static const dot40 = TextStyle(
    fontFamily: numerals,
    fontSize: 40,
    height: 1,
    fontFeatures: _tab,
  );
  static const dot36 = TextStyle(
    fontFamily: numerals,
    fontSize: 36,
    height: 1,
    fontFeatures: _tab,
  );
  static const dot32 = TextStyle(
    fontFamily: numerals,
    fontSize: 32,
    height: 1,
    fontFeatures: _tab,
  );
  static const dot28 = TextStyle(
    fontFamily: numerals,
    fontSize: 28,
    height: 1,
    fontFeatures: _tab,
  );
  static const dot24 = TextStyle(
    fontFamily: numerals,
    fontSize: 24,
    height: 1,
    fontFeatures: _tab,
  );

  // ── screen ramp (pages around the tiles) ────────────────────────────────

  /// Screen titles ("Today").
  static const display = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -.56,
    fontVariations: [FontVariation('opsz', 28)],
  );

  /// Sheet and detail-screen titles.
  static const t1 = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -.44,
    fontVariations: [FontVariation('opsz', 22)],
  );

  /// Card titles.
  static const t2 = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -.36,
    fontVariations: [FontVariation('opsz', 18)],
  );

  /// Row titles, button labels.
  static const head = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w500,
    letterSpacing: -.32,
    fontVariations: [FontVariation('opsz', 16)],
  );

  static const body = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w500,
    letterSpacing: -.2,
    fontVariations: [FontVariation('opsz', 15)],
  );

  static const bodySm = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: -.14,
    fontVariations: [FontVariation('opsz', 14)],
  );

  static const cap = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 12.5,
    height: 17 / 12.5,
    fontWeight: FontWeight.w500,
    letterSpacing: -.12,
    fontVariations: [FontVariation('opsz', 12.5)],
  );

  /// Chips and provenance captions.
  static const micro = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 11.5,
    height: 15 / 11.5,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('opsz', 11.5)],
  );

  /// Uppercase labels and axis ticks. Letter-spaced, so write the string in
  /// uppercase at the call site when it is a label (not for axis numbers).
  static const over = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: .8,
    fontVariations: [FontVariation('opsz', 11)],
  );

  // ── numerals: the dot-matrix face, monospaced ───────────────────────────
  // Every digit of the face has the same advance (0.792 em), so a changing
  // number never re-flows. Height 1: numerals are placed by their box.

  /// The live BPM: the one number read from arm's length mid-workout.
  static const n96 = TextStyle(
    fontFamily: numerals,
    fontSize: 96,
    height: 1,
    fontFeatures: _tab,
  );

  /// Hero numbers.
  static const n64 = TextStyle(
    fontFamily: numerals,
    fontSize: 64,
    height: 1,
    fontFeatures: _tab,
  );
  static const n44 = TextStyle(
    fontFamily: numerals,
    fontSize: 44,
    height: 1,
    fontFeatures: _tab,
  );
  static const n32 = dot32;

  /// Below 28 px the dots blur together: small numbers use the UI face.
  static const n24 = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 24,
    height: 1,
    fontWeight: FontWeight.w500,
    letterSpacing: -.48,
    fontVariations: [FontVariation('opsz', 24)],
    fontFeatures: _tab,
  );
  static const n18 = TextStyle(
    fontFamily: ui,
    fontFamilyFallback: _fallback,
    fontSize: 18,
    height: 1,
    fontWeight: FontWeight.w500,
    letterSpacing: -.36,
    fontVariations: [FontVariation('opsz', 18)],
    fontFeatures: _tab,
  );

  /// [s] scaled by [k] (ring units that track the ring's numeral size). The
  /// optical size follows the new size.
  static TextStyle scaled(TextStyle s, double k) {
    final size = (s.fontSize ?? 14) * k;
    return s.copyWith(
      fontSize: size,
      letterSpacing: s.letterSpacing == null ? null : s.letterSpacing! * k,
      fontVariations: s.fontFamily == ui
          ? [FontVariation('opsz', size.clamp(9, 40).toDouble())]
          : s.fontVariations,
    );
  }

  /// Tabular figures on a UI style, for small changing numbers in running
  /// text: "12 min ago", axis ticks, "+4 ms". (DM Sans has no tabular
  /// figures; the feature is kept so a face that has them picks it up.)
  static TextStyle tab(TextStyle s) => s.copyWith(fontFeatures: _tab);
}
