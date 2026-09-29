// Live view-model: scan → connect → live BPM / zone → workout (live strain,
// 60-second cool-down for HRR-60) or a 2-minute HRV check (RMSSD).
//
// All maths is the engine's (Engine.zoneFor / maxHrFor / liveWorkoutStrain /
// hrr60 / rmssdFromRr). Time comes from clockProvider
// (the 1-second tick drives elapsed time and countdowns); the maths uses the
// samples' own timestamps. Nothing touches Bluetooth until the user asks,
// and leaving the screen disconnects (the band's broadcast costs battery).

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/design.dart' show Motion;
import '../../domain/engine/engine.dart';
import '../../domain/engine/strain.dart' show StrainEngine;
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';
import '../../app/platform_services.dart';

enum LiveStage {
  intro,
  scanning,
  devices,
  connecting,
  connected,
  recording,
  coolDown,
  summary,
  hrvRunning,
  hrvResult,
  error,
}

enum LiveError {
  permission,
  bluetoothOff,
  unsupported,
  unavailable,
  connectFailed,

  /// Connected, but the band exposes no Heart Rate service (0x180D): its
  /// "Share heart rate" setting is off.
  noHeartRateService,
  other,
}

/// Seconds of heart rate kept after Stop to measure HRR-60.
const kCoolDownSeconds = 60;

/// Length of the on-demand HRV check.
const kHrvCheckSeconds = 120;

/// Samples without RR after which the HRV check explains it is unavailable.
const kRrGraceSamples = 15;

/// Maps a scan/connect failure to what the user can do about it. Typed
/// [LiveHrException]s are classified by their kind; anything else (a plugin
/// error that escaped the service) falls back to reading the message.
LiveError classifyLiveError(Object e) {
  if (e is LiveHrException) {
    return switch (e.kind) {
      LiveHrErrorKind.bluetoothOff => LiveError.bluetoothOff,
      LiveHrErrorKind.permissionDenied => LiveError.permission,
      LiveHrErrorKind.unsupported => LiveError.unsupported,
      LiveHrErrorKind.connectFailed => LiveError.connectFailed,
      // Lost while connecting is a failed connect; lost while connected is
      // the dashboard's "Connection lost" (see LiveController).
      LiveHrErrorKind.linkLost => LiveError.connectFailed,
      LiveHrErrorKind.noHeartRateService => LiveError.noHeartRateService,
      LiveHrErrorKind.unknown => LiveError.other,
    };
  }
  if (e is UnimplementedError) return LiveError.unavailable;
  final s = e.toString().toLowerCase();
  if (s.contains('permission')) return LiveError.permission;
  if (s.contains('not supported') || s.contains('unsupported')) {
    return LiveError.unsupported;
  }
  // flutter_blue_plus on Android: "Bluetooth must be turned on"
  // (FlutterBluePlusPlugin.java, startScan / connect).
  if (s.contains('must be turned on') ||
      s.contains('adapter') ||
      s.contains('turned off') ||
      s.contains('turn on') ||
      s.contains('bluetooth is off') ||
      s.contains('bluetooth off')) {
    return LiveError.bluetoothOff;
  }
  return LiveError.other;
}

class LiveState {
  const LiveState({
    this.stage = LiveStage.intro,
    this.devices = const [],
    this.device,
    this.bpm,
    this.zone = 0,
    this.lost = false,
    this.rrAvailable = false,
    this.samplesSeen = 0,
    this.now,
    this.startAt,
    this.stopAt,
    this.live,
    this.trace = const [],
    this.avgHr,
    this.hrr60,
    this.coolDownSkipped = false,
    this.hrvStartAt,
    this.rrCount = 0,
    this.rmssd,
    this.saving = false,
    this.saved = false,
    this.saveError,
    this.error,
    this.errorDetail,
    this.restingHr,
    this.maxHr,
    this.profile = const UserProfile(),
    this.demo = false,
  });

  final LiveStage stage;
  final List<BleDevice> devices;
  final BleDevice? device;

  /// Latest heart rate; null until the first sample.
  final int? bpm;

  /// Karvonen display zone of [bpm] (0 = below zone 1).
  final int zone;

  /// The link dropped while a session was open (data so far is kept).
  final bool lost;
  final bool rrAvailable;
  final int samplesSeen;
  final DateTime? now;

