// The chat's rows: the user's question, an answer (its text with citations,
// the Sources row, the verification pill, "What was sent", Report, and any
// "Remember this?" proposals), the calm safety answer, an error with its
// fix, the static waiting row, and the per-session AI disclosure.
//
// Dumb widgets: plain values and callbacks in, no providers.
//
// Motion (Emil): a message enters once, with a ≤ 200 ms fade and a 6 px
// rise on the strong ease-out; old messages never animate again on rebuild;
// under reduced motion only the fade remains. The waiting row is static.

import 'package:flutter/material.dart';

import '../../../app/copy.dart';
import '../../../design/design.dart';
import '../../../domain/coach/coach_contracts.dart';
import '../coach_providers.dart';
import '../coach_view_model.dart' show MemoryChoice;
import 'answer_text.dart';

/// A one-time entrance for a new message. [play] false renders at once
/// (every message loaded from storage, and every rebuild after the first).
class CoachEnter extends StatefulWidget {
  const CoachEnter({super.key, required this.play, required this.child});

  final bool play;
  final Widget child;

  @override
  State<CoachEnter> createState() => _CoachEnterState();
}

class _CoachEnterState extends State<CoachEnter>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || !widget.play) return;
    final d = motion(context, Motion.base, fade: true);
    if (d == Duration.zero) return;
    final c = AnimationController(vsync: this, duration: d);
    _t = CurvedAnimation(parent: c, curve: Motion.enter);
    _c = c..forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    final moving = Motion.enabled(context);
    return FadeTransition(
      opacity: t,
      child: moving
          ? AnimatedBuilder(
              animation: t,
              builder: (context, c) => Transform.translate(
                offset: Offset(0, (1 - t.value) * 6),
                child: c,
              ),
              child: widget.child,
            )
          : widget.child,
    );
  }
}

/// The user's question: a right-aligned bubble.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .8,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rLg),
          child: Semantics(
            label: 'You asked: $text',
            child: ExcludeSemantics(
              child: Text(text, style: F.body.copyWith(color: p.ink)),
            ),
          ),
        ),
      ),
    );
  }
}

/// "✓ Checked against your data · 3 numbers", or the fallback's honest
/// "Showing facts only — couldn't verify the answer". Null when there is
/// nothing to say (no numbers were quoted).
class VerificationPill extends StatelessWidget {
  const VerificationPill({super.key, required this.verification});
  final Verification verification;

  static bool shows(Verification? v) =>
      v != null && (!v.verified || v.checkedNumbers > 0);

  static String label(Verification v) {
    if (!v.verified) return CoachCopy.fallback;
    final n = v.checkedNumbers;
    return '${CoachCopy.checked} · $n ${n == 1 ? 'number' : 'numbers'}';
  }

  @override
  Widget build(BuildContext context) {
    final ok = verification.verified;
    return StatePill(
      label: label(verification),
      color: ok ? C.recGreen : C.amber,
      icon: ok ? Icons.check_rounded : Icons.info_outline_rounded,
    );
  }
}

/// One source: its number, label and value. Tapping opens its screen with
/// the day selected; press feedback comes from Pressable.
class SourceChip extends StatelessWidget {
  const SourceChip({
    super.key,
    required this.number,
    required this.source,
    this.onTap,
  });

  final int number;
  final SourceRef source;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final value = refValue(source);
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x3, S.x2),
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: R.rMd,
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CiteMark(number: number, inline: false),
          const SizedBox(width: S.x2),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: source.label),
                  if (value != null)
                    TextSpan(
                      text: '  $value',
                      style: F
                          .tab(F.cap)
                          .copyWith(color: p.ink, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              style: F.cap.copyWith(color: p.ink2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: S.x1),
            Icon(Icons.chevron_right_rounded, size: 16, color: p.ink3),
          ],
        ],
      ),
    );
    final spoken =
        'Source $number: ${source.label}${value == null ? '' : ', $value'}';
    if (onTap == null) {
      return Semantics(
        label: spoken,
        child: ExcludeSemantics(child: chip),
      );
    }
    return Pressable(
      onTap: onTap,
      semanticLabel: '$spoken. Opens the screen.',
      scale: .96,
      child: ExcludeSemantics(child: chip),
    );
  }
}

