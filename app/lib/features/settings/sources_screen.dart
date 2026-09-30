// Settings → Data sources: one tile per source, a status pill each, and one
// next step for every state (install, update, connect, allow, check again).
// Explanations live behind ⓘ; the screen itself carries no paragraph.
//
// Enhanced mode (the optional cloud source) is hidden entirely when this
// build has no sign-in set up: no developer hints, no dead buttons.

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/copy.dart' show hcTypeName;
import '../../app/hc_rationale.dart';
import '../../app/platform_services.dart';
import '../../app/route_names.dart';
import '../../app/screen_kit.dart' show IconBadge, InfoButton;
import '../../design/design.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import 'sources_view_model.dart';
import 'widgets/source_picker.dart';

/// Health Connect on Google Play (install, update, or "not compatible").
const kHealthConnectPlayUrl =
    'https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata';

/// The disclosure the cloud source's unverified-app rules require in-app
/// before sign-in (docs/PLAY_RELEASE.md §5). Shown in Enhanced mode's ⓘ
/// sheet and in the dialog before sign-in.
const kEnhancedDisclosure =
    'Enhanced mode signs in to your Google account and reads your own '
    'overnight data straight from Google. Google hasn’t verified this app '
    'yet, so it shows a warning before you continue. That’s expected while '
    'Enhanced mode is in beta. Your data goes from Google to this phone only. '
    'Airlog has no server. Turning it off signs you out and deletes that data '
    'from this phone.';

/// Health Connect's own settings screen (Android intent). Best effort: on
/// devices without the intent, the Play page opens instead.
const kHealthConnectSettingsUri =
    'intent:#Intent;action=android.health.connect.action.HEALTH_HOME_SETTINGS;end';

