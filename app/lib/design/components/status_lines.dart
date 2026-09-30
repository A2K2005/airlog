// The honesty lines that frame every day screen:
//   FreshnessLine      "Latest data from your tracker 12 min ago · synced 2 min ago"
//   CalibrationBanner  "Learning your usual · night 9 of 14"
//   DemoBadge          a persistent "Sample data" pill
//   PreparingNote      "Preparing 90 days of sample data…" (first launch)

import 'package:flutter/material.dart';

import '../../domain/repositories.dart' show SyncPhase, SyncStatus;
import '../../domain/results.dart' show Calibration;
import '../tokens/tokens.dart';
import 'pressable.dart';
import 'surfaces.dart';

/// Relative time in plain words: "just now", "12 min ago", "3h ago",
/// "2 days ago". Future timestamps read "just now" (clock skew).
String ago(DateTime t, DateTime now) {
  final s = now.difference(t).inSeconds;
  if (s < 60) return 'just now';
  final m = s ~/ 60;
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  if (h < 24) return '${h}h ago';
  final d = h ~/ 24;
  return d == 1 ? '1 day ago' : '$d days ago';
}

class FreshnessLine extends StatelessWidget {
  const FreshnessLine({
    super.key,
    required this.now,
    this.lastDataAt,
    this.lastSyncAt,
    this.syncing = false,
    this.error,
    this.source = 'your tracker',
    this.staleAfterHours = 6,
    this.onTap,
    this.compact = false,
  });

  factory FreshnessLine.fromStatus(
    SyncStatus s, {
    Key? key,
    required DateTime now,
    VoidCallback? onTap,
  }) => FreshnessLine(
    key: key,
    now: now,
    lastDataAt: s.lastDataAt,
    lastSyncAt: s.lastSyncAt,
    syncing: s.phase == SyncPhase.syncing,
    // Never a raw exception (QA-07): the calm line says what to do.
    error: s.phase == SyncPhase.error ? readError : null,
    onTap: onTap,
  );

  /// One subtle line per source app ("Samsung Health · 2 h ago"), from
  /// SyncStatus.lastDataByApp; the plain status line when no app is known.
  static List<Widget> perApp(
    SyncStatus s, {
    required DateTime now,
    VoidCallback? onTap,
  }) {
    if (s.lastDataByApp.isEmpty) {
      return [FreshnessLine.fromStatus(s, now: now, onTap: onTap)];
    }
    final apps = s.lastDataByApp.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final e in apps)
        FreshnessLine(
          key: ValueKey('fresh-${e.key}'),
          now: now,
          lastDataAt: e.value,
          lastSyncAt: s.lastSyncAt,
          syncing: s.phase == SyncPhase.syncing,
          error: s.phase == SyncPhase.error ? readError : null,
          // The watermark calls it sample data; so does the line.
          source: e.key == 'Demo data' ? 'Sample data' : e.key,
          compact: true,
          onTap: onTap,
        ),
    ];
  }

  /// What a failed read says (never the exception text).
  static const readError = 'Couldn’t read your data. Pull down to try again.';

  /// Pass the clock in (never read DateTime.now() here) so goldens and tests
  /// are deterministic.
  final DateTime now;
  final DateTime? lastDataAt;
  final DateTime? lastSyncAt;
  final bool syncing;

  /// Non-null = the last sync failed; shown instead of "synced …".
  final String? error;

  /// What produced the data ("your tracker", "Samsung Health").
  final String source;

  /// "Samsung Health · 2 h ago" instead of the full sentence.
  final bool compact;

  /// Data older than this reads as stale (amber dot).
  final int staleAfterHours;
  final VoidCallback? onTap;

  bool get stale =>
      lastDataAt == null ||
      now.difference(lastDataAt!).inMinutes > staleAfterHours * 60;

  String get text {
    if (compact) {
      final when = lastDataAt == null ? 'no data yet' : ago(lastDataAt!, now);
      final tail = syncing ? ' · syncing…' : (error != null ? ' · $error' : '');
      return '$source · $when$tail';
    }
    final data = lastDataAt == null
        ? 'No data from $source yet'
        : 'Latest data from $source ${ago(lastDataAt!, now)}';
    final sync = syncing
        ? 'syncing…'
        : error != null
        ? error!
        : lastSyncAt == null
        ? 'not synced yet'
        : 'synced ${ago(lastSyncAt!, now)}';
    return '$data · $sync';
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final warn = stale || error != null;
    final dot = syncing
        ? p.mark(C.sky)
        : warn
        ? p.mark(C.amber)
        : p.mark(C.health);
    final line = Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: S.x2),
        Expanded(
          child: Text(
            text,
            style: F.tab(F.cap).copyWith(color: warn ? p.ink2 : p.ink3),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    // Not a live region: a screen that ticks `now` every minute would make a
    // screen reader announce "13 min ago… 14 min ago…".
    final labelled = Semantics(
      label: text,
      child: ExcludeSemantics(child: line),
    );
    if (onTap == null) return labelled;
    // A full 48 dp target (Android's floor); the line itself stays small.
    return Pressable(onTap: onTap, child: labelled);
  }
}

