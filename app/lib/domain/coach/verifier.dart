// Deterministic answer verifier (research/06 §B5.3, layer 3).
//
// Every number, date and event in an answer must be backed by THIS turn's
// tool results; anything else is "unsupported" and triggers one repair
// round, then the facts-table fallback (see CoachServiceImpl).
//
// Claims extracted:
//   * numbers with units (%, ms, bpm, breaths/min, °C, steps, points, km,
//     kcal), durations ("7h 12m", "7.2 h", "45 min"), clock times ("23:10",
//     "11 pm", "2 to 4 am"), counts ("5 nights", "3 workouts"), ranges
//     ("10–12") and bare numbers ("strain 12.4");
//   * absolute dates ("Tue 22 Sep", "22 Sep", "Sep 22", ISO), including a
//     weekday that doesn't match the date;
//   * events: workouts (run, swim, ride, walk, hike, strength, yoga, …),
//     "you slept / woke / went to bed", illness, life events (cruise, trip,
//     …) and "rest day".
// Acceptance:
//   * a number matches a SourceRef value of a compatible unit within the
//     rounding tolerance its text implies (more for "about"); when the claim
//     cites [rN], a cited ref of the same unit must match; when the sentence
//     names a metric ("recovery", "HRV", …) and refs of that metric exist,
//     it must match one of those; when the sentence names a date, a dated
//     ref must be on that date (so "0 steps on Sun 20 Sep" fails when that
//     day has no data, and a zero never matches "missing");
//   * a difference of two refs cited in the same sentence is accepted;
//   * numbers in the question, in memories and in methodology results are
//     accepted; list ordinals, [rN] markers and names such as SpO₂ / VO₂ max
//     / zone 2 are not claims;
//   * an event needs a matching workout / sleep / journal factor on the
//     referenced date; negated mentions ("no swim is recorded"), mentions
//     framed as the user's ("you asked about a swim") and advice ("a light
//     walk could help") are not claims. Life events must appear in the
//     question or memories.
// Pure Dart.

import 'dart:math' as math;

import '../day_key.dart';
import 'coach_contracts.dart';
import 'dates.dart';
import 'format.dart';
import 'quoted.dart';
import 'tools.dart';

enum ClaimKind { number, date, event }

class Claim {
  Claim(this.kind, this.text, this.start, this.end);
  final ClaimKind kind;
  final String text;
  final int start;
  final int end;
  bool supported = false;
  String? reason;

  String get describe => reason == null ? '"$text"' : '"$text" ($reason)';
}

class VerificationReport {
  const VerificationReport(this.verification, this.claims, this.citedRefIds);
  final Verification verification;
  final List<Claim> claims;

  /// Ref ids the answer cites that exist in this turn's results.
  final List<String> citedRefIds;

  bool get verified => verification.verified;
  List<String> get unsupported => verification.unsupported;
}

/// Everything this turn's tool results establish.
class Evidence {
  Evidence._();

  final Map<String, SourceRef> refsById = {};
  final List<SourceRef> refs = [];
  final Set<String> dates = {};
  final Set<String> noDataDates = {};
  final List<(String, String)> workouts = []; // (date, name)
  final Map<String, Set<String>> journal = {}; // date → factor labels
  final Set<int> windowDays = {};
  final List<double> counts = [];
  final List<double> constants = []; // methodology numbers
  final List<double> strings = []; // numbers inside result strings
  final Set<String> refDates = {};

  static const _countKeys = {
    'n',
    'nights',
    'days',
    'count',
    'daysInWindow',
    'workouts',
    'acuteDays',
    'chronicDays',
  };

  factory Evidence.from(List<ToolCall> calls, List<ToolResult> results) {
    final e = Evidence._();
    for (final c in calls) {
      final i = c.input;
      String? s(String k) => i[k] is String ? i[k] as String : null;
      for (final k in const [
        'date',
        'from',
        'to',
        'aFrom',
        'aTo',
        'bFrom',
        'bTo',
      ]) {
        final v = s(k);
        if (v != null && _iso.hasMatch(v)) e.dates.add(v);
      }
      for (final (f, t) in const [
        ('from', 'to'),
        ('aFrom', 'aTo'),
        ('bFrom', 'bTo'),
      ]) {
        final a = s(f), b = s(t);
        if (a != null && b != null && _iso.hasMatch(a) && _iso.hasMatch(b)) {
          try {
            e.windowDays.add(DayKey.diff(a, b).abs() + 1);
          } catch (_) {}
        }
      }
    }
    for (final r in results) {
      for (final ref in r.refs) {
        e.refsById[ref.id] = ref;
        e.refs.add(ref);
        if (ref.date != null) {
          e.dates.add(ref.date!);
          e.refDates.add(ref.date!);
        }
      }
      e._walk(r.content, null, r.name == CoachTools.methodology);
    }
    return e;
  }

  static final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _num = RegExp(r'(?<![\w.])\d+(?:\.\d+)?');

  void _walk(Object? v, String? key, bool methodology) {
    // Quoted free text (titles, memories, card text) is data from outside:
    // its numbers and dates are never evidence (research/06 §8, injection).
    if (QuotedText.isQuoted(v)) return;
    if (v is Map) {
      final name = QuotedText.unwrap(v['workout']), date = v['date'];
      if (name != null && date is String) workouts.add((date, name));
      final factors = v['factors'];
      if (factors is List && date is String) {
        (journal[date] ??= {}).addAll(factors.map((f) => '$f'.toLowerCase()));
      }
      for (final e in v.entries) {
        // "display" repeats the fact's own value as text ("5h 29m"): its
        // digits are not separate evidence.
        if (e.key == 'display') continue;
        _walk(e.value, '${e.key}', methodology);
      }
    } else if (v is List) {
      final isNoData = key == 'noDataDates' || key == 'notTrackedDates';
      for (final x in v) {
        if (isNoData && x is String) noDataDates.add(x);
        _walk(x, key, methodology);
      }
    } else if (v is String) {
      if (_iso.hasMatch(v)) {
        dates.add(v);
      } else {
        final into = methodology ? constants : strings;
        for (final m in _num.allMatches(v)) {
          into.add(double.parse(m.group(0)!));
        }
        into.addAll(TextNumbers.clockAndDurations(v));
      }
    } else if (v is num) {
      if (_countKeys.contains(key)) counts.add(v.toDouble());
    }
  }
}

/// A parsed numeric claim.
class _Num {
  _Num(
    this.claim,
    this.value,
    this.unit,
    this.tol, {
    this.hi,
    this.count = false,
  });
  final Claim claim;
  final double value;

