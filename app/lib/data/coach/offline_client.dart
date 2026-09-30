// OfflineClient: the default coach engine. No network, no language model.
//
// A deterministic intent router picks read-only tools from the question and
// the ask context on the first turn; on the next turn a template writes the
// answer from the tool results, citing every number with its [rN], so the
// verifier passes by construction. It never invents: missing data is said
// to be missing, and anything outside its intents gets an honest note plus
// today's headline numbers.
//
// It has no clock: "today", the latest day with data and the screen the
// question came from are read from the system prompt's Context block
// (CoachPrompts.system). A repair round gets an empty answer, so the service
// falls back to the facts table. Pure Dart.

import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/dates.dart';
import '../../domain/coach/format.dart';
import '../../domain/coach/methodology.dart';
import '../../domain/coach/prompts.dart';
import '../../domain/coach/quoted.dart';
import '../../domain/coach/tools.dart';
import '../../domain/day_key.dart';
import '../../domain/engine/journal.dart' show JournalEngine;

enum OfflineIntent {
  seed,
  methodology,
  healthMonitor,
  coverage,
  journal,
  compare,
  trend,
  trainingLoad,
  workouts,
  sleepNight,
  sleepWindow,
  day,
  unknown,
}

/// What the router decided for one question.
class OfflinePlan {
  const OfflinePlan(this.intent, this.calls, {this.metric, this.topic});
  final OfflineIntent intent;
  final List<ToolCall> calls;
  final RangeMetric? metric;
  final MethodologyTopic? topic;
}

/// The Context block of the system prompt.
class OfflineContext {
  const OfflineContext({
    required this.today,
    this.latest,
    this.screen,
    this.date,
    this.generalOnly = false,
    this.detailed = false,
  });

  final String today;
  final String? latest;
  final String? screen;
  final String? date;
  final bool generalOnly;
  final bool detailed;

  /// The newest day with data (today when unknown).
  String get dataDay =>
      latest == null || latest!.compareTo(today) > 0 ? today : latest!;

  static final _today = RegExp(r'- Today: (\d{4}-\d{2}-\d{2})');
  static final _latest = RegExp(r'- Latest day with data: (\d{4}-\d{2}-\d{2})');
  static final _asked = RegExp(
    r'- Asked from: (\S+) screen(?:, about (\d{4}-\d{2}-\d{2}))?',
  );

  factory OfflineContext.parse(String system) {
    final t = _today.firstMatch(system)?.group(1);
    final a = _asked.firstMatch(system);
    final screen = a?.group(1);
    return OfflineContext(
      today: t ?? DayKey.of(DateTime.now()),
      latest: _latest.firstMatch(system)?.group(1),
      screen: screen == 'app' ? null : screen,
      date: a?.group(2),
      generalOnly: system.contains('Mode: general only'),
      detailed: system.contains('Length: detailed'),
    );
  }
}

class OfflineClient implements LlmClient {
  const OfflineClient();

  @override
  CoachProvider get provider => CoachProvider.offline;

  @override
  String get model => 'on-device';

  @override
  Future<LlmTurn> next({
    required String system,
    required List<LlmItem> transcript,
    required List<CoachToolSpec> tools,
    required ResponseLength length,
  }) async {
    final ctx = OfflineContext.parse(system);
    var qi = -1;
    for (var i = transcript.length - 1; i >= 0; i--) {
      final it = transcript[i];
      if (it is LlmUser && !it.text.startsWith(CoachPrompts.repairMarker)) {
        qi = i;
        break;
      }
    }
    if (qi < 0) return const LlmTurn(text: '');
    final question = transcript[qi] as LlmUser;
    final q = question.text;
    final after = transcript.sublist(qi + 1);
    // A repair round: say nothing, so the facts table is shown.
    if (after.any(
      (i) => i is LlmUser && i.text.startsWith(CoachPrompts.repairMarker),
    )) {
      return const LlmTurn(text: '');
    }
    // Data attached to the question (the card seed), then tool results.
    final results = [
      ...question.data,
      for (final i in after)
        if (i is LlmToolResults) ...i.results,
    ];
    final asked = after.any(
      (i) =>
          i is LlmAssistant &&
          i.turn.toolCalls.any((c) => c.name != CoachTools.insightCard),
    );
    final hasSeed = results.any((r) => r.name == CoachTools.insightCard);
    final plan = OfflineRouter.route(q, ctx, {
      for (final t in tools) t.name,
    }, hasSeed: hasSeed);
    if (!asked && plan.calls.isNotEmpty) {
      return LlmTurn(toolCalls: plan.calls, stopReason: 'tool_use');
    }
    return LlmTurn(
      text: OfflineComposer(q, ctx, plan, results).compose(),
      stopReason: 'end_turn',
    );
  }
}

// ── Router ───────────────────────────────────────────────────────────────

