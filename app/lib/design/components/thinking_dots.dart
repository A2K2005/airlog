// ThinkingDots: three dots that fade in turn while an answer is on its way.
//
// The one looping animation in the app (DESIGN_SYSTEM.md, hard rules), and
// it is bounded: at most Motion.dotsCycles cycles (about 17 s), then the
// dots rest at a steady opacity. Each dot's fade is a Motion.dotStep
// (280 ms) ease-out up and another ease-out down; the dots are offset by
// half a step. Opacity only, nothing moves. Under reduced motion the dots
// are static from the start.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key, this.color, this.size = 6});

  /// Dot colour; ink2 by default.
  final Color? color;
  final double size;

  /// Opacity of a resting dot (reduced motion, or after the last cycle).
  static const rest = .6;

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  // One cycle: each dot rises in its own step and falls in the next, three
  // dots half a step apart, then a short rest: four steps in all.
  static const _steps = 4;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = Motion.enabled(context);
    if (!on) {
      _c?.dispose();
      _c = null;
      return;
    }
    if (_c != null) return;
    final c = AnimationController(vsync: this, duration: Motion.dotStep * _steps);
    _c = c;
    c.repeat(count: Motion.dotsCycles).whenCompleteOrCancel(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  /// Dot [i]'s opacity at cycle position [t] (0…1).
  static double _opacity(int i, double t) {
    final start = i * .5 / _steps;
    final up = 1 / _steps;
    final x = t - start;
    if (x < 0 || x > 2 * up) return .3;
    final phase = x <= up ? x / up : (x - up) / up;
    final eased = Motion.enter.transform(phase.clamp(0.0, 1.0));
    return x <= up ? .3 + .7 * eased : 1 - .7 * eased;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? P.of(context).ink2;
    final c = _c;
    Widget dots(double Function(int) opacity) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) SizedBox(width: widget.size * .66),
          Opacity(
            opacity: opacity(i),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ],
      ],
    );
    final resting = c == null || !c.isAnimating;
    return ExcludeSemantics(
      child: resting
          ? dots((_) => ThinkingDots.rest)
          : AnimatedBuilder(
              animation: c,
              builder: (context, _) => dots((i) => _opacity(i, c.value)),
            ),
    );
  }
}
