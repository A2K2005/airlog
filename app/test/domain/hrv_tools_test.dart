// RR artefact filter, RMSSD, Baevsky stress index, HRR-60. [ours]

import 'dart:math' as math;

import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/hrv_tools.dart';
import 'package:airlog/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

double naiveRmssd(List<double> rr) {
  var s = 0.0;
  for (var i = 1; i < rr.length; i++) {
    s += math.pow(rr[i] - rr[i - 1], 2);
  }
  return math.sqrt(s / (rr.length - 1));
}

void main() {
  final alternating = [for (var i = 0; i < 40; i++) i.isEven ? 800.0 : 820.0];

  group('RMSSD from RR', () {
    test('known series: alternating 800/820 ms → 20 ms', () {
      expect(Engine.rmssdFromRr(alternating), closeTo(20, 1e-9));
    });

    test('artefacts are removed and never differenced across', () {
      final rr = [...alternating];
      rr.insertAll(10, [400, 1300]); // ectopic short + compensatory long
      rr.insert(25, 250); // below 300 ms
      rr.insert(30, 2500); // above 2000 ms
      expect(naiveRmssd(rr) > 100, isTrue, reason: 'unfiltered is inflated');
      expect(Engine.rmssdFromRr(rr), closeTo(20, 1e-9));
      final mask = HrvTools.cleanMask(rr);
      expect(mask.where((m) => !m).length, 4);
    });

    test('fewer than 30 clean intervals → null', () {
      expect(Engine.rmssdFromRr(alternating.sublist(0, 29)), isNull);
      expect(Engine.rmssdFromRr(const []), isNull);
      expect(Engine.rmssdFromRr([for (var i = 0; i < 40; i++) 100.0]), isNull);
    });
  });

  group('Baevsky stress index', () {
    // 10 × 780, 40 × 800, 10 × 820 ms, interleaved.
    final rr = <double>[
      for (var i = 0; i < 10; i++) ...[780, 800, 800, 800, 800, 820],
    ];
    test('hand-computed value', () {
      // 50 ms bins: 780 → [750,800), 800 and 820 → [800,850) = modal bin.
      const amo = 50 / 60 * 100; // %
      const mo = 0.825; // s, modal-bin centre
      const mxdmn = 0.040; // s
      expect(rr.length, 60);
      expect(Engine.baevskyStress(rr), closeTo(amo / (2 * mo * mxdmn), 1e-9));
    });
    test('< 60 intervals or zero range → null', () {
      expect(Engine.baevskyStress(rr.sublist(0, 59)), isNull);
      expect(
        Engine.baevskyStress([for (var i = 0; i < 80; i++) 800.0]),
        isNull,
      );
    });
  });

  group('HRR-60 (Cole 1999)', () {
    final end = DateTime(2026, 8, 10, 18, 45);
    List<HrSample> recovery() => [
      for (var s = -30; s <= 90; s++)
        HrSample(end.add(Duration(seconds: s)), s <= 0 ? 160 : 160 - 0.5 * s),
    ];
    test('drop over 60 s', () {
      expect(Engine.hrr60(recovery(), end), closeTo(30, 1e-9));
    });
    test('nearest sample within ±10 s is used', () {
      final samples = recovery()
        ..removeWhere((x) {
          final d = x.t.difference(end).inSeconds;
          return d > 50 && d != 68;
        });
      // +68 s (8 s away) beats +50 s (10 s away): 160 − (160 − 0.5·68) = 34.
      expect(Engine.hrr60(samples, end), closeTo(34, 1e-9));
    });
    test('no sample within ±10 s of end + 60 s → null', () {
      final samples = recovery()
        ..removeWhere((x) {
          final d = x.t.difference(end).inSeconds;
          return d >= 49 && d <= 71;
        });
      expect(Engine.hrr60(samples, end), isNull);
      expect(Engine.hrr60(const [], end), isNull);
    });
  });
}
