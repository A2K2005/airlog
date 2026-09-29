// Live heart rate over the standard Bluetooth Heart Rate Profile:
// scan for service 0x180D, connect, subscribe to 0x2A37, decode with
// hrs_parser.dart. Android 12+ needs BLUETOOTH_SCAN / BLUETOOTH_CONNECT at
// runtime; Android 8–11 need location for scanning.
//
// Failures surface as typed LiveHrExceptions (live_hr_errors.dart): thrown
// by connect(), added to the scan() stream. A link lost while connected is
// the `disconnected` phase (no error event on the samples stream).
//
// The Fitbit Air only advertises 0x180D while "share real-time heart rate"
// is on (battery cost). Whether its notifications carry RR intervals is
// UNVERIFIED until the band arrives — rrAvailable flips on the first frame
// that has them.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

import '../../../domain/repositories.dart';
import '../demo/demo_live_hr_service.dart' show LiveSessionSaver;
import 'hrs_parser.dart';
import 'live_hr_errors.dart';

export 'live_hr_errors.dart' show liveHrErrorFrom;

final fbp.Guid kHrServiceUuid = fbp.Guid('180d');
final fbp.Guid kHrMeasurementUuid = fbp.Guid('2a37');

class LiveHrServiceImpl implements LiveHrService {
  LiveHrServiceImpl({
    this.saver,
    this.platform = const MethodChannel('airlog/health_connect'),
  });

  final LiveSessionSaver? saver;
  final MethodChannel platform;

  LiveHrPhase _phase = LiveHrPhase.idle;
  final _phaseCtl = StreamController<LiveHrPhase>.broadcast();
  final _samplesCtl = StreamController<LiveHrSample>.broadcast();
  final _rrCtl = StreamController<bool>.broadcast();
  bool _rr = false;
  fbp.BluetoothDevice? _device;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<fbp.BluetoothConnectionState>? _connSub;
  String? deviceName;

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

  /// True while a band is connected and streaming (Sources screen).
  bool get isConnected => _phase == LiveHrPhase.connected;

  void _set(LiveHrPhase p) {
    _phase = p;
    if (!_phaseCtl.isClosed) _phaseCtl.add(p);
  }

