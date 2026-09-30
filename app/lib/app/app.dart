// The app: the dark theme, the router and the shell.
//
// No `initialRoute:` on purpose: MaterialApp then uses the platform's
// defaultRouteName, which is how Android lands on '/privacy' when Health
// Connect opens the app from its permissions screen.
//
// Dark only, like the design: [themeMode] is accepted for source
// compatibility (tests pinned light or dark) and every mode gets the dark
// theme. The app root also provides the data mode (SampleDataScope) for the
// data-mode screens (Settings, Data sources), the only ones that label it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/design.dart';
import '../domain/repositories.dart' show DataMode;
import 'providers.dart';
import 'routes.dart';

class AirlogApp extends StatelessWidget {
  const AirlogApp({super.key, this.themeMode = ThemeMode.dark});

  /// Ignored: the app is dark only.
  final ThemeMode themeMode;

  static final _dark = buildTheme();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Airlog',
    debugShowCheckedModeBanner: false,
    theme: _dark,
    darkTheme: _dark,
    themeMode: ThemeMode.dark,
    restorationScopeId: 'airlog',
    onGenerateRoute: onGenerateRoute,
    onUnknownRoute: onUnknownRoute,
    builder: (context, child) =>
        _SampleData(child: child ?? const SizedBox.shrink()),
  );
}

/// Provides [SampleDataScope] from the repository's mode. Defensive: the app
/// must render before (and without) a data layer.
class _SampleData extends ConsumerWidget {
  const _SampleData({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var demo = false;
    try {
      demo = ref.watch(dataModeProvider) == DataMode.demo;
    } catch (_) {}
    return SampleDataScope(demo: demo, child: child);
  }
}
