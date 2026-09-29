// StatusCard — the honesty card. The ONLY way to render a missing or
// uncertain score: what is missing (title), why (body), what fixes it (fix +
// optional action). A screen may only state a cause the data gave it: build
// it from the engine's StatusNote whenever one exists.
//
// Ported in spirit from OpenStrap/edge lib/ui2/grammar.dart StatusCard (MIT,
// see third_party/edge/LICENSE); rewritten for StatusNote and Material icons.

import 'package:flutter/material.dart';

import '../../domain/results.dart' show NoteSeverity, StatusNote;
import '../tokens/tokens.dart';
import 'surfaces.dart';

enum StatusTone { info, warning }

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    required this.body,
    this.tone = StatusTone.info,
    this.fix,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  factory StatusCard.fromNote(
    StatusNote n, {
    Key? key,
    String? actionLabel,
    VoidCallback? onAction,
  }) => StatusCard(
    key: key,
    title: n.title,
    body: n.body,
    tone: n.severity == NoteSeverity.warning
        ? StatusTone.warning
        : StatusTone.info,
    fix: n.fix,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  final String title;
  final String body;
  final StatusTone tone;

  /// Short instruction ("Wear the band to bed tonight").
  final String? fix;

  /// A button, only when it can actually change the outcome.
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final pig = tone == StatusTone.warning ? C.amber : C.sky;
    final glyph =
        icon ??
        (tone == StatusTone.warning
            ? Icons.error_outline_rounded
            : Icons.info_outline_rounded);
    return AppCard(
      child: Semantics(
        container: true,
        label: [
          tone == StatusTone.warning ? 'Warning' : 'Note',
          title,
          body,
          if (fix != null) 'To fix: $fix',
        ].join('. '),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: p.wash(pig),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(glyph, size: 18, color: p.on(pig)),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text(title, style: F.head.copyWith(color: p.ink)),
                        const SizedBox(height: S.x1),
                        Text(body, style: F.bodySm.copyWith(color: p.ink2)),
                        if (fix != null) ...[
                          const SizedBox(height: S.x3),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 15,
                                  color: p.ink,
                                ),
                              ),
                              const SizedBox(width: S.x2),
                              Expanded(
                                child: Text(
                                  fix!,
                                  style: F.bodySm.copyWith(
                                    color: p.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: S.x3),
              Padding(
                padding: const EdgeInsets.only(left: 34 + S.x3),
                child: AppButton(
                  label: actionLabel!,
                  onTap: onAction,
                  kind: AppButtonKind.secondary,
                  compact: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