abstract final class _Copy {
  static const title = 'Data sources';
  static const demoLine = 'You’re looking at sample data.';
  static const connectMine = 'Connect my data';
  static const useMine = 'Use my data';
  static const yourSources = 'Your sources';
  static const notFoundLine =
      'Airlog couldn’t reach Health Connect on this phone.';
  static const unsupportedLine =
      'Health Connect isn’t available on this phone. Live heart rate over '
      'Bluetooth still works.';
  static const stillNotFound =
      'Still can’t reach Health Connect. You can get it from Google Play.';
  static const notInstalledLine = 'Install it to use your tracker’s data.';
  static const updateLine = 'Update it to keep reading your data.';
  static const notConnectedLine = 'Allow Airlog to read your tracker’s data.';
  static const deniedLine =
      'Android won’t ask again. Allow it in Health Connect.';
  static const readFromHc = 'Read from Health Connect';
  static const noRequest =
      'Android didn’t show the request. Allow the rest in Health Connect’s '
      'settings.';
}

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sourcesControllerProvider);
    final s = async.value;
    final List<Widget> body;
    if (s != null) {
      body = _content(context, ref, s);
    } else if (async.hasError) {
      body = [
        StatusCard(
          title: 'Couldn’t load data sources',
          body: 'Go back and try again.',
          tone: StatusTone.warning,
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(sourcesControllerProvider),
        ),
      ];
    } else {
      body = const [
        AppCard(child: SkeletonLines(lines: 4)),
        SizedBox(height: S.x3),
        AppCard(child: SkeletonLines(lines: 4)),
      ];
    }
    return _RefreshOnResume(
      onResume: () => ref.invalidate(sourcesControllerProvider),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(_Copy.title),
          actions: SampleDataChip.action(context),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
          children: body,
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, WidgetRef ref, SourcesState s) {
    final c = ref.read(sourcesControllerProvider.notifier);
    final open = ref.read(linkOpenerProvider);
    final hc = s.of(SourceKind.healthConnect);
    final gh = s.of(SourceKind.googleHealthApi);
    final ble = s.of(SourceKind.ble);
    final ctx = s.of(SourceKind.context);
    final pm = s.hc;
    // No permission state means the check itself failed (the view-model
    // swallowed an error), not that Health Connect can't run here.
    final avail = pm?.availability ?? HcAvailability.checkFailed;
    final connected =
        avail == HcAvailability.available && (hc?.connected ?? false);
    void openLive() => Navigator.of(context).pushNamed(Routes.live);
    final busy = s.busy == SourceKind.healthConnect;
    final enhanced = gh != null && gh.available;

    Future<void> getHc() => open(Uri.parse(kHealthConnectPlayUrl));

    Future<void> openHcSettings() async {
      final ok = await open(Uri.parse(kHealthConnectSettingsUri));
      if (!ok) await getHc();
    }

    Future<void> checkAgain() async {
      ref.invalidate(sourcesControllerProvider);
      final st = await ref.read(sourcesControllerProvider.future);
      if (!context.mounted) return;
      final a = st.hc?.availability ?? HcAvailability.checkFailed;
      if (a == HcAvailability.checkFailed) snack(context, _Copy.stillNotFound);
    }

    /// Rationale first, then the system sheet. When nothing changed (Android
    /// can skip the sheet once a type was refused), Health Connect's own
    /// settings open instead.
    Future<void> requestHc() async {
      if (!await showHcRationale(context)) return;
      final before = {...?pm?.granted};
      final st = await c.requestHealthConnect();
      if (!context.mounted || st == null) return;
      switch (st.availability) {
        case HcAvailability.notInstalled:
          snack(context, 'Install Health Connect from Google Play first.');
        case HcAvailability.updateRequired:
          snack(context, 'Update Health Connect from Google Play first.');
        case HcAvailability.unsupported:
          snack(context, _Copy.unsupportedLine);
        case HcAvailability.checkFailed:
          snack(context, _Copy.notFoundLine);
        case HcAvailability.available:
          final after = st.granted.toSet();
          if (connected && setEquals(before, after) && !st.allGranted) {
            await openHcSettings();
            if (context.mounted) snack(context, _Copy.noRequest);
          } else if (after.isEmpty) {
            snack(
              context,
              'Nothing shared yet. Airlog can’t read your data until you '
              'allow it.',
            );
          } else {
            snack(context, 'Reading ${after.length} kinds of data.');
          }
      }
    }

    Future<void> connectGoogle() async {
      final go = await showDialog<bool>(
        context: context,
        animationStyle: dialogMotion(context),
        builder: (d) => AlertDialog(
          title: const Text('Before you sign in'),
          content: const SingleChildScrollView(
            child: Text(kEnhancedDisclosure),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Continue to Google'),
            ),
          ],
        ),
      );
      if (go != true) return;
      final ok = await c.connectGoogle();
      if (!context.mounted) return;
      snack(
        context,
        ok
            ? 'Enhanced mode is on. The first sync can take a minute.'
            : 'Sign-in didn’t finish. Nothing was changed.',
      );
    }

    Future<void> disconnectGoogle() async {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: dialogMotion(context),
        builder: (d) => AlertDialog(
          title: const Text('Turn off Enhanced mode?'),
          content: const Text(
            'This signs you out and deletes the Enhanced mode data stored on '
            'this phone. Your data will come from Health Connect again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Turn off'),
            ),
          ],
        ),
      );
      if (yes == true) await c.disconnectGoogle();
    }

    // The Health Connect tile's one next step (the demo strip reuses it).
    final missingAny =
        pm != null &&
        (pm.missing.isNotEmpty || !pm.historyGranted || !pm.backgroundGranted);
    final (String label, VoidCallback? onTap, bool primary) = busy
        ? ('Waiting for Health Connect…', null, true)
        : switch (avail) {
            HcAvailability.checkFailed => ('Check again', checkAgain, true),
            // Nothing to install here: live heart rate still works.
            HcAvailability.unsupported => (
              'Open Live heart rate',
              openLive,
              true,
            ),
            HcAvailability.notInstalled => (
              'Install Health Connect',
              getHc,
              true,
            ),
            HcAvailability.updateRequired => (
              'Update Health Connect',
              getHc,
              true,
            ),
            HcAvailability.available when !connected && s.hcDeniedTwice => (
              'Open Health Connect settings',
              openHcSettings,
              true,
            ),
            HcAvailability.available when !connected => (
              _Copy.connectMine,
              requestHc,
              true,
            ),
            _ when missingAny => ('Allow the rest', requestHc, true),
            _ => ('Review permissions', requestHc, false),
          };
    final hcAction = AppButton(
      label: label,
      icon: switch (avail) {
        HcAvailability.checkFailed => Icons.refresh_rounded,
        HcAvailability.unsupported => Icons.monitor_heart_outlined,
        HcAvailability.notInstalled ||
        HcAvailability.updateRequired => Icons.open_in_new_rounded,
        _ => Icons.verified_user_outlined,
      },
      kind: primary ? AppButtonKind.primary : AppButtonKind.secondary,
      compact: true,
      onTap: onTap,
    );

    return [
      if (s.mode == DataMode.demo) ...[
        _DemoStrip(
          action: connected
              ? AppButton(
                  label: _Copy.useMine,
                  compact: true,
                  onTap: () =>
                      Navigator.of(context).pushNamed(Routes.settings),
                )
              : AppButton(
                  label: _Copy.connectMine,
                  compact: true,
                  onTap: busy ? null : onTap,
                ),
        ),
        const SizedBox(height: S.x5),
      ],
      _SectionLabel(
        _Copy.yourSources,
        info: InfoButton(
          title: 'One app each, never mixed',
          semanticLabel: 'About your sources',
          lede:
              'Each measurement comes from one app at a time, never an '
              'average. If you switch apps, Airlog learns your usual again '
              'instead of mixing the two.',
          children: [
            ExplainSection(
              title: 'First available wins',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (metric, order) in _priority(enhanced))
                    BulletLine(order, strong: '$metric:'),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: S.x2),
      _HealthConnectTile(
        status: hc,
        perms: pm,
        availability: avail,
        connected: connected,
        deniedTwice: s.hcDeniedTwice,
        action: hcAction,
        secondary: avail == HcAvailability.checkFailed
            ? AppButton(
                label: 'Get Health Connect',
                kind: AppButtonKind.quiet,
                compact: true,
                onTap: getHc,
              )
            : null,
        onToggle: (v) => c.setEnabled(SourceKind.healthConnect, v),
      ),
      if (enhanced) ...[
        const SizedBox(height: S.x3),
        _EnhancedTile(
          status: gh,
          busy: s.busy == SourceKind.googleHealthApi,
          onConnect: connectGoogle,
          onDisconnect: disconnectGoogle,
        ),
      ],
      if (ble != null || ctx != null) ...[
        const SizedBox(height: S.x3),
        SettingsTile(
          dividers: false,
          children: [
            if (ble != null) ...[
              SettingsSwitchRow(
                icon: Icons.bluetooth_rounded,
                accent: DomainColors.strain,
                title: 'Bluetooth heart rate',
                pill: FadeSwap(
                  swapKey: '${ble.available}${ble.connected}',
                  child: !ble.available
                      ? StatePill.tone(PillTone.off, 'Not available')
                      : ble.connected
                      ? StatePill.tone(PillTone.good, 'Connected')
                      : StatePill.tone(PillTone.off, 'Live only'),
                ),
                subtitle: 'Used only on the Live heart rate screen.',
                value: ble.enabled,
                onChanged: ble.available
                    ? (v) => c.setEnabled(SourceKind.ble, v)
                    : null,
              ),
              SettingsBlock(
                indent: true,
                top: 0,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    label: 'Open Live heart rate',
                    icon: Icons.monitor_heart_outlined,
                    kind: AppButtonKind.secondary,
                    compact: true,
                    onTap: () => Navigator.of(context).pushNamed(Routes.live),
                  ),
                ),
              ),
            ],
            if (ctx != null)
              SettingsSwitchRow(
                icon: Icons.apps_rounded,
                title: 'Other apps (weight)',
                pill: FadeSwap(
                  swapKey: ctx.enabled,
                  child: StatePill.tone(
                    ctx.enabled ? PillTone.good : PillTone.off,
                    ctx.enabled ? 'On' : 'Off',
                  ),
                ),
                subtitle: 'Use data from other apps',
                value: ctx.enabled,
                onChanged: ctx.available
                    ? (v) => c.setEnabled(SourceKind.context, v)
                    : null,
              ),
          ],
        ),
      ],
      if (connected || s.apps.isNotEmpty) ...[
        const SizedBox(height: S.x6),
        SourcePickerSection(state: s),
      ],
    ];
  }

  static List<(String, String)> _priority(bool enhanced) => enhanced
      ? const [
          (
            'HRV',
            'Deep-sleep HRV from Enhanced mode, else overnight HRV from Health '
                'Connect',
          ),
          (
            'Resting heart rate, sleep, breathing, skin temperature, workouts, '
                'steps, heart rate',
            'Health Connect, else Enhanced mode',
          ),
          (
            'Blood oxygen',
            'Health Connect (overnight, from any app), else Enhanced mode',
          ),
          ('Live heart rate', 'Bluetooth only'),
        ]
      : const [
          ('HRV', 'Overnight HRV from Health Connect'),
          (
            'Resting heart rate, sleep, breathing, skin temperature, workouts, '
                'steps, heart rate',
            'Health Connect',
          ),
          ('Blood oxygen', 'Health Connect (overnight, from any app)'),
          ('Live heart rate', 'Bluetooth only'),
        ];
}

