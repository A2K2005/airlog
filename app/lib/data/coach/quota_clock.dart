// When a provider's daily quota comes back. Google's Gemini API quotas
// reset at midnight Pacific time; the coach skips a model whose per-model
// day quota is used up until then (CoachRepositoryImpl.noteModelUnavailable).
//
// No time-zone database: US Pacific is UTC−8, or UTC−7 from the second
// Sunday of March 02:00 to the first Sunday of November 02:00 local.
// Pure Dart.

/// The next midnight in US Pacific time after [now], as a UTC instant.
DateTime nextPacificMidnight(DateTime now) {
  final utc = now.toUtc();
  final offset = _pacificOffset(utc);
  final wall = utc.add(offset);
  final midnight = DateTime.utc(wall.year, wall.month, wall.day + 1);
  // DST switches at 02:00, never at midnight, but the day may change it.
  var result = midnight.subtract(offset);
  final after = _pacificOffset(result);
  if (after != offset) result = midnight.subtract(after);
  return result;
}

Duration _pacificOffset(DateTime utc) {
  final y = utc.year;
  // 02:00 PST = 10:00 UTC; 02:00 PDT = 09:00 UTC.
  final start = _nthSunday(y, 3, 2).add(const Duration(hours: 10));
  final end = _nthSunday(y, 11, 1).add(const Duration(hours: 9));
  final dst = !utc.isBefore(start) && utc.isBefore(end);
  return Duration(hours: dst ? -7 : -8);
}

DateTime _nthSunday(int year, int month, int n) {
  final first = DateTime.utc(year, month, 1);
  final toSunday = (7 - first.weekday % 7) % 7;
  return first.add(Duration(days: toSunday + 7 * (n - 1)));
}
