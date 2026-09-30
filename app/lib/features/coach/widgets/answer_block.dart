// One coach answer: a short reply in plain text, then its cards, then a
// quiet footer.
//
//   reply        the text on the page, no card and no citation marks
//                (answer_text.dart); the verifier still checks every number
//   metric cards pictures of cited numbers (metric_card.dart)
//   plan actions today's plan, word for word ("From today's plan")
//   facts card   "What your data shows": the facts-only fallback as tiles
//   toasts       "Saved to What Coach knows", "Flagged on this phone"
//   footer       ⋯ (engine, data, "Checked against your data", what was
//                shared, report) and a glyph when another engine answered
//
// No data-mode label goes on a message: only the data-mode screens label it.
//
// Principle 6: every number on a card is a cited ref, one of the answer's
// visuals, or a plan action's own words. Dumb widgets: values and callbacks
// in, no providers.

import 'package:flutter/material.dart';

import '../../../app/copy.dart';
import '../../../app/screen_kit.dart' show InfoButton;
import '../../../design/design.dart';
import '../../../domain/coach/coach_contracts.dart';
import '../../../domain/coach/prompts.dart' show CoachPrompts;
import '../../../domain/today_plan.dart' show PlanActionKind;
import 'answer_text.dart';
import 'coach_sheets.dart';
import 'message_widgets.dart';
import 'metric_card.dart';

/// The answer's own words, where the chat keeps them.
abstract final class AnswerCopy {
  static const factsTitle = 'What your data shows';
  static const factsCaption =
      'Just your numbers: Coach couldn’t word a full answer without guessing.';
  static const factsWhy =
      'Coach checks every number an answer quotes against your data. This '
      'time it couldn’t word an answer that passed, so it shows the numbers '
      'it found instead.';
  static const fromPlan = 'From today’s plan';
  static const saved = 'Saved to What Coach knows';
  static const flagged = 'Flagged on this phone. Details copied.';
  static const options = 'Answer options';
  static const checkedTitle = 'Checked against your data';
  static String checked(int n) =>
      n == 1 ? '1 number checked' : '$n numbers checked';
  static const checkedWhy =
      'Coach found every number in this answer in your data. Each one, and '
      'where it came from:';
  static const sourcesWhy =
      'The numbers this answer quotes, and where each came from:';
  static const nothingShared = 'Nothing left this phone';
  static const onThisPhone = 'Answered on this phone';
}

/// The facts-only fallback (the verified facts table), including answers
/// stored before [ChatMessage.factsOnly] existed: the table re-verifies as
/// true, so only its flag or its opening words tell.
bool isFactsOnly(ChatMessage m) =>
    m.factsOnly ||
    m.text.startsWith(CoachPrompts.fallbackNote) ||
    m.text.startsWith('I couldn\'t phrase an answer without adding details') ||
    m.text.startsWith('I couldn\'t check every number in my answer') ||
    (m.verification != null && !m.verification!.verified);

/// Every number in [m] was checked ("Checked against your data" in ⋯).
bool isChecked(ChatMessage m) {
  final v = m.verification;
  return !isFactsOnly(m) && v != null && v.verified && v.checkedNumbers > 0;
}

class AnswerBlock extends StatelessWidget {
  const AnswerBlock({
    super.key,
    required this.message,
    required this.play,
    required this.onCite,
    required this.onOpenCard,
    required this.onOpenAction,
    required this.onMenu,
    this.engineGlyph,
    this.proposals = const [],
    this.flagged = false,
  });

  final ChatMessage message;

  /// A fresh answer: its cards enter one after another.
  final bool play;

  /// A facts tile: the ref's index.
  final void Function(int index) onCite;
  final void Function(SourceRef ref, AnswerVisual visual) onOpenCard;
  final void Function(String route) onOpenAction;
  final VoidCallback onMenu;

  /// Another engine than the chosen model wrote it: the glyph's spoken
  /// label ("Answered by Sonnet 5.5"), else null.
  final String? engineGlyph;

  /// "Remember this?" cards and their toasts, in order.
  final List<Widget> proposals;

