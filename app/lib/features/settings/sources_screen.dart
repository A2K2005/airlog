// Settings → Sources: where every number comes from, and the switches.
// One source per metric, picked by priority, never averaged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../app/platform_services.dart';
import 'sources_view_model.dart';
import 'widgets/source_picker.dart';
import '../../app/copy.dart' show hcTypeName;
import '../../app/hc_rationale.dart';

/// Health Connect on Google Play (for "not installed" / "update required").
const kHealthConnectPlayUrl =
    'https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata';

/// The disclosure the Google Health API's unverified-app rules require
/// in-app before sign-in (PRODUCT_PLAN §2.5, PLAY_RELEASE §5).
const kEnhancedDisclosure =
    'Enhanced mode signs in to Google with your account and reads your own '
    'data straight from the Google Health API. This build’s sign-in is not '
    'verified by Google yet, so Google shows an “unverified app” warning '
    'screen before you continue, and an unverified app can be used by at most '
    '100 people in total. The data goes from Google to this phone only: '
    'Airlog has no server. Disconnecting signs out and deletes the Google '
    'data stored here.';

/// Health Connect's own settings screen (Android intent). Best effort: on
/// devices without the intent, the Play page opens instead.
const kHealthConnectSettingsUri =
    'intent:#Intent;action=android.health.connect.action.HEALTH_HOME_SETTINGS;end';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sourcesControllerProvider);
    final s = async.value;
    final p = P.of(context);
    final List<Widget> body;
    if (s != null) {
      body = _cards(context, ref, s);
    } else if (async.hasError) {
      body = const [
        StatusCard(
          title: 'Sources could not load',
          body: 'The data store did not answer. Go back and try again.',
          tone: StatusTone.warning,
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
          title: const Text('Data sources'),
          actions: SampleDataChip.action(context),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
          children: [
            Text(
              'Each metric comes from one source, picked by priority, never '
              'averaged. Switching a metric’s source starts a new baseline '
              'instead of mixing two kinds of measurement.',
              style: F.bodySm.copyWith(color: p.ink2),
            ),
            const SizedBox(height: S.x4),
            ...body,
          ],
        ),
      ),
    );
  }

  List<Widget> _cards(BuildContext context, WidgetRef ref, SourcesState s) {
    final c = ref.read(sourcesControllerProvider.notifier);
    Widget gap(Widget w) => Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: w,
    );
    final hc = s.of(SourceKind.healthConnect);
    final gh = s.of(SourceKind.googleHealthApi);
    final ble = s.of(SourceKind.ble);
    final ctx = s.of(SourceKind.context);

    Future<void> connectHc() async {
      if (!await showHcRationale(context)) return;
      final st = await c.requestHealthConnect();
      if (!context.mounted || st == null) return;
      final msg = switch (st.availability) {
        HcAvailability.notInstalled =>
          'Install Health Connect from Google Play first.',
        HcAvailability.updateRequired =>
          'Update Health Connect from Google Play first.',
        HcAvailability.unsupported =>
          'Health Connect is not available on this device.',
        HcAvailability.available =>
          st.granted.isEmpty
              ? 'No access granted. Airlog cannot read your data without it.'
              : 'Reading ${st.granted.length} data types.',
      };
      snack(context, msg);
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
            : 'Sign-in did not complete. Nothing was changed.',
      );
    }

    Future<void> disconnectGoogle() async {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: dialogMotion(context),
        builder: (d) => AlertDialog(
          title: const Text('Turn off Enhanced mode?'),
          content: const Text(
            'Signs out of Google and deletes the Google Health data stored '
            'on this phone. Metrics fall back to Health Connect.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );
      if (yes == true) await c.disconnectGoogle();
    }

    return [
      if (s.mode == DataMode.demo)
        gap(
          AppCard(
            tone: CardTone.tinted,
            accent: C.amber,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 18,
                  color: P.of(context).on(C.amber),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(
                    'Sample data is in use. Connect Health Connect below; the '
                    'first grant switches Airlog to your own data.',
                    style: F.bodySm.copyWith(
                      color: P.of(context).ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (hc != null)
        gap(
          _HealthConnectCard(
            status: hc,
            perms: s.hc,
            busy: s.busy == SourceKind.healthConnect,
            onConnect: connectHc,
            onGet: () =>
                ref.read(linkOpenerProvider)(Uri.parse(kHealthConnectPlayUrl)),
            onToggle: (v) => c.setEnabled(SourceKind.healthConnect, v),
          ),
        ),
      if (gh != null)
        gap(
          _EnhancedCard(
            status: gh,
            busy: s.busy == SourceKind.googleHealthApi,
            onConnect: connectGoogle,
            onDisconnect: disconnectGoogle,
          ),
        ),
      if (ble != null)
        gap(
          _SourceCard(
            icon: Icons.bluetooth_rounded,
            title: 'Bluetooth heart rate',
            // `connected` is the real link (the data layer reports it).
            pill: !ble.available
                ? const StatePill(label: 'Unavailable', color: C.neutral)
                : ble.connected
                ? const StatePill(label: 'Connected', color: C.health)
                : const StatePill(label: 'Live only', color: C.sky),
            body:
                '${ble.detail}. Only while the Live screen is open; never a '
                'history source.',
            enabled: ble.enabled,
            onToggle: ble.available
                ? (v) => c.setEnabled(SourceKind.ble, v)
                : null,
            action: AppButton(
              label: 'Open live heart rate',
              icon: Icons.monitor_heart_outlined,
              kind: AppButtonKind.secondary,
              compact: true,
              onTap: () => Navigator.of(context).pushNamed(Routes.live),
            ),
          ),
        ),
      if (ctx != null)
        gap(
          _SourceCard(
            icon: Icons.apps_rounded,
            title: 'Other apps',
            pill: StatePill(
              label: ctx.enabled ? 'On' : 'Off',
              color: ctx.enabled ? C.health : C.neutral,
            ),
            body: '${ctx.detail}. Off until you turn it on.',
            enabled: ctx.enabled,
            onToggle: ctx.available
                ? (v) => c.setEnabled(SourceKind.context, v)
                : null,
            toggleLabel: 'Use context from other apps',
          ),
        ),
      if (s.hcDeniedTwice)
        gap(
          StatusCard(
            title: 'Health Connect won’t ask again',
            body:
                'Access was declined twice, so Android no longer shows the '
                'request. Grant it in Health Connect’s own settings.',
            actionLabel: 'Open Health Connect settings',
            onAction: () => ref.read(linkOpenerProvider)(
              Uri.parse(kHealthConnectSettingsUri),
            ),
          ),
        ),
      gap(SourcePickerSection(state: s)),
      const SizedBox(height: S.x3),
      const _PriorityCard(),
    ];
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.body,
    this.pill,
    this.enabled,
    this.onToggle,
    this.toggleLabel,
    this.action,
    this.children = const [],
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String body;
  final Widget? pill;
  final bool? enabled;
  final ValueChanged<bool>? onToggle;
  final String? toggleLabel;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 20, color: p.ink),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: F.head.copyWith(color: p.ink)),
                    if (subtitle != null)
                      Text(subtitle!, style: F.cap.copyWith(color: p.ink3)),
                    if (pill != null) ...[const SizedBox(height: S.x2), pill!],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Text(body, style: F.bodySm.copyWith(color: p.ink2)),
          ...children,
          if (enabled != null && onToggle != null) ...[
            const SizedBox(height: S.x2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    toggleLabel ?? 'Use this source',
                    style: F.bodySm.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Semantics(
                  label: toggleLabel ?? 'Use $title',
                  child: Switch(value: enabled!, onChanged: onToggle),
                ),
              ],
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: S.x3),
            Align(alignment: Alignment.centerLeft, child: action),
          ],
        ],
      ),
    );
  }
}