  Future<int?> _sdkInt() async {
    try {
      return await platform.invokeMethod<int>('sdkInt');
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensurePermissions() async {
    final sdk = await _sdkInt();
    final wanted = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      if (sdk == null || sdk < 31) Permission.locationWhenInUse,
    ];
    final Map<Permission, PermissionStatus> res;
    try {
      res = await wanted.request();
    } catch (e) {
      throw liveHrErrorFrom(e, fallback: LiveHrErrorKind.permissionDenied);
    }
    final denied = [
      for (final e in res.entries)
        if (!e.value.isGranted && !e.value.isLimited) e,
    ];
    if (denied.isNotEmpty) {
      final forever = denied.any((e) => e.value.isPermanentlyDenied);
      final names = denied
          .map((e) => e.key.toString().split('.').last)
          .join(', ');
      throw LiveHrException(
        LiveHrErrorKind.permissionDenied,
        'Bluetooth permission denied ($names)'
        '${forever ? '; allow it in system settings' : ''}',
      );
    }
  }

  /// The adapter state once it is known (the plugin reports `unknown` until
  /// its first state event) and not mid-transition.
  Future<fbp.BluetoothAdapterState> _adapterState() => fbp
      .FlutterBluePlus
      .adapterState
      .firstWhere(
        (s) =>
            s != fbp.BluetoothAdapterState.unknown &&
            s != fbp.BluetoothAdapterState.turningOn &&
            s != fbp.BluetoothAdapterState.turningOff,
      )
      .timeout(
        const Duration(seconds: 3),
        onTimeout: () => fbp.FlutterBluePlus.adapterStateNow,
      );

  /// Permissions → LE support → adapter on (asking once to turn it on).
  /// Throws a typed [LiveHrException].
  Future<void> _ensureReady() async {
    await _ensurePermissions();
    try {
      if (!await fbp.FlutterBluePlus.isSupported) {
        throw const LiveHrException(
          LiveHrErrorKind.unsupported,
          'Bluetooth LE is not supported on this device',
        );
      }
      var st = await _adapterState();
      if (st == fbp.BluetoothAdapterState.off ||
          st == fbp.BluetoothAdapterState.unknown) {
        try {
          await fbp.FlutterBluePlus.turnOn(timeout: 20);
        } catch (_) {
          // Declined or impossible: reported as "Bluetooth is off" below.
        }
        st = await _adapterState();
      }
      switch (st) {
        case fbp.BluetoothAdapterState.on:
          return;
        case fbp.BluetoothAdapterState.unauthorized:
          throw const LiveHrException(
            LiveHrErrorKind.permissionDenied,
            'Bluetooth access is not authorised',
          );
        case fbp.BluetoothAdapterState.unavailable:
          throw const LiveHrException(
            LiveHrErrorKind.unsupported,
            'Bluetooth is not available on this device',
          );
        default:
          throw const LiveHrException(
            LiveHrErrorKind.bluetoothOff,
            'Bluetooth is off',
          );
      }
    } catch (e) {
      throw liveHrErrorFrom(e);
    }
  }

  @override
  Stream<List<BleDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    final ctl = StreamController<List<BleDevice>>();
    StreamSubscription<List<fbp.ScanResult>>? sub;
    ctl.onListen = () async {
      try {
        await _ensureReady();
        _set(LiveHrPhase.scanning);
        final seen = <String, BleDevice>{};
        sub = fbp.FlutterBluePlus.onScanResults.listen((rs) {
          for (final r in rs) {
            final name = r.advertisementData.advName.isNotEmpty
                ? r.advertisementData.advName
                : (r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : 'Heart-rate sensor');
            seen[r.device.remoteId.str] = BleDevice(
              r.device.remoteId.str,
              name,
              r.rssi,
            );
          }
          if (!ctl.isClosed) {
            ctl.add(
              seen.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)),
            );
          }
        });
        await fbp.FlutterBluePlus.startScan(
          withServices: [kHrServiceUuid],
          timeout: timeout,
        );
        await fbp.FlutterBluePlus.isScanning.where((s) => !s).first;
      } catch (e) {
        if (!ctl.isClosed) ctl.addError(liveHrErrorFrom(e));
        _set(LiveHrPhase.error);
      } finally {
        await sub?.cancel();
        if (_phase == LiveHrPhase.scanning) _set(LiveHrPhase.idle);
        if (!ctl.isClosed) await ctl.close();
      }
    };
    ctl.onCancel = () async {
      await sub?.cancel();
      try {
        await fbp.FlutterBluePlus.stopScan();
      } catch (_) {}
    };
    return ctl.stream;
  }

  @override
  Future<void> stopScan() async {
    try {
      await fbp.FlutterBluePlus.stopScan();
    } catch (_) {}
    if (_phase == LiveHrPhase.scanning) _set(LiveHrPhase.idle);
  }

  @override
  Future<void> connect(BleDevice device) async {
    await disconnect();
    _set(LiveHrPhase.connecting);
    fbp.BluetoothDevice? d;
    // A failure after the link came up but before notifications flow is a
    // lost link if the band dropped, else a failed connect.
    LiveHrErrorKind midway() => d?.isConnected == true
        ? LiveHrErrorKind.connectFailed
        : LiveHrErrorKind.linkLost;
    try {
      await _ensureReady();
      final dev = fbp.BluetoothDevice.fromId(device.id);
      d = dev;
      _device = dev;
      deviceName = device.name;
      try {
        await dev.connect(
          license: fbp.License.nonprofit,
          timeout: const Duration(seconds: 15),
          mtu: null,
        );
      } catch (e) {
        throw liveHrErrorFrom(e, fallback: LiveHrErrorKind.connectFailed);
      }
      _connSub = dev.connectionState.listen((s) {
        if (s == fbp.BluetoothConnectionState.disconnected &&
            _phase == LiveHrPhase.connected) {
          _set(LiveHrPhase.disconnected);
        }
      });
      final List<fbp.BluetoothService> services;
      try {
        services = await dev.discoverServices();
      } catch (e) {
        throw liveHrErrorFrom(e, fallback: midway());
      }
      final svc = services.where((s) => s.uuid == kHrServiceUuid).firstOrNull;
      final ch = svc?.characteristics
          .where((c) => c.uuid == kHrMeasurementUuid)
          .firstOrNull;
      if (ch == null) {
        throw LiveHrException(
          LiveHrErrorKind.noHeartRateService,
          '${device.name} has no Heart Rate Measurement characteristic (0x2A37)',
        );
      }
      _valueSub = ch.onValueReceived.listen(_onValue);
      dev.cancelWhenDisconnected(_valueSub!);
      try {
        await ch.setNotifyValue(true);
      } catch (e) {
        throw liveHrErrorFrom(e, fallback: midway());
      }
      _set(LiveHrPhase.connected);
    } catch (e) {
      await _teardown();
      _set(LiveHrPhase.error);
      throw liveHrErrorFrom(e, fallback: LiveHrErrorKind.connectFailed);
    }
  }

  /// Drops a half-open link without emitting phases.
  Future<void> _teardown() async {
    await _valueSub?.cancel();
    _valueSub = null;
    await _connSub?.cancel();
    _connSub = null;
    final d = _device;
    _device = null;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
  }

  void _onValue(List<int> value) {
    final m = parseHeartRateMeasurement(value);
    if (m == null) return;
    // Off-skin frames are a refusal, not a low reading (Edge rule).
    if (m.contact == false) return;
    if (m.rrMs.isNotEmpty && !_rr) {
      _rr = true;
      _rrCtl.add(true);
    }
    _samplesCtl.add(
      LiveHrSample(DateTime.now(), m.bpm, rrMs: m.rrMs, contact: m.contact),
    );
  }

  @override
  Future<void> disconnect() async {
    await _valueSub?.cancel();
    _valueSub = null;
    await _connSub?.cancel();
    _connSub = null;
    final d = _device;
    _device = null;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
      _set(LiveHrPhase.disconnected);
    }
  }

  @override
  Future<void> saveSession({
    required String kind,
    required List<LiveHrSample> samples,
    String? name,
  }) async => saver?.call(kind: kind, samples: samples, name: name);
}

