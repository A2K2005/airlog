// Settings → Sync log: every sync, per data type, newest first. One failing
// type never hides the others (ARCHITECTURE §4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/design.dart';
import '../../domain/repositories.dart';
import '../../app/platform_services.dart';
import '../../app/copy.dart' show hcTypeName;

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

/// Status → (pigment, word). Errors are red here: a failed read is a fault to
/// fix, not a body signal.
(Color, String) syncStatusStyle(String status) => switch (status) {
  'ok' => (C.health, 'OK'),
  'empty' => (C.neutral, 'Nothing new'),
  'error' => (C.recRed, 'Failed'),
  'denied' => (C.amber, 'No permission'),
  'skipped' => (C.neutral, 'Skipped'),
  _ => (C.neutral, status),
};

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
      body = [
        if (v.status.lastSyncAt != null) ...[
          FreshnessLine.fromStatus(v.status, now: now),
          const SizedBox(height: S.x4),
        ],
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: S.x1),
          child: Column(
            children: [
              for (var i = 0; i < v.entries.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: S.hair, color: p.line),
                _Entry(entry: v.entries[i], now: now),
              ],
            ],
          ),
        ),
      ];
    } else if (v != null) {
      body = [
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Nothing synced yet',
          body: v.mode == DataMode.demo
              ? 'Demo data is generated on this phone, so there is nothing to '
                    'sync. Connect Health Connect to see every read here.'
              : 'Each sync lists every data type it read, with a count, so a '
                    'missing type is easy to spot.',
        ),
      ];
    } else if (async.hasError) {
      body = const [
        StatusCard(
          title: 'Sync log could not load',
          body: 'The data store did not answer. Go back and try again.',
          tone: StatusTone.warning,
        ),
      ];
    } else {
      body = const [AppCard(child: SkeletonLines(lines: 6))];
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync log'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: body,
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry, required this.now});
  final SyncLogEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final e = entry;
    final (pig, word) = syncStatusStyle(e.status);
    final count = e.status == 'ok' || e.records > 0
        ? '${e.records} record${e.records == 1 ? '' : 's'}'
        : null;
    return Semantics(
      container: true,
      label:
          '${hcTypeName(e.dataType)} from ${e.source.label}: $word'
          '${count == null ? '' : ', $count'}, ${ago(e.at, now)}'
          '${e.message == null ? '' : '. ${e.message}'}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: S.card,
            vertical: S.x3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: p.mark(pig),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        Text(
                          ago(e.at, now),
                          style: F.tab(F.cap).copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [word, ?count, e.source.label].join(' · '),
                      style: F
                          .tab(F.cap)
                          .copyWith(
                            color: e.status == 'error' || e.status == 'denied'
                                ? p.on(pig)
                                : p.ink2,
                          ),
                    ),
                    if (e.message != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        e.message!,
                        style: F.cap.copyWith(color: p.ink3),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
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

/// Exposed for tests / other screens: a log line's time in words.
String syncWhen(SyncLogEntry e, DateTime now) =>
    '${dayTime(e.at)} (${ago(e.at, now)})';