  // Workout.
  final DateTime? startAt, stopAt;
  final WorkoutStrain? live;

  /// The session's heart rate so far (workout + cool-down), for the chart.
  final List<HrSample> trace;
  final double? avgHr;
  final double? hrr60;
  final bool coolDownSkipped;

  // HRV check.
  final DateTime? hrvStartAt;
  final int rrCount;
  final double? rmssd;

  final bool saving, saved;
  final String? saveError;
  final LiveError? error;
  final String? errorDetail;

  final double? restingHr, maxHr;
  final UserProfile profile;
  final bool demo;

  int _since(DateTime? t) => t == null || now == null
      ? 0
      : now!.difference(t).inSeconds.clamp(0, 1 << 30);

  /// Workout seconds (frozen at Stop).
  int get elapsed {
    final s = startAt;
    if (s == null) return 0;
    final end = stopAt ?? now;
    return end == null ? 0 : end.difference(s).inSeconds.clamp(0, 1 << 30);
  }

  int get coolDownLeft =>
      (kCoolDownSeconds - _since(stopAt)).clamp(0, kCoolDownSeconds);

  int get hrvLeft =>
      (kHrvCheckSeconds - _since(hrvStartAt)).clamp(0, kHrvCheckSeconds);

  /// RR never arrived although the band has been sending heart rate.
  bool get rrMissing => !rrAvailable && samplesSeen >= kRrGraceSamples;

  bool get sessionOpen => const {
    LiveStage.connected,
    LiveStage.recording,
    LiveStage.coolDown,
    LiveStage.hrvRunning,
  }.contains(stage);

  /// bpm where display zones 1…5 start (same Karvonen maths as the engine).
  List<double> get zoneFloors =>
      StrainEngine.displayFloors(restingHr: restingHr, maxHr: maxHr);

  LiveState copyWith({
    LiveStage? stage,
    List<BleDevice>? devices,
    BleDevice? device,
    int? bpm,
    int? zone,
    bool? lost,
    bool? rrAvailable,
    int? samplesSeen,
    DateTime? now,
    DateTime? startAt,
    DateTime? stopAt,
    WorkoutStrain? live,
    List<HrSample>? trace,
    double? avgHr,
    double? hrr60,
    bool? coolDownSkipped,
    DateTime? hrvStartAt,
    int? rrCount,
    double? rmssd,
    bool? saving,
    bool? saved,
    String? saveError,
    LiveError? error,
    String? errorDetail,
    double? restingHr,
    double? maxHr,
    UserProfile? profile,
    bool? demo,
    bool clearWorkout = false,
    bool clearHrv = false,
    bool clearError = false,
    bool clearSave = false,
    bool clearAnchors = false,
  }) => LiveState(
    stage: stage ?? this.stage,
    devices: devices ?? this.devices,
    device: device ?? this.device,
    bpm: bpm ?? this.bpm,
    zone: zone ?? this.zone,
    lost: lost ?? this.lost,
    rrAvailable: rrAvailable ?? this.rrAvailable,
    samplesSeen: samplesSeen ?? this.samplesSeen,
    now: now ?? this.now,
    startAt: clearWorkout ? startAt : (startAt ?? this.startAt),
    stopAt: clearWorkout ? stopAt : (stopAt ?? this.stopAt),
    live: clearWorkout ? live : (live ?? this.live),
    trace: clearWorkout ? (trace ?? const []) : (trace ?? this.trace),
    avgHr: clearWorkout ? avgHr : (avgHr ?? this.avgHr),
    hrr60: clearWorkout ? hrr60 : (hrr60 ?? this.hrr60),
    coolDownSkipped: clearWorkout
        ? false
        : (coolDownSkipped ?? this.coolDownSkipped),
    hrvStartAt: clearHrv ? hrvStartAt : (hrvStartAt ?? this.hrvStartAt),
    rrCount: clearHrv ? 0 : (rrCount ?? this.rrCount),
    rmssd: clearHrv ? rmssd : (rmssd ?? this.rmssd),
    saving: clearSave ? false : (saving ?? this.saving),
    saved: clearSave ? false : (saved ?? this.saved),
    saveError: clearSave ? null : (saveError ?? this.saveError),
    error: clearError ? null : (error ?? this.error),
    errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
    restingHr: clearAnchors ? restingHr : restingHr ?? this.restingHr,
    maxHr: clearAnchors ? maxHr : maxHr ?? this.maxHr,
    profile: profile ?? this.profile,
    demo: demo ?? this.demo,
  );
}

