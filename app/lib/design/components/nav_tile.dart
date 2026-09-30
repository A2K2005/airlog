// NavTile and NavTileGrid: the settings screens' bento.
//
// A NavTile is one idea in a small tile: an icon badge, a short title, then a
// status pill or a one-line caption. It comes in three forms:
//   * tappable (onTap)  a chevron in a badge circle, the Medium/5 "›";
//   * selected (selected != null)  a radio, for a two-way choice;
//   * static (neither)  a summary tile, no button role.
//
// NavTileGrid lays tiles out two to a row with equal heights, and one per row
// at large text or on a very narrow screen. It never scales its children
// (unlike BentoGrid): these are controls, and a control keeps its 48 dp.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'info_button.dart';
import 'pressable.dart';
import 'tile.dart';

class NavTile extends StatelessWidget {
  const NavTile({
    super.key,
    required this.icon,
    required this.title,
    this.accent,
    this.status,
    this.caption,
    this.onTap,
    this.selected,
    this.semanticLabel,
  });

  final IconData icon;
  final String title;
  final Color? accent;

  /// A status pill under the title.
  final Widget? status;

  /// One line under the title (wraps, never truncated).
  final String? caption;
  final VoidCallback? onTap;

  /// Non-null makes the tile one option of a choice (a radio).
  final bool? selected;

  /// The spoken summary; defaults to the title and caption.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final isOn = selected == true;
    final a = accent ?? C.neutral;
    final Widget corner = selected != null
        ? Icon(
            isOn
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 22,
            color: isOn ? p.ink : p.ink3,
          )
        : onTap != null
        ? Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: C.badge,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.chevron_right_rounded, size: 18, color: p.ink),
          )
        : const SizedBox.shrink();
    final body = AnimatedContainer(
      duration: motion(context, Motion.fast, fade: true),
      curve: Motion.enter,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(S.x4),
      decoration: ShapeDecoration(
        color: isOn ? Color.alphaBlend(p.wash(a), p.card) : p.card,
        shape: TileBorder(
          side: isOn ? BorderSide(color: p.ink, width: 2) : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: icon, accent: accent, size: 36),
              const Spacer(),
              corner,
            ],
          ),
          const SizedBox(height: S.x3),
          Text(title, style: F.tileTitle.copyWith(color: p.ink)),
          if (status != null) ...[
            const SizedBox(height: S.x1 + 2),
            status!,
          ],
          if (caption != null) ...[
            const SizedBox(height: S.x1),
            Text(caption!, style: F.cap.copyWith(color: p.ink2)),
          ],
        ],
      ),
    );
    final label = semanticLabel;
    if (onTap == null) {
      return Semantics(
        container: true,
        label: label,
        child: label == null ? body : ExcludeSemantics(child: body),
      );
    }
    final content = label == null ? body : ExcludeSemantics(child: body);
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      // Inside the press target, so the flag merges into its one node.
      child: selected == null
          ? content
          : Semantics(inMutuallyExclusiveGroup: true, child: content),
    );
  }
}

/// Tiles two to a row, each row as tall as its tallest tile; one per row
/// at large text or below [oneColumnBelow] wide. An odd last tile spans the
/// full width. Never scaled.
class NavTileGrid extends StatelessWidget {
  const NavTileGrid({
    super.key,
    required this.children,
    this.oneColumnBelow = 296,
  });

  final List<Widget> children;
  final double oneColumnBelow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final one = bigText(context) || c.maxWidth < oneColumnBelow;
      final rows = <Widget>[];
      if (one) {
        for (final w in children) {
          rows.add(w);
        }
      } else {
        for (var i = 0; i < children.length; i += 2) {
          if (i + 1 >= children.length) {
            rows.add(children[i]);
            continue;
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: children[i]),
                  const SizedBox(width: S.x3),
                  Expanded(child: children[i + 1]),
                ],
              ),
            ),
          );
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x3),
            rows[i],
          ],
        ],
      );
    },
  );
}
