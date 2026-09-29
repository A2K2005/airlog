// The bento grid and the flexible glow panel.
//
// BentoGrid lays tiles out on the design's grid: two 164 px columns and a
// 20 px gutter, 348 px wide, centred on the screen. Tiles never stretch. On
// a screen narrower than 360 dp the whole grid scales down uniformly (never
// reflows), so a tile always looks like its design.
//
// GlowPanel is the tile surface for content the design has no PNG for (the
// day's plan, notes, settings rows): the same squircle, the same painted
// glow, at whatever height its content needs.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'pressable.dart';
import 'tile.dart';

class BentoGrid extends StatelessWidget {
  const BentoGrid({
    super.key,
    required this.children,
    this.spacing = S.tileGap,
  });

  /// Tiles and panels in reading order. Small tiles pair up two to a row;
  /// medium and large tiles (and panels) take a row each.
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final grid = SizedBox(
        width: S.tileWideW,
        child: Wrap(spacing: spacing, runSpacing: spacing, children: children),
      );
      final w = c.maxWidth;
      if (!w.isFinite || w >= S.gridMinWidth) return Center(child: grid);
      // Narrow phone: scale the whole grid, keep a 6 px margin.
      return Center(
        child: SizedBox(
          width: w - 2 * S.gridNarrowMargin,
          child: FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            child: grid,
          ),
        ),
      );
    },
  );
}

/// A full-width (348 px) glow surface of any height.
class GlowPanel extends StatelessWidget {
  const GlowPanel({
    super.key,
    required this.child,
    this.glow = GlowRecipes.m8,
    this.padding = const EdgeInsets.all(S.tilePad),
    this.onTap,
    this.semanticLabel,
    this.width = S.tileWideW,
  });

  final Widget child;
  final GlowRecipe glow;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final body = SizedBox(
      width: width,
      child: CustomPaint(
        painter: GlowPainter(glow),
        child: Padding(
          padding: padding,
          child: DefaultTextStyle(
            style: F.tileBody.copyWith(
              color: TileInk.primary,
              decoration: TextDecoration.none,
            ),
            child: child,
          ),
        ),
      ),
    );
    if (onTap == null) {
      return semanticLabel == null
          ? body
          : Semantics(container: true, label: semanticLabel, child: body);
    }
    return Pressable(onTap: onTap, semanticLabel: semanticLabel, child: body);
  }
}