class LiveController extends Notifier<LiveState> {
  LiveHrService? _svc;
  StreamSubscription<List<BleDevice>>? _scanSub;
  StreamSubscription<LiveHrSample>? _sampleSub;
  StreamSubscription<LiveHrPhase>? _phaseSub;
  StreamSubscription<bool>? _rrSub;
  Timer? _ticker;
  final _session = <LiveHrSample>[];
  final _hrv = <LiveHrSample>[];
  int? _lastZone;

  @override
  LiveState build() {
    ref.onDispose(_teardown);
    var demo = false;
    try {
      demo = ref.read(healthRepositoryProvider).mode == DataMode.demo;
    } catch (_) {}
    unawaited(_loadProfile());
    return LiveState(demo: demo, now: _now());
  }

  /// The one app clock (clockProvider defaults to DateTime.now).
  DateTime _now() => ref.read(clockProvider)();

  LiveHrService? _service() {
    try {
      return _svc ??= ref.read(liveHrServiceProvider);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadProfile() async {
    try {
      final repo = ref.read(healthRepositoryProvider);
      final profile = await repo.profile();
      double? rhr, maxHr;
      final latest = await repo.latestDate();
      if (latest != null) {
        final b = await repo.day(latest);
        rhr = b?.result.strain?.restingHrUsed;
        // The engine's own max HR for the day (override, birth year, else
        // the observed maximum: StrainResult.maxHrSource), never an
        // assumed age.
        maxHr = b?.result.strain?.maxHrUsed;
      }
      if (!ref.mounted) return;
      state = state.copyWith(
        profile: profile,
        restingHr: rhr,
        maxHr:
            profile.birthYear != null && _now().year - profile.birthYear! < 18
            ? null
            : Engine.knownMaxHrFor(profile, _now()) ?? maxHr,
        clearAnchors: true,
      );
    } catch (_) {
      // Measured HR remains usable; unavailable anchors stay unavailable.
    }
  }

  void _teardown() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_scanSub?.cancel());
    unawaited(_sampleSub?.cancel());
    unawaited(_phaseSub?.cancel());
    unawaited(_rrSub?.cancel());
    final svc = _svc;
    if (svc != null) {
      // An immediately-run async closure: no zero-delay Timer left behind.
      unawaited(() async {
        try {
          await svc.disconnect();
        } catch (_) {}
      }());
    }
  }

  LiveState _failed(Object e, {bool connecting = false}) {
    final kind = classifyLiveError(e);
    return state.copyWith(
      stage: LiveStage.error,
      error: kind == LiveError.other && connecting
          ? LiveError.connectFailed
          : kind,
      errorDetail: '$e',
    );
  }

  // ── scan / connect ─────────────────────────────────────────────────────

  void startScan() {
    final svc = _service();
    if (svc == null) {
      state = state.copyWith(
        stage: LiveStage.error,
        error: LiveError.unavailable,
      );
      return;
    }
    unawaited(_scanSub?.cancel());
    state = state.copyWith(
      stage: LiveStage.scanning,
      devices: const [],
      clearError: true,
    );
    _scanSub = svc.scan().listen(
      (list) {
        if (!ref.mounted) return;
        state = state.copyWith(devices: list);
      },
      onError: (Object e) {
        if (!ref.mounted) return;
        state = _failed(e);
      },
      onDone: () {
        if (!ref.mounted) return;
        if (state.stage == LiveStage.scanning) {
          state = state.copyWith(stage: LiveStage.devices);
        }
      },
      cancelOnError: true,
    );
  }

  Future<void> connect(BleDevice d) async {
    final svc = _service();
    if (svc == null) {
      state = state.copyWith(
        stage: LiveStage.error,
        error: LiveError.unavailable,
      );
      return;
    }
    final scan = _scanSub;
    _scanSub = null;
    final wasScanning = state.stage == LiveStage.scanning;
    state = state.copyWith(
      stage: LiveStage.connecting,
      device: d,
      clearError: true,
    );
    // Not awaited: a finished scan stream's cancel can wait on its
    // generator; only an active scan needs stopping before a connect.
    if (scan != null) unawaited(scan.cancel());
    if (wasScanning) {
      try {
        await svc.stopScan();
      } catch (_) {}
      if (!ref.mounted) return;
    }
    _sampleSub ??= svc.samples.listen(_onSample);
    _phaseSub ??= svc.phaseChanges.listen(_onPhase);
    _rrSub ??= svc.rrAvailableChanges.listen((v) {
      if (ref.mounted) state = state.copyWith(rrAvailable: v);
    });
    try {
      await svc.connect(d);
    } catch (e) {
      if (!ref.mounted) return;
      state = _failed(e, connecting: true);
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      stage: LiveStage.connected,
      rrAvailable: svc.rrAvailable,
      lost: false,
      now: _now(),
    );
    _ticker ??= Timer.periodic(Motion.tick, (_) => _tick());
  }

