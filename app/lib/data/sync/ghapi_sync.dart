// Google Health API sync (Enhanced mode). Each data type is fetched in its
// (Per-type isolation + sync-log pattern ported from Pulse
// `Core/Sync/SyncEngine.swift`, Luraxx/pulse @ 1f8975c, Apache-2.0, see
// third_party/pulse/NOTICE.)
// own try/catch (one failure never blocks the rest) and replaces its stored
// window. HR is only fetched as a FALLBACK for days where Health Connect has
// no heart rate (it costs up to ~9 pages per day at 1 s resolution).

import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../common/source_exception.dart';
import '../common/time.dart';
import '../db/raw_rows.dart';
import '../db/stores.dart';
import '../services/google_health/google_health_source.dart';
import 'score_pipeline.dart';

const String kGhLastSyncKey = 'ghapi.last_sync_ms';

class GhSync {
  GhSync({
    required this.gh,
    required this.raw,
    required this.app,
    required this.clock,
    this.firstDays = 30,
    this.hrFallbackDays = 7,
  });

  final GoogleHealthSource gh;
  final RawStore raw;
  final AppStore app;
  final Clock clock;
  final int firstDays;
  final int hrFallbackDays;

  Future<Set<String>> run(List<SyncLogEntry> log) async {
    final dirty = <String>{};
    void note(String type, String status, {int records = 0, String? message}) =>
        log.add(
          SyncLogEntry(
            at: clock(),
            source: SourceKind.googleHealthApi,
            dataType: type,
            status: status,
            records: records,
            message: message,
          ),
        );

    if (!gh.configured) {
      note('google_health', 'skipped', message: 'Not set up');
      return dirty;
    }
    if (!await gh.signedIn.timeout(const Duration(seconds: 20))) {
      note('google_health', 'denied', message: 'Not signed in');
      return dirty;
    }
    final now = clock();
    final lastMs = int.tryParse(await app.getSetting(kGhLastSyncKey) ?? '');
    var days = firstDays;
    if (lastMs != null) {
      days = now.difference(fromMs(lastMs)).inDays + 3;
      if (days > firstDays) days = firstDays;
    }
    final from = DayKey.start(DayKey.add(DayKey.of(now), -(days - 1)));
    var failures = 0;

    Future<void> step(
      String type,
      Future<GhFetch> Function() fetch,
      List<(RawKind, ScalarKind?)> kinds,
    ) async {
      try {
        final f = await fetch();
        if (f.rawCount > 0 && f.rows.length == 0) {
          throw StateError(
            '${f.rawCount} points received but no value decoded; stored data retained',
          );
        }
        for (final (k, s) in kinds) {
          final part = RawRows(
            hr: k == RawKind.hr ? f.rows.hr : null,
            hrv: k == RawKind.hrv ? f.rows.hrv : null,
            sleep: k == RawKind.sleep ? f.rows.sleep : null,
            scalars: k == RawKind.scalar
                ? [
                    for (final r in f.rows.scalars)
                      if (r.scalar == s) r,
                  ]
                : null,
          );
          dirty.addAll(
            await raw.replaceWindow(
              SourceKind.googleHealthApi,
              k,
              from.subtract(const Duration(hours: 12)),
              now,
              part,
              scalar: s,
            ),
          );
        }
        final n = f.rows.length;
        note(
          type,
          n > 0 ? 'ok' : (f.rawCount > 0 ? 'error' : 'empty'),
          records: n,
          // A mapping gap (see ghapi_mapping.dart), said without the file.
          message: n == 0 && f.rawCount > 0
              ? '${f.rawCount} readings came in, but Airlog couldn’t read them.'
              : null,
        );
      } catch (e) {
        failures++;
        note(
          type,
          e is SourceException ? e.status : 'error',
          message: e is SourceException ? '${e.cause}' : '$e',
        );
      }
    }

    final a = from.subtract(const Duration(hours: 12));
    await step('sleep', () => gh.sleep(a, now), [(RawKind.sleep, null)]);
    await step('daily-heart-rate-variability', () => gh.hrvDaily(from, now), [
      (RawKind.scalar, ScalarKind.hrvDaily),
      (RawKind.scalar, ScalarKind.hrvDeepSleep),
    ]);
    await step('heart-rate-variability', () => gh.hrvSamples(a, now), [
      (RawKind.hrv, null),
    ]);
    await step('oxygen-saturation', () => gh.spo2(a, now), [
      (RawKind.scalar, ScalarKind.spo2Avg),
      (RawKind.scalar, ScalarKind.spo2Min),
    ]);
    await step('daily-respiratory-rate', () => gh.respiratoryRate(from, now), [
      (RawKind.scalar, ScalarKind.resp),
    ]);
    await step(
      'daily-sleep-temperature-derivations',
      () => gh.skinTemp(from, now),
      [(RawKind.scalar, ScalarKind.skinTempDelta)],
    );
    await step('daily-resting-heart-rate', () => gh.restingHr(from, now), [
      (RawKind.scalar, ScalarKind.rhr),
    ]);
    await step('daily-vo2-max', () => gh.vo2max(from, now), [
      (RawKind.scalar, ScalarKind.vo2max),
    ]);

    // HR fallback: only days without Health Connect HR.
    final hrFrom = DayKey.start(
      DayKey.add(DayKey.of(now), -(hrFallbackDays - 1)),
    );
    final have = await raw.load(
      hrFrom,
      now,
      sources: const {SourceKind.healthConnect},
    );
    final hrPlan = (await ScorePipeline(
      raw: raw,
      app: app,
    ).loadPlans())[Metric.hr];
    final covered = {
      for (final d in have.hrDays)
        if (d.minutesWithData > 60 &&
            (hrPlan == null || d.origin == hrPlan.originOn(d.date)))
          d.date,
    };
    var fetched = 0;
    for (
      var d = DayKey.of(hrFrom);
      d.compareTo(DayKey.of(now)) <= 0;
      d = DayKey.add(d, 1)
    ) {
      if (covered.contains(d)) continue;
      try {
        final end = DayKey.end(d).isAfter(now) ? now : DayKey.end(d);
        final f = await gh.heartRate(DayKey.start(d), end);
        if (f.rawCount > 0 && f.rows.hr.isEmpty) {
          throw StateError(
            'Couldn’t read heart rate from Enhanced mode. Your saved data is '
            'safe.',
          );
        }
        dirty.addAll(
          await raw.replaceWindow(
            SourceKind.googleHealthApi,
            RawKind.hr,
            DayKey.start(d),
            end,
            f.rows,
          ),
        );
        fetched += f.rows.hr.length;
      } catch (e) {
        failures++;
        // Plain words, never the exception text.
        note(
          'heart-rate',
          'error',
          message:
              '$d: couldn’t read heart rate from Enhanced mode. Your saved '
              'data is safe.',
        );
        break;
      }
    }
    note(
      'heart-rate',
      fetched > 0 ? 'ok' : 'empty',
      records: fetched,
      message: covered.isEmpty
          ? null
          : 'Health Connect had ${covered.length} '
                '${covered.length == 1 ? 'day' : 'days'}; Enhanced mode '
                'filled the rest',
    );

    if (failures == 0) {
      await app.setSetting(kGhLastSyncKey, '${now.millisecondsSinceEpoch}');
    }
    return dirty;
  }
}
