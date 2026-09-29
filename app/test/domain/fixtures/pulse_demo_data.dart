// Ported from Luraxx/pulse Core/Demo/DemoData.swift (Apache-2.0, see
// third_party/pulse/NOTICE). Changes: Dart port used ONLY as the parity-test
// fixture; `today` and `now` are injected (Pulse reads the wall clock, which
// is why its SelfTest assertions are date-independent ranges); Pulse's
// absolute bodyTemp is stored in `skinTempDelta` unchanged (every rule that
// reads it is shift-invariant); Swift's `Double.random(in:using:)` (Lemire
// bounded integer over 2^53 + 1, × 2^-53) and xorshift64 are reproduced
// algorithmically — bit-exactness against a Swift run is unverified (no
// Swift toolchain here), so parity rests on Pulse's range assertions.

import 'dart:math' as math;

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/stats.dart';
import 'package:airlog/domain/models.dart';

/// xorshift64 (DemoData.swift:5-18).
class SeededRng {
  SeededRng(int seed) : _state = seed == 0 ? -0x61C8864680B583EB : seed;
  int _state;

  static final BigInt _mask64 = (BigInt.one << 64) - BigInt.one;
  static final BigInt _two64 = BigInt.one << 64;
  static final BigInt _maxSignificand = BigInt.one << 53;

  int next() {
    var s = _state;
    s ^= s << 13;
    s ^= s >>> 7;
    s ^= s << 17;
    _state = s;
    return s;
  }

  BigInt _u() => BigInt.from(next()).toUnsigned(64);

  /// Swift RandomNumberGenerator.next(upperBound:) (Lemire).
  BigInt nextBelow(BigInt upperBound) {
    var m = _u() * upperBound;
    if ((m & _mask64) < upperBound) {
      final t = (_two64 - upperBound) % upperBound;
      while ((m & _mask64) < t) {
        m = _u() * upperBound;
      }
    }
    return m >> 64;
  }

  /// Swift `Double.random(in: lo...hi, using:)` for a closed range.
  double uniform(double lo, double hi) {
    final rand = nextBelow(_maxSignificand + BigInt.one);
    if (rand == _maxSignificand) return hi;
    final unit = rand.toDouble() * 1.1102230246251565e-16; // ulpOfOne / 2
    return (hi - lo) * unit + lo;
  }

  /// `Int(rng.next() % UInt64(n))`.
  int nextIndex(int n) => (_u() % BigInt.from(n)).toInt();
}

abstract final class PulseDemoData {
  /// DemoData.swift:24-142. [today] replaces `DayKey.today()`, [now]
  /// replaces `Date()` (HR samples stop at now).
  static Map<String, DayRecord> generate({
    int daysBack = 120,
    int seed = 42,
    required String today,
    required DateTime now,
  }) {
    final rng = SeededRng(seed);
    final result = <String, DayRecord>{};
    var previousIntensity = 0.0;
    var previousAlcohol = false;

    for (var offset = daysBack - 1; offset >= 0; offset--) {
      final key = DayKey.add(today, -offset);
      final dayStart = DayKey.start(key);
      final weekday = dayStart.weekday % 7 + 1; // Swift: 1 = Sun … 7 = Sat
      final intensity = _trainingIntensity(weekday, rng);
      final isWeekend = weekday == 1 || weekday == 7;
      final alcohol = rng.uniform(0, 1) < (isWeekend ? 0.20 : 0.06);

      final dayIndex = (daysBack - offset).toDouble();
      final slowWave = math.sin(dayIndex / 14 * math.pi) * 3.5;

      final hrv = Stats.clamp(
        62 +
            slowWave +
            rng.uniform(-6, 6) -
            previousIntensity * 11 -
            (previousAlcohol ? 12 : 0),
        25,
        110,
      );
      final rhr = Stats.clamp(
        52 -
            slowWave * 0.4 +
            rng.uniform(-2, 2) +
            previousIntensity * 4 +
            (previousAlcohol ? 5 : 0),
        42,
        78,
      );
      final resp =
          14.2 + rng.uniform(-0.35, 0.35) + (previousAlcohol ? 0.9 : 0);
      final spo2 = Stats.clamp(96.8 + rng.uniform(-0.8, 0.6), 93, 99);
      final spo2Min = spo2 - rng.uniform(1.2, 2.8);
      final bodyTemp =
          33.9 + rng.uniform(-0.25, 0.25) + (previousAlcohol ? 0.4 : 0);
      final vo2 = Stats.clamp(
        46.0 + slowWave * 0.3 + rng.uniform(-0.5, 0.5),
        36,
        52,
      );

      // Sleep
      final sleepImpact = previousAlcohol ? -35.0 : 0.0;
      final wakeOffset =
          (6.8 + (isWeekend ? 0.9 : 0) + rng.uniform(-0.4, 0.5)) * 3600;
      final wake = _plus(dayStart, wakeOffset);
      final inBedMinutes = Stats.clamp(
        444 + rng.uniform(-55, 45) + sleepImpact - previousIntensity * 10,
        300,
        560,
      );
      final bed = _plus(wake, -inBedMinutes * 60);
      final session = _sleepSession('demo-$key', bed, wake, rng);
      final sessions = [session];
      if (rng.uniform(0, 1) < 0.06) {
        final napStart = _plus(dayStart, 14.2 * 3600);
        final napMinutes = rng.uniform(18, 40);
        sessions.add(
          SleepSession(
            id: 'demo-nap-$key',
            start: napStart,
            end: _plus(napStart, napMinutes * 60),
            minutesAsleep: napMinutes * 0.9,
            minutesAwake: napMinutes * 0.1,
            isMainSleep: false,
          ),
        );
      }

      // Workout
      Workout? workout;
      if (intensity > 0.2) {
        final names = switch (weekday) {
          2 || 5 => const ['Intervalle', 'Laufen'],
          3 => const ['Krafttraining', 'Rad'],
          7 => const ['Langer Lauf', 'Radtour'],
          _ => const ['Laufen', 'Rad', 'Krafttraining'],
        };
        final name = names[rng.nextIndex(names.length)];
        final duration = 35 + intensity * 60 + rng.uniform(0, 20);
        final startHour = weekday == 7 ? 10.0 : 17.5 + rng.uniform(-1.0, 1.5);
        final start = _plus(dayStart, startHour * 3600);
        const maxHr = 187.0;
        final avgHr = rhr + (maxHr - rhr) * (0.48 + intensity * 0.32);
        workout = Workout(
          id: 'demo-workout-$key',
          name: name,
          start: start,
          end: _plus(start, duration * 60),
          averageHr: avgHr,
          calories: duration * (6 + intensity * 6),
        );
      }

      final steps = (3500 + intensity * 9000 + rng.uniform(0, 2500)).toInt();

      final hr = offset < 28
          ? _hrSamples(dayStart, session, workout, rhr, rng, now)
          : <HrSample>[];

      result[key] = DayRecord(
        date: key,
        hrvRmssd: hrv,
        restingHr: rhr,
        respiratoryRate: resp,
        spo2Avg: spo2,
        spo2Min: spo2Min,
        skinTempDelta: bodyTemp,
        vo2max: vo2,
        steps: steps,
        sleepSessions: sessions,
        workouts: workout == null ? [] : [workout],
        hrSamples: hr,
      );
      previousIntensity = intensity;
      previousAlcohol = alcohol;
    }
    return result;
  }