/// Routes to the simulated strap in demo mode and to real BLE in live mode,
/// behind one stable set of streams (the UI subscribes once). Whatever
/// escapes either service leaves as a typed [LiveHrException].
class ModeAwareLiveHrService implements LiveHrService {
  ModeAwareLiveHrService({
    required this.demo,
    required this.real,
    required this.mode,
  }) {
    for (final s in [demo, real]) {
      s.phaseChanges.listen((p) {
        if (identical(s, _active)) _phaseCtl.add(p);
      });
      s.samples.listen((x) {
        if (identical(s, _active)) _samplesCtl.add(x);
      }, onError: (Object _) {});
      s.rrAvailableChanges.listen((x) {
        if (identical(s, _active)) _rrCtl.add(x);
      });
    }
  }

  final LiveHrService demo;
  final LiveHrService real;
  final DataMode Function() mode;
  LiveHrService? _connected;

  final _phaseCtl = StreamController<LiveHrPhase>.broadcast();
  final _samplesCtl = StreamController<LiveHrSample>.broadcast();
  final _rrCtl = StreamController<bool>.broadcast();

  LiveHrService get _active =>
      _connected ?? (mode() == DataMode.demo ? demo : real);

  /// True while the active service is connected (Sources screen).
  bool get isConnected => _active.phase == LiveHrPhase.connected;

  @override
  LiveHrPhase get phase => _active.phase;
  @override
  Stream<LiveHrPhase> get phaseChanges => _phaseCtl.stream;
  @override
  Stream<LiveHrSample> get samples => _samplesCtl.stream;
  @override
  bool get rrAvailable => _active.rrAvailable;
  @override
  Stream<bool> get rrAvailableChanges => _rrCtl.stream;

  @override
  Stream<List<BleDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => _active
      .scan(timeout: timeout)
      .transform(
        StreamTransformer<List<BleDevice>, List<BleDevice>>.fromHandlers(
          handleError: (e, st, sink) => sink.addError(liveHrErrorFrom(e), st),
        ),
      );

  @override
  Future<void> stopScan() => _active.stopScan();

  @override
  Future<void> connect(BleDevice device) async {
    final target = mode() == DataMode.demo ? demo : real;
    _connected = target;
    try {
      await target.connect(device);
    } catch (e) {
      throw liveHrErrorFrom(e, fallback: LiveHrErrorKind.connectFailed);
    }
  }

  @override
  Future<void> disconnect() async {
    final c = _connected ?? _active;
    await c.disconnect();
    _connected = null;
  }

  @override
  Future<void> saveSession({
    required String kind,
    required List<LiveHrSample> samples,
    String? name,
  }) => _active.saveSession(kind: kind, samples: samples, name: name);
}
