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
  what,
  privacy,
  choose,
  rationale,
  requesting,
  denied,
  done,
}

class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.what,
    this.permissions,
    this.error,
    this.birthYear = '',
    this.busy = false,
  });
  final OnboardingStep step;

  /// Result of the last Health Connect request.
  final HcPermissionState? permissions;
  final String? error;
  final String birthYear;
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
    String? birthYear,
    bool? busy,
  }) => OnboardingState(
    step: step ?? this.step,
    permissions: permissions ?? this.permissions,
    error: clearError ? null : (error ?? this.error),
    birthYear: birthYear ?? this.birthYear,
    busy: busy ?? this.busy,
  );
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  /// The birth year typed on the choose step (asked once: it sets max HR).
  void setBirthYear(String v) =>
      state = state.copyWith(birthYear: v.trim(), clearError: true);

  bool _validBirthYear() {
    if (state.birthYear.isEmpty) return true;
    final y = int.tryParse(state.birthYear);
    final year = ref.read(clockProvider)().year;
    if (y != null && y >= year - 100 && y <= year - 18) return true;
    state = state.copyWith(
      error:
          'Airlog is for adults. Enter a birth year between '
          '${year - 100} and ${year - 18}, or leave it blank.',
    );
    return false;
  }

  /// Birth year is optional, but an entered value must be valid.
  Future<void> _saveBirthYear() async {
    final y = int.tryParse(state.birthYear);
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
      OnboardingStep.rationale ||
      OnboardingStep.denied => OnboardingStep.choose,
      final s => s,
    },
  );

  /// "Connect Health Connect": explain each data type before the system sheet.
  void showRationale() {
    if (state.busy || !_validBirthYear()) return;
    state = state.copyWith(step: OnboardingStep.rationale, clearError: true);
  }

  /// "Explore with demo data". Returns when the flag is stored.
  Future<void> chooseDemo() async {
    if (state.busy || !_validBirthYear()) return;
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
      state = state.copyWith(
        busy: false,
        error: 'Could not start sample data. Your choice was not completed. Try again.',
      );
    }
  }

  /// Opens the Health Connect permission sheet. On any grant the repository
  /// switches itself to live mode (first successful grant).
  Future<void> requestHealthConnect() async {
    if (state.step == OnboardingStep.requesting || !_validBirthYear()) return;
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
    try {
      await _saveBirthYear();
      await ref.read(onboardingStoreProvider).markSeen();
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        step: OnboardingStep.choose,
        error: 'Access was granted, but setup could not finish. Try again.',
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