abstract final class OfflineRouter {
  static final _personal = RegExp(
    r"\b(?:my|mine|me|i|i'm|i've|today|tonight|last night|yesterday|this "
    r"week|this morning)\b",
  );
  static final _define = RegExp(
    r"\bwhat(?:'s| is| are| does| do)\b|\bmeaning of\b|\bmeans?\b|\bexplain\b|"
    r"\bhow (?:is|are|do you|does airlog|does the app|do i get)\b.*\b(?:"
    r"calculat|comput|work(?:ed)? out|measur|scor|set|decid|determin)",
  );
  static final _howCalc = RegExp(
    r"\bhow (?:is|are|do you|does airlog|does the app)\b.*\b(?:calculat|"
    r"comput|work(?:ed)? out|measur|scor|set|decid|determin)",
  );
  static final _seedAsk = RegExp(
    r"\b(?:tell me more|more about (?:this|that|it)|explain (?:this|that|it)|"
    r"what does (?:this|that|it) mean|discuss|go on|what should i do about "
    r"(?:this|that|it)|why (?:is|was) (?:this|that|it)|break (?:this|it) "
    r"down|this card)\b",
  );
  static final _hm = RegExp(
    r"health monitor|\balerts?\b|getting sick|am i sick|coming down|"
    r"anything (?:off|wrong|unusual)|out of range|\bvitals?\b|immune",
  );
  static final _coverage = RegExp(
    r"\bmissing\b|\bgaps?\b|no data|band (?:was )?off|charging|coverage|"
    r"not wearing|wasn'?t wearing|didn'?t (?:record|track)|not recorded|"
    r"where is my data|why is there no|data (?:is )?missing|worn",
  );
  static final _journal = RegExp(
    r"\balcohol\b|\bdrink(?:s|ing)?\b|\bbeer\b|\bwine\b|\bcaffeine\b|"
    r"\bcoffee\b|late meal|\bscreens?\b|\bstress\b|\btravel\b|\bjournal\b|"
    r"\bfactors?\b|\bhabits?\b|\bmeditat\w*",
  );
  static final _compare = RegExp(
    r"\bcompare\w*|\bvs\.?\b|\bversus\b|than last week|than the week "
    r"before|week over week|this week (?:and|with|to) last week|"
    r"(?:better|worse) than (?:last|the previous)",
  );
  static final _trend = RegExp(
    r"\btrend\w*|\blately\b|\brecently\b|\bchang(?:e|ed|ing)\b|"
    r"going (?:up|down)|improv\w*|getting (?:better|worse)|over time",
  );
  static final _load = RegExp(
    r"strain target|target strain|aim for|how hard|push (?:today|it)|"
    r"should i (?:train|work ?out|exercise|go hard|rest)|overtrain\w*|"
    r"training load|too much|\bacwr\b|\bload\b|ready to train",
  );
  static final _workouts = RegExp(
    r"\bworkouts?\b|\bexercis\w*|\btrained\b|\btraining session|\bruns?\b|"
    r"\bran\b|\brid(?:e|es|ing)\b|\brode\b|\bcycl\w*|\bbike\b|\bswim\w*|"
    r"\bswam\b|\bwalk\w*|\bhik\w*|\blift\w*|strength|\bgym\b|\bsessions?\b|"
    r"\bactivit(?:y|ies)\b|\byoga\b|\brow(?:ing|ed)\b",
  );
  static final _sleep = RegExp(
    r"\bsleep\w*|\bslept\b|\bbed(?:time)?\b|\bwoke\b|\bwake\b|\bnaps?\b|"
    r"\bdebt\b|\basleep\b|\bconsisten\w*|\bdeep\b|\brem\b",
  );
  static final _sleepWindow = RegExp(
    r"this week|past week|last week|\bweek\b|\d{1,3} (?:days|nights)|"
    r"consisten\w*|lately|recently|average|this month|month",
  );

  /// The plain phrasings the suggested questions use (COPY_REVIEW C36),
  /// mapped onto the words the rules match, so each lands on the same
  /// intent as before: "what changed my Recovery" asks what drove it; "sleep
  /// I've missed" is sleep debt; "compare with my usual" (but not "my usual
  /// week", a window) is a baseline question. [q] is already lower-case.
  static String aliases(String q) {
    var out = q
        .replaceAllMapped(
          RegExp(r'\bwhat changed (my|this) recovery\b'),
          (m) => 'what drove ${m[1]} recovery',
        )
        .replaceAll(
          RegExp(
            r"\bsleep (?:have|did|do) i miss(?:ed)?\b|\bsleep i'?ve missed\b|"
            r'\bmissed sleep\b',
          ),
          'sleep debt',
        );
    if (_compare.hasMatch(out)) {
      out = out.replaceAll(RegExp(r'\byour usual\b(?!\s+week)'), 'your baseline')
          .replaceAll(RegExp(r'\bmy usual\b(?!\s+week)'), 'my baseline');
    }
    return out;
  }

  static RangeMetric? metricOf(String q) {
    if (RegExp(r'sleep performance').hasMatch(q)) {
      return RangeMetric.sleepPerformance;
    }
    if (RegExp(r'\bdebt\b').hasMatch(q)) return RangeMetric.sleepDebt;
    if (RegExp(r'consisten').hasMatch(q)) return RangeMetric.sleepConsistency;
    if (RegExp(r'\bhrv\b|heart rate variability').hasMatch(q)) {
      return RangeMetric.hrv;
    }
    if (RegExp(r'resting (?:hr|heart rate|pulse)|\brhr\b').hasMatch(q)) {
      return RangeMetric.restingHr;
    }
    if (RegExp(r'respiratory|breathing rate').hasMatch(q)) {
      return RangeMetric.respiratoryRate;
    }
    if (RegExp(r'spo2|spo₂|oxygen').hasMatch(q)) return RangeMetric.spo2;
    if (RegExp(r'skin temp|temperature').hasMatch(q)) {
      return RangeMetric.skinTemp;
    }
    if (RegExp(r'\bsteps?\b').hasMatch(q)) return RangeMetric.steps;
    if (RegExp(r'\bsleep\w*|\bslept\b').hasMatch(q)) {
      return RangeMetric.sleepDuration;
    }
    if (RegExp(r'\bstrain\b').hasMatch(q)) return RangeMetric.strain;
    if (RegExp(r'\brecover\w*').hasMatch(q)) return RangeMetric.recovery;
    return null;
  }

  static MethodologyTopic? topicOf(String q) {
    final rules = <(String, MethodologyTopic)>[
      (r'strain target|target', MethodologyTopic.strainTarget),
      (r'sleep need|need', MethodologyTopic.sleepNeed),
      (r'sleep debt|\bdebt\b', MethodologyTopic.sleepDebt),
      (r'health monitor', MethodologyTopic.healthMonitor),
      (r'training load|acwr|\bload\b', MethodologyTopic.trainingLoad),
      (r'\bzones?\b', MethodologyTopic.heartRateZones),
      (r'\bhrv\b|heart rate variability|rmssd', MethodologyTopic.hrv),
      (r'resting (?:hr|heart rate)|\brhr\b', MethodologyTopic.restingHr),
      (r'spo2|spo₂|oxygen|saturation', MethodologyTopic.spo2),
      (r'calibrat|baseline', MethodologyTopic.calibration),
      (r'\btrends?\b', MethodologyTopic.trends),
      (r'journal|factor', MethodologyTopic.journal),
      (
        r'source|where .* data come|data come from',
        MethodologyTopic.dataSources,
      ),
      (r'\bsleep\b', MethodologyTopic.sleep),
      (r'\bstrain\b', MethodologyTopic.strain),
      (r'\brecovery\b', MethodologyTopic.recovery),
    ];
    for (final (re, t) in rules) {
      if (RegExp(re).hasMatch(q)) return t;
    }
    return null;
  }

