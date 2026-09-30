// Recovery without HRV (sources such as WHOOP don't write HRV to Health
// Connect): scored from the remaining inputs with the weights re-normalised,
// labelled, with lower confidence and an honest note. HRV is never invented.

import 'dart:convert';

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/recovery.dart';
import 'package:airlog/domain/engine/source_apps.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/builders.dart';

Provenance hc(String def, String origin) =>
    Provenance(SourceKind.healthConnect, def, origin: origin);

/// A dense day whose nightly inputs come from [origin]; HRV only if [hrv].
DayRecord fromApp(String date, String origin, {double? hrv}) {
  final d = denseDay(date, hrv: hrv, rhr: 54, resp: 14.5, skinTemp: 0.1);
  d.provenance
    ..[Metric.restingHr] = hc('hc_daily_rhr', origin)
    ..[Metric.respiratoryRate] = hc('hc_nightly_resp', origin)
    ..[Metric.skinTemp] = hc('hc_nightly_skin_temp_delta', origin)
    ..[Metric.sleep] = hc('hc_sleep_sessions', origin);
  if (hrv != null) {
    d.provenance[Metric.hrv] = hc('hc_sleep_mean_rmssd', origin);
  } else {
    d.provenance.remove(Metric.hrv);
  }
  return d;
}

List<DayRecord> nights(String last, int n, String origin, {double? hrv}) => [
  for (var i = 0; i < n; i++)
    fromApp(DayKey.add(last, i - (n - 1)), origin, hrv: hrv),
];

void main() {
  final now = DateTime(2026, 9, 29, 9);

  test('scored from the other inputs, weights re-normalised, labelled, '
      'lower confidence, no HRV value anywhere', () {
    final days = nights('2026-09-20', 20, SourceApps.whoop);
    final rs = Engine.computeRange(days, now: now);
    final rec = rs.last.recovery!;
    expect(rec.withoutHrv, isTrue);
    expect(rec.hrvValue, isNull);
    expect(rec.hrvBaseline, isNull);
    expect(rec.components.map((c) => c.key), isNot(contains('hrv')));
    final sum = rec.components.fold(0.0, (a, c) => a + c.weight);
    expect(sum, closeTo(1, 1e-9));
    // RHR 25 / sleep 25 / resp 10 of the full 100 → 0.6 of the model.
    expect(rec.coverage, closeTo(0.6, 1e-9));
    final rhr = rec.components.firstWhere((c) => c.key == 'rhr');
    expect(rhr.weight, closeTo(0.25 / 0.6, 1e-9));
    expect(rec.confidence, RecoveryConfidence.reduced);
    // The monitor shows no HRV rather than a guessed one.
    final hrvBand = rs.last.health.metrics.firstWhere(
      (m) => m.kind == HealthMetricKind.hrv,
    );
    expect(hrvBand.state, BandState.noData);
    expect(hrvBand.value, isNull);
    expect(rs.last.readiness, isNull);
  });

  test('the note names the app and says what fixes it', () {
    final rs = Engine.computeRange(
      nights('2026-09-20', 5, SourceApps.whoop),
      now: now,
    );
    final n = rs.last.notes.firstWhere((n) => n.metric == 'hrv');
    expect(n.title, 'Recovery without HRV');
    expect(n.body, contains('WHOOP doesn’t share HRV with Health Connect'));
    expect(n.body, contains('without HRV'));
    expect(n.fix, contains('Settings → Data sources'));
    expect(n.severity, NoteSeverity.warning);
  });

  test('first nights of a new app: not yet blamed on the app', () {
    final rs = Engine.computeRange(
      nights('2026-09-20', 2, SourceApps.whoop),
      now: now,
    );
    final n = rs.last.notes.firstWhere((n) => n.metric == 'hrv');
    expect(n.title, 'No HRV yet');
  });

  test('an app that normally writes HRV and missed a night keeps the '
      'wear note', () {
    final days = [
      ...nights('2026-09-19', 10, SourceApps.fitbit, hrv: 45),
      fromApp('2026-09-20', SourceApps.fitbit),
    ];
    final r = Engine.computeRange(days, now: now).last;
    expect(r.recovery!.withoutHrv, isTrue);
    final n = r.notes.firstWhere((n) => n.metric == 'hrv');
    expect(n.title, 'No HRV for this night');
  });

  test('a new app without HRV after an old one with it is named once the '
      'old HRV is more than 14 days old', () {
    final days = [
      ...nights('2026-09-01', 10, SourceApps.fitbit, hrv: 45),
      ...nights('2026-09-20', 19, SourceApps.whoop),
    ];
    final r = Engine.computeRange(days, now: now).last;
    expect(
      r.notes.firstWhere((n) => n.metric == 'hrv').title,
      'Recovery without HRV',
    );
  });

  test('legacy or demo data without an origin keeps the generic note', () {
    final days = denseRange('2026-09-20', 10);
    final today = denseDay('2026-09-21', hrv: null);
    final r = Engine.computeDay(today, history: days, now: now);
    expect(
      r.notes.firstWhere((n) => n.metric == 'hrv').title,
      'No HRV for this night',
    );
  });

  test('confidence tiers', () {
    expect(
      RecoveryEngine.confidenceFor(hasHrv: true, coverage: 1),
      RecoveryConfidence.high,
    );
    expect(
      RecoveryEngine.confidenceFor(hasHrv: true, coverage: 0.9),
      RecoveryConfidence.high,
    );
    expect(
      RecoveryEngine.confidenceFor(hasHrv: true, coverage: 0.65),
      RecoveryConfidence.reduced,
    );
    expect(
      RecoveryEngine.confidenceFor(hasHrv: false, coverage: 0.6),
      RecoveryConfidence.reduced,
    );
    expect(
      RecoveryEngine.confidenceFor(hasHrv: false, coverage: 0.25),
      RecoveryConfidence.low,
    );
  });

  test('new fields round-trip through JSON', () {
    final rec = Engine.computeRange(
      nights('2026-09-20', 8, SourceApps.whoop),
      now: now,
    ).last.recovery!;
    final back = RecoveryResult.fromJson(
      jsonDecode(jsonEncode(rec.toJson())) as Map<String, dynamic>,
    );
    expect(back.withoutHrv, isTrue);
    expect(back.coverage, rec.coverage);
    expect(back.confidence, rec.confidence);
  });

  test('with HRV the score is unchanged and marked high confidence', () {
    final rec = Engine.computeRange(
      denseRange('2026-09-20', 20),
      now: now,
    ).last.recovery!;
    expect(rec.withoutHrv, isFalse);
    expect(rec.coverage, closeTo(1, 1e-9));
    expect(rec.confidence, RecoveryConfidence.high);
  });
}
