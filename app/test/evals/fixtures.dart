// Health fixtures for the evals: the 90-day demo, copied and edited (a
// hostile workout title, Google Health API provenance, a WHOOP-style band
// with no HRV), then re-scored by the real engine and served by the real
// HealthRepositoryImpl over in-memory stores.

import 'package:airlog/data/db/memory_stores.dart';
import 'package:airlog/data/repositories/health_repository_impl.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/data/sync/demo_seeder.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';

import 'coach_harness.dart';

/// The demo days (copies), edited by [edit], re-scored and served.
Future<HealthRepositoryImpl> fixtureRepo(
  void Function(List<DayRecord> days) edit, {
  DataMode mode = DataMode.demo,
}) async {
  final base = InMemoryHealthRepository.demo(now: kEvalNow);
  final today = DayKey.of(kEvalNow);
  final bundles = await base.range(DayKey.add(today, -89), today);
  final records = [
    for (final b in bundles) DayRecord.fromJson(b.record.toJson()),
  ];
  edit(records);
  final results = Engine.computeRange(records, now: kEvalNow);
  final raw = MemoryRawStore();
  final app = MemoryAppStore();
  app
    ..setSettingSync(kModeKey, mode.name)
    ..setSettingSync(kDemoSeededForKey, today)
    ..setSettingSync(kDemoVersionKey, DemoSeeder.stampFor(42, 90))
    ..putDaysSync(mode, records, results);
  for (var i = 0; i < 90; i++) {
    final j = await base.journal(DayKey.add(today, -i));
    if (j.factors.isNotEmpty) app.putJournalSync(mode, j);
  }
  return HealthRepositoryImpl(
    raw: raw,
    app: app,
    clock: () => kEvalNow,
    initialMode: mode,
  );
}

/// Marks [metrics] of the last [days] days as coming from the Google
/// Health API.
void fromGoogleHealth(List<DayRecord> rs, Set<Metric> metrics, {int days = 90}) {
  for (final r in rs.skip(rs.length - days)) {
    for (final m in metrics) {
      final p = r.provenance[m];
      if (p != null) {
        r.provenance[m] = Provenance(
          SourceKind.googleHealthApi,
          p.definition,
          device: p.device,
        );
      }
    }
  }
}

/// Renames the newest workout (before today) to [title].
String renameLatestWorkout(List<DayRecord> rs, String title) {
  for (final r in rs.reversed) {
    if (r.workouts.isEmpty) continue;
    final w = r.workouts.last;
    r.workouts[r.workouts.length - 1] = Workout(
      id: w.id,
      name: title,
      start: w.start,
      end: w.end,
      averageHr: w.averageHr,
      calories: w.calories,
      distanceM: w.distanceM,
    );
    return r.date;
  }
  throw StateError('no workout in the demo');
}

/// A WHOOP-style band: no HRV at all in the last [days] days.
void dropHrv(List<DayRecord> rs, {int days = 3}) {
  for (final r in rs.skip(rs.length - days)) {
    r.hrvRmssd = null;
    r.hrvSamples.clear();
    r.provenance.remove(Metric.hrv);
  }
}