/// An answer from the coach.
class AnswerView extends StatelessWidget {
  const AnswerView({
    super.key,
    required this.message,
    required this.onOpenRef,
    required this.onShowSent,
    required this.onReport,
    required this.reported,
    required this.memoryOn,
    required this.choiceOf,
    required this.categoryOf,
    required this.onPickCategory,
    required this.onRemember,
    required this.onDismissMemory,
    required this.onOpenMemory,
    this.sample = false,
  });

  final ChatMessage message;

  /// Demo mode: the answer's numbers come from sample data, so it carries a
  /// "Sample data" tag (only when it cites any).
  final bool sample;
  final void Function(SourceRef) onOpenRef;
  final VoidCallback? onShowSent;
  final VoidCallback onReport;
  final bool reported;
  final bool memoryOn;
  final MemoryChoice Function(int index) choiceOf;
  final MemoryCategory Function(int index) categoryOf;
  final void Function(int index) onPickCategory;
  final void Function(int index) onRemember;
  final void Function(int index) onDismissMemory;
  final VoidCallback onOpenMemory;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final v = m.verification;
    final proposals = [
      for (var i = 0; i < m.proposedMemories.length; i++)
        if (memoryOn && choiceOf(i) != MemoryChoice.dismissed) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sample && m.refs.isNotEmpty) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: DemoBadge(
              key: ValueKey('answer-sample'),
              label: CoachCopy.sampleData,
            ),
          ),
          const SizedBox(height: S.x2),
        ],
        CitedText(text: m.text, refs: m.refs),
        if (m.refs.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          const OverLabel('Sources'),
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x2,
            runSpacing: 0,
            children: [
              for (var i = 0; i < m.refs.length; i++)
                SourceChip(
                  key: ValueKey('source-${m.id}-${m.refs[i].id}'),
                  number: i + 1,
                  source: m.refs[i],
                  onTap: refRoute(m.refs[i]) == null
                      ? null
                      : () => onOpenRef(m.refs[i]),
                ),
            ],
          ),
        ],
        if (VerificationPill.shows(v)) ...[
          const SizedBox(height: S.x2),
          Align(
            alignment: Alignment.centerLeft,
            child: VerificationPill(verification: v!),
          ),
        ],
        const SizedBox(height: S.x1),
        Wrap(
          spacing: S.x5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (onShowSent != null)
              AppButton(
                label: 'What was sent',
                kind: AppButtonKind.quiet,
                compact: true,
                icon: Icons.outbox_outlined,
                onTap: onShowSent,
              ),
            AppButton(
              label: reported ? 'Reported' : 'Report answer',
              kind: AppButtonKind.quiet,
              compact: true,
              icon: reported ? Icons.flag_rounded : Icons.flag_outlined,
              onTap: reported ? null : onReport,
            ),
          ],
        ),
        for (final i in proposals) ...[
          const SizedBox(height: S.x2),
          RememberCard(
            key: ValueKey('remember-${m.id}-$i'),
            text: m.proposedMemories[i],
            expiresOn: m.proposedExpiry(i),
            choice: choiceOf(i),
            category: categoryOf(i),
            onPickCategory: () => onPickCategory(i),
            onRemember: () => onRemember(i),
            onDismiss: () => onDismissMemory(i),
            onOpenMemory: onOpenMemory,
          ),
        ],
      ],
    );
  }
}

/// "Remember this?" for one proposed fact. Nothing is saved until the user
/// taps Remember; "No thanks" forgets it.
class RememberCard extends StatelessWidget {
  const RememberCard({
    super.key,
    required this.text,
    this.expiresOn,
    required this.choice,
    required this.category,
    required this.onPickCategory,
    required this.onRemember,
    required this.onDismiss,
    required this.onOpenMemory,
  });