class _HealthConnectCard extends StatelessWidget {
  const _HealthConnectCard({
    required this.status,
    required this.perms,
    required this.busy,
    required this.onConnect,
    required this.onToggle,
    required this.onGet,
  });
  final SourceStatus status;
  final HcPermissionState? perms;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onGet;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final st = status;
    final pm = perms;
    final total = pm == null ? 0 : pm.granted.length + pm.missing.length;
    Widget check(String label, bool ok) => Padding(
      padding: const EdgeInsets.only(top: S.x1),
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_rounded
                : Icons.remove_circle_outline_rounded,
            size: 16,
            color: ok ? p.on(C.health) : p.ink3,
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(
              label,
              style: F.bodySm.copyWith(color: ok ? p.ink : p.ink2),
            ),
          ),
        ],
      ),
    );
    return _SourceCard(
      icon: Icons.favorite_border_rounded,
      title: 'Health Connect',
      subtitle: 'Main source · every app that writes to it',
      pill: st.connected
          ? const StatePill(label: 'Connected', color: C.health)
          : st.available
          ? const StatePill(label: 'Not connected', color: C.neutral)
          : const StatePill(label: 'Unavailable', color: C.amber),
      body: st.detail,
      enabled: st.available ? st.enabled : null,
      onToggle: st.available ? onToggle : null,
      toggleLabel: 'Read from Health Connect',
      action: _hcAction(st, pm?.availability, busy, onConnect, onGet),
      children: [
        if (pm != null && pm.availability == HcAvailability.available) ...[
          const SizedBox(height: S.x3),
          check(
            '${pm.granted.length} of $total data types granted',
            pm.allGranted,
          ),
          if (pm.missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(
                'Missing: ${pm.missing.map(hcTypeName).join(', ')}',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ),
          check('History (older than 30 days)', pm.historyGranted),
          check('Background reads (sync while closed)', pm.backgroundGranted),
        ],
      ],
    );
  }

  static Widget? _hcAction(
    SourceStatus st,
    HcAvailability? a,
    bool busy,
    VoidCallback onConnect,
    VoidCallback onGet,
  ) {
    if (a == HcAvailability.notInstalled ||
        a == HcAvailability.updateRequired) {
      return AppButton(
        label: a == HcAvailability.notInstalled
            ? 'Get Health Connect'
            : 'Update Health Connect',
        icon: Icons.open_in_new_rounded,
        compact: true,
        onTap: onGet,
      );
    }
    if (!st.available) return null;
    return AppButton(
      label: busy
          ? 'Waiting for Health Connect…'
          : st.connected
          ? 'Review permissions'
          : 'Connect Health Connect',
      icon: Icons.verified_user_outlined,
      kind: st.connected ? AppButtonKind.secondary : AppButtonKind.primary,
      compact: true,
      onTap: busy ? null : onConnect,
    );
  }
}

