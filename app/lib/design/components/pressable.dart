// Adapted from OpenStrap/edge lib/ui2/grammar.dart — Pressable (MIT, see
// third_party/edge/LICENSE). Changes: controller-driven press so a quick tap
// inside a scroll view still shows the full press (Edge's AnimatedScale missed
// taps whose down and up land in one frame); release faster than press;
// optional light haptic; reduced motion swaps the scale for an opacity dip;
// 48 dp floor (Android) instead of 44 pt; long-press support; press-down /
// press-up / press-cancel callbacks for press-and-hold controls (the
// hold-to-delete button is built on them).
//
// THE gesture primitive of the design system: anything tappable is built on
// it, so every target gets the 48 dp floor, the press feedback and a button
// role for screen readers.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/tokens.dart';

enum PressHaptic { none, selection, light }

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onPressDown,
    this.onPressUp,
    this.onPressCancel,
    this.semanticLabel,
    this.haptic = PressHaptic.selection,
    this.scale = .97,
    this.minSize = S.tap,
    this.selected,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The finger went down (after the platform's tap-down delay, so a scroll
  /// that starts on the target never fires it). Always followed by exactly
  /// one of [onPressUp] or [onPressCancel].
  final VoidCallback? onPressDown;

  /// The finger lifted on the target (then [onTap] runs).
  final VoidCallback? onPressUp;

  /// The press ended without a tap: the finger slid off, a scroll took over,
  /// or the widget went away.
  final VoidCallback? onPressCancel;

  /// Required for anything whose child is not plain text (icon-only).
  final String? semanticLabel;
  final PressHaptic haptic;

  /// Pressed scale (0.95–0.98). 0.97 by default.
  final double scale;

  /// Hit-area floor on both axes; the visual can be smaller.
  final double minSize;

  /// For toggles/segments: exposes selected state to screen readers.
  final bool? selected;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.press,
    reverseDuration: Motion.release,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Motion.enter,
    reverseCurve: Motion.enter.flipped,
  );

  bool get _enabled =>
      widget.onTap != null ||
      widget.onLongPress != null ||
      widget.onPressDown != null ||
      widget.onPressUp != null ||
      widget.onPressCancel != null;

  bool _down = false;

  @override
  void dispose() {
    if (_down) widget.onPressCancel?.call();
    _c.dispose();
    super.dispose();
  }

  void _syncDurations() {
    _c.duration = motion(context, Motion.press, fade: true);
    _c.reverseDuration = motion(context, Motion.release, fade: true);
  }

  void _pressDown(TapDownDetails _) {
    _syncDurations();
    _c.forward();
    _down = true;
    widget.onPressDown?.call();
  }

  void _pressUp(TapUpDetails _) {
    _release();
    if (!_down) return;
    _down = false;
    widget.onPressUp?.call();
  }

  void _pressCancel() {
    _c.reverse();
    if (!_down) return;
    _down = false;
    widget.onPressCancel?.call();
  }

  /// A quick tap can deliver down and up together: finish the press, then
  /// release, so the feedback is always seen.
  void _release() {
    if (_c.status == AnimationStatus.forward) {
      _c.forward().whenCompleteOrCancel(() {
        if (mounted) _c.reverse();
      });
    } else {
      _c.reverse();
    }
  }

  void _tap() {
    if (widget.onTap == null) return;
    switch (widget.haptic) {
      case PressHaptic.none:
        break;
      case PressHaptic.selection:
        unawaited(HapticFeedback.selectionClick());
      case PressHaptic.light:
        unawaited(HapticFeedback.lightImpact());
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final sized = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: widget.minSize,
        minHeight: widget.minSize,
      ),
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1,
        heightFactor: 1,
        child: widget.child,
      ),
    );
    if (!_enabled) {
      return Semantics(
        label: widget.semanticLabel,
        selected: widget.selected,
        child: sized,
      );
    }
    final moving = Motion.enabled(context);
    final Widget feedback = moving
        ? ScaleTransition(
            scale: Tween<double>(begin: 1, end: widget.scale).animate(_t),
            child: sized,
          )
        : FadeTransition(
            opacity: Tween<double>(begin: 1, end: .72).animate(_t),
            child: sized,
          );
    // One node per target: a child's own label (a ring's or a tile's spoken
    // summary) becomes the button's label instead of a separate, unlabelled
    // button wrapped around a labelled container.
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        selected: widget.selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // A tap handler is always registered while enabled: the tap
          // recognizer is what reports down / up / cancel.
          onTap: _tap,
          onLongPress: widget.onLongPress,
          onTapDown: _pressDown,
          onTapUp: _pressUp,
          onTapCancel: _pressCancel,
          child: feedback,
        ),
      ),
    );
  }
}
