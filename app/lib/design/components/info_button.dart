// The ⓘ and the icon badge, the two pieces every tile header shares.
//
//   * InfoButton  a 48 dp ⓘ that opens an explain sheet. Long explanations
//                 live in the sheet, never as paragraphs on a screen.
//   * IconBadge   an icon in a tinted circle (tile and row heads).
//
// Moved here from app/screen_kit.dart (which re-exports them, so older
// imports keep compiling). Neither reads a provider.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'explain_sheet.dart';
import 'surfaces.dart';

/// An icon in a tinted circle. Neutral (card2 and ink2) without an accent.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.accent,
    this.size = 36,
  });

  final IconData icon;
  final Color? accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final a = accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: a == null ? p.card2 : p.wash(a),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * .5, color: a == null ? p.ink2 : p.on(a)),
    );
  }
}

/// The ⓘ: a 48 dp target that opens an explain sheet with [title], [lede]
/// and [children]. Spoken as "About {title}" unless [semanticLabel] is set.
class InfoButton extends StatelessWidget {
  const InfoButton({
    super.key,
    required this.title,
    this.lede,
    this.children = const [],
    this.semanticLabel,
    this.footnote,
    this.color,
  });

  final String title;
  final String? lede;
  final List<Widget> children;
  final String? semanticLabel;

  /// The sheet's closing line; none by default. Score sheets pass
  /// [ExplainSheet.defaultFootnote].
  final String? footnote;

  /// Icon ink; `ink2` by default. On a glow pass `TileInk.unit`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppIconButton(
      icon: Icons.info_outline_rounded,
      size: 20,
      color: color ?? p.ink2,
      semanticLabel: semanticLabel ?? 'About $title',
      onTap: () => showExplainSheet<void>(
        context,
        title: title,
        lede: lede,
        footnote: footnote,
        children: children,
      ),
    );
  }
}
