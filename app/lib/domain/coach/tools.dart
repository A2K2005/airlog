// The coach's read-only tools: provider-neutral specs (JSON Schema, strict-
// compatible: every object has additionalProperties:false and `required`)
// and the executor that runs them over HealthRepository + CoachRepository.
//
// Rules every tool follows (research/06 §B5):
//   * compact payloads: daily values, never raw per-minute samples;
//   * every numeric fact is a SourceRef ({"value", "unit", "ref"}), rounded
//     to the precision the UI shows;
//   * MISSING IS NOT ZERO: absent values are listed as missing with the
//     reason, never emitted as 0 (SleepAnalysis.hasData == false and
//     StrainMethod.none carry zeros in the engine output; they are dropped);
//   * date windows are capped at 90 days and never extend past today;
//   * privacy: for a cloud provider, any metric whose provenance is the
//     Google Health API, and every score derived from one, is withheld and
//     the payload says so (Google Health API policy: no transfer off the
//     device without CASA; research/06 §B7.2).
// Pure Dart.

import 'dart:math' as math;

import '../day_key.dart';
import '../engine/engine.dart';
import '../engine/stats.dart';
import '../models.dart';
import '../repositories.dart';
import '../results.dart';
import 'coach_contracts.dart';
import 'format.dart';
import 'methodology.dart';
import 'quoted.dart';
import 'refs.dart';

/// Metrics `get_range` / `compare_periods` accept.
enum RangeMetric {
  recovery('recovery', 'Recovery', '%', 0, CoachRoutes.recovery),
  strain('strain', 'Strain', 'strain', 1, CoachRoutes.strain),
  hrv('hrv', 'HRV', 'ms', 0, CoachRoutes.trends),
  restingHr('resting_hr', 'Resting HR', 'bpm', 0, CoachRoutes.trends),
  respiratoryRate(
    'respiratory_rate',
    'Respiratory rate',
    '/min',
    1,
    CoachRoutes.trends,
  ),
  spo2('spo2', 'SpO₂', '%', 1, CoachRoutes.trends),
  skinTemp('skin_temp', 'Skin temperature', '°C', 1, CoachRoutes.trends),
  sleepDuration('sleep_duration', 'Sleep', 'min', 0, CoachRoutes.sleep),
  sleepPerformance(
    'sleep_performance',
    'Sleep performance',
    '%',
    0,
    CoachRoutes.sleep,
  ),
  sleepDebt('sleep_debt', 'Sleep debt', 'min', 0, CoachRoutes.sleep),
  sleepConsistency(
    'sleep_consistency',
    'Sleep consistency',
    '%',
    0,
    CoachRoutes.sleep,
  ),
  steps('steps', 'Steps', 'steps', 0, CoachRoutes.trends);

  const RangeMetric(
    this.wire,
    this.label,
    this.unit,
    this.decimals,
    this.route,
  );
  final String wire;
  final String label;
  final String unit;
  final int decimals;
  final String route;

  static RangeMetric? fromWire(String s) {
    for (final m in values) {
      if (m.wire == s) return m;
    }
    return null;
  }
}

/// Tool names and specs.
abstract final class CoachTools {
  static const todaySummary = 'get_today_summary';
  static const day = 'get_day';
  static const range = 'get_range';
  static const compare = 'compare_periods';
  static const sleep = 'get_sleep';
  static const workouts = 'get_workouts';
  static const healthMonitor = 'get_health_monitor';
  static const trainingLoad = 'get_training_load';
  static const journalInsights = 'get_journal_insights';
  static const coverage = 'get_data_coverage';
  static const methodology = 'get_methodology';
  static const memories = 'get_memories';
  static const proposeMemory = 'propose_memory';

  /// The insight card a chat was opened from ("Discuss"). Never offered to
  /// the model: the service runs it once and attaches the result to the
  /// question's user message (LlmUser.data, "Card context"), not as a
  /// synthetic tool call. The name tags that result (verifier, offline
  /// client, CoachPrompts.userData).
  static const insightCard = 'get_insight_card';

  /// Longest window any tool reads.
  static const int maxWindowDays = 90;

  static Map<String, dynamic> _obj(
    Map<String, dynamic> props, [
    List<String>? required,
  ]) => {
    'type': 'object',
    'properties': props,
    'required': required ?? props.keys.toList(),
    'additionalProperties': false,
  };

  static Map<String, dynamic> _date(String what) => {
    'type': 'string',
    'description': '$what: local calendar date, yyyy-MM-dd.',
  };

  static final Map<String, dynamic> _metric = {
    'type': 'string',
    'enum': [for (final m in RangeMetric.values) m.wire],
    'description': 'Which daily metric.',
  };

  static final List<CoachToolSpec> all = [
    CoachToolSpec(
      name: todaySummary,
      description:
          'Today\'s Recovery (with what drove it), last night\'s sleep, strain '
          'so far and the strain target, workouts, Health Monitor state and '
          'missing-data notes. Call this first for any question about today, '
          'this morning or last night.',
      inputSchema: _obj({}),
    ),
    CoachToolSpec(
      name: day,
      description:
          'Everything recorded and scored for one past day: Recovery and its '
          'components, sleep (the night that ended that morning), strain, '
          'workouts, nightly metrics, Health Monitor, journal factors from '
          'the evening before, wear gaps and missing-data notes. Call this '
          'when the user asks about a specific date.',
      inputSchema: _obj({'date': _date('The day')}),
    ),
    CoachToolSpec(
      name: range,
      description:
          'Daily values of one metric over a window (max 90 days): mean, '
          'min and max with their dates, days with and without data, the '
          'significance-tested trend and the personal baseline. Call this '
          'for "over the last N days", "lately" and trend questions.',
      inputSchema: _obj({
        'metric': _metric,
        'from': _date('First day'),
        'to': _date('Last day'),
      }),
    ),
    CoachToolSpec(
      name: compare,
      description:
          'Compares one metric between two windows (e.g. this week vs last '
          'week): both means, the difference and whether it is statistically '
          'meaningful. Call this for any "compared with", "vs" or "better '
          'than before" question.',
      inputSchema: _obj({
        'metric': _metric,
        'aFrom': _date('Period A first day'),
        'aTo': _date('Period A last day'),
        'bFrom': _date('Period B first day'),
        'bTo': _date('Period B last day'),
      }),
    ),
    CoachToolSpec(
      name: sleep,
      description:
          'Sleep per night (asleep, performance vs need, bed and wake times, '
          'stages, debt, consistency) and averages over a window of wake '
          'days (max 90). Nights without sleep data are listed, never '
          'counted as zero. Call this for sleep questions.',
      inputSchema: _obj({
        'from': _date('First wake day'),
        'to': _date('Last wake day'),
      }),
    ),
    CoachToolSpec(
      name: workouts,
      description:
          'Recorded workouts (type as recorded, start, duration, average HR, '
          'strain) and daily strain over a window (max 90 days), plus days '
          'the band recorded nothing. Only these workouts happened: call '
          'this before mentioning any run, ride, swim, walk or session.',
      inputSchema: _obj({'from': _date('First day'), 'to': _date('Last day')}),
    ),
    CoachToolSpec(
      name: healthMonitor,
      description:
          'Overnight Health Monitor for one day: resting HR, HRV, '
          'respiratory rate, SpO₂ and skin temperature against the personal '
          'range, and whether an alert is raised. Call this for "am I getting '
          'sick", "is anything off" or alert questions. Not a diagnosis.',
      inputSchema: _obj({'date': _date('The day')}),
    ),
    CoachToolSpec(
      name: trainingLoad,
      description:
          'Acute (7-day) vs chronic (28-day) strain and their ratio, plus '
          'that day\'s strain target and Recovery. Call this for "how hard '
          'should I train", strain target and overtraining questions.',
      inputSchema: _obj({'date': _date('The day')}),
    ),
    CoachToolSpec(
      name: journalInsights,
      description:
          'How journal factors (alcohol, late caffeine, stress, travel, '
          'feeling sick, …) are associated with next-day Recovery, with '
          'sample sizes and confidence, plus the last 14 days of journal '
          'entries. Call this for "does X affect my recovery" questions.',
      inputSchema: _obj({}),
    ),
    CoachToolSpec(
      name: coverage,
      description:
          'Which data exists for each day of a window (max 90 days), which '
          'is missing, wear gaps (band off or charging, 60 min or longer) '
          'and each metric\'s source. Call this whenever data may be missing '
          'or a question is about specific hours, so a gap is never treated '
          'as sleep, rest or zero.',
      inputSchema: _obj({'from': _date('First day'), 'to': _date('Last day')}),
    ),
    CoachToolSpec(
      name: methodology,
      description:
          'How Airlog computes a score or what a metric means (general '
          'science, no personal data). Call this for "what is", "what does '
          'X mean" and "how is X calculated" questions, and before quoting '
          'any general fact or threshold.',
      inputSchema: _obj({
        'topic': {
          'type': 'string',
          'enum': [for (final t in MethodologyTopic.values) t.wire],
          'description': 'The topic.',
        },
      }),
      readsUserData: false,
    ),
    CoachToolSpec(
      name: memories,
      description:
          'Facts the user asked the coach to remember (goals, events, '
          'preferences). User-stated context, not measurements. Call this '
          'when the answer may depend on the user\'s goals or plans.',
      inputSchema: _obj({}),
    ),
    CoachToolSpec(
      name: proposeMemory,
      description:
          'Suggests saving a lasting fact the user stated (a goal, an event '
          'date, a preference). It saves NOTHING: the app asks the user '
          '"Remember this?". Never propose health measurements.',
      inputSchema: _obj(
        {
          'text': {
            'type': 'string',
            'description': 'The fact in the user\'s words, one sentence.',
          },
          'category': {
            'type': 'string',
            'enum': [for (final c in MemoryCategory.values) c.name],
            'description': 'Memory category.',
          },
          'expiresOn': _date(
            'Optional. When a temporary fact stops applying (event date, '
            'end of an illness)',
          ),
        },
        ['text', 'category'],
      ),
    ),
  ];

