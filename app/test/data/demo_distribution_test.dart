import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/data/services/demo/demo_generator.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

// Demo realism: the synthetic 90 days are what screenshots and goldens are
// built on, so they should look like a healthy, fairly consistent athlete
// (sleep debt that comes and goes, mostly green/yellow recovery, WHOOP-like
// strain) with a few planted bad stretches, not a chronically sleep-deprived
// one pinned at the debt cap.

// The two clocks the screen goldens use (morning and evening).
final nows = [DateTime(2026, 9, 28, 9, 30), DateTime(2026, 9, 28, 19, 30)];

double share<T>(Iterable<T> xs, bool Function(T) p) =>
    xs.isEmpty ? 0 : xs.where(p).length / xs.length;

double median(List<double> xs) {
  final s = [...xs]..sort();
  return s.isEmpty ? double.nan : s[s.length ~/ 2];
}

void main() {
  for (final now in nows) {
    group('now ${now.hour}:${now.minute}', () => _suite(now));
  }
}

void _suite(DateTime now) {
  late List<DayBundle> days; // complete days (today is partial)
  late Set<String> illness;
  setUpAll(() async {
    final repo = InMemoryHealthRepository.demo(now: now);
    final today = DayKey.of(now);
    days = await repo.range(DayKey.add(today, -89), DayKey.add(today, -1));
    final plan = DemoGenerator(seed: 42, now: now).generate().plan;
    // The illness days plus the recovering day after them.
    illness = {...plan.illnessDays, DayKey.add(plan.illnessDays.last, 1)};
  });

  test('recovery zone mix: mostly green/yellow, some red', () {
    final rec = [
      for (final d in days)
        if (d.result.recovery != null && !d.result.recovery!.calibrating)
          d.result.recovery!,
    ];
    expect(rec.length, greaterThanOrEqualTo(80));
    final green = share(rec, (r) => r.zone == RecoveryZone.green);
    final yellow = share(rec, (r) => r.zone == RecoveryZone.yellow);
    final red = share(rec, (r) => r.zone == RecoveryZone.red);
    // ignore: avoid_print
    print(
      'zones over ${rec.length} calibrated days: green ${(green * 100).round()} % '
      'yellow ${(yellow * 100).round()} % red ${(red * 100).round()} %',
    );
    expect(green, inInclusiveRange(0.40, 0.55));
    expect(yellow, inInclusiveRange(0.30, 0.45));
    expect(red, inInclusiveRange(0.05, 0.15));
  });

  test('sleep debt comes and goes instead of sitting at the cap', () {
    final debt = [
      for (final d in days)
        if (d.result.sleep?.hasData ?? false) d.result.sleep!.debtAfterMinutes,
    ];
    final perf = [
      for (final d in days)
        if (d.result.sleep?.hasData ?? false) d.result.sleep!.performance,
    ];
    final need = [
      for (final d in days)
        if (d.result.sleep?.hasData ?? false) d.result.sleep!.needMinutes,
    ];
    expect(debt.length, greaterThanOrEqualTo(85));
    final sorted = [...debt]..sort();
    // ignore: avoid_print
    print(
      'debt min ${sorted.first.round()} median ${median(debt).round()} '
      'max ${sorted.last.round()}; performance median ${median(perf).round()} '
      '(${(share(perf, (p) => p >= 80) * 100).round()} % >= 80); '
      'need ${(need.reduce((a, b) => a < b ? a : b)).round()}..'
      '${(need.reduce((a, b) => a > b ? a : b)).round()} min',
    );
    expect(share(debt, (x) => x <= 150), greaterThanOrEqualTo(0.85));
    expect(debt.where((x) => x >= 299).length, lessThanOrEqualTo(3));
    expect(
      sorted.last,
      greaterThan(90),
      reason: 'bad nights should build some debt',
    );
    expect(
      share(debt, (x) => x > 0),
      greaterThan(0.3),
      reason: 'debt should vary',
    );
    expect(median(debt), lessThan(90));
    expect(median(perf), greaterThanOrEqualTo(90));
    expect(share(perf, (p) => p >= 80), greaterThanOrEqualTo(0.85));
    // Need is not the same number every day.
    expect(need.toSet().length, greaterThan(20));
  });

  test('strain: rest days ~6-12, workout days ~12-18, zone-based', () {
    final ok = days.where((d) => !illness.contains(d.date)).toList();
    final rest = [
      for (final d in ok)
        if (d.record.workouts.isEmpty) d.result.strain!.strain,
    ];
    final work = [
      for (final d in ok)
        if (d.record.workouts.isNotEmpty) d.result.strain!.strain,
    ];
    final restOk = share(rest, (s) => s >= 6 && s <= 12);
    final workOk = share(work, (s) => s >= 12 && s <= 18);
    final zones = share(
      days,
      (d) => d.result.strain?.method == StrainMethod.hrZones,
    );
    // ignore: avoid_print
    print(
      'strain rest ${rest.length} days median ${median(rest).toStringAsFixed(1)} '
      '(${(restOk * 100).round()} % in 6-12); workout ${work.length} days median '
      '${median(work).toStringAsFixed(1)} (${(workOk * 100).round()} % in 12-18); '
      'hrZones ${(zones * 100).round()} %',
    );
    expect(rest.length, greaterThanOrEqualTo(15));
    expect(work.length, greaterThanOrEqualTo(40));
    expect(median(rest), inInclusiveRange(6, 12));
    expect(median(work), inInclusiveRange(12, 18));
    expect(restOk, greaterThanOrEqualTo(0.75));
    expect(workOk, greaterThanOrEqualTo(0.6));
    expect(work.every((s) => s <= 18.5), isTrue);
    expect(zones, greaterThan(0.9));
  });
}