  /// (from, to) of the window the question names, else null.
  static (String, String)? windowOf(String q, OfflineContext c) {
    final end = c.dataDay;
    final n = RegExp(r'\b(\d{1,3})[- ](?:days?|nights?)\b').firstMatch(q);
    if (n != null) {
      final d = int.parse(n.group(1)!).clamp(1, CoachTools.maxWindowDays);
      return (DayKey.add(end, -(d - 1)), end);
    }
    if (RegExp(r'two weeks|fortnight|14 days').hasMatch(q)) {
      return (DayKey.add(end, -13), end);
    }
    if (RegExp(
      r'this month|past month|last month|\bmonth\b|lately|recently|'
      r'over time',
    ).hasMatch(q)) {
      return (DayKey.add(end, -29), end);
    }
    if (RegExp(r'\bweek\b|\bweekly\b').hasMatch(q)) {
      return (DayKey.add(end, -6), end);
    }
    final dates =
        DatePhrases.find(q, c.today)
            .where(
              (m) =>
                  m.kind != DateMentionKind.relative ||
                  !m.text.toLowerCase().contains('today'),
            )
            .expand((m) => m.dates)
            .toList()
          ..sort();
    if (dates.length >= 2) return (dates.first, dates.last);
    return null;
  }

  /// The one day the question is about.
  static String dayOf(String q, OfflineContext c) {
    final ms = DatePhrases.find(q, c.today);
    if (ms.isNotEmpty) {
      final d = ms.first.dates.first;
      // "today" / "last night" when today has no data yet: the latest day.
      if (d == c.today) return c.dataDay;
      return d;
    }
    return c.date ?? c.dataDay;
  }

  static OfflinePlan route(
    String question,
    OfflineContext c,
    Set<String> tools, {
    bool hasSeed = false,
  }) {
    final q = aliases(question.toLowerCase().replaceAll('’', "'"));
    var n = 0;
    ToolCall call(String name, [Map<String, dynamic> input = const {}]) =>
        ToolCall(id: 'offline_${++n}', name: name, input: input);
    bool can(String name) => tools.contains(name);

    final personal = _personal.hasMatch(q);
    final topic = topicOf(q);
    final metric = metricOf(q);

    // General-only mode: methodology is the only tool.
    if (c.generalOnly || !can(CoachTools.todaySummary)) {
      final t = topic ?? MethodologyTopic.recovery;
      return OfflinePlan(
        _define.hasMatch(q) && (!personal || _howCalc.hasMatch(q))
            ? OfflineIntent.methodology
            : OfflineIntent.unknown,
        [
          if (can(CoachTools.methodology) && topic != null)
            call(CoachTools.methodology, {'topic': t.wire}),
        ],
        topic: topic,
      );
    }

    if (hasSeed &&
        (_seedAsk.hasMatch(q) || q.split(RegExp(r'\s+')).length <= 3)) {
      return const OfflinePlan(OfflineIntent.seed, []);
    }

    if (topic != null &&
        _define.hasMatch(q) &&
        (!personal || _howCalc.hasMatch(q)) &&
        can(CoachTools.methodology)) {
      return OfflinePlan(OfflineIntent.methodology, [
        call(CoachTools.methodology, {'topic': topic.wire}),
      ], topic: topic);
    }

    final day = dayOf(q, c);
    final win = windowOf(q, c);

    if (_hm.hasMatch(q)) {
      return OfflinePlan(OfflineIntent.healthMonitor, [
        call(CoachTools.healthMonitor, {'date': day}),
      ]);
    }
    if (_coverage.hasMatch(q)) {
      final w = win ?? (DayKey.add(c.dataDay, -6), c.dataDay);
      return OfflinePlan(OfflineIntent.coverage, [
        call(CoachTools.coverage, {'from': w.$1, 'to': w.$2}),
      ]);
    }
    if (_journal.hasMatch(q) &&
        !RegExp(r'\bsleep\b.*\blast night\b').hasMatch(q)) {
      return OfflinePlan(OfflineIntent.journal, [
        call(CoachTools.journalInsights),
      ]);
    }
    if (_compare.hasMatch(q) && !q.contains('baseline')) {
      final m = metric ?? RangeMetric.recovery;
      final end = c.dataDay;
      return OfflinePlan(OfflineIntent.compare, [
        call(CoachTools.compare, {
          'metric': m.wire,
          'aFrom': DayKey.add(end, -6),
          'aTo': end,
          'bFrom': DayKey.add(end, -13),
          'bTo': DayKey.add(end, -7),
        }),
      ], metric: m);
    }
    if (_trend.hasMatch(q) && (metric != null || win != null)) {
      final m = metric ?? RangeMetric.recovery;
      final w = win ?? (DayKey.add(c.dataDay, -29), c.dataDay);
      return OfflinePlan(OfflineIntent.trend, [
        call(CoachTools.range, {'metric': m.wire, 'from': w.$1, 'to': w.$2}),
      ], metric: m);
    }
    if (_load.hasMatch(q)) {
      return OfflinePlan(OfflineIntent.trainingLoad, [
        call(CoachTools.trainingLoad, {'date': day}),
      ]);
    }
    if (_workouts.hasMatch(q)) {
      final explicitDay = DatePhrases.find(q, c.today).isNotEmpty;
      final w =
          win ??
          (explicitDay || c.date != null
              ? (day, day)
              : (DayKey.add(c.dataDay, -6), c.dataDay));
      return OfflinePlan(OfflineIntent.workouts, [
        call(CoachTools.workouts, {'from': w.$1, 'to': w.$2}),
      ]);
    }
    if (_sleep.hasMatch(q) || (c.screen == 'sleep' && metric == null)) {
      if (win != null || _sleepWindow.hasMatch(q)) {
        final w = win ?? (DayKey.add(c.dataDay, -6), c.dataDay);
        return OfflinePlan(OfflineIntent.sleepWindow, [
          call(CoachTools.sleep, {'from': w.$1, 'to': w.$2}),
        ]);
      }
      return OfflinePlan(OfflineIntent.sleepNight, [
        call(CoachTools.sleep, {'from': day, 'to': day}),
      ]);
    }
    if (win != null && metric != null) {
      return OfflinePlan(OfflineIntent.trend, [
        call(CoachTools.range, {
          'metric': metric.wire,
          'from': win.$1,
          'to': win.$2,
        }),
      ], metric: metric);
    }
    final known =
        metric != null ||
        RegExp(
          r"\brecover\w*|\bready\b|readiness|how am i|how'?s my|"
          r"\btoday\b|\bstrain\b|\bdrove\b|\bwhy\b",
        ).hasMatch(q) ||
        c.screen != null;
    if (known) {
      return OfflinePlan(OfflineIntent.day, [
        if (day == c.dataDay)
          call(CoachTools.todaySummary)
        else
          call(CoachTools.day, {'date': day}),
      ], metric: metric);
    }
    return OfflinePlan(OfflineIntent.unknown, [call(CoachTools.todaySummary)]);
  }
}

// ── Composer ─────────────────────────────────────────────────────────────

