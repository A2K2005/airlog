// ScoreRing — a score as a hero number inside one flat arc.
//
// States are drawn differently on purpose, so "measured", "provisional",
// "calibrating", "loading" and "no data" can never be mistaken for each other:
//   measured     solid arc in the accent
//   provisional  beaded arc in the accent + "Provisional" (baseline 5–13 nights)
//   calibrating  beaded NEUTRAL arc filled to calibration progress, no score
//   loading      bare track, skeleton number
//   noData       bare track, "No data" — never a guessed number
//
// Motion: the fill sweeps (700 ms, strong ease-out) at most ONCE per
// [playKey] per app process; after that a value change morphs from the
// current arc (ease-in-out, retargetable) and the number crossfades. Screens
// that want "once per day across restarts" persist the played flag themselves
// and pass `playKey: null` when it is already set.

import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/painters.dart';
import '../tokens/tokens.dart';
import 'motion_widgets.dart';
import 'pressable.dart';
import 'skeleton.dart';

enum RingState { measured, provisional, calibrating, loading, noData }

class ScoreRing extends StatefulWidget {
  const ScoreRing({
    super.key,
    required this.label,
    required this.color,
    this.value,
    this.max = 100,
    this.state = RingState.measured,
    this.valueText,
    this.unit,
    this.caption,
    this.progress,
    this.size = 148,
    this.playKey,
    this.onTap,
    this.semanticsLabel,
    this.reserveCaption = false,
  });

  /// "Recovery", "Strain", "Sleep" (shown in uppercase under the ring).
  final String label;

  /// Pigment for the arc (e.g. `DomainColors.recovery(score)`).
  final Color color;

  /// The score, 0…[max]. Ignored for calibrating / loading / noData.
  final double? value;
  final double max;
  final RingState state;

  /// Display override for the number ("12.4"); default: rounded [value].
  final String? valueText;

  /// Small suffix after the number ("%").
  final String? unit;

  /// Line under the label. Defaults per state ("Provisional", "No data" …).
  final String? caption;

  /// Calibration progress 0…1 for [RingState.calibrating].
  final double? progress;
  final double size;

  /// Sweep once per key per process (e.g. 'recovery:2026-09-28').
  /// Null = no sweep, the ring is simply drawn.
  final String? playKey;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  /// Keep one caption line of height even with no caption (a skeleton bar
  /// while loading), so a row of rings is the same height loading and
  /// loaded: data arriving never pushes the cards below.
  final bool reserveCaption;

  static final _played = <String>{};

  /// Forget which keys have played (gallery "replay", tests).
  static void resetPlayed() => _played.clear();

  @override
  State<ScoreRing> createState() => _ScoreRingState();
}

class _ScoreRingState extends State<ScoreRing> {
  bool _sweeping = false;

  /// Bumped to restart the tween from a chosen begin value (a sweep from 0,
  /// or a snap straight to the value) instead of morphing from the current.
  int _epoch = 0;

  static bool _hasArc(RingState s) =>
      s != RingState.loading && s != RingState.noData;

  /// Claims the sweep for [ScoreRing.playKey] if it has not played yet.
  bool _claimSweep() {
    final k = widget.playKey;
    if (k == null || ScoreRing._played.contains(k)) return false;
    ScoreRing._played.add(k);
    return true;
  }

  @override
  void initState() {
    super.initState();
    if (_hasArc(widget.state)) _sweeping = _claimSweep();
  }

  @override
  void didUpdateWidget(ScoreRing old) {
    super.didUpdateWidget(old);
    // The real sequence on a screen is loading → measured in the SAME slot.
    // That first arrival of a value is the "first view": sweep once if the
    // key has not played, otherwise draw the value at once — never the
    // 0 → value morph a plain tween would do.
    if (!_hasArc(old.state) && _hasArc(widget.state)) {
      _sweeping = _claimSweep();
      _epoch++;
    }
  }

  double get _frac {
    switch (widget.state) {
      case RingState.measured:
      case RingState.provisional:
        final v = widget.value;
        if (v == null || !v.isFinite || widget.max <= 0) return 0;
        return (v / widget.max).clamp(0.0, 1.0);
      case RingState.calibrating:
        final pr = widget.progress;
        return pr == null || !pr.isFinite ? 0 : pr.clamp(0.0, 1.0);
      case RingState.loading:
      case RingState.noData:
        return 0;
    }
  }

