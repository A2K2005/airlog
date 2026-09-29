// The design-system API additions: ChartFrame.showUnit, one-sided bands,
// BaselineBandChart.xMarks, signed MetricTile deltas, Pressable press
// callbacks, AcwrGauge titles, F.n96, the 48 dp floors, exit curves and the
// shared formatters.

import 'package:airlog/design/design.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_test/flutter_test.dart';

import '../support/fonts.dart';

Widget _host(Widget child, {bool reduce = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(Brightness.dark),
  home: Builder(
    builder: (c) => MediaQuery(
      data: MediaQuery.of(c).copyWith(disableAnimations: reduce),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

HealthMetricStatus _status(HealthMetricKind k, double v, double mean) =>
    HealthMetricStatus(
      kind: k,
      state: BandState.inRange,
      value: v,
      baseline: Baseline(mean: mean, sd: .2, count: 20),
    );

void main() {
  setUpAll(loadAppFonts);

  group('formatters', () {
    test('signed: sign after rounding, real minus', () {
      expect(signed(.04, 1), '0.0');
      expect(signed(.06, 1), '+0.1');
      expect(signed(-.3, 1), '−0.3');
      expect(signed(4, 0, plus: false), '4');
      expect(signed(-2, 0), '−2');
    });

    test('numText, distance, calories, zone ranges', () {
      expect(numText(8.0), '8');
      expect(numText(0.03), '0.03');
      expect(distanceText(5210), '5.21 km');
      expect(distanceText(820), '820 m');
      expect(distanceText(null), isNull);
      expect(kcalText(411.6), '412 kcal');
      expect(kcalText(0), isNull);
      expect(zoneRanges(const [.5, .6, .7, .8, .9]), [
        '50–60 %',
        '60–70 %',
        '70–80 %',
        '80–90 %',
        '90–100 %',
      ]);
      expect(zoneRanges(const [.5, .6], withRest: true).first, '< 50 %');
    });
  });

  group('MetricTile.health', () {
    test('a signed metric signs every number and names its unit', () {
      expect(
        MetricTile.deltaText(HealthMetricKind.skinTemp, .2, .1),
        '+0.1 °C vs usual +0.1',
      );
      expect(
        MetricTile.deltaText(HealthMetricKind.skinTemp, -.3, .1),
        '−0.4 °C vs usual +0.1',
      );
      expect(MetricTile.valueText(HealthMetricKind.skinTemp, -.3), '−0.3');
      expect(MetricTile.valueText(HealthMetricKind.skinTemp, .3), '+0.3');
    });

    test('a zero delta reads "Same as usual"', () {
      expect(
        MetricTile.deltaText(HealthMetricKind.skinTemp, .1, .1),
        'Same as usual',
      );
      // Rounded first: 54.4 vs 53.6 both print 54.
      expect(
        MetricTile.deltaText(HealthMetricKind.restingHr, 54.4, 54.1),
        'Same as usual',
      );
      expect(
        MetricTile.deltaText(HealthMetricKind.hrv, 59, 47),
        '+12 vs usual 47',
      );
    });

    testWidgets('renders the signed delta on the tile', (t) async {
      await t.pumpWidget(
        _host(
          SizedBox(
            width: 180,
            child: MetricTile.health(
              _status(HealthMetricKind.skinTemp, .2, .1),
            ),
          ),
        ),
      );
      expect(find.text('+0.2'), findsOneWidget);
      expect(find.text('+0.1 °C vs usual +0.1'), findsOneWidget);
      expect(find.textContaining('±'), findsNothing);
    });
  });

  group('charts', () {
    testWidgets(
      'ChartFrame.showUnit hides the printed unit, not the spoken one',
      (t) async {
        await t.pumpWidget(
          _host(
            const SizedBox(
              width: 300,
              child: ChartFrame(
                title: 'Resting heart rate',
                unit: 'bpm',
                showUnit: false,
                trailing: Text('54 bpm'),
                child: SizedBox.expand(),
              ),
            ),
          ),
        );
        expect(find.text('bpm'), findsNothing);
        expect(find.text('54 bpm'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('measured in bpm')),
          findsOneWidget,
        );
      },
    );

    testWidgets('one-sided band: floor only, spoken and footnoted', (t) async {
      await t.pumpWidget(
        _host(
          const SizedBox(
            width: 320,
            child: BaselineBandChart(
              title: 'SpO₂',
              unit: '%',
              values: [96, 97, 93],
              lower: 94,
              mean: 96,
              color: C.health,
            ),
          ),
        ),
      );
      expect(
        find.text('Band: your usual range at or above 94 %'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('usual range at or above 94. latest is below the usual range'),
        ),
        findsOneWidget,
      );
      final painter = t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<BaselineBandPainter>()
          .single;
      expect(painter.lower, 94);
      expect(painter.upper, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('xMarks reach the band painter', (t) async {
      await t.pumpWidget(
        _host(
          const SizedBox(
            width: 320,
            child: BaselineBandChart(
              title: 'HRV',
              unit: 'ms',
              values: [40, 42, 50, 52, 51],
              color: C.health,
              xMarks: [.5],
            ),
          ),
        ),
      );
      final painter = t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<BaselineBandPainter>()
          .single;
      expect(painter.marks, [.5]);
    });

    testWidgets('Sparkline draws a one-sided band without error', (t) async {
      await t.pumpWidget(
        _host(
          const SizedBox(
            width: 120,
            child: Sparkline(
              values: [96, 97, 95, 96],
              color: C.health,
              lower: 94,
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('AcwrGauge prints its title in both states', (t) async {
      await t.pumpWidget(
        _host(
          SizedBox(
            width: 320,
            child: Column(
              children: [
                AcwrGauge.fromLoad(
                  const TrainingLoad(
                    acute7: 10,
                    chronic28: 9,
                    ratio: 1.1,
                    state: LoadState.optimal,
                    daysOfHistory: 28,
                  ),
                ),
                const AcwrGauge(ratio: null),
                const AcwrGauge(ratio: 1.1, title: null),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Training load'), findsNWidgets(2));
    });
  });

  group('Pressable press callbacks', () {
    testWidgets('down then up on a tap; down then cancel when dragged off', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        _host(
          Pressable(
            onTap: () => log.add('tap'),
            onPressDown: () => log.add('down'),
            onPressUp: () => log.add('up'),
            onPressCancel: () => log.add('cancel'),
            child: const SizedBox(width: 80, height: 48),
          ),
        ),
      );
      await t.tap(find.byType(Pressable));
      await t.pumpAndSettle();
      expect(log, ['down', 'up', 'tap']);

      log.clear();
      final g = await t.startGesture(t.getCenter(find.byType(Pressable)));
      await t.pump(const Duration(milliseconds: 150));
      await g.moveBy(const Offset(0, 200));
      await g.up();
      await t.pumpAndSettle();
      expect(log, ['down', 'cancel']);
    });

    testWidgets('press callbacks alone make it enabled', (t) async {
      var downs = 0;
      await t.pumpWidget(
        _host(
          Pressable(
            onPressDown: () => downs++,
            child: const SizedBox(width: 80, height: 48),
          ),
        ),
      );
      final g = await t.startGesture(t.getCenter(find.byType(Pressable)));
      await t.pump(const Duration(milliseconds: 150));
      expect(downs, 1);
      await g.up();
    });
  });

  group('48 dp and no day-switch animation', () {
    testWidgets('each segment is a full 48 dp target', (t) async {
      await t.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            child: SegmentedRange(days: 30, onChanged: (_) {}),
          ),
        ),
      );
      for (final e in find.byType(Pressable).evaluate()) {
        final size = (e.renderObject! as RenderBox).size;
        expect(size.height, greaterThanOrEqualTo(S.tap));
        expect(size.width, greaterThanOrEqualTo(S.tap));
      }
    });

    testWidgets('a tappable FreshnessLine is a 48 dp target', (t) async {
      await t.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            child: FreshnessLine(
              now: DateTime(2026, 9, 28, 9),
              lastDataAt: DateTime(2026, 9, 28, 8),
              onTap: () {},
            ),
          ),
        ),
      );
      expect(
        t.getSize(find.byType(Pressable)).height,
        greaterThanOrEqualTo(S.tap),
      );
    });

    testWidgets('the DaySwitcher label swaps without a crossfade', (t) async {
      await t.pumpWidget(
        _host(
          DaySwitcher(date: '2026-09-28', today: '2026-09-28', onShift: (_) {}),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(DaySwitcher),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
    });

    testWidgets('DaySwitcherSkeleton has the switcher\'s height', (t) async {
      await t.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [DaySwitcherSkeleton()],
          ),
        ),
      );
      expect(t.getSize(find.byType(DaySwitcherSkeleton)).height, S.tap);
    });
  });

  group('motion', () {
    testWidgets('exits run a flipped ease-out, never an ease-in', (t) async {
      late BuildContext c;
      await t.pumpWidget(
        _host(
          Builder(
            builder: (ctx) {
              c = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      final sheet = sheetMotion(c);
      expect(sheet.reverseCurve, isA<FlippedCurve>());
      expect(sheet.reverseDuration, lessThan(sheet.duration!));
      final dialog = dialogMotion(c);
      expect(dialog.curve, Motion.enter);
      expect(dialog.reverseCurve, isA<FlippedCurve>());
      expect(dialog.duration!.inMilliseconds, lessThan(300));
      final snack = snackMotion(c);
      expect(snack.reverseDuration, lessThan(snack.duration!));

      await t.pumpWidget(_host(const NumberSwap('72', style: F.n24)));
      final sw = t.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
      expect(sw.switchOutCurve, isA<FlippedCurve>());
    });

    test('F.n96 is a tabular numeral step', () {
      expect(F.n96.fontSize, 96);
      expect(F.n96.fontFamily, F.numerals);
      expect(F.n96.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  group('PreparingNote', () {
    test('shows only while syncing with nothing to show', () {
      const syncing = SyncStatus(phase: SyncPhase.syncing);
      expect(PreparingNote.shows(syncing, hasData: false), isTrue);
      expect(PreparingNote.shows(syncing, hasData: true), isFalse);
      expect(
        PreparingNote.shows(
          const SyncStatus(phase: SyncPhase.idle),
          hasData: false,
        ),
        isFalse,
      );
      expect(PreparingNote.shows(null, hasData: false), isFalse);
    });

    testWidgets('uses the data layer\'s message, else the mode copy', (
      t,
    ) async {
      await t.pumpWidget(
        _host(
          PreparingNote.fromStatus(
            const SyncStatus(phase: SyncPhase.syncing, message: 'Seeding…'),
            demo: true,
          ),
        ),
      );
      expect(find.text('Seeding…'), findsOneWidget);
      await t.pumpWidget(
        _host(
          PreparingNote.fromStatus(
            const SyncStatus(phase: SyncPhase.syncing),
            demo: true,
          ),
        ),
      );
      expect(find.text(PreparingNote.demoTitle), findsOneWidget);
      await t.pumpWidget(
        _host(
          PreparingNote.fromStatus(
            const SyncStatus(phase: SyncPhase.syncing),
            demo: false,
          ),
        ),
      );
      expect(find.text(PreparingNote.liveTitle), findsOneWidget);
    });
  });
}