  /// Spec of the card seed, for [CoachToolbox.run] only (never offered).
  static final CoachToolSpec insightCardSpec = CoachToolSpec(
    name: insightCard,
    description:
        'The insight card the user opened this chat from: its text (quoted '
        'data) and its own facts with ref ids.',
    inputSchema: _obj({}),
  );

  static final Set<String> userDataTools = {
    for (final t in [...all, insightCardSpec])
      if (t.readsUserData) t.name,
  };

  /// The spec named [name] (including the synthetic card tool), or null.
  static CoachToolSpec? spec(String name) {
    if (name == insightCard) return insightCardSpec;
    for (final t in all) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// The specs offered for [mode]. General-only offers no data tool. The
  /// insight card is never offered (see [insightCard]).
  static List<CoachToolSpec> forMode(CoachMode mode, {required bool memory}) {
    if (mode == CoachMode.generalOnly) {
      return [
        for (final t in all)
          if (!t.readsUserData) t,
      ];
    }
    return [
      for (final t in all)
        if (memory || (t.name != memories && t.name != proposeMemory)) t,
    ];
  }
}

class ToolError implements Exception {
  const ToolError(this.message);
  final String message;
}

/// A memory the model proposed (pending the user's "Remember this?").
class MemoryProposal {
  const MemoryProposal(this.text, this.category, this.expiresOn);
  final String text;
  final MemoryCategory category;
  final String? expiresOn;
}

/// Runs tool calls for ONE ask. Holds the turn-wide ref counter, the human
/// data-type list for SentPayload and the memory proposals.
class CoachToolbox {
  CoachToolbox({
    required this.health,
    required this.coach,
    required this.now,
    required this.cloud,
    required this.mode,
    this.memoryEnabled = true,
    this.seed,
    this.question,
  }) : today = DayKey.of(now);

  final HealthRepository health;
  final CoachRepository coach;
  final DateTime now;
  final String today;

  /// True when results leave the phone (Claude / Gemini).
  final bool cloud;
  final CoachMode mode;
  final bool memoryEnabled;

  /// The insight card this ask was opened from (get_insight_card).
  final AskContext? seed;

  /// The user's question (sensitive memory proposals must be user-stated).
  final String? question;

  int _refCount = 0;
  final List<String> dataTypes = [];
  final List<MemoryProposal> proposals = [];

  /// Executes [calls] concurrently; results come back in call order with
  /// turn-wide ref ids.
  Future<List<ToolResult>> run(List<ToolCall> calls) async {
    final raw = await Future.wait([for (final c in calls) _one(c)]);
    final out = <ToolResult>[];
    for (var i = 0; i < calls.length; i++) {
      final (content, refs, isError) = raw[i];
      final (c2, r2) = RefSink.renumber(content, refs, _refCount);
      _refCount += refs.length;
      out.add(
        ToolResult(
          callId: calls[i].id,
          name: calls[i].name,
          content: c2,
          refs: r2,
          isError: isError,
        ),
      );
    }
    return out;
  }

  Future<(Map<String, dynamic>, List<SourceRef>, bool)> _one(
    ToolCall call,
  ) async {
    final sink = RefSink();
    try {
      final spec = CoachTools.spec(call.name);
      if (spec == null ||
          (call.name == CoachTools.insightCard && seed == null)) {
        throw ToolError('Unknown tool "${call.name}".');
      }
      if (mode == CoachMode.generalOnly &&
          CoachTools.userDataTools.contains(call.name)) {
        throw const ToolError(
          'General-only mode: this tool reads personal data and is off.',
        );
      }
      validateArgs(spec, call.input);
      final ctx = _Ctx(sink, cloud);
      final content = await _dispatch(call, ctx);
      if (QuotedText.containsQuoted(content)) {
        content[QuotedText.noticeKey] = QuotedText.notice;
      }
      if (ctx.withheld.isNotEmpty) {
        content['privacy'] = {
          'withheld': [
            for (final e in ctx.withheld.entries)
              '${e.key} (${e.value} day${e.value == 1 ? '' : 's'})',
          ],
          'why':
              'These values come from the Google Health API, which cloud AI '
              'may not receive. They stay on the phone; tell the user they '
              'are only available in the app itself.',
        };
      }
      return (content, sink.refs, false);
    } on ToolError catch (e) {
      return (<String, dynamic>{'error': e.message}, const <SourceRef>[], true);
    }
  }

  Future<Map<String, dynamic>> _dispatch(ToolCall c, _Ctx x) async {
    final i = c.input;
    switch (c.name) {
      case CoachTools.todaySummary:
        dataTypes.add('Today\'s scores (1 day)');
        return _todaySummary(x);
      case CoachTools.day:
        final d = _pastDate(i, 'date');
        dataTypes.add('Day summary (${CoachFormat.day(d)})');
        final b = await health.day(d);
        if (b == null) return _noDay(d, x);
        return _dayPayload(b, x, detailed: true);
      case CoachTools.range:
        final m = _metricOf(i);
        final w = _window(i, 'from', 'to');
        dataTypes.add('${m.label} (${w.days} days)');
        return _range(m, w, x);
      case CoachTools.compare:
        final m = _metricOf(i);
        final a = _window(i, 'aFrom', 'aTo');
        final b = _window(i, 'bFrom', 'bTo');
        dataTypes.add('${m.label} (${a.days + b.days} days)');
        return _compare(m, a, b, x);
      case CoachTools.sleep:
        final w = _window(i, 'from', 'to');
        dataTypes.add('Sleep (${w.days} nights)');
        return _sleep(w, x);
      case CoachTools.workouts:
        final w = _window(i, 'from', 'to');
        dataTypes.add('Workouts and strain (${w.days} days)');
        return _workouts(w, x);
      case CoachTools.healthMonitor:
        final d = _pastDate(i, 'date');
        dataTypes.add('Health Monitor (1 day)');
        return _healthMonitor(d, x);
      case CoachTools.trainingLoad:
        final d = _pastDate(i, 'date');
        dataTypes.add('Strain history (28 days)');
        return _trainingLoad(d, x);
      case CoachTools.journalInsights:
        dataTypes.add('Journal factors and insights');
        return _journal(x);
      case CoachTools.coverage:
        final w = _window(i, 'from', 'to');
        dataTypes.add('Data coverage (${w.days} days)');
        return _coverage(w, x);
      case CoachTools.methodology:
        final t = MethodologyTopic.fromWire('${i['topic']}');
        if (t == null) throw ToolError('Unknown topic "${i['topic']}".');
        dataTypes.add('Methodology (no personal data)');
        return Methodology.build(t, x.sink);
      case CoachTools.memories:
        return _memories();
      case CoachTools.proposeMemory:
        return _propose(i);
      case CoachTools.insightCard:
        return _insightCard(x);
    }
    throw ToolError('Unknown tool "${c.name}".');
  }

