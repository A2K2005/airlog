// ExplainSheet — the "how is this calculated" bottom sheet. Every score's
// breakdown is free and one tap away (PRODUCT_PLAN §3 principle 1).
//
//   showExplainSheet(context, title: 'Recovery', lede: '…', children: [
//     ExplainSection(title: 'Inputs', child: ContributionBars.recovery(…)),
//     ExplainSection(title: 'Formula', formula: 'score = Σ wᵢ · sᵢ − penalties'),
//   ]);
//
// Motion: drawer curve, 280 ms in / 180 ms out; no animation under reduced
// motion (see sheetMotion).

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';
import 'motion_widgets.dart';

Future<T?> showExplainSheet<T>(
  BuildContext context, {
  required String title,
  String? lede,
  List<Widget> children = const [],
  String? footnote = ExplainSheet.defaultFootnote,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: sheetMotion(context),
    builder: (c) => ExplainSheet(
      title: title,
      lede: lede,
      footnote: footnote,
      children: children,
    ),
  );
}

class ExplainSheet extends StatelessWidget {
  const ExplainSheet({
    super.key,
    required this.title,
    this.lede,
    this.children = const [],
    this.footnote = defaultFootnote,
  });

  static const defaultFootnote =
      'Computed on this phone from your own data. Not medical advice.';

  final String title;
  final String? lede;
  final List<Widget> children;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final maxH = MediaQuery.sizeOf(context).height * .88;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: S.x3),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: p.line, borderRadius: R.rPill),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                S.gutter,
                S.x5,
                S.gutter,
                S.x8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: F.t1.copyWith(color: p.ink)),
                  ),
                  if (lede != null) ...[
                    const SizedBox(height: S.x2),
                    Text(lede!, style: F.body.copyWith(color: p.ink2)),
                  ],
                  for (var i = 0; i < children.length; i++) ...[
                    const SizedBox(height: S.x6),
                    EnterFade(index: i, child: children[i]),
                  ],
                  if (footnote != null) ...[
                    const SizedBox(height: S.x8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: p.ink3,
                        ),
                        const SizedBox(width: S.x2),
                        Expanded(
                          child: Text(
                            footnote!,
                            style: F.cap.copyWith(color: p.ink3),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One block in an ExplainSheet: a heading, prose, an optional formula line
/// and an optional child (a chart, contribution bars).
class ExplainSection extends StatelessWidget {
  const ExplainSection({
    super.key,
    required this.title,
    this.body,
    this.formula,
    this.child,
  });

  final String title;
  final String? body;

  /// Plain-text formula, shown in an inset block with tabular figures.
  final String? formula;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title.toUpperCase(),
            style: F.over.copyWith(color: p.ink3),
          ),
        ),
        const SizedBox(height: S.x2),
        if (body != null) Text(body!, style: F.body.copyWith(color: p.ink2)),
        if (formula != null) ...[
          const SizedBox(height: S.x3),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: S.x4,
              vertical: S.x3,
            ),
            decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
            child: Text(
              formula!,
              style: F
                  .tab(F.bodySm)
                  .copyWith(color: p.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        if (child != null) ...[const SizedBox(height: S.x3), child!],
      ],
    );
  }
}
