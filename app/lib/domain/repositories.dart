// Repository interfaces — the boundary between presentation and data.
//
// CONTRACT FILE (Clean Architecture: interfaces live in the domain, the data
// layer implements them). data/ implements [HealthRepository] and
// [LiveHrService]; features/ reach them only through Riverpod providers in
// app/providers.dart. Pure Dart (Streams, no Flutter imports) so the domain
// stays testable without a device. Additive changes only (ARCHITECTURE.md).

import 'models.dart';
import 'results.dart';

/// Why the repository couldn't serve a read. [additive 2026-09-29, QA-01]
enum DataErrorKind {
  /// The local database failed (closed, locked, corrupt).
  storage,
}

/// Typed read failure, so screens never show a raw DatabaseException. The
/// UI owns the final wording; [userMessage] is a plain default.
class DataUnavailableException implements Exception {
  const DataUnavailableException(this.kind, [this.detail]);
  final DataErrorKind kind;

  /// Technical detail for logs and diagnostics, never for display.
  final String? detail;

  String get userMessage => switch (kind) {
    DataErrorKind.storage =>
      "Airlog couldn't open its data on this phone. Close and reopen the app.",
  };

  @override
  String toString() => 'DataUnavailableException(${kind.name})';
}

/// Demo = seeded synthetic "Fitbit Air" (no band needed). Live = real sources.
enum DataMode { demo, live }

/// One day as the UI sees it: the resolved inputs plus the computed scores.
class DayBundle {
  const DayBundle(this.record, this.result);
  final DayRecord record;
  final DayResult result;
  String get date => record.date;
}

enum SyncPhase { idle, syncing, error }

class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.lastSyncAt,
    this.lastDataAt,
    this.message,
    this.lastDataByApp = const {},
  });
  final SyncPhase phase;
  final DateTime? lastSyncAt;

  /// Newest raw datum from any source (the "last data received" line).
  final DateTime? lastDataAt;
  final String? message;

  /// Display name of each source app → its newest datum, for one freshness
  /// line per source ("Samsung Health · 2 h ago"). Apps write to Health
  /// Connect on their own schedules.
  final Map<String, DateTime> lastDataByApp;
}

/// One line of the per-metric sync log (Settings → Data).
class SyncLogEntry {
  const SyncLogEntry({
    required this.at,
    required this.source,
    required this.dataType,
    required this.status,
    this.records = 0,
    this.message,
  });
  final DateTime at;
  final SourceKind source;

  /// e.g. 'HEART_RATE', 'SLEEP_SESSION', 'hrv'
  final String dataType;

  /// 'ok' | 'empty' | 'error' | 'denied' | 'skipped'
  final String status;
  final int records;
  final String? message;
}

/// State of one data source for Settings → Sources.
class SourceStatus {
  const SourceStatus({
    required this.kind,
    required this.available,
    required this.enabled,
    required this.connected,
    required this.detail,
    this.lastSyncAt,
    this.beta = false,
  });
  final SourceKind kind;

  /// Can this source work on this phone/build at all?
  final bool available;

  /// User switched it on.
  final bool enabled;

  /// Permissions granted / signed in / paired.
  final bool connected;

  /// One human sentence: "Reading 9 data types from Fitbit" /
  /// "Not configured: add a Google Cloud OAuth client ID".
  final String detail;
  final DateTime? lastSyncAt;
  final bool beta;
}

enum HcAvailability { available, notInstalled, updateRequired, unsupported }

class HcPermissionState {
  const HcPermissionState({
    required this.availability,
    required this.granted,
    required this.missing,
    this.historyGranted = false,
    this.backgroundGranted = false,
    this.deniedTwice = false,
  });
  final HcAvailability availability;

  /// [additive 2026-09-29, QA-13] The permission sheet was dismissed twice
  /// with nothing granted: Android won't show it again, so the UI offers
  /// "Open Health Connect settings" instead.
  final bool deniedTwice;

  /// Data-type names (e.g. 'HEART_RATE') granted / not granted.
  final List<String> granted;
  final List<String> missing;
  final bool historyGranted;
  final bool backgroundGranted;
  bool get allGranted => missing.isEmpty;
}

/// Phase 0 probe: what actually reaches the phone, per data type & origin.
class DiagnosticsTypeStat {
  const DiagnosticsTypeStat({
    required this.dataType,
    required this.records,
    required this.origins,
    required this.devices,
    this.first,
    this.last,
    this.medianSpacingSec,
    this.samplesPerHour,
  });
  final String dataType;
  final int records;

  /// Package names that wrote this type, with counts.
  final Map<String, int> origins;

  /// Device names/models from record metadata, with counts.
  final Map<String, int> devices;
  final DateTime? first;
  final DateTime? last;
  final double? medianSpacingSec;
  final double? samplesPerHour;
}

class DiagnosticsReport {
  const DiagnosticsReport({
    required this.generatedAt,
    required this.windowDays,
    required this.types,
    required this.verdicts,
    this.rawJsonPath,
  });
  final DateTime generatedAt;
  final int windowDays;
  final List<DiagnosticsTypeStat> types;

  /// Phase 0 decisions in plain words, e.g.
  /// 'HR density: 1 sample / 62 s → full zone-based strain'.
  final List<String> verdicts;

  /// Where the full JSON dump was written (shareable).
  final String? rawJsonPath;
}

class ExportResult {
  const ExportResult({required this.files, required this.directory});
  final List<String> files;
  final String directory;
}

abstract class HealthRepository {
  DataMode get mode;
  Future<void> setMode(DataMode mode);

  /// Bumps whenever stored data or scores change. View-models re-read on it.
  int get revision;

  /// Broadcast stream of new [revision] values.
  Stream<int> get revisions;

