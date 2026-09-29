// Sources view-model: each source's status, Health Connect permissions, the
// apps found in Health Connect with the one used per metric (any app,
// 2026-09-29), and the connect / disconnect / enable / choose actions.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../app/platform_services.dart';

class SourcesState {
  const SourcesState({
    required this.mode,
    required this.sources,
    this.hc,
    this.busy,
    this.apps = const [],
    this.choices = const {},
    this.hcDeniedTwice = false,
  });
  final DataMode mode;
  final List<SourceStatus> sources;
  final HcPermissionState? hc;

  /// Apps writing to Health Connect, with 14-day coverage per metric.
  final List<SourceApp> apps;

  /// The one app used per metric (automatic or pinned).
  final Map<Metric, SourceChoice> choices;

  /// The Health Connect sheet was denied twice: Android won't show it
  /// again, so offer "Open Health Connect settings" (QA-13).
  final bool hcDeniedTwice;

  /// The source kind whose action is running.
  final SourceKind? busy;

  SourceStatus? of(SourceKind k) {
    for (final s in sources) {
      if (s.kind == k) return s;
    }
    return null;
  }

  SourcesState copyWith({
    HcPermissionState? hc,
    SourceKind? busy,
    bool idle = false,
  }) => SourcesState(
    mode: mode,
    sources: sources,
    hc: hc ?? this.hc,
    busy: idle ? null : (busy ?? this.busy),
    apps: apps,
    choices: choices,
    hcDeniedTwice: hcDeniedTwice,
  );
}

class SourcesController extends AsyncNotifier<SourcesState> {
  @override
  Future<SourcesState> build() async {
    ref.watch(revisionProvider.select((r) => r.value));
    final repo = ref.watch(healthRepositoryProvider);
    final sources = await repo.sources();
    HcPermissionState? hc;
    try {
      hc = await repo.healthConnectPermissions();
    } catch (_) {}
    var apps = const <SourceApp>[];
    var choices = const <Metric, SourceChoice>{};
    try {
      apps = await repo.detectedSources();
      choices = await repo.sourceChoices();
    } catch (_) {}
    final denied = hc?.deniedTwice ?? false;
    return SourcesState(
      mode: repo.mode,
      sources: sources,
      hc: hc,
      apps: apps,
      choices: choices,
      hcDeniedTwice: denied,
    );
  }

  /// Uses [origin] for [metric] from now on and for its history (null:
  /// back to automatic). Scores are recomputed from the affected days.
  Future<void> chooseSource(Metric metric, String? origin) async {
    try {
      await _repo.setSourceChoice(metric, origin);
    } catch (_) {}
    if (ref.mounted) ref.invalidateSelf();
  }

  HealthRepository get _repo => ref.read(healthRepositoryProvider);

  void _busy(SourceKind? k) {
    final v = state.value;
    if (v == null) return;
    state = AsyncData(k == null ? v.copyWith(idle: true) : v.copyWith(busy: k));
  }

  /// Opens the system Health Connect sheet (after the rationale).
  Future<HcPermissionState?> requestHealthConnect() async {
    _busy(SourceKind.healthConnect);
    HcPermissionState? st;
    try {
      st = await _repo.requestHealthConnectPermissions();
    } catch (_) {}
    if (!ref.mounted) return st;
    ref.invalidateSelf();
    return st;
  }

  Future<bool> connectGoogle() async {
    _busy(SourceKind.googleHealthApi);
    var ok = false;
    try {
      ok = await _repo.connectGoogleHealth();
    } catch (_) {}
    if (ref.mounted) ref.invalidateSelf();
    return ok;
  }

  Future<void> disconnectGoogle() async {
    _busy(SourceKind.googleHealthApi);
    try {
      await _repo.disconnectGoogleHealth();
    } catch (_) {}
    if (ref.mounted) ref.invalidateSelf();
  }

  Future<void> setEnabled(SourceKind k, bool on) async {
    _busy(k);
    try {
      await _repo.setSourceEnabled(k, on);
    } catch (_) {}
    if (ref.mounted) ref.invalidateSelf();
  }
}

final sourcesControllerProvider =
    AsyncNotifierProvider.autoDispose<SourcesController, SourcesState>(
      SourcesController.new,
      retry: noRetry,
    );
