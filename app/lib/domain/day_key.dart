// Calendar-day keys ("yyyy-MM-dd") in the phone's local time zone.
//
// CONTRACT FILE — shared by domain/, data/ and features/. Additive changes only.
//
// Nightly metrics (HRV, resting HR, respiratory rate, SpO2, skin temperature)
// belong to the day you WAKE UP on, so a night from Mon 23:10 to Tue 07:02 is
// keyed "Tue". This matches Pulse's DayRecord convention.

class DayKey {
  DayKey._();

  static String of(DateTime t) {
    final l = t.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-'
        '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  /// Local midnight at the start of [key].
  static DateTime start(String key) {
    final p = key.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// Local midnight at the end of [key] (start of the next day).
  static DateTime end(String key) {
    final s = start(key);
    return DateTime(s.year, s.month, s.day + 1);
  }

  static String add(String key, int days) {
    final s = start(key);
    return of(DateTime(s.year, s.month, s.day + days));
  }

  static String today([DateTime? now]) => of(now ?? DateTime.now());

  /// Inclusive list of keys from [from] to [to], oldest first.
  static List<String> range(String from, String to) {
    final out = <String>[];
    var k = from;
    while (k.compareTo(to) <= 0) {
      out.add(k);
      k = add(k, 1);
    }
    return out;
  }

  /// Whole days between two keys (b - a).
  static int diff(String a, String b) {
    final da = start(a), db = start(b);
    return (DateTime.utc(
              db.year,
              db.month,
              db.day,
            ).difference(DateTime.utc(da.year, da.month, da.day)).inHours /
            24)
        .round();
  }
}

/// The journal "evening" a timestamp belongs to: before 05:00 counts as the
/// previous evening, so late-night tags pair with the next morning's
/// recovery (engine: factor on day D → recovery on D+1).
String eveningKeyOf(DateTime now) {
  final l = now.toLocal();
  return l.hour < 5 ? DayKey.add(DayKey.of(l), -1) : DayKey.of(l);
}
