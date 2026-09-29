// Small time helpers shared by the data layer (pure Dart).

import '../../domain/day_key.dart';

/// Injected clock so tests (and the in-memory demo repository) are
/// deterministic.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();

/// Memoises the local day that contains the last instant asked for, so hot
/// loops over time-sorted samples don't re-format a date per sample.
class _DayCache {
  int _lo = 0, _hi = -1, _eve = 0;
  String _key = '', _next = '';

  void _fill(DateTime t) {
    final l = t.toLocal();
    _key = DayKey.of(l);
    final s = DayKey.start(_key);
    _lo = s.millisecondsSinceEpoch;
    _hi = DayKey.end(_key).millisecondsSinceEpoch;
    _eve = DateTime(s.year, s.month, s.day, 18).millisecondsSinceEpoch;
    _next = DayKey.add(_key, 1);
  }

  String of(DateTime t) {
    final m = t.millisecondsSinceEpoch;
    if (m < _lo || m >= _hi) _fill(t);
    return _key;
  }

  String night(DateTime t) {
    final m = t.millisecondsSinceEpoch;
    if (m < _lo || m >= _hi) _fill(t);
    return m >= _eve ? _next : _key;
  }
}

final _DayCache _dayCache = _DayCache();

/// Fast [DayKey.of] for hot loops (same result).
String dayKeyOf(DateTime t) => _dayCache.of(t);

/// The wake day a night-time instant belongs to (ARCHITECTURE: nightly
/// metrics belong to the day you WAKE UP on). Instants from 18:00 local
/// onward count towards the next day; earlier ones to the same day.
String nightKey(DateTime t) => _dayCache.night(t);

/// Milliseconds since epoch (UTC) — the storage format for every timestamp.
int ms(DateTime t) => t.millisecondsSinceEpoch;

DateTime fromMs(int v) => DateTime.fromMillisecondsSinceEpoch(v);

/// Overlap of two intervals in milliseconds (0 when disjoint).
int overlapMs(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
  final s = aStart.isAfter(bStart) ? aStart : bStart;
  final e = aEnd.isBefore(bEnd) ? aEnd : bEnd;
  final d = e.difference(s).inMilliseconds;
  return d > 0 ? d : 0;
}

/// Every day key touched by [start]..[end] (inclusive), plus the next day
/// when the interval reaches into the evening (nightly metrics move there).
Set<String> daysTouched(DateTime start, DateTime end) {
  final e = end.isBefore(start) ? start : end;
  final first = dayKeyOf(start);
  final last = dayKeyOf(e);
  final night = nightKey(e);
  if (first == last) return {first, night};
  final out = <String>{};
  var k = first;
  var guard = 0;
  while (k.compareTo(last) <= 0 && guard++ < 400) {
    out.add(k);
    k = DayKey.add(k, 1);
  }
  out.add(night);
  return out;
}

double median(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double mean(Iterable<double> xs) {
  var n = 0;
  var sum = 0.0;
  for (final x in xs) {
    n++;
    sum += x;
  }
  return n == 0 ? double.nan : sum / n;
}
