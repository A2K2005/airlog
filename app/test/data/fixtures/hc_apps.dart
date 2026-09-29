// Health Connect fixtures shaped like what each app writes (any app,
// 2026-09-29; research/09 + 09b for the per-app shapes):
//   * Google Health (Fitbit): HR, sleep + stages, HRV series in sleep, RHR,
//     respiratory rate, skin temperature, steps.
//   * Samsung Health: HR samples, sleep + stages, steps. NO HRV, resting
//     HR, respiratory rate or skin temperature (Samsung developer blog,
//     2025-02-18).
//   * WHOOP: HR, sleep, resting HR, respiratory rate. NO HRV.
//   * Oura: HR, sleep + stages, HRV series, resting HR, respiratory rate,
//     skin temperature.
// Values differ per app on purpose, so a mix would be visible.

import 'package:airlog/data/db/memory_stores.dart';
import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/services/health_connect/hc_mapper.dart';
import 'package:airlog/data/services/health_connect/hc_types.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/source_apps.dart';

import '../fakes.dart';

enum AppShape { fitbit, samsung, whoop, oura }

String originOf(AppShape a) => switch (a) {
  AppShape.fitbit => SourceApps.fitbit,
  AppShape.samsung => SourceApps.samsungHealth,
  AppShape.whoop => SourceApps.whoop,
  AppShape.oura => SourceApps.oura,
};

/// Per-app values, so a mix is detectable.
({double hr, double hrv, double rhr, double resp, double steps}) valuesOf(
  AppShape a,
) => switch (a) {
  AppShape.fitbit => (hr: 70, hrv: 45, rhr: 55, resp: 14.5, steps: 8000),
  AppShape.samsung => (hr: 80, hrv: 0, rhr: 0, resp: 0, steps: 11000),
  AppShape.whoop => (hr: 75, hrv: 0, rhr: 58, resp: 15.5, steps: 0),
  AppShape.oura => (hr: 65, hrv: 60, rhr: 50, resp: 13.5, steps: 6000),
};

/// One night + day of [app]'s records, waking on [wakeDay] at 07:00.
List<HcRecord> appDay(AppShape app, String wakeDay, {int seed = 0}) {
  final o = originOf(app);
  final v = valuesOf(app);
  final wake = DayKey.start(wakeDay).add(const Duration(hours: 7));
  final bed = wake.subtract(const Duration(hours: 8));
  final id = '${app.name}-$wakeDay';
  final out = <HcRecord>[
    ...night('$id-sleep', bed, wake, origin: o),
    // HR every minute from bed to 21:00 of the wake day (dense).
    for (var m = 0; m < 22 * 60; m++)
      hr(
        '$id-hr${m ~/ 60}',
        bed.add(Duration(minutes: m)),
        v.hr + (m % 7) + seed % 3,
        origin: o,
      ),
  ];
  if (v.hrv > 0) {
    for (var i = 0; i < 20; i++) {
      out.add(
        HcRecord(
          type: HcType.hrv,
          id: '$id-hrv$i',
          origin: o,
          start: bed.add(Duration(minutes: 20 + i * 20)),
          end: bed.add(Duration(minutes: 20 + i * 20)),
          value: v.hrv + (i % 5) + seed % 4,
        ),
      );
    }
  }
  if (v.rhr > 0) {
    out.add(
      scalar(HcType.restingHr, '$id-rhr', wake, v.rhr + seed % 3, origin: o),
    );
  }
  if (v.resp > 0) {
    out.add(
      scalar(
        HcType.respiratoryRate,
        '$id-resp',
        wake.subtract(const Duration(hours: 2)),
        v.resp,
        origin: o,
      ),
    );
  }
  if (app == AppShape.fitbit || app == AppShape.oura) {
    out.add(
      scalar(
        HcType.skinTemp,
        '$id-skin',
        wake.subtract(const Duration(hours: 3)),
        0.1,
        origin: o,
      ),
    );
  }
  if (v.steps > 0) {
    out.add(
      scalar(
        HcType.steps,
        '$id-steps',
        wake.add(const Duration(hours: 3)),
        v.steps,
        origin: o,
        end: wake.add(const Duration(hours: 4)),
      ),
    );
  }
  return out;
}

/// Maps [records] through the real mapper and a memory store (so HR is
/// bucketed per origin as in the app).
RawRows ingest(List<HcRecord> records, DateTime now) {
  final m = mapHcRecords(records, now: now, ingestedAt: now);
  final store = MemoryRawStore()..upsertSync(m.rows);
  return store.loadSync(DateTime(2000), DateTime(2100));
}
