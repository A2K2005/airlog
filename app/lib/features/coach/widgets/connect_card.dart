// The empty chat's one, dismissible nudge: "For fuller answers, connect
// Claude or Gemini in Settings". Shown only while the coach answers on this
// phone, the chat is empty, it is not a Discuss chat, and it was never
// dismissed (CoachSettings.cloudHintDismissed). Never a wall: the composer
// works either way.

import 'package:flutter/material.dart';

import '../../../app/copy.dart';
import '../../../design/design.dart';

class ConnectHintCard extends StatelessWidget {
  const ConnectHintCard({
    super.key,
    required this.onOpen,
    required this.onDismiss,
  });

  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      key: const ValueKey('connect-hint'),
      tone: CardTone.inset,
      padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x1, S.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.auto_awesome_outlined, size: 18, color: p.ink2),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  CoachCopy.connectHint,
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
                AppButton(
                  key: const ValueKey('connect-hint-open'),
                  label: 'Open Settings',
                  kind: AppButtonKind.quiet,
                  compact: true,
                  onTap: onOpen,
                ),
              ],
            ),
          ),
          AppIconButton(
            key: const ValueKey('connect-hint-dismiss'),
            icon: Icons.close_rounded,
            semanticLabel: 'Dismiss',
            size: 18,
            color: p.ink3,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}