  /// Reported on this phone: the toast shows.
  final bool flagged;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final facts = isFactsOnly(m);
    final cards = <Widget>[
      if (facts && m.refs.isNotEmpty)
        FactsCard(
          key: ValueKey('facts-${m.id}'),
          refs: m.refs,
          onOpen: onCite,
        ),
      if (!facts && MetricCards.of(m).isNotEmpty)
        MetricCards(message: m, onOpen: onOpenCard),
      if (!facts && m.actions.isNotEmpty)
        PlanActions(
          key: ValueKey('actions-${m.id}'),
          actions: m.actions.take(2).toList(),
          onOpen: onOpenAction,
        ),
      ...proposals,
      if (flagged)
        const StatusToast(icon: Icons.flag_rounded, text: AnswerCopy.flagged),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!facts || m.refs.isEmpty)
          CoachEnter(
            play: play,
            child: ReplyText(text: m.text, refs: m.refs),
          ),
        for (var i = 0; i < cards.length; i++) ...[
          SizedBox(height: i == 0 && !(facts && m.refs.isNotEmpty) ? S.x3 : S.x2),
          CoachEnter(
            play: play,
            delay: Motion.cardStagger *
                (i + 1).clamp(0, Motion.cardStaggerCap),
            child: cards[i],
          ),
        ],
        CoachEnter(
          play: play,
          delay: Motion.cardStagger *
              (cards.length + 1).clamp(0, Motion.cardStaggerCap),
          child: AnswerFooter(
            key: ValueKey('footer-${m.id}'),
            onMenu: onMenu,
            engineGlyph: engineGlyph,
            onDevice: m.answeredBy == ChatMessage.onDevice,
          ),
        ),
      ],
    );
  }
}

/// ⋯, and a glyph when another engine answered.
class AnswerFooter extends StatelessWidget {
  const AnswerFooter({
    super.key,
    required this.onMenu,
    this.engineGlyph,
    this.onDevice = false,
  });

  final VoidCallback onMenu;
  final String? engineGlyph;
  final bool onDevice;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final glyph = engineGlyph;
    return Row(
      children: [
        // A 48 dp target whose icon lines up with the reply's left edge.
        Pressable(
          onTap: onMenu,
          semanticLabel: AnswerCopy.options,
          scale: .92,
          child: SizedBox(
            width: S.tap,
            height: S.tap,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(Icons.more_horiz_rounded, size: 20, color: p.ink3),
            ),
          ),
        ),
        if (glyph != null)
          Semantics(
            container: true,
            label: glyph,
            child: Icon(
              onDevice ? Icons.phone_android_rounded : Icons.swap_horiz_rounded,
              size: 14,
              color: p.ink3,
            ),
          ),
      ],
    );
  }
}

/// "What your data shows": the facts-only fallback as tiles, with one
/// honest line.
class FactsCard extends StatelessWidget {
  const FactsCard({super.key, required this.refs, required this.onOpen});

  final List<SourceRef> refs;
  final void Function(int index) onOpen;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (var i = 0; i < refs.length; i++)
        if (refs[i].value != null) _tile(i, refs[i]),
    ];
    return GlowPanel(
      glow: GlowRecipes.m8,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              AnswerCopy.factsTitle,
              style: F.tileTitle.copyWith(color: TileInk.primary),
            ),
          ),
          const SizedBox(height: S.x3),
          for (var i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: S.x2),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[i]),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: i + 1 < tiles.length
                        ? tiles[i + 1]
                        : const SizedBox(),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: S.x2),
          Row(
            children: [
              Expanded(
                child: Text(
                  AnswerCopy.factsCaption,
                  style: F.tileLabel.copyWith(
                    color: TileInk.secondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const InfoButton(
                title: 'Just your numbers',
                lede: AnswerCopy.factsWhy,
                footnote: CoachCopy.notMedical,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(int i, SourceRef r) {
    final label = r.label.split(' · ').first;
    final caption = captionOf(r);
    return Pressable(
      key: ValueKey('fact-${r.id}'),
      onTap: () => onOpen(i),
      scale: .98,
      semanticLabel:
          '$label, ${readingOf(r)}${caption.isEmpty ? '' : ', $caption'}. '
          'Opens details.',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(S.x3),
          decoration: const BoxDecoration(color: C.plate, borderRadius: R.rMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: F.tileLabel.copyWith(color: TileInk.unit),
              ),
              const SizedBox(height: S.x1),
              DotReading(readingOf(r), style: F.dot24),
              if (caption.isNotEmpty)
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.tileMicro.copyWith(color: TileInk.secondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's plan actions under an answer, in the plan tile's own words and
/// look.
class PlanActions extends StatelessWidget {
  const PlanActions({super.key, required this.actions, required this.onOpen});

  final List<AnswerAction> actions;
  final void Function(String route) onOpen;

  static IconData iconFor(String kind) {
    for (final k in PlanActionKind.values) {
      if (k.name == kind) return PlanTile.iconFor(k);
    }
    return Icons.flag_outlined;
  }

  @override
  Widget build(BuildContext context) => GlowPanel(
    glow: GlowRecipes.m8,
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(S.tilePad, 12, S.tilePad, S.x1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AnswerCopy.fromPlan,
          style: F.tileMicro.copyWith(color: TileInk.secondary),
        ),
        for (final a in actions) _row(a),
      ],
    ),
  );

  Widget _row(AnswerAction a) {
    final meta = a.meta;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: C.badge,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(iconFor(a.kind), size: 18, color: TileInk.primary),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: F.tileBody.copyWith(color: TileInk.primary),
                ),
                if (meta != null)
                  Text(
                    meta,
                    style: F.tileLabel.copyWith(
                      fontWeight: FontWeight.w400,
                      color: TileInk.secondary,
                    ),
                  ),
              ],
            ),
          ),
          if (a.route != null)
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: TileInk.secondary,
            ),
        ],
      ),
    );
    final route = a.route;
    final spoken = '${a.title}${meta == null ? '' : '. $meta'}';
    if (route == null) {
      return Semantics(
        label: spoken,
        child: ExcludeSemantics(child: row),
      );
    }
    return Pressable(
      key: ValueKey('action-${a.kind}'),
      onTap: () => onOpen(route),
      semanticLabel: '$spoken. Opens the screen.',
      child: ExcludeSemantics(child: row),
    );
  }
}

