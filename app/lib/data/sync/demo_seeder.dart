// Demo mode: seed the synthetic Fitbit Air once per calendar day (so the
// 90 days always end today), computing its scores in the same step
// (demo_seed.dart; in a worker isolate in the app); otherwise demo sync is
// a no-op.
// Demo rows live alongside live rows (source 'demo', mode 'demo' day rows),
// so switching modes never mixes or loses either side.

import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../common/time.dart';
import '../db/stores.dart';
import '../common/timing.dart';
import '../services/demo/demo_generator.dart';
import 'demo_seed.dart';
import 'score_pipeline.dart';

const String kDemoSeededForKey = 'demo.seeded_for';
const String kDemoVersionKey = 'demo.version';

/// When the demo was last generated (epoch ms). A seed made in the small
/// hours holds only part of last night; it is refreshed (at most hourly)
/// until the latest possible demo wake-up has passed (QA-02).
const String kDemoSeededAtKey = 'demo.seeded_at';

/// The demo night ends by 10:30 at the latest (demo_generator.dart).
const Duration kDemoLatestWake = Duration(hours: 10, minutes: 30);
const Duration kDemoMorningRefresh = Duration(hours: 1);

class DemoSeeder {
  DemoSeeder({
    required this.raw,
    required this.app,
    required this.clock,
    this.seed = 42,
    this.days = 90,
    this.writer,
    this.runner = runDemoSeedInline,
  });

  final RawStore raw;
  final AppStore app;
  final Clock clock;
  final int seed;
  final int days;

  /// sqlite bulk writer (the app). Null: write through the store
  /// interfaces (in-memory stores, tests).
  final DemoSeedWriter? writer;

  /// Where [buildDemoSeed] runs (inline by default; the app uses an isolate).
  final DemoSeedRunner runner;

  static String stampFor(int seed, int days) =>
      '$kDemoGeneratorVersion:$seed:$days';

  String get _stamp => stampFor(seed, days);

  Future<bool> isFresh() async {
    final now = clock();
    if (await app.getSetting(kDemoSeededForKey) != DayKey.of(now) ||
        await app.getSetting(kDemoVersionKey) != _stamp) {
      return false;
    }
    final at = int.tryParse(await app.getSetting(kDemoSeededAtKey) ?? '');
    if (at == null) return true; // older seeds: once per day, as before
    final seededAt = fromMs(at);
    final nightDone = DayKey.start(DayKey.of(now)).add(kDemoLatestWake);
    return !seededAt.isBefore(nightDone) ||
        now.difference(seededAt) < kDemoMorningRefresh;
  }

  /// Re-generates the demo rows, journal AND their scores if needed (once
  /// per calendar day, or when the generator changed). Returns the computed
  /// days, or null when the stored demo data was already fresh.
  Future<ComputeOutcome?> seedAndScore({
    required UserProfile profile,
    bool force = false,
  }) async {
    if (!force && await isFresh()) return null;
    final now = clock();
    final w = writer;
    final res = await runner(
      DemoSeedRequest(
        seed: seed,
        days: days,
        now: now,
        profile: profile,
        forSqlite: w != null,
      ),
    );
    final t = Stopwatch()..start();
    if (w != null) {
      await w(res.ops);
    } else {
      final ds = res.dataset!;
      await raw.wipe(sources: const {SourceKind.demo});
      await raw.upsert(ds.rows);
      await app.clearJournal(DataMode.demo);
      for (final j in ds.journal) {
        await app.putJournal(DataMode.demo, j);
      }
      await app.putDays(
        DataMode.demo,
        res.outcome.records,
        res.outcome.results,
        clearFrom: '0000-00-00',
      );
    }
    // Stamp last: a seed that failed half-way is redone on the next start.
    await app.setSetting(kDemoSeededForKey, DayKey.of(now));
    await app.setSetting(kDemoVersionKey, _stamp);
    await app.setSetting(kDemoSeededAtKey, '${now.millisecondsSinceEpoch}');
    Timing.phases('demo_seed', {
      ...res.timingsMs,
      'write': t.elapsedMilliseconds,
    });
    return res.outcome;
  }
}
