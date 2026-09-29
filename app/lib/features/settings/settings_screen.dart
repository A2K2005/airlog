// Settings: data mode, sources, profile, sync log; export and delete; how
// the scores work, diagnostics, privacy, licences and versions.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/copy.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart' show kAlgoVersion;
import 'settings_view_model.dart';
import 'widgets/hold_to_confirm.dart';
import 'widgets/settings_rows.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(settingsControllerProvider);
    final s = async.value;
    final c = ref.read(settingsControllerProvider.notifier);
    final p = P.of(context);
    void go(String r) => Navigator.of(context).pushNamed(r);

    Future<void> export() async {
      final out = await c.export();
      if (!context.mounted) return;
      snack(
        context,
        out.ok
            ? 'Exported ${out.files} files. Choose where to keep them.'
            : 'Export failed: ${out.error}',
      );
    }

    Future<void> wipe() async {
      final ok = await c.wipe();
      if (!context.mounted) return;
      snack(
        context,
        ok
            ? 'Stored records deleted. Settings and keys kept.'
            : 'Deletion did not finish. Some records may already be removed.',
      );
    }

    // Screen readers: the hold becomes a tap, so confirm in a dialog.
    Future<void> confirmWipe() async {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: dialogMotion(context),
        builder: (d) => AlertDialog(
          title: const Text('${SettingsCopy.deleteTitle}?'),
          content: const Text(
            'Deletes stored readings, scores, journal entries, live sessions, '
            'coach chats and memories, and exports held by Airlog. Settings, '
            'profile, cloud keys and source sign-ins stay. Copies already shared '
            'elsewhere and records in Health Connect or Google stay. Demo data '
            'is regenerated in Demo mode. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(
                'Delete',
                style: F.head.copyWith(color: P.of(d).on(C.recRed)),
              ),
            ),
          ],
        ),
      );
      if (yes != true) return;
      await wipe();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: [
          const OverLabel('Data'),
          const SizedBox(height: S.x3),
          if (s?.error != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                s!.error!,
                style: F.bodySm.copyWith(color: p.on(C.recRed)),
              ),
            ),
            const SizedBox(height: S.x3),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Data mode', style: F.head.copyWith(color: p.ink)),
                const SizedBox(height: S.x3),
                ExcludeFocus(
                  excluding: s == null || s.busy != null,
                  child: AbsorbPointer(
                    absorbing: s == null || s.busy != null,
                    child: SegmentedControl<DataMode>(
                      values: DataMode.values,
                      selected: s?.mode ?? DataMode.demo,
                      label: (m) => m == DataMode.demo ? 'Demo' : 'Live',
                      semanticsLabel: 'Data mode',
                      onChanged: s == null || s.busy != null
                          ? (_) {}
                          : c.setMode,
                    ),
                  ),
                ),
                const SizedBox(height: S.x3),
                Text(
                  (s?.mode ?? DataMode.demo) == DataMode.demo
                      ? 'Sample data: 90 days generated on this phone, so you '
                            'can explore every screen. Nothing here is your data.'
                      : 'Live: your tracker’s data from Health Connect (and '
                            'Enhanced mode, if on). Demo and live data are kept '
                            'apart; switching never mixes them.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x3),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.hub_outlined,
                title: 'Sources',
                subtitle:
                    s?.sourcesSummary ??
                    'Health Connect, Enhanced mode, Bluetooth',
                onTap: () => go(Routes.sources),
              ),
              SettingsRow(
                icon: Icons.person_outline_rounded,
                title: 'Profile',
                subtitle:
                    s?.profileSummary ?? 'Birth year, sex, max heart rate',
                onTap: () => go(Routes.profile),
              ),
              SettingsRow(
                icon: Icons.receipt_long_outlined,
                title: 'Sync log',
                subtitle: 'Every sync, per data type',
                onTap: () => go(Routes.syncLog),
              ),
              // Never gated: this is where "Show coach" is turned back on.
              SettingsRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Coach',
                subtitle: 'Engine, messages and what it remembers',
                onTap: () => go(Routes.settingsCoach),
              ),
            ],
          ),
          const SizedBox(height: S.x6),
          const OverLabel('Your data'),
          const SizedBox(height: S.x3),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  SettingsCopy.exportTitle,
                  style: F.head.copyWith(color: p.ink),
                ),
                const SizedBox(height: S.x1),
                Text(
                  'Readings, scores and journal entries for the current data '
                  'mode and enabled sources, as CSV and JSON. This is a '
                  'readable export, not a restorable backup. Coach chats, '
                  'memory and settings are not included.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
                const SizedBox(height: S.x3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: s?.busy == 'export' ? 'Exporting…' : 'Export',
                    icon: Icons.ios_share_rounded,
                    kind: AppButtonKind.secondary,
                    onTap: s == null || s.busy != null ? null : export,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x3),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  SettingsCopy.deleteTitle,
                  style: F.head.copyWith(color: p.ink),
                ),
                const SizedBox(height: S.x1),
                Text(
                  'Deletes health records, journal entries, live sessions, '
                  'coach chats and memories, and exports held by Airlog. '
                  'Settings, profile, cloud keys and source sign-ins stay. '
                  'Shared copies stay elsewhere. Demo data is regenerated '
                  'in Demo mode.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
                const SizedBox(height: S.x3),
                HoldToConfirm(
                  label: s?.busy == 'wipe' ? 'Deleting…' : 'Hold to delete',
                  hint: 'Press and hold for two seconds to delete',
                  enabled: s != null && s.busy == null,
                  onConfirmed: wipe,
                  onAccessibleConfirm: confirmWipe,
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x6),
          const OverLabel('About'),
          const SizedBox(height: S.x3),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.functions_rounded,
                title: 'How scores work',
                subtitle: 'Every formula, constant and source',
                onTap: () => go(Routes.methodology),
              ),
              SettingsRow(
                icon: Icons.troubleshoot_rounded,
                title: 'Diagnostics',
                subtitle: 'What reaches this phone, per data type',
                onTap: () => go(Routes.diagnostics),
              ),
              SettingsRow(
                icon: Icons.lock_outline_rounded,
                title: 'Privacy',
                subtitle: 'Local by default. Optional cloud coach explained',
                onTap: () => go(Routes.privacy),
              ),
              SettingsRow(
                icon: Icons.gavel_rounded,
                title: 'Licences',
                subtitle: 'Pulse (Apache-2.0), Edge (MIT), DM Sans (OFL)',
                onTap: () => go(Routes.licenses),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          const SettingsGroup(
            children: [
              SettingsValueRow(
                title: 'Algorithm version',
                value: 'v$kAlgoVersion',
              ),
              SettingsValueRow(title: 'App version', value: kAppVersion),
            ],
          ),
          const SizedBox(height: S.x5),
          Text(
            'Not medical advice. Not affiliated with Google, Fitbit or WHOOP.',
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}
