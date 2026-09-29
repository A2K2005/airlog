// Parity with Luraxx/pulse SelfTest main.swift (Apache-2.0, see
// third_party/pulse/NOTICE): "Strain-Engine" (:224-262), the zone-label part
// of "Sprachen" (:169), the strain part of "Demo-Daten & Engines"
// (:266-284) and "Workout-Strain" (:349-359). Same fixtures, same checks,
// against the faithful port in engine/strain.dart.

import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/strain.dart';
import 'package:airlog/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/pulse_demo_data.dart';

void main() {
  group('Strain-Engine (main.swift:224-262)', () {
    final s60 = StrainEngine.strainFromRaw(60);
    final s300 = StrainEngine.strainFromRaw(300);
    final s900 = StrainEngine.strainFromRaw(900);
    final s5000 = StrainEngine.strainFromRaw(5000);
    test('no load → strain 0', () {
      expect(StrainEngine.strainFromRaw(0), 0);
    });
    test('easy day ≈ 2–4', () {
      expect(s60 > 2 && s60 < 4, isTrue, reason: '$s60');
    });
    test('solid training ≈ 9–12', () {
      expect(s300 > 9 && s300 < 12, isTrue, reason: '$s300');
    });
    test('hard day ≈ 16–19', () {
      expect(s900 > 16 && s900 < 19, isTrue, reason: '$s900');
    });
    test('scale stays below 21', () {
      expect(s5000 < 21, isTrue, reason: '$s5000');
    });
    test('strain grows monotonically with load', () {
      expect(s60 < s300 && s300 < s900 && s900 < s5000, isTrue);
    });

    final t90 = StrainEngine.targetStrain(90);
    final t67 = StrainEngine.targetStrain(67);
    final t34 = StrainEngine.targetStrain(34);
    test('recovery 90 → training target', () {
      expect(t90 >= 17 && t90 <= 18.5, isTrue, reason: '$t90');
    });
    test('recovery 67 → moderate target', () {
      expect(t67 >= 13 && t67 <= 14, isTrue, reason: '$t67');
    });
    test('recovery 34 → recovery target', () {
      expect(t34 >= 6 && t34 <= 8, isTrue, reason: '$t34');
    });
    test('target floor 3', () {
      expect(StrainEngine.targetStrain(5) >= 3, isTrue);
    });
    test('target ceiling 18.5 (never all-out)', () {
      expect(StrainEngine.targetStrain(99) <= 18.5, isTrue);
    });
    test('target grows with recovery', () {
      expect(t90 > t67 && t67 > t34, isTrue);
    });

    test('below zone 0 → no load', () {
      expect(StrainEngine.zoneIndex(0.1), isNull);
    });
    test('50 % HRR → zone 3 (index 2)', () {
      expect(StrainEngine.zoneIndex(0.5), 2);
    });
    test('99 % HRR → max zone', () {
      expect(StrainEngine.zoneIndex(0.99), 5);
    });

    final base = DayKey.start('2026-07-17');
    final rest = [
      for (var i = 0; i < 10; i++) HrSample(base.add(Duration(minutes: i)), 60),
    ];
    test('near-resting samples → no active zone time, rest time counted', () {
      final acc = StrainEngine.accumulate(rest, restingHr: 58, maxHr: 190);
      expect(acc.zones.fold(0.0, (a, b) => a + b), 0);
      expect(acc.restMin >= 9, isTrue, reason: '${acc.restMin} min');
    });
    test('pure rest day → strain ≈ 0 and tracked time visible', () {
      final r = StrainEngine.dayStrain(
        DayRecord(date: '2026-07-17', hrSamples: rest),
        restingHr: 58,
        config: const StrainConfig(age: 30),
      );
      expect(r.strain < 1, isTrue);
      expect(r.trackedMinutes >= 9, isTrue);
    });
  });

  test('Sprachen: zone labels complete (main.swift:169)', () {
    expect(StrainEngine.zoneLabels.length, StrainEngine.zoneWeights.length);
    expect(StrainEngine.zoneLabels.length, StrainEngine.zoneLowerBounds.length);
  });

  group('Demo-Daten & Engines: strain (main.swift:266-284)', () {
    final demo = pulseDemo();
    test('120 demo days generated', () {
      expect(demo.length, 120);
    });
    const config = StrainConfig(age: 30);
    final strainByDay = {
      for (final e in demo.entries)
        e.key: StrainEngine.dayStrain(
          e.value,
          restingHr: e.value.restingHr,
          config: config,
        ).strain,
    };
    test('all day strains in 0–21', () {
      expect(strainByDay.values.every((s) => s >= 0 && s <= 21), isTrue);
    });
    test('hard days reach strain > 10', () {
      final max = strainByDay.values.reduce((a, b) => a > b ? a : b);
      expect(max > 10, isTrue, reason: 'max $max');
    });
    test('average strain plausible (3–16)', () {
      final avg =
          strainByDay.values.reduce((a, b) => a + b) / strainByDay.length;
      expect(avg > 3 && avg < 16, isTrue, reason: 'avg $avg');
    });
  });

  test('Workout-Strain: at least one in (0, 21] (main.swift:349-359)', () {
    final demo = pulseDemo();
    final keys = demo.keys.toList()..sort();
    var checked = false;
    for (final key in keys.sublist(keys.length - 28)) {
      final record = demo[key]!;
      if (record.workouts.isEmpty) continue;
      final w = record.workouts.first;
      final s = StrainEngine.workoutStrain(
        w,
        record.hrSamples,
        restingHr: record.restingHr,
        config: const StrainConfig(age: 30),
      );
      if (s != null) {
        expect(s > 0 && s <= 21, isTrue, reason: '${w.name} $key: $s');
        checked = true;
        break;
      }
    }
    expect(checked, isTrue);
  });
}