  // ── Input validation ──────────────────────────────────────────────────

  /// Checks [input] against [spec]'s JSON Schema (the subset the specs
  /// use: an object of string properties, `enum`, `required`,
  /// `additionalProperties: false`). Models can send anything; nothing
  /// unvalidated reaches a tool.
  static void validateArgs(CoachToolSpec spec, Map<String, dynamic> input) {
    final schema = spec.inputSchema;
    final props =
        (schema['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final required = (schema['required'] as List?)?.cast<String>() ?? const [];
    for (final k in input.keys) {
      if (!props.containsKey(k)) {
        throw ToolError('Unknown argument "$k" for ${spec.name}.');
      }
    }
    for (final k in required) {
      if (input[k] == null) {
        throw ToolError('Missing argument "$k" for ${spec.name}.');
      }
    }
    for (final e in input.entries) {
      final p = (props[e.key] as Map?)?.cast<String, dynamic>() ?? const {};
      final v = e.value;
      if (v == null) continue;
      if (p['type'] == 'string') {
        if (v is! String) {
          throw ToolError('"${e.key}" must be a string.');
        }
        if (v.length > 300) throw ToolError('"${e.key}" is too long.');
        final allowed = p['enum'];
        if (allowed is List && !allowed.contains(v)) {
          throw ToolError('"${e.key}" must be one of ${allowed.join(', ')}.');
        }
      }
    }
  }

  static final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  String _dateOf(Map<String, dynamic> i, String key) {
    final v = i[key];
    if (v is! String || !_dateRe.hasMatch(v)) {
      throw ToolError('"$key" must be a date like $today.');
    }
    try {
      final t = DayKey.start(v);
      if (DayKey.of(t) != v) throw const FormatException();
    } catch (_) {
      throw ToolError('"$key" is not a valid date: $v.');
    }
    return v;
  }

  String _pastDate(Map<String, dynamic> i, String key) {
    final d = _dateOf(i, key);
    if (d.compareTo(today) > 0) {
      throw ToolError(
        '$d is in the future (today is $today); there is no data yet.',
      );
    }
    return d;
  }

  _Window _window(Map<String, dynamic> i, String fk, String tk) {
    var from = _dateOf(i, fk), to = _dateOf(i, tk);
    if (from.compareTo(to) > 0) (from, to) = (to, from);
    if (from.compareTo(today) > 0) {
      throw ToolError('$from is in the future (today is $today).');
    }
    final notes = <String>[];
    if (to.compareTo(today) > 0) {
      to = today;
      notes.add('Window ends today ($today); later days have no data yet.');
    }
    if (DayKey.diff(from, to) + 1 > CoachTools.maxWindowDays) {
      from = DayKey.add(to, -(CoachTools.maxWindowDays - 1));
      notes.add(
        'Window capped at ${CoachTools.maxWindowDays} days (from $from).',
      );
    }
    return _Window(from, to, notes);
  }

  RangeMetric _metricOf(Map<String, dynamic> i) {
    final m = RangeMetric.fromWire('${i['metric']}');
    if (m == null) throw ToolError('Unknown metric "${i['metric']}".');
    return m;
  }

  // ── Shared builders ───────────────────────────────────────────────────

  Map<String, dynamic> _noDay(String d, _Ctx x) => {
    'date': d,
    'day': CoachFormat.day(d),
    'missing':
        'No data at all for ${CoachFormat.day(d)}: the band was not worn, '
        'not synced, or the day is before your history. Do not treat this '
        'day as rest, sleep or zero.',
    'noDataDates': [d],
  };

  Future<Map<String, dynamic>> _todaySummary(_Ctx x) async {
    var b = await health.day(today);
    String? note;
    if (b == null) {
      final latest = await health.latestDate();
      if (latest == null) {
        return {
          'date': today,
          'missing': 'There is no data yet. Sync or wear the band first.',
          'noDataDates': [today],
        };
      }
      b = await health.day(latest);
      if (b == null) return _noDay(today, x);
      note =
          'No data for today (${CoachFormat.day(today)}) yet; this is the '
          'latest day with data.';
    }
    final p = await _dayPayload(b, x, detailed: false);
    return {
      'note': ?note,
      if (b.date == today)
        'partialDay':
            'Today is in progress: strain and steps are so far '
            '(${CoachFormat.clock(CoachFormat.minutesOfDay(now))}).',
      ...p,
    };
  }

  Map<String, dynamic> _f(
    _Ctx x,
    String label,
    double value,
    String unit, {
    String? date,
    String? route,
    int decimals = 0,
  }) => x.sink.fact(
    date == null ? label : '$label · ${CoachFormat.day(date)}',
    value,
    unit,
    date: date,
    route: route,
    decimals: decimals,
  );

  Future<Map<String, dynamic>> _dayPayload(
    DayBundle b,
    _Ctx x, {
    required bool detailed,
  }) async {
    final r = b.record, s = b.result, d = b.date;
    final out = <String, dynamic>{'date': d, 'day': CoachFormat.day(d)};
    final missing = <String>[];

    // Recovery.
    final rec = s.recovery;
    if (rec == null) {
      missing.add('Recovery: ${_noteFor(s, 'recovery') ?? 'not enough data'}');
    } else if (x.recoveryWithheld(r)) {
      x.withhold('Recovery');
    } else {
      out['recovery'] = {
        'score': _f(
          x,
          'Recovery',
          rec.score.toDouble(),
          '%',
          date: d,
          route: CoachRoutes.recovery,
        ),
        'zone': rec.zone.name,
        if (rec.calibrating)
          'calibrating': 'Baseline still calibrating: treat as provisional.',
        'drivers': [for (final c in rec.components) _component(c, d, x)],
        if (rec.penalties.isNotEmpty)
          'penalties': [
            for (final p in rec.penalties)
              {
                'reason': p.label,
                'points': _f(
                  x,
                  'Recovery penalty',
                  p.points,
                  'pts',
                  date: d,
                  route: CoachRoutes.recovery,
                  decimals: 1,
                ),
              },
          ],
      };
    }

    // Sleep (the night that ended this morning).
    final sl = s.sleep;
    if (sl == null || !sl.hasData) {
      missing.add('Sleep: ${_noteFor(s, 'sleep') ?? 'no sleep recorded'}');
    } else if (x.withheldMetric(r, Metric.sleep)) {
      x.withhold('Sleep');
    } else {
      out['sleep'] = _sleepNight(sl, d, x, detailed: detailed);
    }

    // Strain + workouts.
    final st = s.strain;
    if (st == null || st.method == StrainMethod.none) {
      missing.add('Strain: ${_noteFor(s, 'strain') ?? 'no heart rate'}');
    } else if (x.strainWithheld(r)) {
      x.withhold('Strain');
    } else {
      out['strain'] = {
        'value': _f(
          x,
          'Strain',
          st.strain,
          'strain',
          date: d,
          route: CoachRoutes.strain,
          decimals: 1,
        ),
        'method': st.method == StrainMethod.hrZones
            ? 'heart-rate zones'
            : 'estimated from workouts and steps (sparse heart rate)',
        // The target is a fixed factor × Recovery: withheld with it.
        if (st.targetStrain != null && !x.recoveryWithheld(r))
          'target': _f(
            x,
            'Strain target',
            st.targetStrain!,
            'strain',
            date: d,
            route: CoachRoutes.strain,
            decimals: 1,
          ),
        if (detailed && st.avgHr != null)
          'avgHr': _f(
            x,
            'Average HR',
            st.avgHr!,
            'bpm',
            date: d,
            route: CoachRoutes.strain,
          ),
      };
    }
    if (x.withheldMetric(r, Metric.workouts)) {
      if (r.workouts.isNotEmpty) x.withhold('Workouts');
    } else {
      out['workouts'] = [for (final w in r.workouts) _workout(w, s.strain, x)];
    }

    // Nightly metrics.
    final nightly = <String, dynamic>{};
    void put(
      String key,
      String label,
      double? v,
      Metric m,
      String unit, [
      int dec = 0,
    ]) {
      if (v == null) {
        missing.add('$label: not recorded');
      } else if (x.withheldMetric(r, m)) {
        x.withhold(label);
      } else {
        nightly[key] = _f(
          x,
          label,
          v,
          unit,
          date: d,
          route: CoachRoutes.trends,
          decimals: dec,
        );
      }
    }

    put('hrv', 'HRV', r.hrvRmssd, Metric.hrv, 'ms');
    put('restingHr', 'Resting HR', r.restingHr, Metric.restingHr, 'bpm');
    if (detailed) {
      put(
        'respiratoryRate',
        'Respiratory rate',
        r.respiratoryRate,
        Metric.respiratoryRate,
        '/min',
        1,
      );
      put('spo2Avg', 'SpO₂ average', r.spo2Avg, Metric.spo2, '%', 1);
      put('spo2Min', 'SpO₂ lowest', r.spo2Min, Metric.spo2, '%', 1);
      put(
        'skinTemp',
        'Skin temperature vs baseline',
        r.skinTempDelta,
        Metric.skinTemp,
        '°C',
        1,
      );
    }
    out['nightly'] = nightly;
    if (r.steps != null && !x.withheldMetric(r, Metric.steps)) {
      out['steps'] = _f(
        x,
        'Steps',
        r.steps!.toDouble(),
        'steps',
        date: d,
        route: CoachRoutes.trends,
      );
    }

    // Health Monitor summary.
    final hm = s.health;
    if (!x.healthWithheld(r)) {
      out['healthMonitor'] = {
        'alert': hm.alert,
        if (hm.alertReason != null) 'reason': hm.alertReason,
        'outOfRange': [
          for (final m in hm.metrics)
            if (m.state == BandState.above || m.state == BandState.below)
              '${m.kind.label} ${m.state.name} your range',
        ],
      };
    }

    // Journal factors from the evening before (they pair with this
    // morning's Recovery).
    final eve = DayKey.add(d, -1);
    final j = await health.journal(eve);
    if (j.factors.isNotEmpty) {
      out['journal'] = {
        'date': eve,
        'loggedEvening': CoachFormat.day(eve),
        'factors': [for (final f in j.factors) f.label],
      };
    }

    // Wear gaps.
    final cov = _gaps(r, x);
    if (cov.isNotEmpty) out['wear'] = cov;

    if (missing.isNotEmpty) out['missing'] = missing;
    final notes = [
      for (final n in s.notes)
        if (n.severity == NoteSeverity.warning) n.title,
    ];
    if (notes.isNotEmpty) out['notes'] = notes;
    return out;
  }

  String? _noteFor(DayResult s, String metric) {
    for (final n in s.notes) {
      if (n.metric == metric) return '${n.title}. ${n.body}';
    }
    return null;
  }

  Map<String, dynamic> _component(RecoveryComponent c, String d, _Ctx x) {
    final (unit, dec, name) = switch (c.key) {
      'hrv' => ('ms', 0, 'HRV'),
      'rhr' => ('bpm', 0, 'Resting HR'),
      'sleep' => ('%', 0, 'Sleep performance'),
      'resp' => ('/min', 1, 'Respiratory rate'),
      _ => ('', 0, c.label),
    };
    final out = <String, dynamic>{'input': name};
    if (c.value != null) {
      out['value'] = _f(
        x,
        name,
        c.value!,
        unit,
        date: d,
        route: CoachRoutes.recovery,
        decimals: dec,
      );
    }
    final bl = c.baseline;
    if (bl != null && c.value != null) {
      out['baseline'] = _f(
        x,
        '$name baseline',
        bl.mean,
        unit,
        date: d,
        route: CoachRoutes.recovery,
        decimals: dec,
      );
      if (bl.mean.abs() > 1e-9) {
        out['vsBaseline'] = _f(
          x,
          '$name vs baseline',
          (c.value! - bl.mean) / bl.mean * 100,
          '%',
          date: d,
          route: CoachRoutes.recovery,
        );
      }
    }
    out['recoveryPoints'] = _f(
      x,
      'Recovery points from $name',
      c.points,
      'pts',
      date: d,
      route: CoachRoutes.recovery,
      decimals: 1,
    );
    out['weight'] = _f(
      x,
      'Recovery weight today · $name',
      c.weight * 100,
      '%',
      date: d,
      route: CoachRoutes.recovery,
    );
    return out;
  }

  Map<String, dynamic> _sleepNight(
    SleepAnalysis sl,
    String d,
    _Ctx x, {
    required bool detailed,
  }) {
    const rt = CoachRoutes.sleep;
    return {
      'date': d,
      'asleep': _f(x, 'Sleep', sl.sleptMinutes, 'min', date: d, route: rt),
      'performance': _f(
        x,
        'Sleep performance',
        sl.performance,
        '%',
        date: d,
        route: rt,
      ),
      'need': _f(x, 'Sleep need', sl.needMinutes, 'min', date: d, route: rt),
      if (sl.needMinutes > sl.sleptMinutes)
        'shortOfNeed': _f(
          x,
          'Sleep short of need',
          sl.needMinutes - sl.sleptMinutes,
          'min',
          date: d,
          route: rt,
        ),
      'debtAfter': _f(
        x,
        'Sleep debt',
        sl.debtAfterMinutes,
        'min',
        date: d,
        route: rt,
      ),
      if (sl.bedTime != null)
        'bedtime': _f(
          x,
          'Bedtime',
          CoachFormat.minutesOfDay(sl.bedTime!).toDouble(),
          'clock',
          date: d,
          route: rt,
        ),
      if (sl.wakeTime != null)
        'wake': _f(
          x,
          'Wake time',
          CoachFormat.minutesOfDay(sl.wakeTime!).toDouble(),
          'clock',
          date: d,
          route: rt,
        ),
      if (sl.efficiency != null)
        'efficiency': _f(
          x,
          'Sleep efficiency',
          sl.efficiency!,
          '%',
          date: d,
          route: rt,
        ),
      if (sl.consistency != null)
        'consistency': _f(
          x,
          'Sleep consistency',
          sl.consistency!,
          '%',
          date: d,
          route: rt,
        ),
      if (sl.napMinutes > 0)
        'naps': _f(x, 'Naps', sl.napMinutes, 'min', date: d, route: rt),
      if (detailed && sl.stageMinutes.isNotEmpty)
        'stages': {
          for (final st in [SleepStage.deep, SleepStage.rem, SleepStage.light])
            if ((sl.stageMinutes[st] ?? 0) > 0)
              st.name: _f(
                x,
                '${_stageLabel(st)} sleep',
                sl.stageMinutes[st]!,
                'min',
                date: d,
                route: rt,
              ),
        },
    };
  }

  static String _stageLabel(SleepStage s) => switch (s) {
    SleepStage.deep => 'Deep',
    SleepStage.rem => 'REM',
    SleepStage.light => 'Light',
    _ => s.name,
  };

  Map<String, dynamic> _workout(Workout w, StrainResult? st, _Ctx x) {
    final d = DayKey.of(w.start);
    const rt = CoachRoutes.strain;
    final label = 'Workout · ${QuotedText.safeTitle(w.name)}';
    WorkoutStrain? ws;
    for (final e in st?.workouts ?? const <WorkoutStrain>[]) {
      if (e.workoutId == w.id) ws = e;
    }
    return {
      // The title can come from another app or the user: quoted data.
      'workout': QuotedText.wrap(w.name, max: 60),
      'date': d,
      'start': _f(
        x,
        '$label · start',
        CoachFormat.minutesOfDay(w.start).toDouble(),
        'clock',
        date: d,
        route: rt,
      ),
      'duration': _f(
        x,
        '$label · duration',
        w.durationMinutes,
        'min',
        date: d,
        route: rt,
      ),
      if ((ws?.avgHr ?? w.averageHr) != null)
        'avgHr': _f(
          x,
          '$label · average HR',
          (ws?.avgHr ?? w.averageHr)!,
          'bpm',
          date: d,
          route: rt,
        ),
      if (ws != null)
        'strain': _f(
          x,
          '$label · strain',
          ws.strain,
          'strain',
          date: d,
          route: rt,
          decimals: 1,
        ),
      if (w.distanceM != null && w.distanceM! > 0)
        'distance': _f(
          x,
          '$label · distance',
          w.distanceM! / 1000,
          'km',
          date: d,
          route: rt,
          decimals: 1,
        ),
    };
  }

  /// Runs of ≥ 60 min without heart rate inside the day (band off or
  /// charging). Today only counts up to now.
  List<Map<String, dynamic>> _gaps(DayRecord r, _Ctx x) {
    if (x.withheldMetric(r, Metric.hr)) return const [];
    final hr = r.hrSamples;
    final d = r.date;
    if (hr.isEmpty) return const [];
    final end = d == today ? CoachFormat.minutesOfDay(now) : 1440;
    final seen = List<bool>.filled(1440, false);
    for (final s in hr) {
      if (DayKey.of(s.t) != d) continue;
      seen[CoachFormat.minutesOfDay(s.t)] = true;
    }
    final out = <Map<String, dynamic>>[];
    var i = 0;
    while (i < end) {
      if (seen[i]) {
        i++;
        continue;
      }
      var j = i;
      while (j < end && !seen[j]) {
        j++;
      }
      // A trailing run on today is sync lag, not a gap.
      final trailing = j >= end && d == today;
      if (j - i >= 60 && !trailing) {
        const label = 'No data (band off or charging)';
        out.add({
          'from': _f(
            x,
            '$label · from',
            i.toDouble(),
            'clock',
            date: d,
            route: CoachRoutes.sources,
          ),
          'to': _f(
            x,
            '$label · to',
            (j % 1440).toDouble(),
            'clock',
            date: d,
            route: CoachRoutes.sources,
          ),
          'length': _f(
            x,
            '$label · length',
            (j - i).toDouble(),
            'min',
            date: d,
            route: CoachRoutes.sources,
          ),
        });
      }
      i = j;
    }
    return out;
  }

  // ── get_range / compare_periods ────────────────────────────────────────

  double? _metricValue(RangeMetric m, DayBundle b, _Ctx x) {
    final r = b.record, s = b.result;
    switch (m) {
      case RangeMetric.recovery:
        if (s.recovery == null) return null;
        if (x.recoveryWithheld(r)) return x.skip('Recovery');
        return s.recovery!.score.toDouble();
      case RangeMetric.strain:
        final st = s.strain;
        if (st == null || st.method == StrainMethod.none) return null;
        if (x.strainWithheld(r)) return x.skip('Strain');
        return st.strain;
      case RangeMetric.hrv:
        return x.metric(r, Metric.hrv, 'HRV', r.hrvRmssd);
      case RangeMetric.restingHr:
        return x.metric(r, Metric.restingHr, 'Resting HR', r.restingHr);
      case RangeMetric.respiratoryRate:
        return x.metric(
          r,
          Metric.respiratoryRate,
          'Respiratory rate',
          r.respiratoryRate,
        );
      case RangeMetric.spo2:
        return x.metric(r, Metric.spo2, 'SpO₂', r.spo2Avg);
      case RangeMetric.skinTemp:
        return x.metric(
          r,
          Metric.skinTemp,
          'Skin temperature',
          r.skinTempDelta,
        );
      case RangeMetric.steps:
        return x.metric(r, Metric.steps, 'Steps', r.steps?.toDouble());
      case RangeMetric.sleepDuration:
      case RangeMetric.sleepPerformance:
      case RangeMetric.sleepDebt:
      case RangeMetric.sleepConsistency:
        final sl = s.sleep;
        if (sl == null || !sl.hasData) return null;
        if (x.withheldMetric(r, Metric.sleep)) return x.skip('Sleep');
        return switch (m) {
          RangeMetric.sleepDuration => sl.sleptMinutes,
          RangeMetric.sleepPerformance => sl.performance,
          RangeMetric.sleepDebt => sl.debtAfterMinutes,
          _ => sl.consistency,
        };
    }
  }

  Future<List<(String, double?)>> _series(
    RangeMetric m,
    _Window w,
    _Ctx x,
  ) async {
    final bundles = {
      for (final b in await health.range(w.from, w.to)) b.date: b,
    };
    return [
      for (final d in DayKey.range(w.from, w.to))
        (d, bundles[d] == null ? null : _metricValue(m, bundles[d]!, x)),
    ];
  }

  Future<Map<String, dynamic>> _range(RangeMetric m, _Window w, _Ctx x) async {
    final series = await _series(m, w, x);
    final present = [
      for (final (d, v) in series)
        if (v != null && !v.isNaN) (d, v),
    ];
    final noData = [
      for (final (d, v) in series)
        if (v == null) d,
    ];
    final out = <String, dynamic>{
      'metric': m.wire,
      'from': w.from,
      'to': w.to,
      if (w.notes.isNotEmpty) 'notes': w.notes,
      'daysInWindow': w.days,
      'daysWithData': _f(
        x,
        '${m.label} · days with data',
        present.length.toDouble(),
        'days',
        route: m.route,
      ),
    };
    if (noData.isNotEmpty) {
      out['noDataDates'] = noData;
      out['noDataMeans'] =
          'No value on these days (not measured, band off, or not synced). '
          'Never treat them as zero.';
    }
    if (present.isEmpty) {
      out['missing'] = 'No ${m.label} values in this window.';
      return out;
    }
    final vals = [for (final (_, v) in present) v];
    var minE = present.first, maxE = present.first;
    for (final e in present) {
      if (e.$2 < minE.$2) minE = e;
      if (e.$2 > maxE.$2) maxE = e;
    }
    final span = '${CoachFormat.day(w.from)} to ${CoachFormat.day(w.to)}';
    out['mean'] = _f(
      x,
      '${m.label} mean · $span',
      Stats.mean(vals),
      m.unit,
      route: m.route,
      decimals: m.decimals,
    );
    out['min'] = _f(
      x,
      '${m.label} lowest',
      minE.$2,
      m.unit,
      date: minE.$1,
      route: m.route,
      decimals: m.decimals,
    );
    out['max'] = _f(
      x,
      '${m.label} highest',
      maxE.$2,
      m.unit,
      date: maxE.$1,
      route: m.route,
      decimals: m.decimals,
    );

    final t = Engine.trend([for (final (_, v) in series) v]);
    out['trend'] = {
      'significant': t.significant,
      'direction': t.direction.name,
      if (t.significant)
        'changePerWeek': _f(
          x,
          '${m.label} trend per week',
          t.slopePerDay * 7,
          m.unit == 'clock' ? 'min' : m.unit,
          route: m.route,
          decimals: m.decimals == 0 ? 1 : m.decimals,
        ),
      'rule': t.n < 7
          ? 'Too few days for a trend test (needs 7).'
          : (t.significant
                ? 'Significant (Mann-Kendall, p < 0.05).'
                : 'No significant trend: describe it as stable or unclear, '
                      'not as rising or falling.'),
    };

    final bl = await _baseline(m, w, x);
    if (bl != null) out['baseline'] = bl;

    if (w.days <= 31) {
      out['daily'] = [
        for (final (d, v) in present)
          {
            'date': d,
            m.wire: _f(
              x,
              m.label,
              v,
              m.unit,
              date: d,
              route: m.route,
              decimals: m.decimals,
            ),
          },
      ];
    } else {
      final weeks = <String, List<double>>{};
      for (final (d, v) in present) {
        final wd = DayKey.start(d).weekday;
        (weeks[DayKey.add(d, -(wd - 1))] ??= []).add(v);
      }
      out['weeklyMeans'] = [
        for (final e in weeks.entries)
          {
            'weekOf': e.key,
            'mean': _f(
              x,
              '${m.label} week of ${CoachFormat.day(e.key)}',
              Stats.mean(e.value),
              m.unit,
              route: m.route,
              decimals: m.decimals,
            ),
            'days': e.value.length,
          },
      ];
    }
    return out;
  }

  /// The personal baseline from the latest day with a Recovery component
  /// (HRV / RHR / respiratory rate only).
  Future<Map<String, dynamic>?> _baseline(
    RangeMetric m,
    _Window w,
    _Ctx x,
  ) async {
    final key = switch (m) {
      RangeMetric.hrv => 'hrv',
      RangeMetric.restingHr => 'rhr',
      RangeMetric.respiratoryRate => 'resp',
      _ => null,
    };
    if (key == null) return null;
    final bundles = await health.range(w.from, w.to);
    for (final b in bundles.reversed) {
      final rec = b.result.recovery;
      if (rec == null || x.recoveryWithheld(b.record)) continue;
      for (final c in rec.components) {
        if (c.key == key && c.baseline != null) {
          return {
            'asOf': b.date,
            'mean': _f(
              x,
              '${m.label} baseline',
              c.baseline!.mean,
              m.unit,
              date: b.date,
              route: m.route,
              decimals: m.decimals,
            ),
            'nights': c.baseline!.count,
          };
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _compare(
    RangeMetric m,
    _Window a,
    _Window b,
    _Ctx x,
  ) async {
    Future<Map<String, dynamic>> side(_Window w, List<double> into) async {
      final series = await _series(m, w, x);
      into.addAll([
        for (final (_, v) in series)
          if (v != null && !v.isNaN) v,
      ]);
      final span = '${CoachFormat.day(w.from)} to ${CoachFormat.day(w.to)}';
      return {
        'from': w.from,
        'to': w.to,
        if (w.notes.isNotEmpty) 'notes': w.notes,
        'daysWithData': _f(
          x,
          '${m.label} · days with data · $span',
          into.length.toDouble(),
          'days',
          route: m.route,
        ),
        if (into.isNotEmpty)
          'mean': _f(
            x,
            '${m.label} mean · $span',
            Stats.mean(into),
            m.unit,
            route: m.route,
            decimals: m.decimals,
          ),
        'noDataDates': [
          for (final (d, v) in series)
            if (v == null) d,
        ],
      };
    }

    final va = <double>[], vb = <double>[];
    final out = <String, dynamic>{
      'metric': m.wire,
      'a': await side(a, va),
      'b': await side(b, vb),
    };
    if (va.isEmpty || vb.isEmpty) {
      out['missing'] = 'One of the periods has no ${m.label} data.';
      return out;
    }
    final ma = Stats.mean(va), mb = Stats.mean(vb);
    final diffUnit = m.unit == '%' ? 'pts' : m.unit;
    out['difference'] = _f(
      x,
      '${m.label} difference (A − B)',
      ma - mb,
      diffUnit,
      route: m.route,
      decimals: m.decimals == 0 ? 0 : m.decimals,
    );
    if (mb.abs() > 1e-9 && m.unit != '°C') {
      out['differencePct'] = _f(
        x,
        '${m.label} change (A vs B)',
        (ma - mb) / mb.abs() * 100,
        '%',
        route: m.route,
      );
    }
    var significant = false;
    if (va.length >= 3 && vb.length >= 3) {
      final sa = Stats.standardDeviation(va), sb = Stats.standardDeviation(vb);
      final se = math.sqrt(sa * sa / va.length + sb * sb / vb.length);
      significant = se > 0 && (ma - mb).abs() > 2 * se;
    }
    out['significant'] = significant;
    out['rule'] = significant
        ? 'The difference is larger than twice its standard error (Welch).'
        : 'The difference is within day-to-day noise: do not call it a real '
              'change.';
    return out;
  }

  // ── get_sleep ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _sleep(_Window w, _Ctx x) async {
    final bundles = {
      for (final b in await health.range(w.from, w.to)) b.date: b,
    };
    final nights = <Map<String, dynamic>>[];
    final noData = <String>[];
    final asleep = <(String, double)>[];
    final perf = <double>[];
    for (final d in DayKey.range(w.from, w.to)) {
      final b = bundles[d];
      final sl = b?.result.sleep;
      if (b == null || sl == null || !sl.hasData) {
        noData.add(d);
        continue;
      }
      if (x.withheldMetric(b.record, Metric.sleep)) {
        x.withhold('Sleep');
        continue;
      }
      asleep.add((d, sl.sleptMinutes));
      perf.add(sl.performance);
      if (w.days <= 31) {
        nights.add(_sleepNight(sl, d, x, detailed: w.days <= 3));
        final gaps = _gaps(b.record, x);
        if (gaps.isNotEmpty) nights.last['wear'] = gaps;
      }
    }
    final out = <String, dynamic>{
      'from': w.from,
      'to': w.to,
      if (w.notes.isNotEmpty) 'notes': w.notes,
      'nightsWithData': _f(
        x,
        'Sleep · nights with data',
        asleep.length.toDouble(),
        'nights',
        route: CoachRoutes.sleep,
      ),
      if (noData.isNotEmpty) 'noDataDates': noData,
      if (noData.isNotEmpty)
        'noDataMeans':
            'No sleep recorded for these wake days. Never count '
            'them as zero sleep or as a good night.',
    };
    if (asleep.isEmpty) {
      out['missing'] = 'No sleep recorded in this window.';
      return out;
    }
    if (asleep.length > 1) {
      var minE = asleep.first, maxE = asleep.first;
      for (final e in asleep) {
        if (e.$2 < minE.$2) minE = e;
        if (e.$2 > maxE.$2) maxE = e;
      }
      final span = '${CoachFormat.day(w.from)} to ${CoachFormat.day(w.to)}';
      out['average'] = {
        'asleep': _f(
          x,
          'Sleep average · $span',
          Stats.mean([for (final e in asleep) e.$2]),
          'min',
          route: CoachRoutes.sleep,
        ),
        'performance': _f(
          x,
          'Sleep performance average · $span',
          Stats.mean(perf),
          '%',
          route: CoachRoutes.sleep,
        ),
        'shortest': _f(
          x,
          'Shortest sleep',
          minE.$2,
          'min',
          date: minE.$1,
          route: CoachRoutes.sleep,
        ),
        'longest': _f(
          x,
          'Longest sleep',
          maxE.$2,
          'min',
          date: maxE.$1,
          route: CoachRoutes.sleep,
        ),
      };
    }
    if (nights.isNotEmpty) out['nights'] = nights;
    return out;
  }

  // ── get_workouts ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _workouts(_Window w, _Ctx x) async {
    final bundles = {
      for (final b in await health.range(w.from, w.to)) b.date: b,
    };
    final list = <Map<String, dynamic>>[];
    final strain = <Map<String, dynamic>>[];
    final untracked = <String>[];
    var total = 0.0;
    for (final d in DayKey.range(w.from, w.to)) {
      final b = bundles[d];
      if (b == null) {
        untracked.add(d);
        continue;
      }
      final st = b.result.strain;
      if (st == null || st.method == StrainMethod.none) {
        untracked.add(d);
      } else if (x.strainWithheld(b.record)) {
        x.withhold('Strain');
      } else {
        strain.add({
          'date': d,
          'strain': _f(
            x,
            'Strain',
            st.strain,
            'strain',
            date: d,
            route: CoachRoutes.strain,
            decimals: 1,
          ),
        });
      }
      if (x.withheldMetric(b.record, Metric.workouts)) {
        if (b.record.workouts.isNotEmpty) x.withhold('Workouts');
        continue;
      }
      for (final wk in b.record.workouts) {
        if (list.length >= 60) break;
        list.add(_workout(wk, st, x));
        total += wk.durationMinutes;
      }
    }
    return {
      'from': w.from,
      'to': w.to,
      if (w.notes.isNotEmpty) 'notes': w.notes,
      'count': _f(
        x,
        'Workouts · count',
        list.length.toDouble(),
        'count',
        route: CoachRoutes.strain,
      ),
      if (list.isNotEmpty)
        'totalDuration': _f(
          x,
          'Workouts · total time',
          total,
          'min',
          route: CoachRoutes.strain,
        ),
      'workouts': list,
      'onlyTheseHappened':
          'These are the only recorded workouts. Anything else (a swim, a '
          'run) was not recorded; say so rather than assume it.',
      'dailyStrain': strain,
      if (untracked.isNotEmpty) 'notTrackedDates': untracked,
      if (untracked.isNotEmpty)
        'notTrackedMeans':
            'No heart rate on these days (band off or not '
            'synced): they are NOT rest days.',
    };
  }

  // ── get_health_monitor ────────────────────────────────────────────────

  Future<Map<String, dynamic>> _healthMonitor(String d, _Ctx x) async {
    final b = await health.day(d);
    if (b == null) return _noDay(d, x);
    final r = b.record, hm = b.result.health;
    final metrics = <Map<String, dynamic>>[];
    const rt = CoachRoutes.recovery;
    for (final m in hm.metrics) {
      final label = m.kind.label;
      final metric = _hmMetric(m.kind);
      if (x.withheldMetric(r, metric)) {
        x.withhold(label);
        continue;
      }
      final unit = switch (m.kind) {
        HealthMetricKind.restingHr => 'bpm',
        HealthMetricKind.hrv => 'ms',
        HealthMetricKind.respiratoryRate => '/min',
        HealthMetricKind.spo2 => '%',
        HealthMetricKind.skinTemp => '°C',
      };
      final dec =
          m.kind == HealthMetricKind.restingHr || m.kind == HealthMetricKind.hrv
          ? 0
          : 1;
      metrics.add({
        'metric': label,
        'state': switch (m.state) {
          BandState.inRange => 'in range',
          BandState.above => 'above range',
          BandState.below => 'below range',
          BandState.noData => 'no data',
          BandState.calibrating => 'calibrating (baseline too short)',
        },
        if (m.value != null)
          'value': _f(
            x,
            label,
            m.value!,
            unit,
            date: d,
            route: rt,
            decimals: dec,
          ),
        if (m.baseline != null)
          'baseline': _f(
            x,
            '$label baseline',
            m.baseline!.mean,
            unit,
            date: d,
            route: rt,
            decimals: dec,
          ),
        if (m.lower != null)
          'rangeLow': _f(
            x,
            '$label range low',
            m.lower!,
            unit,
            date: d,
            route: rt,
            decimals: dec,
          ),
        if (m.upper != null)
          'rangeHigh': _f(
            x,
            '$label range high',
            m.upper!,
            unit,
            date: d,
            route: rt,
            decimals: dec,
          ),
        if (m.provenance != null) 'source': m.provenance!.source.label,
      });
    }
    // The alert and its reason are built from every metric: withheld when
    // any of them came from the Google Health API.
    final hideAlert = x.healthWithheld(r);
    return {
      'date': d,
      'day': CoachFormat.day(d),
      if (!hideAlert) 'alert': hm.alert,
      if (!hideAlert && hm.alertReason != null) 'reason': hm.alertReason,
      'metrics': metrics,
      'notADiagnosis':
          'Out-of-range values can follow training, alcohol, heat, travel or '
          'illness. Describe, never diagnose.',
    };
  }

  static Metric _hmMetric(HealthMetricKind k) => switch (k) {
    HealthMetricKind.restingHr => Metric.restingHr,
    HealthMetricKind.hrv => Metric.hrv,
    HealthMetricKind.respiratoryRate => Metric.respiratoryRate,
    HealthMetricKind.spo2 => Metric.spo2,
    HealthMetricKind.skinTemp => Metric.skinTemp,
  };

  // ── get_training_load ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> _trainingLoad(String d, _Ctx x) async {
    final from = DayKey.add(d, -27);
    final bundles = await health.range(from, d);
    final strain = <String, double>{};
    DayBundle? today0;
    for (final b in bundles) {
      if (b.date == d) today0 = b;
      final st = b.result.strain;
      if (st == null || st.method == StrainMethod.none) continue;
      if (x.strainWithheld(b.record)) {
        x.withhold('Strain');
        continue;
      }
      strain[b.date] = st.strain;
    }
    final out = <String, dynamic>{'date': d, 'day': CoachFormat.day(d)};
    final load = Engine.trainingLoad(strain, d);
    if (load == null) {
      out['load'] = {
        'missing':
            'Needs 14 days of strain in the last 28; have ${strain.length}.',
      };
    } else {
      out['load'] = {
        'acute7': _f(
          x,
          'Acute load (last-week mean strain)',
          load.acute7,
          'strain',
          date: d,
          route: CoachRoutes.strain,
          decimals: 1,
        ),
        'chronic28': _f(
          x,
          'Chronic load (four-week mean strain)',
          load.chronic28,
          'strain',
          date: d,
          route: CoachRoutes.strain,
          decimals: 1,
        ),
        'ratio': _f(
          x,
          'Training load ratio (ACWR)',
          load.ratio,
          'ratio',
          date: d,
          route: CoachRoutes.strain,
          decimals: 2,
        ),
        'state': load.state.name,
        'daysOfHistory': _f(
          x,
          'Training load · days with strain',
          load.daysOfHistory.toDouble(),
          'days',
          route: CoachRoutes.strain,
        ),
      };
    }
    final b = today0;
    if (b != null) {
      final rec = b.result.recovery;
      if (rec != null && !x.recoveryWithheld(b.record)) {
        out['recovery'] = _f(
          x,
          'Recovery',
          rec.score.toDouble(),
          '%',
          date: d,
          route: CoachRoutes.recovery,
        );
      }
      final st = b.result.strain;
      if (st != null && !x.strainWithheld(b.record)) {
        if (x.recoveryWithheld(b.record)) {
          // The target is a fixed factor × Recovery: withheld with it.
          x.withhold('Strain target');
        } else if (st.targetStrain != null) {
          out['strainTarget'] = _f(
            x,
            'Strain target',
            st.targetStrain!,
            'strain',
            date: d,
            route: CoachRoutes.strain,
            decimals: 1,
          );
        } else {
          out['strainTarget'] = {
            'missing': 'No strain target without a Recovery score.',
          };
        }
        if (st.method != StrainMethod.none) {
          out['strainSoFar'] = _f(
            x,
            'Strain',
            st.strain,
            'strain',
            date: d,
            route: CoachRoutes.strain,
            decimals: 1,
          );
        }
      }
    }
    return out;
  }

  // ── get_journal_insights ──────────────────────────────────────────────

  Future<Map<String, dynamic>> _journal(_Ctx x) async {
    final latest = await health.latestDate() ?? today;
    List<FactorInsight> insights;
    String? note;
    if (cloud) {
      // Derived data counts too: recompute without days whose Recovery
      // used Google Health API inputs.
      final from = DayKey.add(latest, -364);
      final bundles = await health.range(from, latest);
      final tainted = bundles.where((b) => x.recoveryWithheld(b.record));
      if (tainted.isEmpty) {
        insights = await health.journalInsights();
      } else {
        final entries = <String, JournalEntry>{};
        final rec = <String, int>{};
        for (final b in bundles) {
          if (!x.recoveryWithheld(b.record) && b.result.recovery != null) {
            rec[b.date] = b.result.recovery!.score;
          }
          final j = await health.journal(DayKey.add(b.date, -1));
          if (j.factors.isNotEmpty) entries[j.date] = j;
        }
        insights = Engine.journalInsights(entries, rec);
        x.withhold('Recovery used in journal insights', tainted.length);
        note =
            'Computed without days whose Recovery used Google Health API '
            'data, so numbers can differ from the Journal screen.';
      }
    } else {
      insights = await health.journalInsights();
    }
    final recent = <Map<String, dynamic>>[];
    for (var i = 13; i >= 0; i--) {
      final d = DayKey.add(latest, -i);
      final j = await health.journal(d);
      if (j.factors.isNotEmpty) {
        recent.add({
          'date': d,
          'factors': [for (final f in j.factors) f.label],
        });
      }
    }
    const rt = CoachRoutes.journal;
    return {
      'note': ?note,
      'insights': [
        for (final f in insights)
          {
            'factor': f.factor.label,
            'recoveryWith': _f(
              x,
              'Journal · ${f.factor.label} · next-day '
                  'recovery with',
              f.avgWith,
              '%',
              route: rt,
            ),
            'recoveryWithout': _f(
              x,
              'Journal · ${f.factor.label} · next-day '
                  'recovery without',
              f.avgWithout,
              '%',
              route: rt,
            ),
            'difference': _f(
              x,
              'Journal · ${f.factor.label} · difference',
              f.delta,
              'pts',
              route: rt,
              decimals: 1,
            ),
            'daysWith': _f(
              x,
              'Journal · ${f.factor.label} · days with',
              f.daysWith.toDouble(),
              'days',
              route: rt,
            ),
            'daysWithout': _f(
              x,
              'Journal · ${f.factor.label} · days without',
              f.daysWithout.toDouble(),
              'days',
              route: rt,
            ),
            'confidence': f.confidence == InsightConfidence.solid
                ? 'solid (larger than twice its standard error)'
                : 'emerging (could still be noise)',
          },
      ],
      if (insights.isEmpty)
        'missing': 'No factor has 5 days with and 5 days without yet.',
      'associationNotCause':
          'These are associations with next-day Recovery, not proof of cause.',
      'journal': recent,
    };
  }

  // ── get_data_coverage ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> _coverage(_Window w, _Ctx x) async {
    final bundles = {
      for (final b in await health.range(w.from, w.to)) b.date: b,
    };
    final noData = <String>[];
    final days = <Map<String, dynamic>>[];
    final counts = <String, int>{};
    final metrics = <(String, bool Function(DayBundle))>[
      ('heart rate', (b) => b.record.hrSamples.isNotEmpty),
      ('sleep', (b) => b.result.sleep?.hasData ?? false),
      ('HRV', (b) => b.record.hrvRmssd != null),
      ('resting HR', (b) => b.record.restingHr != null),
      ('respiratory rate', (b) => b.record.respiratoryRate != null),
      ('SpO₂', (b) => b.record.spo2Avg != null),
      ('skin temperature', (b) => b.record.skinTempDelta != null),
      ('steps', (b) => b.record.steps != null),
      ('Recovery', (b) => b.result.recovery != null),
    ];
    for (final d in DayKey.range(w.from, w.to)) {
      final b = bundles[d];
      if (b == null) {
        noData.add(d);
        continue;
      }
      final have = <String>[], miss = <String>[];
      for (final (name, has) in metrics) {
        if (has(b)) {
          have.add(name);
          counts[name] = (counts[name] ?? 0) + 1;
        } else {
          miss.add(name);
        }
      }
      if (w.days <= 31) {
        final gaps = _gaps(b.record, x);
        days.add({
          'date': d,
          if (miss.isNotEmpty) 'missing': miss,
          if (b.record.workouts.isNotEmpty)
            'workouts': b.record.workouts.length,
          if (gaps.isNotEmpty) 'wear': gaps,
        });
      }
    }
    final latest = bundles.isEmpty ? null : bundles[bundles.keys.last];
    return {
      'from': w.from,
      'to': w.to,
      if (w.notes.isNotEmpty) 'notes': w.notes,
      'daysWithAnyData': _f(
        x,
        'Days with any data',
        bundles.length.toDouble(),
        'days',
        route: CoachRoutes.sources,
      ),
      if (noData.isNotEmpty) 'noDataDates': noData,
      if (noData.isNotEmpty)
        'noDataMeans':
            'Nothing recorded on these days: not rest, not sleep, '
            'not zero.',
      'daysPerMetric': {
        for (final (name, _) in metrics)
          name: _f(
            x,
            'Days with $name',
            (counts[name] ?? 0).toDouble(),
            'days',
            route: CoachRoutes.sources,
          ),
      },
      if (days.isNotEmpty) 'days': days,
      if (latest != null)
        'sources': {
          for (final e in latest.record.provenance.entries)
            e.key.code: e.value.label,
        },
      'gapRule':
          'A wear gap is 60 min or more without heart rate: the band '
          'was off or charging. Never describe a gap as sleep.',
    };
  }

  // ── get_insight_card (the card seed, run by the service) ─────────────

  Future<Map<String, dynamic>> _insightCard(_Ctx x) async {
    final s = seed!;
    dataTypes.add('The insight card you opened');
    if (cloud) {
      // The card was built on the phone from any source; for a cloud model
      // it is withheld whole when its day used Google Health API data.
      final days = {?s.date, for (final r in s.seedRefs) ?r.date};
      for (final d in days) {
        final b = await health.day(d);
        if (b != null &&
            b.record.provenance.values.any(
              (p) => p.source == SourceKind.googleHealthApi,
            )) {
          x.withhold('The insight card');
          return {
            'missing':
                'This card used Google Health API data, which stays on the '
                'phone. Call the data tools for what can be shared.',
          };
        }
      }
    }
    return {
      'card': {
        'screen': ?s.screen,
        'date': ?s.date,
        if ((s.seedText ?? '').trim().isNotEmpty)
          'text': QuotedText.wrap(s.seedText!, max: 600),
      },
      'facts': [for (final r in s.seedRefs) x.sink.ref(r)],
      'rule':
          'These are the card\'s own facts: use them and cite their ref ids. '
          'Call other tools for anything else.',
    };
  }

  // ── Memories ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _memories() async {
    if (!memoryEnabled) throw const ToolError('Memory is turned off.');
    final all = await coach.memories();
    final active = [
      for (final m in all)
        if (m.expiresOn == null || m.expiresOn!.compareTo(today) >= 0) m,
    ];
    dataTypes.add('Saved memories (${active.length})');
    return {
      'userStated':
          'Facts the user asked you to remember. Context, not '
          'measurements.',
      'memories': [
        for (final m in active)
          {
            'text': QuotedText.wrap(m.text, max: 200),
            'category': m.category.label,
            if (m.expiresOn != null) 'until': m.expiresOn,
          },
      ],
    };
  }

  static final _healthNumber = RegExp(
    r'\d+(\.\d+)?\s*(bpm|ms|%|percent|breaths|°|kcal)|'
    r'\b(recovery|hrv|strain|resting heart rate|spo2|spo₂)\b[^.]*\d',
    caseSensitive: false,
  );

  Map<String, dynamic> _propose(Map<String, dynamic> i) {
    if (!memoryEnabled) throw const ToolError('Memory is turned off.');
    final text = '${i['text'] ?? ''}'.trim();
    if (text.isEmpty) throw const ToolError('"text" is empty.');
    if (text.length > 200) throw const ToolError('"text" is too long.');
    if (_healthNumber.hasMatch(text)) {
      throw const ToolError(
        'Memories never hold health measurements; those always come from '
        'the data tools.',
      );
    }
    MemoryCategory cat;
    try {
      cat = MemoryCategory.values.byName('${i['category']}');
    } catch (_) {
      throw ToolError('Unknown category "${i['category']}".');
    }
    String? exp;
    if (i['expiresOn'] != null && '${i['expiresOn']}'.isNotEmpty) {
      exp = _dateOf(i, 'expiresOn');
    }
    final sensitive = sensitiveMemory.contains(cat);
    if (sensitive && !_userStated(text)) {
      throw const ToolError(
        'Health history and mood are proposed only when the user states '
        'them in this message. Never infer them.',
      );
    }
    proposals.add(MemoryProposal(text, cat, exp));
    dataTypes.add('Proposed memory');
    return {
      'status': 'pending user confirmation',
      'text': text,
      'category': cat.name,
      'expiresOn': ?exp,
      if (sensitive) 'needsExplicitConfirm': true,
      'note':
          'Nothing is saved until the user taps Remember. Tell them you '
          'can remember it if they confirm.',
    };
  }

  /// Categories that need the user's own words and an explicit confirm
  /// (the UI asks a second time before saving one).
  static final sensitiveMemory = {
    for (final c in MemoryCategory.values)
      if (c.needsExplicitConfirm) c,
  };

  /// Most content words of [text] appear in the user's question.
  bool _userStated(String text) {
    final q = (question ?? '').toLowerCase();
    final words = {
      for (final m in RegExp(r'[a-z]{4,}').allMatches(text.toLowerCase()))
        m.group(0)!,
    }..removeAll(const {'user', 'they', 'their', 'have', 'with', 'that'});
    if (words.isEmpty || q.isEmpty) return false;
    return words.where(q.contains).length * 2 >= words.length;
  }
}

class _Window {
  _Window(this.from, this.to, this.notes);
  final String from;
  final String to;
  final List<String> notes;
  int get days => DayKey.diff(from, to) + 1;
}

/// Per-call context: the ref sink and the Google Health API firewall.
class _Ctx {
  _Ctx(this.sink, this.cloud);
  final RefSink sink;
  final bool cloud;

