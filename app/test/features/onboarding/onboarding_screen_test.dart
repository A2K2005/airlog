import 'dart:async';

import 'package:airlog/app/providers.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/onboarding/onboarding_screen.dart';
import 'package:airlog/features/onboarding/onboarding_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

const _granted = HcPermissionState(
  availability: HcAvailability.available,
  granted: ['HEART_RATE', 'SLEEP_SESSION'],
  missing: ['WEIGHT'],
);

/// A stand-in shell: calls the gate after its first frame, like AppShell.
class _Host extends ConsumerStatefulWidget {
  const _Host();
  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(maybeShowOnboarding(context, ref));
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('shell'));
}

/// A repository whose start-up never finishes.
class _NeverStarted extends ScreensBRepo {
  _NeverStarted(super.inner);
  @override
  Future<String?> latestDate() => Completer<String?>().future;
}

Future<void> _toChoose(WidgetTester t) async {
  await t.tap(find.text('Next'));
  await t.pumpAndSettle();
  await t.tap(find.text('Next'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(resetOnboardingGate);

  testWidgets('three steps, then demo: marks onboarding seen', (t) async {
    final store = MemoryOnboardingStore();
    await pumpB(
      t,
      const OnboardingScreen(),
      repo: ScreensBRepo.demo(),
      onboarding: store,
    );
    await t.pumpAndSettle();
    expect(find.text('Airlog'), findsOneWidget);
    expect(find.textContaining('Not medical.'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('It stays on this phone'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('How do you want to start?'), findsOneWidget);
    await t.tap(find.text('Try with sample data'));
    await t.pumpAndSettle();
    expect(store.seenValue, isTrue);
  });

  testWidgets('Health Connect: the rationale comes before the system sheet', (
    t,
  ) async {
    final store = MemoryOnboardingStore();
    final repo = ScreensBRepo.demo()..hcAfterRequest = _granted;
    await pumpB(t, const OnboardingScreen(), repo: repo, onboarding: store);
    await t.pumpAndSettle();
    await _toChoose(t);
    await t.tap(find.text('Connect Health Connect'));
    await t.pumpAndSettle();
    expect(find.text('What Airlog will read'), findsOneWidget);
    expect(find.textContaining('The main input to Recovery'), findsOneWidget);
    expect(repo.calls, isNot(contains('requestHealthConnectPermissions')));
    await t.tap(find.text('Continue to Health Connect'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('requestHealthConnectPermissions'));
    expect(store.seenValue, isTrue);
  });

  testWidgets('no Health Connect on the device: says so, offers demo', (
    t,
  ) async {
    final repo = ScreensBRepo.demo()
      ..hcAfterRequest = const HcPermissionState(
        availability: HcAvailability.unsupported,
        granted: [],
        missing: [],
      );
    final store = MemoryOnboardingStore();
    await pumpB(t, const OnboardingScreen(), repo: repo, onboarding: store);
    await t.pumpAndSettle();
    await _toChoose(t);
    await t.tap(find.text('Connect Health Connect'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue to Health Connect'));
    await t.pumpAndSettle();
    expect(find.text('Health Connect isn’t available here'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(store.seenValue, isFalse);
    await t.tap(find.text('Try with sample data instead'));
    await t.pumpAndSettle();
    expect(store.seenValue, isTrue);
  });

  test('gate: not seen → show (any mode); seen → not', () async {
    Future<bool> gate(DataMode mode, bool seen) async {
      final repo = ScreensBRepo.demo();
      await repo.setMode(mode);
      final c = ProviderContainer(
        overrides: [
          healthRepositoryProvider.overrideWithValue(repo),
          onboardingStoreProvider.overrideWithValue(
            MemoryOnboardingStore(seenValue: seen),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c.read(shouldShowOnboardingProvider.future);
    }

    expect(await gate(DataMode.demo, false), isTrue);

    // The gate never waits for the repository to start (QA-03/QA-04): a
    // start-up that hasn't finished still gets an answer at once.
    final late = _NeverStarted(ScreensBRepo.demo().inner);
    final c = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(late),
        onboardingStoreProvider.overrideWithValue(MemoryOnboardingStore()),
      ],
    );
    addTearDown(c.dispose);
    // A fresh install is live by default: the gate is "not yet seen" only.
    expect(
      await c
          .read(shouldShowOnboardingProvider.future)
          .timeout(const Duration(seconds: 1)),
      isTrue,
    );
    expect(await gate(DataMode.demo, true), isFalse);
    expect(await gate(DataMode.live, false), isTrue);
    expect(await gate(DataMode.live, true), isFalse);
  });

  test('the default store never shows onboarding under flutter test', () async {
    expect(await const FileOnboardingStore().seen(), isTrue);
  });

  testWidgets('the shell hook pushes onboarding once, only when due', (
    t,
  ) async {
    final store = MemoryOnboardingStore();
    await pumpB(t, const _Host(), repo: ScreensBRepo.demo(), onboarding: store);
    await t.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await t.binding.handlePopRoute(); // Android back
    await t.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);
    // Only a choice marks onboarding seen (QA-05): backing out offers it
    // again next launch.
    expect(store.seenValue, isFalse);

    // Seen: nothing is pushed.
    resetOnboardingGate();
    await pumpB(
      t,
      const _Host(),
      repo: ScreensBRepo.demo(),
      onboarding: MemoryOnboardingStore(seenValue: true),
    );
    await t.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('system Back steps back through the flow (QA-05)', (t) async {
    final store = MemoryOnboardingStore();
    await pumpB(t, const _Host(), repo: ScreensBRepo.demo(), onboarding: store);
    await t.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await _toChoose(t);
    expect(find.text('3 of 3'), findsOneWidget);

    await t.binding.handlePopRoute(); // Android back on step 3
    await t.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('2 of 3'), findsOneWidget);

    await t.binding.handlePopRoute(); // step 2 → step 1
    await t.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(store.seenValue, isFalse);

    await t.binding.handlePopRoute(); // step 1 leaves, without a choice
    await t.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('shell'), findsOneWidget);
    expect(store.seenValue, isFalse);
  });

  testWidgets('no overflow at 320 px and text scale 1.3', (t) async {
    await pumpB(
      t,
      const OnboardingScreen(),
      repo: ScreensBRepo.demo(),
      size: kSmall,
      textScale: 1.3,
    );
    await t.pumpAndSettle();
    await scrollThrough(t);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await scrollThrough(t);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await scrollThrough(t);
    await t.tap(find.text('Connect Health Connect'));
    await t.pumpAndSettle();
    await scrollThrough(t);
  });

  for (final b in const [Brightness.dark]) {
    // dark only
    testWidgets('golden what · ${b.name}', (t) async {
      await pumpB(
        t,
        const OnboardingScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/onboarding_what_${b.name}.png',
        ),
      );
    });

    testWidgets('golden choose · ${b.name}', (t) async {
      await pumpB(
        t,
        const OnboardingScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await _toChoose(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/onboarding_choose_${b.name}.png',
        ),
      );
    });

    testWidgets('golden rationale · ${b.name}', (t) async {
      await pumpB(
        t,
        const OnboardingScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await _toChoose(t);
      await t.tap(find.text('Connect Health Connect'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/onboarding_rationale_${b.name}.png',
        ),
      );
    });
  }
}
