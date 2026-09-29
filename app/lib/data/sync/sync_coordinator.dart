// SyncCoordinator: one sync run for live mode.
//   Health Connect (backfill → token → incremental) → Google Health API
//   (if enabled + signed in) → prune raw HR → recompute from the earliest
//   dirty day onward → sync log.
// Demo mode: seed once per day (DemoSeeder), then only recompute.

import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../common/time.dart';
import '../common/timing.dart';
import '../db/stores.dart';
import '../resolver/resolver.dart';
import '../services/google_health/google_health_source.dart';
import '../services/health_connect/hc_types.dart';
import 'demo_seeder.dart';
import 'ghapi_sync.dart';
import 'hc_sync.dart';
import 'score_pipeline.dart';

class SyncRun {
  SyncRun(this.log, this.recomputedFrom, this.outcome);
  final List<SyncLogEntry> log;
  final String? recomputedFrom;
  final ComputeOutcome? outcome;
  bool get hadErrors => log.any((e) => e.status == 'error');
}

class SyncCoordinator {
  SyncCoordinator({
    required this.raw,
    required this.app,
    required this.pipeline,
    required this.demo,
    required this.clock,
    this.hc,
    this.gh,
  });

  final RawStore raw;
  final AppStore app;
  final ScorePipeline pipeline;
  final DemoSeeder demo;
  final Clock clock;
  final HealthConnectSource? hc;
  final GoogleHealthSource? gh;

  Future<SyncRun> syncLive({
    required Set<SourceKind> enabled,
    required UserProfile profile,
    bool background = false,
  }) async {
    final log = <SyncLogEntry>[];
    final dirty = <String>{};
    final hcSrc = hc;
    if (hcSrc != null && enabled.contains(SourceKind.healthConnect)) {
      dirty.addAll(
        await HcSync(
          hc: hcSrc,
          raw: raw,
          app: app,
          clock: clock,
          contextEnabled: enabled.contains(SourceKind.context),
        ).run(log, background: background),
      );
    }
    final ghSrc = gh;
    if (ghSrc != null && enabled.contains(SourceKind.googleHealthApi)) {
      dirty.addAll(
        await GhSync(gh: ghSrc, raw: raw, app: app, clock: clock).run(log),
      );
    }
    await raw.pruneRawHr(clock().subtract(kRawHrRetention));
    ComputeOutcome? out;
    String? from;
    if (dirty.isNotEmpty) {
      from = dirty.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
      out = await pipeline.recompute(
        DataMode.live,
        fromDate: from,
        cfg: ResolverConfig(
          mode: DataMode.live,
          now: clock(),
          enabled: enabled,
        ),
        profile: profile,
      );
      _engineNote(log, out, SourceKind.healthConnect);
    }
    await app.addLog(log);
    return SyncRun(log, from, out);
  }

  /// Demo "sync": re-seed (and score) if the day changed, else nothing to
  /// read.
  Future<SyncRun> syncDemo({
    required UserProfile profile,
    bool force = false,
  }) async {
    final log = <SyncLogEntry>[];
    final t = Stopwatch()..start();
    final out = await demo.seedAndScore(profile: profile, force: force);
    final changed = out != null;
    if (out != null) {
      Timing.mark('sync_demo', tookMs: t.elapsedMilliseconds);
      log.add(
        SyncLogEntry(
          at: clock(),
          source: SourceKind.demo,
          dataType: 'demo',
          status: 'ok',
          records: out.records.length,
          message: 'Seeded ${demo.days} synthetic days (seed ${demo.seed})',
        ),
      );
      _engineNote(log, out, SourceKind.demo);
      await app.addLog(log);
    }
    return SyncRun(log, changed ? '' : null, out);
  }

  void _engineNote(
    List<SyncLogEntry> log,
    ComputeOutcome out,
    SourceKind source,
  ) {
    if (out.engineError == null) return;
    log.add(
      SyncLogEntry(
        at: clock(),
        source: source,
        dataType: 'engine',
        status: 'error',
        message: 'Scores not computed: ${out.engineError}',
      ),
    );
  }
}
