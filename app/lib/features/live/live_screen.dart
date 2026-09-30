// Live heart rate over Bluetooth: find the tracker, see BPM / zone / strain as
// you train, measure heart-rate recovery after Stop, or run a 2-minute HRV
// check when the tracker sends beat-to-beat intervals.
//
// View only: every state and action is LiveController's.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/screen_kit.dart' show IconBadge, InfoButton;
import '../../design/design.dart';
import '../../domain/repositories.dart' show BleDevice;
import 'live_view_model.dart';
import 'widgets/live_widgets.dart';

class LiveScreen extends ConsumerWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(liveControllerProvider);
    final c = ref.read(liveControllerProvider.notifier);
    final title = switch (s.stage) {
      LiveStage.summary => 'Workout summary',
      LiveStage.hrvRunning || LiveStage.hrvResult => 'HRV check',
      _ => 'Live heart rate',
    };
    final Widget body = switch (s.stage) {
      LiveStage.intro => _Intro(state: s, onScan: c.startScan),
      LiveStage.scanning || LiveStage.devices => _Devices(
        state: s,
        onScan: c.startScan,
        onConnect: c.connect,
      ),
      LiveStage.connecting => _Connecting(device: s.device),
      LiveStage.connected ||
      LiveStage.recording ||
      LiveStage.coolDown => LiveDashboard(state: s, controller: c),
      LiveStage.summary => WorkoutSummary(state: s, controller: c),
      LiveStage.hrvRunning => HrvRunning(state: s, onCancel: c.cancelHrvCheck),
      LiveStage.hrvResult => HrvResult(state: s, controller: c),
      LiveStage.error => _Failure(state: s, onRetry: c.startScan),
    };
    // Back must not silently throw away a workout or an HRV check.
    final unsaved = switch (s.stage) {
      LiveStage.recording || LiveStage.coolDown || LiveStage.hrvRunning => true,
      LiveStage.summary => !s.saved,
      LiveStage.hrvResult => s.rmssd != null && !s.saved,
      _ => false,
    };
    return PopScope(
      canPop: !unsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          animationStyle: dialogMotion(context),
          builder: (d) => AlertDialog(
            title: const Text('Leave this workout?'),
            content: const Text(
              'Your workout isn’t saved yet. If you leave, it’s deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(d).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(d).pop(true),
                child: const Text('Delete and leave'),
              ),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(top: false, child: body),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.state, required this.onScan});
  final LiveState state;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x10),
      children: [
        GlowPanel(
          glow: GlowRecipes.m10,
          width: double.infinity,
          padding: const EdgeInsets.all(S.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(
                icon: Icons.monitor_heart_outlined,
                accent: C.recRed,
                size: 44,
              ),
              const SizedBox(height: S.x4),
              Semantics(
                header: true,
                child: Text(
                  'Live heart rate',
                  style: F.t1.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: S.x2),
              Text(
                'See your heart rate and effort as you train.',
                style: F.body.copyWith(color: p.ink),
              ),
              const SizedBox(height: S.x3),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 14, color: p.ink2),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: Text(
                      'Stays on this phone.',
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x6),
        const OverLabel('Before you start'),
        const SizedBox(height: S.x3),
        const SettingsTile(
          children: [
            SettingsRow(
              icon: Icons.looks_one_outlined,
              accent: DomainColors.strain,
              title: 'Turn on “Share heart rate”',
              subtitle: 'In your tracker’s app. Turn it off after.',
              trailing: _ShareInfo(),
            ),
            SettingsRow(
              icon: Icons.looks_two_outlined,
              accent: DomainColors.strain,
              title: 'Wear your tracker snug',
              subtitle: 'Keep your phone close.',
            ),
          ],
        ),
        const SizedBox(height: S.x6),
        AppButton(
          label: 'Find my tracker',
          icon: Icons.bluetooth_rounded,
          accent: DomainColors.strain,
          expand: true,
          onTap: onScan,
        ),
        const SizedBox(height: S.x6),
        const HrvCheckCard(state: null),
      ],
    );
  }
}

/// The ⓘ on the first step: how to turn sharing on, brand-free.
class _ShareInfo extends StatelessWidget {
  const _ShareInfo();

  @override
  Widget build(BuildContext context) => const InfoButton(
    title: 'Turn on heart-rate sharing',
    lede: 'Most trackers only send live heart rate while sharing is on.',
    children: [
      ExplainSection(
        title: 'Where to find it',
        body:
            'Open your tracker’s app and look for “Share heart rate” or '
            '“Heart-rate broadcast”.',
      ),
      ExplainSection(
        title: 'Battery',
        body: 'Sharing uses battery, so turn it off when you’re done.',
      ),
    ],
  );
}

