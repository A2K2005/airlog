// A tick (or radio) row on Pressable: the consent confirmations and the
// model list. A full-width 48 dp target whose screen-reader node says
// "checked" / "not checked".

import 'package:flutter/material.dart';

import '../../../design/design.dart';

class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.value,
    required this.title,
    required this.onChanged,
    this.subtitle,
    this.trailing,
    this.radio = false,
  });

  final bool value;
  final String title;
  final String? subtitle;

  /// Right-aligned text (a model's cost).
  final String? trailing;

  /// A radio (one of many) instead of a tick box.
  final bool radio;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final icon = radio
        ? (value
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded)
        : (value
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded);
    return Pressable(
      onTap: () => onChanged(!value),
      scale: .985,
      child: Semantics(
        checked: radio ? null : value,
        selected: radio ? value : null,
        inMutuallyExclusiveGroup: radio,
        label: [title, ?subtitle, ?trailing].join('. '),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: S.card,
              vertical: S.x3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: value ? p.ink : p.ink3),
                const SizedBox(width: S.x3),
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
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: S.x3),
                  Text(
                    trailing!,
                    style: F
                        .tab(F.bodySm)
                        .copyWith(color: p.ink2, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
