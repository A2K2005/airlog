// Three motion primitives the components share.
//
//  * NumberSwap: a changing number crossfades through a slight blur, so two
//    values never read as two overlapping objects. Opacity + blur only, so it
//    survives reduced motion (as a fade).
//  * EnterFade: a one-time entrance (opacity + 8 px rise) with an optional
//    stagger slot (30 ms per item by default, capped; [EnterFade.step]
//    widens it for a few large tiles). It never blocks interaction and
//    runs once per mount; under reduced motion it is opacity only. Use it for
//    rarely seen content (a sheet's sections, first load), never for things
//    seen tens of times a day.
//  * FadeSwap: a status that changes in place (a pill going from "Not
//    connected" to "Connected" when you come back from Health Connect)
//    crossfades in 160 ms on the strong ease-out, the outgoing one on the
//    flipped curve. Opacity only, so it stays (short) under reduced motion.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

class FadeSwap extends StatelessWidget {
  const FadeSwap({super.key, required this.swapKey, required this.child});

  /// A new key crossfades [child] in; the same key never animates.
  final Object swapKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = motion(context, Motion.fast, fade: true);
    return AnimatedSwitcher(
      duration: d,
      reverseDuration: d,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.enter.flipped,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey(swapKey), child: child),
    );
  }
}

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
            final sigma = Motion.enabled(context) ? (1 - a.value) * 2.5 : 0.0;
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
    this.step = Motion.stagger,
  });

  final Widget child;

  /// Stagger slot. Items past [Motion.staggerCap] enter with the cap.
  final int index;

  /// Delay per stagger slot: [Motion.stagger], or [Motion.staggerTiles] for
  /// a few large tiles.
  final Duration step;

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
    final delay = Motion.enabled(context)
        ? widget.step * widget.index.clamp(0, Motion.staggerCap)
        : Duration.zero;
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
