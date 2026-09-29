// The router: every named route → its screen. Names live in route_names.dart
// so features can navigate without importing this file.
//
// Deep links / initial routes: MaterialApp's default initial-route generation
// splits '/settings/sources' into '/', '/settings', '/settings/sources', so
// every prefix must resolve here (they do). Android opens '/privacy' from
// Health Connect's permissions screen.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../features/coach/coach_history_screen.dart';
import '../features/coach/coach_memory_screen.dart';
import '../features/coach/coach_screen.dart';
import '../features/coach/coach_settings_screen.dart';
import '../features/coach/coach_setup_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/gallery/gallery_screen.dart';
import '../features/journal/journal_screen.dart';
import '../features/live/live_screen.dart';
import '../features/methodology/methodology_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/privacy/privacy_screen.dart';
import '../features/recovery/recovery_screen.dart';
import '../features/settings/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/sources_screen.dart';
import '../features/settings/sync_log_screen.dart';
import '../features/sleep/sleep_screen.dart';
import '../features/strain/strain_screen.dart';
import '../features/today/today_screen.dart';
import '../features/trends/trends_screen.dart';
import 'licenses.dart';
import 'route_names.dart';
import 'shell.dart';

export 'route_names.dart';

/// Every route. `/gallery` exists in debug builds only.
final Map<String, WidgetBuilder> routeTable = {
  Routes.home: (_) => const AppShell(),
  Routes.recovery: (_) => const RecoveryScreen(),
  Routes.live: (_) => const LiveScreen(),
  Routes.journal: (_) => const JournalScreen(),
  Routes.settings: (_) => const SettingsScreen(),
  Routes.sources: (_) => const SourcesScreen(),
  Routes.profile: (_) => const ProfileScreen(),
  Routes.syncLog: (_) => const SyncLogScreen(),
  Routes.methodology: (_) => const MethodologyScreen(),
  Routes.licenses: (_) {
    registerAirlogLicenses();
    return const LicensePage(
      applicationName: 'Airlog',
      applicationLegalese:
          'Computed on your phone. Not medical advice.\n'
          'Not affiliated with Google, Fitbit or WHOOP.',
    );
  },
  Routes.diagnostics: (_) => const DiagnosticsScreen(),
  Routes.onboarding: (_) => const OnboardingScreen(),
  Routes.privacy: (_) => const PrivacyScreen(),
  Routes.coach: (_) => const CoachScreen(),
  Routes.coachSetup: (_) => const CoachSetupScreen(),
  Routes.coachMemory: (_) => const CoachMemoryScreen(),
  Routes.coachHistory: (_) => const CoachHistoryScreen(),
  Routes.settingsCoach: (_) => const CoachSettingsScreen(),
  // The day tabs as pages, for a coach source chip (back returns to the
  // chat). The shell's own tabs are unchanged.
  Routes.today: (_) => const TabPage(child: TodayScreen()),
  Routes.sleep: (_) => const TabPage(child: SleepScreen()),
  Routes.strain: (_) => const TabPage(child: StrainScreen()),
  Routes.trends: (_) => const TabPage(child: TrendsScreen()),
  if (kDebugMode) Routes.gallery: (_) => const GalleryScreen(),
};

/// A shell tab body pushed as a page: the route owns the Scaffold (as the
/// shell does for the tab) and adds only a back button above the tab's own
/// header.
class TabPage extends StatelessWidget {
  const TabPage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: P.of(context).bg,
    appBar: AppBar(
      toolbarHeight: S.tap,
      actions: SampleDataChip.action(context),
    ),
    body: child,
  );
}

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final b = routeTable[settings.name];
  if (b == null) return null;
  return MaterialPageRoute<dynamic>(settings: settings, builder: b);
}

/// Unknown names land on the shell rather than a red error screen.
Route<dynamic> onUnknownRoute(RouteSettings settings) =>
    MaterialPageRoute<dynamic>(
      settings: settings,
      builder: routeTable[Routes.home]!,
    );
