// Deterministic insight-card templates: the only card text in v1
// (InsightLevel.full is cut). Built from DayResult + DayRecord only:
// every number in a card is one of its own refs, so the verifier passes by
// construction, and the output policy passes because the copy is fixed.
//
// Voice (product decisions, 2026-09-29): a short plain headline, at most two
// calm sentences, the numbers always shown, no streak language (weekly uses
// "Consistency (X of Y nights met your need)"), no motivational filler,
// never a diagnosis. The TodayPlan is the only narrator of the day's overall
// state, so the recovery card never restates it: it says which input moved
// most, the component breakdown and the change against the baseline.
//
// At most one card per kind per day; one workout card per workout. Health
// Monitor cards reuse the engine's fixed alert copy and are never rewritten
// by a model. Pure Dart (no Flutter, no I/O).

import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/format.dart';
import '../../domain/coach/insight_contracts.dart';
import '../../domain/coach/quoted.dart';
import '../../domain/coach/refs.dart';
import '../../domain/coach/tools.dart';
import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../domain/results.dart';

/// A template card plus what the verifier (and a full-level rewrite) needs.
class InsightDraft {
  const InsightDraft({
    required this.insight,
    required this.content,
    required this.memoryTexts,
  });
  final Insight insight;

  /// The card's facts as a tool-result payload (get_insight_card shape):
  /// the verifier's evidence, and the only data a rewrite may use.
  final Map<String, dynamic> content;

  /// Texts of the memories that shaped the card (verifier context).
  final List<String> memoryTexts;

  /// The card's text as one string (headline, body, bullets).
  String get text => InsightTemplates.textOf(insight);

  /// The synthetic tool result behind the card.
  ToolResult get result => ToolResult(
    callId: 'card',
    name: CoachTools.insightCard,
    content: content,
    refs: insight.refs,
  );
}

class _Facts {
  final List<SourceRef> refs = [];
  final Map<String, dynamic> content = {};

  SourceRef add(
    String label,
    double value,
    String unit, {
    String? date,
    String? route,
    int decimals = 0,
  }) {
    final r = SourceRef(
      id: 'r${refs.length + 1}',
      label: label,
      value: CoachFormat.round(value, decimals),
      unit: unit,
      date: date,
      route: route,
    );
    refs.add(r);
    return r;
  }

  static String t(SourceRef r) => CoachFormat.value(r.value!, r.unit);
}

abstract final class InsightTemplates {
  static String textOf(Insight i) => [
    i.headline,
    i.body,
    for (final b in i.bullets) '${b.label}: ${b.text}',
  ].join('\n');

