// The four-tab shell: Today · Sleep · Strain · Trends.
//
// Tabs are built lazily on first visit and then kept alive in an IndexedStack
// (state and scroll position preserved). Switching tabs has NO animation: it
// happens tens of times a day. Back from another tab returns to Today first.
// The selected tab survives process death (state restoration).
//
// First launch decides onboarding BEFORE Today draws: while the onboarding
// question is open the shell shows only the page colour, then either pushes
// onboarding or reveals the tabs, so the dashboard never flashes (QA-04).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/common/timing.dart';
import '../design/design.dart';
import '../features/onboarding/onboarding_view_model.dart'
    show maybeShowOnboarding, shouldShowOnboardingProvider;
import '../features/sleep/sleep_screen.dart';
import '../features/strain/strain_screen.dart';
import '../features/today/today_screen.dart';
import '../features/trends/trends_screen.dart';
import 'providers.dart';

enum AppTab {
  today('Today', Icons.wb_twilight_outlined, Icons.wb_twilight_rounded),
  sleep('Sleep', Icons.bedtime_outlined, Icons.bedtime_rounded),
  strain('Strain', Icons.bolt_outlined, Icons.bolt_rounded),
  trends('Trends', Icons.insights_outlined, Icons.insights_rounded);

  const AppTab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// The tab a [ShellTabs] id names (ids are stable across reorders).
  static AppTab ofId(int id) => switch (id) {
    ShellTabs.sleep => AppTab.sleep,
    ShellTabs.strain => AppTab.strain,
    ShellTabs.trends => AppTab.trends,
    _ => AppTab.today,
  };
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.initial = AppTab.today});
  final AppTab initial;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with RestorationMixin {
  late final _tabIndex = RestorableInt(widget.initial.index);
  late final Set<AppTab> _built = {widget.initial};

  AppTab get _tab => AppTab.values[_tabIndex.value];

  @override
  String? get restorationId => 'shell';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_tabIndex, 'tab');
    _built.add(_tab);
  }

  @override
  void dispose() {
    _tabIndex.dispose();
    super.dispose();
  }

  bool _asked = false;
  bool _gateMarked = false;

  /// Onboarding closed (with or without a choice): show the tabs.
  bool _closed = false;

  void _select(AppTab t) => setState(() {
    _tabIndex.value = t.index;
    _built.add(t);
  });

  Widget _body(AppTab t) => switch (t) {
    AppTab.today => const TodayScreen(),
    AppTab.sleep => const SleepScreen(),
    AppTab.strain => const StrainScreen(),
    AppTab.trends => const TrendsScreen(),
  };

  /// true = onboarding is (or will be) on top; null = still deciding.
  bool? _onboarding() {
    try {
      return ref
          .watch(shouldShowOnboardingProvider)
          .when(data: (v) => v, loading: () => null, error: (_, _) => false);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Screens ask for a tab (Today's Sleep tile → Sleep). [screens, additive]
    ref.listen<TabRequest?>(tabRequestProvider, (_, r) {
      if (r != null) _select(AppTab.ofId(r.index));
    });
    final p = P.of(context);
    final onboarding = _onboarding();
    if (onboarding != null && !_gateMarked) {
      _gateMarked = true;
      Timing.mark(onboarding ? 'gate_onboarding' : 'gate_tabs');
    }
    if (onboarding == true && !_asked) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await maybeShowOnboarding(context, ref);
        if (!mounted) return;
        ref.invalidate(shouldShowOnboardingProvider);
        setState(() => _closed = true);
      });
    }
    if (onboarding != false && !_closed) {
      // Deciding, or onboarding on top: the page colour only.
      return ColoredBox(color: p.bg, child: const SizedBox.expand());
    }
    return PopScope(
      canPop: _tab == AppTab.today,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(AppTab.today);
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: IndexedStack(
          index: _tab.index,
          children: [
            for (final t in AppTab.values)
              if (_built.contains(t)) _body(t) else const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: NavigationBar(
            selectedIndex: _tab.index,
            animationDuration: Motion.none,
            onDestinationSelected: (i) => _select(AppTab.values[i]),
            destinations: [
              for (final t in AppTab.values)
                NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: t.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
