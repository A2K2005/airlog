// Diagnostics: the Phase 0 probe (PRODUCT_PLAN §5, DAY1_CHECKLIST). Per data
// type: records, which apps wrote them (the Fitbit app flagged), devices,
// first / last, median spacing, samples per hour; then the decisions those
// numbers settle. In demo mode everything is labelled synthetic.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/design.dart';
import '../../domain/repositories.dart';
import '../../app/copy.dart' show hcTypeName;
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
      if (!ok) snack(context, 'No dump to share yet. Run the probe first.');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: [
          Text(
            'What actually reaches this phone from your tracker, per data '
            'type and app. Run it the morning after your first night.',
            style: F.bodySm.copyWith(color: p.ink2),
          ),
          const SizedBox(height: S.x4),
          if (s.demo) ...[
            AppCard(
              tone: CardTone.tinted,
              accent: C.amber,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.science_outlined, size: 18, color: p.on(C.amber)),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Synthetic data',
                          style: F.head.copyWith(color: p.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'In demo mode the probe describes the demo generator, '
                          'not a real band. Connect Health Connect and switch '
                          'to Live for the real probe.',
                          style: F.bodySm.copyWith(color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.x3),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Look back',
                  style: F.bodySm.copyWith(
                    color: p.ink2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: S.x2),
                SegmentedControl<int>(
                  values: const [7, 14, 30],
                  selected: s.windowDays,
                  label: (d) => '$d days',
                  semanticsLabel: 'Probe window',
                  onChanged: c.setWindow,
                ),
                const SizedBox(height: S.x4),
                AppButton(
                  label: s.running
                      ? 'Reading…'
                      : 'Run probe (${s.windowDays} days)',
                  icon: Icons.troubleshoot_rounded,
                  expand: true,
                  onTap: s.running ? null : c.run,
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x5),
          if (s.running && r == null)
            const AppCard(child: SkeletonLines(lines: 6)),
          if (s.error != null)
            StatusCard(
              title: 'The probe stopped',
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
    return [
      Text(
        '${s.demo ? 'Synthetic · ' : ''}Generated ${dayTime(r.generatedAt)} · '
        'last ${r.windowDays} days · ${r.types.length} data types',
        style: F.tab(F.cap).copyWith(color: p.ink3),
      ),
      const SizedBox(height: S.x4),
      const SectionHeader(
        title: 'Decisions',
        subtitle: 'What the numbers settle',
      ),
      const SizedBox(height: S.x3),
      for (final v in r.verdicts)
        Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: _Verdict(text: v),
        ),
      if (s.sources.isNotEmpty) ...[
        const SizedBox(height: S.x4),
        const SectionHeader(
          title: 'App per metric',
          subtitle: 'The app each metric reads, and the others found',
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
                    '${row.chosen}${row.automatic ? ' (auto)' : ''} · '
                    '${row.chosenDays}/14 days'
                    '${row.alternatives.isEmpty ? '' : ' · also ${row.alternatives.entries.map((e) => '${e.key} ${e.value}/14').join(', ')}'}',
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: S.x4),
      const SectionHeader(title: 'Per data type'),
      const SizedBox(height: S.x3),
      if (r.types.isEmpty)
        const StatusCard(
          title: 'Nothing arrived',
          body:
              'No records from any app in this window. Check that your '
              'tracker’s app syncs to Health Connect and that Airlog has '
              'permission.',
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
        label: 'Share JSON dump',
        icon: Icons.ios_share_rounded,
        kind: AppButtonKind.secondary,
        expand: true,
        onTap: r.rawJsonPath == null ? null : share,
      ),
      if (r.rawJsonPath == null) ...[
        const SizedBox(height: S.x2),
        Text(
          'The dump could not be written on this device.',
          textAlign: TextAlign.center,
          style: F.cap.copyWith(color: p.ink3),
        ),
      ],
    ];
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
    return AppCard(
      semanticLabel: text,
      padding: const EdgeInsets.fromLTRB(S.x4, S.x3 + 2, S.x4, S.x3 + 2),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                v.concern
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 18,
                color: p.on(pig),
              ),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: p.ink2,
                          ),
                        ),
                        const SizedBox(width: S.x1 + 2),
                        Expanded(
                          child: Text(
                            v.decision!,
                            style: F.bodySm.copyWith(color: p.ink2),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${t.records}', style: F.n24.copyWith(color: p.ink)),
                  Text('RECORDS', style: F.over.copyWith(color: p.ink3)),
                ],
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          if (t.first != null) KeyValueLine('First', dayTime(t.first!)),
          if (t.last != null) KeyValueLine('Last', dayTime(t.last!)),
          KeyValueLine(
            'Median spacing',
            t.medianSpacingSec == null
                ? 'n/a'
                : spacingWords(t.medianSpacingSec!),
          ),
          KeyValueLine(
            'Samples per hour',
            t.samplesPerHour == null
                ? 'n/a'
                : t.samplesPerHour!.toStringAsFixed(1),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: S.x2),
                    Text(
                      '${o.value}',
                      style: F.tab(F.cap).copyWith(color: p.ink2),
                    ),
                    const SizedBox(width: S.x2),
                    if (inUse.contains(o.key))
                      const StatePill(label: 'In use', color: C.health)
                    else if (demo)
                      const StatePill(label: 'Synthetic', color: C.amber)
                    else
                      const StatePill(label: 'Available', color: C.neutral),
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