  /// Canonical unit or null (bare number).
  final String? unit;
  final double tol;

  /// Upper bound of a range claim ("10–12").
  final double? hi;
  final bool count;
  bool approx = false;
  String? family;
  List<String> cited = const [];
  int sentence = 0;
}

class _Sentence {
  _Sentence(this.start, this.end);
  final int start;
  final int end;
  final Set<String> anchors = {};
  final Set<String> cited = {};
  bool lastNight = false;
}

abstract final class Verifier {
  static VerificationReport verify({
    required String answer,
    required String question,
    required String today,
    required List<ToolCall> calls,
    required List<ToolResult> results,
    List<String> memories = const [],
    bool repaired = false,
    int? nowMinutes,
  }) {
    final ev = Evidence.from(calls, results);
    final ctx = _Run(answer, question, today, ev, memories, nowMinutes);
    ctx.run();
    final unsupported = <String>[];
    for (final c in ctx.claims) {
      if (!c.supported && !unsupported.contains(c.describe)) {
        unsupported.add(c.describe);
      }
    }
    return VerificationReport(
      Verification(
        checkedNumbers: ctx.claims.length,
        unsupported: unsupported,
        repaired: repaired,
      ),
      ctx.claims,
      ctx.citedIds,
    );
  }

  /// Ref ids cited in [text] ("[r3]", "[r3, r4]").
  static List<String> citations(String text) => [
    for (final m in _Run._cite.allMatches(text))
      for (final id in RegExp(r'r?\d+').allMatches(m.group(1)!))
        id.group(0)!.startsWith('r') ? id.group(0)! : 'r${id.group(0)}',
  ];
}

class _Run {
  _Run(
    this.answer,
    this.question,
    this.today,
    this.ev,
    this.memories,
    this.nowMinutes,
  ) : lower = answer.toLowerCase();

  final String answer;
  final String lower;
  final String question;
  final String today;
  final Evidence ev;
  final List<String> memories;
  final int? nowMinutes;

  final List<Claim> claims = [];
  final List<String> citedIds = [];
  late final List<bool> _used = List<bool>.filled(answer.length, false);
  late String _masked;
  final List<_Sentence> _sentences = [];
  final List<(int, int, List<String>)> _citations = [];

  static final _cite = RegExp(
    r'[\[(]\s*(r\d+(?:\s*[,;]\s*r?\d+)*)\s*[\])]',
    caseSensitive: false,
  );

  // ── Setup ──────────────────────────────────────────────────────────────

  void run() {
    _mask();
    _splitSentences();
    _dates();
    _numbers();
    _events();
  }

  void _mask() {
    final b = answer.split('');
    void blank(int s, int e) {
      for (var i = s; i < e && i < b.length; i++) {
        if (b[i] != '\n') b[i] = ' ';
      }
    }

    for (final m in _cite.allMatches(answer)) {
      final ids = [
        for (final id in RegExp(
          r'r?\d+',
          caseSensitive: false,
        ).allMatches(m.group(1)!))
          id.group(0)!.toLowerCase().startsWith('r')
              ? id.group(0)!.toLowerCase()
              : 'r${id.group(0)}',
      ];
      _citations.add((m.start, m.end, ids));
      blank(m.start, m.end);
    }
    final names = RegExp(
      r'SpO[2₂]|VO[2₂](?:\s*max)?|\bzones?\s+[1-5](?:\s*(?:–|-|to|and)\s*[1-5])?'
      r'|COVID-19|\b[A-Za-z]+\d+[A-Za-z]*\b|\b(?:19|20)\d{2}\b(?![-:/])'
      r'|(?<!(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s)'
      r'\b\d+(?:st|nd|rd|th)\b(?!\s+(?:of\s+)?(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec))',
      caseSensitive: false,
    );
    final text = b.join();
    for (final m in names.allMatches(text)) {
      // Keep years inside dates ("22 Sep 2026", ISO) for the date parser.
      if (RegExp(r'^(19|20)\d{2}$').hasMatch(m.group(0)!)) {
        final before = text.substring(math.max(0, m.start - 12), m.start);
        if (RegExp(
          r'[a-z]{3}\.?,?\s*$',
          caseSensitive: false,
        ).hasMatch(before)) {
          continue;
        }
      }
      blank(m.start, m.end);
    }
    final ordinal = RegExp(
      r'^\s*(?:[-*•]\s*)?(\d{1,2})[.)]\s',
      multiLine: true,
    );
    for (final m in ordinal.allMatches(b.join())) {
      final s = m.start + m.group(0)!.indexOf(m.group(1)!);
      blank(s, s + m.group(1)!.length);
    }
    _masked = b.join();
  }

  void _splitSentences() {
    final end = RegExp(r'[.!?](?=\s|$)|\n');
    var s = 0;
    for (final m in end.allMatches(_masked)) {
      if (m.end > s) _sentences.add(_Sentence(s, m.end));
      s = m.end;
    }
    if (s < _masked.length) _sentences.add(_Sentence(s, _masked.length));
    if (_sentences.isEmpty) _sentences.add(_Sentence(0, _masked.length));
    for (final (st, _, ids) in _citations) {
      _sentenceAt(st).cited.addAll(ids);
      for (final id in ids) {
        if (ev.refsById.containsKey(id)) {
          if (!citedIds.contains(id)) citedIds.add(id);
        } else {
          final c = Claim(ClaimKind.number, '[$id]', st, st)
            ..reason = 'no such source in this answer\'s data';
          claims.add(c);
        }
      }
    }
  }

  _Sentence _sentenceAt(int pos) {
    for (final s in _sentences) {
      if (pos >= s.start && pos < s.end) return s;
    }
    return _sentences.last;
  }

  bool _free(int s, int e) {
    for (var i = s; i < e; i++) {
      if (_used[i]) return false;
    }
    return true;
  }

  void _use(int s, int e) {
    for (var i = s; i < e && i < _used.length; i++) {
      _used[i] = true;
    }
  }

  // ── Dates ──────────────────────────────────────────────────────────────

  late final Set<String> _okDates = {
    ...ev.dates,
    today,
    for (final m in DatePhrases.find(question, today)) ...m.dates,
    for (final t in memories)
      for (final m in DatePhrases.find(t, today)) ...m.dates,
  };

