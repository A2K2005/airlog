// The chat's plain rows: the user's question, "Remember this?", the calm
// safety answer, an error with its fix, the pinned card of a "Discuss"
// chat, the follow-up chips, and the one quiet AI-disclosure line. An
// answer itself is an AnswerBlock (answer_block.dart).
//
// Dumb widgets: plain values and callbacks in, no providers.
//
// Motion (Emil): a message enters once, with a 200 ms fade and an 8 px
// rise on the strong ease-out; old messages never animate again on
// rebuild; under reduced motion only the fade remains.

import 'package:flutter/material.dart';

import '../../../app/copy.dart';
import '../../../design/design.dart';
import '../../../domain/coach/coach_contracts.dart';

/// A one-time entrance for a new message. [play] false renders at once
/// (every message loaded from storage, and every rebuild after the first).
/// [delay] staggers the cards under an answer (Motion.cardStagger).
class CoachEnter extends StatefulWidget {
  const CoachEnter({
    super.key,
    required this.play,
    required this.child,
    this.delay = Duration.zero,
  });

  final bool play;
  final Widget child;
  final Duration delay;

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
    final body = motion(context, Motion.base, fade: true);
    if (body == Duration.zero) return;
    // Under reduced motion every card fades in together: no stagger.
    final delay = Motion.enabled(context) ? widget.delay : Duration.zero;
    final total = delay + body;
    final c = AnimationController(vsync: this, duration: total);
    _t = CurvedAnimation(
      parent: c,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Motion.enter,
      ),
    );
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
                offset: Offset(0, (1 - t.value) * 8),
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

/// "Remember this?" for one proposed fact. Nothing is saved until the user
/// taps Remember; "No thanks" forgets it. Once saved, the answer shows a
/// status toast in its place.
class RememberCard extends StatelessWidget {
  const RememberCard({
    super.key,
    required this.text,
    this.expiresOn,
    required this.category,
    required this.onPickCategory,
    required this.onRemember,
    required this.onDismiss,
  });

  final String text;
  final String? expiresOn;
  final MemoryCategory category;
  final VoidCallback onPickCategory;
  final VoidCallback onRemember;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
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

/// The deterministic safety answer: calm, distinct, and without sources,
/// cards or chips.
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
                Semantics(
                  header: true,
                  child: Text(
                    'For your safety',
                    style: F.bodySm.copyWith(
                      color: p.on(C.health),
                      fontWeight: FontWeight.w700,
                    ),
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
enum ErrorFix { settings, retry, none }

/// [message] is the stored answer text: only the daily limit shows it (the
/// app's own budget message); every other kind has fixed copy here, so a
/// provider's raw error text never reaches the screen.
({String title, String body, ErrorFix fix, String? action}) errorCopy(
  CoachErrorKind kind,
  CoachProvider provider, {
  String? message,
}) {
  final cloud = provider != CoachProvider.offline;
  final who = cloud ? CoachCopy.company(provider) : 'your AI provider';
  final name = cloud ? CoachCopy.providerName(provider) : 'The AI model';
  final account = cloud ? who : 'AI';
  return switch (kind) {
    CoachErrorKind.notConfigured => (
      title: 'Check Coach settings',
      body:
          'Coach’s settings changed while it was answering, so nothing more '
          'was sent. Check them, or switch to On this phone.',
      fix: ErrorFix.settings,
      action: 'Open Coach settings',
    ),
    CoachErrorKind.invalidKey => (
      title: 'Your key didn’t work',
      body:
          '$name didn’t accept your API key. Paste it again in '
          '${CoachSettingsCopy.path}.',
      fix: ErrorFix.settings,
      action: 'Fix the key',
    ),
    CoachErrorKind.rateLimited => (
      title: 'Too many questions at once',
      body: '$who asked for a short pause. Wait a moment, then try again.',
      fix: ErrorFix.retry,
      action: 'Try again',
    ),
    CoachErrorKind.quotaExceeded => (
      title: 'Your $account account is out of credit',
      body:
          'Add credit in your $account account, or switch to On this phone '
          'in ${CoachSettingsCopy.path}.',
      fix: ErrorFix.settings,
      action: 'Open Coach settings',
    ),
    CoachErrorKind.dailyLimit => (
      title: 'Today’s limit reached',
      body: (message?.trim().isNotEmpty ?? false)
          ? message!.trim()
          : CoachCopy.usageSpent,
      fix: ErrorFix.settings,
      action: 'Open Coach settings',
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
      title: '$name didn’t answer that',
      body: 'Try asking it another way.',
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
      body: 'The answer didn’t finish. Try again.',
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
    this.onSettings,
    this.onRetry,
  });

  final CoachErrorKind kind;
  final CoachProvider provider;

  /// The stored answer text (shown only for [CoachErrorKind.dailyLimit]).
  final String? message;
  final VoidCallback? onSettings;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = errorCopy(kind, provider, message: message);
    final onAction = switch (c.fix) {
      ErrorFix.settings => onSettings,
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
      label: 'About this card: $headline.${b == null ? '' : ' $b'}',
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
                      'About this card: $headline',
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

/// Suggested questions as pills, in one row that scrolls sideways. Tapping
/// one fills the composer; nothing is sent until the user taps send. With
/// [play], fresh chips enter once, one after another (EnterFade: fade and
/// an 8 px rise, 30 ms apart; fade only under reduced motion).
class FollowUpChips extends StatelessWidget {
  const FollowUpChips({
    super.key,
    required this.items,
    required this.onPick,
    this.play = false,
  });
  final List<String> items;
  final ValueChanged<String> onPick;
  final bool play;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: S.gutter),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: S.x2),
            EnterFade(
              index: i,
              enabled: play,
              child: Pressable(
                key: ValueKey('follow-up-${items[i]}'),
                onTap: () => onPick(items[i]),
                semanticLabel:
                    'Suggested: ${items[i]}. Fills the question box.',
                scale: .96,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x3,
                      vertical: S.x2,
                    ),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: R.rPill,
                      border: Border.all(color: p.line),
                    ),
                    child: Text(
                      items[i],
                      style: F.bodySm.copyWith(color: p.ink),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The AI disclosure a cloud session opens with: one quiet centred line,
/// no card (Anthropic's usage policy asks for it).
class DisclosureLine extends StatelessWidget {
  const DisclosureLine({super.key, required this.provider});
  final CoachProvider provider;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Text(
        CoachCopy.aiDisclosure(provider),
        textAlign: TextAlign.center,
        style: F.cap.copyWith(color: p.ink3),
      ),
    );
  }
}

/// A small status note in the thread ("Saved to What Coach knows · View").
class StatusToast extends StatelessWidget {
  const StatusToast({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final action = actionLabel;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            S.x3,
            action == null ? S.x2 : 0,
            action == null ? S.x3 : S.x1,
            action == null ? S.x2 : 0,
          ),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rPill),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: p.on(C.recGreen)),
              const SizedBox(width: S.x2),
              Flexible(
                child: Text(text, style: F.cap.copyWith(color: p.ink2)),
              ),
              if (action != null)
                AppButton(
                  label: action,
                  kind: AppButtonKind.quiet,
                  compact: true,
                  onTap: onAction,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