  /// A stable hash of the card's inputs (its refs and text): the "data
  /// revision" a cached card is keyed on, so a sync that doesn't change the
  /// card's numbers never triggers a new rewrite.
  static int revisionOf(Insight i) {
    var h = 0x811c9dc5;
    final s = StringBuffer(textOf(i));
    for (final id in i.usedMemoryIds) {
      s.write('|memory:$id');
    }
    for (final r in i.refs) {
      s.write('|${r.label}=${r.value}${r.unit}@${r.date}');
    }
    for (final c in s.toString().codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  static final _goalRe = RegExp(
    r'marathon|half|\b\d+ ?k\b|\brace\b|triathlon|\brun(?:ning)?\b|\bride\b|'
    r'cycl|\bswim|train|fitness|strength|\bkm\b|miles|event|sportive|'
    r'century|\bgoal',
    caseSensitive: false,
  );

  /// Every card for [b]'s day. [week]: the 7 days ending that day (weekly
  /// card, built on Sundays). [memories]: active, user-confirmed facts.
  static List<InsightDraft> build(
    DayBundle b, {
    List<DayBundle> week = const [],
    List<MemoryFact> memories = const [],
  }) {
    final goals = [
      for (final m in memories)
        if ((m.category == MemoryCategory.goals ||
                m.category == MemoryCategory.events) &&
            _goalRe.hasMatch(m.text))
          m,
    ];
    return [
      ?_sleep(b),
      ?_recovery(b),
      ?_strain(b, goals),
      for (final w in b.record.workouts) ?_workout(b, w, goals),
      ?_health(b),
      if (DayKey.start(b.date).weekday == DateTime.sunday) ?_weekly(b, week),
    ];
  }

  static DateTime _at(String date, int hour, [int minute = 0]) {
    final d = DayKey.start(date);
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  // ── Sleep ─────────────────────────────────────────────────────────────

  static InsightDraft? _sleep(DayBundle b) {
    final sl = b.result.sleep;
    if (sl == null || !sl.hasData) return null;
    final d = b.date, x = _Facts();
    const rt = CoachRoutes.sleep;
    final day = CoachFormat.day(d);
    final asleep = x.add(
      'Asleep · $day',
      sl.sleptMinutes,
      'min',
      date: d,
      route: rt,
    );
    final perf = x.add(
      'Sleep % of goal · $day',
      sl.performance,
      '%',
      date: d,
      route: rt,
    );
    final need = x.add(
      'Sleep goal · $day',
      sl.needMinutes,
      'min',
      date: d,
      route: rt,
    );
    final debt = x.add(
      'Missed sleep · $day',
      sl.debtAfterMinutes,
      'min',
      date: d,
      route: rt,
    );
    final headline = sl.performance >= 85
        ? 'A solid night\'s sleep'
        : sl.performance >= 70
        ? 'A slightly short night'
        : 'A short night';
    final body = StringBuffer(
      'You slept ${_Facts.t(asleep)}, ${_Facts.t(perf)} of your '
      '${_Facts.t(need)} sleep goal.',
    );
    body.write(
      sl.debtAfterMinutes >= 1
          ? ' You’re short ${_Facts.t(debt)} of sleep from recent nights.'
          : ' You’re not short on sleep.',
    );
    final bullets = <InsightBullet>[];
    if (sl.bedTime != null && sl.wakeTime != null) {
      final bed = x.add(
        'Bedtime · $day',
        CoachFormat.minutesOfDay(sl.bedTime!).toDouble(),
        'clock',
        date: d,
        route: rt,
      );
      final wake = x.add(
        'Wake time · $day',
        CoachFormat.minutesOfDay(sl.wakeTime!).toDouble(),
        'clock',
        date: d,
        route: rt,
      );
      bullets.add(
        InsightBullet(
          'Timing',
          'Asleep at ${_Facts.t(bed)}, up at ${_Facts.t(wake)}',
        ),
      );
    }
    final deep = sl.stageMinutes[SleepStage.deep] ?? 0;
    final rem = sl.stageMinutes[SleepStage.rem] ?? 0;
    if (sl.hasStageData && deep > 0 && rem > 0) {
      final dr = x.add('Deep sleep · $day', deep, 'min', date: d, route: rt);
      final rr = x.add('REM sleep · $day', rem, 'min', date: d, route: rt);
      bullets.add(
        InsightBullet(
          'Stages',
          'Deep sleep ${_Facts.t(dr)}, REM sleep ${_Facts.t(rr)}',
        ),
      );
    }
    return _draft(
      id: 'sleep:$d',
      kind: InsightKind.sleep,
      date: d,
      createdAt: sl.wakeTime ?? _at(d, 7),
      headline: headline,
      body: body.toString(),
      bullets: bullets,
      metrics: [asleep, perf],
      x: x,
      route: rt,
    );
  }

  // ── Recovery (detail only: the TodayPlan narrates the state) ──────────

  static InsightDraft? _recovery(DayBundle b) {
    final rec = b.result.recovery;
    if (rec == null) return null;
    final d = b.date, x = _Facts();
    const rt = CoachRoutes.recovery;
    final day = CoachFormat.day(d);
    final comps = [
      for (final c in rec.components)
        if (c.value != null) c,
    ];
    if (comps.isEmpty) return null;
    // (label for refs and bullets, name inside a sentence, unit, decimals)
    (String, String, String, int) meta(RecoveryComponent c) => switch (c.key) {
      'hrv' => ('HRV', 'HRV', 'ms', 0),
      'rhr' => ('Resting HR', 'resting heart rate', 'bpm', 0),
      'sleep' => ('Sleep % of goal', 'sleep', '%', 0),
      // The ref unit stays the engine's "/min": the verifier and
      // CoachFormat read it.
      'resp' => ('Breathing rate', 'breathing rate', '/min', 1),
      _ => (c.label, c.label, '', 0),
    };
    final withBase = [
      for (final c in comps)
        if (c.baseline != null && c.baseline!.mean.abs() > 1e-9) c,
    ]..sort((a, b) => _dev(b).compareTo(_dev(a)));
    final bullets = <InsightBullet>[];
    final metrics = <SourceRef>[];
    final vals = <String, SourceRef>{}, bases = <String, SourceRef>{};
    for (final c in comps) {
      final (name, _, unit, dec) = meta(c);
      final v = x.add(
        '$name · $day',
        c.value!,
        unit,
        date: d,
        route: rt,
        decimals: dec,
      );
      vals[c.key] = v;
      final w = x.add(
        'Recovery weight · $name · $day',
        c.weight * 100,
        '%',
        date: d,
        route: rt,
      );
      final share = '(${_Facts.t(w)} of the score)';
      var line = '${_Facts.t(v)} $share';
      if (c.baseline != null) {
        final bl = x.add(
          '$name usual · $day',
          c.baseline!.mean,
          unit,
          date: d,
          route: rt,
          decimals: dec,
        );
        bases[c.key] = bl;
        line = '${_Facts.t(v)}, usual ${_Facts.t(bl)} $share';
      }
      bullets.add(InsightBullet(name, line));
    }
    for (final p in rec.penalties) {
      final pr = x.add(
        'Recovery penalty · $day',
        p.points,
        'pts',
        date: d,
        route: rt,
        decimals: 1,
      );
      bullets.add(
        InsightBullet('Penalty', '${p.label}: ${_Facts.t(pr)} off'),
      );
    }
    String headline;
    final body = StringBuffer();
    String cap(String s) => s[0].toUpperCase() + s.substring(1);
    if (withBase.isEmpty) {
      final c = comps.first;
      final (_, plain, _, _) = meta(c);
      headline = 'Still learning your usual';
      body.write(
        'Your $plain was ${_Facts.t(vals[c.key]!)}. Your score will settle '
        'once Airlog has more nights to compare.',
      );
      metrics.add(vals[c.key]!);
    } else {
      final top = withBase.first;
      final (name, plain, _, _) = meta(top);
      final up = top.value! >= top.baseline!.mean;
      headline = '${cap(name == 'Resting HR' ? plain : name)} made the '
          'biggest difference';
      body.write(
        'Your $plain was ${_Facts.t(vals[top.key]!)}, '
        '${up ? 'above' : 'below'} your usual '
        '${_Facts.t(bases[top.key]!)}.',
      );
      metrics
        ..add(vals[top.key]!)
        ..add(bases[top.key]!);
      if (withBase.length > 1) {
        final second = withBase[1];
        final (_, p2, _, _) = meta(second);
        body.write(
          ' Your $p2 was ${_Facts.t(vals[second.key]!)}, against your '
          'usual ${_Facts.t(bases[second.key]!)}.',
        );
      }
      if (rec.calibrating) {
        body.clear();
        body.write(
          'Your $plain was ${_Facts.t(vals[top.key]!)}, against your usual '
          'of ${_Facts.t(bases[top.key]!)}, which Airlog is still '
          'learning.',
        );
      }
    }
    return _draft(
      id: 'recovery:$d',
      kind: InsightKind.recovery,
      date: d,
      createdAt: (b.result.sleep?.wakeTime ?? _at(d, 7)).add(
        const Duration(minutes: 1),
      ),
      headline: headline,
      body: body.toString(),
      bullets: bullets,
      metrics: metrics,
      x: x,
      route: rt,
    );
  }

  static double _dev(RecoveryComponent c) =>
      ((c.value! - c.baseline!.mean) / c.baseline!.mean).abs();

  // ── Strain (the day) ──────────────────────────────────────────────────

  static InsightDraft? _strain(DayBundle b, List<MemoryFact> goals) {
    final st = b.result.strain;
    if (st == null || st.method == StrainMethod.none) return null;
    final d = b.date, x = _Facts();
    const rt = CoachRoutes.strain;
    final day = CoachFormat.day(d);
    final s = x.add(
      'Strain · $day',
      st.strain,
      'strain',
      date: d,
      route: rt,
      decimals: 1,
    );
    final t = st.targetStrain == null
        ? null
        : x.add(
            // "Strain" keeps the ref in the verifier's strain family.
            'Effort goal (Strain) · $day',
            st.targetStrain!,
            'strain',
            date: d,
            route: rt,
            decimals: 1,
          );
    String headline;
    final body = StringBuffer();
    if (t == null) {
      headline = 'Your Strain for the day';
      body.write(
        'Your Strain was ${_Facts.t(s)}. There’s no effort goal without a '
        'Recovery score.',
      );
    } else {
      final ratio = st.strain / (st.targetStrain! <= 0 ? 1 : st.targetStrain!);
      headline = ratio >= 1
          ? 'Past your effort goal'
          : ratio >= 0.8
          ? 'Close to your effort goal'
          : 'A lighter day';
      body.write(
        'Your Strain was ${_Facts.t(s)}, against a goal of '
        '${_Facts.t(t)}.',
      );
    }
    final ws = [...st.workouts]..sort((a, b) => b.strain.compareTo(a.strain));
    final wk = b.record.workouts;
    if (ws.isNotEmpty) {
      final w = wk.where((e) => e.id == ws.first.workoutId).firstOrNull;
      if (w != null) {
        final name = _title(w.name);
        final wsRef = x.add(
          'Workout · $name · strain',
          ws.first.strain,
          'strain',
          date: d,
          route: rt,
          decimals: 1,
        );
        body.write(
          ' Most of it came from your ${name.toLowerCase()} (Strain '
          '${_Facts.t(wsRef)}).',
        );
        _workoutEvidence(x, w, d);
      }
    }
    final bullets = <InsightBullet>[];
    final zones = st.zoneMinutes;
    if (zones.length == 5) {
      final hi = x.add(
        'Strain · time in zones 4 and 5 · $day',
        zones[3] + zones[4],
        'min',
        date: d,
        route: rt,
      );
      final mid = x.add(
        'Strain · time in zones 2 and 3 · $day',
        zones[1] + zones[2],
        'min',
        date: d,
        route: rt,
      );
      bullets.add(
        InsightBullet(
          'Effort',
          '${_Facts.t(mid)} light to moderate (zones 2–3), ${_Facts.t(hi)} '
              'hard (zones 4–5)',
        ),
      );
    }
    if (wk.isNotEmpty) {
      final n = x.add(
        'Workouts · count · $day',
        wk.length.toDouble(),
        'count',
        date: d,
        route: rt,
      );
      final total = x.add(
        'Workouts · total time · $day',
        wk.fold<double>(0, (a, w) => a + w.durationMinutes),
        'min',
        date: d,
        route: rt,
      );
      bullets.add(
        InsightBullet(
          'Workouts',
          '${_Facts.t(n)}, ${_Facts.t(total)} in total',
        ),
      );
    }
    final used = <String>[];
    if (goals.isNotEmpty && wk.isNotEmpty) {
      used.add(goals.first.id);
      bullets.add(
        const InsightBullet(
          'Your goal',
          'This training adds to the goal you saved.',
        ),
      );
    }
    return _draft(
      id: 'strain:$d',
      kind: InsightKind.strain,
      date: d,
      createdAt: wk.isEmpty
          ? _at(d, 20)
          : wk.map((w) => w.end).reduce((a, b) => a.isAfter(b) ? a : b),
      headline: headline,
      body: body.toString(),
      bullets: bullets,
      metrics: [s, ?t],
      x: x,
      route: rt,
      usedMemoryIds: used,
      memoryTexts: [for (final g in goals.take(1)) g.text],
    );
  }

  static void _workoutEvidence(_Facts x, Workout w, String d) {
    (x.content['workouts'] ??= <Map<String, dynamic>>[]).add({
      'workout': QuotedText.wrap(w.name, max: 60),
      'date': DayKey.of(w.start),
    });
  }

  /// A short plain activity name, or "Workout".
  static String _title(String name) => QuotedText.safeTitle(name);

  // ── One workout ───────────────────────────────────────────────────────

  static InsightDraft? _workout(
    DayBundle b,
    Workout w,
    List<MemoryFact> goals,
  ) {
    final d = DayKey.of(w.start), x = _Facts();
    const rt = CoachRoutes.strain;
    final name = _title(w.name);
    WorkoutStrain? ws;
    for (final e in b.result.strain?.workouts ?? const <WorkoutStrain>[]) {
      if (e.workoutId == w.id) ws = e;
    }
    _workoutEvidence(x, w, d);
    final dur = x.add(
      'Workout · $name · duration',
      w.durationMinutes,
      'min',
      date: d,
      route: rt,
    );
    final avg = ws?.avgHr ?? w.averageHr;
    final hr = avg == null
        ? null
        : x.add('Workout · $name · average HR', avg, 'bpm', date: d, route: rt);
    final s = ws == null
        ? null
        : x.add(
            'Workout · $name · strain',
            ws.strain,
            'strain',
            date: d,
            route: rt,
            decimals: 1,
          );
    final effort = ws == null
        ? null
        : ws.strain >= 14
        ? 'hard'
        : ws.strain >= 8
        ? 'moderate'
        : 'easy';
    final headline = effort == null
        ? '$name recorded'
        : '$name: ${effort == 'easy' ? 'an' : 'a'} $effort session';
    final body = StringBuffer(_Facts.t(dur));
    if (hr != null) body.write(', average heart rate ${_Facts.t(hr)}');
    if (s != null) body.write(', Strain ${_Facts.t(s)}');
    body.write('.');
    final bullets = <InsightBullet>[];
    final z = ws?.zoneMinutes ?? const <double>[];
    if (z.length == 5) {
      final hi = x.add(
        'Workout · $name · time in zones 4 and 5',
        z[3] + z[4],
        'min',
        date: d,
        route: rt,
      );
      final mid = x.add(
        'Workout · $name · time in zones 2 and 3',
        z[1] + z[2],
        'min',
        date: d,
        route: rt,
      );
      bullets.add(
        InsightBullet(
          'Effort',
          '${_Facts.t(mid)} light to moderate (zones 2–3), ${_Facts.t(hi)} '
              'hard (zones 4–5)',
        ),
      );
    }
    if (w.distanceM != null && w.distanceM! > 0) {
      final km = x.add(
        'Workout · $name · distance',
        w.distanceM! / 1000,
        'km',
        date: d,
        route: rt,
        decimals: 1,
      );
      bullets.add(
        InsightBullet('Distance', '${_Facts.t(km)} in ${_Facts.t(dur)}'),
      );
    }
    final used = <String>[];
    if (goals.isNotEmpty) {
      used.add(goals.first.id);
      bullets.add(
        const InsightBullet(
          'Your goal',
          'This session adds to the goal you saved.',
        ),
      );
    }
    return _draft(
      id: 'workout:$d:${w.id}',
      kind: InsightKind.workout,
      date: b.date,
      createdAt: w.end,
      headline: headline,
      body: body.toString(),
      bullets: bullets,
      metrics: [dur, ?s],
      x: x,
      route: rt,
      usedMemoryIds: used,
      memoryTexts: [for (final g in goals.take(1)) g.text],
    );
  }

  // ── Health Monitor (fixed copy; never model-written) ──────────────────

  /// The Health Monitor's fixed, non-diagnostic line (same wording as the
  /// app's Health Monitor alert).
  static const notADiagnosis =
      'This is a pattern in your numbers, not a diagnosis.';

  static InsightDraft? _health(DayBundle b) {
    final hm = b.result.health;
    if (!hm.alert) return null;
    final d = b.date, x = _Facts();
    const rt = CoachRoutes.recovery;
    final day = CoachFormat.day(d);
    final metrics = <SourceRef>[];
    final lines = <String>[];
    for (final m in hm.metrics) {
      if (m.value == null ||
          (m.state != BandState.above && m.state != BandState.below)) {
        continue;
      }
      final (unit, dec) = switch (m.kind) {
        HealthMetricKind.restingHr => ('bpm', 0),
        HealthMetricKind.hrv => ('ms', 0),
        HealthMetricKind.respiratoryRate => ('/min', 1),
        HealthMetricKind.spo2 => ('%', 1),
        HealthMetricKind.skinTemp => ('°C', 1),
      };
      final label = m.kind.label;
      final v = x.add(
        '$label · $day',
        m.value!,
        unit,
        date: d,
        route: rt,
        decimals: dec,
      );
      metrics.add(v);
      final side = m.state == BandState.above ? 'above' : 'below';
      if (m.lower != null && m.upper != null) {
        final lo = x.add(
          '$label range low · $day',
          m.lower!,
          unit,
          date: d,
          route: rt,
          decimals: dec,
        );
        final hi = x.add(
          '$label range high · $day',
          m.upper!,
          unit,
          date: d,
          route: rt,
          decimals: dec,
        );
        lines.add(
          'Your ${m.kind.plainName} was ${_Facts.t(v)}, $side your usual '
          'range of ${_Facts.t(lo)} to ${_Facts.t(hi)}',
        );
      } else {
        lines.add(
          'Your ${m.kind.plainName} was ${_Facts.t(v)}, $side your usual '
          'range',
        );
      }
    }
    final body = lines.isEmpty
        ? 'Some overnight signals are outside your usual range. '
              '$notADiagnosis'
        : '${lines.first}. $notADiagnosis';
    return _draft(
      id: 'healthMonitor:$d',
      kind: InsightKind.healthMonitor,
      date: d,
      createdAt: b.result.sleep?.wakeTime ?? _at(d, 7),
      headline: metrics.length >= 2
          ? 'Signals outside your usual range'
          : 'A signal outside your usual range',
      body: body,
      bullets: [for (final l in lines.skip(1)) InsightBullet('Also', l)],
      metrics: metrics,
      x: x,
      route: rt,
    );
  }

  // ── Weekly (Sundays; the 7 days ending that day) ───────────────────────

  static InsightDraft? _weekly(DayBundle b, List<DayBundle> week) {
    final days = [
      for (final w in week)
        if (DayKey.diff(w.date, b.date) >= 0 &&
            DayKey.diff(w.date, b.date) <= 6)
          w,
    ];
    if (days.length < 3) return null;
    final d = b.date, x = _Facts();
    const rt = CoachRoutes.trends;
    final from = DayKey.add(d, -6);
    final span = '${CoachFormat.day(from)} to ${CoachFormat.day(d)}';
    final recs = [
      for (final w in days)
        if (w.result.recovery != null) w.result.recovery!.score.toDouble(),
    ];
    final sleeps = [
      for (final w in days)
        if (w.result.sleep?.hasData ?? false) w.result.sleep!,
    ];
    final body = StringBuffer();
    final metrics = <SourceRef>[];
    if (recs.isNotEmpty) {
      final r = x.add('Recovery average · $span', _mean(recs), '%', route: rt);
      metrics.add(r);
      body.write('Recovery averaged ${_Facts.t(r)}');
    }
    if (sleeps.isNotEmpty) {
      final s = x.add(
        'Sleep average · $span',
        _mean([for (final s in sleeps) s.sleptMinutes]),
        'min',
        route: rt,
      );
      metrics.add(s);
      body.write(
        body.isEmpty
            ? 'Sleep averaged ${_Facts.t(s)} a night'
            : ' and sleep averaged ${_Facts.t(s)} a night',
      );
    }
    if (body.isEmpty) return null;
    body.write('.');
    final bullets = <InsightBullet>[];
    if (sleeps.isNotEmpty) {
      final met = sleeps.where((s) => s.performance >= 99.5).length;
      final m = x.add(
        'Nights that met your sleep goal · $span',
        met.toDouble(),
        'nights',
        route: rt,
      );
      final n = x.add(
        'Nights with sleep data · $span',
        sleeps.length.toDouble(),
        'nights',
        route: rt,
      );
      bullets.add(
        InsightBullet(
          'Consistency',
          '${_Facts.t(m)} of ${_Facts.t(n)} nights met your sleep goal',
        ),
      );
    }
    final wk = [for (final w in days) ...w.record.workouts];
    if (wk.isNotEmpty) {
      final n = x.add(
        'Workouts · count · $span',
        wk.length.toDouble(),
        'count',
        route: rt,
      );
      final t = x.add(
        'Workouts · total time · $span',
        wk.fold<double>(0, (a, w) => a + w.durationMinutes),
        'min',
        route: rt,
      );
      bullets.add(
        InsightBullet(
          'Workouts',
          '${_Facts.t(n)}, ${_Facts.t(t)} in total',
        ),
      );
    }
    return _draft(
      id: 'weekly:$d',
      kind: InsightKind.weekly,
      date: d,
      createdAt: _at(d, 21),
      headline: 'Your week in numbers',
      body: body.toString(),
      bullets: bullets,
      metrics: metrics,
      x: x,
      route: rt,
    );
  }

  static double _mean(List<double> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

  // ── Assembly ──────────────────────────────────────────────────────────

  static InsightDraft _draft({
    required String id,
    required InsightKind kind,
    required String date,
    required DateTime createdAt,
    required String headline,
    required String body,
    required List<InsightBullet> bullets,
    required List<SourceRef> metrics,
    required _Facts x,
    required String route,
    List<String> usedMemoryIds = const [],
    List<String> memoryTexts = const [],
  }) {
    final content = <String, dynamic>{
      'kind': kind.name,
      'date': date,
      ...x.content,
      'facts': [
        for (final r in x.refs)
          {
            'label': r.label,
            'value': RefSink.jsonNumber(r.value!),
            'unit': r.unit,
            if (const {'min', 'clock', '°C', 'steps'}.contains(r.unit))
              'display': CoachFormat.value(r.value!, r.unit),
            'date': ?r.date,
            'ref': r.id,
          },
      ],
    };
    if (QuotedText.containsQuoted(content)) {
      content[QuotedText.noticeKey] = QuotedText.notice;
    }
    final i = Insight(
      id: id,
      kind: kind,
      date: date,
      createdAt: createdAt,
      headline: headline,
      body: body,
      bullets: bullets,
      metrics: metrics,
      refs: List.unmodifiable(x.refs),
      usedMemoryIds: usedMemoryIds,
      algoVersion: kAlgoVersion,
      route: route,
    );
    final withRev = Insight(
      id: i.id,
      kind: i.kind,
      date: i.date,
      createdAt: i.createdAt,
      headline: i.headline,
      body: i.body,
      bullets: i.bullets,
      metrics: i.metrics,
      refs: i.refs,
      usedMemoryIds: i.usedMemoryIds,
      algoVersion: i.algoVersion,
      revision: revisionOf(i),
      route: i.route,
    );
    return InsightDraft(
      insight: withRev,
      content: content,
      memoryTexts: memoryTexts,
    );
  }
}