  void _dates() {
    for (final m in DatePhrases.find(_masked, today)) {
      final s = _sentenceAt(m.start);
      s.anchors.addAll(m.dates);
      if (m.text.toLowerCase().contains('last night')) s.lastNight = true;
      _use(m.start, m.end);
      if (m.kind != DateMentionKind.absolute) continue;
      final c = Claim(
        ClaimKind.date,
        answer.substring(m.start, m.end).trim(),
        m.start,
        m.end,
      );
      claims.add(c);
      if (m.weekdayMismatch != null) {
        c.reason =
            '${CoachFormat.day(m.dates.first)} is a '
            '${_weekdayName(m.weekdayMismatch!)}';
        continue;
      }
      final bad = [
        for (final d in m.dates)
          if (!_okDates.contains(d)) d,
      ];
      if (bad.isEmpty) {
        c.supported = true;
      } else {
        c.reason =
            'no data for ${bad.map(CoachFormat.day).join(', ')} '
            'in this answer\'s tool results';
      }
    }
  }

  static String _weekdayName(String short) => const {
    'Mon': 'Monday',
    'Tue': 'Tuesday',
    'Wed': 'Wednesday',
    'Thu': 'Thursday',
    'Fri': 'Friday',
    'Sat': 'Saturday',
    'Sun': 'Sunday',
  }[short]!;

  // ── Numbers ────────────────────────────────────────────────────────────

  static const _n = r'(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)';
  static const _dash = r'\s*(?:–|—|-|to)\s*';

  static final _clockRange = RegExp(
    '(?<![\\d.:])(\\d{1,2})(?::(\\d{2}))?$_dash(\\d{1,2})(?::(\\d{2}))?\\s*'
    r'(am|pm|a\.m\.|p\.m\.)(?![a-z])',
    caseSensitive: false,
  );
  static final _between = RegExp(
    r'between\s+(\d{1,2})(?::(\d{2}))?\s+and\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)',
    caseSensitive: false,
  );
  static final _clockAmPm = RegExp(
    r'(?<![\d.:])(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?![a-z])',
    caseSensitive: false,
  );
  static final _clock24 = RegExp(r'(?<![\d.:])(\d{1,2}):(\d{2})(?![\d:])');
  static final _noonMidnight = RegExp(
    r'\b(noon|midnight)\b',
    caseSensitive: false,
  );

  static final _hm = RegExp(
    '(?<![\\d.])(\\d+)\\s*(?:h|hr|hrs|hours?)\\s*(?:and\\s*)?(\\d+)\\s*'
    r'(?:m|min|mins|minutes?)(?![a-z])',
    caseSensitive: false,
  );
  static final _durRange = RegExp(
    '(?<![\\d.])$_n$_dash$_n\\s*(h|hr|hrs|hours?|m|min|mins|minutes?)(?![a-z])',
    caseSensitive: false,
  );
  static final _hours = RegExp(
    r'(?<![\d.,])(\d+(?:\.\d+)?)\s*-?\s*(?:h|hr|hrs|hours?)(?![a-z])',
    caseSensitive: false,
  );
  static final _mins = RegExp(
    r'(?<![\d.,])(\d+(?:\.\d+)?)\s*-?\s*(?:m|min|mins|minutes?)(?![a-z/])',
    caseSensitive: false,
  );

  static const _unitAlt =
      r'%|percent|per cent|ms|milliseconds?|bpm|beats per minute|'
      r'breaths?\s*(?:/|per)\s*min(?:ute)?|breaths|brpm|/min|°\s*c|°|degrees?|'
      r'k\s+steps|steps|kcal|calories|km|kilomet(?:er|re)s?|points?|pts|'
      r'percentage points|days?|nights?|weeks?|times|workouts?|sessions?|'
      r'runs|rides|entries|ml/kg/min';
  static final _unitRange = RegExp(
    '(?<![\\d.])$_n$_dash$_n\\s*($_unitAlt)(?![a-z])',
    caseSensitive: false,
  );
  static final _betweenNum = RegExp(
    'between\\s+$_n\\s+and\\s+$_n\\s*($_unitAlt)?(?![a-z])',
    caseSensitive: false,
  );
  static final _withUnit = RegExp(
    '(?<![\\d.])([-−+]?)$_n(k)?\\s*-?\\s*($_unitAlt)(?![a-z])',
    caseSensitive: false,
  );
  static final _bare = RegExp(
    r'(?<![\w.,])([-−+]?)(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)(?![\w%]|\.\d)',
  );
  static final _bareRange = RegExp(
    r'(?<![\w.,])(\d+(?:\.\d+)?)\s*(?:–|—|\bto\b)\s*(\d+(?:\.\d+)?)(?![\w%]|\.\d)',
  );

  static final _approx = RegExp(
    r'(about|around|roughly|approximately|approx\.?|nearly|almost|~|just over|'
    r'just under|over|under|more than|less than|at least|close to|some)\s*$',
    caseSensitive: false,
  );

  static int _decimals(String s) {
    final i = s.indexOf('.');
    return i < 0 ? 0 : s.length - i - 1;
  }

  static double _parse(String s) => double.parse(s.replaceAll(',', ''));

  static double _halfUnit(String s) => 0.5 * math.pow(10, -_decimals(s));

  final List<_Num> _nums = [];

  _Num _add(
    int s,
    int e,
    double v,
    String? unit,
    double tol, {
    double? hi,
    bool count = false,
  }) {
    final c = Claim(ClaimKind.number, answer.substring(s, e).trim(), s, e);
    claims.add(c);
    final n = _Num(c, v, unit, tol, hi: hi, count: count);
    final before = _masked.substring(math.max(0, s - 18), s);
    n.approx = _approx.hasMatch(before);
    _nums.add(n);
    _use(s, e);
    return n;
  }

  static double _clockMin(int h, int m, String? ampm) {
    var hh = h;
    if (ampm != null) {
      final pm = ampm.toLowerCase().startsWith('p');
      if (hh == 12) hh = 0;
      if (pm) hh += 12;
    }
    return (hh * 60 + m).toDouble();
  }

