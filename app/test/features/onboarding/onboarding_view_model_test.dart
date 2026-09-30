import 'package:airlog/app/providers.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/onboarding/onboarding_copy.dart';
import 'package:airlog/features/onboarding/onboarding_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/screens_b_fixtures.dart';

void main() {
  (ProviderContainer, ScreensBRepo, MemoryOnboardingStore) setUpVm({
    HcPermissionState? afterRequest,
  }) {
    final repo = ScreensBRepo.demo()..hcAfterRequest = afterRequest;
    final store = MemoryOnboardingStore();
    final c = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => kNow),
        onboardingStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(c.dispose);
    // Keep the auto-dispose controller alive for the test.
    c.listen(onboardingControllerProvider, (_, _) {});
    return (c, repo, store);
  }

  test('the birth-year range comes from the clock: 18 to 100', () {
    final (c, _, _) = setUpVm();
    final r = c.read(onboardingControllerProvider.notifier).birthYearRange();
    expect(r.min, kNow.year - 100);
    expect(r.max, kNow.year - 18);
    expect(r.initial, kNow.year - 30);
    expect(r.count, 83);
    expect(r.contains(r.max + 1), isFalse);
  });

  test('setBirthYear sets and clears', () {
    final (c, _, _) = setUpVm();
    final vm = c.read(onboardingControllerProvider.notifier);
    vm.setBirthYear(1990);
    expect(c.read(onboardingControllerProvider).birthYear, 1990);
    vm.setBirthYear(null);
    expect(c.read(onboardingControllerProvider).birthYear, isNull);
  });

  test('the guard still rejects a year outside the range', () async {
    final (c, repo, store) = setUpVm();
    final vm = c.read(onboardingControllerProvider.notifier);
    vm.setBirthYear(kNow.year - 10);
    await vm.chooseDemo();
    final s = c.read(onboardingControllerProvider);
    expect(s.error, OnboardingCopy.adultsOnly(kNow.year - 100, kNow.year - 18));
    expect(s.step, OnboardingStep.what);
    expect(store.seenValue, isFalse);
    expect(repo.calls.where((x) => x.startsWith('saveProfile')), isEmpty);
  });

  test('seen only after a choice; the year is written with it', () async {
    final (c, repo, store) = setUpVm();
    final vm = c.read(onboardingControllerProvider.notifier);
    vm
      ..next()
      ..next()
      ..setBirthYear(1990);
    expect(store.seenValue, isFalse);
    expect(repo.calls.where((x) => x.startsWith('saveProfile')), isEmpty);
    await vm.chooseDemo();
    expect(store.seenValue, isTrue);
    expect(repo.profileOverride?.birthYear, 1990);
    expect(c.read(onboardingControllerProvider).step, OnboardingStep.done);
  });

  test('resume re-check: nothing granted keeps "Not connected"', () async {
    const denied = HcPermissionState(
      availability: HcAvailability.available,
      granted: [],
      missing: ['HEART_RATE'],
      deniedTwice: true,
    );
    final (c, repo, store) = setUpVm(afterRequest: denied);
    final vm = c.read(onboardingControllerProvider.notifier);
    await vm.requestHealthConnect();
    expect(c.read(onboardingControllerProvider).step, OnboardingStep.denied);
    await vm.recheckPermissions();
    expect(c.read(onboardingControllerProvider).step, OnboardingStep.denied);
    expect(store.seenValue, isFalse);

    repo.hcState = const HcPermissionState(
      availability: HcAvailability.available,
      granted: ['HEART_RATE'],
      missing: [],
    );
    await vm.recheckPermissions();
    expect(c.read(onboardingControllerProvider).step, OnboardingStep.done);
    expect(store.seenValue, isTrue);
    expect(repo.calls, contains('setMode:live'));
  });

  test('resume re-check does nothing outside "Not connected"', () async {
    final (c, repo, store) = setUpVm();
    repo.hcState = const HcPermissionState(
      availability: HcAvailability.available,
      granted: ['HEART_RATE'],
      missing: [],
    );
    await c.read(onboardingControllerProvider.notifier).recheckPermissions();
    expect(c.read(onboardingControllerProvider).step, OnboardingStep.what);
    expect(store.seenValue, isFalse);
  });
}