/// An over-label with an ⓘ at its end.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.info});
  final String text;
  final Widget? info;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: OverLabel(text)),
      ?info,
    ],
  );
}

class _DemoStrip extends StatelessWidget {
  const _DemoStrip({required this.action});
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final line = Text(
      _Copy.demoLine,
      style: F.bodySm.copyWith(color: p.ink, fontWeight: FontWeight.w600),
    );
    return AppCard(
      tone: CardTone.tinted,
      accent: C.amber,
      padding: const EdgeInsets.fromLTRB(S.x3, S.x2, S.x3, S.x2),
      child: bigText(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconBadge(
                      icon: Icons.science_outlined,
                      accent: C.amber,
                      size: 32,
                    ),
                    const SizedBox(width: S.x3),
                    Expanded(child: line),
                  ],
                ),
                const SizedBox(height: S.x2),
                action,
              ],
            )
          : Row(
              children: [
                const IconBadge(
                  icon: Icons.science_outlined,
                  accent: C.amber,
                  size: 32,
                ),
                const SizedBox(width: S.x3),
                Expanded(child: line),
                const SizedBox(width: S.x2),
                action,
              ],
            ),
    );
  }
}

class _HealthConnectTile extends StatelessWidget {
  const _HealthConnectTile({
    required this.status,
    required this.perms,
    required this.availability,
    required this.connected,
    required this.deniedTwice,
    required this.action,
    required this.onToggle,
    this.secondary,
  });

