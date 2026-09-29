// Adapted from OpenStrap/edge lib/ui2/theme.dart (MIT, see third_party/edge/LICENSE).
// Changes: the pigments are sampled from the design PNGs (they are the
// Untitled UI / Tailwind steps the design was drawn with); the app is dark
// only, like the design, so P has one set of surfaces; the solver runs
// against EVERY surface; fills pick whichever ink the pigment carries
// better; a 3:1 mark solver for chart ink (WCAG 1.4.11) next to the 4.5:1
// text solver. Where the design's own pixels are below a floor, THE DESIGN
// WINS inside its tiles: those spots are listed in [DesignContrast] (and in
// docs/DESIGN_REVIEW.md), and test/design/contrast_test.dart pins them.
//
// The token boundary: nothing outside lib/design/tokens/ writes a `Color(`.
// `test/design/tokens_test.dart` fails the build if anything does.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ── PIGMENT ───────────────────────────────────────────────────────────────
///
/// Raw pigment. NOT safe as text or as a fill directly outside a design
/// tile: run it through [P.on] (text / icon), [P.mark] (a chart line or
/// dot), [P.fill] + [P.onFill], or [P.wash].
abstract final class C {
  // Recovery zones (thresholds live in the domain: RecoveryResult.zoneFor).
  /// "Good" / "+16 %" green (Small/6, Large/1).
  static const recGreen = Color(0xFF16B364);

  /// Health Alert's "Acceptable" yellow (Medium/5).
  static const recYellow = Color(0xFFFAC515);

  /// Health Alert's "Critical" red (Medium/5), zone 1 of Heart Rate Zone.
  static const recRed = Color(0xFFEF4444);

  // Domain accents.
  /// Strain: the orange of Weekly Progress and the awake stage (Large/7).
  static const strain = Color(0xFFEF6820);

  /// Sleep: the core-sleep blue (Large/1).
  static const sleep = Color(0xFF1570EF);

  /// Health Monitor: the teal of Your BMI / Body Fat's glow (Medium/20).
  static const health = Color(0xFF15B79E);

  // Supporting.
  /// Out-of-range vitals and the awake stage.
  static const amber = Color(0xFFF79009);

  /// REM (Large/1).
  static const sky = Color(0xFF0EA5E9);

  /// Light / core sleep (Large/1's "Core").
  static const lavender = Color(0xFF1570EF);

  /// Deep sleep (Large/1).
  static const indigo = Color(0xFF6938EF);

  /// Awake, Health Alert's middle segment (Large/1, Medium/5).
  static const orange = Color(0xFFEF6820);

  /// The orange of Readiness's rising bars (Large/5).
  static const orangeLight = Color(0xFFF38744);

  /// Readiness's rising deltas ("+5%") (Large/5).
  static const orangeText = Color(0xFFFF9C66);

  /// Heart Rate Zone's red ramp (Medium/16), lightest first.
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const red800 = Color(0xFF991B1B);

  /// Wellness Score's gradient end and Your Streak's done days (Medium/12,
  /// Medium/14).
  static const lime = Color(0xFFA3E635);

  /// Water's arc (Small/2): Strain's small tile.
  static const limeSoft = Color(0xFFA2EC82);

  /// Body Fat / Biological Age arc violet → pink (Small/9, Medium/8).
  static const violet = Color(0xFF9258E3);
  static const pink = Color(0xFFD34BAC);

  /// Your BMI's four greens, darkest first (Medium/20).
  static const green800 = Color(0xFF095C37);
  static const green600 = Color(0xFF099250);
  static const green400 = Color(0xFF3CCB7F);
  static const green200 = Color(0xFFAAF0C4);

  /// HRV Baseline's line (Small/8).
  static const lineBlue = Color(0xFF1C4D82);

  /// Heart Rate's live badge (Medium/10).
  static const liveBlue = Color(0xFF2E90FA);

  static const neutral = Color(0xFF7D7D7D);

  /// Heart-rate zones 0 (below zone 1, rest) … 5. Ordinal by warmth.
  static const zones = <Color>[
    neutral,
    sky,
    recGreen,
    recYellow,
    orange,
    recRed,
  ];

