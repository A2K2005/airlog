// Screen and section headers.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'surfaces.dart';

/// The large title at the top of a tab ("Today") with trailing actions
/// (e.g. the settings gear) and an optional line under it.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.below,
  });

  final String title;
  final String? subtitle;

  /// Usually AppIconButtons (48 dp targets).
  final List<Widget> actions;

  /// A widget under the title row (e.g. a DaySwitcher or FreshnessLine).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x3, S.x2, S.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: F.display.copyWith(color: p.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ...actions,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(right: S.x3),
              child: Text(
                subtitle!,
                style: F.tab(F.bodySm).copyWith(color: p.ink2),
              ),
            ),
          if (below != null)
            Padding(
              padding: const EdgeInsets.only(top: S.x2, right: S.x3),
              child: below!,
            ),
        ],
      ),
    );
  }
}

/// A section title inside a screen, with an optional quiet action
/// ("How it's calculated") or a trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: F.t2.copyWith(color: p.ink)),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: F.cap.copyWith(color: p.ink3)),
                ),
            ],
          ),
        ),
        if (trailing != null)
          trailing!
        else if (actionLabel != null && onAction != null)
          AppButton(
            label: actionLabel!,
            onTap: onAction,
            kind: AppButtonKind.quiet,
            compact: true,
          ),
      ],
    );
  }
}