  final SourceStatus? status;
  final HcPermissionState? perms;
  final HcAvailability availability;
  final bool connected;
  final bool deniedTwice;
  final Widget action;
  final Widget? secondary;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final pill = switch (availability) {
      HcAvailability.checkFailed => StatePill.tone(
        PillTone.attention,
        'Not found',
      ),
      HcAvailability.unsupported => StatePill.tone(
        PillTone.off,
        'Not available',
      ),
      HcAvailability.notInstalled => StatePill.tone(
        PillTone.attention,
        'Not installed',
      ),
      HcAvailability.updateRequired => StatePill.tone(
        PillTone.attention,
        'Update needed',
      ),
      HcAvailability.available when connected => StatePill.tone(
        PillTone.good,
        'Connected',
      ),
      _ => StatePill.tone(
        deniedTwice ? PillTone.attention : PillTone.off,
        'Not connected',
      ),
    };
    const info = InfoButton(
      title: 'Health Connect',
      lede:
          'Android’s shared health store. Your tracker’s app puts data there, '
          'and Airlog reads it.',
      children: [
        ExplainSection(title: 'What Airlog reads', child: HcRationaleList()),
        ExplainSection(
          title: 'Older history',
          body:
              'Lets Airlog read more than 30 days back, so it can learn your '
              'usual from day one.',
        ),
        ExplainSection(
          title: 'Background sync',
          body:
              'Lets Airlog read new data while it’s closed, so your scores '
              'and widget are ready when you wake up.',
        ),
      ],
    );
    final actions = SettingsBlock(
      child: Wrap(
        spacing: S.x4,
        runSpacing: S.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [action, ?secondary],
      ),
    );
    final pm = perms;
    if (!connected || pm == null) {
      final line = switch (availability) {
        HcAvailability.checkFailed => _Copy.notFoundLine,
        HcAvailability.unsupported => _Copy.unsupportedLine,
        HcAvailability.notInstalled => _Copy.notInstalledLine,
        HcAvailability.updateRequired => _Copy.updateLine,
        HcAvailability.available =>
          deniedTwice ? _Copy.deniedLine : _Copy.notConnectedLine,
      };
      return SettingsTile(
        title: 'Health Connect',
        icon: Icons.favorite_border_rounded,
        accent: C.health,
        status: FadeSwap(swapKey: pill.label, child: pill),
        info: info,
        dividers: false,
        children: [
          SettingsBlock(
            bottom: 0,
            child: Text(
              line,
              style: F.bodySm.copyWith(color: P.of(context).ink2),
            ),
          ),
          actions,
        ],
      );
    }
    final total = pm.granted.length + pm.missing.length;
    // Medium/12's recipe: dark where the header sits, green at the foot.
    return SettingsTile(
      glow: GlowRecipes.m12,
      title: 'Health Connect',
      icon: Icons.favorite_border_rounded,
      accent: C.health,
      status: FadeSwap(swapKey: pill.label, child: pill),
      info: info,
      dividers: false,
      children: [
        SettingsBlock(
          child: _Plate(
            child: DotStat(
              value: '${pm.granted.length}/$total',
              style: F.dot40,
              swap: true,
              caption: pm.missing.isEmpty
                  ? 'kinds of data allowed'
                  : 'kinds of data allowed · Not allowed: '
                        '${pm.missing.map(hcTypeName).join(', ')}',
            ),
          ),
        ),
        SettingsBlock(
          top: 0,
          child: _PairOrStack(
            first: _PermPlate(
              icon: Icons.history_rounded,
              title: 'Older history',
              allowed: pm.historyGranted,
            ),
            second: _PermPlate(
              icon: Icons.sync_rounded,
              title: 'Background sync',
              allowed: pm.backgroundGranted,
            ),
          ),
        ),
        if (status != null)
          SettingsSwitchRow(
            title: _Copy.readFromHc,
            value: status!.enabled,
            onChanged: onToggle,
          ),
        actions,
      ],
    );
  }
}