class _EnhancedCard extends StatelessWidget {
  const _EnhancedCard({
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
    final p = P.of(context);
    final st = status;
    final configured = st.available;
    return _SourceCard(
      icon: Icons.cloud_outlined,
      title: 'Enhanced mode',
      subtitle: 'Google Health API',
      pill: Wrap(
        spacing: S.x1 + 2,
        runSpacing: S.x1,
        children: [
          if (st.beta) const StatePill(label: 'Beta', color: C.lavender),
          !configured
              ? const StatePill(label: 'Not configured', color: C.neutral)
              : st.connected
              ? const StatePill(label: 'Signed in', color: C.health)
              : const StatePill(label: 'Off', color: C.neutral),
        ],
      ),
      body:
          'Adds overnight SpO₂, deep-sleep HRV (the cleanest Recovery input) '
          'and breathing rate by sleep stage. Optional.',
      action: _action(st, busy, onConnect, onDisconnect),
      children: [
        const SizedBox(height: S.x3),
        Container(
          padding: const EdgeInsets.all(S.x3),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: p.ink2),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  kEnhancedDisclosure,
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ),
            ],
          ),
        ),
        if (!configured) ...[
          const SizedBox(height: S.x3),
          Text(st.detail, style: F.tab(F.cap).copyWith(color: p.ink3)),
        ],
      ],
    );
  }

  static Widget _action(
    SourceStatus st,
    bool busy,
    VoidCallback onConnect,
    VoidCallback onDisconnect,
  ) => !st.available
      ? const AppButton(
          label: 'Connect Google Health',
          icon: Icons.login_rounded,
          kind: AppButtonKind.secondary,
          compact: true,
        )
      : st.connected
      ? AppButton(
          label: busy ? 'Disconnecting…' : 'Disconnect',
          icon: Icons.logout_rounded,
          kind: AppButtonKind.secondary,
          compact: true,
          onTap: busy ? null : onDisconnect,
        )
      : AppButton(
          label: busy ? 'Waiting for Google…' : 'Connect Google Health',
          icon: Icons.login_rounded,
          compact: true,
          onTap: busy ? null : onConnect,
        );
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard();

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    const rows = [
      (
        'HRV',
        'Deep-sleep RMSSD (Google Health API), else sleep-mean RMSSD (Health Connect)',
      ),
      (
        'Resting HR, sleep, breathing, skin temp, workouts, steps, HR',
        'Health Connect, else Google Health API',
      ),
      (
        'SpO₂',
        'Health Connect (overnight, from any app), else Google Health API',
      ),
      ('Live heart rate', 'Bluetooth only'),
    ];
    return AppCard(
      tone: CardTone.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OverLabel('Priority, first available wins'),
          const SizedBox(height: S.x3),
          for (final (metric, order) in rows)
            BulletLine(order, strong: '$metric:'),
          const SizedBox(height: S.x2),
          Text(
            'Each metric reads one app’s records (see above); a change of '
            'app starts a new baseline.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
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
