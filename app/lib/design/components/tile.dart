// The tile: the one surface of the app. A fixed-size squircle (Figma corner
// smoothing, sampled from the design PNGs' alpha: R.tile, R.tileSmoothing)
// on a painted glow background, with its content placed by baseline at the
// design's own coordinates.
//
// Tiles never stretch or reflow. Their four sizes are the design's 1× sizes
// (TileSize); a BentoGrid centres them, and scales the whole grid uniformly
// on a phone narrower than the design. Text inside a tile is pinned to the
// design scale (see TileScope) because a fixed layout cannot grow; every
// tile's full content is also its spoken label, and the detail screen it
// opens scales normally.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'pressable.dart';

/// The design's tile sizes, in logical pixels.
enum TileSize {
  /// 164 × 164.
  small(Size(S.tileW, S.tileW)),

  /// 164 × 218.
  tall(Size(S.tileW, S.tileTallH)),

  /// 348 × 164.
  medium(Size(S.tileWideW, S.tileW)),

  /// 348 × 365.
  large(Size(S.tileWideW, S.tileLargeH));

  const TileSize(this.size);
  final Size size;
}

/// The tile outline: a rectangle whose corners follow Figma's corner
/// smoothing (a squircle), radius [radius], smoothing [smoothing] 0…1.
///
/// Ported from figma-squircle (github.com/phamfoo/figma-squircle,
/// src/draw.ts and src/distribute.ts; MIT, see the Licences page). Changes:
/// Dart Path calls instead of an SVG string; one radius for all corners.
Path tilePath(
  Rect r, {
  double radius = R.tile,
  double smoothing = R.tileSmoothing,
}) {
  final budget = math.min(r.width, r.height) / 2;
  final rad = math.min(radius, budget);
  if (rad <= 0) return Path()..addRect(r);
  var s = smoothing;
  var p = (1 + s) * rad;
  final maxS = budget / rad - 1;
  s = math.min(s, maxS);
  p = math.min(p, budget);
  double deg(double d) => d * math.pi / 180;
  final arcMeasure = 90 * (1 - s);
  final arcLen = math.sin(deg(arcMeasure / 2)) * rad * math.sqrt2;
  final alpha = (90 - arcMeasure) / 2;
  final p3ToP4 = rad * math.tan(deg(alpha / 2));
  final beta = 45 * s;
  final c = p3ToP4 * math.cos(deg(beta));
  final d = c * math.tan(deg(beta));
  final b = (p - arcLen - c - d) / 3;
  final a = 2 * b;
  final arc = Radius.circular(rad);
  final w = r.width, h = r.height;
  return Path()
    ..moveTo(r.left + w - p, r.top)
    // top right
    ..relativeCubicTo(a, 0, a + b, 0, a + b + c, d)
    ..relativeArcToPoint(Offset(arcLen, arcLen), radius: arc)
    ..relativeCubicTo(d, c, d, b + c, d, a + b + c)
    ..lineTo(r.left + w, r.top + h - p)
    // bottom right
    ..relativeCubicTo(0, a, 0, a + b, -d, a + b + c)
    ..relativeArcToPoint(Offset(-arcLen, arcLen), radius: arc)
    ..relativeCubicTo(-c, d, -(b + c), d, -(a + b + c), d)
    ..lineTo(r.left + p, r.top + h)
    // bottom left
    ..relativeCubicTo(-a, 0, -(a + b), 0, -(a + b + c), -d)
    ..relativeArcToPoint(Offset(-arcLen, -arcLen), radius: arc)
    ..relativeCubicTo(-d, -c, -d, -(b + c), -d, -(a + b + c))
    ..lineTo(r.left, r.top + p)
    // top left
    ..relativeCubicTo(0, -a, 0, -(a + b), d, -(a + b + c))
    ..relativeArcToPoint(Offset(arcLen, -arcLen), radius: arc)
    ..relativeCubicTo(c, -d, b + c, -d, a + b + c, -d)
    ..close();
}

/// [tilePath] as a ShapeBorder (clips, decorations, Material shapes).
class TileBorder extends ShapeBorder {
  const TileBorder({this.radius = R.tile, this.smoothing = R.tileSmoothing});
  final double radius;
  final double smoothing;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      tilePath(rect, radius: radius, smoothing: smoothing);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) =>
      TileBorder(radius: radius * t, smoothing: smoothing);

  @override
  bool operator ==(Object other) =>
      other is TileBorder &&
      other.radius == radius &&
      other.smoothing == smoothing;

  @override
  int get hashCode => Object.hash(radius, smoothing);
}

