// Column-oriented HR samples for the hot loops, and cheap civil-date math.
// [ours]
//
// Performance notes (measured on the Windows desktop VM): constructing a
// LOCAL DateTime (e.g. DayKey.start) costs ~30 µs and a local hour/minute
// read ~10 µs, because each needs a time-zone lookup; boxed 64-bit ints in
// typed lists are slow too. So the engine
//   * converts each day's clean, sorted samples once into a Float64List of
//     minutes since the first sample (+ bpm), working on index ranges;
//   * does calendar-day arithmetic on "yyyy-MM-dd" keys in UTC (civil dates
//     are time-zone independent, so results equal DayKey.add);
//   * reads a clock time with ONE offset lookup.

import 'dart:typed_data';

import '../day_key.dart';
import '../models.dart';

class HrSeries {
  HrSeries._(this.originUs, this.m, this.bpm);

  /// microsecondsSinceEpoch of sample 0 (0 when empty).
  final int originUs;

  /// Minutes since [originUs], ascending.
  final Float64List m;
  final Float64List bpm;

  int get length => m.length;
  bool get isEmpty => m.isEmpty;

  /// [us] (epoch µs) on this series' minute axis.
  double toMin(int us) => (us - originUs) / 6e7;

  /// From samples (sorted here if they are not already).
  factory HrSeries.of(List<HrSample> samples) {
    var list = samples;
    for (var i = 1; i < list.length; i++) {
      if (list[i].t.isBefore(list[i - 1].t)) {
        list = [...samples]..sort((a, b) => a.t.compareTo(b.t));
        break;
      }
    }
    final origin = list.isEmpty ? 0 : list.first.t.microsecondsSinceEpoch;
    final m = Float64List(list.length);
    final bpm = Float64List(list.length);
    for (var i = 0; i < list.length; i++) {
      m[i] = (list[i].t.microsecondsSinceEpoch - origin) / 6e7;
      bpm[i] = list[i].bpm;
    }
    return HrSeries._(origin, m, bpm);
  }

  /// First index with minute ≥ [x].
  int lowerBound(double x) {
    var lo = 0;
    var hi = m.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (m[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// First index with minute > [x].
  int upperBound(double x) {
    var lo = 0;
    var hi = m.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (m[mid] <= x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Index range [from, to) of samples with start ≤ t ≤ end (inclusive, as
  /// Pulse's workout slice, StrainEngine.swift:172).
  (int, int) closedRange(DateTime start, DateTime end) => (
    lowerBound(toMin(start.microsecondsSinceEpoch)),
    upperBound(toMin(end.microsecondsSinceEpoch)),
  );
}

/// Merged, sorted [start, end) intervals in epoch microseconds.
typedef UsIntervals = List<(int, int)>;

/// Walks a series' sorted samples through sorted, merged intervals in O(n + m).
class IntervalCursor {
  IntervalCursor(HrSeries s, UsIntervals intervals)
    : _a = [for (final (a, _) in intervals) s.toMin(a)],
      _b = [for (final (_, b) in intervals) s.toMin(b)];
  final List<double> _a;
  final List<double> _b;
  int _i = 0;

  /// True if minute [x] lies in an interval. Calls must be non-decreasing.
  bool inside(double x) {
    while (_i < _b.length && _b[_i] <= x) {
      _i++;
    }
    return _i < _a.length && _a[_i] <= x;
  }
}

/// Civil-date helpers on "yyyy-MM-dd" keys. Same results as DayKey, without
/// local-time construction.
abstract final class Civil {
  static final RegExp _re = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static bool valid(String key) {
    final match = _re.firstMatch(key);
    if (match == null) return false;
    final y = int.parse(match[1]!);
    final mo = int.parse(match[2]!);
    final d = int.parse(match[3]!);
    final u = DateTime.utc(y, mo, d);
    return u.year == y && u.month == mo && u.day == d;
  }

  /// DayKey.add equivalent.
  static String add(String key, int days) {
    final y = int.parse(key.substring(0, 4));
    final mo = int.parse(key.substring(5, 7));
    final d = int.parse(key.substring(8, 10));
    return _fmt(DateTime.utc(y, mo, d + days));
  }

  /// DayKey.range equivalent (inclusive, oldest first).
  static List<String> range(String from, String to) {
    final out = <String>[];
    var k = from;
    while (k.compareTo(to) <= 0) {
      out.add(k);
      k = add(k, 1);
    }
    return out;
  }

  /// ISO weekday (1 = Monday … 7 = Sunday) of a key.
  static int weekday(String key) => DateTime.utc(
    int.parse(key.substring(0, 4)),
    int.parse(key.substring(5, 7)),
    int.parse(key.substring(8, 10)),
  ).weekday;

  static String _fmt(DateTime u) =>
      '${u.year.toString().padLeft(4, '0')}-'
      '${u.month.toString().padLeft(2, '0')}-'
      '${u.day.toString().padLeft(2, '0')}';

  /// Local minutes since midnight (hour·60 + minute), one offset lookup.
  static double clockMinutes(DateTime t) {
    final l = t.isUtc ? t.toLocal() : t;
    final us = l.microsecondsSinceEpoch + l.timeZoneOffset.inMicroseconds;
    final minutes = (us - us % 60000000) ~/ 60000000; // floor division
    return (minutes % 1440).toDouble();
  }
}

/// Local midnights (DayKey.start semantics) for many keys at about one
/// time-zone lookup per key, instead of the several a local DateTime
/// constructor needs. Falls back to DayKey.start on any inconsistency
/// (e.g. a DST gap at midnight).
abstract final class LocalMidnights {
  static int _offsetAt(int us) =>
      DateTime.fromMicrosecondsSinceEpoch(us).timeZoneOffset.inMicroseconds;

  static int _utcMidnight(String key) => DateTime.utc(
    int.parse(key.substring(0, 4)),
    int.parse(key.substring(5, 7)),
    int.parse(key.substring(8, 10)),
  ).microsecondsSinceEpoch;

  /// Epoch µs of local midnight for each key in [keys] and the day after it.
  static Map<String, int> forKeys(Iterable<String> keys) {
    final all = <String>{};
    for (final k in keys) {
      all
        ..add(k)
        ..add(Civil.add(k, 1));
    }
    final sorted = all.toList()..sort();
    final out = <String, int>{};
    int? prevOff;
    for (final k in sorted) {
      final u = _utcMidnight(k);
      final off = prevOff ?? _offsetAt(u);
      var local = u - off;
      final check = _offsetAt(local);
      if (check != off) {
        local = u - check;
        if (_offsetAt(local) != check) {
          local = DayKey.start(k).microsecondsSinceEpoch;
          out[k] = local;
          prevOff = null;
          continue;
        }
      }
      out[k] = local;
      prevOff = u - local;
    }
    return out;
  }
}
