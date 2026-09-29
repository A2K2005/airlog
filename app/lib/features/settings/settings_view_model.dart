// Settings view-model: data mode, a one-line summary of each source and the
// profile, export (repository → system share sheet) and delete-all.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../app/platform_services.dart';

/// App version shown in Settings. There is no package_info plugin in this
/// build, so it mirrors pubspec.yaml's `version:` (override at build time
/// with --dart-define=AIRLOG_VERSION=…).
const kAppVersion = String.fromEnvironment(
  'AIRLOG_VERSION',
  defaultValue: '1.0.0 (1)',
);

class SettingsState {
  const SettingsState({
    required this.mode,
    this.sources = const [],
    this.profile = const UserProfile(),
    this.busy,
  });
  final DataMode mode;
  final List<SourceStatus> sources;
  final UserProfile profile;

  /// 'export' | 'wipe' | 'mode' while running.
  final String? busy;

  SourceStatus? source(SourceKind k) {
    for (final s in sources) {
      if (s.kind == k) return s;
    }
    return null;
  }

  SettingsState copyWith({
    DataMode? mode,
    List<SourceStatus>? sources,
    UserProfile? profile,
    String? busy,
    bool idle = false,
  }) => SettingsState(
    mode: mode ?? this.mode,
    sources: sources ?? this.sources,
    profile: profile ?? this.profile,
    busy: idle ? null : (busy ?? this.busy),
  );

  /// "Connected · Enhanced mode not configured" style summary.
  String get sourcesSummary {
    final hc = source(SourceKind.healthConnect);
    final gh = source(SourceKind.googleHealthApi);
    final parts = <String>[
      if (mode == DataMode.demo) 'Demo data in use',
      if (hc != null)
        hc.connected
            ? 'Health Connect connected'
            : hc.available
            ? 'Health Connect not connected'
            : 'Health Connect unavailable',
      if (gh != null)
        !gh.available
            ? 'Enhanced mode not configured'
            : gh.connected
            ? 'Enhanced mode on'
            : 'Enhanced mode off',
    ];
    return parts.join(' · ');
  }

  String get profileSummary {
    final p = profile;
    final parts = <String>[
      if (p.birthYear != null) 'Born ${p.birthYear}' else 'No birth year',
      switch (p.sex) {
        Sex.female => 'Female',
        Sex.male => 'Male',
        Sex.unspecified => 'Sex not specified',
      },
      if (p.maxHrOverride != null) 'Max HR ${p.maxHrOverride!.round()}',
    ];
    return parts.join(' · ');
  }
}

/// Result of an export for the snack bar.
class ExportOutcome {
  const ExportOutcome({this.files = 0, this.error});
  final int files;
  final String? error;
  bool get ok => error == null;
}

class SettingsController extends AsyncNotifier<SettingsState> {
  @override
  Future<SettingsState> build() async {
    ref.watch(revisionProvider.select((r) => r.value));
    final repo = ref.watch(healthRepositoryProvider);
    var sources = const <SourceStatus>[];
    var profile = const UserProfile();
    try {
      sources = await repo.sources();
    } catch (_) {}
    try {
      profile = await repo.profile();
    } catch (_) {}
    return SettingsState(mode: repo.mode, sources: sources, profile: profile);
  }

  HealthRepository get _repo => ref.read(healthRepositoryProvider);

  Future<void> setMode(DataMode mode) async {
    final cur = state.value;
    if (cur == null || cur.mode == mode) return;
    state = AsyncData(cur.copyWith(mode: mode, busy: 'mode'));
    try {
      await _repo.setMode(mode);
    } catch (_) {}
    if (!ref.mounted) return;
    ref.invalidateSelf();
  }

  /// Writes CSV + JSON to the phone, then hands the files to the share sheet.
  Future<ExportOutcome> export() async {
    final cur = state.value;
    if (cur != null) state = AsyncData(cur.copyWith(busy: 'export'));
    try {
      final r = await _repo.exportAll();
      await ref
          .read(fileSharerProvider)
          .share(
            r.files,
            subject: 'Airlog export',
            text:
                'Airlog data export: raw readings and every score, as CSV '
                'and JSON.',
          );
      return ExportOutcome(files: r.files.length);
    } catch (e) {
      return ExportOutcome(error: '$e');
    } finally {
      if (ref.mounted && state.value != null) {
        state = AsyncData(state.value!.copyWith(idle: true));
      }
    }
  }

  Future<bool> wipe() async {
    final cur = state.value;
    if (cur != null) state = AsyncData(cur.copyWith(busy: 'wipe'));
    try {
      await _repo.wipeData();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (ref.mounted && state.value != null) {
        state = AsyncData(state.value!.copyWith(idle: true));
      }
    }
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider.autoDispose<SettingsController, SettingsState>(
      SettingsController.new,
      retry: noRetry,
    );
