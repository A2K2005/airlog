import 'dart:math' as math;

import 'package:airlog/data/db/raw_rows.dart';
import 'package:airlog/data/services/demo/demo_generator.dart';
import 'package:airlog/data/services/demo/demo_live_hr_service.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 28, 9, 30);

String fingerprint(DemoDataset d) {
  final b = StringBuffer();
  for (final r in d.rows.hr.take(500)) {
    b.write('${r.t.millisecondsSinceEpoch}:${r.bpm};');
  }
  b
    ..write(d.rows.hr.length)
    ..write('|')
    ..write([for (final r in d.rows.hrv) r.rmssd].join(','))
    ..write('|')
    ..write(
      [for (final s in d.rows.sleep) '${s.start}-${s.end}-${s.stages.length}']
          .join(','),
    )
    ..write('|')
    ..write([for (final w in d.rows.workouts) '${w.name}@${w.start}'].join(','))
    ..write('|')
    ..write(
      [for (final s in d.rows.scalars) '${s.scalar.code}=${s.value}'].join(','),
    )
    ..write('|')
    ..write([for (final j in d.journal) j.toJson()].join(','));
  return b.toString();
}

double avg(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

void main() {
  late DemoDataset ds;
  setUpAll(() => ds = DemoGenerator(seed: 42, now: now).generate());

  test('deterministic: same seed + now ⇒ identical output', () {
    final again = DemoGenerator(seed: 42, now: now).generate();
    expect(fingerprint(again), fingerprint(ds));
  });

  test('different seed ⇒ different data', () {
    final other = DemoGenerator(seed: 7, now: now).generate();
    expect(fingerprint(other), isNot(fingerprint(ds)));
  });

  test('every row is demo-tagged and nothing is future-dated', () {
    for (final r in ds.rows.all) {
      expect(r.source, SourceKind.demo);
      expect(r.device, kDemoDevice);
      expect(
        r.end.isAfter(now),
        isFalse,
        reason: '${r.sourceRecordId} ends ${r.end}',
      );
    }
  });

  test('plausible ranges', () {
    for (final r in ds.rows.hr) {
      expect(r.bpm, inInclusiveRange(38, 205));
    }
    for (final r in ds.rows.hrv) {
      expect(r.rmssd, inInclusiveRange(8, 180));
    }
    final rhr = ds.rows.scalars
        .where((s) => s.scalar == ScalarKind.rhr)
        .map((s) => s.value);
    expect(rhr.reduce(math.min), greaterThan(40));
    expect(rhr.reduce(math.max), lessThan(75));
    final mains = ds.rows.sleep
        .where((s) => s.end.difference(s.start).inHours >= 3)
        .toList();
    expect(mains.length, inInclusiveRange(85, 90));
    for (final s in mains) {
      final h = s.end.difference(s.start).inMinutes / 60;
      expect(h, inInclusiveRange(4.3, 10.5));
      expect(
        s.stages.map((x) => x.stage).toSet(),
        containsAll([SleepStage.light, SleepStage.deep, SleepStage.rem]),
      );
    }
    // HR at 1/min on complete days (charging gap aside).
    final day = DayKey.add(DayKey.of(now), -5);
    final n = ds.rows.hr.where((r) => DayKey.of(r.t) == day).length;
    expect(n, inInclusiveRange(1200, 1440));
    // HRV every ~5 min during sleep.
    final nightHrv = ds.rows.hrv.where((r) => nightMatches(r, day)).length;
    expect(nightHrv, inInclusiveRange(60, 130));
    // 3-5 workouts a week on average.
    final perWeek = ds.rows.workouts.length / (90 / 7);
    expect(perWeek, inInclusiveRange(3, 5.2));
  });

  test('planted illness is visible in RHR, HRV, resp and skin temp', () {
    final ill = ds.plan.illnessDays.toSet();
    expect(ill, hasLength(4));
    double mean(ScalarKind k, bool inIll) => avg(
      ds.rows.scalars
          .where(
            (s) => s.scalar == k && ill.contains(DayKey.of(s.start)) == inIll,
          )
          .map((s) => s.value),
    );
    expect(
      mean(ScalarKind.rhr, true) - mean(ScalarKind.rhr, false),
      greaterThan(4),
    );
    expect(
      mean(ScalarKind.resp, true) - mean(ScalarKind.resp, false),
      greaterThan(1),
    );
    expect(
      mean(ScalarKind.skinTempDelta, true) -
          mean(ScalarKind.skinTempDelta, false),
      greaterThan(0.4),
    );
    final hrvIll = avg(
      ds.rows.hrv.where((r) => ill.contains(wakeDay(r))).map((r) => r.rmssd),
    );
    final hrvOk = avg(
      ds.rows.hrv.where((r) => !ill.contains(wakeDay(r))).map((r) => r.rmssd),
    );
    expect(hrvIll / hrvOk, lessThan(0.8));
  });

  test('wear gaps: most days have a ~2 h charging gap, one day a 6 h gap', () {
    final gapDay = ds.plan.longGapDay!;
    final rows = ds.rows.hr.where((r) => DayKey.of(r.t) == gapDay).toList()
      ..sort((a, b) => a.t.compareTo(b.t));
    var longest = Duration.zero;
    for (var i = 1; i < rows.length; i++) {
      final g = rows[i].t.difference(rows[i - 1].t);
      if (g > longest) longest = g;
    }
    expect(longest.inMinutes, inInclusiveRange(355, 365));
  });

  test('journal: alcohol evenings and sick days are logged', () {
    final alcohol = ds.journal.where(
      (j) => j.factors.contains(JournalFactor.alcohol),
    );
    expect(alcohol.length, greaterThanOrEqualTo(7));
    expect(
      ds.journal.where((j) => j.factors.contains(JournalFactor.sick)),
      isNotEmpty,
    );
    expect(ds.plan.poorSleepDays, isNotEmpty);
  });

  test('DemoLiveHrService: ~1 Hz samples with RR intervals, no timers before connect', () async {
    final svc = DemoLiveHrService(tick: const Duration(milliseconds: 5));
    final devices = await svc.scan().first;
    expect(devices.single.name, contains('demo'));
    final got = <LiveHrSample>[];
    final sub = svc.samples.listen(got.add);
    await svc.connect(devices.single);
    expect(svc.phase, LiveHrPhase.connected);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await svc.disconnect();
    await sub.cancel();
    expect(got.length, greaterThan(5));
    expect(svc.rrAvailable, isTrue);
    final rr = [for (final s in got) ...s.rrMs];
    expect(rr.every((x) => x > 300 && x < 1600), isTrue);
    expect(
      got.first.bpm,
      inInclusiveRange(55, 75),
      reason: 'starts at rest for HRV checks',
    );
    await svc.dispose();
  });
}

String wakeDay(RawHrvRow r) =>
    r.t.hour >= 18 ? DayKey.add(DayKey.of(r.t), 1) : DayKey.of(r.t);
bool nightMatches(RawHrvRow r, String day) => wakeDay(r) == day;