  /// Human label → number of withheld days.
  final Map<String, int> withheld = {};

  void withhold(String label, [int n = 1]) =>
      withheld[label] = (withheld[label] ?? 0) + n;

  double? skip(String label) {
    withhold(label);
    return double.nan; // withheld, not missing
  }

  bool withheldMetric(DayRecord r, Metric m) =>
      cloud && r.provenance[m]?.source == SourceKind.googleHealthApi;

  bool _any(DayRecord r, List<Metric> ms) =>
      ms.any((m) => withheldMetric(r, m));

  /// Recovery is derived from HRV, RHR, sleep, respiratory rate and the
  /// SpO₂ / skin-temperature penalties.
  bool recoveryWithheld(DayRecord r) => _any(r, const [
    Metric.hrv,
    Metric.restingHr,
    Metric.sleep,
    Metric.respiratoryRate,
    Metric.spo2,
    Metric.skinTemp,
  ]);

  bool strainWithheld(DayRecord r) => _any(r, const [
    Metric.hr,
    Metric.workouts,
    Metric.steps,
    Metric.restingHr,
  ]);

  bool healthWithheld(DayRecord r) => _any(r, const [
    Metric.hrv,
    Metric.restingHr,
    Metric.respiratoryRate,
    Metric.spo2,
    Metric.skinTemp,
  ]);

  double? metric(DayRecord r, Metric m, String label, double? v) {
    if (v == null) return null;
    if (withheldMetric(r, m)) return skip(label);
    return v;
  }
}
