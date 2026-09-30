// Cards, buttons, pills — the surfaces every screen is built from.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'pressable.dart';
import 'tile.dart';

enum CardTone {
  /// The standard raised card.
  base,

  /// A recessed block inside a card (card2).
  inset,

  /// A tinted card carrying one accent (wash). Text on it uses `p.on(accent)`.
  tinted,
}

/// The card: the design's squircle tile surface; tappable when [onTap] is set
/// (press feedback via Pressable).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.card),
    this.onTap,
    this.tone = CardTone.base,
    this.accent,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final CardTone tone;

  /// Pigment for [CardTone.tinted].
  final Color? accent;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final bg = switch (tone) {
      CardTone.base => p.card,
      CardTone.inset => p.card2,
      CardTone.tinted => Color.alphaBlend(p.wash(accent ?? C.health), p.card),
    };
    // The tile surface: the design's squircle corner, no border (the design's
    // tiles carry depth by their own colour, not a rim).
    final box = DecoratedBox(
      decoration: ShapeDecoration(
        color: bg,
        shape: tone == CardTone.inset
            ? const TileBorder(radius: R.panel)
            : const TileBorder(),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) {
      return semanticLabel == null
          ? box
          : Semantics(container: true, label: semanticLabel, child: box);
    }
    return Pressable(onTap: onTap, semanticLabel: semanticLabel, child: box);
  }
}

enum AppButtonKind {
  /// Inverted ink fill (or the accent's fill when [AppButton.accent] is set).
  primary,

  /// Quiet filled (card2).
  secondary,

  /// Text only. No side padding: its label lines up with the content edge
  /// around it (the 48 dp hit height is kept).
  quiet,
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.kind = AppButtonKind.primary,
    this.icon,
    this.accent,
    this.expand = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final AppButtonKind kind;
  final IconData? icon;

  /// Pigment for an accent primary / quiet button.
  final Color? accent;

  /// Fill the available width.
  final bool expand;

  /// 36 px tall visual (the hit area stays 48 dp).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final disabled = onTap == null;
    final (Color bg, Color fg) = switch (kind) {
      AppButtonKind.primary =>
        accent == null
            ? (p.ink, p.inkInverse)
            : (p.fill(accent!), p.onFill(accent!)),
      AppButtonKind.secondary => (p.card2, p.ink),
      AppButtonKind.quiet => (C.clear, accent == null ? p.ink : p.on(accent!)),
    };
    final ink = disabled ? p.ink3 : fg;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: compact ? 16 : 18, color: ink),
          const SizedBox(width: S.x2),
        ],
        Flexible(
          child: Text(
            label,
            style: (compact ? F.bodySm : F.head).copyWith(
              color: ink,
              fontWeight: FontWeight.w700,
            ),
            maxLines: bigText(context) ? null : 2,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    final visual = Container(
      constraints: BoxConstraints(minHeight: compact ? 36 : S.tap),
      padding: EdgeInsets.symmetric(
        horizontal: kind == AppButtonKind.quiet ? 0 : (compact ? S.x4 : S.x5),
        vertical: S.x2,
      ),
      alignment: expand ? Alignment.center : null,
      decoration: BoxDecoration(
        color: disabled && kind != AppButtonKind.quiet ? p.card2 : bg,
        borderRadius: R.rPill,
      ),
      child: content,
    );
    return Pressable(
      onTap: onTap,
      semanticLabel: null,
      haptic: PressHaptic.light,
      child: expand ? SizedBox(width: double.infinity, child: visual) : visual,
    );
  }
}

/// An icon-only control with a 48 dp target. [semanticLabel] is required.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.filled = false,
    this.color,
    this.size = 22,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  /// Draw a card2 circle behind the icon.
  final bool filled;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final ink = onTap == null ? p.ink3 : (color ?? p.ink);
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: size + 18,
        height: size + 18,
        decoration: filled
            ? BoxDecoration(color: p.card2, shape: BoxShape.circle)
            : null,
        alignment: Alignment.center,
        child: Icon(icon, size: size, color: ink),
      ),
    );
  }
}

/// The status tones a pill can take. Each keeps its word: a pill never
/// carries meaning by colour alone.
enum PillTone {
  /// Connected, allowed, on.
  good(C.health),

  /// Off, not connected, not available.
  off(C.neutral),

  /// Beta features.
  beta(C.lavender),

  /// Needs the user: not installed, needs a fix, sample data.
  attention(C.amber),

  /// Locked until something else happens (a lock icon replaces the dot).
  locked(C.neutral);

  const PillTone(this.color);
  final Color color;
}

/// A small state chip: a dot and a word ("In range", "Provisional").
/// Never carries a number that changes.
class StatePill extends StatelessWidget {
  const StatePill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.tinted = true,
  });

  /// A status pill in one of the [PillTone]s ("Connected", "Off", "Beta").
  factory StatePill.tone(PillTone tone, String label, {Key? key}) =>
      StatePill(
        key: key,
        label: label,
        color: tone.color,
        icon: tone == PillTone.locked ? Icons.lock_outline_rounded : null,
      );

  final String label;

  /// Pigment; text is solved via `p.on`.
  final Color color;
  final IconData? icon;

  /// Tinted background (wash) vs plain.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final ink = p.on(color);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tinted ? S.x2 + 2 : 0,
        vertical: tinted ? 3 : 0,
      ),
      decoration: tinted
          ? BoxDecoration(color: p.wash(color), borderRadius: R.rPill)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 13, color: ink)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: p.mark(color),
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: S.x1 + 2),
          Flexible(
            child: Text(
              label,
              style: F.cap.copyWith(color: ink, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
