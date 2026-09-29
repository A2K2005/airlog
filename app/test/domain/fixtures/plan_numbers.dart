// The TodayPlan number check: every number in a plan's text must come from
// a cited field (TodayPlan.citedResultFields) printed through PlanFormat, or
// from one of the documented comparisons of two such fields. [ours]

import 'package:airlog/domain/engine/strain.dart';
import 'package:airlog/domain/engine/today_planner.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/today_plan.dart';

final _num = RegExp(r'\d+(?:\.\d+)?');

Iterable<String> numbersIn(String s) => _num.allMatches(s).map((m) => m[0]!);

/// Every text of [p]: headline, summary, chips, action titles and whys.
Iterable<String> planTexts(TodayPlan p) sync* {
  yield p.headline;
  yield p.summary;
  for (final e in p.evidence) {
    yield '${e.label} ${e.value} ${e.comparison ?? ''}';
  }
  for (final a in p.actions) {
    yield a.title;
    yield a.why;
    for (final e in a.evidence) {
      yield '${e.label} ${e.value} ${e.comparison ?? ''}';
    }
  }
  yield* p.sources;
  if (p.relearningSource != null) yield p.relearningSource!;
}

/// Number tokens the plan for [b] may print.
Set<String> allowedNumbers(DayBundle b, {SyncStatus? sync, DateTime? now}) {
  final r = b.result;
  final out = <String>{};
  void add(String s) => out.addAll(numbersIn(s));

  final rec = r.recovery;
  if (rec != null) {
    add(PlanFormat.pct(rec.score));
    for (final c in rec.components) {
      final v = c.value, m = c.baseline?.mean;
      if (v == null) continue;
      add(PlanFormat.ms(v));
      add(PlanFormat.bpm(v));
      if (m != null) {
        add(PlanFormat.ms(m));
        add(PlanFormat.bpm(m));
        if (m > 0) add('${PlanFormat.pctVsUsual(v, m)}');
        add('${PlanFormat.bpmVsUsual(v, m)}');
      }
    }
  }
  final st = r.strain;
  if (st != null) {
    add(PlanFormat.strain(st.strain));
    final t = st.targetStrain;
    if (t != null) {
      add(PlanFormat.strain(t));
      final (lo, hi) = StrainEngine.targetRange(t);
      add('$lo $hi');
    }
  }
  final sl = r.sleep;
  if (sl != null) {
    add(PlanFormat.hm(sl.sleptMinutes));
    add(PlanFormat.hm(sl.needMinutes));
    add(PlanFormat.hm(sl.debtAfterMinutes));
    if (sl.performance.isFinite) add('${sl.performance.round()}');
  }
  final bt = r.bedtime;
  if (bt != null) {
    add(PlanFormat.hm(bt.projectedNeedMinutes));
    add(PlanFormat.hm(bt.debtMinutes));
    if (bt.recommendedBedtimeMinutes != null) {
      add(PlanFormat.clock(bt.recommendedBedtimeMinutes!));
    }
    if (bt.habitualWakeMinutes != null) {
      add(PlanFormat.clock(bt.habitualWakeMinutes!));
    }
  }
  for (final m in r.health.metrics) {
    for (final v in [m.value, m.baseline?.mean, m.lower, m.upper]) {
      if (v != null) add(PlanFormat.vital(m.kind, v));
    }
  }
  add('${r.calibration.haveNights} ${r.calibration.needNights}');
  if (r.sourceChange != null) add('${r.sourceChange!.nights}');
  final last = sync?.lastDataAt ?? b.record.lastDataAt;
  if (last != null && now != null) add(PlanFormat.when(last, now));
  // App names may contain digits (e.g. a package name).
  for (final n in r.notShared.values) {
    add(n);
  }
  for (final p in b.record.provenance.values) {
    if (p.origin != null) add(p.origin!);
  }
  return out;
}

/// Numbers in [p]'s text that no cited field supports.
List<String> unsupportedNumbers(TodayPlan p, Set<String> allowed) => [
  for (final t in planTexts(p))
    for (final n in numbersIn(t))
      if (!allowed.contains(n)) '$n in "$t"',
];
