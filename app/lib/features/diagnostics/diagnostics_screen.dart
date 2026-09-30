// Diagnostics: the Phase 0 probe (PRODUCT_PLAN §5, DAY1_CHECKLIST), as a
// data check. A hero to run it; three counts; what the numbers mean; the app
// each measurement reads; then, per data type, the records, how often they
// arrive, which apps wrote them and the devices. Power-user detail (package
// and type names) stays: it is data. In sample-data mode everything is
// labelled as sample.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/copy.dart' show hcTypeName;
import '../../app/screen_kit.dart' show IconBadge, InfoButton;
import '../../design/design.dart';
import '../../domain/repositories.dart';
import 'diagnostics_view_model.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(diagnosticsControllerProvider);
    final c = ref.read(diagnosticsControllerProvider.notifier);
    final p = P.of(context);
    final r = s.report;

    Future<void> share() async {
      final ok = await c.share();
      if (!context.mounted) return;
      if (!ok) snack(context, 'Nothing to share yet. Run the check first.');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: [
          SettingsTile(
            glow: GlowRecipes.m5,
            title: 'Check your data',
            icon: Icons.troubleshoot_rounded,
            accent: C.sky,
            dividers: false,
            info: const InfoButton(
              title: 'Diagnostics',
              children: [
                ExplainSection(
                  title: 'When to run it',
                  body: 'Best run the morning after your first night.',
                ),
                ExplainSection(
                  title: 'What it shows',
                  body:
                      'Every kind of data that arrived, which app wrote it, '
                      'and how often.',
                ),
              ],
            ),
            children: [
              SettingsBlock(
                bottom: 0,
                child: Text(
                  'See what reaches this phone from your tracker.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
              ),
              SettingsBlock(
                top: S.x3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedControl<int>(
                      values: const [7, 14, 30],
                      selected: s.windowDays,
                      label: (d) => '$d days',
                      semanticsLabel: 'How far back to check',
                      onChanged: c.setWindow,
                    ),
                    const SizedBox(height: S.x3),
                    AppButton(
                      label: s.running
                          ? 'Checking…'
                          : 'Check the last ${s.windowDays} days',
                      icon: Icons.troubleshoot_rounded,
                      expand: true,
                      onTap: s.running ? null : c.run,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (s.demo) ...[
            const SizedBox(height: S.x3),
            AppCard(
              tone: CardTone.tinted,
              accent: C.amber,
              padding: const EdgeInsets.fromLTRB(S.x3, S.x2, S.x3, S.x2),
              child: Row(
                children: [
                  const IconBadge(
                    icon: Icons.science_outlined,
                    accent: C.amber,
                    size: 32,
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                      'This checks the sample data, not a tracker.',
                      style: F.bodySm.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: S.x5),
          if (s.running && r == null)
            const AppCard(child: SkeletonLines(lines: 6)),
          if (s.error != null)
            StatusCard(
              title: 'The check stopped',
              body: s.error!,
              tone: StatusTone.warning,
              actionLabel: 'Try again',
              onAction: c.run,
            ),
          if (r != null) ..._report(context, s, r, share),
        ],
      ),
    );
  }

  List<Widget> _report(
    BuildContext context,
    DiagnosticsState s,
    DiagnosticsReport r,
    VoidCallback share,
  ) {
    final p = P.of(context);
    final records = r.types.fold<int>(0, (a, t) => a + t.records);
    return [
      _Counts([
        ('${r.windowDays}', 'Days checked'),
        ('${r.types.length}', 'Kinds of data'),
        ('$records', 'Records'),
      ]),
      const SizedBox(height: S.x3),
      Text(
        '${s.demo ? 'Sample data · ' : ''}Checked ${dayTime(r.generatedAt)} · '
        'last ${r.windowDays} days · ${r.types.length} kinds of data',
        style: F.tab(F.cap).copyWith(color: p.ink3),
      ),
      const SizedBox(height: S.x6),
      const SectionHeader(
        title: 'What this means',
        subtitle: 'How Airlog will use this data',
      ),
      const SizedBox(height: S.x3),
      SettingsTile(
        children: [for (final v in r.verdicts) _Verdict(text: v)],
      ),
      if (s.sources.isNotEmpty) ...[
        const SizedBox(height: S.x6),
        const SectionHeader(
          title: 'App for each measurement',
          subtitle: 'The app each one comes from, and the others found',
        ),
        const SizedBox(height: S.x3),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in s.sources)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x1),
                  child: KeyValueLine(
                    row.metric.code,
                    '${row.chosen}${row.automatic ? ' (automatic)' : ''} · '
                    '${row.chosenDays} of 14 days'
                    '${row.alternatives.isEmpty ? '' : ' · also ${row.alternatives.entries.map((e) => '${e.key} ${e.value} of 14').join(', ')}'}',
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: S.x6),
      const SectionHeader(title: 'By kind of data'),
      const SizedBox(height: S.x3),
      if (r.types.isEmpty)
        const StatusCard(
          title: 'Nothing arrived',
          body:
              'Nothing came in from any app in this time. Check that your '
              'tracker’s app syncs to Health Connect and that Airlog is '
              'allowed to read it.',
          tone: StatusTone.warning,
        ),
      for (final t in r.types)
        Padding(
          padding: const EdgeInsets.only(bottom: S.x3),
          child: _TypeCard(
            stat: t,
            demo: s.demo,
            inUse: {for (final row in s.sources) row.chosen},
          ),
        ),
      const SizedBox(height: S.x2),
      AppButton(
        label: 'Share raw report (JSON)',
        icon: Icons.ios_share_rounded,
        kind: AppButtonKind.secondary,
        expand: true,
        onTap: r.rawJsonPath == null ? null : share,
      ),
      if (r.rawJsonPath == null) ...[
        const SizedBox(height: S.x2),
        Text(
          'Couldn’t save the report on this phone.',
          textAlign: TextAlign.center,
          style: F.cap.copyWith(color: p.ink3),
        ),
      ],
    ];
  }
}

/// Three dot-matrix counts, stacked at large text.
class _Counts extends StatelessWidget {
  const _Counts(this.items);
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    Widget tile((String, String) it) => AppCard(
      padding: const EdgeInsets.all(S.x4),
      child: DotStat(
        value: it.$1,
        caption: it.$2,
        style: F.dot32,
        semanticsLabel: '${it.$1} ${it.$2}',
      ),
    );
    if (bigText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x2),
            tile(items[i]),
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: S.x3),
            Expanded(child: tile(items[i])),
          ],
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final v = splitVerdict(text);
    final pig = v.concern ? C.amber : C.health;
    return Semantics(
      container: true,
      label: text,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: S.card,
            vertical: S.x3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: v.concern
                    ? Icons.error_outline_rounded
                    : Icons.check_rounded,
                accent: pig,
                size: 32,
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.finding,
                      style: F.bodySm.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (v.decision != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '→ ${v.decision!}',
                        style: F.bodySm.copyWith(color: p.ink2),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.stat,
    required this.demo,
    this.inUse = const {},
  });
  final DiagnosticsTypeStat stat;
  final bool demo;

  /// Apps (display names or packages) that some metric reads.
  final Set<String> inUse;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final t = stat;
    final origins = t.origins.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final devices = t.devices.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    Widget plate(String value, String label) => Container(
      padding: const EdgeInsets.all(S.x3),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rPanel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: F
                .tab(F.bodySm)
                .copyWith(color: p.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(label, style: F.cap.copyWith(color: p.ink3)),
        ],
      ),
    );
    final plates = [
      plate(
        t.medianSpacingSec == null
            ? 'n/a'
            : spacingWords(t.medianSpacingSec!),
        'Median spacing',
      ),
      plate(
        t.samplesPerHour == null
            ? 'n/a'
            : t.samplesPerHour!.toStringAsFixed(1),
        'Samples per hour',
      ),
      if (t.first != null && t.last != null)
        plate('${dayTime(t.first!)} →\n${dayTime(t.last!)}', 'First → last'),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hcTypeName(t.dataType),
                      style: F.head.copyWith(color: p.ink),
                    ),
                    Text(t.dataType, style: F.micro.copyWith(color: p.ink3)),
                  ],
                ),
              ),
              const SizedBox(width: S.x2),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: DotStat(
                    value: '${t.records}',
                    caption: 'records',
                    style: F.dot24,
                    semanticsLabel: '${t.records} records',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [for (final pl in plates) pl],
          ),
          if (origins.isNotEmpty) ...[
            const SizedBox(height: S.x3),
            const OverLabel('Written by'),
            const SizedBox(height: S.x2),
            for (final o in origins)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        o.key,
                        style: F.tab(F.cap).copyWith(color: p.ink),
                      ),
                    ),
                    const SizedBox(width: S.x2),
                    Text(
                      '${o.value}',
                      style: F.tab(F.cap).copyWith(color: p.ink2),
                    ),
                    const SizedBox(width: S.x2),
                    if (inUse.contains(o.key))
                      StatePill.tone(PillTone.good, 'In use')
                    else if (demo)
                      StatePill.tone(PillTone.attention, 'Sample')
                    else
                      StatePill.tone(PillTone.off, 'Available'),
                  ],
                ),
              ),
          ],
          if (devices.isNotEmpty) ...[
            const SizedBox(height: S.x3),
            const OverLabel('Device'),
            const SizedBox(height: S.x2),
            for (final d in devices)
              Text(
                '${d.key} · ${d.value}',
                style: F
                    .tab(F.cap)
                    .copyWith(
                      color: d.key.toLowerCase().contains('air')
                          ? p.ink
                          : p.on(C.amber),
                    ),
              ),
          ],
        ],
      ),
    );
  }
}
