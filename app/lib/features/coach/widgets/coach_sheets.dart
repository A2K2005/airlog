// The chat's bottom sheets: "What was sent" (per cloud answer), "Report
// answer" (kept on this phone; details copied only if the user asks), and
// the memory-category picker. Sheets use sheetMotion (drawer curve, exit
// faster than enter, a cut under reduced motion).

import 'package:flutter/material.dart';

import '../../../app/copy.dart';
import '../../../design/design.dart';
import '../../../domain/coach/coach_contracts.dart';

Future<T?> _sheet<T>(
  BuildContext context,
  List<Widget> children,
) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: sheetMotion(context),
  builder: (c) {
    final p = P.of(c);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, S.x8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: p.line, borderRadius: R.rPill),
              ),
            ),
            const SizedBox(height: S.x4),
            ...children,
          ],
        ),
      ),
    );
  },
);

Widget _title(BuildContext context, String s) => Semantics(
  header: true,
  child: Text(s, style: F.t1.copyWith(color: P.of(context).ink)),
);

/// "About 4,200 characters".
String approxSize(int chars) {
  if (chars < 1000) return 'About $chars characters';
  final k = (chars / 100).round() / 10;
  final t = k == k.roundToDouble() ? k.toStringAsFixed(0) : '$k';
  return 'About ${t}k characters';
}

/// What left the phone for one answer.
Future<void> showSentSheet(BuildContext context, SentPayload sent) {
  final model = CoachCopy.model(sent.provider, sent.model);
  return _sheet<void>(context, [
    _title(context, 'What was sent'),
    const SizedBox(height: S.x2),
    Text(
      CoachCopy.recipient(sent.provider),
      style: F.bodySm.copyWith(color: P.of(context).ink2),
    ),
    const SizedBox(height: S.x4),
    AppCard(
      tone: CardTone.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueLine('To', CoachCopy.company(sent.provider)),
          KeyValueLine('Model', model?.name ?? sent.model),
          KeyValueLine('Size', approxSize(sent.approxChars)),
          KeyValueLine(
            'Tools',
            sent.toolsCalled.isEmpty
                ? 'None'
                : sent.toolsCalled
                      .map((t) => t.replaceAll('_', ' '))
                      .join(', '),
          ),
        ],
      ),
    ),
    const SizedBox(height: S.x4),
    const OverLabel('Data in this question'),
    const SizedBox(height: S.x2),
    if (sent.dataTypes.isEmpty)
      const BulletLine('None of your data: only the question.')
    else
      for (final d in sent.dataTypes) BulletLine(d),
    const SizedBox(height: S.x4),
    const OverLabel('Never sent'),
    const SizedBox(height: S.x2),
    for (final n in CoachCopy.neverSent)
      BulletLine(n, icon: Icons.block_rounded),
    const SizedBox(height: S.x4),
    Text(
      CoachCopy.retention(sent.provider),
      style: F.cap.copyWith(color: P.of(context).ink3),
    ),
  ]);
}

/// Report an answer. Returns true when the user flagged it.
Future<bool> showReportSheet(
  BuildContext context, {
  required Future<void> Function() onFlag,
}) async {
  final done = await _sheet<bool>(context, [
    _title(context, 'Report this answer'),
    const SizedBox(height: S.x2),
    Builder(
      builder: (c) => Text(
        'Flag an answer that is wrong, unsafe or unhelpful. The flag stays '
        'on this phone: Airlog has no server, so nothing is sent. The '
        'question, the answer and its sources are copied, so you can share '
        'them with the developer if you choose.',
        style: F.body.copyWith(color: P.of(c).ink2),
      ),
    ),
    const SizedBox(height: S.x5),
    Builder(
      builder: (c) => AppButton(
        label: 'Flag and copy details',
        icon: Icons.flag_outlined,
        expand: true,
        onTap: () async {
          await onFlag();
          if (c.mounted) Navigator.of(c).pop(true);
        },
      ),
    ),
    const SizedBox(height: S.x2),
    Builder(
      builder: (c) => AppButton(
        label: 'Cancel',
        kind: AppButtonKind.secondary,
        expand: true,
        onTap: () => Navigator.of(c).pop(false),
      ),
    ),
  ]);
  return done ?? false;
}

/// The category picker for a memory. Returns the choice, or null.
Future<MemoryCategory?> showCategorySheet(
  BuildContext context,
  MemoryCategory current,
) => _sheet<MemoryCategory>(context, [
  _title(context, 'Save under'),
  const SizedBox(height: S.x3),
  for (final c in MemoryCategory.values)
    Builder(
      builder: (ctx) {
        final p = P.of(ctx);
        final on = c == current;
        return Pressable(
          onTap: () => Navigator.of(ctx).pop(c),
          selected: on,
          scale: .985,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(
              children: [
                Expanded(
                  child: Text(c.label, style: F.head.copyWith(color: p.ink)),
                ),
                if (on) Icon(Icons.check_rounded, size: 20, color: p.ink),
              ],
            ),
          ),
        );
      },
    ),
]);
