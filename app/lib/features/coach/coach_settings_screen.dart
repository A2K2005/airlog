// Settings → Coach (pushed at /settings/coach; Settings links here): the
// "Show coach" master switch, the engine, model and mode (into setup),
// today's cloud usage, the answer length, "Coach messages" (on or off; v1
// has no AI-written cards), What Coach knows, conversations, and turning the
// cloud engine off.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ask_entry.dart' show coachEnabledProvider;
import '../../app/copy.dart';
import '../../app/insight_card.dart' show insightLevelProvider;
import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/insight_contracts.dart';
import 'coach_providers.dart';

/// "3 of 50 questions · 12k of 200k tokens".
String usageLine(CoachUsage u) {
  String k(int n) => n < 1000
      ? '$n'
      : '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0).replaceFirst(RegExp(r'\.0$'), '')}k';
  final tokens = u.inputTokens + u.outputTokens;
  return '${u.requests} of ${u.requestLimit} questions · '
      '${k(tokens)} of ${k(u.tokenLimit)} tokens';
}

class CoachSettingsScreen extends ConsumerWidget {
  const CoachSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = P.of(context);
    final async = ref.watch(coachConfigProvider);
    final cfg = async.value;
    final c = cfg ?? const CoachConfig();

    Future<void> go(String route) async {
      await Navigator.of(context).pushNamed(route);
      ref.invalidate(coachConfigProvider);
    }

