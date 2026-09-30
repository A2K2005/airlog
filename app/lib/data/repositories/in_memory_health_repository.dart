// InMemoryHealthRepository: the real HealthRepositoryImpl over in-memory
// stores, pre-seeded SYNCHRONOUSLY with the demo generator → resolver →
// engine. No sqflite, no plugins, no timers — for widget and golden tests:
//
//   final repo = InMemoryHealthRepository.demo(now: DateTime(2026, 9, 28, 9));
//   ProviderScope(overrides: [
//     healthRepositoryProvider.overrideWithValue(repo),
//     liveHrServiceProvider.overrideWithValue(repo.liveHr),
//   ], child: ...)
//
// Pass a fixed [now] for deterministic goldens (all timestamps derive from
// it). If the engine is not implemented yet, records exist but day()/range()
// return nothing and [engineError] says why.

import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../common/time.dart';
import '../db/memory_stores.dart';
import '../resolver/resolver.dart';
import '../services/demo/demo_generator.dart';
import '../services/demo/demo_live_hr_service.dart';
import '../services/widget/widget_sink.dart';
import '../sync/demo_seeder.dart';
import '../sync/score_pipeline.dart';
import 'health_repository_impl.dart';

class InMemoryHealthRepository extends HealthRepositoryImpl {
  InMemoryHealthRepository._({
    required MemoryRawStore super.raw,
    required MemoryAppStore super.app,
    required super.clock,
    required super.demoSeed,
    required super.demoDays,
    super.widgets,
  }) : super(initialMode: DataMode.demo);

  /// Why scores are missing (null when the engine ran fine).
  Object? engineError;

  late final DemoLiveHrService liveHr = DemoLiveHrService(
    saver: saveLiveSession,
  );

  static final Map<String, DemoDataset> _cache = {};

  // Computed days are cached too and SHARED between instances built with the
  // same (seed, days, now): treat returned DayRecords as read-only.
  static final Map<String, ComputeOutcome> _computed = {};

  factory InMemoryHealthRepository.demo({
    int seed = 42,
    int days = 90,
    DateTime? now,
    WidgetSink widgets = const NoopWidgetSink(),
  }) {
    final Clock clock = now == null ? systemClock : () => now;
    final t = clock();
    final raw = MemoryRawStore();
    final app = MemoryAppStore();
    final key = '$seed/$days/${t.millisecondsSinceEpoch}';
    if (_cache.length > 4) _cache.clear();
    if (_computed.length > 4) _computed.clear();
    final ds = _cache[key] ??= DemoGenerator(
      seed: seed,
      days: days,
      now: t,
    ).generate();
    raw.upsertSync(ds.rows);
    for (final j in ds.journal) {
      app.putJournalSync(DataMode.demo, j);
    }
    app
      ..setSettingSync(kModeKey, DataMode.demo.name)
      ..setSettingSync(kDemoSeededForKey, DayKey.of(t))
      ..setSettingSync(kDemoSeededAtKey, '${t.millisecondsSinceEpoch}')
      ..setSettingSync(kDemoVersionKey, DemoSeeder.stampFor(seed, days));
    final today = DayKey.of(t);
    final first = DayKey.add(today, -(days - 1));
    final cfg = ResolverConfig(mode: DataMode.demo, now: t);
    final out = _computed[key] ??= computeDays(
      raw.loadSync(
        DayKey.start(first).subtract(const Duration(days: 1)),
        DayKey.end(today),
        sources: const {SourceKind.demo},
      ),
      computeFrom: first,
      keepFrom: first,
      to: today,
      cfg: cfg,
      profile: const UserProfile(),
    );
    app.putDaysSync(DataMode.demo, out.records, out.results);
    return InMemoryHealthRepository._(
      raw: raw,
      app: app,
      clock: clock,
      demoSeed: seed,
      demoDays: days,
      widgets: widgets,
    )..engineError = out.engineError;
  }
}
