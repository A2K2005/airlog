// Simulated Bluetooth heart-rate strap for demo mode: ~1 Hz samples with RR
// intervals (respiratory sinus arrhythmia at rest), so the live screen and
// the on-demand HRV check work without a band.
//
// Profile (20-minute loop): 30 s at rest right after connecting, then a
// 1-minute ramp into a workout-like block with intervals (so a workout
// started at once scores; QA-14), a cool-down, and ~4.5 min at rest
// (≈64 bpm, RR variability ≈ 40–60 ms RMSSD) for on-demand HRV checks;
// repeats.
// No timers exist until connect(); disconnect() cancels them (widget tests
// must not leave timers pending). Failures are typed LiveHrExceptions like
// the real service's; [DemoLiveHrService.failNext] and
// [DemoLiveHrService.simulateLinkLoss] reproduce each one on demand.

import 'dart:async';
import 'dart:math' as math;

import '../../../domain/repositories.dart';
import 'demo_generator.dart' show SeededRng;

typedef LiveSessionSaver = Future<void> Function({
  required String kind,
  required List<LiveHrSample> samples,
  String? name,
});

class DemoLiveHrService implements LiveHrService {
  DemoLiveHrService({
    this.saver,
    int seed = 7,
    this.tick = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _r = SeededRng(seed),
       clock = clock ?? DateTime.now;

  final LiveSessionSaver? saver;
  final Duration tick;
  final SeededRng _r;

  /// Timestamps of emitted samples. Inject a fake clock (advanced per tick)
  /// to make session math like HRR-60 deterministic in tests.
  final DateTime Function() clock;

  /// Test/demo hook: the next scan() or connect() fails with this kind
  /// (then it resets), so every error state can be shown without a band.
  LiveHrErrorKind? failNext;

  bool _disposed = false;

  static const BleDevice device = BleDevice(
    'demo-fitbit-air',
    'Fitbit Air (demo)',
    -58,
  );

  LiveHrPhase _phase = LiveHrPhase.idle;
  final _phaseCtl = StreamController<LiveHrPhase>.broadcast();
  final _samplesCtl = StreamController<LiveHrSample>.broadcast();
  final _rrCtl = StreamController<bool>.broadcast();
  Timer? _timer;
  bool _rr = false;
  int _second = 0;
  double _beatClock = 0; // seconds since connect of the next beat

  @override
  LiveHrPhase get phase => _phase;

  @override
  Stream<LiveHrPhase> get phaseChanges => _phaseCtl.stream;

  @override
  Stream<LiveHrSample> get samples => _samplesCtl.stream;

  @override
  bool get rrAvailable => _rr;

  @override
  Stream<bool> get rrAvailableChanges => _rrCtl.stream;

  void _set(LiveHrPhase p) {
    _phase = p;
    if (!_phaseCtl.isClosed) _phaseCtl.add(p);
  }

  /// Throws the typed failure a real strap could produce, if one is due.
  void _check(String action) {
    if (_disposed) {
      throw const LiveHrException(
        LiveHrErrorKind.unknown,
        'The simulated strap was shut down',
      );
    }
    final k = failNext;
    if (k == null) return;
    failNext = null;
    _set(LiveHrPhase.error);
    throw LiveHrException(k, 'Simulated $action failure (${k.name})');
  }

  @override
  Stream<List<BleDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    _check('scan');
    _set(LiveHrPhase.scanning);
    yield const [device];
    if (_phase == LiveHrPhase.scanning) _set(LiveHrPhase.idle);
  }

  @override
  Future<void> stopScan() async {
    if (_phase == LiveHrPhase.scanning) _set(LiveHrPhase.idle);
  }

  @override
  Future<void> connect(BleDevice d) async {
    _check('connect');
    if (d.id != device.id) {
      _set(LiveHrPhase.error);
      throw LiveHrException(
        LiveHrErrorKind.connectFailed,
        '${d.name} is not the simulated strap (${device.name})',
      );
    }
    _set(LiveHrPhase.connecting);
    _second = 0;
    _beatClock = 0;
    _timer?.cancel();
    _set(LiveHrPhase.connected);
    _timer = Timer.periodic(tick, (_) => _emit());
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    if (_phase != LiveHrPhase.idle) _set(LiveHrPhase.disconnected);
  }

  /// Test/demo hook: the strap drops the link while connected (the real
  /// service reports this as the `disconnected` phase, not as an error).
  void simulateLinkLoss() {
    if (_phase != LiveHrPhase.connected) return;
    _timer?.cancel();
    _timer = null;
    _set(LiveHrPhase.disconnected);
  }

  /// Target HR for second [s] of the simulated session.
  double hrAt(int s) {
    final cycle = s % 1200; // 20-minute loop
    if (cycle < 30) return 64 + 2 * math.sin(s / 23);
    if (cycle < 90) return 64 + (cycle - 30) / 60 * 76; // ramp to 140
    if (cycle < 750) {
      final block = ((cycle - 90) ~/ 90).isEven;
      return block ? 158 + 4 * math.sin(s / 11) : 138 + 3 * math.sin(s / 7);
    }
    if (cycle < 930) return 140 - (cycle - 750) / 180 * 76; // cool-down
    return 64 + 2 * math.sin(s / 23); // rest (HRV checks)
  }

  /// One tick = one second of simulated beats.
  void _emit() {
    final s = _second++;
    final hr = hrAt(s);
    final rr = <double>[];
    final end = (s + 1).toDouble();
    while (_beatClock < end) {
      final rest = hr < 90;
      final rsa = rest
          ? 0.045 * math.sin(2 * math.pi * _beatClock / 4.6)
          : 0.008;
      final noise = _r.gauss(0, rest ? 9 : 3);
      final ms = (60000 / hr) * (1 + rsa) + noise;
      rr.add(double.parse(ms.clamp(280.0, 1600.0).toStringAsFixed(1)));
      _beatClock += ms / 1000;
    }
    if (!_rr && rr.isNotEmpty && !_rrCtl.isClosed) {
      _rr = true;
      _rrCtl.add(true);
    }
    final bpm = rr.isEmpty
        ? hr.round()
        : (60000 / (rr.reduce((a, b) => a + b) / rr.length)).round();
    if (_samplesCtl.isClosed) return;
    _samplesCtl.add(LiveHrSample(clock(), bpm, rrMs: rr, contact: true));
  }

  @override
  Future<void> saveSession({
    required String kind,
    required List<LiveHrSample> samples,
    String? name,
  }) async {
    await saver?.call(kind: kind, samples: samples, name: name);
  }

  /// Stops the strap and closes its streams. Does not await the
  /// controllers' done futures: a broadcast controller whose last listener
  /// already cancelled never completes it under testWidgets' fake async.
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_phaseCtl.close());
    unawaited(_samplesCtl.close());
    unawaited(_rrCtl.close());
  }
}
