// Date mentions in free text ("Tue 22 Sep", "22 Sep", "Sep 22", ISO,
// "yesterday", "last night", "3 days ago", "last Monday"), resolved against
// the user's local "today". Shared by the verifier (date claims, date
// anchors of a sentence) and the offline intent router (which day or window
// a question is about). Pure Dart.

import '../day_key.dart';

enum DateMentionKind {
  /// An explicit calendar date (ISO, "22 Sep", "Tue 22 Sep").
  absolute,

  /// today / last night / this morning / yesterday / N days ago.
  relative,

  /// "last Monday" (checked) or "on Monday" (anchor only).
  weekday,
}

class DateMention {
  const DateMention({
    required this.start,
    required this.end,
    required this.dates,
    required this.kind,
    required this.text,
    this.checkable = true,
    this.weekdayMismatch,
  });

  /// Character span in the text.
  final int start;
  final int end;

  /// Resolved day keys (two for "23–29 Sep").
  final List<String> dates;
  final DateMentionKind kind;
  final String text;

  /// False for anchors that are too vague to be a claim ("on Monday").
  final bool checkable;

  /// "Tue 22 Sep" where 22 Sep is not a Tuesday: the actual weekday.
  final String? weekdayMismatch;
}

abstract final class DatePhrases {
  static const _wd = r'(mon|tue|wed|thu|fri|sat|sun)[a-z]*';
  static const _mo =
      r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?';
  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  static const _weekdays = {
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
    'sun': 7,
  };

  static final _iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');

  // [weekday] 22[nd] Sep[tember] [2026], and "23–29 Sep".
  static final _dayMonth = RegExp(
    '\\b(?:$_wd,?\\s+)?(\\d{1,2})(?:st|nd|rd|th)?'
    '(?:\\s*(?:–|-|to)\\s*(\\d{1,2})(?:st|nd|rd|th)?)?\\s+$_mo'
    '(?:,?\\s+(\\d{4}))?(?![a-z])',
    caseSensitive: false,
  );

  // [weekday] Sep[tember] 22[nd][, 2026]
  static final _monthDay = RegExp(
    '\\b(?:$_wd,?\\s+)?$_mo\\s+(\\d{1,2})(?:st|nd|rd|th)?'
    '(?:,?\\s+(\\d{4}))?(?![\\d:a-z])',
    caseSensitive: false,
  );

  static final _relative = RegExp(
    r'\b(the day before yesterday|yesterday|last night|this morning|'
    r'today|(\d{1,2}) days? ago)\b',
    caseSensitive: false,
  );

  static final _weekdayOnly = RegExp(
    r"\b(last|on|this past|past)?\s*(monday|tuesday|wednesday|thursday|friday|saturday|sunday)('s)?\b",
    caseSensitive: false,
  );

  /// Every date mention in [text], in order, non-overlapping.
  static List<DateMention> find(String text, String today) {
    final out = <DateMention>[];
    bool free(int s, int e) => out.every((m) => e <= m.start || s >= m.end);

    for (final m in _iso.allMatches(text)) {
      final key = _key(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
      if (key == null) continue;
      out.add(
        DateMention(
          start: m.start,
          end: m.end,
          dates: [key],
          kind: DateMentionKind.absolute,
          text: m.group(0)!,
        ),
      );
    }

    for (final m in _dayMonth.allMatches(text)) {
      if (!free(m.start, m.end)) continue;
      final monthTok = m.group(4)!;
      // "20 may help" is not a date: only a capitalised "May".
      if (monthTok.toLowerCase().startsWith('may') && monthTok[0] != 'M') {
        continue;
      }
      final month = _months[monthTok.substring(0, 3).toLowerCase()]!;
      final d1 = int.parse(m.group(2)!);
      final d2 = m.group(3) == null ? null : int.parse(m.group(3)!);
      final year = m.group(5) == null ? null : int.parse(m.group(5)!);
      final dates = <String>[];
      for (final d in [d1, ?d2]) {
        final k = year == null ? _infer(month, d, today) : _key(year, month, d);
        if (k != null) dates.add(k);
      }
      if (dates.isEmpty) continue;
      out.add(
        DateMention(
          start: m.start,
          end: m.end,
          dates: dates,
          kind: DateMentionKind.absolute,
          text: m.group(0)!,
          weekdayMismatch: _mismatch(m.group(1), dates.first),
        ),
      );
    }

    for (final m in _monthDay.allMatches(text)) {
      if (!free(m.start, m.end)) continue;
      final monthTok = m.group(2)!;
      if (monthTok.toLowerCase().startsWith('may') && monthTok[0] != 'M') {
        continue;
      }
      final month = _months[monthTok.substring(0, 3).toLowerCase()]!;
      final d = int.parse(m.group(3)!);
      final year = m.group(4) == null ? null : int.parse(m.group(4)!);
      final k = year == null ? _infer(month, d, today) : _key(year, month, d);
      if (k == null) continue;
      out.add(
        DateMention(
          start: m.start,
          end: m.end,
          dates: [k],
          kind: DateMentionKind.absolute,
          text: m.group(0)!,
          weekdayMismatch: _mismatch(m.group(1), k),
        ),
      );
    }

    for (final m in _relative.allMatches(text)) {
      if (!free(m.start, m.end)) continue;
      final p = m.group(1)!.toLowerCase();
      final String key;
      if (p == 'today' || p == 'this morning' || p == 'last night') {
        // A night belongs to the day you wake up on.
        key = today;
      } else if (p == 'yesterday') {
        key = DayKey.add(today, -1);
      } else if (p == 'the day before yesterday') {
        key = DayKey.add(today, -2);
      } else {
        key = DayKey.add(today, -int.parse(m.group(2)!));
      }
      out.add(
        DateMention(
          start: m.start,
          end: m.end,
          dates: [key],
          kind: DateMentionKind.relative,
          text: m.group(0)!,
        ),
      );
    }

    for (final m in _weekdayOnly.allMatches(text)) {
      final s = m.start + m.group(0)!.indexOf(m.group(2)!);
      if (!free(s, m.end)) continue;
      final prefix = (m.group(1) ?? '').toLowerCase();
      final wd = _weekdays[m.group(2)!.substring(0, 3).toLowerCase()]!;
      final todayWd = DayKey.start(today).weekday;
      var back = (todayWd - wd) % 7;
      if (prefix == 'last' && back == 0) back = 7;
      out.add(
        DateMention(
          start: m.start,
          end: m.end,
          dates: [DayKey.add(today, -back)],
          kind: DateMentionKind.weekday,
          text: m.group(0)!,
          checkable: prefix == 'last',
        ),
      );
    }

    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  static String? _mismatch(String? weekdayToken, String key) {
    if (weekdayToken == null) return null;
    final stated = _weekdays[weekdayToken.substring(0, 3).toLowerCase()];
    final actual = DayKey.start(key).weekday;
    if (stated == null || stated == actual) return null;
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[actual - 1];
  }

  static String? _key(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final t = DateTime(y, m, d);
    if (t.month != m || t.day != d) return null;
    return DayKey.of(t);
  }

  /// Year of a "22 Sep" mention: the one that puts it nearest to today.
  static String? _infer(int month, int day, String today) {
    final t = DayKey.start(today);
    String? best;
    var bestDiff = 1 << 30;
    for (final y in [t.year - 1, t.year, t.year + 1]) {
      final k = _key(y, month, day);
      if (k == null) continue;
      final diff = DayKey.diff(today, k).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = k;
      }
    }
    return best;
  }
}
