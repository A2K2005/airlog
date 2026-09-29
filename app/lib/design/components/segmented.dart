// SegmentedControl<T> and its 7/30/90-day form, SegmentedRange.
//
// The thumb slides between segments with the on-screen-move curve (it is
// already on screen, so ease-in-out, 200 ms) using a transform, not layout;
// under reduced motion it jumps. Selection gives a selection haptic.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'pressable.dart';

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.label,
    this.semanticsLabel,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) label;

  /// What the group controls ("Range").
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final n = values.length;
    if (n == 0) return const SizedBox.shrink();
    final index = values.indexOf(selected).clamp(0, n - 1);
    final thumbColor = p.dark ? p.sheet : p.card;
    // The pill is 40 px tall, but each segment's hit area is the full
    // 48 dp row it sits in.
    return Semantics(
      label: semanticsLabel,
      container: semanticsLabel != null,
      child: SizedBox(
        height: S.tap,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: (S.tap - _pill) / 2,
              height: _pill,
              child: Container(
                padding: const EdgeInsets.all(_inset),
                decoration: BoxDecoration(
                  color: p.card2,
                  borderRadius: R.rPill,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    heightFactor: 1,
                    child: AnimatedSlide(
                      offset: Offset(index.toDouble(), 0),
                      duration: motion(context, Motion.base),
                      curve: Motion.move,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: thumbColor,
                          borderRadius: R.rPill,
                          boxShadow: p.el(1),
                          border: p.dark ? Border.all(color: p.line) : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _inset),
                child: Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: Semantics(
                          inMutuallyExclusiveGroup: true,
                          child: Pressable(
                            selected: i == index,
                            onTap: i == index
                                ? () {}
                                : () => onChanged(values[i]),
                            child: SizedBox.expand(
                              child: Center(
                                child: Text(
                                  label(values[i]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: F
                                      .tab(F.bodySm)
                                      .copyWith(
                                        color: i == index ? p.ink : p.ink2,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _pill = 40.0, _inset = 3.0;
}

/// The trend-window toggle: 7 / 30 / 90 days.
class SegmentedRange extends StatelessWidget {
  const SegmentedRange({
    super.key,
    required this.days,
    required this.onChanged,
    this.options = const [7, 30, 90],
  });

  final int days;
  final ValueChanged<int> onChanged;
  final List<int> options;

  @override
  Widget build(BuildContext context) => SegmentedControl<int>(
    values: options,
    selected: days,
    onChanged: onChanged,
    label: (d) => '${d}D',
    semanticsLabel: 'Range in days',
  );
}
