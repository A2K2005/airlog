import 'dart:async';

import 'package:airlog/app/platform_services.dart';
import 'package:airlog/app/providers.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/onboarding/onboarding_copy.dart';
import 'package:airlog/features/onboarding/onboarding_screen.dart';
import 'package:airlog/features/onboarding/onboarding_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

const _granted = HcPermissionState(
  availability: HcAvailability.available,
  granted: ['HEART_RATE', 'SLEEP_SESSION'],
  missing: ['WEIGHT'],
);

const _deniedOnce = HcPermissionState(
  availability: HcAvailability.available,
  granted: [],
  missing: ['HEART_RATE'],
);

const _deniedTwice = HcPermissionState(
  availability: HcAvailability.available,
  granted: [],
  missing: ['HEART_RATE'],
  deniedTwice: true,
);

const _unsupported = HcPermissionState(
  availability: HcAvailability.unsupported,
  granted: [],
  missing: [],
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

/// A repository whose permission sheet stays open until [answer].
class _SheetOpen extends ScreensBRepo {
  _SheetOpen(super.inner);
  final _answer = Completer<HcPermissionState>();
  void answer(HcPermissionState st) => _answer.complete(st);

  @override
  Future<HcPermissionState> requestHealthConnectPermissions() {
    calls.add('requestHealthConnectPermissions');
    return _answer.future;
  }
}

Future<void> _toChoose(WidgetTester t) async {
  await t.tap(find.text(OnboardingCopy.getStarted));
  await t.pumpAndSettle();
  await t.tap(find.text(OnboardingCopy.next));
  await t.pumpAndSettle();
}

/// "Use my tracker" goes straight to Android's permission sheet.
Future<void> _toDenied(WidgetTester t) async {
  await _toChoose(t);
  await tapOn(t, find.text(OnboardingCopy.trackerTitle));
  await t.pumpAndSettle();
}

/// Every string on screen: text, and the labels given to screen readers.
List<String> _strings(WidgetTester t) => [
  for (final r in t.widgetList<RichText>(find.byType(RichText)))
    r.text.toPlainText(),
  for (final s in t.widgetList<Semantics>(find.byType(Semantics)))
    ?s.properties.label,
];

final _brands = RegExp(
  r'whoop|google|fitbit|oura|garmin|samsung|apple|polar|withings|claude|'
  r'gemini|anthropic|android|play store',
  caseSensitive: false,
);

void _expectNoBrands(WidgetTester t, String where) {
  for (final s in _strings(t)) {
    expect(_brands.hasMatch(s), isFalse, reason: '$where: "$s"');
  }
}

void main() {
  setUpAll(loadAppFonts);
  setUp(resetOnboardingGate);

  testWidgets('three steps, then sample data: marks onboarding seen', (
    t,
  ) async {
    final store = MemoryOnboardingStore();
    await pumpB(
      t,
      const OnboardingScreen(),
      repo: ScreensBRepo.demo(),
      onboarding: store,
    );
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.welcomeTitle), findsOneWidget);
    expect(find.text(OnboardingCopy.notMedical), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    await t.tap(find.text(OnboardingCopy.getStarted));
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.worksTitle), findsOneWidget);
    await t.tap(find.text(OnboardingCopy.next));
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.chooseTitle), findsOneWidget);
    expect(store.seenValue, isFalse);
    await tapOn(t, find.text(OnboardingCopy.sampleTitle));
    await t.pumpAndSettle();
    expect(store.seenValue, isTrue);
  });

  testWidgets('the welcome tile is clearly a sample', (t) async {
    final handle = t.ensureSemantics();
    await pumpB(t, const OnboardingScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    expect(find.byType(SampleDataChip), findsOneWidget);
    expect(find.bySemanticsLabel('Showing sample data'), findsOneWidget);
    expect(find.bySemanticsLabel(OnboardingCopy.heroLabel), findsOneWidget);
    handle.dispose();
  });

  testWidgets('score chips and the hero open plain ⓘ sheets', (t) async {
    await pumpB(t, const OnboardingScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();

    await t.tap(find.text(OnboardingCopy.recovery));
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.recoveryLede), findsOneWidget);
    expect(
      find.text(OnboardingCopy.recoveryZones('67', '34', '66')),
      findsOneWidget,
    );
    expect(find.text(OnboardingCopy.sheetFootnote), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    await t.tap(find.text(OnboardingCopy.heroTitle));
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.recoveryLede), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    await t.tap(find.text(OnboardingCopy.strain));
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.strainLede('21')), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    await t.tap(find.text(OnboardingCopy.sleep));
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.missedSleepBody), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    // Closing a sheet stays on the step.
    expect(find.text(OnboardingCopy.welcomeTitle), findsOneWidget);
  });

  testWidgets('"Use my tracker" opens the permission sheet directly', (
    t,
  ) async {
    final store = MemoryOnboardingStore();
    final repo = ScreensBRepo.demo()..hcAfterRequest = _granted;
    await pumpB(t, const OnboardingScreen(), repo: repo, onboarding: store);
    await t.pumpAndSettle();
    await _toChoose(t);
    expect(repo.calls, isNot(contains('requestHealthConnectPermissions')));
    await tapOn(t, find.text(OnboardingCopy.trackerTitle));
    await t.pumpAndSettle();
    // No screen of our own in between: Android's sheet lists each type.
    expect(repo.calls, contains('requestHealthConnectPermissions'));
    expect(store.seenValue, isTrue);
  });

  testWidgets('while the permission sheet is open, the choices wait', (
    t,
  ) async {
    final store = MemoryOnboardingStore();
    final repo = _SheetOpen(ScreensBRepo.demo().inner);
    await pumpB(t, const OnboardingScreen(), repo: repo, onboarding: store);
    await t.pumpAndSettle();
    await _toChoose(t);
    await tapOn(t, find.text(OnboardingCopy.trackerTitle));
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.chooseTitle), findsOneWidget);
    expect(find.text(OnboardingCopy.waitingForHc), findsOneWidget);
    // A second tap on either tile does nothing while the sheet is open.
    await t.tap(find.text(OnboardingCopy.sampleTitle));
    await t.tap(find.text(OnboardingCopy.trackerTitle));
    await t.pumpAndSettle();
    expect(
      repo.calls.where((c) => c == 'requestHealthConnectPermissions'),
      hasLength(1),
    );
    expect(store.seenValue, isFalse);
    repo.answer(_granted);
    await t.pumpAndSettle();
    expect(store.seenValue, isTrue);
  });

  testWidgets('no Health Connect on the device: says so, offers sample data', (
    t,
  ) async {
    final repo = ScreensBRepo.demo()..hcAfterRequest = _unsupported;
    final store = MemoryOnboardingStore();
    await pumpB(t, const OnboardingScreen(), repo: repo, onboarding: store);
    await t.pumpAndSettle();
    await _toDenied(t);
    expect(find.text(OnboardingCopy.unsupportedTitle), findsOneWidget);
    expect(find.text(OnboardingCopy.tryAgain), findsNothing);
    expect(store.seenValue, isFalse);
    await t.tap(find.text(OnboardingCopy.trySampleInstead));
    await t.pumpAndSettle();
    expect(store.seenValue, isTrue);
  });

  testWidgets('denied once: "Try again" asks again', (t) async {
    final repo = ScreensBRepo.demo()..hcAfterRequest = _deniedOnce;
    await pumpB(t, const OnboardingScreen(), repo: repo);
    await t.pumpAndSettle();
    await _toDenied(t);
    expect(find.text(OnboardingCopy.nothingSharedTitle), findsOneWidget);
    expect(find.text(OnboardingCopy.nothingSharedBody), findsOneWidget);
    expect(find.text(OnboardingCopy.openHcSettings), findsNothing);
    await t.tap(find.text(OnboardingCopy.tryAgain));
    await t.pumpAndSettle();
    expect(
      repo.calls.where((c) => c == 'requestHealthConnectPermissions'),
      hasLength(2),
    );
  });

  testWidgets('denied twice: opens Health Connect settings (QA-06); a grant '
      'made there finishes on resume', (t) async {
    final opened = <Uri>[];
    final store = MemoryOnboardingStore();
    final repo = ScreensBRepo.demo()..hcAfterRequest = _deniedTwice;
    await pumpB(
      t,
      const OnboardingScreen(),
      repo: repo,
      onboarding: store,
      extra: [
        linkOpenerProvider.overrideWithValue((u) async {
          opened.add(u);
          return true;
        }),
      ],
    );
    await t.pumpAndSettle();
    await _toDenied(t);
    expect(find.text(OnboardingCopy.deniedTwiceBody), findsOneWidget);
    expect(find.text(OnboardingCopy.tryAgain), findsNothing);
    await t.tap(find.text(OnboardingCopy.openHcSettings));
    await t.pumpAndSettle();
    expect(opened, [hcSettingsUri]);

    // Nothing granted in settings: still not connected.
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.deniedTitle), findsOneWidget);
    expect(store.seenValue, isFalse);

    // Granted in settings: back in the app, onboarding finishes, live.
    repo.hcState = _granted;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(store.seenValue, isTrue);
    expect(repo.calls, contains('setMode:live'));
  });

  testWidgets('birth year: a bounded wheel, saved only with the choice', (
    t,
  ) async {
    final repo = ScreensBRepo.demo();
    await pumpB(t, const OnboardingScreen(), repo: repo);
    await t.pumpAndSettle();
    await _toChoose(t);

    // Before the choices in reading order: they commit on tap.
    final add = find.bySemanticsLabel(OnboardingCopy.birthYearAddLabel);
    expect(
      t.getRect(add).top,
      lessThan(t.getRect(find.text(OnboardingCopy.trackerTitle)).top),
    );
    expect(find.text(OnboardingCopy.birthYearCaption), findsOneWidget);

    await t.tap(find.text(OnboardingCopy.birthYearAdd));
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.sheetTitle), findsOneWidget);
    // kNow is 2026: 1926…2008, opening on 1996.
    final wheel = t.widget<ListWheelScrollView>(
      find.byType(ListWheelScrollView),
    );
    final delegate = wheel.childDelegate as ListWheelChildBuilderDelegate;
    expect(delegate.childCount, 2008 - 1926 + 1);
    expect(
      (wheel.controller! as FixedExtentScrollController).selectedItem,
      1996 - 1926,
    );
    expect(find.text(OnboardingCopy.removeBirthYear), findsNothing);
    await t.tap(find.text(OnboardingCopy.save));
    await t.pumpAndSettle();
    expect(find.text('1996'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('saveProfile')), isEmpty);

    // Remove it again.
    await t.tap(find.text('1996'));
    await t.pumpAndSettle();
    await t.tap(find.text(OnboardingCopy.removeBirthYear));
    await t.pumpAndSettle();
    expect(find.text(OnboardingCopy.birthYearAdd), findsOneWidget);

    // Set, then choose: the year is written with the choice.
    await t.tap(find.text(OnboardingCopy.birthYearAdd));
    await t.pumpAndSettle();
    await t.tap(find.text(OnboardingCopy.save));
    await t.pumpAndSettle();
    await tapOn(t, find.text(OnboardingCopy.sampleTitle));
    await t.pumpAndSettle();
    expect(repo.profileOverride?.birthYear, 1996);
  });

  testWidgets('birth year: the wheel is one adjustable control', (t) async {
    final handle = t.ensureSemantics();
    await pumpB(t, const OnboardingScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    await _toChoose(t);
    await t.tap(find.text(OnboardingCopy.birthYearAdd));
    await t.pumpAndSettle();
    final wheel = find.bySemanticsLabel(OnboardingCopy.birthYear);
    SemanticsNode node() => t.getSemantics(wheel);
    Future<void> increase() async {
      final n = node();
      n.owner!.performAction(n.id, SemanticsAction.increase);
      await t.pumpAndSettle();
    }

    expect(node().value, '1996');
    await increase();
    expect(node().value, '1997');
    for (var i = 0; i < 20; i++) {
      if (!node().getSemanticsData().hasAction(SemanticsAction.increase)) {
        break;
      }
      await increase();
    }
    expect(node().value, '2008');
    expect(
      node().getSemanticsData().hasAction(SemanticsAction.increase),
      isFalse,
    );
    handle.dispose();
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

  testWidgets('reduced motion: pages fade, nothing slides', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpB(t, const OnboardingScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    await t.tap(find.text(OnboardingCopy.getStarted));
    await t.pump();
    final switcher = find.byType(AnimatedSwitcher).first;
    expect(
      find.descendant(of: switcher, matching: find.byType(SlideTransition)),
      findsNothing,
    );
    await t.pump(Motion.fast);
    await t.pump();
    expect(find.text(OnboardingCopy.worksTitle), findsOneWidget);
    expect(find.text(OnboardingCopy.welcomeTitle), findsNothing);
  });

  testWidgets('no brand names anywhere in the flow', (t) async {
    final repo = ScreensBRepo.demo()..hcAfterRequest = _deniedTwice;
    await pumpB(
      t,
      const OnboardingScreen(),
      repo: repo,
      size: const Size(412, 2400),
    );
    await t.pumpAndSettle();
    _expectNoBrands(t, 'welcome');
    for (final chip in [
      OnboardingCopy.recovery,
      OnboardingCopy.strain,
      OnboardingCopy.sleep,
    ]) {
      await t.tap(find.text(chip));
      await t.pumpAndSettle();
      _expectNoBrands(t, '$chip sheet');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
    }
    await t.tap(find.text(OnboardingCopy.getStarted));
    await t.pumpAndSettle();
    _expectNoBrands(t, 'works with');
    await t.tap(find.text(OnboardingCopy.next));
    await t.pumpAndSettle();
    _expectNoBrands(t, 'choose');
    await t.tap(find.bySemanticsLabel('About birth year'));
    await t.pumpAndSettle();
    _expectNoBrands(t, 'birth year ⓘ');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(find.text(OnboardingCopy.birthYearAdd));
    await t.pumpAndSettle();
    _expectNoBrands(t, 'birth year sheet');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(find.text(OnboardingCopy.trackerTitle));
    await t.pumpAndSettle();
    _expectNoBrands(t, 'denied twice');

    for (final st in const [
      HcPermissionState(
        availability: HcAvailability.notInstalled,
        granted: [],
        missing: [],
      ),
      HcPermissionState(
        availability: HcAvailability.updateRequired,
        granted: [],
        missing: [],
      ),
      _deniedOnce,
      _unsupported,
    ]) {
      repo.hcAfterRequest = st;
      await t.tap(find.text(OnboardingCopy.back));
      await t.pumpAndSettle();
      await t.tap(find.text(OnboardingCopy.trackerTitle));
      await t.pumpAndSettle();
      _expectNoBrands(t, 'denied ${st.availability.name}');
    }
  });

  testWidgets('the denied card is announced', (t) async {
    final repo = ScreensBRepo.demo()..hcAfterRequest = _deniedOnce;
    await pumpB(t, const OnboardingScreen(), repo: repo);
    await t.pumpAndSettle();
    await _toDenied(t);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
      findsOneWidget,
    );
  });

  for (final scale in const [1.3, 2.0]) {
    testWidgets('no overflow at 320 px and text scale $scale', (t) async {
      final repo = ScreensBRepo.demo()..hcAfterRequest = _deniedTwice;
      await pumpB(
        t,
        const OnboardingScreen(),
        repo: repo,
        size: kSmall,
        textScale: scale,
      );
      await t.pumpAndSettle();
      if (scale > 1.3) {
        // The hero falls back to its readable text card.
        expect(find.textContaining('Sample Recovery'), findsOneWidget);
      }
      await tapOn(t, find.text(OnboardingCopy.recovery));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await scrollThrough(t);
      await t.tap(find.text(OnboardingCopy.getStarted));
      await t.pumpAndSettle();
      await scrollThrough(t);
      await t.tap(find.text(OnboardingCopy.next));
      await t.pumpAndSettle();
      await tapOn(t, find.text(OnboardingCopy.birthYearAdd));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await scrollThrough(t);
      final list = t.state<ScrollableState>(find.byType(Scrollable).first);
      list.position.jumpTo(0);
      await t.pump();
      await tapOn(t, find.text(OnboardingCopy.trackerTitle));
      await t.pumpAndSettle();
      expect(find.text(OnboardingCopy.deniedTitle), findsOneWidget);
      await scrollThrough(t);
    });
  }

  testWidgets('right-to-left: no overflow on the three steps', (t) async {
    await pumpB(t, const OnboardingScreen(), repo: ScreensBRepo.demo());
    // Re-pump under an RTL directionality.
    final app = t.widget<ProviderScope>(find.byType(ProviderScope));
    await t.pumpWidget(
      Directionality(textDirection: TextDirection.rtl, child: app),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text(OnboardingCopy.getStarted));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text(OnboardingCopy.next));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  // ── goldens (dark only) ─────────────────────────────────────────────────
  Future<void> golden(WidgetTester t, String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../../goldens/screens/onboarding_${name}_dark.png'),
  );

  testWidgets('golden welcome', (t) async {
    await pumpB(t, const OnboardingScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    await golden(t, 'welcome');
  });

  testWidgets('golden welcome at 2x text', (t) async {
    await pumpB(
      t,
      const OnboardingScreen(),
      repo: ScreensBRepo.demo(),
      textScale: 2,
    );
    await t.pumpAndSettle();
    await golden(t, 'welcome_text2x');
  });

  testWidgets('golden sources', (t) async {
    await pumpB(t, const OnboardingScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    await t.tap(find.text(OnboardingCopy.getStarted));
    await t.pumpAndSettle();
    await golden(t, 'sources');
  });

  testWidgets('golden choose', (t) async {
    await pumpB(t, const OnboardingScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    await _toChoose(t);
    await golden(t, 'choose');
  });

  testWidgets('golden birth year sheet', (t) async {
    await pumpB(t, const OnboardingScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    await _toChoose(t);
    await t.tap(find.text(OnboardingCopy.birthYearAdd));
    await t.pumpAndSettle();
    await golden(t, 'birthyear');
  });

  testWidgets('golden denied', (t) async {
    final repo = ScreensBRepo.demo()..hcAfterRequest = _deniedOnce;
    await pumpB(t, const OnboardingScreen(), repo: repo);
    await t.pumpAndSettle();
    await _toDenied(t);
    await golden(t, 'denied');
  });

  testWidgets('golden denied twice', (t) async {
    final repo = ScreensBRepo.demo()..hcAfterRequest = _deniedTwice;
    await pumpB(t, const OnboardingScreen(), repo: repo);
    await t.pumpAndSettle();
    await _toDenied(t);
    await golden(t, 'denied_twice');
  });
}
