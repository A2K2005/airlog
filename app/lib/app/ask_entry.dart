// "Ask about this": the coach's entry points, for any screen.
//
// Shared kit for features/: imports no feature. A screen drops in
//
//   * AskAboutThis   a quiet text button ("Ask about this"), or
//   * AskIconButton  a 48 dp header icon ("Ask"),
//
// or calls openCoach() itself. Each opens Routes.coach with an AskContext
// (the screen and the day it shows). The chat pre-fills a question for that
// screen and day, or uses [prefill] when given.
//
// The master switch (Settings → Coach → "Show coach", CoachSettings.enabled)
// hides every entry point when it is off. A screen whose tests do not wire
// the coach still shows the buttons: an unwired coach reads as "unknown",
// and the buttons' default is visible.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/design.dart';
import '../domain/coach/coach_contracts.dart';
import 'copy.dart';
import 'providers.dart';
import 'route_names.dart';

/// The icon every "Ask" entry point uses.
const askIcon = Icons.chat_bubble_outline_rounded;

Duration? _noRetry(int count, Object error) => null;

/// The "Show coach" master switch: true or false once read, null when the
/// coach is not wired (no repository override) or its storage failed.
/// Ask buttons show unless this is `false`; insight cards show only when it
/// is `true`. Kept alive: Settings → Coach invalidates it when it changes.
final coachEnabledProvider = FutureProvider<bool?>((ref) async {
  try {
    final repo = ref.watch(coachRepositoryProvider);
    return (await repo.settings()).enabled;
  } catch (_) {
    return null;
  }
}, retry: _noRetry);

/// Route arguments for [Routes.coach].
class CoachArgs {
  const CoachArgs({this.context, this.prefill, this.conversationId});

  /// Where the question is asked from (screen + day, or an insight card's
  /// "Discuss"). Null from a plain "Ask" button.
  final AskContext? context;

  /// Text to pre-fill the composer with. Null lets the chat derive one from
  /// [context]. Never sent until the user taps send.
  final String? prefill;

  /// Reopen a stored conversation instead of starting a new session.
  final String? conversationId;
}

/// Pushes the coach chat, optionally about [ask]'s screen and day.
Future<void> openCoach(
  BuildContext context,
  AskContext? ask, {
  String? prefill,
}) async {
  await Navigator.of(context).pushNamed(
    Routes.coach,
    arguments: CoachArgs(context: ask, prefill: prefill),
  );
}

/// A quiet "Ask about this" button that opens the coach about [screen]
/// ('today' | 'recovery' | 'sleep' | 'strain' | 'trends' | 'journal') on
/// [date] (yyyy-MM-dd; null = the latest day). Renders nothing while the
/// coach is switched off.
class AskAboutThis extends ConsumerWidget {
  const AskAboutThis({
    super.key,
    required this.screen,
    this.date,
    this.prefill,
    this.label = CoachCopy.askAboutThis,
  });

  final String screen;
  final String? date;
  final String? prefill;

  /// "Ask about this" by default; Today uses [CoachCopy.askAboutToday].
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(coachEnabledProvider).value == false) {
      return const SizedBox.shrink();
    }
    return AppButton(
      label: label,
      kind: AppButtonKind.quiet,
      compact: true,
      icon: askIcon,
      onTap: () => openCoach(
        context,
        AskContext(screen: screen, date: date),
        prefill: prefill,
      ),
    );
  }
}

/// The header icon ("Ask"). With [screen] it asks about that screen and
/// [date]; without, it opens a plain new chat. Renders nothing while the
/// coach is switched off.
class AskIconButton extends ConsumerWidget {
  const AskIconButton({super.key, this.screen, this.date});

  final String? screen;
  final String? date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(coachEnabledProvider).value == false) {
      return const SizedBox.shrink();
    }
    return AppIconButton(
      icon: askIcon,
      semanticLabel: 'Ask the coach',
      onTap: () => openCoach(
        context,
        screen == null ? null : AskContext(screen: screen, date: date),
      ),
    );
  }
}
