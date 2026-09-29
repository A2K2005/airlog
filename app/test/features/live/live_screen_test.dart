import 'package:airlog/design/design.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/live/live_screen.dart';
import 'package:airlog/features/live/live_view_model.dart';
import 'package:airlog/features/live/widgets/live_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

Future<StepClock> _connect(
  WidgetTester t,
  FakeLiveHr live, {
  Brightness brightness = Brightness.dark,
  Size size = kPhone,
  double textScale = 1,
}) async {
  final clock = StepClock(DateTime(2026, 9, 28, 18));
  await pumpB(
    t,
    const LiveScreen(),
    repo: ScreensBRepo.demo(),
    live: live,
    clock: clock.call,
    brightness: brightness,
    size: size,
    textScale: textScale,
  );
  await t.pumpAndSettle();
  await t.scrollUntilVisible(
    find.text('Find my tracker'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(find.text('Find my tracker'));
  await t.pumpAndSettle();
  await t.tap(find.text('Find my tracker'));
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('Fitbit Air'));
  await t.pumpAndSettle();
  await t.tap(find.text('Fitbit Air'));
  await t.pumpAndSettle();
  return clock;
}

/// One simulated second: clock, sample, tick.
Future<void> _second(
  WidgetTester t,
  StepClock clock,
  FakeLiveHr live,
  int bpm, {
  bool rr = false,
  int i = 0,
}) async {
  clock.advance(1);
  live.emit(clock.now, bpm, rr: rr ? rrFor(i, bpm) : const []);
  await t.pump(Motion.tick);
}

int _workoutBpm(int s) => s < 60 ? 90 + s : (s < 600 ? 150 + (s % 20) : 160);

Future<void> _workout(
  WidgetTester t,
  StepClock clock,
  FakeLiveHr live,
  int seconds,
) async {
  await t.scrollUntilVisible(
    find.text('Start workout'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await t.tap(find.text('Start workout'));
  await t.pump();
  for (var s = 0; s < seconds; s++) {
    await _second(t, clock, live, _workoutBpm(s));
  }
}

void main() {
  setUpAll(loadAppFonts);

  test('Bluetooth errors map to what the user can do', () {
    // Verbatim flutter_blue_plus (Android) adapter-off error.
    expect(
      classifyLiveError(
        PlatformException(
          code: 'startScan',
          message: 'Bluetooth must be turned on',
        ),
      ),
      LiveError.bluetoothOff,
    );
    expect(
      classifyLiveError(
        Exception('Bluetooth permission denied (bluetoothScan)'),
      ),
      LiveError.permission,
    );
    expect(
      classifyLiveError(
        StateError('Bluetooth LE is not supported on this device'),
      ),
      LiveError.unsupported,
    );
    expect(
      classifyLiveError(UnimplementedError('not overridden')),
      LiveError.unavailable,
    );
    expect(classifyLiveError(Exception('boom')), LiveError.other);
  });

  test('typed LiveHrExceptions are classified by kind, not by message', () {
    const cases = {
      LiveHrErrorKind.bluetoothOff: LiveError.bluetoothOff,
      LiveHrErrorKind.permissionDenied: LiveError.permission,
      LiveHrErrorKind.unsupported: LiveError.unsupported,
      LiveHrErrorKind.connectFailed: LiveError.connectFailed,
      LiveHrErrorKind.linkLost: LiveError.connectFailed,
      LiveHrErrorKind.noHeartRateService: LiveError.noHeartRateService,
      LiveHrErrorKind.unknown: LiveError.other,
    };
    for (final e in cases.entries) {
      // A misleading message must not win over the kind.
      expect(
        classifyLiveError(
          LiveHrException(e.key, 'Bluetooth permission must be turned on'),
        ),
        e.value,
        reason: e.key.name,
      );
    }
  });

  testWidgets('no heart-rate service: says to turn on Share heart rate', (
    t,
  ) async {
    final live = FakeLiveHr()
      ..connectError = const LiveHrException(
        LiveHrErrorKind.noHeartRateService,
      );
    await pumpB(t, const LiveScreen(), repo: ScreensBRepo.demo(), live: live);
    await t.pumpAndSettle();
    await t.tap(find.text('Find my tracker'));
    await t.pumpAndSettle();
    await t.tap(find.text('Fitbit Air'));
    await t.pumpAndSettle();
    expect(find.text('Your tracker isn’t sharing heart rate'), findsOneWidget);
    expect(find.textContaining('Share heart rate'), findsWidgets);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('back during a workout asks before discarding it', (t) async {
    final live = FakeLiveHr();
    final clock = await _connect(t, live);
    await _workout(t, clock, live, 30);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Leave this session?'), findsOneWidget);
    await t.tap(find.text('Stay'));
    await t.pumpAndSettle();
    expect(find.text('Recording'), findsOneWidget);
  });

  testWidgets('scan → connect → samples → stop → HRR-60 → save', (t) async {
    final live = FakeLiveHr();
    final clock = await _connect(t, live);
    expect(live.connects, ['air-1']);
    await _second(t, clock, live, 64);
    expect(find.text('64'), findsOneWidget);

    await _workout(t, clock, live, 600);
    await t.pumpAndSettle();
    expect(find.text('10:00'), findsOneWidget); // elapsed
    expect(find.text('Recording'), findsOneWidget);

    await t.tap(find.text('Stop'));
    await t.pump();
    expect(find.textContaining('Stay still'), findsOneWidget);
    // Stop at 169 bpm; cool-down 160 → 128 over the minute.
    for (var s = 1; s <= 62; s++) {
      await _second(t, clock, live, 160 - (s * 32 ~/ 60).clamp(0, 32));
    }
    await t.pumpAndSettle();
    expect(find.text('Workout summary'), findsOneWidget);
    expect(find.text('Heart-rate recovery'), findsOneWidget);
    expect(find.text('−41'), findsOneWidget);

    await t.tap(find.text('Save workout'));
    await t.pumpAndSettle();
    expect(live.saved.single.$1, 'workout');
    // Saved samples end at Stop (the cool-down is not part of the workout).
    expect(live.saved.single.$2.length, 600);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('skipping the cool-down explains the missing HRR', (t) async {
    final live = FakeLiveHr();
    final clock = await _connect(t, live);
    await _workout(t, clock, live, 90);
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(find.textContaining('cool-down was skipped'), findsOneWidget);
  });

  testWidgets('HRV check is locked before connecting and without RR', (
    t,
  ) async {
    final live = FakeLiveHr();
    final clock = StepClock(DateTime(2026, 9, 28, 18));
    await pumpB(
      t,
      const LiveScreen(),
      repo: ScreensBRepo.demo(),
      live: live,
      clock: clock.call,
    );
    await t.pumpAndSettle();
    expect(find.textContaining('Unlocks after you connect'), findsOneWidget);
    expect(find.text('Start HRV check'), findsNothing);

    await t.tap(find.text('Find my tracker'));
    await t.pumpAndSettle();
    await t.tap(find.text('Fitbit Air'));
    await t.pumpAndSettle();
    for (var s = 0; s < kRrGraceSamples; s++) {
      await _second(t, clock, live, 62);
    }
    await t.pumpAndSettle();
    expect(find.text('HRV check unavailable'), findsOneWidget);
    expect(find.textContaining('RR intervals'), findsOneWidget);
    expect(find.text('Start HRV check'), findsNothing);
  });

  testWidgets('HRV check unlocks with RR and yields RMSSD, no stress index', (
    t,
  ) async {
    final live = FakeLiveHr();
    final clock = await _connect(t, live);
    await _second(t, clock, live, 62, rr: true);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Start HRV check'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Start HRV check'));
    await t.pump();
    expect(find.text('Sit still and breathe normally'), findsOneWidget);
    for (var s = 0; s < kHrvCheckSeconds + 1; s++) {
      await _second(t, clock, live, 62, rr: true, i: s);
    }
    await t.pumpAndSettle();
    expect(find.text('RMSSD'), findsOneWidget);
    // The Baevsky stress number is cut (product-critic review, 2026-09-29).
    expect(find.textContaining('Stress'), findsNothing);
    expect(find.textContaining('Baevsky'), findsNothing);
    expect(find.text('Beats analysed'), findsOneWidget);
    await t.tap(find.text('Save HRV check'));
    await t.pumpAndSettle();
    expect(live.saved.single.$1, 'hrv_check');
  });

  testWidgets('permission denial and Bluetooth off say what to do', (t) async {
    final live = FakeLiveHr()
      ..scanError = Exception('Bluetooth permission denied (bluetoothScan)');
    await pumpB(t, const LiveScreen(), repo: ScreensBRepo.demo(), live: live);
    await t.pumpAndSettle();
    await t.tap(find.text('Find my tracker'));
    await t.pumpAndSettle();
    expect(find.text('Bluetooth permission needed'), findsOneWidget);

    live.scanError = Exception('Bluetooth adapter is turned off');
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Bluetooth is off'), findsOneWidget);

    live.scanError = null;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Fitbit Air'), findsOneWidget);
  });

  testWidgets('no devices found gives the Share heart rate guidance', (
    t,
  ) async {
    final live = FakeLiveHr(devices: const []);
    await pumpB(t, const LiveScreen(), repo: ScreensBRepo.demo(), live: live);
    await t.pumpAndSettle();
    await t.tap(find.text('Find my tracker'));
    await t.pumpAndSettle();
    expect(find.text('No heart-rate sensors found'), findsOneWidget);
    expect(find.textContaining('Share heart rate'), findsWidgets);
  });

  testWidgets('a dropped link keeps the session and offers reconnect', (
    t,
  ) async {
    final live = FakeLiveHr();
    final clock = await _connect(t, live);
    await _workout(t, clock, live, 30);
    live.drop();
    await t.pump();
    await t.pump();
    expect(find.text('Connection lost'), findsOneWidget);
    await t.tap(find.text('Reconnect'));
    await t.pumpAndSettle();
    expect(live.connects.length, 2);
    await _second(t, clock, live, 150);
    expect(find.text('Connection lost'), findsNothing);
  });

  testWidgets('a reconnect that fails with Bluetooth off says so', (t) async {
    final live = FakeLiveHr();
    final clock = await _connect(t, live);
    await _workout(t, clock, live, 5);
    live.drop();
    await t.pump();
    await t.pump();
    live.connectError = const LiveHrException(LiveHrErrorKind.bluetoothOff);
    await t.tap(find.text('Reconnect'));
    await t.pumpAndSettle();
    expect(find.text('Bluetooth is off'), findsOneWidget);
  });

  testWidgets('the zone band draws all six segments at full height', (t) async {
    final live = FakeLiveHr();
    final clock = await _connect(t, live);
    await _second(t, clock, live, 150);
    final segments = find.descendant(
      of: find.byType(ZoneBand),
      matching: find.byType(DecoratedBox),
    );
    expect(segments, findsNWidgets(6));
    for (final e in segments.evaluate()) {
      expect((e.renderObject! as RenderBox).size.height, 12);
    }
  });

  testWidgets('leaving the screen disconnects', (t) async {
    final live = FakeLiveHr();
    await _connect(t, live);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    expect(live.disconnects, greaterThanOrEqualTo(1));
  });

  testWidgets('no overflow at 320 px and text scale 1.3 while recording', (
    t,
  ) async {
    final live = FakeLiveHr();
    final clock = await _connect(t, live, size: kSmall, textScale: 1.3);
    await _workout(t, clock, live, 20);
    await t.pumpAndSettle();
    await scrollThrough(t);
  });

  for (final b in const [Brightness.dark]) { // dark only
    testWidgets('golden intro · ${b.name}', (t) async {
      await pumpB(
        t,
        const LiveScreen(),
        repo: ScreensBRepo.demo(),
        live: FakeLiveHr(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/live_intro_${b.name}.png'),
      );
    });

    testWidgets('golden recording · ${b.name}', (t) async {
      final live = FakeLiveHr();
      final clock = await _connect(t, live, brightness: b);
      await _workout(t, clock, live, 754);
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/live_recording_${b.name}.png'),
      );
    });

    testWidgets('golden summary · ${b.name}', (t) async {
      final live = FakeLiveHr();
      final clock = await _connect(t, live, brightness: b);
      await _workout(t, clock, live, 754);
      await t.tap(find.text('Stop'));
      await t.pump();
      for (var s = 1; s <= 62; s++) {
        await _second(t, clock, live, 160 - (s * 29 ~/ 60).clamp(0, 29));
      }
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/live_summary_${b.name}.png'),
      );
    });
  }
}