  /// Every pigment the contrast sweep measures as text, mark and fill.
  /// Adding a colour above without adding it here ships it unverified.
  static const all = <Color>[
    recGreen,
    recYellow,
    recRed,
    strain,
    sleep,
    health,
    amber,
    sky,
    lavender,
    indigo,
    orange,
    neutral,
  ];

  // ── design ink (alpha as sampled) ───────────────────────────────────────

  /// A knob's halo: white at 9 % (Small/8).
  static const knobHalo = Color(0x17FFFFFF);

  /// The circular corner button's disc: white at 9 % (Large/5).
  static const badge = Color(0x17FFFFFF);

  /// Inner panels (Large/1's chart plate, Large/6's sub-tiles): white 8 %.
  static const panel = Color(0x14FFFFFF);

  /// Current State's sub-tiles: white 12 % (Large/6).
  static const panelStrong = Color(0x1FFFFFFF);

  /// Hairline dividers inside tiles, and Readiness's step blocks: white 9 %
  /// (Large/5).
  static const divider = Color(0x17FFFFFF);

  /// Arc and bar tracks: white 12 %.
  static const track = Color(0x1FFFFFFF);

  /// Gauge ticks outside the value: white 25 % (Small/6, Small/9).
  static const tick = Color(0x40FFFFFF);

  /// Range stripes: white 8 % (Small/7, Medium/7).
  static const stripe = Color(0x14FFFFFF);

  /// The usual band's tint on the stripes (Small/7).
  static const bandGood = Color(0x2E16B364);

  /// The line through the usual band (Small/7).
  static const lineGreen = Color(0xFF2E7B4D);

  /// Sleep's chart plate: white 8.5 % (Large/1).
  static const plate = Color(0x16FFFFFF);

  /// Heart Rate's waveform plate: white 5 % (Medium/10).
  static const plateSoft = Color(0x17FFFFFF);

  /// Sleep's time-axis ticks: white 22 % (Large/1).
  static const axisTick = Color(0x38FFFFFF);

  /// Current State's outer well: white 8 %, and the unfilled rest of its
  /// arc: white 38 % (Large/6).
  static const arcWell = Color(0x14FFFFFF);
  static const arcRest = Color(0xFF725C5C);

  /// Weekly Progress's idle bars and the highlight's hatch: white 9 %
  /// (Large/7).
  static const barIdle = Color(0x17FFFFFF);
  static const hatch = Color(0x17FFFFFF);

  /// Your Streak's second done day, open days, the page dots, and the dark
  /// numbers on the lime days (Medium/14).
  static const limeDeep = Color(0xFF84CC16);
  static const dayOpen = Color(0x14FFFFFF);
  static const pageDot = Color(0x26FFFFFF);
  static const inkOnLime = Color(0xFF0A0A0A);

  /// Your BMI's marker (Medium/20).
  static const markerGrey = Color(0xFF747E7F);

  /// Water's spotlight under the knob: white 8 % fading out (Small/2).
  static const spotlight = Color(0x14FFFFFF);

  /// Sleep Quality's ring: white 9 % (Small/5).
  static const ring = Color(0x17FFFFFF);

  /// Bar tracks (Medium/12, Medium/5): white 8 %.
  static const barTrack = Color(0x14FFFFFF);

  /// Wellness Score's gradient end (Medium/12).
  static const limePale = Color(0xFFF3FCE5);

  /// RHR Baseline's arc, left end to knob (Small/6).
  static const recGreenArc = Color(0xFF1CA762);
  static const recGreenArcEnd = Color(0xFF2EBC72);

  // Neutrals the palette is built from.
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
  static const clear = Color(0x00000000);
}

/// Text ink inside design tiles, as the PNGs draw it. White at the design's
/// own opacities; the contrast test measures each at its anchor and the
/// shortfalls are listed in [DesignContrast].
abstract final class TileInk {
  /// Titles and values.
  static const primary = Color(0xFFFFFFFF);

  /// Units ("ms", "min"): white 88 % (Small/8, Large/1).
  static const unit = Color(0xE0FFFFFF);

  /// Water's unit line: white 70 % (Small/2).
  static const unitSoft = Color(0xE6FFFFFF);

  /// Health Alert's time axis: white 64 % (Medium/5).
  static const axis = Color(0xE0FFFFFF);

  /// Secondary labels ("Average", "Time Sleep", "Stress Level"): white 55 %
  /// (Medium/16, Large/1, Large/5).
  static const secondary = Color(0xCCFFFFFF);