  void _numbers() {
    // Clock ranges first ("2 to 4 am", "between 2 and 4 am").
    for (final re in [_between, _clockRange]) {
      for (final m in re.allMatches(_masked)) {
        if (!_free(m.start, m.end)) continue;
        final ap = m.group(5)!;
        final h1 = int.parse(m.group(1)!), h2 = int.parse(m.group(3)!);
        if (h1 > 12 || h2 > 12) continue;
        final m1 = int.tryParse(m.group(2) ?? '') ?? 0;
        final m2 = int.tryParse(m.group(4) ?? '') ?? 0;
        // "11 to 1 am": the first time is on the other side of noon.
        var ap1 = ap;
        if (h1 > h2 && h1 != 12) {
          ap1 = ap.toLowerCase().startsWith('a') ? 'pm' : 'am';
        }
        final s2 = m.start + m.group(0)!.lastIndexOf(m.group(3)!);
        final a = _add(
          m.start,
          s2,
          _clockMin(h1, m1, ap1),
          'clock',
          m.group(2) == null ? 30 : 1,
        );
        final b = _add(
          s2,
          m.end,
          _clockMin(h2, m2, ap),
          'clock',
          m.group(4) == null ? 30 : 1,
        );
        _use(a.claim.start, b.claim.end);
      }
    }
    for (final m in _clockAmPm.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      final h = int.parse(m.group(1)!);
      if (h > 12) continue;
      final mm = int.tryParse(m.group(2) ?? '') ?? 0;
      _add(
        m.start,
        m.end,
        _clockMin(h, mm, m.group(3)),
        'clock',
        m.group(2) == null ? 30 : 1,
      );
    }
    for (final m in _clock24.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      final h = int.parse(m.group(1)!), mm = int.parse(m.group(2)!);
      if (h > 23 || mm > 59) continue;
      final before = _masked
          .substring(math.max(0, m.start - 14), m.start)
          .toLowerCase();
      if (RegExp(r'(slept|asleep|sleep of|duration|total|for)\s*$')
          .hasMatch(before)) {
        _add(m.start, m.end, (h * 60 + mm).toDouble(), 'min', 1);
      } else {
        _add(m.start, m.end, _clockMin(h, mm, null), 'clock', 1);
      }
    }
    for (final m in _noonMidnight.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      _add(
        m.start,
        m.end,
        m.group(1)!.toLowerCase() == 'noon' ? 720 : 0,
        'clock',
        5,
      );
    }

    // Durations.
    for (final m in _hm.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      _add(
        m.start,
        m.end,
        double.parse(m.group(1)!) * 60 + double.parse(m.group(2)!),
        'min',
        1,
      );
    }
    for (final m in _durRange.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      final f = m.group(3)!.toLowerCase().startsWith('h') ? 60.0 : 1.0;
      final lo = _parse(m.group(1)!) * f, hi = _parse(m.group(2)!) * f;
      _add(
        m.start,
        m.end,
        lo,
        'min',
        math.max(1, _halfUnit(m.group(1)!) * f),
        hi: hi,
      );
    }
    for (final m in _hours.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      final v = double.parse(m.group(1)!);
      _add(m.start, m.end, v * 60, 'min', _halfUnit(m.group(1)!) * 60);
    }
    for (final m in _mins.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      _add(m.start, m.end, double.parse(m.group(1)!), 'min', 1);
    }

    // Ranges with units, then single numbers with units, then bare ones.
    for (final re in [_betweenNum, _unitRange]) {
      for (final m in re.allMatches(_masked)) {
        if (!_free(m.start, m.end)) continue;
        final (unit, count, mult) = _unitOf(m.group(3));
        final lo = _parse(m.group(1)!) * mult, hi = _parse(m.group(2)!) * mult;
        _add(
          m.start,
          m.end,
          lo,
          unit,
          _halfUnit(m.group(1)!) * mult,
          hi: hi,
          count: count,
        );
      }
    }
    for (final m in _withUnit.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      final u = m.group(4)!;
      var (unit, count, mult) = _unitOf(u);
      var tol = _halfUnit(m.group(2)!) * mult;
      if (m.group(3) != null || u.toLowerCase().startsWith('k ')) {
        mult *= 1000;
        tol = math.max(tol * 1000, 50);
      }
      final sign = m.group(1) == '' || m.group(1) == '+' ? 1 : -1;
      _add(
        m.start,
        m.end,
        sign * _parse(m.group(2)!) * mult,
        unit,
        tol,
        count: count,
      );
    }
    for (final m in _bareRange.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      _add(
        m.start,
        m.end,
        _parse(m.group(1)!),
        null,
        _halfUnit(m.group(1)!),
        hi: _parse(m.group(2)!),
      );
    }
    for (final m in _bare.allMatches(_masked)) {
      if (!_free(m.start, m.end)) continue;
      final sign = m.group(1) == '' || m.group(1) == '+' ? 1 : -1;
      _add(
        m.start,
        m.end,
        sign * _parse(m.group(2)!),
        null,
        _halfUnit(m.group(2)!),
      );
    }

    _nums.sort((a, b) => a.claim.start.compareTo(b.claim.start));
    _assignContext();
    for (final n in _nums) {
      _check(n);
    }
  }

  /// (canonical unit, is a count, multiplier)
  static (String?, bool, double) _unitOf(String? u) {
    if (u == null) return (null, false, 1);
    final s = u.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (s == '%' || s.startsWith('percent') || s == 'per cent') {
      return ('%', false, 1);
    }
    if (s.startsWith('percentage point') ||
        s.startsWith('point') ||
        s == 'pts') {
      return ('pts', false, 1);
    }
    if (s == 'ms' || s.startsWith('millisecond')) return ('ms', false, 1);
    if (s == 'bpm' || s.startsWith('beats')) return ('bpm', false, 1);
    if (s.startsWith('breath') || s == 'brpm' || s == '/min') {
      return ('/min', false, 1);
    }
    if (s.startsWith('°') || s.startsWith('degree')) return ('°C', false, 1);
    if (s.contains('steps')) return ('steps', false, 1);
    if (s == 'kcal' || s == 'calories') return ('kcal', false, 1);
    if (s == 'km' || s.startsWith('kilomet')) return ('km', false, 1);
    if (s == 'ml/kg/min') return ('ml/kg/min', false, 1);
    if (s.startsWith('week')) return ('days', true, 7);
    if (s.startsWith('night')) return ('nights', true, 1);
    if (s.startsWith('day')) return ('days', true, 1);
    return ('count', true, 1);
  }

