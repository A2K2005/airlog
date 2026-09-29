// Grouped rows for Settings: a card holding tappable rows split by hairlines.

import 'package:flutter/material.dart';

import '../../../design/design.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: S.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: S.card + 34),
                child: Divider(height: 1, thickness: S.hair, color: p.line),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.card, vertical: S.x3),
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.ink2),
          const SizedBox(width: S.x4 - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: F.head.copyWith(color: p.ink)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: F.cap.copyWith(color: p.ink3),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            Icon(Icons.chevron_right_rounded, size: 20, color: p.ink3),
        ],
      ),
    );
    if (onTap == null) return row;
    return Pressable(onTap: onTap, scale: .985, child: row);
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
              Text(
                value,
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