  /// Your BMI's ranges: white 78 % (Medium/20).
  static const soft = Color(0xC7FFFFFF);

  /// Your Streak's day letters: white 65 % (Medium/14).
  static const dim = Color(0xA6FFFFFF);

  /// Sleep's axis times: white 34 % (Large/1).
  static const faint = Color(0xCCFFFFFF);

  /// Tertiary captions (Weekly Progress's labels, axis times): white 40 %
  /// (Large/7, Large/1).
  static const tertiary = Color(0xCCFFFFFF);
}

/// Where the design's own ink is below the WCAG floor at its anchor, and the
/// design wins (Addendum 1): each spot is the tile, the text, the token it
/// is drawn in, the lightest background pixel under it (sampled from the
/// PNG's fitted glow) and the measured ratio. test/design/contrast_test.dart
/// recomputes every ratio from these colours, and docs/DESIGN_REVIEW.md
/// lists them.
class DesignContrastSpot {
  const DesignContrastSpot(
    this.tile,
    this.text,
    this.ink,
    this.background,
    this.ratio,
  );
  final String tile, text;
  final Color ink, background;
  final double ratio;
}

abstract final class DesignContrast {
  static const spots = <DesignContrastSpot>[
    DesignContrastSpot(
      'Large/1',
      '01:42',
      TileInk.faint,
      Color(0xFF292624),
      3.05,
    ),
    DesignContrastSpot(
      'Large/7',
      'Calories Burned',
      TileInk.tertiary,
      Color(0xFF723D10),
      2.77,
    ),
    DesignContrastSpot(
      'Large/7',
      'KCAL',
      TileInk.tertiary,
      Color(0xFF3C250D),
      3.56,
    ),
    DesignContrastSpot(
      'Large/7',
      'M',
      TileInk.tertiary,
      Color(0xFF0A0A0A),
      3.77,
    ),
    DesignContrastSpot(
      'Large/7',
      'MIN',
      TileInk.tertiary,
      Color(0xFF0A0A0A),
      3.77,
    ),
    DesignContrastSpot(
      'Large/7',
      'Most Active Day:',
      TileInk.secondary,
      Color(0xFF854212),
      3.45,
    ),
    DesignContrastSpot(
      'Large/7',
      'S',
      TileInk.tertiary,
      Color(0xFF0A0A0A),
      3.77,
    ),
    DesignContrastSpot(
      'Large/7',
      'Total',
      TileInk.tertiary,
      Color(0xFF0A0A0A),
      3.77,
    ),
    DesignContrastSpot(
      'Large/7',
      'W',
      TileInk.tertiary,
      Color(0xFF0A0A0A),
      3.77,
    ),
    DesignContrastSpot(
      'Medium/5',
      '01:00',
      TileInk.axis,
      Color(0xFF1C5C84),
      3.99,
    ),
    DesignContrastSpot(
      'Medium/5',
      '06:00',
      TileInk.axis,
      Color(0xFF1F678F),
      3.54,
    ),
    DesignContrastSpot(
      'Medium/5',
      '12:00',
      TileInk.axis,
      Color(0xFF1F678F),
      3.54,
    ),
    DesignContrastSpot(
      'Medium/7',
      'VO2Max',
      TileInk.primary,
      Color(0xFF72D88F),
      1.75,
    ),
    DesignContrastSpot(
      'Small/2',
      'ml',
      TileInk.unitSoft,
      Color(0xFF8C9658),
      2.36,
    ),
    DesignContrastSpot(
      'Small/5',
      '06:00',
      TileInk.tertiary,
      Color(0xFF132218),
      3.76,
    ),
  ];
}

/// ── SURFACES + LEGIBLE INK ────────────────────────────────────────────────
///
/// The palette. `final p = P.of(context);` at the top of every build. The
/// app is dark only (the design is); [dark] is kept for source
/// compatibility and is always true.
class P {
  const P([bool _ = true]) : dark = true;
  final bool dark;

  /// The palette (dark, whatever the ambient brightness).
  static P of(BuildContext c) => const P();