  String? get _number {
    if (widget.state != RingState.measured &&
        widget.state != RingState.provisional) {
      return null;
    }
    if (widget.valueText != null) return widget.valueText;
    final v = widget.value;
    return v == null || !v.isFinite ? null : v.round().toString();
  }

  String get _caption {
    if (widget.caption != null) return widget.caption!;
    return switch (widget.state) {
      RingState.measured => '',
      RingState.provisional => 'Early estimate',
      RingState.calibrating => 'Learning',
      RingState.loading => '',
      RingState.noData => '',
    };
  }

  String get _spoken {
    if (widget.semanticsLabel != null) return widget.semanticsLabel!;
    final n = _number;
    final unit = widget.unit == '%' ? ' percent' : (widget.unit ?? '');
    return switch (widget.state) {
      RingState.measured => '${widget.label} $n$unit',
      RingState.provisional => '${widget.label} $n$unit, early estimate',
      RingState.calibrating =>
        '${widget.label} learning${_caption.isEmpty || _caption == 'Learning' ? '' : ', $_caption'}',
      RingState.loading => '${widget.label} loading',
      RingState.noData => '${widget.label}: no data',
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final size = widget.size;
    final stroke = max(6.0, size * .068);
    final beaded =
        widget.state == RingState.provisional ||
        widget.state == RingState.calibrating;
    final arcInk = widget.state == RingState.calibrating
        ? p.ink3
        : p.mark(widget.color);
    final target = _frac;
    // Under reduced motion there is no sweep at all: the ring is drawn.
    final sweeping = _sweeping && Motion.enabled(context);
    final dur = sweeping ? Motion.sweep : Motion.slow;
    final curve = sweeping ? Motion.enter : Motion.move;

    final ring = TweenAnimationBuilder<double>(
      key: ValueKey(_epoch),
      tween: Tween(begin: sweeping ? 0 : target, end: target),
      duration: motion(context, dur),
      curve: curve,
      // No setState: the flag only picks the duration of LATER changes, and
      // with a zero duration this fires synchronously during build.
      onEnd: () => _sweeping = false,
      builder: (context, v, _) => CustomPaint(
        size: Size.square(size),
        painter: beaded
            ? DashedRing(
                v,
                arcInk,
                p.track,
                stroke: stroke,
                segments: size >= 120 ? 28 : 20,
              )
            : Ring(v, arcInk, p.track, stroke: stroke),
      ),
    );

    final inner = size - stroke * 2 - size * .16;
    final numStyle =
        (size >= 132
                ? F.n64
                : size >= 96
                ? F.n44
                : F.n32)
            .copyWith(color: p.ink);
    final n = _number;
    Widget centre;
    if (widget.state == RingState.loading) {
      centre = SkeletonBox(width: inner * .5, height: inner * .28);
    } else if (n != null) {
      centre = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          NumberSwap(n, style: numStyle),
          if (widget.unit != null)
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Text(
                widget.unit!,
                style: F.scaled(numStyle, .36).copyWith(color: p.ink2),
              ),
            ),
        ],
      );
    } else if (widget.state == RingState.calibrating) {
      centre = Icon(
        Icons.hourglass_top_rounded,
        size: size * .2,
        color: p.ink3,
      );
    } else {
      centre = Text(
        'No data',
        style: F.bodySm.copyWith(color: p.ink3, fontWeight: FontWeight.w700),
      );
    }

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ring,
              SizedBox(
                width: inner,
                height: inner * .62,
                child: FittedBox(fit: BoxFit.scaleDown, child: centre),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        SizedBox(
          width: size,
          child: Text(
            widget.label.toUpperCase(),
            textAlign: TextAlign.center,
            style: F.over.copyWith(color: p.ink2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_caption.isNotEmpty) ...[
          const SizedBox(height: 3),
          SizedBox(
            width: size,
            child: Text(
              _caption,
              textAlign: TextAlign.center,
              style: F.tab(F.cap).copyWith(color: p.ink3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else if (widget.reserveCaption) ...[
          const SizedBox(height: 3),
          SizedBox(
            width: size,
            // One line of caption height (text-scale aware), with a quiet
            // bar in it while loading.
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Text('\u00A0', style: F.cap),
                if (widget.state == RingState.loading)
                  SkeletonBox(width: size * .42, height: 9),
              ],
            ),
          ),
        ],
      ],
    );

    final labelled = Semantics(
      container: true,
      label: _spoken,
      child: ExcludeSemantics(child: body),
    );
    if (widget.onTap == null) return labelled;
    return Pressable(onTap: widget.onTap, semanticLabel: null, child: labelled);
  }
}
