// Settings tiles: the grouped-rows surface of the settings screens, in the
// tile language (docs/DESIGN_SYSTEM.md).
//
//   * SettingsTile       one tile: an optional header (icon badge, title,
//                        status pill, ⓘ) over rows or blocks. Flat card, or a
//                        glow panel for the one hero tile of a screen.
//   * SettingsRow        icon badge, title, optional pill, a wrapping
//                        subtitle; a chevron when it navigates.
//   * SettingsSwitchRow  a row whose whole 48 dp height toggles a switch.
//   * SettingsValueRow   a read-only "label · value" line (versions).
//   * SettingsBlock      any other content, inset to the tile's edges.
//   * MetricChip         a small non-interactive chip naming a measurement
//                        ("HRV 14/14", "+ Blood oxygen").
//
// Components never read providers; every string is a parameter.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'bento.dart';
import 'info_button.dart';
import 'pressable.dart';
import 'surfaces.dart';

/// The icon badge size inside settings tiles and rows.
const double _badge = 32;

/// Where row text starts: the card padding, the badge and its gap.
const double _textInset = S.card + _badge + S.x3;

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.children,
    this.title,
    this.icon,
    this.accent,
    this.status,
    this.info,
    this.glow,
    this.dividers = true,
    this.semanticLabel,
  });

  final List<Widget> children;

  /// The header title; no header without it.
  final String? title;
  final IconData? icon;
  final Color? accent;

  /// A status pill after the title.
  final Widget? status;

  /// Usually an [InfoButton], at the header's trailing edge.
  final Widget? info;

  /// Paints the tile as a glow panel (the screen's hero tile).
  final GlowRecipe? glow;

  /// Hairlines between rows; false leaves space instead.
  final bool dividers;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final head = title == null
        ? null
        : Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              S.card,
              S.x3,
              info == null ? S.card : S.x1,
              S.x1,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  IconBadge(icon: icon!, accent: accent, size: _badge),
                  const SizedBox(width: S.x3),
                ],
                Expanded(
                  child: Wrap(
                    spacing: S.x2,
                    runSpacing: S.x1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title!,
                          style: F.head.copyWith(color: p.ink),
                        ),
                      ),
                      ?status,
                    ],
                  ),
                ),
                ?info,
              ],
            ),
          );
    final rows = <Widget>[
      ?head,
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0)
          dividers
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: _textInset,
                  ),
                  child: Divider(height: 1, thickness: S.hair, color: p.line),
                )
              : const SizedBox(height: S.x1),
        children[i],
      ],
    ];
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
    const pad = EdgeInsets.symmetric(vertical: S.x1);
    final Widget tile = glow == null
        ? AppCard(padding: pad, child: column)
        : GlowPanel(
            glow: glow!,
            width: double.infinity,
            padding: pad,
            child: column,
          );
    return semanticLabel == null
        ? tile
        : Semantics(container: true, label: semanticLabel, child: tile);
  }
}

/// Content inside a [SettingsTile] that is not a row: inset to the tile's
/// edges (and, with [indent], to the rows' text).
class SettingsBlock extends StatelessWidget {
  const SettingsBlock({
    super.key,
    required this.child,
    this.indent = false,
    this.top = S.x2,
    this.bottom = S.x3,
  });

  final Widget child;

  /// Line up with the rows' text instead of the tile edge.
  final bool indent;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(
      indent ? _textInset : S.card,
      top,
      S.card,
      bottom,
    ),
    child: child,
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.pill,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    this.accent,
  });

  final IconData icon;
  final String title;

  /// Wraps; never truncated.
  final String? subtitle;

  /// A status pill after the title.
  final Widget? pill;

  /// Replaces the chevron (a button, an ⓘ, a value).
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.card, vertical: S.x3),
      child: Row(
        children: [
          IconBadge(icon: icon, accent: accent, size: _badge),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: S.x2,
                  runSpacing: S.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title, style: F.head.copyWith(color: p.ink)),
                    ?pill,
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: S.x2),
            trailing!,
          ] else if (onTap != null)
            Icon(Icons.chevron_right_rounded, size: 20, color: p.ink3),
        ],
      ),
    );
    if (onTap == null) {
      return semanticLabel == null
          ? row
          : Semantics(container: true, label: semanticLabel, child: row);
    }
    return Pressable(
      onTap: onTap,
      scale: .985,
      semanticLabel: semanticLabel,
      child: row,
    );
  }
}