/// Two plates side by side, stacked at large text.
class _PairOrStack extends StatelessWidget {
  const _PairOrStack({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (bigText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: S.x2), second],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: S.x2),
          Expanded(child: second),
        ],
      ),
    );
  }
}

/// A sub-fact inside a tile: the Medium/19 plate.
class _Plate extends StatelessWidget {
  const _Plate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(S.x3),
    decoration: const BoxDecoration(color: C.plate, borderRadius: R.rPanel),
    child: child,
  );
}

class _PermPlate extends StatelessWidget {
  const _PermPlate({
    required this.icon,
    required this.title,
    required this.allowed,
  });
  final IconData icon;
  final String title;
  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return _Plate(
      child: Semantics(
        container: true,
        label: '$title: ${allowed ? 'allowed' : 'not allowed'}',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: allowed ? p.on(C.health) : p.ink2),
              const SizedBox(height: S.x2),
              Text(
                title,
                style: F.bodySm.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: S.x1 + 2),
              StatePill.tone(
                allowed ? PillTone.good : PillTone.off,
                allowed ? 'Allowed' : 'Not allowed',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnhancedTile extends StatelessWidget {
  const _EnhancedTile({
    required this.status,
    required this.busy,
    required this.onConnect,
    required this.onDisconnect,
  });
  final SourceStatus status;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final st = status;
    return SettingsTile(
      glow: GlowRecipes.m8,
      title: 'Enhanced mode (cloud)',
      icon: Icons.cloud_outlined,
      accent: C.lavender,
      status: Wrap(
        spacing: S.x1 + 2,
        runSpacing: S.x1,
        children: [
          if (st.beta) StatePill.tone(PillTone.beta, 'Beta'),
          FadeSwap(
            swapKey: st.connected,
            child: st.connected
                ? StatePill.tone(PillTone.good, 'On')
                : StatePill.tone(PillTone.off, 'Off'),
          ),
        ],
      ),
      info: const InfoButton(
        title: 'Enhanced mode (cloud)',
        lede:
            'Optional, and in beta. Adds overnight data from your tracker’s '
            'cloud account.',
        children: [
          ExplainSection(
            title: 'What it adds',
            body:
                'Blood oxygen overnight, a more accurate HRV from deep sleep, '
                'and breathing rate by sleep stage.',
          ),
          ExplainSection(title: 'How it works', body: kEnhancedDisclosure),
        ],
      ),
      dividers: false,
      children: [
        const SettingsBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OverLabel('Adds'),
              SizedBox(height: S.x2),
              Wrap(
                spacing: S.x2,
                runSpacing: S.x2,
                children: [
                  MetricChip(
                    label: 'Blood oxygen',
                    icon: Icons.water_drop_outlined,
                    style: MetricChipStyle.add,
                  ),
                  MetricChip(
                    label: 'Deep-sleep HRV',
                    icon: Icons.monitor_heart_outlined,
                    style: MetricChipStyle.add,
                  ),
                  MetricChip(
                    label: 'Breathing by sleep stage',
                    icon: Icons.air_rounded,
                    style: MetricChipStyle.add,
                  ),
                ],
              ),
            ],
          ),
        ),
        SettingsBlock(
          top: 0,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: st.connected
                ? AppButton(
                    label: busy ? 'Turning off…' : 'Turn off',
                    icon: Icons.logout_rounded,
                    kind: AppButtonKind.secondary,
                    compact: true,
                    onTap: busy ? null : onDisconnect,
                  )
                : AppButton(
                    label: busy ? 'Waiting for sign-in…' : 'Turn on Enhanced mode',
                    icon: Icons.login_rounded,
                    compact: true,
                    onTap: busy ? null : onConnect,
                  ),
          ),
        ),
      ],
    );
  }
}

/// Re-reads Sources when the app comes back to the foreground: permissions
/// and the apps found change in Health Connect's own screens (QA-13).
class _RefreshOnResume extends StatefulWidget {
  const _RefreshOnResume({required this.onResume, required this.child});
  final VoidCallback onResume;
  final Widget child;

  @override
  State<_RefreshOnResume> createState() => _RefreshOnResumeState();
}

class _RefreshOnResumeState extends State<_RefreshOnResume> {
  late final AppLifecycleListener _l = AppLifecycleListener(
    onResume: () => widget.onResume(),
  );

  @override
  void initState() {
    super.initState();
    _l;
  }

  @override
  void dispose() {
    _l.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
