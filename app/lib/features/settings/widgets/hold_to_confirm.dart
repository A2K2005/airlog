// Hold-to-confirm (Emil Kowalski's hold-to-delete), built on Pressable's
// press-down / press-up / press-cancel: press and hold, and a fill sweeps
// across the button over a slow, deliberate 2 s (linear: it is a timer, and
// linear reads as one); let go early and it snaps back in 200 ms on the
// strong ease-out. Slow where the user decides, fast where the system
// answers. Pressable supplies the 0.97 press scale and the 48 dp floor.
//
// Only a completed hold calls [onConfirmed]. A short tap explains what to do.
// With a screen reader on, holding a finger still is not how people press,
// so a tap (double-tap) calls [onAccessibleConfirm] instead: a confirm
// dialog, never an instant delete.
//
// The 2-second hold deliberately does NOT go through motion(), and the
// controller uses AnimationBehavior.preserve: under reduced motion either
// would collapse the hold to a fraction of a second and make the delete
// nearly instant. Only the release snap is gated (it stays a short fade).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/design.dart';

class HoldToConfirm extends StatefulWidget {
  const HoldToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    required this.onAccessibleConfirm,
    this.color = C.recRed,
    this.icon = Icons.delete_outline_rounded,
    this.hint = 'Keep holding to confirm',
    this.enabled = true,
  });

  final String label;

  /// A full hold completed.
  final VoidCallback onConfirmed;

  /// A screen-reader activation: open a confirm dialog.
  final VoidCallback onAccessibleConfirm;

  /// Pigment of the fill.
  final Color color;
  final IconData icon;

  /// Shown after a tap that was too short.
  final String hint;
  final bool enabled;

  /// How long the finger has to stay down.
  static final hold = Motion.tick * 2;

  /// The snap back after an early release.
  static const release = Motion.base;

  @override
  State<HoldToConfirm> createState() => _HoldToConfirmState();
}

class _HoldToConfirmState extends State<HoldToConfirm>
    with SingleTickerProviderStateMixin {
  // `preserve`: with Android's "Remove animations" on, a normal controller
  // runs at 5 % speed-up, which would turn the 2-second hold into 0.1 s.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: HoldToConfirm.hold,
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _holding = false;
  bool _firedThisPress = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && _holding && !_firedThisPress) {
        _firedThisPress = true;
        unawaited(HapticFeedback.heavyImpact());
        widget.onConfirmed();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _screenReader =>
      MediaQuery.maybeAccessibleNavigationOf(context) ?? false;

  void _down() {
    if (_screenReader) return;
    _holding = true;
    _firedThisPress = false;
    // Linear, from wherever an interrupted release left the fill.
    _c.forward(from: _c.value);
  }

  /// Early release: snap back. After a completed hold the fill also empties
  /// on release, so the button is ready again once the action is done.
  void _up() {
    _holding = false;
    if (_c.isDismissed) return;
    _c.animateBack(
      0,
      duration: motion(context, HoldToConfirm.release, fade: true),
      curve: Motion.enter,
    );
  }

  void _tap() {
    if (_screenReader) {
      widget.onAccessibleConfirm();
      return;
    }
    if (_firedThisPress) {
      _firedThisPress = false;
      return;
    }
    snack(context, widget.hint);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final ink = p.on(widget.color);
    final fill = p.fill(widget.color);
    final onFill = p.onFill(widget.color);
    Widget face(Color bg, Color fg) => Container(
      constraints: const BoxConstraints(minHeight: S.tap),
      padding: const EdgeInsets.symmetric(horizontal: S.x5),
      decoration: BoxDecoration(color: bg, borderRadius: R.rPill),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 18, color: fg),
          const SizedBox(width: S.x2),
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.head.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    final base = face(Color.alphaBlend(p.wash(widget.color), p.card), ink);
    final filled = face(fill, onFill);
    final on = widget.enabled;
    return Pressable(
      haptic: PressHaptic.none,
      semanticLabel: '${widget.label}. Press and hold for two seconds.',
      onTap: on ? _tap : null,
      onPressDown: on ? _down : null,
      onPressUp: on ? _up : null,
      onPressCancel: on ? _up : null,
      child: ExcludeSemantics(
        child: SizedBox(
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Stack(
              children: [
                on ? base : face(p.card2, p.ink3),
                Positioned.fill(
                  child: ClipRect(clipper: _Reveal(_c.value), child: filled),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// clip-path: inset(0 (1 − t) 0 0): the fill grows from the leading edge.
class _Reveal extends CustomClipper<Rect> {
  const _Reveal(this.t);
  final double t;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * t, size.height);

  @override
  bool shouldReclip(covariant _Reveal old) => old.t != t;
}