  // Metric words → family. Checked in the text before a number.
  static final List<(String, RegExp)> _families = [
    ('rhr', RegExp(r'resting (?:hr|heart rate|pulse)|\brhr\b')),
    ('hrv', RegExp(r'\bhrv\b|heart[- ]rate variability|\brmssd\b')),
    ('recovery', RegExp(r'\brecover(?:y|ies|ed)?\b')),
    ('strain', RegExp(r'\bstrain\b')),
    ('load', RegExp(r'\bacwr\b|training load|\bacute\b|\bchronic\b|\bratio\b')),
    (
      'sleep',
      RegExp(
        r'\bslept\b|\bsleep\b|\basleep\b|\bnaps?\b|\bnapped\b|\bbed(?:times?)?\b|'
        r'\bwoke\b|\bwake\b|\bdebt\b|\bneed\b|\bdeep\b|\brem\b|\befficiency\b|'
        r'\bconsistency\b',
      ),
    ),
    ('steps', RegExp(r'\bsteps?\b')),
    ('resp', RegExp(r'\brespiratory\b|breathing rate')),
    ('spo2', RegExp(r'spo[2₂]|\boxygen\b|\bsaturation\b')),
    ('skin', RegExp(r'skin temp|\btemperature\b')),
    (
      'journal',
      RegExp(
        r'\balcohol\b|\bcaffeine\b|\bjournal\b|\bstress\b|\blate meal\b|'
        r'\bscreens?\b|\bmeditation\b|\btravel\b|\bsick\b',
      ),
    ),
    (
      'workout',
      RegExp(
        r'\bworkouts?\b|\bruns?\b|\bran\b|\brides?\b|\bcycling\b|\bswim\b|'
        r'\bstrength\b|\bsession\b|\bwalk\b|\bhike\b',
      ),
    ),
    (
      'coverage',
      RegExp(
        r'no data|band (?:was )?off|charging|\bgap\b|not wearing|not worn|'
        r'missing|nothing recorded',
      ),
    ),
    ('hr', RegExp(r'\bheart rate\b|\bhr\b|\bpulse\b')),
  ];

  static Set<String> familiesOf(String label) {
    final l = label.toLowerCase();
    return {
      for (final (f, re) in _families)
        if (re.hasMatch(l)) f,
    };
  }

  late final Map<String, Set<String>> _refFam = {
    for (final r in ev.refs) r.id: familiesOf(r.label),
  };

  /// Last family keyword in [text] (longest match wins at equal ends).
  static String? _lastFamily(String text) {
    String? best;
    var bestEnd = -1;
    for (final (f, re) in _families) {
      for (final m in re.allMatches(text)) {
        if (m.end > bestEnd) {
          bestEnd = m.end;
          best = f;
        }
      }
    }
    return best;
  }

  static String? _firstFamily(String text) {
    String? best;
    var bestStart = 1 << 30;
    for (final (f, re) in _families) {
      final m = re.firstMatch(text);
      if (m != null && m.start < bestStart) {
        bestStart = m.start;
        best = f;
      }
    }
    return best;
  }

  void _assignContext() {
    // Citation groups: a citation covers every claim since the previous
    // citation in the same sentence.
    final cites = [..._citations]..sort((a, b) => a.$1.compareTo(b.$1));
    for (var si = 0; si < _sentences.length; si++) {
      final s = _sentences[si];
      final inS = [
        for (final n in _nums)
          if (n.claim.start >= s.start && n.claim.start < s.end) n,
      ];
      final cs = [
        for (final c in cites)
          if (c.$1 >= s.start && c.$1 < s.end) c,
      ];
      // Merge adjacent citations ("[r3][r4]").
      final merged = <(int, int, List<String>)>[];
      for (final c in cs) {
        if (merged.isNotEmpty &&
            answer.substring(merged.last.$2, c.$1).trim().isEmpty) {
          final l = merged.removeLast();
          merged.add((l.$1, c.$2, [...l.$3, ...c.$3]));
        } else {
          merged.add(c);
        }
      }
      var pending = <_Num>[];
      var ci = 0;
      String? prevFamily;
      var prevEnd = s.start;
      for (final n in inS) {
        while (ci < merged.length && merged[ci].$1 < n.claim.start) {
          for (final p in pending) {
            p.cited = merged[ci].$3;
          }
          pending = [];
          ci++;
        }
        pending.add(n);
        n.sentence = si;
        final seg = lower.substring(prevEnd, n.claim.start);
        var fam = _lastFamily(seg);
        if (fam == null) {
          final after = lower.substring(
            n.claim.end,
            math.min(s.end, n.claim.end + 28),
          );
          fam = _firstFamily(after);
        }
        n.family = fam ?? prevFamily;
        prevFamily = n.family;
        prevEnd = n.claim.end;
      }
      if (ci < merged.length) {
        for (final p in pending) {
          p.cited = merged[ci].$3;
        }
      }
    }
  }

  static bool _compatible(String? claimUnit, String? refUnit) {
    if (claimUnit == null) return refUnit != 'clock';
    if (claimUnit == refUnit) return true;
    const pctLike = {'%', 'pts'};
    if (pctLike.contains(claimUnit) && pctLike.contains(refUnit)) return true;
    if (claimUnit == 'steps' && refUnit == 'count') return true;
    return false;
  }

  double _tol(_Num n, double refValue) {
    var t = n.tol + 1e-9;
    if (n.approx) t = math.max(t, 0.05 * refValue.abs());
    if (n.unit == 'clock' && n.approx) t = math.max(t, 10);
    return t;
  }

  bool _close(_Num n, double ref) {
    final t = _tol(n, ref);
    if (n.hi != null) {
      final lo = math.min(n.value, n.hi!), hi = math.max(n.value, n.hi!);
      return ref >= lo - t && ref <= hi + t;
    }
    if (n.unit == 'clock') {
      final d = (n.value - ref).abs() % 1440;
      return math.min(d, 1440 - d) <= t;
    }
    return (n.value.abs() - ref.abs()).abs() <= t;
  }

  Set<String> _anchorsFor(_Num n) {
    final s = _sentences[n.sentence];
    if (s.anchors.isEmpty) return const {};
    final out = {...s.anchors};
    if (n.family == 'sleep') {
      for (final a in s.anchors) {
        out.add(DayKey.add(a, 1));
        out.add(DayKey.add(a, -1));
      }
    }
    if (s.lastNight) {
      for (final a in s.anchors) {
        out.add(DayKey.add(a, -1));
      }
    }
    return out;
  }

  bool _dateOk(SourceRef r, Set<String> anchors) =>
      anchors.isEmpty || r.date == null || anchors.contains(r.date);

  bool _matches(_Num n, SourceRef r, Set<String> anchors) {
    if (r.value == null || !_compatible(n.unit, r.unit)) return false;
    if (n.value == 0 && n.hi == null && r.value!.abs() > 1e-9) return false;
    return _close(n, r.value!) && _dateOk(r, anchors);
  }

