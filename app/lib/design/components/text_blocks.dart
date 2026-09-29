// Small text building blocks shared by many screens: an over-label above a
// group, a label/value line, a bullet line, and a one-at-a-time snack bar.
// None of these read a provider; they take plain values.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

/// Replaces any visible snack bar with [message] (feedback never queues
/// behind a stale hint).
void snack(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(content: Text(message)),
    snackBarAnimationStyle: snackMotion(context),
  );
}

/// An uppercase over-label ("DATA", "ABOUT") above a group.
class OverLabel extends StatelessWidget {
  const OverLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Semantics(
      header: true,
      child: Text(text.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
    );
  }
}

/// A label / value pair on one line; the value in tabular figures.
class KeyValueLine extends StatelessWidget {
  const KeyValueLine(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: F.bodySm.copyWith(color: p.ink2)),
          ),
          const SizedBox(width: S.x3),
          Flexible(
            flex: 2,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: F
                    .tab(F.bodySm)
                    .copyWith(
                      color: valueColor ?? p.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bullet line (dot or icon + text), for short lists inside cards and
/// sheets, with an optional bold lead-in.
class BulletLine extends StatelessWidget {
  const BulletLine(
    this.text, {
    super.key,
    this.icon,
    this.strong,
    this.large = false,
  });
  final String text;
  final IconData? icon;

  /// Optional bold lead-in ("Heart rate.").
  final String? strong;

  /// Body size instead of small body (long-form pages: the privacy policy).
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final style = large ? F.body : F.bodySm;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: p.ink),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 2, right: 2),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: p.ink3,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (strong != null)
                    TextSpan(
                      text: '$strong ',
                      style: style.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  TextSpan(
                    text: text,
                    style: style.copyWith(color: p.ink2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