/// The ⋯ menu of one answer: which engine answered and with what data,
/// "Checked against your data" (each number and where it came from, when
/// the verifier checked them all; else "Sources"), what it shared, "Ask
/// again" and Report.
Future<void> showAnswerMenu(
  BuildContext context, {
  required String engine,
  String? engineNote,
  String? mode,
  bool checked = false,
  int sources = 0,
  VoidCallback? onSources,
  VoidCallback? onShared,
  String? askAgainLabel,
  VoidCallback? onAskAgain,
  required bool reported,
  VoidCallback? onReport,
}) => coachSheet<void>(context, [
  sheetTitle(context, engine),
  if (engineNote != null) ...[
    const SizedBox(height: S.x1),
    Builder(
      builder: (c) => Text(
        engineNote,
        key: const ValueKey('menu-engine-note'),
        style: F.bodySm.copyWith(color: P.of(c).ink2),
      ),
    ),
  ],
  const SizedBox(height: S.x3),
  if (mode != null)
    _MenuRow(icon: Icons.insights_rounded, label: mode),
  if (sources > 0 && onSources != null)
    Builder(
      builder: (c) => _MenuRow(
        key: const ValueKey('menu-sources'),
        icon: checked
            ? Icons.fact_check_outlined
            : Icons.format_list_numbered_rounded,
        label: checked ? AnswerCopy.checkedTitle : 'Sources · $sources',
        onTap: () {
          Navigator.of(c).pop();
          onSources();
        },
      ),
    ),
  if (onShared != null)
    Builder(
      builder: (c) => _MenuRow(
        key: const ValueKey('menu-shared'),
        icon: Icons.outbox_outlined,
        label: 'What was shared',
        onTap: () {
          Navigator.of(c).pop();
          onShared();
        },
      ),
    )
  else
    const _MenuRow(
      icon: Icons.phone_android_rounded,
      label: AnswerCopy.nothingShared,
    ),
  if (askAgainLabel != null && onAskAgain != null)
    Builder(
      builder: (c) => _MenuRow(
        key: const ValueKey('menu-ask-again'),
        icon: Icons.refresh_rounded,
        label: askAgainLabel,
        onTap: () {
          Navigator.of(c).pop();
          onAskAgain();
        },
      ),
    ),
  Builder(
    builder: (c) => _MenuRow(
      key: const ValueKey('menu-report'),
      icon: reported ? Icons.flag_rounded : Icons.flag_outlined,
      label: reported ? 'Reported' : 'Report answer',
      onTap: reported || onReport == null
          ? null
          : () {
              Navigator.of(c).pop();
              onReport();
            },
    ),
  ),
]);

class _MenuRow extends StatelessWidget {
  const _MenuRow({super.key, required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.ink2),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(label, style: F.head.copyWith(color: p.ink)),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded, size: 20, color: p.ink3),
        ],
      ),
    );
    if (onTap == null) {
      return MergeSemantics(child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: S.tap),
        child: row,
      ));
    }
    return Pressable(onTap: onTap, scale: .985, child: row);
  }
}
