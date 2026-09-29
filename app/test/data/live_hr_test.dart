// Live heart rate: typed failures (LiveHrException) from every service and
// a deterministic simulated strap (injected clock).

import 'dart:async';

import 'package:airlog/data/services/ble/live_hr_service_impl.dart';
import 'package:airlog/data/services/demo/demo_live_hr_service.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_test/flutter_test.dart';

fbp.FlutterBluePlusException fbpError(fbp.FbpErrorCode c) =>
    fbp.FlutterBluePlusException(fbp.ErrorPlatform.fbp, 'op', c.index, c.name);

class _Throwing implements LiveHrService {
  _Throwing(this.error);
  final Object error;
  @override
  LiveHrPhase get phase => LiveHrPhase.idle;
  @override
  Stream<LiveHrPhase> get phaseChanges => const Stream.empty();
  @override
  Stream<LiveHrSample> get samples => const Stream.empty();
  @override
  bool get rrAvailable => false;
  @override
  Stream<bool> get rrAvailableChanges => const Stream.empty();
  @override
  Stream<List<BleDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => Stream.error(error);
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(BleDevice device) async => throw error;
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> saveSession({
    required String kind,
    required List<LiveHrSample> samples,
    String? name,
  }) async {}
}

void main() {
  group('liveHrErrorFrom', () {
    test('flutter_blue_plus codes', () {
      expect(
        liveHrErrorFrom(fbpError(fbp.FbpErrorCode.adapterIsOff)).kind,
        LiveHrErrorKind.bluetoothOff,
      );
      expect(
        liveHrErrorFrom(fbpError(fbp.FbpErrorCode.userRejected)).kind,
        LiveHrErrorKind.bluetoothOff,
      );
      expect(
        liveHrErrorFrom(fbpError(fbp.FbpErrorCode.deviceIsDisconnected)).kind,
        LiveHrErrorKind.linkLost,
      );
      expect(
        liveHrErrorFrom(fbpError(fbp.FbpErrorCode.serviceNotFound)).kind,
        LiveHrErrorKind.noHeartRateService,
      );
      expect(
        liveHrErrorFrom(
          fbpError(fbp.FbpErrorCode.timeout),
          fallback: LiveHrErrorKind.connectFailed,
        ).kind,
        LiveHrErrorKind.connectFailed,
      );
    });

    test(
      'platform errors and messages; typed errors pass through; text kept',
      () {
        expect(
          liveHrErrorFrom(MissingPluginException('no fbp')).kind,
          LiveHrErrorKind.unsupported,
        );
        expect(
          liveHrErrorFrom(
            PlatformException(
              code: 'x',
              message: 'Bluetooth must be turned on',
            ),
          ).kind,
          LiveHrErrorKind.bluetoothOff,
        );
        expect(
          liveHrErrorFrom(StateError('missing permission BLUETOOTH_CONNECT'))
              .kind,
          LiveHrErrorKind.permissionDenied,
        );
        final typed = const LiveHrException(LiveHrErrorKind.linkLost, 'gone');
        expect(identical(liveHrErrorFrom(typed), typed), isTrue);
        final e = liveHrErrorFrom(
          StateError('weird'),
          fallback: LiveHrErrorKind.connectFailed,
        );
        expect(e.kind, LiveHrErrorKind.connectFailed);
        expect(e.message, contains('weird'));
      },
    );
  });

  group('ModeAwareLiveHrService', () {
    test('untyped failures leave as LiveHrException', () async {
      final svc = ModeAwareLiveHrService(
        demo: _Throwing(StateError('boom')),
        real: DemoLiveHrService(),
        mode: () => DataMode.demo,
      );
      await expectLater(
        svc.connect(DemoLiveHrService.device),
        throwsA(
          isA<LiveHrException>()
              .having((e) => e.kind, 'kind', LiveHrErrorKind.connectFailed)
              .having((e) => e.message, 'message', contains('boom')),
        ),
      );
      await expectLater(
        svc.scan(),
        emitsError(
          isA<LiveHrException>().having(
            (e) => e.kind,
            'kind',
            LiveHrErrorKind.unknown,
          ),
        ),
      );
    });
  });

  group('DemoLiveHrService', () {
    test(
      'typed failures on demand, and for a device that is not the strap',
      () async {
        final svc = DemoLiveHrService();
        svc.failNext = LiveHrErrorKind.bluetoothOff;
        await expectLater(
          svc.scan(),
          emitsError(
            isA<LiveHrException>().having(
              (e) => e.kind,
              'kind',
              LiveHrErrorKind.bluetoothOff,
            ),
          ),
        );
        expect(await svc.scan().first, [
          DemoLiveHrService.device,
        ], reason: 'resets');
        svc.failNext = LiveHrErrorKind.noHeartRateService;
        await expectLater(
          svc.connect(DemoLiveHrService.device),
          throwsA(
            isA<LiveHrException>().having(
              (e) => e.kind,
              'kind',
              LiveHrErrorKind.noHeartRateService,
            ),
          ),
        );
        await expectLater(
          svc.connect(const BleDevice('other', 'Other strap', -70)),
          throwsA(
            isA<LiveHrException>().having(
              (e) => e.kind,
              'kind',
              LiveHrErrorKind.connectFailed,
            ),
          ),
        );
        await svc.dispose();
        await expectLater(
          svc.connect(DemoLiveHrService.device),
          throwsA(isA<LiveHrException>()),
        );
      },
    );

    testWidgets('injected clock: timestamps and HRR-60 are deterministic', (
      tester,
    ) async {
      Future<(List<LiveHrSample>, double?)> run() async {
        var t = DateTime(2026, 9, 28, 18);
        final svc = DemoLiveHrService(
          clock: () => t = t.add(const Duration(seconds: 1)),
        );
        final got = <LiveHrSample>[];
        final sub = svc.samples.listen(got.add);
        await svc.connect(DemoLiveHrService.device);
        // Simulated profile: hard block until second 750, then cool-down.
        await tester.pump(const Duration(seconds: 1100));
        svc.simulateLinkLoss();
        expect(svc.phase, LiveHrPhase.disconnected);
        // Not awaited: under testWidgets, awaiting a broadcast
        // subscription's cancel() (a root-zone future) stalls the fake-async
        // test body.
        unawaited(sub.cancel());
        unawaited(svc.dispose());
        final samples = [for (final s in got) HrSample(s.t, s.bpm.toDouble())];
        final end = DateTime(2026, 9, 28, 18).add(const Duration(seconds: 751));
        return (got, Engine.hrr60(samples, end));
      }

      final (a, hrrA) = await run();
      final (b, hrrB) = await run();
      expect(a.length, 1100);
      expect(a.first.t, DateTime(2026, 9, 28, 18, 0, 1));
      expect(a[59].t.difference(a.first.t), const Duration(seconds: 59));
      expect([for (final s in a) s.bpm], [for (final s in b) s.bpm]);
      expect(hrrA, isNotNull);
      expect(hrrA, hrrB);
      expect(
        hrrA!,
        inInclusiveRange(12, 40),
        reason: 'cool-down drop after the hard block',
      );
    });
  });
}