class OfflineComposer {
  OfflineComposer(this.question, this.ctx, this.plan, this.results)
    : q = OfflineRouter.aliases(question.toLowerCase().replaceAll('’', "'")) {
    for (final r in results) {
      for (final ref in r.refs) {
        refs[ref.id] = ref;
      }
    }
  }

  final String question;
  final String q;
  final OfflineContext ctx;
  final OfflinePlan plan;
  final List<ToolResult> results;
  final Map<String, SourceRef> refs = {};

  static const openNote =
      'For open questions, connect Claude or Gemini in Settings → Coach.';

  Map<String, dynamic>? _res(String name) {
    for (final r in results.reversed) {
      if (r.name == name && !r.isError) return r.content;
    }
    return null;
  }

  String? _error(String name) {
    for (final r in results.reversed) {
      if (r.name == name && r.isError) return '${r.content['error'] ?? ''}';
    }
    return null;
  }

  /// "70% [r1]" for a fact map, or null.
  static String? f(Object? fact) {
    if (fact is! Map) return null;
    final v = fact['value'], ref = fact['ref'];
    if (v is! num || ref is! String) return null;
    final shown = fact['display'] is String
        ? fact['display'] as String
        : CoachFormat.value(v.toDouble(), fact['unit'] as String?);
    return '$shown [$ref]';
  }

  static double? val(Object? fact) => fact is Map && fact['value'] is num
      ? (fact['value'] as num).toDouble()
      : null;

  String? _dateOfFact(Object? fact) =>
      fact is Map ? refs['${fact['ref']}']?.date : null;

  String _day(String d) =>
      d == ctx.today ? 'today' : 'on ${CoachFormat.day(d)}';

  String _span(String a, String b) =>
      '${CoachFormat.day(a)} to ${CoachFormat.day(b)}';

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// A workout title safe to repeat in an answer (see QuotedText).
  static String safeTitle(Object? w) =>
      QuotedText.safeTitle(QuotedText.unwrap(w));

  String compose() {
    final text = switch (plan.intent) {
      OfflineIntent.seed => _seed(),
      OfflineIntent.methodology => _methodology(),
      OfflineIntent.healthMonitor => _healthMonitor(),
      OfflineIntent.coverage => _coverage(),
      OfflineIntent.journal => _journal(),
      OfflineIntent.compare => _compare(),
      OfflineIntent.trend => _trend(),
      OfflineIntent.trainingLoad => _load(),
      OfflineIntent.workouts => _workouts(),
      OfflineIntent.sleepNight => _sleepNight(),
      OfflineIntent.sleepWindow => _sleepWindow(),
      OfflineIntent.day => _dayAnswer(),
      OfflineIntent.unknown => _unknown(),
    };
    return text.trim();
  }

  // ── Seed (insight card "Discuss") ─────────────────────────────────────

  String _seed() {
    final card = _res(CoachTools.insightCard);
    if (card == null || card['facts'] is! List) {
      return 'I don’t have the card’s details here. Ask me about one day or '
          'one score.';
    }
    final facts = [
      for (final x in card['facts'] as List)
        if (x is Map && x['value'] is num) x,
    ];
    if (facts.isEmpty) {
      return 'That card has no numbers I can show. Ask me about a specific '
          'day or metric.';
    }
    final b = StringBuffer('Here are the numbers behind that card:');
    for (final x in facts.take(ctx.detailed ? 8 : 5)) {
      b
        ..writeln()
        ..write(
          '• ${QuotedText.displayLabel(QuotedText.unwrap(x['label']) ?? 'Value')}: ${f(x)}',
        );
    }
    b
      ..writeln()
      ..write('Ask me what drove them, or how they compare with last week.');
    return b.toString();
  }

  // ── Methodology ───────────────────────────────────────────────────────

  String _methodology() {
    final m = _res(CoachTools.methodology);
    if (m == null) return _unknown();
    final text = '${m['text'] ?? ''}';
    if (ctx.detailed) return text;
    final sentences = sentencesOf(text);
    return sentences.isEmpty ? text : sentences.take(3).join(' ');
  }

  // ── Health Monitor ────────────────────────────────────────────────────

