// Onboarding: the first-launch gate and the three-step flow's view-model.
//
// Gate (the "has the user seen onboarding?" flag). The repository has no
// settings API, so the flag is a one-byte marker file in the app-support
// directory, behind [OnboardingStore]. It is shown when the store says it
// has not been seen: only a choice (Connect, or sample data) marks it seen.
// Any failure reading the flag counts as "seen": onboarding is a courtesy,
// never a wall. The default store also reports "seen" under `flutter test`,
// so no other suite ever gets onboarding pushed over its screen; tests that
// exercise the gate override [onboardingStoreProvider].
//
// The shell calls [maybeShowOnboarding] once after its first frame; it does
// nothing when another route is already on top (e.g. a cold start on
// /privacy from Health Connect).

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../domain/models.dart' show UserProfile;
import '../../domain/repositories.dart';
import '../../app/platform_services.dart';
import 'onboarding_copy.dart';

abstract class OnboardingStore {
  Future<bool> seen();
  Future<void> markSeen();
}

class FileOnboardingStore implements OnboardingStore {
  const FileOnboardingStore();

  static const _name = 'onboarding_seen';

  Future<File> _file() async =>
      File(p.join((await getApplicationSupportDirectory()).path, _name));

  static bool get _underTest => Platform.environment['FLUTTER_TEST'] == 'true';

  @override
  Future<bool> seen() async {
    if (_underTest) return true;
    try {
      return await (await _file()).exists();
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> markSeen() async {
    if (_underTest) return;
    try {
      final f = await _file();
      await f.create(recursive: true);
      await f.writeAsString('1');
    } catch (_) {}
  }
}

final onboardingStoreProvider = Provider<OnboardingStore>(
  (ref) => const FileOnboardingStore(),
);

/// Whether the first-launch onboarding should be pushed now.
///
/// Gated only on the user never having made their choice (Connect or sample
/// data): a fresh install is live by default, so the data mode doesn't
/// matter. The gate deliberately does NOT wait for the repository to start
/// (database open, a demo re-seed): the shell shows only the page colour
/// until this resolves, so waiting here delayed every cold start by the
/// whole repository start-up (QA-03 / QA-04).
final shouldShowOnboardingProvider = FutureProvider<bool>((ref) async {
  try {
    return !(await ref.watch(onboardingStoreProvider).seen());
  } catch (_) {
    return false;
  }
}, retry: noRetry);

bool _pushedThisProcess = false;

/// Called by the shell after its first frame. Pushes /onboarding at most once
/// per process, and only when the shell is the top route.
Future<void> maybeShowOnboarding(BuildContext context, WidgetRef ref) async {
  if (_pushedThisProcess) return;
  bool show;
  try {
    show = await ref.read(shouldShowOnboardingProvider.future);
  } catch (_) {
    return;
  }
  if (!show || !context.mounted) return;
  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) return;
  _pushedThisProcess = true;
  await Navigator.of(context).pushNamed(Routes.onboarding);
}

/// Test hook: forget that onboarding was pushed in this process.
@visibleForTesting
void resetOnboardingGate() => _pushedThisProcess = false;

// ── the flow ─────────────────────────────────────────────────────────────

enum OnboardingStep {
  /// 1 · Welcome: the sample Recovery tile and the three scores.
  what,

  /// 2 · Works with your tracker: Health Connect and the privacy promises.
  privacy,

  /// 3 · How do you want to start: birth year, then the two choices.
  choose,

  /// The system permission sheet is open ("Use my tracker" or "Try
  /// again"): the page stays where it was, its choices disabled.
  requesting,

  /// 3b · Not connected.
  denied,
  done,
}

/// The years the birth-year wheel offers: adults only, at most 100 years
/// old, starting on [initial]. Built from the injected clock.
class BirthYearRange {
  const BirthYearRange({
    required this.min,
    required this.max,
    required this.initial,
  });

  factory BirthYearRange.at(DateTime now) => BirthYearRange(
    min: now.year - 100,
    max: now.year - 18,
    initial: now.year - 30,
  );

  final int min, max, initial;