/// A row whose whole height toggles [value]. Spoken as one switch.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    this.onChanged,
    this.icon,
    this.subtitle,
    this.pill,
    this.accent,
  });

  final String title;
  final bool value;

  /// Null disables the row (the pill says why).
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? subtitle;
  final Widget? pill;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final change = onChanged;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.card, vertical: S.x2),
      child: Row(
        children: [
          if (icon != null) ...[
            IconBadge(icon: icon!, accent: accent, size: _badge),
            const SizedBox(width: S.x3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: S.x2,
                  runSpacing: S.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: (icon == null ? F.bodySm : F.head).copyWith(
                        color: p.ink,
                        fontWeight: icon == null ? FontWeight.w600 : null,
                      ),
                    ),
                    ?pill,
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: S.x2),
          ExcludeSemantics(
            child: Switch(
              value: value,
              onChanged: change,
            ),
          ),
        ],
      ),
    );
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        enabled: change != null,
        label: title,
        child: Pressable(
          onTap: change == null ? null : () => change(!value),
          scale: .985,
          child: ExcludeSemantics(child: row),
        ),
      ),
    );
  }
}

/// A non-interactive "label · value" row (versions).
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({super.key, required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Semantics(
      label: '$title $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: S.card,
            vertical: S.x3 + 2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: F.bodySm.copyWith(color: p.ink2)),
              ),
              const SizedBox(width: S.x3),
              Text(
                value,
                textAlign: TextAlign.end,
                style: F
                    .tab(F.bodySm)
                    .copyWith(color: p.ink, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum MetricChipStyle {
  /// This app is used for the measurement (a check, tinted).
  used,

  /// Available but not used (outlined).
  available,

  /// Something a source adds (its own icon, tinted).
  add,

  /// Something that takes points off (a minus, amber).
  penalty,

  /// Not there yet (quiet text).
  muted,
}

/// A small chip naming a measurement, with an optional [count] ("14/14").
/// Not a control: no press, no 48 dp target.
class MetricChip extends StatelessWidget {
  const MetricChip({
    super.key,
    required this.label,
    this.icon,
    this.count,
    this.style = MetricChipStyle.available,
  });

  final String label;
  final IconData? icon;
  final String? count;
  final MetricChipStyle style;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final (Color bg, Color ink, Color? border, IconData? glyph) =
        switch (style) {
          MetricChipStyle.used => (
            p.wash(C.health),
            p.on(C.health),
            null,
            Icons.check_rounded,
          ),
          MetricChipStyle.available => (p.card2, p.ink, p.line, icon),
          MetricChipStyle.add => (
            p.wash(C.lavender),
            p.on(C.lavender),
            null,
            icon ?? Icons.add_rounded,
          ),
          MetricChipStyle.penalty => (
            p.wash(C.amber),
            p.on(C.amber),
            null,
            Icons.remove_rounded,
          ),
          MetricChipStyle.muted => (p.card2, p.ink3, null, icon),
        };
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: R.rPill,
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            Icon(glyph, size: 15, color: ink),
            const SizedBox(width: S.x1 + 2),
          ],
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: label),
                  if (count != null)
                    TextSpan(
                      text: ' $count',
                      style: F.tab(F.cap).copyWith(
                        color: style == MetricChipStyle.muted ? p.ink3 : p.ink2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              style: F.cap.copyWith(color: ink, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