  static List<double> _numbersIn(String t) => [
    for (final m in RegExp(r'\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?').allMatches(t))
      _parse(m.group(0)!),
    ...TextNumbers.clockAndDurations(t),
  ];

  late final List<double> _questionNumbers = _numbersIn(question);
  late final List<double> _memoryNumbers = [
    for (final t in memories) ..._numbersIn(t),
  ];

  /// Families a memory number may never support: memories hold goals and
  /// dates, never measurements (a planted "recovery 99%" memory must not
  /// ground a recovery claim).
  static const _measured = {
    'rhr',
    'hrv',
    'recovery',
    'strain',
    'load',
    'sleep',
    'steps',
    'resp',
    'spo2',
    'skin',
    'hr',
  };

  void _check(_Num n) {
    final c = n.claim;
    final anchors = _anchorsFor(n);

    bool inList(List<double> xs) => xs.any((k) => _close(n, k));

    // A question can contain a mistaken hypothesis, not a measurement.
    // Only an explicitly attributed/negated repetition can use that number
    // when the answer names a measured metric or cites measurement evidence.
    final before = _masked.substring(_sentences[n.sentence].start, c.start);
    final attributed = RegExp(
      r'(?:you (?:said|asked|reported|mentioned)|your (?:question|estimate)|not)\s*[^.!?;]{0,45}$',
      caseSensitive: false,
    ).hasMatch(before);
    final negated = RegExp(r'\bnot\s*$', caseSensitive: false).hasMatch(before);
    if ((inList(_questionNumbers) &&
            (negated ||
                (n.cited.isEmpty &&
                    (attributed || !_measured.contains(n.family))))) ||
        (!_measured.contains(n.family) && inList(_memoryNumbers))) {
      c.supported = true;
      return;
    }
    if (nowMinutes != null &&
        n.unit == 'clock' &&
        _close(n, nowMinutes!.toDouble())) {
      c.supported = true;
      return;
    }

    // Counts: windows, counted items, count refs.
    if (n.count) {
      final wins = [for (final w in ev.windowDays) w.toDouble()];
      final items = [
        ...ev.counts,
        ev.workouts.length.toDouble(),
        for (final r in ev.refs)
          if (const {'days', 'nights', 'count'}.contains(r.unit) &&
              r.value != null)
            r.value!,
      ];
      if (inList(wins) ||
          inList(items) ||
          inList(ev.strings) ||
          inList(ev.constants)) {
        c.supported = true;
      } else {
        c.reason = 'no matching count or window in the data';
      }
      return;
    }

    final cited = [
      for (final id in n.cited)
        if (ev.refsById[id] != null) ev.refsById[id]!,
    ];
    final sentenceCited = [
      for (final id in _sentences[n.sentence].cited)
        if (ev.refsById[id] != null) ev.refsById[id]!,
    ];

    bool derived(List<SourceRef> pool) {
      for (var i = 0; i < pool.length; i++) {
        for (var j = i + 1; j < pool.length; j++) {
          final a = pool[i], b = pool[j];
          if (a.value == null || b.value == null) continue;
          if (a.unit != b.unit || a.unit == 'clock') continue;
          if (!_compatible(n.unit, a.unit)) continue;
          if (_close(n, (a.value! - b.value!).abs())) return true;
        }
      }
      return false;
    }

    // 1. A cited ref of the same kind must match.
    if (cited.isNotEmpty) {
      if (cited.any((r) => _matches(n, r, anchors)) || derived(sentenceCited)) {
        c.supported = true;
        return;
      }
      final sameKind = cited.where((r) => _compatible(n.unit, r.unit));
      if (sameKind.isNotEmpty && n.unit != null) {
        c.reason =
            'doesn\'t match ${sameKind.map((r) => '[${r.id}] '
                '${CoachFormat.value(r.value ?? 0, r.unit)}').join(', ')}';
        return;
      }
    }

    // 2. The named metric's refs, when there are any of that kind.
    final pool = [
      for (final r in ev.refs)
        if (r.value != null && _compatible(n.unit, r.unit)) r,
    ];
    final fam = n.family;
    final famPool = fam == null
        ? const <SourceRef>[]
        : [
            for (final r in pool)
              if (_refFam[r.id]!.contains(fam)) r,
          ];
    final gated = famPool.isNotEmpty;
    final candidates = gated ? famPool : pool;
    if (candidates.any((r) => _matches(n, r, anchors)) ||
        derived(sentenceCited)) {
      c.supported = true;
      return;
    }

    // 3. Methodology constants; numbers in result text when no metric gate.
    // Numbers inside result text only back BARE numbers: "5 ms" never
    // matches a 5 that appears in some other string.
    if (inList(ev.constants) ||
        (!gated && n.unit == null && inList(ev.strings))) {
      c.supported = true;
      return;
    }

    final what = fam == null ? '' : ' for ${_familyName(fam)}';
    final on = anchors.isEmpty
        ? ''
        : ' on ${_sentences[n.sentence].anchors.map(CoachFormat.day).join(' / ')}';
    final noData = _sentences[n.sentence].anchors
        .where(ev.noDataDates.contains)
        .toList();
    c.reason = noData.isNotEmpty
        ? 'no data recorded on ${noData.map(CoachFormat.day).join(', ')}'
        : 'no matching value$what$on in the data';
  }

  static String _familyName(String f) => const {
    'rhr': 'resting HR',
    'hrv': 'HRV',
    'recovery': 'Recovery',
    'strain': 'strain',
    'load': 'training load',
    'sleep': 'sleep',
    'steps': 'steps',
    'resp': 'respiratory rate',
    'spo2': 'SpO₂',
    'skin': 'skin temperature',
    'journal': 'journal factors',
    'workout': 'workouts',
    'coverage': 'data coverage',
    'hr': 'heart rate',
  }[f]!;

  // ── Events ─────────────────────────────────────────────────────────────

  static final List<(String, RegExp, RegExp?)> _eventFamilies = [
    (
      'run',
      RegExp(r'\b(runs?|running|ran|jog|jogs|jogging|jogged)\b'),
      RegExp(r'run|jog|treadmill'),
    ),
    ('swim', RegExp(r'\b(swims?|swimming|swam)\b'), RegExp(r'swim')),
    (
      'ride',
      RegExp(
        r'\b(rides?|riding|rode|cycl(?:e|es|ed|ing)|bikes?|biked|biking)\b',
      ),
      RegExp(r'ride|cycl|bik'),
    ),
    ('walk', RegExp(r'\b(walks?|walking|walked)\b'), RegExp(r'walk')),
    ('hike', RegExp(r'\b(hikes?|hiking|hiked)\b'), RegExp(r'hik')),
    (
      'strength',
      RegExp(
        r'\b(strength (?:training|session|workout)s?|lifting|lifted|weights|'
        r'weight training|gym session)\b',
      ),
      RegExp(r'strength|weight|lift'),
    ),
    ('yoga', RegExp(r'\b(yoga|pilates)\b'), RegExp(r'yoga|pilates')),
    ('row', RegExp(r'\b(rowing|rowed)\b'), RegExp(r'row')),
    (
      'sport',
      RegExp(
        r'\b(tennis|football|soccer|basketball|golf|padel|squash|climbing)\b',
      ),
      null,
    ),
    (
      'workout',
      RegExp(r'\b(workouts?|training sessions?|exercise sessions?)\b'),
      RegExp(r'.'),
    ),
  ];

  static final _pastVerb = RegExp(
    r'\b(ran|swam|rode|cycled|biked|walked|hiked|lifted|jogged|rowed)\b',
  );
  static final _illness = RegExp(
    r'\b(sick|ill|illness|fever|flu|a cold|caught a cold|infection|covid)\b',
  );
  static final _life = RegExp(
    r'\b(cruise|vacation|holiday|trip|travell?ed|travell?ing|flight|flew|'
    r'jet lag|moved house|moving house|house move|new job|wedding|party|'
    r'festival|concert|marathon|race|surgery|injury|injured|pregnan\w*)\b',
  );
  static final _sleepEvent = RegExp(
    r'\byou (slept|fell asleep|went to bed|woke(?: up)?|napped|were asleep|'
    r'got up)\b',
  );
  static final _restDay = RegExp(r'\b(rest day|day off|full recovery day)\b');

  static final _idioms = RegExp(
    r'in the long run|run (?:the|your|through)|walk (?:you|me) through|'
    r'walk through|strength of|in a row|runs? (?:low|high|out|hot)|'
    r'ran (?:low|out)|walking bursts|on the run|trip up|over the long run|'
    r'runs? (?:about|around|at|between|higher|lower|above|below|close)',
  );
  static final _negation = RegExp(
    r"\b(no|not|never|without|don't|didn't|doesn't|isn't|wasn't|aren't|"
    r"weren't|haven't|hasn't|hadn't|can't|cannot|couldn't|nothing|none|"
    r"neither|nor|zero)\b|n't\b",
  );
  static final _negAfter = RegExp(
    r"^\W*\w*\W*(isn't|wasn't|aren't|weren't|is not|was not|not)\b",
  );
  static final _userFrame = RegExp(
    r"\byou(?:'ve| have)? (?:mentioned|said|asked|asked about|are asking|"
    r"'re asking|are planning|'re planning|plan|planned|want|wanted|told me)\b|"
    r"\byour question\b|\byou're thinking\b",
  );

  /// A conditional clause ("if you run…") is never a claim.
  static final _ifClause = RegExp(r"\b(if|unless|whenever|when you)\b");

  /// Advice words just before the noun ("try an easy run", "could go for a
  /// walk", "consider a light walk").
  static final _hypoNear = RegExp(
    r"\b(would|could|might|may|should|can|try|consider|aim|plan|planning|"
    r"maybe|perhaps|recommend|suggest|go|keep|avoid|skip|such|e\.g\.|"
    r"options?|instead|swap|choose|pick|add|include|schedule|save)\b",
  );
  static final _hypoAfter = RegExp(
    r"^\W*(\w+\W+){0,2}(would|could|might|may|can|should|helps?|tends?)\b",
  );

  void _events() {
    final qLower = question.toLowerCase();
    final memLower = memories.map((m) => m.toLowerCase()).join(' | ');
    for (final s in _sentences) {
      final text = lower.substring(s.start, s.end);
      final idiomSpans = [
        for (final m in _idioms.allMatches(text)) (m.start, m.end),
      ];
      bool inIdiom(int a) => idiomSpans.any((sp) => a >= sp.$1 && a < sp.$2);
      bool quoted(int a) {
        final before = text.substring(0, a);
        return '"'.allMatches(before).length.isOdd ||
            '“'.allMatches(before).length > '”'.allMatches(before).length;
      }

      String clauseBefore(int a) {
        final b = text.substring(0, a);
        final cut = b.lastIndexOf(RegExp(r'[,;:—–(]|\bbut\b|\bso\b'));
        return cut < 0 ? b : b.substring(cut + 1);
      }

      List<String> wordsBefore(int a, int n) {
        final w = RegExp(r"[a-z']+")
            .allMatches(clauseBefore(a))
            .map((m) => m.group(0)!)
            .toList();
        return w.length <= n ? w : w.sublist(w.length - n);
      }

      bool negated(int a, int e) {
        final before = wordsBefore(a, 6).join(' ');
        if (_negation.hasMatch(before)) return true;
        return _negAfter.hasMatch(text.substring(e));
      }

      bool userFramed(int a) => _userFrame.hasMatch(text.substring(0, a));

      final anchors = s.anchors;
      final hasAnchor = anchors.isNotEmpty;

      void claim(int a, int e, bool Function() ok, String why) {
        final c = Claim(
          ClaimKind.event,
          answer.substring(s.start + a, s.start + e).trim(),
          s.start + a,
          s.start + e,
        );
        claims.add(c);
        if (ok()) {
          c.supported = true;
        } else {
          c.reason = why;
        }
      }

      // Workouts.
      for (final (fam, re, nameRe) in _eventFamilies) {
        for (final m in re.allMatches(text)) {
          final a = m.start, e = m.end;
          if (inIdiom(a) || quoted(a) || negated(a, e) || userFramed(a)) {
            continue;
          }
          final past = _pastVerb.hasMatch(m.group(0)!);
          final before3 = wordsBefore(a, 3);
          final possessive = before3.any(
            (w) => w == 'your' || w == 'you' || w == "you've" || w == "you'd",
          );
          if (_ifClause.hasMatch(clauseBefore(a))) continue;
          final hypoNear = _hypoNear.hasMatch(wordsBefore(a, 4).join(' '));
          final hypoAfter = _hypoAfter.hasMatch(text.substring(e));
          final isClaim =
              past || possessive || (hasAnchor && !hypoNear && !hypoAfter);
          if (!isClaim) continue;
          final label = m.group(0)!;
          claim(
            a,
            e,
            () {
              final days = _eventDays(s);
              return ev.workouts.any((w) {
                final n = w.$2.toLowerCase();
                final nameOk = nameRe == null
                    ? n.contains(label)
                    : nameRe.hasMatch(n);
                return nameOk && (days.isEmpty || days.contains(w.$1));
              });
            },
            hasAnchor
                ? 'no $label recorded on ${anchors.map(CoachFormat.day).join(' / ')}'
                : 'no $label in the recorded workouts',
          );
          if (fam == 'workout') break;
        }
      }

      // "You slept / woke / went to bed".
      for (final m in _sleepEvent.allMatches(text)) {
        if (negated(m.start, m.end)) continue;
        claim(m.start, m.end, () {
          final sleepRefs = ev.refs.where(
            (r) => r.date != null && _refFam[r.id]!.contains('sleep'),
          );
          if (!hasAnchor) return sleepRefs.isNotEmpty;
          final days = {
            for (final a in anchors) ...[a, DayKey.add(a, 1)],
          };
          return sleepRefs.any((r) => days.contains(r.date));
        }, 'no sleep recorded for that night');
      }

      // Illness.
      for (final m in _illness.allMatches(text)) {
        final a = m.start, e = m.end;
        if (negated(a, e) || userFramed(a) || quoted(a)) continue;
        final before3 = wordsBefore(a, 4);
        final personal = before3.any(
          (w) => const {
            'you',
            'your',
            "you're",
            'were',
            'got',
            'been',
            'felt',
          }.contains(w),
        );
        if (!personal || _ifClause.hasMatch(clauseBefore(a))) continue;
        claim(a, e, () {
          if (_illness.hasMatch(qLower) || _illness.hasMatch(memLower)) {
            return true;
          }
          final days = hasAnchor
              ? {
                  for (final d in anchors)
                    for (var k = -1; k <= 1; k++) DayKey.add(d, k),
                }
              : null;
          return ev.journal.entries.any(
            (j) =>
                (days == null || days.contains(j.key)) &&
                j.value.any((f) => f.contains('sick')),
          );
        }, 'no illness logged in the journal or mentioned by you');
      }

      // Life events: only if the user brought them up.
      for (final m in _life.allMatches(text)) {
        final a = m.start, e = m.end;
        if (negated(a, e) || quoted(a)) continue;
        final word = m.group(0)!;
        claim(a, e, () {
          final stem = word.length > 5 ? word.substring(0, 5) : word;
          if (qLower.contains(stem) || memLower.contains(stem)) return true;
          if (RegExp(r'trip|travel|flight|flew|jet lag').hasMatch(word)) {
            return ev.journal.values.any((f) => f.contains('travel'));
          }
          return false;
        }, 'you didn\'t mention it and it isn\'t in your data');
      }

      // "Rest day": only on a day that was actually tracked.
      for (final m in _restDay.allMatches(text)) {
        final a = m.start, e = m.end;
        if (!hasAnchor ||
            negated(a, e) ||
            _ifClause.hasMatch(clauseBefore(a)) ||
            _hypoNear.hasMatch(wordsBefore(a, 4).join(' '))) {
          continue;
        }
        claim(
          a,
          e,
          () => anchors.every(
            (d) => !ev.noDataDates.contains(d) && ev.refDates.contains(d),
          ),
          'that day has no data: the band wasn\'t worn, it wasn\'t rest',
        );
      }
    }
  }

  /// Days a workout mention can refer to: the anchors, plus the evening
  /// before for "last night".
  Set<String> _eventDays(_Sentence s) {
    if (s.anchors.isEmpty) return const {};
    if (s.anchors.length >= 2) {
      final sorted = s.anchors.toList()..sort();
      if (DayKey.diff(sorted.first, sorted.last) <= 92) {
        return DayKey.range(sorted.first, sorted.last).toSet();
      }
    }
    return {
      ...s.anchors,
      if (s.lastNight)
        for (final a in s.anchors) DayKey.add(a, -1),
    };
  }
}