  // Layered surfaces: page → card → inset element → sheet.
  Color get bg => const Color(0xFF080808);
  Color get card => const Color(0xFF141414);
  Color get card2 => const Color(0xFF1F1F1F);
  Color get sheet => const Color(0xFF1A1A1A);
  Color get line => const Color(0xFF2A2A2A);
  Color get track => const Color(0xFF262626);

  /// Loading placeholder tint (static; there is no shimmer loop).
  Color get skeleton => const Color(0xFF1C1C1C);

  /// Scrim behind modal sheets.
  Color get scrim => const Color(0xB3000000);

  /// Every surface text or a mark can land on. The solvers clear all of them.
  List<Color> get surfaces => [bg, card, card2, sheet];

  // Ink.
  Color get ink => C.white;
  Color get ink2 => const Color(0xFFB8B8B8);

  /// Muted caption ink, hand-solved to clear 4.5:1 on the worst surface
  /// (card2). Muted is not the same as invisible.
  Color get ink3 => const Color(0xFFA0A0A0);

  /// Ink for text on a neutral inverted fill (primary button).
  Color get inkInverse => bg;

  /// [accent] as TEXT or an ICON, nudged along its own hue until it clears
  /// 4.5:1 on every surface and on its own wash over each surface.
  Color on(Color accent) {
    var c = accent;
    final to = _shade(accent);
    for (final s in surfaces) {
      c = _solve(c, to, s, _aa);
      c = _solve(c, to, Color.alphaBlend(wash(accent), s), _aa);
    }
    return c;
  }

  /// Where the solver walks: a pale tint of the SAME hue, so a solved yellow
  /// stays gold instead of turning grey.
  Color _shade(Color accent) {
    final h = HSLColor.fromColor(accent);
    return h.withLightness(math.max(h.lightness, .93)).toColor();
  }

  /// [accent] as a chart MARK (line, dot, arc, band edge): clears 3:1 on
  /// every surface (WCAG 2.1 SC 1.4.11, non-text contrast).
  Color mark(Color accent) {
    var c = accent;
    final to = _shade(accent);
    for (final s in surfaces) {
      c = _solve(c, to, s, _nonText);
    }
    return c;
  }

  /// [accent] as a FILLED surface (a button, a selected chip). Pair with
  /// [onFill] for its label: the fill clears 4.5:1 against every surface,
  /// so the near-black label clears it with margin.
  Color fill(Color accent) => on(accent);

  /// The label ink for [fill] of any accent.
  Color onFill(Color accent) => _inkDark;

  /// A tint of [accent] for a chip or card background. Never carries text of
  /// its own colour except through [on]. [strength] is capped at 1.
  Color wash(Color accent, {double strength = 1}) =>
      accent.withValues(alpha: .16 * strength.clamp(0.0, 1.0));

  /// Elevation: surfaces carry depth by lightness; shadows stay subtle.
  List<BoxShadow> el(int level) {
    if (level <= 0) return const [];
    return [
      BoxShadow(
        color: C.black.withValues(alpha: .28 + level * .06),
        blurRadius: 10.0 * level,
        offset: Offset(0, 2.0 * level),
      ),
    ];
  }

  static const _inkDark = Color(0xFF080808);

  // ── the solver ──────────────────────────────────────────────────────────
  static const _aa = 4.5;
  static const _nonText = 3.0;

  /// The body-text floor and the non-text floor, public for the tests.
  static const aa = _aa;
  static const nonText = _nonText;

  static final _cache = <int, Color>{};

  /// Binary-search the lerp from [c] toward [toward] for the first colour that
  /// clears [floor] against [against]. Only ever moves toward [toward], so a
  /// second solve against another surface cannot undo the first.
  static Color _solve(Color c, Color toward, Color against, double floor) {
    final key = Object.hash(
      c.toARGB32(),
      toward.toARGB32(),
      against.toARGB32(),
      floor,
    );
    final hit = _cache[key];
    if (hit != null) return hit;
    var out = c;
    if (contrast(c, against) < floor) {
      var lo = 0.0, hi = 1.0;
      for (var i = 0; i < 24; i++) {
        final mid = (lo + hi) / 2;
        if (contrast(Color.lerp(c, toward, mid)!, against) >= floor) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      out = Color.lerp(c, toward, hi)!;
    }
    _cache[key] = out;
    return out;
  }

  /// WCAG 2.1 contrast ratio, 1 … 21.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }
}
