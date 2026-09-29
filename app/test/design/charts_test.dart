// Charts: never throw, never paint NaN, and axes that humans can read.

import 'package:airlog/design/design.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fonts.dart';

/// A canvas that fails on any non-finite coordinate it is handed.
class _FiniteCanvas implements Canvas {
  int calls = 0;

  static void _check(Object? a, String where) {
    bool bad(double v) => !v.isFinite;
    if (a is double && bad(a)) fail('non-finite double in $where');
    if (a is Offset && (bad(a.dx) || bad(a.dy))) {
      fail('non-finite Offset in $where');
    }
    if (a is Rect &&
        (bad(a.left) || bad(a.top) || bad(a.right) || bad(a.bottom))) {
      fail('non-finite Rect in $where');
    }
    if (a is RRect) _check(a.outerRect, where);
    if (a is Path) {
      final b = a.getBounds();
      if (!b.isEmpty) _check(b, where);
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) {
    calls++;
    for (final a in i.positionalArguments) {
      _check(a, i.memberName.toString());
    }
    return null;
  }
}

const _series = <String, List<double?>>{
  'empty': [],
  'one': [52],
  'all null': [null, null],
  'non-finite': [double.nan, double.infinity, double.negativeInfinity],
  'constant zero': [0, 0, 0, 0],
  'gappy': [50, null, 52, null, null, 55, 54],
};

void main() {
  setUpAll(loadAppFonts);

  group('painters never paint a non-finite coordinate', () {
    const p = P(true);
    const sizes = [Size(0, 0), Size(1, 1), Size(320, 120)];
    final axis = AxisSpec.of([40, 60])!;
    _series.forEach((name, d) {
      test(name, () {
        final finite = [for (final v in d) v ?? double.nan];
        final painters = <CustomPainter>[
          LineChart(d, C.strain),
          LineChart(d, C.strain, axis: axis, fill: true, dots: true),
          Bars(d, C.strain),
          Bars(d, C.strain, axis: axis),
          Ring(
            d.isEmpty ? double.nan : (d.first ?? double.nan),
            C.strain,
            p.track,
          ),
          DashedRing(
            d.isEmpty ? double.nan : (d.first ?? 0),
            C.strain,
            p.track,
          ),
          ZoneBar(finite, p),
          NightStack([d, d], [C.strain, C.sleep]),
          HeatMap([d, d], C.health, p.track),
          Actogram([finite, null], C.sleep),
          DayLanes(p: p, movement: d, gaps: const [(double.nan, .5)]),
          BaselineBandPainter(
            values: d,
            axis: axis,
            line: C.health,
            band: C.health,
            meanInk: C.neutral,
            knockout: C.black,
            lower: 45,
            upper: 55,
            mean: double.nan,
            highlight: d.length - 1,
          ),
          SparklinePainter(
            values: d,
            color: C.health,
            band: C.health,
            knockout: C.black,
            lower: double.nan,
            upper: 50,
          ),
          AcwrPainter(
            ratio: d.isEmpty ? double.nan : (d.first ?? 1),
            active: null,
            p: p,
          ),
        ];
        for (final painter in painters) {
          for (final s in sizes) {
            painter.paint(_FiniteCanvas(), s);
          }
        }
      });
    });

    test('hypnogram and zone timeline with degenerate windows', () {
      final t0 = DateTime(2026, 9, 28);
      for (final spans in [
        <StageSpan>[],
        [StageSpan(SleepStage.deep, t0, t0)],
        [StageSpan(SleepStage.unknown, t0, t0.add(const Duration(hours: 1)))],
        [StageSpan(SleepStage.rem, t0.add(const Duration(hours: 1)), t0)],
      ]) {
        for (final s in const [Size(0, 0), Size(320, 100)]) {
          Hypnogram(spans, const P(false)).paint(_FiniteCanvas(), s);
        }
      }
      final axis = AxisSpec.of([50, 150])!;
      for (final hr in [
        <HrSample>[],
        [HrSample(t0, 60)],
        [HrSample(t0, 60), HrSample(t0, 61)],
      ]) {
        ZoneTimelinePainter(
          samples: hr,
          start: t0,
          end: t0.add(const Duration(hours: 1)),
          floors: const [100, 120, 140, 160, 180],
          axis: axis,
          zoneInk: List.filled(6, C.strain),
          floorInk: C.neutral,
          blockInk: C.strain,
          restInk: C.sleep,
          maxGapMinutes: 10,
        ).paint(_FiniteCanvas(), const Size(320, 120));
        ZoneTimelinePainter(
          samples: hr,
          start: t0,
          end: t0, // zero-length window
          floors: const [],
          axis: axis,
          zoneInk: List.filled(6, C.strain),
          floorInk: C.neutral,
          blockInk: C.strain,
          restInk: C.sleep,
          maxGapMinutes: 10,
        ).paint(_FiniteCanvas(), const Size(320, 120));
      }
    });
  });

  group('chart widgets build for every degenerate series', () {
    final t0 = DateTime(2026, 9, 27);
    _series.forEach((name, d) {
      for (final width in const [0.0, 320.0]) {
        testWidgets('$name at ${width.toInt()} px', (t) async {
          await t.pumpWidget(
            MaterialApp(
              theme: buildTheme(Brightness.dark),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        BaselineBandChart(
                          title: 'HRV',
                          unit: 'ms',
                          values: d,
                          color: C.health,
                          mean: 50,
                          lower: 45,
                          upper: 55,
                        ),
                        DualAxisChart.recoveryStrain(recovery: d, strain: d),
                        Sparkline(values: d, color: C.health),
                        AcwrGauge(ratio: d.isEmpty ? null : d.first),
                        ScatterConsistency(
                          nights: [
                            for (final v in d)
                              v == null || !v.isFinite
                                  ? null
                                  : NightWindow(
                                      t0.add(const Duration(hours: 23)),
                                      t0.add(
                                        Duration(
                                          hours: 30,
                                          minutes: v.round() % 60,
                                        ),
                                      ),
                                    ),
                          ],
                        ),
                        ZoneTimeline(
                          samples: [
                            for (var i = 0; i < d.length; i++)
                              if (d[i] != null)
                                HrSample(t0.add(Duration(minutes: i)), d[i]!),
                          ],
                          start: t0,
                          end: t0.add(const Duration(hours: 1)),
                          zoneFloors: const [100, 120, 140, 160, 180],
                        ),
                        ContributionBars(
                          color: C.recGreen,
                          items: [
                            for (final v in d)
                              Contribution(
                                label: 'x',
                                points: v ?? double.nan,
                                maxPoints: 40,
                              ),
                          ],
                          total: d.isEmpty ? null : d.first,
                        ),
                        const HypnogramChart(stages: []),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        });
      }
    });
  });

  group('AxisSpec', () {
    test('null for nothing finite (the signal for an empty state)', () {
      expect(AxisSpec.of([]), isNull);
      expect(AxisSpec.of([double.nan, double.infinity, null]), isNull);
    });

    test('rounds out to human steps and covers the data', () {
      final a = AxisSpec.of([52.3, 57.8, 61.1])!;
      expect(a.min, lessThanOrEqualTo(52.3));
      expect(a.max, greaterThanOrEqualTo(61.1));
      for (final v in a.tickValues) {
        expect(
          v,
          closeTo(v.roundToDouble(), 1e-9),
          reason: 'axisInt ticks are integers',
        );
      }
      expect(a.t(double.nan), 0);
      expect(a.t(-1000), 0);
      expect(a.t(1000), 1);
    });

    test('flat series get a band around them, zero stays on the floor', () {
      final flat = AxisSpec.of([60, 60, 60])!;
      expect(flat.min, lessThan(60));
      expect(flat.max, greaterThan(60));
      final zero = AxisSpec.of([0, 0])!;
      expect(zero.min, 0);
    });

    test('formats', () {
      expect(axisHm(450), '7h 30m');
      expect(axisHm(45), '45m');
      expect(clockHm(-30), '23:30');
      expect(clockHm(1440 + 65), '01:05');
      expect(axisInt(double.nan), '');
    });

    test('gaps break runs and an isolated reading is a run of one', () {
      final runs = minMaxRuns([1, 2, null, 3, null, 4, 5], 100, (v) => v);
      expect(runs.map((r) => r.length).toList(), [2, 1, 2]);
    });

    test('long series are reduced to ≤ 2 points per pixel', () {
      final d = [for (var i = 0; i < 30000; i++) (i % 97).toDouble()];
      expect(minMaxColumns(d, 300, (v) => v).length, lessThanOrEqualTo(600));
    });
  });

  group('spoken summaries', () {
    test('ChartFrame says title, unit, latest, range and the x range', () {
      const f = ChartFrame(
        title: 'Resting heart rate',
        unit: 'bpm',
        series: [56, 55, 54],
        xLabels: ['1 Sep', 'Today'],
        child: SizedBox(),
      );
      final s = f.spokenLabel();
      expect(s, contains('Resting heart rate'));
      expect(s, contains('measured in bpm'));
      expect(s, contains('Latest 54'));
      expect(s, contains('from 1 Sep to Today'));
    });

    test('an explicit semanticsLabel wins', () {
      const f = ChartFrame(
        title: 'x',
        unit: 'y',
        semanticsLabel: 'custom',
        child: SizedBox(),
      );
      expect(f.spokenLabel(), 'custom');
    });

    testWidgets('BaselineBandChart speaks the band verdict', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(
            body: BaselineBandChart(
              title: 'HRV',
              unit: 'ms',
              values: [45, 47, 62],
              color: C.health,
              mean: 47,
              lower: 40,
              upper: 54,
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp('latest is above the usual range')),
        findsOneWidget,
      );
    });
  });

  group('domain helpers used by the charts', () {
    test('zone of a bpm against caller floors', () {
      const floors = <double>[120, 134, 147, 161, 174];
      expect(ZoneTimeline.zoneOf(80, floors), 0);
      expect(ZoneTimeline.zoneOf(120, floors), 1);
      expect(ZoneTimeline.zoneOf(200, floors), 5);
    });

    test('bed/wake minutes since noon', () {
      expect(ScatterConsistency.sinceNoon(DateTime(2026, 9, 27, 23)), 660);
      expect(ScatterConsistency.sinceNoon(DateTime(2026, 9, 28, 7)), 1140);
    });

    test('ACWR scale clamps to 0.5–2.0 and bands follow LoadState', () {
      expect(AcwrGauge.frac(0.1), 0);
      expect(AcwrGauge.frac(5), 1);
      expect([for (final b in AcwrGauge.bands) b.$3], LoadState.values);
    });

    test('recovery colours come from the domain zones', () {
      expect(DomainColors.recovery(67), C.recGreen);
      expect(DomainColors.recovery(66), C.recYellow);
      expect(DomainColors.recovery(33), C.recRed);
    });
  });
}