  /// Reconnect to the same band after the link dropped.
  Future<void> reconnect() async {
    final d = state.device;
    if (d == null) return startScan();
    final svc = _service();
    if (svc == null) return;
    try {
      await svc.connect(d);
      if (ref.mounted) state = state.copyWith(lost: false);
    } catch (e) {
      if (!ref.mounted) return;
      // Something the user has to fix first (Bluetooth off, permission
      // revoked) gets its own card; a plain failed reconnect stays "lost".
      final kind = classifyLiveError(e);
      state = switch (kind) {
        LiveError.bluetoothOff ||
        LiveError.permission ||
        LiveError.unsupported ||
        LiveError.noHeartRateService => state.copyWith(
          stage: LiveStage.error,
          error: kind,
          errorDetail: '$e',
        ),
        _ => state.copyWith(lost: true, errorDetail: '$e'),
      };
    }
  }

  /// Leave the live dashboard (disconnects).
  Future<void> disconnect() async {
    _ticker?.cancel();
    _ticker = null;
    final svc = _service();
    try {
      await svc?.disconnect();
    } catch (_) {}
    if (!ref.mounted) return;
    _session.clear();
    _hrv.clear();
    state = state.copyWith(
      stage: LiveStage.intro,
      lost: false,
      clearWorkout: true,
      clearHrv: true,
      clearSave: true,
    );
  }

  void _onPhase(LiveHrPhase p) {
    if (!ref.mounted) return;
    if (p == LiveHrPhase.disconnected && state.sessionOpen) {
      state = state.copyWith(lost: true);
    } else if (p == LiveHrPhase.connected && state.lost) {
      state = state.copyWith(lost: false);
    }
  }

  void _onSample(LiveHrSample s) {
    if (!ref.mounted) return;
    if (s.bpm < 25 || s.bpm > 250 || s.contact == false) return;
    final zone = state.zoneFloors.where((floor) => s.bpm >= floor).length;
    var next = state.copyWith(
      bpm: s.bpm,
      zone: zone,
      lost: false,
      samplesSeen: state.samplesSeen + 1,
    );
    switch (state.stage) {
      case LiveStage.recording:
        _session.add(s);
        next = next.copyWith(
          trace: [...state.trace, HrSample(s.t, s.bpm.toDouble())],
        );
        if (_lastZone != null && zone != _lastZone) {
          unawaited(HapticFeedback.mediumImpact());
        }
        _lastZone = zone;
        next = next.copyWith(live: _liveStrain(s.t), avgHr: _avg(_session));
      case LiveStage.coolDown:
        _session.add(s);
        next = next.copyWith(
          trace: [...state.trace, HrSample(s.t, s.bpm.toDouble())],
        );
      case LiveStage.hrvRunning:
        _hrv.add(s);
        next = next.copyWith(rrCount: next.rrCount + s.rrMs.length);
      default:
        break;
    }
    state = next;
  }

  void _tick() {
    if (!ref.mounted) return;
    final now = _now();
    state = state.copyWith(now: now);
    if (state.stage == LiveStage.coolDown && state.coolDownLeft <= 0) {
      _finishCoolDown();
    } else if (state.stage == LiveStage.hrvRunning && state.hrvLeft <= 0) {
      _finishHrv();
    }
  }

  static double? _avg(List<LiveHrSample> xs) {
    if (xs.isEmpty) return null;
    return xs.fold(0.0, (a, s) => a + s.bpm) / xs.length;
  }

  List<HrSample> _workoutSamples({bool includeCoolDown = false}) {
    final stop = state.stopAt;
    return [
      for (final s in _session)
        if (includeCoolDown || stop == null || !s.t.isAfter(stop))
          HrSample(s.t, s.bpm.toDouble()),
    ];
  }

