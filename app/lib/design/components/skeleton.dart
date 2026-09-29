// Loading placeholders. STATIC on purpose: a shimmer is an infinite loop,
// which the reduced-motion gate cannot stop and which never lets a test
// settle. Loading is short; a calm block is enough.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = R.rSm,
  }) : circle = false;

  const SkeletonBox.circle({super.key, required double size})
    : width = size,
      height = size,
      radius = R.rPill,
      circle = true;

  final double? width;
  final double height;
  final BorderRadius radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: p.skeleton,
          borderRadius: circle ? null : radius,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
        ),
      ),
    );
  }
}

/// A block of skeleton lines that announces itself once as "Loading".
class SkeletonLines extends StatelessWidget {
  const SkeletonLines({super.key, this.lines = 3, this.label = 'Loading'});
  final int lines;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines; i++) ...[
            if (i > 0) const SizedBox(height: S.x2 + 2),
            FractionallySizedBox(
              widthFactor: i == lines - 1 && lines > 1 ? .6 : 1,
              child: const SkeletonBox(height: 12),
            ),
          ],
        ],
      ),
    );
  }
}
