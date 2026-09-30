// What an answer's cards may draw next to its cited numbers (AnswerVisual),
// read from THIS answer's own tool results after verification.
//
// Principle 6: nothing here is computed. Every number is the value of a
// SourceRef a tool returned for this answer (a day in a range, a night, the
// personal usual, the Health Monitor's usual range), found by walking the
// tool payloads. A number the tools did not return is never drawn, so most
// single-day answers get no trend and many get no card at all. Pure Dart.

import '../day_key.dart';
import 'coach_contracts.dart';
import 'tools.dart' show CoachTools;

abstract final class AnswerVisuals {
  /// Longest trend a card draws (days).
  static const maxPoints = 31;

  /// Most visuals one answer carries.
  static const maxVisuals = 3;

  /// Metrics a card may picture: the headline numbers. Everything else
  /// (clock times, counts, points, weights, targets) keeps its superscript
  /// only.
  static const headline = {
    'recovery',
    'hrv',
    'resting_hr',
    'respiratory_rate',
    'spo2',
    'skin_temp',
    'sleep_duration',
    'sleep_performance',
    'strain',
    'steps',
  };

  /// The visuals for the [shown] refs (the answer's cited refs, in order),
  /// from [results] (this attempt's tool results, the card seed included).
  static List<AnswerVisual> build(
    List<ToolResult> results,
    List<SourceRef> shown,
  ) {
    final w = _Walk();
    for (final r in results) {
      if (r.isError) continue;
      w.result(r.name, r.content);
    }
    final out = <AnswerVisual>[];
    final seen = <String>{};
    for (final ref in shown) {
      if (out.length >= maxVisuals) break;
      final f = w.byRef[ref.id];
      if (f == null || !f.role.headline || ref.value == null) continue;
      if (!headline.contains(f.metric) || !seen.add(f.metric)) continue;
      final m = f.metric;
      final vs = w.vs[(m, f.date)];
      out.add(
        AnswerVisual(
          refId: ref.id,
          metric: m,
          series: w.series[m] ?? const [],
          usual: w.usualFor(m, f.date),
          usualLow: w.low[m],
          usualHigh: w.high[m],
          vsUsualPct: vs,
          state: w.state[m],
        ),
      );
    }
    return out;
  }
}

enum _Role {
  value(true),
  mean(true),
  point(true),
  usual(false),
  other(false);

  const _Role(this.headline);
  final bool headline;
}

class _Fact {
  const _Fact(this.metric, this.role, this.date);
  final String metric;
  final _Role role;
  final String? date;
}

class _Walk {
  final byRef = <String, _Fact>{};
  final series = <String, List<SeriesPoint>>{};
  final usual = <String, Map<String?, double>>{};
  final low = <String, double>{};
  final high = <String, double>{};
  final state = <String, String>{};
  final vs = <(String, String?), double>{};

  double? usualFor(String metric, String? date) {
    final u = usual[metric];
    if (u == null || u.isEmpty) return null;
    return u[date] ?? u.values.first;
  }

  static String? _ref(Object? v) =>
      v is Map && v['ref'] is String && v['value'] is num
      ? v['ref'] as String
      : null;

  static double? _num(Object? v) =>
      v is Map && v['value'] is num ? (v['value'] as num).toDouble() : null;

  void _fact(Object? v, String metric, _Role role, String? date) {
    final id = _ref(v);
    if (id == null) return;
    byRef.putIfAbsent(id, () => _Fact(metric, role, date));
  }

  void _usual(Object? v, String metric, String? date) {
    final n = _num(v);
    if (n == null) return;
    _fact(v, metric, _Role.usual, date);
    (usual[metric] ??= {}).putIfAbsent(date, () => n);
  }

  static const _drivers = {
    'HRV': 'hrv',
    'Resting HR': 'resting_hr',
    'Sleep performance': 'sleep_performance',
    'Respiratory rate': 'respiratory_rate',
  };

  static const _vitals = {
    'HRV': 'hrv',
    'Resting HR': 'resting_hr',
    'Respiratory rate': 'respiratory_rate',
    'SpO₂': 'spo2',
    'Skin temp': 'skin_temp',
  };

  static const _nightly = {
    'hrv': 'hrv',
    'restingHr': 'resting_hr',
    'respiratoryRate': 'respiratory_rate',
    'spo2Avg': 'spo2',
    'skinTemp': 'skin_temp',
  };

  void result(String tool, Map<String, dynamic> c) {
    switch (tool) {
      case CoachTools.todaySummary || CoachTools.day:
        _day(c);
      case CoachTools.range:
        _range(c);
      case CoachTools.sleep:
        _sleep(c);
      case CoachTools.workouts:
        _workouts(c);
      case CoachTools.healthMonitor:
        _vitalsOf(c);
    }
  }

