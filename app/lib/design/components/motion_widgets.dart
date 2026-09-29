// Two motion primitives the components share.
//
//  * NumberSwap: a changing number crossfades through a slight blur, so two
//    values never read as two overlapping objects. Opacity + blur only, so it
//    survives reduced motion (as a fade).
//  * EnterFade: a one-time entrance (opacity + 8 px rise) with an optional
//    stagger slot (≤ 30 ms per item, capped). It never blocks interaction and
//    runs once per mount; under reduced motion it is opacity only. Use it for
//    rarely seen content (a sheet's sections, first load), never for things
//    seen tens of times a day.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

class NumberSwap extends StatelessWidget {
  const NumberSwap(
    this.text, {
    super.key,
    required this.style,
    this.textAlign,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motion(context, Motion.base, fade: true),
      reverseDuration: motion(context, Motion.fast, fade: true),
      switchInCurve: Motion.enter,
      // The outgoing child runs its curve backwards: flip it so the exit is
      // an ease-out too (fast to leave), not an ease-in.
      switchOutCurve: Motion.enter.flipped,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: AnimatedBuilder(
          animation: a,
          builder: (context, c) {
            final sigma = (1 - a.value) * 2.5;
            if (sigma < .05) return c!;
            return ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: c,
            );
          },
          child: child,
        ),
      ),
      child: Text(
        text,
        key: ValueKey(text),
        style: style,
        textAlign: textAlign,
        maxLines: 1,
        softWrap: false,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}

class EnterFade extends StatefulWidget {
  const EnterFade({
    super.key,
    required this.child,
    this.index = 0,
    this.enabled = true,
  });

  final Widget child;

  /// Stagger slot. Items past [Motion.staggerCap] enter with the cap.
  final int index;

  /// False renders [child] immediately (e.g. already seen today).
  final bool enabled;

  @override
  State<EnterFade> createState() => _EnterFadeState();
}

class _EnterFadeState extends State<EnterFade>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || !widget.enabled) return;
    final delay = Motion.stagger * widget.index.clamp(0, Motion.staggerCap);
    final body = motion(context, Motion.slow, fade: true);
    final total = delay + body;
    if (total == Duration.zero || body == Duration.zero) return;
    final c = AnimationController(vsync: this, duration: total);
    final start = delay.inMicroseconds / total.inMicroseconds;
    _t = CurvedAnimation(
      parent: c,
      curve: Interval(start, 1, curve: Motion.enter),
    );
    _c = c..forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    final moving = Motion.enabled(context);
    return FadeTransition(
      opacity: t,
      child: moving
          ? AnimatedBuilder(
              animation: t,
              builder: (context, c) => Transform.translate(
                offset: Offset(0, (1 - t.value) * 8),
                child: c,
              ),
              child: widget.child,
            )
          : widget.child,
    );
  }
}