  final String text;
  final String? expiresOn;
  final MemoryChoice choice;
  final MemoryCategory category;
  final VoidCallback onPickCategory;
  final VoidCallback onRemember;
  final VoidCallback onDismiss;
  final VoidCallback onOpenMemory;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    if (choice == MemoryChoice.saved) {
      return AppCard(
        tone: CardTone.inset,
        padding: const EdgeInsets.fromLTRB(S.x4, S.x1, S.x3, S.x1),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 18, color: p.ink2),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text(
                'Saved to What Coach knows',
                style: F.bodySm.copyWith(color: p.ink2),
              ),
            ),
            AppButton(
              label: 'View',
              kind: AppButtonKind.quiet,
              compact: true,
              onTap: onOpenMemory,
            ),
          ],
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark_add_outlined, size: 18, color: p.ink2),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  'Remember this?',
                  style: F.bodySm.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x1),
          Text('“$text”', style: F.bodySm.copyWith(color: p.ink2)),
          if (expiresOn != null)
            Text('Use until $expiresOn', style: F.cap.copyWith(color: p.ink3)),
          Wrap(
            spacing: S.x3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Pressable(
                onTap: onPickCategory,
                semanticLabel: 'Category: ${category.label}. Change',
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x3,
                      vertical: S.x1 + 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: R.rPill,
                      border: Border.all(color: p.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          category.label,
                          style: F.cap.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: p.ink2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AppButton(
                label: 'Remember',
                kind: AppButtonKind.secondary,
                compact: true,
                onTap: onRemember,
              ),
              AppButton(
                label: 'No thanks',
                kind: AppButtonKind.quiet,
                compact: true,
                onTap: onDismiss,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The deterministic safety answer: calm, distinct, and without sources.
class SafetyAnswer extends StatelessWidget {
  const SafetyAnswer({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      tone: CardTone.tinted,
      accent: C.health,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 20,
            color: p.on(C.health),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'For your safety',
                  style: F.bodySm.copyWith(
                    color: p.on(C.health),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: S.x1),
                Text(text, style: F.body.copyWith(color: p.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What to do about each error.
enum ErrorFix { setup, retry, none }

/// [message] is the stored answer text: only the daily limit shows it (the
/// app's own budget message); every other kind has fixed copy here, so a
/// provider's raw error text never reaches the screen.
({String title, String body, ErrorFix fix, String? action}) errorCopy(
  CoachErrorKind kind,
  CoachProvider provider, {
  String? message,
}) {
  final who = CoachCopy.company(provider);
  return switch (kind) {
    CoachErrorKind.notConfigured => (
      title: 'Review coach settings',
      body:
          'Coach is not ready, or its settings changed during this answer. '
          'Review setup or switch to on-device. No further requests were sent.',
      fix: ErrorFix.setup,
      action: 'Open setup',
    ),
    CoachErrorKind.invalidKey => (
      title: 'Your key was not accepted',
      body:
          '$who did not accept the saved API key. Paste it again in setup; '
          'the old one is replaced.',
      fix: ErrorFix.setup,
      action: 'Fix the key',
    ),
    CoachErrorKind.rateLimited => (
      title: 'Too many questions at once',
      body: '$who asked for a short pause. Wait a moment, then try again.',
      fix: ErrorFix.retry,
      action: 'Try again',
    ),
    CoachErrorKind.quotaExceeded => (
      title: 'Your provider account is out of credit',
      body:
          'Add credit or raise the limit in the $who console, or switch to '
          'on-device in setup.',
      fix: ErrorFix.setup,
      action: 'Open setup',
    ),
    CoachErrorKind.dailyLimit => (
      title: 'Today’s limit reached',
      body: (message?.trim().isNotEmpty ?? false)
          ? message!.trim()
          : CoachCopy.usageSpent,
      fix: ErrorFix.setup,
      action: 'Open setup',
    ),
    CoachErrorKind.network => (
      title: 'No connection',
      body:
          'No answer arrived from $who. Check your connection and try again. '
          'A request may already have reached the provider.',
      fix: ErrorFix.retry,
      action: 'Try again',
    ),
    CoachErrorKind.refused => (
      title: "Coach couldn't answer that",
      body: 'The model declined this question. Try asking it another way.',
      fix: ErrorFix.none,
      action: null,
    ),
    CoachErrorKind.server => (
      title: '$who had a problem',
      body: 'Their service returned an error. Try again in a moment.',
      fix: ErrorFix.retry,
      action: 'Try again',
    ),
    CoachErrorKind.unknown => (
      title: 'Something went wrong',
      body:
          'The answer did not complete. Your question may remain in chat. '
          'Try again.',
      fix: ErrorFix.retry,
      action: 'Try again',
    ),
  };
}

/// An error, with its fix. Only the latest error offers the action.
class ErrorAnswer extends StatelessWidget {
  const ErrorAnswer({
    super.key,
    required this.kind,
    required this.provider,
    this.message,
    this.onSetup,
    this.onRetry,
  });

  final CoachErrorKind kind;
  final CoachProvider provider;

  /// The stored answer text (shown only for [CoachErrorKind.dailyLimit]).
  final String? message;
  final VoidCallback? onSetup;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = errorCopy(kind, provider, message: message);
    final onAction = switch (c.fix) {
      ErrorFix.setup => onSetup,
      ErrorFix.retry => onRetry,
      ErrorFix.none => null,
    };
    return StatusCard(
      title: c.title,
      body: c.body,
      tone: StatusTone.warning,
      icon: Icons.error_outline_rounded,
      actionLabel: onAction == null ? null : c.action,
      onAction: onAction,
    );
  }
}

/// The waiting state: a static, answer-shaped skeleton (three text lines
/// and a row of source chips) under "Checking your data…". Fades in once,
/// never loops, never a spinner.
class WaitingRow extends StatelessWidget {
  const WaitingRow({super.key, required this.generalOnly});
  final bool generalOnly;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final label = generalOnly ? 'Working on it…' : 'Checking your data…';
    return CoachEnter(
      play: true,
      child: Semantics(
        liveRegion: true,
        label: label,
        child: ExcludeSemantics(
          child: Column(
            key: const ValueKey('waiting-skeleton'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.manage_search_rounded, size: 18, color: p.ink3),
                  const SizedBox(width: S.x2),
                  Text(label, style: F.bodySm.copyWith(color: p.ink2)),
                ],
              ),
              const SizedBox(height: S.x3),
              const SkeletonBox(height: 12),
              const SizedBox(height: S.x2 + 2),
              const FractionallySizedBox(
                widthFactor: .92,
                child: SkeletonBox(height: 12),
              ),
              const SizedBox(height: S.x2 + 2),
              const FractionallySizedBox(
                widthFactor: .6,
                child: SkeletonBox(height: 12),
              ),
              if (!generalOnly) ...[
                const SizedBox(height: S.x4),
                const Row(
                  children: [
                    SkeletonBox(width: 120, height: 32, radius: R.rMd),
                    SizedBox(width: S.x2),
                    SkeletonBox(width: 96, height: 32, radius: R.rMd),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The card a "Discuss" chat is about, pinned above the conversation.
class DiscussPin extends StatelessWidget {
  const DiscussPin({super.key, required this.headline, this.body});
  final String headline;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final b = body;
    return Semantics(
      container: true,
      label: 'Discussing: $headline.${b == null ? '' : ' $b'}',
      child: ExcludeSemantics(
        child: AppCard(
          key: const ValueKey('discuss-pin'),
          tone: CardTone.inset,
          padding: const EdgeInsets.all(S.x4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.push_pin_outlined, size: 16, color: p.ink2),
              ),
              const SizedBox(width: S.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Discussing: $headline',
                      style: F.bodySm.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (b != null) ...[
                      const SizedBox(height: S.x1),
                      Text(
                        b,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: F.bodySm.copyWith(color: p.ink2),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Suggested questions as pills. Tapping one fills the composer; nothing
/// is sent until the user taps send.
class FollowUpChips extends StatelessWidget {
  const FollowUpChips({super.key, required this.items, required this.onPick});
  final List<String> items;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Wrap(
      spacing: S.x2,
      runSpacing: 0,
      children: [
        for (final q in items)
          Pressable(
            key: ValueKey('follow-up-$q'),
            onTap: () => onPick(q),
            semanticLabel: 'Suggested: $q. Fills the question box.',
            scale: .96,
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.x3,
                  vertical: S.x2,
                ),
                decoration: BoxDecoration(
                  borderRadius: R.rPill,
                  border: Border.all(color: p.line),
                ),
                child: Text(q, style: F.bodySm.copyWith(color: p.ink)),
              ),
            ),
          ),
      ],
    );
  }
}

/// The AI disclosure at the start of every cloud chat session.
class DisclosureCard extends StatelessWidget {
  const DisclosureCard({super.key, required this.provider});
  final CoachProvider provider;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      tone: CardTone.inset,
      padding: const EdgeInsets.all(S.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.smart_toy_outlined, size: 18, color: p.ink2),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(
              CoachCopy.aiDisclosure(provider),
              style: F.cap.copyWith(color: p.ink2),
            ),
          ),
        ],
      ),
    );
  }
}
