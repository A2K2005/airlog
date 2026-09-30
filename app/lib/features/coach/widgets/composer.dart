// The composer: 2–3 follow-up chips just above one input pill with its send
// button inside, and one quiet line under it ("Wellness info, not medical
// advice." on this phone, "AI can make mistakes. Not medical advice." for
// Claude or Gemini). Answer length lives in Settings → Coach.
//
// The chips show only while the field is empty and no answer is on its
// way; they fade (160 ms, fade only) and the row's height snaps, so the
// pill never slides. While an answer is on its way the field stays
// editable and send is disabled.

import 'package:flutter/material.dart';

import '../../../app/copy.dart';
import '../../../design/design.dart';
import 'message_widgets.dart' show FollowUpChips;

class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.sending,
    required this.enabled,
    this.chips = const [],
    this.onChip,
    this.playChips = false,
    this.hint = 'Ask about your sleep, recovery or training',
    this.note = CoachCopy.notMedical,
    this.focusNode,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;

  /// False only while Coach is switched off (the chat says why).
  final bool enabled;

  /// Follow-up questions; a tap fills the field ([onChip]).
  final List<String> chips;
  final ValueChanged<String>? onChip;

  /// The chips follow a fresh answer: they enter once, one after another.
  final bool playChips;
  final String hint;

  /// The one quiet line under the pill.
  final String note;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final pick = onChip;
    return SafeArea(
      top: false,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, v, _) {
          final typed = v.text.trim().isNotEmpty;
          final showChips =
              chips.isNotEmpty && pick != null && !typed && !sending;
          final canSend = enabled && !sending && typed;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chips.isNotEmpty && pick != null)
                AnimatedOpacity(
                  opacity: showChips ? 1 : 0,
                  duration: motion(context, Motion.fast, fade: true),
                  curve: Motion.enter,
                  child: IgnorePointer(
                    ignoring: !showChips,
                    child: ExcludeSemantics(
                      excluding: !showChips,
                      child: Padding(
                        key: const ValueKey('composer-chips'),
                        padding: const EdgeInsets.only(bottom: S.x1),
                        // A new set of chips is a new row, so it enters.
                        child: FollowUpChips(
                          key: ValueKey(chips.join('|')),
                          items: chips.take(3).toList(),
                          onPick: pick,
                          play: playChips,
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: R.rLg,
                    border: Border.all(color: p.line),
                  ),
                  padding: const EdgeInsets.fromLTRB(S.x4, 0, 0, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: S.x1),
                          child: TextField(
                            key: const ValueKey('coach-input'),
                            controller: controller,
                            focusNode: focusNode,
                            enabled: enabled,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: canSend ? (_) => onSend() : null,
                            style: F.body.copyWith(color: p.ink),
                            decoration: InputDecoration(
                              hintText: hint,
                              hintStyle: F.body.copyWith(color: p.ink3),
                              isDense: true,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: S.x2,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: canSend ? 1 : .45,
                        duration: motion(context, Motion.fast, fade: true),
                        curve: Motion.enter,
                        child: AppIconButton(
                          icon: Icons.arrow_upward_rounded,
                          semanticLabel: sending
                              ? 'Waiting for the answer'
                              : 'Send',
                          filled: true,
                          onTap: canSend ? onSend : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(S.gutter, S.x1, S.gutter, S.x1),
                child: Text(
                  note,
                  key: const ValueKey('composer-note'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.micro.copyWith(color: p.ink3),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
