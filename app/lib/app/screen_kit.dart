// Small building blocks the rebuilt text screens share (docs/UI_REVAMP.md):
//
//   * Disclosure  a details expander: a 48 dp header (icon, title, one-line
//                 lede, chevron) over a body that opens with AnimatedSize.
//                 Ease-out both ways (an implicit animation always runs
//                 forward), ≤ 200 ms, zero under reduced motion. The header
//                 reports expanded / collapsed to screen readers.
//   * IconBadge, InfoButton  now live in design/components/info_button.dart;
//                 re-exported here so older imports keep compiling.
//
// Shared kit for features/: imports no feature, reads no provider.

import 'package:flutter/material.dart';

import '../design/components/info_button.dart';
import '../design/design.dart';

export '../design/components/info_button.dart' show IconBadge, InfoButton;

class Disclosure extends StatefulWidget {
  const Disclosure({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.accent,
    this.open,
    this.onChanged,
    this.initiallyOpen = false,
    this.headerPadding = const EdgeInsets.symmetric(
      horizontal: S.card,
      vertical: S.x3,
    ),
    this.bodyPadding = const EdgeInsets.fromLTRB(S.card, 0, S.card, S.card),
    this.dense = false,
  });

  final String title;

  /// One line under the title, always visible.
  final String? subtitle;
  final IconData? icon;

  /// Tints the icon badge; neutral when null.
  final Color? accent;

  /// Controlled mode: the parent owns the state (a contents list that opens
  /// a section). Null = the widget keeps its own.
  final bool? open;
  final ValueChanged<bool>? onChanged;
  final bool initiallyOpen;
  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry bodyPadding;

  /// A quiet one-line toggle ("Show the details") instead of a heading.
  final bool dense;

  /// The body, built only while open.
  final Widget child;

  @override
  State<Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<Disclosure> {
  late bool _open = widget.initiallyOpen;

  bool get _isOpen => widget.open ?? _open;

  void _toggle() {
    final next = !_isOpen;
    if (widget.open == null) setState(() => _open = next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final open = _isOpen;
    final d = motion(context, Motion.base);
    final chevron = AnimatedRotation(
      turns: open ? .5 : 0,
      duration: d,
      curve: Motion.enter,
      child: Icon(Icons.expand_more_rounded, size: 22, color: p.ink3),
    );
    final Widget header;
    if (widget.dense) {
      header = Padding(
        padding: widget.headerPadding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: F.bodySm.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            chevron,
          ],
        ),
      );
    } else {
      header = Padding(
        padding: widget.headerPadding,
        child: Row(
          children: [
            if (widget.icon != null) ...[
              IconBadge(icon: widget.icon!, accent: widget.accent),
              const SizedBox(width: S.x3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: F.head.copyWith(color: p.ink)),
                  if (widget.subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        widget.subtitle!,
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: S.x2),
            chevron,
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: _toggle,
          scale: .985,
          child: Semantics(
            expanded: open,
            hint: open ? 'Collapse' : 'Expand',
            child: header,
          ),
        ),
        AnimatedSize(
          duration: d,
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(padding: widget.bodyPadding, child: widget.child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
