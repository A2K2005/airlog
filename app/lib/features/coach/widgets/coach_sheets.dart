// The chat's bottom sheets: "What this answer shared" (per cloud answer),
// "Report this answer" (kept on this phone; details copied only if the user
// asks), the memory-category picker, an answer's sources, and one number's
// metric sheet. Sheets use sheetMotion (drawer curve, exit faster than
// enter, a cut under reduced motion).

import 'package:flutter/material.dart';

import '../../../app/copy.dart';
import '../../../design/design.dart';
import '../../../domain/coach/coach_contracts.dart';
import 'metric_card.dart';

/// A bottom sheet with the chat's handle and padding.
Future<T?> coachSheet<T>(
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

/// A sheet's title.
Widget sheetTitle(BuildContext context, String s) => Semantics(
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
  return coachSheet<void>(context, [
    sheetTitle(context, 'What this answer shared'),
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
          KeyValueLine('Sent to', CoachCopy.company(sent.provider)),
          KeyValueLine('Model', model?.name ?? sent.model),
          KeyValueLine('Size', approxSize(sent.approxChars)),
          KeyValueLine(
            'Data looked up',
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
    const OverLabel('Your data in this question'),
    const SizedBox(height: S.x2),
    if (sent.dataTypes.isEmpty)
      const BulletLine('None of your data, only your question.')
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
  final done = await coachSheet<bool>(context, [
    sheetTitle(context, 'Report this answer'),
    const SizedBox(height: S.x2),
    Builder(
      builder: (c) => Text(
        'Flag an answer that’s wrong, unsafe or unhelpful. The flag stays '
        'on this phone, and nothing is sent. Airlog copies the question and '
        'answer so you can send them to the developer if you want.',
        style: F.body.copyWith(color: P.of(c).ink2),
      ),
    ),
    const SizedBox(height: S.x5),
    Builder(
      builder: (c) => AppButton(
        label: 'Flag and copy',
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
) => coachSheet<MemoryCategory>(context, [
  sheetTitle(context, 'Save under'),
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

/// The numbers an answer quotes, each with where it came from, one 48 dp
/// row each ("Checked against your data" when the verifier checked them
/// all). A tap opens that number's metric sheet.
Future<void> showSourcesSheet(
  BuildContext context, {
  required ChatMessage message,
  required String title,
  required String lede,
  required bool checked,
  required void Function(int index) onOpen,
}) => coachSheet<void>(context, [
  sheetTitle(context, title),
  const SizedBox(height: S.x2),
  Builder(
    builder: (c) => Text(
      lede,
      style: F.bodySm.copyWith(color: P.of(c).ink2),
    ),
  ),
  const SizedBox(height: S.x3),
  for (var i = 0; i < message.refs.length; i++)
    Builder(
      builder: (c) {
        final p = P.of(c);
        final r = message.refs[i];
        final value = r.value == null ? null : readingOf(r);
        return Pressable(
          key: ValueKey('source-row-${message.id}-${r.id}'),
          scale: .985,
          semanticLabel:
              '${value ?? r.label}${checked ? ', checked' : ''}. From '
              '${r.label}. Opens details.',
          onTap: () {
            Navigator.of(c).pop();
            onOpen(i);
          },
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x3),
              child: Row(
                children: [
                  Icon(
                    checked ? Icons.check_rounded : Icons.circle_outlined,
                    size: checked ? 18 : 8,
                    color: checked ? p.on(C.recGreen) : p.ink3,
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (value != null)
                          Text(
                            value,
                            style: F
                                .tab(F.head)
                                .copyWith(color: p.ink),
                          ),
                        Text(
                          r.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: S.x1),
                  Icon(Icons.chevron_right_rounded, size: 18, color: p.ink3),
                ],
              ),
            ),
          ),
        );
      },
    ),
]);

/// One cited number: its value in dots, its picture when the answer's tools
/// gave one, whether it was checked, and the screen it came from.
Future<void> showMetricSheet(
  BuildContext context, {
  required SourceRef ref,
  AnswerVisual? visual,
  required bool checked,
  VoidCallback? onOpenScreen,
  String? screenName,
}) {
  final v = visual;
  final values = v == null ? const <double?>[] : [for (final p in v.series) p.value];
  final trend = v != null && MetricCard.tierOf(v) == MetricTier.trend;
  final hasRange = v?.usualLow != null && v?.usualHigh != null;
  return coachSheet<void>(context, [
    sheetTitle(context, v == null ? ref.label.split(' · ').first : metricName(v.metric)),
    Builder(
      builder: (c) => Text(
        captionOf(ref),
        style: F.bodySm.copyWith(color: P.of(c).ink2),
      ),
    ),
    const SizedBox(height: S.x4),
    DotReading(readingOf(ref), style: F.dot48, unitStyle: F.body),
    if (v != null && MetricCard.usualLine(v, ref) != null) ...[
      const SizedBox(height: S.x2),
      Builder(
        builder: (c) => Text(
          MetricCard.usualLine(v, ref)!,
          style: F.bodySm.copyWith(color: P.of(c).ink2),
        ),
      ),
    ],
    if (v != null && MetricCard.stateWord(v.state) != null) ...[
      const SizedBox(height: S.x1),
      Builder(
        builder: (c) => Text(
          '${MetricCard.stateWord(v.state)} '
          '(usual range ${readingIn(v.usualLow!, ref)} to '
          '${readingIn(v.usualHigh!, ref)})',
          style: F.bodySm.copyWith(color: P.of(c).ink2),
        ),
      ),
    ],
    if (trend) ...[
      const SizedBox(height: S.x4),
      AppCard(
        child: BaselineBandChart(
          title: 'Last ${values.length} days',
          unit: ref.unit ?? '',
          values: values,
          color: MetricCard.accentFor(v.metric),
          mean: v.usual,
          lower: hasRange ? v.usualLow : null,
          upper: hasRange ? v.usualHigh : null,
          highlightIndex: values.length - 1,
          height: 120,
        ),
      ),
    ],
    if (checked) ...[
      const SizedBox(height: S.x4),
      Builder(
        builder: (c) {
          final p = P.of(c);
          return Row(
            children: [
              Icon(Icons.check_rounded, size: 18, color: p.on(C.recGreen)),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  'Found in your data: Airlog checked this number.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
              ),
            ],
          );
        },
      ),
    ],
    if (onOpenScreen != null) ...[
      const SizedBox(height: S.x5),
      Builder(
        builder: (c) => AppButton(
          key: const ValueKey('metric-open-screen'),
          label: 'Open ${screenName ?? 'the screen'}',
          kind: AppButtonKind.secondary,
          expand: true,
          onTap: () {
            Navigator.of(c).pop();
            onOpenScreen();
          },
        ),
      ),
    ],
    const SizedBox(height: S.x4),
    Builder(
      builder: (c) => Text(
        CoachCopy.notMedical,
        style: F.cap.copyWith(color: P.of(c).ink3),
      ),
    ),
  ]);
}