  String _healthMonitor() {
    final h = _res(CoachTools.healthMonitor);
    if (h == null) return _toolTrouble(CoachTools.healthMonitor);
    final d = '${h['date']}';
    if (h['missing'] != null) {
      return 'I don\'t have Health Monitor data ${_day(d)}: nothing was '
          'recorded that night, so I can\'t say whether anything is off.';
    }
    final metrics = [
      for (final m in (h['metrics'] as List? ?? const []))
        if (m is Map) m,
    ];
    final out = <Map<dynamic, dynamic>>[],
        inRange = <Map<dynamic, dynamic>>[],
        none = <String>[];
    for (final m in metrics) {
      final s = '${m['state']}';
      if (s.startsWith('above') || s.startsWith('below')) {
        out.add(m);
      } else if (s == 'in range' && m['value'] != null) {
        inRange.add(m);
      } else {
        none.add('${m['metric']}');
      }
    }
    final b = StringBuffer();
    if (h['alert'] == true || out.isNotEmpty) {
      b.write(
        h['alert'] == true
            ? 'Airlog flagged your overnight signals ${_day(d)}.'
            : out.length == 1
            ? 'One overnight signal was outside your usual range '
                  '${_day(d)}.'
            : 'Some overnight signals were outside your usual range '
                  '${_day(d)}.',
      );
      for (final m in out) {
        final lo = f(m['rangeLow']), hi = f(m['rangeHigh']);
        b.write(
          ' ${m['metric']} was ${f(m['value'])}, ${m['state']} (your '
          'usual range ${lo ?? '?'} to ${hi ?? '?'}).',
        );
      }
      b.write(
        ' Out-of-range values can follow hard training, alcohol, heat '
        'or illness, so this is not a diagnosis. If you feel unwell, talk '
        'to a doctor.',
      );
    } else {
      b.write('No Health Monitor alert ${_day(d)}.');
      if (inRange.isNotEmpty) {
        b.write(
          ' ${_cap(_joinList([for (final m in inRange) '${_metricName('${m['metric']}')} '
                '${f(m['value'])}']))} ${inRange.length == 1 ? 'is' : 'are'} within your usual range.',
        );
      }
    }
    if (none.isNotEmpty) {
      b.write(
        ' No reading or baseline yet for ${_joinList([for (final n in none) _metricName(n)])}.',
      );
    }
    return b.toString();
  }

  static String _metricName(String label) => switch (label) {
    'Resting HR' => 'resting HR',
    'Respiratory rate' => 'respiratory rate',
    'Skin temp' => 'skin temperature',
    _ => label,
  };

  // ── Coverage ──────────────────────────────────────────────────────────

  String _coverage() {
    final c = _res(CoachTools.coverage);
    if (c == null) return _toolTrouble(CoachTools.coverage);
    final from = '${c['from']}', to = '${c['to']}';
    final b = StringBuffer(
      'From ${_span(from, to)} I have data on ${f(c['daysWithAnyData'])}.',
    );
    final noData = (c['noDataDates'] as List? ?? const []).cast<Object?>();
    if (noData.isNotEmpty) {
      b.write(
        ' Nothing at all was recorded on ${_joinList([for (final d in noData.take(6)) CoachFormat.day('$d')])}: those days count as missing, not as rest or zero.',
      );
    }
    final days = [
      for (final d in (c['days'] as List? ?? const []))
        if (d is Map) d,
    ];
    var gaps = 0;
    for (final d in days) {
      for (final g in (d['wear'] as List? ?? const [])) {
        if (g is! Map || gaps >= (ctx.detailed ? 6 : 3)) continue;
        gaps++;
        b.write(
          ' On ${CoachFormat.day('${d['date']}')} your tracker recorded no '
          'heart rate from ${f(g['from'])} to ${f(g['to'])} '
          '(${f(g['length'])}), so it was off or charging.',
        );
      }
    }
    final missing = [
      for (final d in days)
        if (d['missing'] is List && (d['missing'] as List).isNotEmpty) d,
    ];
    for (final d in missing.take(3)) {
      b.write(
        ' On ${CoachFormat.day('${d['date']}')}, '
        '${_joinList((d['missing'] as List).map((e) => '$e').toList())} '
        '${(d['missing'] as List).length == 1 ? 'is' : 'are'} missing.',
      );
    }
    if (gaps == 0 && noData.isEmpty && missing.isEmpty) {
      b.write(' No wear gaps of an hour or more in that window.');
    }
    return b.toString();
  }

  // ── Journal ───────────────────────────────────────────────────────────

  /// The Journal's minimum days per group (JournalEngine.minDaysPerGroup),
  /// spelled out.
  static final _minDays = switch (JournalEngine.minDaysPerGroup) {
    5 => 'five',
    7 => 'seven',
    10 => 'ten',
    14 => 'fourteen',
    final n => '$n',
  };

  static const _factorWords = {
    'Alcohol': r'alcohol|drink|beer|wine',
    'Late caffeine': r'caffeine|coffee',
    'Late meal': r'late meal|meal',
    'Stress': r'stress',
    'Feeling sick': r'sick',
    'Screens before bed': r'screen',
    'Trained': r'trained|training|workout',
    'Travel': r'travel',
    'Meditation': r'meditat',
  };

  String _journal() {
    final j = _res(CoachTools.journalInsights);
    if (j == null) return _toolTrouble(CoachTools.journalInsights);
    final all = [
      for (final i in (j['insights'] as List? ?? const []))
        if (i is Map) i,
    ];
    String? asked;
    for (final e in _factorWords.entries) {
      if (RegExp(e.value).hasMatch(q)) {
        asked = e.key;
        break;
      }
    }
    String line(Map<dynamic, dynamic> i) {
      final dw = f(i['daysWith']), dwo = f(i['daysWithout']);
      final solid = '${i['confidence']}'.startsWith('solid');
      return '"${i['factor']}": next-day recovery ${f(i['recoveryWith'])} '
          'with it and ${f(i['recoveryWithout'])} without, a difference of '
          '${f(i['difference'])} ($dw with, $dwo without; '
          '${solid ? 'a solid pattern' : 'still emerging, could be noise'}).';
    }

    final b = StringBuffer();
    if (asked != null) {
      final hit = all.where((i) => i['factor'] == asked).firstOrNull;
      if (hit == null) {
        // The Journal's own minimum (JournalEngine.minDaysPerGroup), as a
        // word: a digit here would be a claim for the verifier to check.
        return 'I can\'t see a pattern for "$asked" yet: I need at least '
            '$_minDays logged days with it and $_minDays without. Keep '
            'tagging it in the journal.';
      }
      b.write(line(hit));
    } else {
      if (all.isEmpty) {
        return 'No journal factor has enough days yet to show a pattern: I '
            'need at least $_minDays days with each tag and $_minDays '
            'without.';
      }
      final sorted = [...all]
        ..sort(
          (a, b) => (val(b['difference']) ?? 0).abs().compareTo(
            (val(a['difference']) ?? 0).abs(),
          ),
        );
      b.write('The factors most linked with your next-day recovery:');
      for (final i in sorted.take(ctx.detailed ? 5 : 3)) {
        b
          ..writeln()
          ..write('• ${line(i)}');
      }
      b.writeln();
    }
    b.write(' These are associations, not proof of cause.');
    return b.toString();
  }

  // ── Compare ───────────────────────────────────────────────────────────

  String _compare() {
    final c = _res(CoachTools.compare);
    final m = plan.metric ?? RangeMetric.recovery;
    if (c == null) return _toolTrouble(CoachTools.compare);
    final a = c['a'] as Map? ?? const {}, bb = c['b'] as Map? ?? const {};
    final name = _metricLabel(m);
    if (c['missing'] != null) {
      return 'I can\'t compare $name for those weeks: one of them has no '
          '$name data.';
    }
    final out = StringBuffer(
      '${_cap(name)} averaged ${f(a['mean'])} from '
      '${_span('${a['from']}', '${a['to']}')}, against ${f(bb['mean'])} from '
      '${_span('${bb['from']}', '${bb['to']}')}.',
    );
    out.write(' The difference is ${f(c['difference'])}.');
    out.write(
      c['significant'] == true
          ? ' That is larger than your day-to-day variation.'
          : ' That is within your normal day-to-day variation, so it isn\'t a '
                'clear change.',
    );
    final gaps = [
      ...(a['noDataDates'] as List? ?? const []),
      ...(bb['noDataDates'] as List? ?? const []),
    ];
    if (gaps.isNotEmpty) {
      out.write(
        ' No $name data on ${_joinList([for (final d in gaps.take(5)) CoachFormat.day('$d')])}, so those days aren\'t counted.',
      );
    }
    return out.toString();
  }

  static String _metricLabel(RangeMetric m) => switch (m) {
    RangeMetric.recovery => 'recovery',
    RangeMetric.strain => 'strain',
    RangeMetric.hrv => 'HRV',
    RangeMetric.restingHr => 'resting HR',
    RangeMetric.respiratoryRate => 'respiratory rate',
    RangeMetric.spo2 => 'SpO₂',
    RangeMetric.skinTemp => 'skin temperature',
    RangeMetric.sleepDuration => 'sleep',
    RangeMetric.sleepPerformance => 'sleep performance',
    RangeMetric.sleepDebt => 'sleep debt',
    RangeMetric.sleepConsistency => 'sleep consistency',
    RangeMetric.steps => 'steps',
  };

  // ── Trend (get_range) ─────────────────────────────────────────────────

  String _trend() {
    final r = _res(CoachTools.range);
    final m = plan.metric ?? RangeMetric.recovery;
    if (r == null) return _toolTrouble(CoachTools.range);
    final name = _metricLabel(m);
    final from = '${r['from']}', to = '${r['to']}';
    if (r['missing'] != null) {
      return 'I don\'t have any $name data from ${_span(from, to)}.';
    }
    final b = StringBuffer(
      'From ${_span(from, to)} your $name averaged ${f(r['mean'])}, ranging '
      'from ${f(r['min'])} on ${CoachFormat.day(_dateOfFact(r['min']) ?? from)} '
      'to ${f(r['max'])} on ${CoachFormat.day(_dateOfFact(r['max']) ?? to)}.',
    );
    final t = r['trend'] as Map? ?? const {};
    if (t['significant'] == true) {
      final up = t['direction'] == 'up';
      b.write(
        ' It is trending ${up ? 'up' : 'down'}, by about '
        '${f(t['changePerWeek'])} a week.',
      );
    } else {
      b.write(' There is no clear trend: it has been broadly stable.');
    }
    final bl = r['baseline'] as Map?;
    if (bl != null && bl['mean'] != null) {
      b.write(' Your usual is ${f(bl['mean'])}.');
    }
    final noData = (r['noDataDates'] as List? ?? const []);
    if (noData.isNotEmpty) {
      b.write(
        ' $_noDataWord ${f(r['daysWithData'])} in that window have '
        '$name data; the others are missing, not zero.',
      );
    }
    return b.toString();
  }

  static const _noDataWord = 'Only';

  // ── Training load / strain target ─────────────────────────────────────

  String _load() {
    final l = _res(CoachTools.trainingLoad);
    if (l == null) return _toolTrouble(CoachTools.trainingLoad);
    final d = '${l['date']}';
    final b = StringBuffer();
    final target = l['strainTarget'];
    if (target is Map && target['value'] != null) {
      b.write('Your effort goal ${_day(d)} is ${f(target)}');
      if (l['recovery'] != null) {
        b.write(', set from a Recovery of ${f(l['recovery'])}');
      }
      b.write('.');
      if (l['strainSoFar'] != null) {
        b.write(' Strain so far is ${f(l['strainSoFar'])}.');
      }
    } else {
      b.write(
        'I don’t have an effort goal ${_day(d)}: it needs a Recovery '
        'score, and there isn’t one.',
      );
    }
    final load = l['load'] as Map? ?? const {};
    if (load['ratio'] != null) {
      final state = '${load['state']}';
      b.write(
        ' Your recent training load (average strain over the last week) '
        'is ${f(load['acute7'])} against ${f(load['chronic28'])} over the '
        'last four weeks, a ratio of ${f(load['ratio'])}: '
        '${switch (state) {
          'detraining' => 'less than usual',
          'optimal' => 'about usual',
          'elevated' => 'more than usual',
          _ => 'much more than usual',
        }}.',
      );
    } else {
      b.write(
        ' I don\'t have enough strain history yet to compare your '
        'recent training load with your longer-term load.',
      );
    }
    return b.toString();
  }

  // ── Workouts ──────────────────────────────────────────────────────────

  static const _kinds = <(String, String, String)>[
    ('swim', r'\bswim\w*|\bswam\b', r'swim'),
    ('run', r'\bruns?\b|\bran\b|\brunning\b|\bjog\w*', r'run|jog|treadmill'),
    (
      'ride',
      r'\brid(?:e|es|ing)\b|\brode\b|\bcycl\w*|\bbik\w*',
      r'ride|cycl|bik',
    ),
    ('walk', r'\bwalk\w*', r'walk'),
    ('hike', r'\bhik\w*', r'hik'),
    (
      'strength session',
      r'strength|\blift\w*|weights|\bgym\b',
      r'strength|weight|lift',
    ),
    ('yoga session', r'\byoga\b|pilates', r'yoga|pilates'),
  ];

  String _workouts() {
    final w = _res(CoachTools.workouts);
    if (w == null) return _toolTrouble(CoachTools.workouts);
    final from = '${w['from']}', to = '${w['to']}';
    final single = from == to;
    final when = single ? _day(from) : 'from ${_span(from, to)}';
    final list = [
      for (final x in (w['workouts'] as List? ?? const []))
        if (x is Map) x,
    ];
    final b = StringBuffer();
    // The question assumes an activity: say plainly if it isn't recorded.
    for (final (label, askRe, nameRe) in _kinds) {
      if (!RegExp(askRe).hasMatch(q)) continue;
      final hits = list.where(
        (x) => RegExp(
          nameRe,
          caseSensitive: false,
        ).hasMatch(QuotedText.unwrap(x['workout']) ?? ''),
      );
      if (hits.isEmpty) {
        b.write('No $label is recorded $when. ');
      }
      break;
    }
    if (list.isEmpty) {
      b.write('I don\'t see any recorded workouts $when.');
    } else {
      b.write(
        single
            ? 'Recorded $when:'
            : 'You recorded ${f(w['count'])} workouts $when, '
                  '${f(w['totalDuration'])} in total:',
      );
      for (final x in list.take(ctx.detailed ? 10 : 6)) {
        final name = safeTitle(x['workout']);
        final parts = [
          ?f(x['duration']),
          if (x['strain'] != null) 'strain ${f(x['strain'])}',
          if (x['avgHr'] != null) 'average HR ${f(x['avgHr'])}',
          if (ctx.detailed && x['distance'] != null) f(x['distance'])!,
        ];
        b
          ..writeln()
          ..write(
            '• $name, ${CoachFormat.day('${x['date']}')}: '
            '${parts.join(', ')}',
          );
      }
    }
    final untracked = (w['notTrackedDates'] as List? ?? const []);
    if (untracked.isNotEmpty) {
      b
        ..writeln()
        ..write(
          'No heart rate on ${_joinList([for (final d in untracked.take(5)) CoachFormat.day('$d')])}, so I can\'t say what happened those days.',
        );
    }
    return b.toString();
  }

  // ── Sleep ─────────────────────────────────────────────────────────────

  String _sleepNight() {
    final s = _res(CoachTools.sleep);
    if (s == null) return _toolTrouble(CoachTools.sleep);
    final d = '${s['to']}';
    final nights = [
      for (final n in (s['nights'] as List? ?? const []))
        if (n is Map) n,
    ];
    final when = d == ctx.today
        ? 'last night'
        : 'the night before ${CoachFormat.day(d)}';
    if (nights.isEmpty) {
      // Never a guessed cause (prompts.dart rule 4): the data can't say
      // why nothing came in.
      return 'I don’t have sleep data for $when: nothing was recorded, so I '
          'can’t score it.';
    }
    final n = nights.last;
    final b = StringBuffer(
      'You slept ${f(n['asleep'])} $when, ${f(n['performance'])} of your '
      'sleep goal of ${f(n['need'])}.',
    );
    if (n['bedtime'] != null && n['wake'] != null) {
      b.write(
        ' Bedtime was ${f(n['bedtime'])} and wake time '
        '${f(n['wake'])}.',
      );
    }
    if (RegExp(r'\bdebt\b').hasMatch(q) ||
        ctx.detailed ||
        val(n['debtAfter']) != 0) {
      b.write(' You’ve missed ${f(n['debtAfter'])} of sleep recently.');
    }
    final st = n['stages'] as Map?;
    if (st != null && (ctx.detailed || RegExp(r'deep|rem|stage').hasMatch(q))) {
      b.write(
        ' Stages: ${_joinList([if (st['deep'] != null) 'deep sleep ${f(st['deep'])}', if (st['rem'] != null) 'REM sleep ${f(st['rem'])}', if (st['light'] != null) 'light sleep ${f(st['light'])}'])}.',
      );
    }
    if (n['consistency'] != null && RegExp(r'consisten').hasMatch(q)) {
      b.write(' Sleep consistency was ${f(n['consistency'])}.');
    }
    return b.toString();
  }

  String _sleepWindow() {
    final s = _res(CoachTools.sleep);
    if (s == null) return _toolTrouble(CoachTools.sleep);
    final from = '${s['from']}', to = '${s['to']}';
    if (s['missing'] != null) {
      return 'I don\'t have any sleep data from ${_span(from, to)}.';
    }
    final nights = [
      for (final n in (s['nights'] as List? ?? const []))
        if (n is Map) n,
    ];
    final avg = s['average'] as Map?;
    final b = StringBuffer();
    if (avg != null) {
      b.write(
        'From ${_span(from, to)} you slept an average of '
        '${f(avg['asleep'])} a night, ${f(avg['performance'])} of your '
        'sleep goal, across ${f(s['nightsWithData'])} with data.',
      );
      b.write(
        ' The shortest night was ${f(avg['shortest'])} '
        '(${CoachFormat.day(_dateOfFact(avg['shortest']) ?? from)}) and the '
        'longest ${f(avg['longest'])} '
        '(${CoachFormat.day(_dateOfFact(avg['longest']) ?? to)}).',
      );
    } else if (nights.isNotEmpty) {
      final n = nights.last;
      b.write(
        'I only have one night from ${_span(from, to)}: you slept '
        '${f(n['asleep'])} (${CoachFormat.day('${n['date']}')}).',
      );
    }
    if (RegExp(r'consisten').hasMatch(q)) {
      final withC = [
        for (final n in nights)
          if (n['consistency'] != null) n,
      ];
      if (withC.isNotEmpty) {
        withC.sort(
          (a, b) => (val(a['consistency']) ?? 0).compareTo(
            val(b['consistency']) ?? 0,
          ),
        );
        final lo = withC.first, hi = withC.last;
        b.write(
          ' Sleep consistency ranged from ${f(lo['consistency'])} '
          '(${CoachFormat.day('${lo['date']}')}) to '
          '${f(hi['consistency'])} (${CoachFormat.day('${hi['date']}')}).',
        );
      }
    }
    if (RegExp(r'\bdebt\b').hasMatch(q) && nights.isNotEmpty) {
      b.write(
        ' After the latest night, you’ve missed '
        '${f(nights.last['debtAfter'])} of sleep.',
      );
    }
    final noData = (s['noDataDates'] as List? ?? const []);
    if (noData.isNotEmpty) {
      b.write(
        ' No sleep was recorded for ${_joinList([for (final d in noData.take(6)) CoachFormat.day('$d')])}; those nights are missing, not zero.',
      );
    }
    return b.toString();
  }

  // ── A day (today summary / get_day) ───────────────────────────────────

  String _dayAnswer() {
    final p = _res(CoachTools.todaySummary) ?? _res(CoachTools.day);
    if (p == null) {
      return _toolTrouble(CoachTools.day);
    }
    final d = '${p['date']}';
    if (p['recovery'] == null &&
        p['sleep'] == null &&
        p['strain'] == null &&
        p['missing'] is String) {
      return 'I don’t have any data ${_day(d)}. Nothing was recorded or '
          'synced yet.';
    }
    final m = plan.metric;
    final b = StringBuffer();
    if (p['note'] != null) {
      b.write(
        'There\'s no data for today yet, so this is '
        '${CoachFormat.day(d)}. ',
      );
    }
    // A single metric question ("what was my HRV?").
    if (m != null && m != RangeMetric.recovery) {
      final one = _metricOfDay(p, m, d);
      if (one != null) return '$b$one';
    }
    final rec = p['recovery'] as Map?;
    if (rec == null) {
      final why = (p['missing'] as List? ?? const [])
          .map((e) => '$e')
          .firstWhere((e) => e.startsWith('Recovery'), orElse: () => '');
      b.write('I don\'t have a recovery score ${_day(d)}');
      b.write(
        why.isEmpty ? '.' : ': ${why.substring(why.indexOf(':') + 1).trim()}',
      );
    } else {
      b.write(
        'Your recovery ${_day(d)} is ${f(rec['score'])}, in the '
        '${rec['zone']} zone.',
      );
      final drivers = [
        for (final x in (rec['drivers'] as List? ?? const []))
          if (x is Map && x['value'] != null) x,
      ];
      final withBase = drivers.where((x) => x['baseline'] != null).toList()
        ..sort(
          (a, b) => (val(b['vsBaseline']) ?? 0).abs().compareTo(
            (val(a['vsBaseline']) ?? 0).abs(),
          ),
        );
      final shown = withBase.take(ctx.detailed ? 3 : 2).toList();
      if (shown.isNotEmpty) {
        final parts = [
          for (final x in shown)
            '${_driverName('${x['input']}')} was ${f(x['value'])} against a '
                'baseline of ${f(x['baseline'])}',
        ];
        b.write(' ${_cap(parts.join(', and '))}.');
      }
      final sleepD = drivers
          .where((x) => x['input'] == 'Sleep performance')
          .firstOrNull;
      if (sleepD != null) {
        b.write(' You got ${f(sleepD['value'])} of your sleep goal.');
      }
      for (final pen in (rec['penalties'] as List? ?? const [])) {
        if (pen is Map) {
          b.write(
            ' A penalty of ${f(pen['points'])} applied '
            '(${pen['reason']}).',
          );
        }
      }
      if (rec['calibrating'] != null) {
        b.write(
          ' Airlog is still learning your usual, so treat this as an early '
          'estimate.',
        );
      }
    }
    final st = p['strain'] as Map?;
    if (st != null && (ctx.detailed || RegExp(r'strain|today').hasMatch(q))) {
      b.write(
        ' Strain ${d == ctx.today ? 'so far' : ''} is '
        '${f(st['value'])}'
        '${st['target'] != null ? ' with a target of ${f(st['target'])}' : ''}.',
      );
    }
    if (ctx.detailed && p['sleep'] is Map) {
      final s = p['sleep'] as Map;
      b.write(' You slept ${f(s['asleep'])} the night before.');
    }
    if (plan.intent == OfflineIntent.unknown) b.write(' $openNote');
    return b.toString().replaceAll('  ', ' ');
  }

  String? _metricOfDay(Map<dynamic, dynamic> p, RangeMetric m, String d) {
    final nightly = p['nightly'] as Map? ?? const {};
    final sleep = p['sleep'] as Map?;
    Object? fact;
    String name = _metricLabel(m);
    switch (m) {
      case RangeMetric.hrv:
        fact = nightly['hrv'];
      case RangeMetric.restingHr:
        fact = nightly['restingHr'];
      case RangeMetric.respiratoryRate:
        fact = nightly['respiratoryRate'];
      case RangeMetric.spo2:
        fact = nightly['spo2Avg'];
      case RangeMetric.skinTemp:
        fact = nightly['skinTemp'];
        name = 'skin temperature (vs your baseline)';
      case RangeMetric.steps:
        fact = p['steps'];
      case RangeMetric.strain:
        final st = p['strain'] as Map?;
        if (st == null) return null;
        return 'Your strain ${d == ctx.today ? 'so far today' : _day(d)} is '
            '${f(st['value'])}'
            '${st['target'] != null ? ', with a target of ${f(st['target'])}' : ''}.';
      case RangeMetric.sleepDuration:
      case RangeMetric.sleepPerformance:
      case RangeMetric.sleepDebt:
      case RangeMetric.sleepConsistency:
        if (sleep == null) return null;
        return 'You slept ${f(sleep['asleep'])} the night before '
            '${CoachFormat.day(d)}, ${f(sleep['performance'])} of your sleep '
            'goal; you’ve missed ${f(sleep['debtAfter'])} of sleep recently.';
      case RangeMetric.recovery:
        return null;
    }
    if (fact == null) {
      return 'I don\'t have $name data ${_day(d)}: it wasn\'t recorded, so '
          'I can\'t say what it was.';
    }
    if (m == RangeMetric.steps) {
      return 'You took ${f(fact)} ${d == ctx.today ? 'so far today' : _day(d)}.';
    }
    final base = _baselineFor(p, m);
    return 'Your $name ${_day(d)} was ${f(fact)}'
        '${base == null ? '' : ', against a baseline of $base'}.';
  }

  String? _baselineFor(Map<dynamic, dynamic> p, RangeMetric m) {
    final key = switch (m) {
      RangeMetric.hrv => 'HRV',
      RangeMetric.restingHr => 'Resting HR',
      RangeMetric.respiratoryRate => 'Respiratory rate',
      _ => null,
    };
    if (key == null) return null;
    final rec = p['recovery'] as Map?;
    for (final x in (rec?['drivers'] as List? ?? const [])) {
      if (x is Map && x['input'] == key && x['baseline'] != null) {
        return f(x['baseline']);
      }
    }
    return null;
  }

  static String _driverName(String input) => switch (input) {
    'Resting HR' => 'resting HR',
    'Respiratory rate' => 'respiratory rate',
    'Sleep performance' => 'sleep performance',
    _ => input,
  };

  // ── Unknown / general-only / errors ───────────────────────────────────

  String _unknown() {
    if (ctx.generalOnly) {
      final m = _res(CoachTools.methodology);
      final b = StringBuffer(
        'General-only mode can\'t see your data, so I can\'t answer that '
        'about you. You can switch to "Use my data" in Settings → Coach.',
      );
      if (m != null && m['text'] != null) {
        final s = sentencesOf('${m['text']}').take(2).join(' ');
        b.write(' In general: $s');
      }
      return b.toString();
    }
    final p = _res(CoachTools.todaySummary);
    final b = StringBuffer(
      'I can\'t answer that one on the device: I answer questions about '
      'your recovery, sleep, strain, workouts, trends, journal and data '
      'gaps.',
    );
    if (p != null) {
      final d = '${p['date']}';
      final facts = [
        if ((p['recovery'] as Map?)?['score'] != null)
          'recovery ${f((p['recovery'] as Map)['score'])}',
        if ((p['sleep'] as Map?)?['asleep'] != null)
          'sleep ${f((p['sleep'] as Map)['asleep'])}',
        if ((p['strain'] as Map?)?['value'] != null)
          'strain ${f((p['strain'] as Map)['value'])}',
      ];
      if (facts.isNotEmpty) {
        b.write(
          ' Here is ${d == ctx.today ? 'today' : CoachFormat.day(d)}: '
          '${_joinList(facts)}.',
        );
      }
    }
    b.write(' $openNote');
    return b.toString();
  }

  String _toolTrouble(String tool) {
    final e = _error(tool);
    if (e != null && e.contains('future')) {
      return 'That date is in the future, so there is no data for it yet.';
    }
    return 'I couldn’t read that from your data just now. Try asking about '
        'one day or one score.';
  }

  /// Sentences of [text], without splitting decimals ("0.2") or "e.g.".
  static List<String> sentencesOf(String text) => [
    for (final s in text.split(RegExp(r'(?<=[.!?])\s+(?=[A-Z"(])')))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  static String _joinList(List<String> xs) {
    if (xs.isEmpty) return '';
    if (xs.length == 1) return xs.first;
    return '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';
  }
}