String signalWords(int rssi) => rssi >= -60
    ? 'Strong signal'
    : rssi >= -75
    ? 'Good signal'
    : 'Weak signal';

class _Devices extends StatelessWidget {
  const _Devices({
    required this.state,
    required this.onScan,
    required this.onConnect,
  });
  final LiveState state;
  final VoidCallback onScan;
  final void Function(BleDevice) onConnect;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final scanning = state.stage == LiveStage.scanning;
    final none = !scanning && state.devices.isEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x10),
      children: [
        SectionHeader(
          title: 'Trackers nearby',
          subtitle: scanning
              ? 'Looking for trackers…'
              : 'Trackers sharing heart rate',
        ),
        const SizedBox(height: S.x4),
        for (final d in state.devices)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x3),
            child: AppCard(
              onTap: () => onConnect(d),
              semanticLabel: 'Connect to ${d.name}, ${signalWords(d.rssi)}',
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: p.wash(DomainColors.strain),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.bluetooth_rounded,
                      size: 20,
                      color: p.on(DomainColors.strain),
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          style: F.head.copyWith(color: p.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          signalWords(d.rssi),
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.ink3),
                ],
              ),
            ),
          ),
        if (none)
          StatusCard(
            title: 'No trackers found',
            body:
                'Most trackers only share heart rate while sharing is on. '
                'Turn on “Share heart rate” in your tracker’s app, keep it '
                'close, then look again.',
            actionLabel: 'Look again',
            onAction: onScan,
            icon: Icons.bluetooth_disabled_rounded,
          )
        else ...[
          const SizedBox(height: S.x2),
          Text(
            'Don’t see your tracker? Turn on “Share heart rate” in your '
            'tracker’s app, then look again.',
            style: F.cap.copyWith(color: p.ink3),
          ),
          if (!scanning) ...[
            const SizedBox(height: S.x3),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Look again',
                icon: Icons.refresh_rounded,
                kind: AppButtonKind.secondary,
                compact: true,
                onTap: onScan,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting({this.device});
  final BleDevice? device;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(S.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching_rounded, size: 40, color: p.ink2),
            const SizedBox(height: S.x4),
            Text(
              'Connecting to ${device?.name ?? 'your tracker'}…',
              textAlign: TextAlign.center,
              style: F.head.copyWith(color: p.ink),
            ),
            const SizedBox(height: S.x2),
            Text(
              'Keep your tracker close to the phone.',
              textAlign: TextAlign.center,
              style: F.bodySm.copyWith(color: p.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.state, required this.onRetry});
  final LiveState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (String title, String body, String? fix) = switch (state.error) {
      LiveError.permission => (
        'Bluetooth permission needed',
        'Airlog needs the “Nearby devices” permission to find your tracker. '
            'It’s used only while this screen is open, never for location.',
        'Allow it when Android asks, or in Android Settings → Apps → '
            'Airlog → Permissions.',
      ),
      LiveError.bluetoothOff => (
        'Bluetooth is off',
        'Turn Bluetooth on to connect to your tracker.',
        'Swipe down for Quick Settings and tap Bluetooth.',
      ),
      LiveError.unsupported => (
        'This phone can’t connect to trackers',
        'It doesn’t support the kind of Bluetooth that heart-rate trackers '
            'use.',
        null,
      ),
      LiveError.unavailable => (
        'Live heart rate isn’t available',
        'This version of Airlog can’t use Bluetooth.',
        null,
      ),
      LiveError.noHeartRateService => (
        'Your tracker isn’t sharing heart rate',
        'It connected, but it isn’t sharing heart rate, so there’s nothing to '
            'read.',
        'Turn on “Share heart rate” in your tracker’s app, then try again.',
      ),
      LiveError.connectFailed => (
        'Couldn’t connect',
        'Your tracker didn’t accept the connection. It may have stopped '
            'sharing heart rate, or another app is connected to it.',
        'Check that “Share heart rate” is on in your tracker’s app, then try '
            'again.',
      ),
      _ => (
        'Something went wrong',
        'The search for trackers stopped. Try again.',
        null,
      ),
    };
    final canRetry =
        state.error != LiveError.unsupported &&
        state.error != LiveError.unavailable;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x10),
      children: [
        StatusCard(
          title: title,
          body: body,
          fix: fix,
          tone: StatusTone.warning,
          icon: Icons.bluetooth_disabled_rounded,
          actionLabel: canRetry ? 'Try again' : null,
          onAction: canRetry ? onRetry : null,
        ),
      ],
    );
  }
}