class CalibrationBanner extends StatelessWidget {
  const CalibrationBanner({
    super.key,
    required this.have,
    this.need = 14,
    this.body,
    this.onTap,
  });

  factory CalibrationBanner.of(
    Calibration c, {
    Key? key,
    String? body,
    VoidCallback? onTap,
  }) => CalibrationBanner(
    key: key,
    have: c.haveNights,
    need: c.needNights,
    body: body,
    onTap: onTap,
  );

  /// Show only while the baseline is not established.
  static bool shouldShow(Calibration c) => !c.established;

  final int have;
  final int need;
  final String? body;
  final VoidCallback? onTap;

  String get title =>
      'Learning your usual · night ${have.clamp(0, need)} of $need';

  String get _body =>
      body ??
      (have < 5
          ? 'Scores start to mean something after 5 nights. Wear your '
                'tracker to bed.'
          : 'Scores may shift until Airlog knows your usual.');

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final n = need <= 0 ? 1 : need;
    final filled = have.clamp(0, n);
    final ink = p.mark(C.health);
    return AppCard(
      onTap: onTap,
      semanticLabel: '$title. $_body',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.hourglass_top_rounded,
                  size: 16,
                  color: p.on(C.health),
                ),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(
                    title,
                    style: F.tab(F.head).copyWith(color: p.ink),
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded, size: 20, color: p.ink3),
              ],
            ),
            const SizedBox(height: S.x3),
            SizedBox(
              height: 6,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: i < filled ? ink : p.track,
                          borderRadius: R.rPill,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: S.x3),
            Text(_body, style: F.bodySm.copyWith(color: p.ink2)),
          ],
        ),
      ),
    );
  }
}

/// Persistent pill shown whenever the app is showing synthetic data.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.label = 'Sample data', this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: 5),
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: R.rPill,
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, size: 13, color: p.on(C.amber)),
          const SizedBox(width: S.x1 + 2),
          Text(
            label,
            style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    final labelled = Semantics(
      label: '$label: made-up numbers, not from your tracker',
      child: ExcludeSemantics(child: pill),
    );
    if (onTap == null) return labelled;
    return Pressable(onTap: onTap, child: labelled);
  }
}

/// First launch: the repository is syncing and nothing is stored yet. A calm
/// card that sits where the day's first card will appear, under skeleton
/// rings, so the switch to real data moves nothing above it. Static on
/// purpose (no spinner: an infinite loop cannot honour reduced motion).
class PreparingNote extends StatelessWidget {
  const PreparingNote({
    super.key,
    required this.title,
    this.body = defaultBody,
    this.icon = Icons.hourglass_top_rounded,
  });

  /// [s]'s message when the data layer gave one, else a mode-specific line.
  factory PreparingNote.fromStatus(
    SyncStatus s, {
    Key? key,
    required bool demo,
  }) => PreparingNote(
    key: key,
    title: (s.message?.trim().isNotEmpty ?? false)
        ? s.message!.trim()
        : demo
        ? demoTitle
        : liveTitle,
    icon: demo ? Icons.science_outlined : Icons.hourglass_top_rounded,
  );

  /// True while [s] is syncing and the screen has nothing to show yet.
  static bool shows(SyncStatus? s, {required bool hasData}) =>
      !hasData && s?.phase == SyncPhase.syncing;

  static const demoTitle = 'Preparing 90 days of sample data…';
  static const liveTitle = 'Reading your data from Health Connect…';
  static const defaultBody =
      'This happens once, on first launch, and takes a few seconds. Your '
      'scores appear here as soon as it is done.';

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      tone: CardTone.inset,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: '$title $body',
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 18, color: p.ink2),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: F.head.copyWith(color: p.ink)),
                    const SizedBox(height: S.x1),
                    Text(body, style: F.bodySm.copyWith(color: p.ink2)),
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
