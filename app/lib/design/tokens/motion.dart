// Adapted from OpenStrap/edge lib/ui2/theme.dart (MIT, see third_party/edge/LICENSE).
// Changes: named curves (strong ease-out for enter/exit, ease-in-out for
// on-screen moves, drawer curve for sheets; never ease-in); asymmetric
// enter/exit durations; the gate keeps OPACITY/COLOUR animations under reduced
// motion (`fade: true`) and drops only movement; our own page transition
// (fade + short rise, 280 ms / 200 ms) instead of the SDK's 450 ms default,
// which becomes a plain fade under reduced motion rather than a hard cut.

import 'package:flutter/material.dart';

/// ── MOTION ── one gate, no exceptions ─────────────────────────────────────
///
/// These are the only durations in the app. Everything reaches the screen
/// through [motion] so reduced motion is decided in one place.
abstract final class Motion {
  /// True when the platform is NOT asking for reduced motion.
  static bool enabled(BuildContext c) =>
      MediaQuery.maybeDisableAnimationsOf(c) != true;

  /// No animation at all (tab switches, things seen tens of times a day).
  static const none = Duration.zero;

  /// Press feedback: scale down.
  static const press = Duration(milliseconds: 120);

  /// Press release: faster than the press.
  static const release = Duration(milliseconds: 90);

  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 280);

  /// Exits are faster than enters.
  static const exit = Duration(milliseconds: 180);

  /// The score-ring fill sweep. The one deliberate "delight" duration, played
  /// at most once per ring per day (see ScoreRing.playKey).
  static const sweep = Duration(milliseconds: 700);

  /// Per-item stagger for list entrances (cap 40 ms).
  static const stagger = Duration(milliseconds: 30);

  /// Per-tile stagger for a few large tiles entering a rarely seen page
  /// (onboarding): wider than [stagger] so 3–4 big tiles read as a cascade.
  static const staggerTiles = Duration(milliseconds: 50);

  /// Most items a stagger ever delays; later items enter with the last one,
  /// so a long list never makes the user wait.
  static const staggerCap = 8;

  /// Wall clock for live screens (NOT an animation; not gated).
  static const tick = Duration(seconds: 1);

  // ── curves ──────────────────────────────────────────────────────────────

  /// Strong ease-out: anything entering or exiting.
  static const enter = Cubic(0.23, 1, 0.32, 1);

  /// Strong ease-in-out: something already on screen moving or morphing.
  static const move = Cubic(0.77, 0, 0.175, 1);

  /// iOS-like drawer curve: sheets and drawers.
  static const drawer = Cubic(0.32, 0.72, 0, 1);
}

/// THE gate. Returns [d], or zero when the user asked for reduced motion.
///
/// Pass `fade: true` for an animation that only changes opacity or colour: it
/// keeps a short duration under reduced motion, because a fade aids
/// comprehension and does not move anything.
Duration motion(BuildContext c, Duration d, {bool fade = false}) {
  if (Motion.enabled(c)) return d;
  if (!fade) return Duration.zero;
  return d > Motion.fast ? Motion.fast : d;
}

/// Draw-in progress: returns 1 (finished) instead of [t] under reduced motion,
/// so a chart that draws itself in still lands fully drawn.
double animate(BuildContext c, double t) => Motion.enabled(c) ? t : 1;

/// Animation style for `showModalBottomSheet` (which ignores page themes):
/// drawer curve, exit faster than enter, and a plain cut under reduced
/// motion (the sheet's only transition is a slide).
///
/// The reverse curve is the drawer curve FLIPPED: a curve runs backwards on
/// the way out, so without it the exit would be an ease-in (slow to leave,
/// the moment the user is watching).
AnimationStyle sheetMotion(BuildContext c) => Motion.enabled(c)
    ? AnimationStyle(
        curve: Motion.drawer,
        reverseCurve: Motion.drawer.flipped,
        duration: Motion.slow,
        reverseDuration: Motion.exit,
      )
    : AnimationStyle.noAnimation;

/// Animation style for `showDialog`: a centred fade (modals are not anchored
/// to a trigger, so they do not scale from one), strong ease-out both ways.
/// A fade, so it stays (shortened) under reduced motion.
AnimationStyle dialogMotion(BuildContext c) => AnimationStyle(
  curve: Motion.enter,
  reverseCurve: Motion.enter.flipped,
  duration: motion(c, Motion.fast, fade: true),
);

/// Animation style for `ScaffoldMessenger.showSnackBar`: in 200 ms, out in
/// 160 ms; no animation under reduced motion (a snack bar slides).
AnimationStyle snackMotion(BuildContext c) => Motion.enabled(c)
    ? const AnimationStyle(duration: Motion.base, reverseDuration: Motion.fast)
    : AnimationStyle.noAnimation;

/// True once the user's text scale is past where one-line card headers fit.
bool bigText(BuildContext c) => MediaQuery.textScalerOf(c).scale(1) > 1.3;

/// Page transitions for every platform: the incoming page fades in and rises
/// 3 % of its height on the strong ease-out; the outgoing page dims slightly.
/// Under reduced motion it is an opacity-only crossfade.
class AirlogPageTransitions extends PageTransitionsBuilder {
  const AirlogPageTransitions();

  @override
  Duration get transitionDuration => Motion.slow;

  @override
  Duration get reverseTransitionDuration => Motion.exit;

  static final _rise = Tween<Offset>(
    begin: const Offset(0, .03),
    end: Offset.zero,
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Motion.enter,
      reverseCurve: Motion.enter.flipped,
    );
    if (!Motion.enabled(context)) {
      return FadeTransition(opacity: curved, child: child);
    }
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: _rise.animate(curved),
        child: FadeTransition(
          opacity: Tween<double>(
            begin: 1,
            end: .92,
          ).animate(CurvedAnimation(parent: secondary, curve: Motion.enter)),
          child: child,
        ),
      ),
    );
  }
}
