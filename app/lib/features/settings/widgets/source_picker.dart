// Settings → Data sources, any app (PRODUCT_PLAN §7, "Any app"):
//   * one tile per app found in Health Connect: what Airlog uses it for and
//     what else it shares, from the last 14 days of data;
//   * one row per measurement naming the app it reads, with a picker to pin
//     another app or go back to automatic, the confirmation that a switch
//     means learning your usual again, and a one-time prompt when a
//     different app has newer data.
//
// Built only on the view-model's SourcesState.apps / choices and
// SourcesController.chooseSource.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/screen_kit.dart' show IconBadge, InfoButton;
import '../../../design/design.dart';
import '../../../domain/models.dart';
import '../../../domain/repositories.dart';
import '../sources_view_model.dart';

/// Human names for measurements (the rows, chips and prompts).
String metricName(Metric m) => switch (m) {
  Metric.hr => 'Heart rate',
  Metric.hrv => 'HRV',
  Metric.restingHr => 'Resting heart rate',
  Metric.respiratoryRate => 'Breathing rate',
  Metric.spo2 => 'Blood oxygen',
  Metric.skinTemp => 'Skin temperature',
  Metric.vo2max => 'VO₂ max',
  Metric.sleep => 'Sleep',
  Metric.workouts => 'Workouts',
  Metric.steps => 'Steps',
  Metric.weight => 'Weight',
  Metric.sleepingHr => 'Sleeping heart rate',
};

IconData metricIcon(Metric m) => switch (m) {
  Metric.hr => Icons.favorite_border_rounded,
  Metric.hrv => Icons.monitor_heart_outlined,
  Metric.restingHr => Icons.airline_seat_flat_outlined,
  Metric.respiratoryRate => Icons.air_rounded,
  Metric.spo2 => Icons.water_drop_outlined,
  Metric.skinTemp => Icons.thermostat_rounded,
  Metric.vo2max => Icons.speed_rounded,
  Metric.sleep => Icons.bedtime_outlined,
  Metric.workouts => Icons.fitness_center_rounded,
  Metric.steps => Icons.directions_walk_rounded,
  Metric.weight => Icons.monitor_weight_outlined,
  Metric.sleepingHr => Icons.nights_stay_outlined,
};

/// What a switch of app means, said before it happens.
const kSwitchWarning =
    'If you switch, Airlog learns your usual again. Scores may shift for '
    'about 2 weeks.';

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
  /// surprise): "{App} has newer {measurement} data. Switch to it?".
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
            '$app has newer ${metricName(c.metric)} data. Switch to it?',
            style: F.bodySm.copyWith(color: p.ink, fontWeight: FontWeight.w600),
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
    final now = ref.watch(currentTimeProvider);
    final choices = s.choices.values.toList()
      ..sort((a, b) => a.metric.index.compareTo(b.metric.index));
    Widget label(String text, Widget info) => Row(
      children: [
        Expanded(child: OverLabel(text)),
        info,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(
          'Apps sharing with Health Connect',
          const InfoButton(
            title: 'Apps sharing with Health Connect',
            lede:
                'Each app your tracker uses shares its own data. Airlog uses '
                'one app for each measurement, never a mix.',
            children: [
              ExplainSection(
                title: 'What 12/14 means',
                body:
                    'The app shared that measurement on 12 of the last 14 '
                    'days.',
              ),
              ExplainSection(
                title: 'Used for',
                body:
                    'Airlog reads these from this app. You can change that '
                    'below.',
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x2),
        if (s.apps.isEmpty)
          AppCard(
            tone: CardTone.inset,
            child: Text(
              'No apps have shared data with Health Connect yet. When your '
              'tracker’s app syncs, it shows up here.',
              style: F.bodySm.copyWith(color: p.ink2),
            ),
          )
        else
          for (var i = 0; i < s.apps.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x3),
            _AppTile(app: s.apps[i], choices: s.choices, now: now),
          ],
        const SizedBox(height: S.x6),
        label(
          'Where each measurement comes from',
          const InfoButton(
            title: 'Where each measurement comes from',
            lede: kSwitchWarning,
            children: [
              ExplainSection(
                title: 'Automatic',
                body:
                    'Airlog picks the app with the most recent data, unless '
                    'you choose one.',
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x2),
        if (_suggestion() case final c?) ...[
          _suggest(context, c),
          const SizedBox(height: S.x3),
        ],
        if (choices.isEmpty)
          AppCard(
            tone: CardTone.inset,
            child: Text(
              'Once Health Connect has data, you’ll see which app each '
              'measurement comes from here.',
              style: F.bodySm.copyWith(color: p.ink2),
            ),
          )
        else
          SettingsTile(
            children: [
              for (final c in choices)
                SettingsRow(
                  icon: metricIcon(c.metric),
                  title: metricName(c.metric),
                  subtitle:
                      '${c.displayName}${c.automatic ? ' · Auto' : ''}',
                  trailing: Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: p.ink3,
                  ),
                  semanticLabel:
                      '${metricName(c.metric)}, ${c.displayName}'
                      '${c.automatic ? ', automatic' : ''}. Change.',
                  onTap: () => _pick(c),
                ),
            ],
          ),
      ],
    );
  }
}

/// One app found in Health Connect: what Airlog uses it for, and what else
/// it shared in the last 14 days.
class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.choices,
    required this.now,
  });
  final SourceApp app;
  final Map<Metric, SourceChoice> choices;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final a = app;
    final used = <Metric>[];
    final also = <Metric>[];
    for (final m in Metric.values) {
      final days = a.daysWithData[m] ?? 0;
      if (choices[m]?.origin == a.origin) {
        used.add(m);
      } else if (days > 0) {
        also.add(m);
      }
    }
    String count(Metric m) => '${a.daysWithData[m] ?? 0}/14';
    Widget group(String title, List<Metric> ms, MetricChipStyle style) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: S.x3),
            OverLabel(title),
            const SizedBox(height: S.x2),
            Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              children: [
                for (final m in ms)
                  MetricChip(
                    label: metricName(m),
                    count: count(m),
                    style: style,
                  ),
              ],
            ),
          ],
        );
    final name = a.device == null
        ? a.displayName
        : '${a.displayName} · ${a.device}';
    return AppCard(
      semanticLabel: [
        name,
        if (a.lastDataAt != null) 'last data ${ago(a.lastDataAt!, now)}',
        if (used.isNotEmpty) 'used for ${used.map(metricName).join(', ')}',
        if (also.isNotEmpty) 'also has ${also.map(metricName).join(', ')}',
      ].join('. '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(icon: Icons.apps_rounded, size: 32),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(name, style: F.head.copyWith(color: p.ink)),
                ),
                if (a.lastDataAt != null) ...[
                  const SizedBox(width: S.x2),
                  Text(
                    ago(a.lastDataAt!, now),
                    style: F.tab(F.cap).copyWith(color: p.ink3),
                  ),
                ],
              ],
            ),
            if (used.isNotEmpty)
              group('Used for', used, MetricChipStyle.used),
            if (also.isNotEmpty)
              group(
                used.isEmpty ? 'Shares' : 'Also has',
                also,
                MetricChipStyle.available,
              ),
            if (used.isEmpty && also.isEmpty) ...[
              const SizedBox(height: S.x2),
              Text('No recent data', style: F.cap.copyWith(color: p.ink3)),
            ],
          ],
        ),
      ),
    );
  }
}
