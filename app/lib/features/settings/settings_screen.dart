// Settings: sample data or my data, sources, profile, sync log and coach;
// export and delete; how the scores work, diagnostics, privacy, licences and
// versions. Tiles and rows, one idea each; the explanations live behind ⓘ.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/copy.dart';
import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../app/screen_kit.dart' show InfoButton;
import '../../design/design.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart' show kAlgoVersion;
import 'settings_view_model.dart';
import 'widgets/hold_to_confirm.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(settingsControllerProvider);
    final s = async.value;
    final c = ref.read(settingsControllerProvider.notifier);
    final now = ref.watch(currentTimeProvider);
    final p = P.of(context);
    void go(String r) => Navigator.of(context).pushNamed(r);
    final idle = s != null && s.busy == null;
    final mode = s?.mode ?? DataMode.demo;

    Future<void> export() async {
      final out = await c.export();
      if (!context.mounted) return;
      snack(
        context,
        out.ok
            ? 'Exported ${out.files} files. Choose where to keep them.'
            : 'Couldn’t export: ${out.error}',
      );
    }

    Future<void> wipe() async {
      final ok = await c.wipe();
      if (!context.mounted) return;
      snack(
        context,
        ok
            ? 'Your data was deleted. Settings and keys are kept.'
            : 'Delete didn’t finish. Some data may already be gone.',
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
            'This deletes your readings, scores, journal, workouts, coach '
            'chats and memories, and any exports Airlog stored. Your '
            'settings, profile, keys and sign-ins stay. Data in Health '
            'Connect or your Enhanced mode account, and copies you already '
            'shared, stay too. With sample data on, fresh sample data is '
            'made. This can’t be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(
                SettingsCopy.deleteTitle,
                style: F.head.copyWith(color: P.of(d).on(C.recRed)),
              ),
            ),
          ],
        ),
      );
      if (yes != true) return;
      await wipe();
    }

    final (pillLabel, pillTone) =
        s?.sourcesPill ?? ('Health Connect', PillTone.off);
    final lastSync = s?.lastSyncAt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: [
          const _Label(
            'Data',
            info: InfoButton(
              title: 'Sample data and my data',
              children: [
                ExplainSection(
                  title: 'Sample data',
                  body:
                      '90 days of made-up data, made on this phone, so you '
                      'can look around. None of it is yours.',
                ),
                ExplainSection(
                  title: 'My data',
                  body:
                      'Your tracker’s data from Health Connect (and Enhanced '
                      'mode, if it’s on).',
                ),
                ExplainSection(
                  title: 'Kept apart',
                  body:
                      'Sample data and your data are stored apart. Switching '
                      'never mixes them.',
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x2),
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
          NavTileGrid(
            children: [
              NavTile(
                icon: Icons.science_outlined,
                accent: C.amber,
                title: 'Sample data',
                caption: 'Made on this phone',
                selected: mode == DataMode.demo,
                onTap: idle ? () => c.setMode(DataMode.demo) : null,
              ),
              NavTile(
                icon: Icons.favorite_border_rounded,
                accent: C.health,
                title: 'My data',
                caption: 'From your tracker',
                selected: mode == DataMode.live,
                onTap: idle ? () => c.setMode(DataMode.live) : null,
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          NavTileGrid(
            children: [
              NavTile(
                icon: Icons.hub_outlined,
                accent: C.health,
                title: 'Data sources',
                status: FadeSwap(
                  swapKey: pillLabel,
                  child: StatePill.tone(pillTone, pillLabel),
                ),
                semanticLabel: 'Data sources. $pillLabel.',
                onTap: () => go(Routes.sources),
              ),
              NavTile(
                icon: Icons.person_outline_rounded,
                accent: C.sky,
                title: 'Profile',
                caption:
                    s?.profileSummary ?? 'Birth year, sex, max heart rate',
                onTap: () => go(Routes.profile),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          SettingsTile(
            children: [
              SettingsRow(
                icon: Icons.receipt_long_outlined,
                title: 'Sync log',
                subtitle: lastSync == null
                    ? 'Nothing synced yet'
                    : 'Last sync ${ago(lastSync, now)}',
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
          SettingsTile(
            dividers: false,
            children: [
              const SettingsRow(
                icon: Icons.ios_share_rounded,
                accent: C.sky,
                title: SettingsCopy.exportTitle,
                subtitle: 'CSV and JSON files. A copy, not a backup.',
                trailing: InfoButton(
                  title: SettingsCopy.exportTitle,
                  children: [
                    ExplainSection(
                      title: 'What’s in it',
                      body:
                          'Your readings, scores and journal for the data '
                          'you’re looking at now, as CSV and JSON files you '
                          'can open in a spreadsheet.',
                    ),
                    ExplainSection(
                      title: 'What’s not',
                      body:
                          'Coach chats, memories and settings aren’t '
                          'included. It’s a copy to read, not a backup to '
                          'restore.',
                    ),
                  ],
                ),
              ),
              SettingsBlock(
                indent: true,
                top: 0,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    label: s?.busy == 'export' ? 'Exporting…' : 'Export',
                    icon: Icons.ios_share_rounded,
                    kind: AppButtonKind.secondary,
                    compact: true,
                    onTap: idle ? export : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          SettingsTile(
            dividers: false,
            children: [
              const SettingsRow(
                icon: Icons.delete_outline_rounded,
                accent: C.recRed,
                title: SettingsCopy.deleteTitle,
                subtitle:
                    'Deletes your readings, scores, journal and chats. '
                    'Settings and keys stay.',
                trailing: InfoButton(
                  title: SettingsCopy.deleteTitle,
                  children: [
                    ExplainSection(
                      title: 'What’s deleted',
                      body:
                          'Your readings, scores, journal, workouts, coach '
                          'chats and memories, and any exports Airlog stored.',
                    ),
                    ExplainSection(
                      title: 'What stays',
                      body:
                          'Your settings, profile, keys and sign-ins. Data in '
                          'Health Connect or your Enhanced mode account. '
                          'Copies you already shared.',
                    ),
                    ExplainSection(
                      title: 'With sample data on',
                      body: 'Fresh sample data is made again.',
                    ),
                  ],
                ),
              ),
              SettingsBlock(
                top: 0,
                child: HoldToConfirm(
                  label: s?.busy == 'wipe' ? 'Deleting…' : 'Hold to delete',
                  hint: 'Press and hold for two seconds to delete',
                  enabled: idle,
                  onConfirmed: wipe,
                  onAccessibleConfirm: confirmWipe,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x6),
          const OverLabel('About'),
          const SizedBox(height: S.x3),
          SettingsTile(
            children: [
              SettingsRow(
                icon: Icons.functions_rounded,
                title: 'How scores work',
                onTap: () => go(Routes.methodology),
              ),
              SettingsRow(
                icon: Icons.troubleshoot_rounded,
                title: 'Diagnostics',
                onTap: () => go(Routes.diagnostics),
              ),
              SettingsRow(
                icon: Icons.lock_outline_rounded,
                title: 'Privacy',
                onTap: () => go(Routes.privacy),
              ),
              SettingsRow(
                icon: Icons.gavel_rounded,
                title: 'Licences and credits',
                onTap: () => go(Routes.licenses),
              ),
              const SettingsValueRow(
                title: 'Score formula version',
                value: '$kAlgoVersion',
              ),
              const SettingsValueRow(title: 'App version', value: kAppVersion),
            ],
          ),
          const SizedBox(height: S.x5),
          Text(
            'Not medical advice.',
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}

/// An over-label with an ⓘ at its end.
class _Label extends StatelessWidget {
  const _Label(this.text, {required this.info});
  final String text;
  final Widget info;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: OverLabel(text)),
      info,
    ],
  );
}
