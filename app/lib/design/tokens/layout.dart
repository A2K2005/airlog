// Adapted from OpenStrap/edge lib/ui2/theme.dart (MIT, see third_party/edge/LICENSE).
// Changes: a screen gutter token; the tap floor is Android's 48 dp (Edge used
// iOS's 44 pt); radii re-scaled for 22 px cards and 28 px sheets.

import 'package:flutter/painting.dart';

/// ── SPACING ── 4 pt grid ──────────────────────────────────────────────────
abstract final class S {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x12 = 48.0;
  static const x16 = 64.0;

  /// Horizontal page padding.
  static const gutter = 20.0;

  /// Padding inside a card.
  static const card = 18.0;

  /// Minimum touch target (Material / Android accessibility: 48 dp).
  /// `Pressable` applies it; nothing tappable is smaller.
  static const tap = 48.0;

  /// Hairline stroke.
  static const hair = 1.0;

  // ── the design grid (1× PNG sizes, logical px) ──────────────────────────

  /// Small tile width (and a square small tile's height).
  static const tileW = 164.0;

  /// A tall small tile's height.
  static const tileTallH = 218.0;

  /// Medium and large tile width: two columns plus the gutter.
  static const tileWideW = 348.0;

  /// Large tile height.
  static const tileLargeH = 365.0;

  /// The gap between tiles (the grid's gutter).
  static const tileGap = 20.0;

  /// The design's inner padding: every tile's content starts 20 px in.
  static const tilePad = 20.0;

  /// Below this width the whole grid scales down uniformly (never reflows).
  static const gridMinWidth = 360.0;

  /// The side margin a scaled-down grid keeps.
  static const gridNarrowMargin = 6.0;
}

/// ── RADII ─────────────────────────────────────────────────────────────────
abstract final class R {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const card = 24.0;
  static const sheet = 28.0;
  static const pill = 999.0;

  static const rXs = BorderRadius.all(Radius.circular(xs));
  static const rSm = BorderRadius.all(Radius.circular(sm));
  static const rMd = BorderRadius.all(Radius.circular(md));
  static const rLg = BorderRadius.all(Radius.circular(lg));
  static const rCard = BorderRadius.all(Radius.circular(card));
  static const rSheet = BorderRadius.vertical(top: Radius.circular(sheet));
  static const rPill = BorderRadius.all(Radius.circular(pill));

  /// Small painter corner (bars, lane blocks).
  static const bar = Radius.circular(3);

  /// The tile corner: Figma corner smoothing, fitted to the PNGs' alpha
  /// (tool/figma/squircle.py: radius 24.1, smoothing 0.98; the same on all
  /// four tile sizes).
  static const tile = 24.1;
  static const tileSmoothing = .98;

  /// Inner panels (the sleep chart's plate, sub-tiles).
  static const panel = 16.0;
  static const rPanel = BorderRadius.all(Radius.circular(panel));
}