  SyncStatus get syncStatus;

  /// Broadcast stream of [syncStatus] changes.
  Stream<SyncStatus> get syncStatusChanges;

  /// Newest day that has any data, or null when empty.
  Future<String?> latestDate();

  Future<DayBundle?> day(String date);

  /// Inclusive, oldest first; days without data are omitted.
  Future<List<DayBundle>> range(String from, String to);

  Future<void> syncNow();
  Future<List<SyncLogEntry>> syncLog({int limit = 200});

  Future<List<SourceStatus>> sources();
  Future<void> setSourceEnabled(SourceKind kind, bool enabled);

  Future<HcPermissionState> healthConnectPermissions();

  /// Opens the Health Connect permission sheet. Returns the new state.
  Future<HcPermissionState> requestHealthConnectPermissions();

  /// Google Health API (Enhanced mode): OAuth sign-in / sign-out.
  Future<bool> connectGoogleHealth();
  Future<void> disconnectGoogleHealth();

  Future<UserProfile> profile();
  Future<void> saveProfile(UserProfile profile);

  /// Raw rows + scores as CSV and JSON into app documents.
  Future<ExportResult> exportAll();

  /// Phase 0 probe (live mode reads Health Connect; demo mode describes the
  /// synthetic source).
  Future<DiagnosticsReport> diagnostics({int windowDays = 7});

  /// Journal (behaviour tags). Stored separately so sync never touches it.
  Future<JournalEntry> journal(String date);
  Future<void> saveJournal(JournalEntry entry);

  /// Correlations of journal factors with next-day recovery.
  Future<List<FactorInsight>> journalInsights();

  /// Deletes every stored row (keeps settings). Irreversible; UI confirms.
  Future<void> wipeData();

  // ── Any app via Health Connect (user decision 2026-09-29) ──────────────
  // Defaults keep existing fakes compiling; HealthRepositoryImpl overrides.

  /// Apps found writing to Health Connect, with per-metric coverage over the
  /// last 14 days. Empty in demo mode or before permissions are granted.
  Future<List<SourceApp>> detectedSources() async => const [];

  /// The ONE origin used per metric. Persisted, and changed only by the user
  /// or by a sustained absence (see ARCHITECTURE §3), so baselines don't
  /// flip-flop.
  Future<Map<Metric, SourceChoice>> sourceChoices() async => const {};

  /// Pins [metric] to [origin]; null returns it to automatic.
  Future<void> setSourceChoice(Metric metric, String? origin) async {}
}

/// An app that writes to Health Connect (Google Health, Samsung Health,
/// WHOOP, Oura, …).
class SourceApp {
  const SourceApp({
    required this.origin,
    required this.displayName,
    this.daysWithData = const {},
    this.lastDataAt,
    this.device,
  });

  /// Package name, e.g. 'com.sec.android.app.shealth'.
  final String origin;
  final String displayName;

  /// Metric → days with data in the window.
  final Map<Metric, int> daysWithData;
  final DateTime? lastDataAt;

  /// Most recent device name from record metadata, if any.
  final String? device;
}

class SourceChoice {
  const SourceChoice({
    required this.metric,
    required this.origin,
    required this.displayName,
    required this.automatic,
    this.since,
    this.suggestedOrigin,
    this.suggestedDisplayName,
  });
  final Metric metric;
  final String origin;
  final String displayName;

  /// false = pinned by the user.
  final bool automatic;

  /// When this origin became the metric's source (a new baseline segment
  /// starts here).
  final String? since;

  /// A different app now has fresher data for this metric (e.g. the user
  /// switched devices). The UI asks once whether to switch, instead of waiting
  /// out the sustained-absence rule silently.
  final String? suggestedOrigin;
  final String? suggestedDisplayName;
}

// ── Live heart rate over Bluetooth (standard 0x180D / 0x2A37) ────────────

class LiveHrSample {
  const LiveHrSample(this.t, this.bpm, {this.rrMs = const [], this.contact});
  final DateTime t;
  final int bpm;

  /// RR intervals in ms, if the band's 0x2A37 notification carries them.
  final List<double> rrMs;

  /// Sensor contact status if reported.
  final bool? contact;
}

class BleDevice {
  const BleDevice(this.id, this.name, this.rssi);
  final String id;
  final String name;
  final int rssi;
}

enum LiveHrPhase { idle, scanning, connecting, connected, disconnected, error }

abstract class LiveHrService {
  LiveHrPhase get phase;
  Stream<LiveHrPhase> get phaseChanges;

  /// Devices advertising the Heart Rate service (0x180D).
  Stream<List<BleDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  });
  Future<void> stopScan();
  Future<void> connect(BleDevice device);
  Future<void> disconnect();

  /// Samples while connected (~1 Hz).
  Stream<LiveHrSample> get samples;

  /// True once any notification carried RR intervals (unlocks HRV check).
  bool get rrAvailable;
  Stream<bool> get rrAvailableChanges;

  /// Persists a finished session (workout or HRV check) into the store.
  Future<void> saveSession({
    required String kind, // 'workout' | 'hrv_check'
    required List<LiveHrSample> samples,
    String? name,
  });
}

/// Typed failures from [LiveHrService] so the UI never parses messages.
enum LiveHrErrorKind {
  bluetoothOff,
  permissionDenied,
  unsupported,
  connectFailed,
  linkLost,
  noHeartRateService,
  unknown,
}

class LiveHrException implements Exception {
  const LiveHrException(this.kind, [this.message]);
  final LiveHrErrorKind kind;
  final String? message;

  @override
  String toString() =>
      'LiveHrException(${kind.name}${message == null ? '' : ': $message'})';
}
