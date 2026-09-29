// Diagnostics (the Phase 0 probe): what actually reaches this phone, per data
// type and origin, and the design decisions it answers.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../app/platform_services.dart';

/// The Google Health (Fitbit) app's package. No longer the only origin read
/// (every app is; one per metric), kept for the screen's origin highlight.
const kFitbitOrigin = 'com.fitbit.FitbitMobile';

/// One metric's source for the probe (J): the app in use, its 14-day
/// coverage, and the other apps that also write the metric.
class MetricSourceRow {
  const MetricSourceRow({
    required this.metric,
    required this.chosen,
    required this.chosenDays,
    required this.automatic,
    this.since,
    this.alternatives = const {},
    this.suggested,
  });
  final Metric metric;

  /// Display name of the app in use.
  final String chosen;

  /// Days with data from it in the last 14.
  final int chosenDays;
  final bool automatic;
  final String? since;

  /// Other apps (display name) → their days with data in the last 14.
  final Map<String, int> alternatives;

  /// An app with fresher data the user may switch to.
  final String? suggested;
}

/// Joins [choices] with [detected] per metric (pure; tested).
List<MetricSourceRow> metricSourceRows(
  Map<Metric, SourceChoice> choices,
  List<SourceApp> detected,
) => [
  for (final m in Metric.values)
    if (choices[m] case final c?)
      MetricSourceRow(
        metric: m,
        chosen: c.displayName,
        chosenDays:
            detected
                .where((a) => a.origin == c.origin)
                .firstOrNull
                ?.daysWithData[m] ??
            0,
        automatic: c.automatic,
        since: c.since,
        suggested: c.suggestedDisplayName,
        alternatives: {
          for (final a in detected)
            if (a.origin != c.origin && (a.daysWithData[m] ?? 0) > 0)
              a.displayName: a.daysWithData[m]!,
        },
      ),
];

class DiagnosticsState {
  const DiagnosticsState({
    this.windowDays = 7,
    this.report,
    this.running = false,
    this.error,
    this.mode = DataMode.demo,
    this.sources = const [],
  });
  final int windowDays;
  final DiagnosticsReport? report;
  final bool running;
  final String? error;
  final DataMode mode;

  /// Per metric: the app in use, its coverage, the alternatives (live).
  final List<MetricSourceRow> sources;

  bool get demo => mode == DataMode.demo;

  DiagnosticsState copyWith({
    int? windowDays,
    DiagnosticsReport? report,
    bool? running,
    String? error,
    DataMode? mode,
    List<MetricSourceRow>? sources,
    bool clearError = false,
  }) => DiagnosticsState(
    windowDays: windowDays ?? this.windowDays,
    report: report ?? this.report,
    running: running ?? this.running,
    error: clearError ? null : (error ?? this.error),
    mode: mode ?? this.mode,
    sources: sources ?? this.sources,
  );
}

class DiagnosticsController extends Notifier<DiagnosticsState> {
  @override
  DiagnosticsState build() {
    var mode = DataMode.demo;
    try {
      mode = ref.read(healthRepositoryProvider).mode;
    } catch (_) {}
    return DiagnosticsState(mode: mode);
  }

  void setWindow(int days) => state = state.copyWith(windowDays: days);

  Future<void> run() async {
    if (state.running) return;
    state = state.copyWith(running: true, clearError: true);
    try {
      final repo = ref.read(healthRepositoryProvider);
      final r = await repo.diagnostics(windowDays: state.windowDays);
      var rows = const <MetricSourceRow>[];
      try {
        rows = metricSourceRows(
          await repo.sourceChoices(),
          await repo.detectedSources(),
        );
      } catch (_) {}
      if (!ref.mounted) return;
      state = state.copyWith(
        report: r,
        running: false,
        mode: repo.mode,
        sources: rows,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(running: false, error: '$e');
    }
  }

  /// Shares the full JSON dump. Returns false when there is none.
  Future<bool> share() async {
    final path = state.report?.rawJsonPath;
    if (path == null) return false;
    try {
      await ref
          .read(fileSharerProvider)
          .share(
            [path],
            subject: 'Airlog probe (${state.windowDays} days)',
            text: state.demo
                ? 'Airlog Phase 0 probe — SYNTHETIC demo data, not a real band.'
                : 'Airlog Phase 0 probe: what reaches the phone from the band.',
          );
      return true;
    } catch (_) {
      return false;
    }
  }
}

final diagnosticsControllerProvider =
    NotifierProvider.autoDispose<DiagnosticsController, DiagnosticsState>(
      DiagnosticsController.new,
      retry: noRetry,
    );

/// "HR density: 1 sample / 60 s → full zone-based strain" → finding + decision.
({String finding, String? decision, bool concern}) splitVerdict(String v) {
  final t = v.startsWith('Demo data: ') ? v.substring('Demo data: '.length) : v;
  final i = t.indexOf('→');
  final raw = (i < 0 ? t : t.substring(0, i)).trim();
  final finding = raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
  final decision = i < 0 ? null : t.substring(i + 1).trim();
  final lower = t.toLowerCase();
  final concern =
      lower.startsWith('no ') ||
      lower.contains('sparse') ||
      lower.contains('not granted') ||
      lower.contains('none from any app') ||
      lower.contains('none in health connect') ||
      lower.contains('not available');
  return (finding: finding, decision: decision, concern: concern);
}

/// Human spacing: "60 s", "5.0 min", "1.0 h".
String spacingWords(double s) => s < 90
    ? '${s.round()} s'
    : s < 5400
    ? '${(s / 60).toStringAsFixed(1)} min'
    : '${(s / 3600).toStringAsFixed(1)} h';
