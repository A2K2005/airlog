// Route names. No imports on purpose: features/ import this file to navigate
// (`Navigator.of(context).pushNamed(Routes.settings)`) without importing the
// router, which imports every feature.

abstract final class Routes {
  static const home = '/';
  static const recovery = '/recovery';
  static const live = '/live';
  static const journal = '/journal';
  static const settings = '/settings';
  static const sources = '/settings/sources';
  static const profile = '/settings/profile';
  static const syncLog = '/settings/sync-log';
  static const methodology = '/methodology';
  static const licenses = '/licenses';
  static const diagnostics = '/diagnostics';
  static const onboarding = '/onboarding';

  /// Android opens the app here from Health Connect's permission screen
  /// (the "privacy policy" / permissions-rationale intent). Must work as the
  /// INITIAL route: the navigator builds '/' then '/privacy'.
  static const privacy = '/privacy';

  /// Debug builds only.
  static const gallery = '/gallery';

  // ── Ask (the coach) ─────────────────────────────────────────────────────
  // Every prefix resolves: a cold start on '/coach/setup' builds '/', then
  // '/coach', then '/coach/setup'.

  /// The chat. Arguments: an `AskContext` (domain/coach) from an "Ask about
  /// this" entry point, or nothing.
  static const coach = '/coach';

  /// Choose the engine; the consent sheet for a cloud engine.
  static const coachSetup = '/coach/setup';

  /// "What Coach knows": the confirmed memories.
  static const coachMemory = '/coach/memory';

  /// Past conversations.
  static const coachHistory = '/coach/history';

  /// Settings → Coach: engine, model, mode, length, memory, history and
  /// withdrawing consent. Settings links here.
  static const settingsCoach = '/settings/coach';

  // ── Day screens opened from a coach source chip ─────────────────────────
  // Sleep, Strain and Trends are shell tabs. A source chip pushes them as a
  // page (back returns to the chat), with the cited day selected.

  static const sleep = '/sleep';
  static const strain = '/strain';
  static const trends = '/trends';
  static const today = '/today';
}
