// The composer: the question field and send button, the Brief / Detailed
// toggle, and the standing "Wellness info, not medical advice." line.
// While an answer is on its way the field stays editable, send is disabled,
// and nothing loops.

import 'package:flutter/material.dart';

import '../../../app/copy.dart';
import '../../../design/design.dart';
import '../../../domain/coach/coach_contracts.dart';

class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.sending,
    required this.enabled,
    required this.length,
    required this.onLength,
    this.hint = 'Ask about your sleep, recovery or training',
    this.note = CoachCopy.notMedical,
    this.focusNode,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;

  /// False when the engine is not ready (the chat says why above).
  final bool enabled;
  final ResponseLength length;
  final ValueChanged<ResponseLength>? onLength;
  final String hint;

  /// The standing disclaimer under the field.
  final String note;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.x3, S.x1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('coach-input'),
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: enabled && !sending ? (_) => onSend() : null,
                      style: F.body.copyWith(color: p.ink),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: F.body.copyWith(color: p.ink3),
                        isDense: true,
                        filled: true,
                        fillColor: p.card,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: S.x4,
                          vertical: S.x3,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: R.rLg,
                          borderSide: BorderSide(color: p.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: R.rLg,
                          borderSide: BorderSide(color: p.line),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: R.rLg,
                          borderSide: BorderSide(color: p.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: R.rLg,
                          borderSide: BorderSide(color: p.ink2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: S.x1),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, v, _) => AppIconButton(
                      icon: Icons.arrow_upward_rounded,
                      semanticLabel: sending
                          ? 'Waiting for the answer'
                          : 'Send',
                      filled: true,
                      onTap: enabled && !sending && v.text.trim().isNotEmpty
                          ? onSend
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x1),
              Row(
                children: [
                  SizedBox(
                    width: 172,
                    child: SegmentedControl<ResponseLength>(
                      values: ResponseLength.values,
                      selected: length,
                      label: (l) =>
                          l == ResponseLength.brief ? 'Brief' : 'Detailed',
                      semanticsLabel: 'Answer length',
                      onChanged: onLength ?? (_) {},
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                      note,
                      style: F.micro.copyWith(color: p.ink3),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
