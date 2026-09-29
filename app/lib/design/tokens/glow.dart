// Glow backgrounds: the tile's deep core with colour bleeding in from its
// edges. Each background is a base fill plus a few soft ellipses composited
// source-over, sampled from the design PNGs by tool/figma/bgfit.py (a
// least-squares fit of exactly this model to the exported pixels, text and
// marks masked out). The recipes themselves are generated into
// glow_recipes.dart; this file is the model and its maths.
//
// Why a model instead of a bitmap: the PNGs must not ship, and a recipe is a
// handful of numbers that paint in one pass. Why not blur: a Gaussian-blurred
// ellipse has a closed-form edge (erfc), so each blob is a plain radial
// gradient with precomputed stops. Nothing is blurred per frame; the tile
// paints its background once inside a RepaintBoundary.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// One soft ellipse. Coverage at elliptical distance d (1 = on the rim):
/// `alpha · ½·erfc((d − 1) / (√2·softness))`.
class GlowBlob {
  const GlowBlob({
    required this.center,
    required this.radii,
    required this.softness,
    required this.alpha,
    required this.color,
    this.rotation = 0,
  });

  /// In tile pixels, from the tile's top-left.
  final Offset center;

  /// Semi-axes before [rotation], in tile pixels.
  final Size radii;

  /// Edge softness in units of the radius (the blur's σ / radius).
  final double softness;

  /// Peak opacity at the centre, 0…1.
  final double alpha;

  /// Opaque pigment; [alpha] carries the transparency.
  final Color color;

  /// Radians, clockwise.
  final double rotation;

  /// Distance at which the coverage is below 1/1000 of [alpha].
  double get reach => 1 + 3.3 * softness;

  static const _stops = 24;

  /// Gradient stops for this blob's radial profile, over d ∈ [0, reach].
  (List<Color>, List<double>) profile() {
    final colors = <Color>[];
    final stops = <double>[];
    for (var i = 0; i <= _stops; i++) {
      final t = i / _stops;
      final d = t * reach;
      final a = i == _stops
          ? 0.0
          : alpha * .5 * erfc((d - 1) / (math.sqrt2 * softness));
      colors.add(color.withValues(alpha: a.clamp(0.0, 1.0)));
      stops.add(t);
    }
    return (colors, stops);
  }
}

/// A tile background: [base] under [blobs], painted in order, drawn at the
/// design size [size] (tiles never stretch; see TileSize).
class GlowRecipe {
  const GlowRecipe({
    required this.size,
    required this.base,
    required this.blobs,
    this.dim = 0,
  });

  final Size size;
  final Color base;
  final List<GlowBlob> blobs;

  /// Readability correction for the few reference glows too bright for text.
  final double dim;

  /// Paints the recipe into [canvas], scaled from [size] to [target] (1:1 in
  /// the app; the scale exists only for previews).
  void paint(Canvas canvas, Size target) {
    canvas.save();
    if (target != size) {
      canvas.scale(target.width / size.width, target.height / size.height);
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    for (final b in blobs) {
      final (colors, stops) = _profiles[b] ??= b.profile();
      canvas.save();
      canvas.translate(b.center.dx, b.center.dy);
      canvas.rotate(b.rotation);
      canvas.scale(b.radii.width, b.radii.height);
      final r = b.reach;
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()..shader = ui.Gradient.radial(Offset.zero, r, colors, stops),
      );
      canvas.restore();
    }
    if (dim > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF000000).withValues(alpha: dim),
      );
    }
    canvas.restore();
  }

  static final _profiles = Expando<(List<Color>, List<double>)>();
}

/// Complementary error function (Abramowitz & Stegun 7.1.26, |ε| < 1.5e-7):
/// the edge of a Gaussian-blurred disc.
double erfc(double x) {
  final z = x.abs();
  final t = 1 / (1 + .3275911 * z);
  final y =
      t *
      (.254829592 +
          t *
              (-.284496736 +
                  t * (1.421413741 + t * (-1.453152027 + t * 1.061405429)))) *
      math.exp(-z * z);
  return x >= 0 ? y : 2 - y;
}
