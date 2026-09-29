// Parity with Luraxx/pulse SelfTest main.swift (Apache-2.0, see
// third_party/pulse/NOTICE): "Journal & Korrelation" (:465-514) and the
// JournalFactor label check of "Sprachen" (:166). Same fixtures, same checks,
// against engine/journal.dart. Pulse's JournalStore file round-trip is ported
// as the contract's JournalEntry toggle + JSON round-trip (persistence itself
// belongs to data/). The `.sex` factor check (:484) is not portable: the
// contract's JournalFactor list has no such factor.
//
// Deliberate change since algo v2 (product-critic review, 2026-09-29): a
// factor needs ≥ 10 days per group (Pulse: 5) and "solid" means significant
// after a Holm correction. Pulse's 12-day fixtures are therefore doubled to
// 24 days (12/12); the checks are otherwise Pulse's.

import 'dart:convert';

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/journal.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Journal & Korrelation (main.swift:465-514)', () {
    final entries = <String, JournalEntry>{};
    final recovery = <String, int>{};
    for (var i = 0; i < 24; i++) {
      final day = DayKey.add('2026-06-01', i);
      final alcohol = i % 2 == 0;
      entries[day] = JournalEntry(
        date: day,
        factors: alcohol ? {JournalFactor.alcohol} : {},
      );
      recovery[DayKey.add('2026-06-01', i + 1)] = alcohol ? 45 : 75;
    }
    final insights = JournalEngine.insights(entries, recovery);

    test('alcohol clearly lowers next-day recovery, solid, 10/10 groups', () {
      final alc = insights.where((i) => i.factor == JournalFactor.alcohol);
      expect(alc, isNotEmpty);
      final a = alc.first;
      expect(a.delta < -15, isTrue, reason: '${a.delta}');
      expect(a.daysWith >= 10 && a.daysWithout >= 10, isTrue);
      expect(a.confidence, InsightConfidence.solid);
      expect(a.ciLow! <= a.delta && a.delta <= a.ciHigh!, isTrue);
    });

    test('fewer than 10 days in a group → no insight', () {
      final few = {
        for (final e in entries.entries)
          if (e.key.compareTo(DayKey.add('2026-06-01', 18)) < 0) e.key: e.value,
      };
      expect(few.length, 18);
      expect(JournalEngine.insights(few, recovery), isEmpty);
    });

    test('Holm: a borderline factor that passes alone fails among many', () {
      // Two factors with the same moderate effect; with Holm the smaller p
      // is compared with α/2.
      final e = <String, JournalEntry>{};
      final r = <String, int>{};
      final rng = [3, -4, 6, -2, 5, -6, 1, -1, 4, -5, 2, -3];
      for (var i = 0; i < 40; i++) {
        final day = DayKey.add('2026-03-01', i);
        final f = i % 2 == 0;
        e[day] = JournalEntry(
          date: day,
          factors: {if (f) JournalFactor.stress, if (f) JournalFactor.travel},
        );
        r[DayKey.add('2026-03-01', i + 1)] = 70 + (f ? -3 : 0) + rng[i % 12];
      }
      final ins = JournalEngine.insights(e, r);
      expect(ins, hasLength(2));
      for (final x in ins) {
        expect(x.pValue, isNotNull);
        expect(x.ciLow! < x.delta && x.delta < x.ciHigh!, isTrue);
      }
      // Identical groups → identical p; both pass only if p ≤ α/2.
      final p = ins.first.pValue!;
      final both = p <= JournalEngine.alpha / 2;
      expect(
        ins.every((x) => x.confidence == InsightConfidence.solid),
        both,
        reason: 'p=$p',
      );
    });
    test('factor without entries yields no insight', () {
      expect(insights.any((i) => i.factor == JournalFactor.sick), isFalse);
    });

    test('small effect in heavy noise → only emerging', () {
      final noisyEntries = <String, JournalEntry>{};
      final noisyRecovery = <String, int>{};
      const scores = [55, 58, 80, 77, 60, 63, 75, 74, 65, 70, 72, 68];
      for (var i = 0; i < 24; i++) {
        final day = DayKey.add('2026-05-01', i);
        noisyEntries[day] = JournalEntry(
          date: day,
          factors: i % 2 == 0 ? {JournalFactor.lateMeal} : {},
        );
        noisyRecovery[DayKey.add('2026-05-01', i + 1)] = scores[i % 12];
      }
      final noisy = JournalEngine.insights(
        noisyEntries,
        noisyRecovery,
      ).where((i) => i.factor == JournalFactor.lateMeal);
      expect(noisy, isNotEmpty, reason: 'insight missing despite 12/12 days');
      expect(
        noisy.first.confidence,
        InsightConfidence.emerging,
        reason: 'Δ ${noisy.first.delta}, SE ${noisy.first.standardError}',
      );
    });

    test('monthly assessment gate at 28 recovery days', () {
      expect(JournalEngine.assessmentReady(recovery), isFalse);
      final many = {
        for (var i = 0; i < 30; i++) DayKey.add('2026-05-01', i): 70,
      };
      expect(JournalEngine.assessmentReady(many), isTrue);
    });

    test('toggle sets a factor and survives a round-trip', () {
      final e = const JournalEntry(date: '2026-07-18')
          .toggle(JournalFactor.alcohol);
      expect(e.factors.contains(JournalFactor.alcohol), isTrue);
      final back = JournalEntry.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>,
      );
      expect(back.factors.contains(JournalFactor.alcohol), isTrue);
    });
  });

  test('Sprachen: JournalFactor English label (main.swift:166)', () {
    expect(JournalFactor.alcohol.label, 'Alcohol');
  });
}