  void _day(Map<String, dynamic> c) {
    final d = c['date'] as String?;
    final rec = c['recovery'];
    if (rec is Map) {
      _fact(rec['score'], 'recovery', _Role.value, d);
      for (final dr in rec['drivers'] as List? ?? const []) {
        if (dr is! Map) continue;
        final m = _drivers[dr['input']];
        if (m == null) continue;
        _fact(dr['value'], m, _Role.value, d);
        _usual(dr['baseline'], m, d);
        final v = _num(dr['vsBaseline']);
        if (v != null) {
          _fact(dr['vsBaseline'], m, _Role.other, d);
          vs.putIfAbsent((m, d), () => v);
        }
      }
    }
    final sl = c['sleep'];
    if (sl is Map) {
      final sd = sl['date'] as String? ?? d;
      _fact(sl['asleep'], 'sleep_duration', _Role.value, sd);
      _fact(sl['performance'], 'sleep_performance', _Role.value, sd);
    }
    final st = c['strain'];
    if (st is Map) _fact(st['value'], 'strain', _Role.value, d);
    final n = c['nightly'];
    if (n is Map) {
      for (final e in _nightly.entries) {
        _fact(n[e.key], e.value, _Role.value, d);
      }
    }
    _fact(c['steps'], 'steps', _Role.value, d);
  }

  /// Every day of [from]..[to] (at most [AnswerVisuals.maxPoints], the
  /// latest ones), valued from [values]; no value = null, never zero.
  static List<SeriesPoint>? _days(
    String? from,
    String? to,
    Map<String, double> values,
  ) {
    if (from == null || to == null) return null;
    List<String> days;
    try {
      days = DayKey.range(from, to).toList();
    } catch (_) {
      return null;
    }
    if (days.length > AnswerVisuals.maxPoints) {
      days = days.sublist(days.length - AnswerVisuals.maxPoints);
    }
    return [for (final d in days) SeriesPoint(d, values[d])];
  }

  void _range(Map<String, dynamic> c) {
    final m = c['metric'] as String?;
    if (m == null) return;
    final values = <String, double>{};
    for (final e in c['daily'] as List? ?? const []) {
      if (e is! Map) continue;
      final d = e['date'] as String?;
      final v = _num(e[m]);
      if (d == null || v == null) continue;
      _fact(e[m], m, _Role.point, d);
      values[d] = v;
    }
    _fact(c['mean'], m, _Role.mean, null);
    final bl = c['baseline'];
    if (bl is Map) _usual(bl['mean'], m, bl['asOf'] as String?);
    if (values.isNotEmpty) {
      final s = _days(c['from'] as String?, c['to'] as String?, values);
      if (s != null) series.putIfAbsent(m, () => s);
    }
  }

  void _sleep(Map<String, dynamic> c) {
    final asleep = <String, double>{};
    final perf = <String, double>{};
    for (final n in c['nights'] as List? ?? const []) {
      if (n is! Map) continue;
      final d = n['date'] as String?;
      if (d == null) continue;
      _fact(n['asleep'], 'sleep_duration', _Role.point, d);
      _fact(n['performance'], 'sleep_performance', _Role.point, d);
      final a = _num(n['asleep']), p = _num(n['performance']);
      if (a != null) asleep[d] = a;
      if (p != null) perf[d] = p;
    }
    final av = c['average'];
    if (av is Map) {
      _fact(av['asleep'], 'sleep_duration', _Role.mean, null);
      _fact(av['performance'], 'sleep_performance', _Role.mean, null);
    }
    final from = c['from'] as String?, to = c['to'] as String?;
    if (asleep.length > 1) {
      final s = _days(from, to, asleep);
      if (s != null) series.putIfAbsent('sleep_duration', () => s);
    }
    if (perf.length > 1) {
      final s = _days(from, to, perf);
      if (s != null) series.putIfAbsent('sleep_performance', () => s);
    }
  }

  void _workouts(Map<String, dynamic> c) {
    final values = <String, double>{};
    for (final e in c['dailyStrain'] as List? ?? const []) {
      if (e is! Map) continue;
      final d = e['date'] as String?;
      final v = _num(e['strain']);
      if (d == null || v == null) continue;
      _fact(e['strain'], 'strain', _Role.point, d);
      values[d] = v;
    }
    if (values.length > 1) {
      final s = _days(c['from'] as String?, c['to'] as String?, values);
      if (s != null) series.putIfAbsent('strain', () => s);
    }
  }

  void _vitalsOf(Map<String, dynamic> c) {
    final d = c['date'] as String?;
    for (final e in c['metrics'] as List? ?? const []) {
      if (e is! Map) continue;
      final m = _vitals[e['metric']];
      if (m == null) continue;
      _fact(e['value'], m, _Role.value, d);
      _usual(e['baseline'], m, d);
      final lo = _num(e['rangeLow']), hi = _num(e['rangeHigh']);
      if (lo != null && hi != null && hi > lo) {
        _fact(e['rangeLow'], m, _Role.other, d);
        _fact(e['rangeHigh'], m, _Role.other, d);
        low.putIfAbsent(m, () => lo);
        high.putIfAbsent(m, () => hi);
        final st = e['state'];
        if (st is String) state.putIfAbsent(m, () => st);
      }
    }
  }
}