    Future<void> withdraw() async {
      final name = CoachCopy.providerName(c.provider);
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: dialogMotion(context),
        builder: (d) => AlertDialog(
          title: Text('Turn off $name?'),
          content: const Text(CoachCopy.withdrawBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(
                'Turn off',
                style: F.head.copyWith(color: P.of(d).on(C.recRed)),
              ),
            ),
          ],
        ),
      );
      if (yes != true) return;
      var ok = true;
      try {
        await withdrawCloud(ref.read(coachRepositoryProvider));
      } catch (_) {
        ok = false;
      }
      ref.invalidate(coachConfigProvider);
      if (context.mounted) {
        snack(
          context,
          ok
              ? 'Back to on-device. Your key was deleted.'
              : 'Could not turn it off. Try again.',
        );
      }
    }

    final engineSub = !c.cloud
        ? 'Nothing leaves your phone'
        : c.cloudReady
        ? 'Your key · ${CoachCopy.company(c.provider)} · '
              '${CoachCopy.model(c.provider, c.settings.model)?.cost ?? ''} '
              'per question'
        : 'Not set up yet: finish in setup';

    final usage = c.cloud ? ref.watch(coachUsageProvider).value : null;
    // Null until read (or when the insight service is not wired).
    final level = ref.watch(insightLevelProvider).value;
    final messagesOn = level != null && level != InsightLevel.off;

    Future<void> setShown(bool on) async {
      try {
        final repo = ref.read(coachRepositoryProvider);
        await repo.saveSettings((await repo.settings()).copyWith(enabled: on));
      } catch (_) {
        if (context.mounted) snack(context, 'Could not save. Try again.');
      }
      ref.invalidate(coachConfigProvider);
      ref.invalidate(coachEnabledProvider);
    }

    // On is InsightLevel.basic: on-device templates only.
    Future<void> setMessages(bool on) async {
      try {
        await ref
            .read(insightServiceProvider)
            .setLevel(on ? InsightLevel.basic : InsightLevel.off);
      } catch (_) {
        if (context.mounted) snack(context, 'Could not save. Try again.');
      }
      ref.invalidate(insightLevelProvider);
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text(CoachSettingsCopy.title),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: [
          if (cfg == null && async.hasError) ...[
            const StatusCard(
              title: 'Coach settings could not be read',
              body: 'Showing the defaults. Nothing was changed.',
              tone: StatusTone.warning,
            ),
            const SizedBox(height: S.x3),
          ],
          AppCard(
            key: const ValueKey('row-show-coach'),
            padding: const EdgeInsets.fromLTRB(S.card, S.x3, S.x3, S.x3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        CoachCopy.showCoach,
                        style: F.head.copyWith(color: p.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        CoachCopy.showCoachBody,
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: S.x3),
                Semantics(
                  label: CoachCopy.showCoach,
                  child: Switch(
                    key: const ValueKey('switch-show-coach'),
                    value: c.settings.enabled,
                    onChanged: cfg == null ? null : setShown,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x6),
          const OverLabel('Engine'),
          const SizedBox(height: S.x3),
          _Group(
            children: [
              _Row(
                key: const ValueKey('row-engine'),
                icon: c.cloud
                    ? Icons.cloud_outlined
                    : Icons.phone_android_rounded,
                title: c.engineLabel,
                subtitle: engineSub,
                onTap: () => go(Routes.coachSetup),
              ),
              _Row(
                key: const ValueKey('row-mode'),
                icon: c.settings.mode == CoachMode.generalOnly
                    ? Icons.menu_book_outlined
                    : Icons.insights_rounded,
                title: c.modeLabel,
                subtitle: c.settings.mode == CoachMode.generalOnly
                    ? 'Science and training info only; none of your data'
                    : 'Looks up your scores; every number is checked',
                onTap: () => go(Routes.coachSetup),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Answer length', style: F.head.copyWith(color: p.ink)),
                const SizedBox(height: S.x3),
                SegmentedControl<ResponseLength>(
                  values: ResponseLength.values,
                  selected: c.settings.length,
                  label: (l) =>
                      l == ResponseLength.brief ? 'Brief' : 'Detailed',
                  semanticsLabel: 'Answer length',
                  onChanged: cfg == null
                      ? (_) {}
                      : (l) async {
                          await saveLength(
                            ref.read(coachRepositoryProvider),
                            l,
                          );
                          ref.invalidate(coachConfigProvider);
                        },
                ),
              ],
            ),
          ),
          if (c.cloud) ...[
            const SizedBox(height: S.x3),
            AppCard(
              key: const ValueKey('row-backup-models'),
              padding: const EdgeInsets.fromLTRB(S.card, S.x3, S.x3, S.x3),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          CoachCopy.backupModels,
                          style: F.head.copyWith(color: p.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          CoachCopy.backupModelsBody(c.provider),
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Semantics(
                    label: CoachCopy.backupModels,
                    child: Switch(
                      key: const ValueKey('switch-backup-models'),
                      value: c.settings.backupModels,
                      onChanged: cfg == null
                          ? null
                          : (on) async {
                              try {
                                await saveBackupModels(
                                  ref.read(coachRepositoryProvider),
                                  on,
                                );
                              } catch (_) {
                                if (context.mounted) {
                                  snack(context, 'Could not save. Try again.');
                                }
                              }
                              ref.invalidate(coachConfigProvider);
                            },
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (usage != null) ...[
            const SizedBox(height: S.x3),
            AppCard(
              key: const ValueKey('row-usage'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    InsightCopy.usageTitle,
                    style: F.head.copyWith(color: p.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    usageLine(usage),
                    style: F.tab(F.cap).copyWith(color: p.ink2),
                  ),
                  if (usage.exhausted) ...[
                    const SizedBox(height: S.x1),
                    Text(
                      CoachCopy.usageSpent,
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: S.x6),
          AppCard(
            key: const ValueKey('row-coach-messages'),
            padding: const EdgeInsets.fromLTRB(S.card, S.x3, S.x3, S.x3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        InsightCopy.levelTitle,
                        style: F.head.copyWith(color: p.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        messagesOn
                            ? InsightCopy.messagesOnBody
                            : InsightCopy.messagesOffBody,
                        style: F.cap.copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: S.x3),
                Semantics(
                  label: InsightCopy.levelTitle,
                  child: Switch(
                    key: const ValueKey('switch-coach-messages'),
                    value: messagesOn,
                    onChanged: level == null ? null : setMessages,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x6),
          const OverLabel('On this phone'),
          const SizedBox(height: S.x3),
          _Group(
            children: [
              _Row(
                key: const ValueKey('row-memory'),
                icon: Icons.bookmark_border_rounded,
                title: 'What Coach knows',
                subtitle: !c.memoryOn
                    ? 'Memory off'
                    : c.memoryCount == 0
                    ? 'Nothing yet · only facts you confirm'
                    : '${c.memoryCount} '
                          '${c.memoryCount == 1 ? 'fact' : 'facts'} you '
                          'confirmed',
                onTap: () => go(Routes.coachMemory),
              ),
              _Row(
                key: const ValueKey('row-history'),
                icon: Icons.history_rounded,
                title: 'Conversations',
                subtitle: 'Kept on this phone; delete any or all',
                onTap: () => go(Routes.coachHistory),
              ),
            ],
          ),
          if (c.cloud) ...[
            const SizedBox(height: S.x6),
            const OverLabel('Consent'),
            const SizedBox(height: S.x3),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    CoachCopy.recipient(c.provider),
                    style: F.bodySm.copyWith(color: p.ink),
                  ),
                  const SizedBox(height: S.x1),
                  Text(
                    CoachCopy.retention(c.provider),
                    style: F.bodySm.copyWith(color: p.ink2),
                  ),
                  const SizedBox(height: S.x3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      key: const ValueKey('settings-withdraw'),
                      label: CoachSettingsCopy.withdrawTitle,
                      icon: Icons.power_settings_new_rounded,
                      kind: AppButtonKind.quiet,
                      accent: C.recRed,
                      onTap: withdraw,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: S.x5),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'How the coach handles your data',
              icon: Icons.lock_outline_rounded,
              kind: AppButtonKind.quiet,
              compact: true,
              onTap: () => Navigator.of(context).pushNamed(Routes.privacy),
            ),
          ),
          Text(CoachCopy.notMedical, style: F.cap.copyWith(color: p.ink3)),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: S.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: S.card + 34),
                child: Divider(height: 1, thickness: S.hair, color: p.line),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Pressable(
      onTap: onTap,
      scale: .985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.card, vertical: S.x3),
        child: Row(
          children: [
            Icon(icon, size: 20, color: p.ink2),
            const SizedBox(width: S.x4 - 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: F.head.copyWith(color: p.ink)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: F.cap.copyWith(color: p.ink3),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: p.ink3),
          ],
        ),
      ),
    );
  }
}
