// Settings → Sources, any app (PRODUCT_PLAN §7, "Any app"): one row per
// metric naming the app it reads ("Heart rate · Samsung Health (auto) ▾"),
// a picker to pin another app or go back to automatic, the confirmation
// that a switch starts a new baseline, the apps found in Health Connect with
// their coverage, and a one-time prompt when a different app has newer data.
//
// Built only on the view-model's SourcesState.apps / choices and
// SourcesController.chooseSource (the Data agent's repository methods).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/design.dart';
import '../../../domain/models.dart';
import '../../../domain/repositories.dart';
import '../sources_view_model.dart';

/// Human names for metrics (the picker rows and prompts).
String metricName(Metric m) => switch (m) {
  Metric.hr => 'Heart rate',
  Metric.hrv => 'HRV',
  Metric.restingHr => 'Resting heart rate',
  Metric.respiratoryRate => 'Respiratory rate',
  Metric.spo2 => 'SpO₂',
  Metric.skinTemp => 'Skin temperature',
  Metric.vo2max => 'VO₂ max',
  Metric.sleep => 'Sleep',
  Metric.workouts => 'Workouts',
  Metric.steps => 'Steps',
  Metric.weight => 'Weight',
  Metric.sleepingHr => 'Sleeping HR (4 h mean)',
};

/// What a switch of app means, said before it happens.
const kSwitchWarning =
    'Switching starts a new baseline. Scores are provisional for about 2 '
    'weeks.';

class SourcePickerSection extends ConsumerStatefulWidget {
  const SourcePickerSection({super.key, required this.state});
  final SourcesState state;

  @override
  ConsumerState<SourcePickerSection> createState() =>
      _SourcePickerSectionState();
}

class _SourcePickerSectionState extends ConsumerState<SourcePickerSection> {
  /// Suggestions already asked about this session (metric + origin).
  static final _asked = <String>{};

  /// The first suggestion not yet answered this session.
  SourceChoice? _suggestion() {
    for (final c in widget.state.choices.values) {
      final o = c.suggestedOrigin;
      if (o != null && !_asked.contains('${c.metric.code}|$o')) return c;
    }
    return null;
  }

  Future<void> _answer(SourceChoice c, {required bool switchApp}) async {
    setState(() => _asked.add('${c.metric.code}|${c.suggestedOrigin}'));
    if (switchApp) {
      await ref
          .read(sourcesControllerProvider.notifier)
          .chooseSource(c.metric, c.suggestedOrigin);
    }
  }

  /// Asked once, inline (a dialog on opening the screen would be a
  /// surprise): `"<App> has newer <metric> data. Switch?"`.
  Widget _suggest(BuildContext context, SourceChoice c) {
    final p = P.of(context);
    final app = c.suggestedDisplayName ?? c.suggestedOrigin!;
    return AppCard(
      tone: CardTone.tinted,
      accent: C.sky,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$app has newer ${metricName(c.metric).toLowerCase()} data. '
            'Switch? Recovery re-learns for up to 14 nights.',
            style: F.bodySm.copyWith(color: p.ink),
          ),
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x4,
            children: [
              AppButton(
                label: 'Switch to $app',
                kind: AppButtonKind.quiet,
                compact: true,
                onTap: () => _answer(c, switchApp: true),
              ),
              AppButton(
                label: 'Not now',
                kind: AppButtonKind.quiet,
                compact: true,
                onTap: () => _answer(c, switchApp: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pick(SourceChoice c) async {
    final apps = [
      for (final a in widget.state.apps)
        if ((a.daysWithData[c.metric] ?? 0) > 0 || a.origin == c.origin) a,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: sheetMotion(context),
      builder: (sheet) {
        final p = P.of(sheet);
        Widget row(String label, String? sub, String value, bool selected) =>
            Pressable(
              onTap: () => Navigator.of(sheet).pop(value),
              selected: selected,
              semanticLabel: sub == null ? label : '$label, $sub',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.gutter,
                  vertical: S.x3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: F.head.copyWith(color: p.ink)),
                          if (sub != null)
                            Text(sub, style: F.cap.copyWith(color: p.ink3)),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_rounded, color: p.ink, size: 20),
                  ],
                ),
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    S.gutter,
                    0,
                    S.gutter,
                    S.x2,
                  ),
                  child: Text(
                    metricName(c.metric),
                    style: F.t2.copyWith(color: p.ink),
                  ),
                ),
                row(
                  'Automatic',
                  'The app with the most recent data',
                  '',
                  c.automatic,
                ),
                for (final a in apps)
                  row(
                    a.displayName,
                    '${a.daysWithData[c.metric] ?? 0} of the last 14 days',
                    a.origin,
                    !c.automatic && a.origin == c.origin,
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    final origin = picked.isEmpty ? null : picked;
    final same = origin == null ? c.automatic : origin == c.origin;
    if (same) return;
    if (origin != null && origin != c.origin) {
      final ok = await showDialog<bool>(
        context: context,
        animationStyle: dialogMotion(context),
        builder: (d) => AlertDialog(
          title: const Text('Switch app?'),
          content: const Text(kSwitchWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await ref
        .read(sourcesControllerProvider.notifier)
        .chooseSource(c.metric, origin);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final s = widget.state;
    final choices = s.choices.values.toList()
      ..sort((a, b) => a.metric.index.compareTo(b.metric.index));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Where each metric comes from',
          subtitle: 'One app per metric, never averaged',
        ),
        const SizedBox(height: S.x3),
        if (_suggestion() case final c?) ...[
          _suggest(context, c),
          const SizedBox(height: S.x3),
        ],
        if (choices.isEmpty)
          AppCard(
            tone: CardTone.inset,
            child: Text(
              'Once Health Connect has data, each metric shows the app it '
              'reads here, and you can pick another.',
              style: F.bodySm.copyWith(color: p.ink2),
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final c in choices)
                  Pressable(
                    onTap: () => _pick(c),
                    semanticLabel:
                        '${metricName(c.metric)}, ${c.displayName}'
                        '${c.automatic ? ', automatic' : ''}. Change.',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: S.card,
                        vertical: S.x3,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: metricName(c.metric),
                                    style: F.bodySm.copyWith(color: p.ink),
                                  ),
                                  TextSpan(
                                    text:
                                        ' · ${c.displayName}'
                                        '${c.automatic ? ' (auto)' : ''}',
                                    style: F.bodySm.copyWith(color: p.ink2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color: p.ink3,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: S.x5),
        const SectionHeader(title: 'Found in Health Connect'),
        const SizedBox(height: S.x3),
        if (s.apps.isEmpty)
          AppCard(
            tone: CardTone.inset,
            child: Text(
              'No apps have written data to Health Connect yet. When your '
              'tracker’s app syncs, it appears here with what it covers.',
              style: F.bodySm.copyWith(color: p.ink2),
            ),
          )
        else
          for (final a in s.apps)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x3),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.device == null
                          ? a.displayName
                          : '${a.displayName} · ${a.device}',
                      style: F.head.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: S.x1),
                    Text(_coverage(a), style: F.cap.copyWith(color: p.ink2)),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  static String _coverage(SourceApp a) {
    final parts = [
      for (final e in a.daysWithData.entries)
        if (e.value > 0) '${metricName(e.key)} ${e.value}/14',
    ];
    return parts.isEmpty
        ? 'No recent data'
        : 'Last 14 days: ${parts.join(' · ')}';
  }
}