  WorkoutStrain? _liveStrain(DateTime at) {
    try {
      return Engine.liveWorkoutStrain(
        _workoutSamples(),
        restingHr: state.restingHr,
        maxHr: state.maxHr,
        config: EngineConfig(profile: state.profile),
        now: at,
      );
    } catch (_) {
      return state.live;
    }
  }

  // ── workout ────────────────────────────────────────────────────────────

  void startWorkout() {
    _session.clear();
    _lastZone = state.zone;
    final now = _now();
    state = state.copyWith(
      stage: LiveStage.recording,
      clearWorkout: true,
      clearSave: true,
      startAt: now,
      now: now,
    );
  }

  /// Stop the workout; heart rate keeps recording for the 60-s cool-down.
  void stopWorkout() {
    final now = _now();
    final last = _session.isEmpty ? null : _session.last.t;
    // End at the last real sample if the link went quiet before Stop.
    final end = last != null && last.isBefore(now) && state.lost ? last : now;
    state = state.copyWith(
      stage: LiveStage.coolDown,
      stopAt: end,
      now: now,
      live: _session.isEmpty ? null : _liveStrainAt(end),
    );
  }

  WorkoutStrain? _liveStrainAt(DateTime end) {
    try {
      return Engine.liveWorkoutStrain(
        [
          for (final s in _session)
            if (!s.t.isAfter(end)) HrSample(s.t, s.bpm.toDouble()),
        ],
        restingHr: state.restingHr,
        maxHr: state.maxHr,
        config: EngineConfig(profile: state.profile),
        now: end,
      );
    } catch (_) {
      return state.live;
    }
  }

  void skipCoolDown() {
    state = state.copyWith(stage: LiveStage.summary, coolDownSkipped: true);
  }

  void _finishCoolDown() {
    final stop = state.stopAt;
    double? hrr;
    if (stop != null) {
      try {
        hrr = Engine.hrr60(_workoutSamples(includeCoolDown: true), stop);
      } catch (_) {}
    }
    state = state.copyWith(stage: LiveStage.summary, hrr60: hrr);
  }

  Future<void> saveWorkout() async {
    final svc = _service();
    if (svc == null || state.saving) return;
    final stop = state.stopAt;
    final samples = [
      for (final s in _session)
        if (stop == null || !s.t.isAfter(stop)) s,
    ];
    state = state.copyWith(saving: true, saveError: null);
    try {
      await svc.saveSession(
        kind: 'workout',
        samples: samples,
        name: 'Live workout',
      );
      if (!ref.mounted) return;
      state = state.copyWith(saving: false, saved: true);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(saving: false, saveError: '$e');
    }
  }

  /// Back to the live dashboard (workout discarded or already saved).
  void backToLive() {
    _session.clear();
    _hrv.clear();
    state = state.copyWith(
      stage: LiveStage.connected,
      clearWorkout: true,
      clearHrv: true,
      clearSave: true,
    );
  }

  // ── HRV check ──────────────────────────────────────────────────────────

  void startHrvCheck() {
    if (!state.rrAvailable) return;
    _hrv.clear();
    final now = _now();
    state = state.copyWith(
      stage: LiveStage.hrvRunning,
      clearHrv: true,
      clearSave: true,
      hrvStartAt: now,
      now: now,
    );
  }

  void cancelHrvCheck() => backToLive();

  void _finishHrv() {
    final rr = [for (final s in _hrv) ...s.rrMs];
    double? rmssd;
    try {
      rmssd = Engine.rmssdFromRr(rr);
    } catch (_) {}
    state = state.copyWith(
      stage: LiveStage.hrvResult,
      rmssd: rmssd,
      rrCount: rr.length,
    );
  }

  Future<void> saveHrvCheck() async {
    final svc = _service();
    if (svc == null || state.saving) return;
    state = state.copyWith(saving: true, saveError: null);
    try {
      await svc.saveSession(
        kind: 'hrv_check',
        samples: [..._hrv],
        name: 'HRV check',
      );
      if (!ref.mounted) return;
      state = state.copyWith(saving: false, saved: true);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(saving: false, saveError: '$e');
    }
  }
}

final liveControllerProvider =
    NotifierProvider.autoDispose<LiveController, LiveState>(
      LiveController.new,
      retry: noRetry,
    );