/// Clock times and durations in free text, in the verifier's canonical
/// units (minutes since midnight / minutes), so "5 am" in a question or
/// "3h" in a methodology text supports the same claim in an answer.
abstract final class TextNumbers {
  static final _ampm = RegExp(
    r'(?<![\d.:])(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)(?![a-z])',
    caseSensitive: false,
  );
  static final _range = RegExp(
    r'(?<![\d.:])(\d{1,2})(?::(\d{2}))?\s*(?:–|-|to|and)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?![a-z])',
    caseSensitive: false,
  );
  static final _h24 = RegExp(r'(?<![\d.:])(\d{1,2}):(\d{2})(?![\d:])');
  static final _hm = RegExp(
    r'(\d+)\s*h(?:ours?|rs?)?\s*(\d+)\s*m(?:in(?:utes?)?)?',
    caseSensitive: false,
  );
  static final _h = RegExp(
    r'(?<![\d.])(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?)(?![a-z])',
    caseSensitive: false,
  );

  static List<double> clockAndDurations(String text) {
    final out = <double>[];
    double clock(int h, int m, String? ap) {
      var hh = h;
      if (ap != null) {
        if (hh == 12) hh = 0;
        if (ap.toLowerCase() == 'pm') hh += 12;
      }
      return (hh * 60 + m).toDouble();
    }

    for (final m in _range.allMatches(text)) {
      final h1 = int.parse(m.group(1)!), h2 = int.parse(m.group(3)!);
      final ap = m.group(5)!;
      var ap1 = ap;
      if (h1 > h2 && h1 != 12) ap1 = ap.toLowerCase() == 'am' ? 'pm' : 'am';
      out
        ..add(clock(h1, int.tryParse(m.group(2) ?? '') ?? 0, ap1))
        ..add(clock(h2, int.tryParse(m.group(4) ?? '') ?? 0, ap));
    }
    for (final m in _ampm.allMatches(text)) {
      out.add(
        clock(
          int.parse(m.group(1)!),
          int.tryParse(m.group(2) ?? '') ?? 0,
          m.group(3),
        ),
      );
    }
    for (final m in _h24.allMatches(text)) {
      final h = int.parse(m.group(1)!), mm = int.parse(m.group(2)!);
      if (h < 24 && mm < 60) out.add((h * 60 + mm).toDouble());
    }
    for (final m in _hm.allMatches(text)) {
      out.add(double.parse(m.group(1)!) * 60 + double.parse(m.group(2)!));
    }
    for (final m in _h.allMatches(text)) {
      out.add(double.parse(m.group(1)!) * 60);
    }
    return out;
  }
}