  static DateTime _plus(DateTime t, double seconds) =>
      t.add(Duration(microseconds: (seconds * 1e6).round()));

  /// DemoData.swift:144-157.
  static double _trainingIntensity(int weekday, SeededRng rng) {
    final base = switch (weekday) {
      2 => 0.85,
      3 => 0.55,
      4 => 0.25,
      5 => 0.80,
      6 => 0.10,
      7 => 0.70,
      _ => 0.0,
    };
    if (base <= 0) return 0;
    return Stats.clamp(base + rng.uniform(-0.15, 0.15), 0, 1);
  }

  /// DemoData.swift:159-201.
  static SleepSession _sleepSession(
    String id,
    DateTime bed,
    DateTime wake,
    SeededRng rng,
  ) {
    final stages = <StageSpan>[];
    var cursor = bed;
    var awakeMinutes = 0.0;
    final totalMinutes = wake.difference(bed).inMicroseconds / 6e7;
    var elapsed = 0.0;
    while (cursor.isBefore(wake)) {
      final progress = elapsed / totalMinutes;
      final roll = rng.uniform(0, 1);
      final SleepStage stage;
      if (roll < 0.05 && elapsed > 30) {
        stage = SleepStage.awake;
      } else if (progress < 0.45) {
        stage = roll < 0.42 ? SleepStage.deep : SleepStage.light;
      } else if (progress > 0.55) {
        stage = roll < 0.40 ? SleepStage.rem : SleepStage.light;
      } else {
        stage = SleepStage.light;
      }
      final length = stage == SleepStage.awake
          ? rng.uniform(2, 7)
          : rng.uniform(14, 36);
      var end = _plus(cursor, length * 60);
      if (end.isAfter(wake)) end = wake;
      stages.add(StageSpan(stage, cursor, end));
      final m = end.difference(cursor).inMicroseconds / 6e7;
      if (stage == SleepStage.awake) awakeMinutes += m;
      elapsed += m;
      cursor = end;
    }
    return SleepSession(
      id: id,
      start: bed,
      end: wake,
      minutesAsleep: totalMinutes - awakeMinutes,
      minutesAwake: awakeMinutes,
      stages: stages,
    );
  }

  /// DemoData.swift:203-235 (2-minute resolution).
  static List<HrSample> _hrSamples(
    DateTime dayStart,
    SleepSession session,
    Workout? workout,
    double rhr,
    SeededRng rng,
    DateTime now,
  ) {
    final samples = <HrSample>[];
    var minute = 0.0;
    while (minute < 1440) {
      final t = _plus(dayStart, minute * 60);
      if (t.isAfter(now)) break;
      double bpm;
      if (!t.isBefore(session.start) && t.isBefore(session.end)) {
        bpm = rhr + rng.uniform(-2, 6);
      } else if (workout != null &&
          !t.isBefore(workout.start) &&
          t.isBefore(workout.end) &&
          workout.averageHr != null) {
        final avgHr = workout.averageHr!;
        final progress =
            t.difference(workout.start).inMicroseconds /
            math.max(
              60e6,
              workout.end.difference(workout.start).inMicroseconds,
            );
        final ramp = math.min(1.0, progress * 4);
        bpm = rhr + (avgHr - rhr) * ramp + rng.uniform(-8, 10);
      } else {
        bpm = rhr + 14 + rng.uniform(-6, 14);
        if (rng.uniform(0, 1) < 0.03) bpm += rng.uniform(10, 30);
      }
      samples.add(HrSample(t, Stats.clamp(bpm, 40, 195)));
      minute += 2;
    }
    return samples;
  }
}

/// The fixed anchor used by every parity test (Pulse's own test date).
const String kPulseToday = '2026-07-18';
final DateTime kPulseNow = DateTime(2026, 7, 18, 20);

Map<String, DayRecord> pulseDemo() =>
    PulseDemoData.generate(today: kPulseToday, now: kPulseNow);
