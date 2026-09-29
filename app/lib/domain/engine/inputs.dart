// Sanitised reads of DayRecord inputs. [ours]
//
// Numerical hygiene: every formula reads its inputs through here, so a NaN,
// Infinity, zero or physiologically impossible value from any source is
// treated as ABSENT (and gets a StatusNote) instead of propagating into a
// score. Normal values pass through unchanged, so Pulse parity is unaffected.

import '../models.dart';
import 'stats.dart';

abstract final class Inputs {
  static double? _range(double? x, double lo, double hi) {
    final v = finiteOrNull(x);
    if (v == null || v < lo || v > hi) return null;
    return v;
  }

  /// RMSSD in ms, (0, 500]. ln() is taken of this, so it must be > 0.
  static double? hrv(DayRecord r) {
    final v = finiteOrNull(r.hrvRmssd);
    return (v == null || v <= 0 || v > 500) ? null : v;
  }

  static double? rhr(DayRecord r) => _range(r.restingHr, 25, 150);

  /// Sleeping HR (4 h mean); never read where resting HR is meant.
  static double? sleepingHr(DayRecord r) => _range(r.sleepingHr4h, 25, 150);
  static double? resp(DayRecord r) => _range(r.respiratoryRate, 4, 60);
  static double? spo2Avg(DayRecord r) => _range(r.spo2Avg, 50, 100);
  static double? spo2Min(DayRecord r) => _range(r.spo2Min, 30, 100);

  /// Skin temperature (a delta in °C from Health Connect). Only finiteness
  /// and a loose |x| ≤ 50 bound are enforced: every rule applied to it
  /// (baseline z, ± band) is shift-invariant, so absolute temperatures (as in
  /// Pulse's fixtures) behave identically.
  static double? skinTemp(DayRecord r) => _range(r.skinTempDelta, -50, 50);

  static double? vo2max(DayRecord r) => _range(r.vo2max, 5, 100);

  static int? steps(DayRecord r) {
    final s = r.steps;
    return (s == null || s < 0 || s > 200000) ? null : s;
  }

  /// Max-HR override if plausible, else null.
  static double? maxHrOverride(UserProfile p) =>
      _range(p.maxHrOverride, 100, 240);

  static double minutes(double x) => (x.isFinite && x > 0) ? x : 0;

  /// Asleep minutes of a session (NaN/negative → 0).
  static double asleep(SleepSession s) => minutes(s.minutesAsleep);

  /// Clean HR samples, oldest first. Implausible readings are dropped.
  static List<HrSample> hr(DayRecord r) => cleanHr(r.hrSamples);

  static List<HrSample> cleanHr(List<HrSample> samples) {
    final out = <HrSample>[];
    var sorted = true;
    for (final s in samples) {
      if (!s.bpm.isFinite || s.bpm < 25 || s.bpm > 250) continue;
      if (out.isNotEmpty && s.t.isBefore(out.last.t)) sorted = false;
      out.add(s);
    }
    if (!sorted) out.sort((a, b) => a.t.compareTo(b.t));
    return out;
  }

  /// Main sleep (flagged, else longest), ignoring corrupt minute values.
  static SleepSession? mainSleep(DayRecord r) {
    for (final s in r.sleepSessions) {
      if (s.isMainSleep) return s;
    }
    if (r.sleepSessions.isEmpty) return null;
    return r.sleepSessions.reduce((a, b) => asleep(a) >= asleep(b) ? a : b);
  }

  static double totalSleep(DayRecord r) =>
      r.sleepSessions.fold(0.0, (a, s) => a + asleep(s));
}