/// Paints a [GlowRecipe] clipped to the tile outline. Painted once: the tile
/// wraps it in a RepaintBoundary and it never repaints unless the recipe
/// changes.
class GlowPainter extends CustomPainter {
  const GlowPainter(this.glow, {this.radius = R.tile});
  final GlowRecipe glow;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipPath(tilePath(Offset.zero & size, radius: radius));
    glow.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlowPainter old) =>
      old.glow != glow || old.radius != radius;
}

/// A tile's loading shape: the tile outline at its size, in the skeleton
/// tint (static; no shimmer).
class TileSkeleton extends StatelessWidget {
  const TileSkeleton({super.key, required this.size, this.height});
  final TileSize size;

  /// Overrides the height (a flexible panel's placeholder).
  final double? height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: SizedBox(
      width: size.size.width,
      height: height ?? size.size.height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: P.of(context).skeleton,
          shape: const TileBorder(),
        ),
      ),
    ),
  );
}

/// Pins text inside a tile to the design scale: the layout is fixed, so it
/// cannot grow. The tile's spoken label carries the full content, and the
/// screen a tile opens scales with the user's setting.
class TileScope extends StatelessWidget {
  const TileScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
    child: DefaultTextStyle(
      style: F.tileBody.copyWith(
        color: P.of(context).ink,
        decoration: TextDecoration.none,
      ),
      child: child,
    ),
  );
}

/// A design tile: fixed [size], painted [glow], and [children] placed at
/// design coordinates (use [TileText] / Positioned). The whole tile is the
/// tap target when [onTap] is set.
class GlowTile extends StatelessWidget {
  const GlowTile({
    super.key,
    required this.size,
    required this.glow,
    required this.children,
    this.onTap,
    this.semanticLabel,
  });

  final TileSize size;
  final GlowRecipe glow;
  final List<Widget> children;
  final VoidCallback? onTap;

  /// The tile's spoken summary (its visible text, in reading order).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final body = SizedBox.fromSize(
      size: size.size,
      child: TileScope(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: GlowPainter(glow), isComplex: true),
              ),
            ),
            // Marks that run past the edge (arcs, tracks) are cut by the
            // tile's own outline, as in the design.
            Positioned.fill(
              child: RepaintBoundary(
                child: ClipPath(
                  clipper: const ShapeBorderClipper(shape: TileBorder()),
                  child: Stack(clipBehavior: Clip.none, children: children),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return Semantics(
        container: true,
        label: semanticLabel,
        child: ExcludeSemantics(excluding: semanticLabel != null, child: body),
      );
    }
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: ExcludeSemantics(excluding: semanticLabel != null, child: body),
    );
  }
}

/// Text placed like the design places it: the pen origin at [x] and the
/// alphabetic baseline at [baseline] (tile pixels). With [right] the text
/// ends at x = [right] instead; with [center] it is centred on the tile's
/// width (or on [center] when it is a number).
class TileText extends StatelessWidget {
  const TileText(
    this.text, {
    super.key,
    required this.baseline,
    required this.style,
    this.x,
    this.right,
    this.centerX,
    this.color,
    this.maxWidth,
  }) : assert(x != null || right != null || centerX != null);

  final String text;
  final double baseline;
  final TextStyle style;
  final double? x;

  /// Right edge (tile pixels from the left) for right-aligned text.
  final double? right;

  /// Centre line (tile pixels from the left) for centred text.
  final double? centerX;
  final Color? color;

  /// Ellipsis beyond this width (keeps a long real-data label inside its
  /// slot; the design's own strings fit).
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = Text(
      text,
      style: style.copyWith(color: color ?? style.color ?? P.of(context).ink),
      maxLines: 1,
      softWrap: false,
      overflow: maxWidth == null ? TextOverflow.visible : TextOverflow.ellipsis,
      textAlign: right != null
          ? TextAlign.right
          : (centerX != null ? TextAlign.center : TextAlign.left),
    );
    final child = Baseline(
      baseline: baseline,
      baselineType: TextBaseline.alphabetic,
      child: maxWidth == null
          ? t
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth!),
              child: t,
            ),
    );
    if (centerX != null) {
      const span = 2000.0;
      return Positioned(
        left: centerX! - span / 2,
        width: span,
        top: 0,
        child: Align(alignment: Alignment.topCenter, child: child),
      );
    }
    if (right != null) {
      return Positioned(
        right: null,
        left: right! - 2000,
        width: 2000,
        top: 0,
        child: Align(alignment: Alignment.topRight, child: child),
      );
    }
    return Positioned(left: x, top: 0, child: child);
  }
}
