// Settings → Sync log: how the latest syncs went at a glance (counts in dot
// matrix), what needs a fix (with the way to fix it), then every sync, per
// data type, newest first. One failing type never hides the others
// (ARCHITECTURE §4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/copy.dart' show hcTypeName;
import '../../app/platform_services.dart';
import '../../app/providers.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/repositories.dart';

class SyncLogView {
  const SyncLogView({
    required this.entries,
    required this.mode,
    required this.status,
  });
  final List<SyncLogEntry> entries;
  final DataMode mode;
  final SyncStatus status;
}

final syncLogViewProvider = FutureProvider.autoDispose<SyncLogView>((
  ref,
) async {
  ref.watch(revisionProvider.select((r) => r.value));
  final repo = ref.watch(healthRepositoryProvider);
  final entries = await repo.syncLog();
  return SyncLogView(
    entries: [...entries]..sort((a, b) => b.at.compareTo(a.at)),
    mode: repo.mode,
    status: repo.syncStatus,
  );
}, retry: noRetry);

/// Status → (tone, word). A failed read is a fault to fix, not a body
/// signal, so "Failed" is the one red word.
(Color, String) syncStatusStyle(String status) => switch (status) {
  'ok' => (C.health, 'Updated'),
  'empty' => (C.neutral, 'Nothing new'),
  'error' => (C.recRed, 'Failed'),
  'denied' => (C.amber, 'Not allowed'),
  'skipped' => (C.neutral, 'Skipped'),
  _ => (C.neutral, status),
};

/// The newest entry per (data type, source): the state each one is in now.
List<SyncLogEntry> latestPerType(List<SyncLogEntry> newestFirst) {
  final seen = <String>{};
  return [
    for (final e in newestFirst)
      if (seen.add('${e.dataType}|${e.source.code}')) e,
  ];
}

class SyncLogScreen extends ConsumerWidget {
  const SyncLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(syncLogViewProvider);
    final now = ref.watch(currentTimeProvider);
    final v = async.value;
    final p = P.of(context);
    final List<Widget> body;
    if (v != null && v.entries.isNotEmpty) {
      final latest = latestPerType(v.entries);
      final updated = latest.where((e) => e.status == 'ok').length;
      final nothing = latest.where((e) => e.status == 'empty').length;
      final fix = [
        for (final e in latest)
          if (e.status == 'denied' || e.status == 'error') e,
      ];
      body = [
        _Counts([
          ('$updated', 'Updated', C.health),
          ('$nothing', 'Nothing new', C.neutral),
          ('${fix.length}', 'Didn’t sync', C.recRed),
        ]),
        if (v.status.lastSyncAt != null) ...[
          const SizedBox(height: S.x3),
          FreshnessLine.fromStatus(v.status, now: now),
        ],
        if (fix.isNotEmpty) ...[
          const SizedBox(height: S.x5),
          const OverLabel('Needs a fix'),
          const SizedBox(height: S.x3),
          SettingsTile(
            children: [
              for (final e in fix)
                _Entry(
                  entry: e,
                  now: now,
                  showMessage: true,
                  onFix: () =>
                      Navigator.of(context).pushNamed(Routes.sources),
                ),
            ],
          ),
        ],
        const SizedBox(height: S.x5),
        const OverLabel('All syncs'),
        const SizedBox(height: S.x3),
        SettingsTile(
          children: [
            for (final e in v.entries) _Entry(entry: e, now: now),
          ],
        ),
      ];
    } else if (v != null) {
      body = const [
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Nothing synced yet',
          body:
              'Each sync lists every kind of data it read, with a count, '
              'so anything missing is easy to spot.',
        ),
      ];
    } else if (async.hasError) {
      body = const [
        StatusCard(
          title: 'Couldn’t load the sync log',
          body: 'Go back and try again.',
          tone: StatusTone.warning,
        ),
      ];
    } else {
      body = const [AppCard(child: SkeletonLines(lines: 6))];
    }
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(title: const Text('Sync log')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: body,
      ),
    );
  }
}

/// Three count tiles (dot matrix), stacked at large text.
class _Counts extends StatelessWidget {
  const _Counts(this.items);
  final List<(String, String, Color)> items;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    Widget tile((String, String, Color) it) => AppCard(
      padding: const EdgeInsets.all(S.x4),
      child: DotStat(
        value: it.$1,
        caption: it.$2,
        color: it.$1 == '0' ? p.ink3 : p.on(it.$3),
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

class _Entry extends StatelessWidget {
  const _Entry({
    required this.entry,
    required this.now,
    this.showMessage = false,
    this.onFix,
  });
  final SyncLogEntry entry;
  final DateTime now;
  final bool showMessage;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final e = entry;
    final (pig, word) = syncStatusStyle(e.status);
    final count = e.status == 'ok' || e.records > 0
        ? '${e.records} record${e.records == 1 ? '' : 's'}'
        : null;
    final source = sourceName(e.source);
    final message = showMessage ? e.message : null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.card, vertical: S.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hcTypeName(e.dataType),
                  style: F.bodySm.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: S.x2),
              Text(
                ago(e.at, now),
                style: F.tab(F.cap).copyWith(color: p.ink3),
              ),
            ],
          ),
          const SizedBox(height: S.x1 + 2),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatePill(label: word, color: pig),
              Text(
                [?count, source].join(' · '),
                style: F.tab(F.cap).copyWith(color: p.ink2),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: S.x1),
            Text(message, style: F.cap.copyWith(color: p.ink3)),
          ],
          if (onFix != null) ...[
            const SizedBox(height: S.x2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: 'Fix in Data sources',
                icon: Icons.chevron_right_rounded,
                kind: AppButtonKind.secondary,
                compact: true,
                onTap: onFix,
              ),
            ),
          ],
        ],
      ),
    );
    final label =
        '${hcTypeName(e.dataType)} from $source: $word'
        '${count == null ? '' : ', $count'}, ${ago(e.at, now)}'
        '${message == null ? '' : '. $message'}';
    if (onFix != null) {
      // The fix button stays its own control.
      return Semantics(container: true, label: label, child: row);
    }
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(child: row),
    );
  }
}

/// Exposed for tests / other screens: a log line's time in words.
String syncWhen(SyncLogEntry e, DateTime now) =>
    '${dayTime(e.at)} (${ago(e.at, now)})';