  int get count => max - min + 1;
  bool contains(int y) => y >= min && y <= max;
}

class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.what,
    this.permissions,
    this.error,
    this.birthYear,
    this.busy = false,
  });
  final OnboardingStep step;

  /// Result of the last Health Connect request.
  final HcPermissionState? permissions;
  final String? error;

  /// Picked on the choose step; written to the profile only with a choice.
  final int? birthYear;
  final bool busy;

  int get page => switch (step) {
    OnboardingStep.what => 0,
    OnboardingStep.privacy => 1,
    _ => 2,
  };

  OnboardingState copyWith({
    OnboardingStep? step,
    HcPermissionState? permissions,
    String? error,
    bool clearError = false,
    int? birthYear,
    bool clearBirthYear = false,
    bool? busy,
  }) => OnboardingState(
    step: step ?? this.step,
    permissions: permissions ?? this.permissions,
    error: clearError ? null : (error ?? this.error),
    birthYear: clearBirthYear ? null : (birthYear ?? this.birthYear),
    busy: busy ?? this.busy,
  );
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  /// The years the wheel offers, from the injected clock.
  BirthYearRange birthYearRange() =>
      BirthYearRange.at(ref.read(clockProvider)());

  /// The birth year picked on the choose step (asked once: it sets max HR).
  /// Null clears it.
  void setBirthYear(int? year) => state = year == null
      ? state.copyWith(clearBirthYear: true, clearError: true)
      : state.copyWith(birthYear: year, clearError: true);

  /// A backstop: the wheel only offers valid years.
  bool _validBirthYear() {
    final y = state.birthYear;
    if (y == null) return true;
    final r = birthYearRange();
    if (r.contains(y)) return true;
    state = state.copyWith(error: OnboardingCopy.adultsOnly(r.min, r.max));
    return false;
  }

  /// Birth year is optional; written with the choice, never before it.
  Future<void> _saveBirthYear() async {
    final y = state.birthYear;
    if (y == null) return;
    final repo = ref.read(healthRepositoryProvider);
    final p = await repo.profile();
    await repo.saveProfile(
      UserProfile(
        birthYear: y,
        sex: p.sex,
        maxHrOverride: p.maxHrOverride,
        weightKg: p.weightKg,
      ),
    );
  }

  void next() => state = state.copyWith(
    step: switch (state.step) {
      OnboardingStep.what => OnboardingStep.privacy,
      OnboardingStep.privacy => OnboardingStep.choose,
      final s => s,
    },
  );

  void back() => state = state.copyWith(
    clearError: true,
    step: switch (state.step) {
      OnboardingStep.privacy => OnboardingStep.what,
      OnboardingStep.choose => OnboardingStep.privacy,
      OnboardingStep.denied => OnboardingStep.choose,
      final s => s,
    },
  );

  /// "Try sample data". Returns when the flag is stored.
  Future<void> chooseDemo() async {
    if (state.busy ||
        state.step == OnboardingStep.requesting ||
        !_validBirthYear()) {
      return;
    }
    state = state.copyWith(busy: true, clearError: true);
    final repo = ref.read(healthRepositoryProvider);
    try {
      await _saveBirthYear();
      if (repo.mode != DataMode.demo) await repo.setMode(DataMode.demo);
      await ref.read(onboardingStoreProvider).markSeen();
      if (!ref.mounted) return;
      state = state.copyWith(step: OnboardingStep.done, busy: false);
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, error: OnboardingCopy.sampleFailed);
    }
  }

  /// "Use my tracker" (and "Try again"): opens Android's Health Connect
  /// permission sheet directly. The sheet lists every data type with its own
  /// switch, so there is no screen of our own before it. On any grant the
  /// repository switches itself to live mode (first successful grant).
  Future<void> requestHealthConnect() async {
    if (state.busy ||
        state.step == OnboardingStep.requesting ||
        !_validBirthYear()) {
      return;
    }
    state = state.copyWith(step: OnboardingStep.requesting, clearError: true);
    HcPermissionState st;
    try {
      st = await ref
          .read(healthRepositoryProvider)
          .requestHealthConnectPermissions();
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(step: OnboardingStep.denied, error: '$e');
      return;
    }
    if (!ref.mounted) return;
    if (st.granted.isEmpty) {
      state = state.copyWith(step: OnboardingStep.denied, permissions: st);
      return;
    }
    await _finishWithGrant(st);
  }

  /// Back from Health Connect's settings (or the app store) while "Not
  /// connected" shows: read the permissions again. A grant made there
  /// finishes onboarding; otherwise the card and buttons follow the new
  /// state (an install turns "isn't installed" into "Try again").
  Future<void> recheckPermissions() async {
    if (state.step != OnboardingStep.denied || state.busy) return;
    final repo = ref.read(healthRepositoryProvider);
    HcPermissionState st;
    try {
      st = await repo.healthConnectPermissions();
    } catch (_) {
      return;
    }
    if (!ref.mounted || state.step != OnboardingStep.denied) return;
    if (st.granted.isEmpty) {
      state = state.copyWith(permissions: st, clearError: true);
      return;
    }
    // Granted outside the system sheet, so the repository's first-grant
    // switch did not run: switch to live here (or sync, when already live).
    try {
      if (repo.mode != DataMode.live) {
        await repo.setMode(DataMode.live);
      } else {
        unawaited(repo.syncNow().catchError((Object _) {}));
      }
    } catch (_) {}
    if (!ref.mounted) return;
    await _finishWithGrant(st);
  }

  /// Any grant (the system sheet, or settings then resume): save the birth
  /// year and mark onboarding seen.
  Future<void> _finishWithGrant(HcPermissionState st) async {
    try {
      await _saveBirthYear();
      await ref.read(onboardingStoreProvider).markSeen();
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        step: OnboardingStep.choose,
        error: OnboardingCopy.setupFailed,
      );
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(step: OnboardingStep.done, permissions: st);
  }
}

final onboardingControllerProvider =
    NotifierProvider.autoDispose<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );
