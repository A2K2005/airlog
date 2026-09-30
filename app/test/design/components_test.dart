// Component behaviour: states, semantics, motion, and no overflow at 320 px
// or at 1.3× text for anything in the gallery.

import 'package:airlog/design/design.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart' show SyncPhase, SyncStatus;
import 'package:airlog/domain/results.dart';
import 'package:airlog/features/gallery/gallery_screen.dart';
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_test/flutter_test.dart';

import '../support/fonts.dart';

Widget _host(
  Widget child, {
  Brightness b = Brightness.dark,
  bool reduce = false,
  double scale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(b),
  home: Builder(
    builder: (c) => MediaQuery(
      data: MediaQuery.of(c).copyWith(
        disableAnimations: reduce,
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

double _ringValue(WidgetTester t) {
  final paints = t.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(ScoreRing),
      matching: find.byType(CustomPaint),
    ),
  );
  for (final cp in paints) {
    final p = cp.painter;
    if (p is Ring) return p.v;
    if (p is DashedRing) return p.v;
  }
  throw StateError('no ring painter');
}

void main() {
  setUpAll(loadAppFonts);
  setUp(ScoreRing.resetPlayed);

  group('no overflow: every gallery section', () {
    for (final (w, scale) in const [(320.0, 1.0), (320.0, 1.3), (412.0, 1.3)]) {
      for (final b in const [Brightness.dark]) {
        // dark only
        for (final s in GallerySection.values) {
          testWidgets('${s.name} · ${w.toInt()} px · ${scale}x · ${b.name}', (
            t,
          ) async {
            // Tall enough that the ListView builds every case.
            t.view.physicalSize = Size(w, 4000);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            await t.pumpWidget(
              MaterialApp(
                theme: buildTheme(b),
                home: Builder(
                  builder: (c) => MediaQuery(
                    data: MediaQuery.of(c)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: GalleryScreen(section: s, animate: false),
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  });

  group('Pressable', () {
    testWidgets('taps, scales to 0.97 while held, meets 48 dp, is a button', (
      t,
    ) async {
      var taps = 0;
      await t.pumpWidget(
        _host(
          Pressable(
            onTap: () => taps++,
            semanticLabel: 'Go',
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      final size = t.getSize(find.byType(Pressable));
      expect(size.width, greaterThanOrEqualTo(S.tap));
      expect(size.height, greaterThanOrEqualTo(S.tap));
      final g = await t.startGesture(t.getCenter(find.byType(Pressable)));
      await t.pump(); // the ticker's first frame
      await t.pump(const Duration(milliseconds: 200));
      final scale = t.widget<ScaleTransition>(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(ScaleTransition),
        ),
      );
      expect(scale.scale.value, closeTo(.97, .001));
      await g.up();
      await t.pumpAndSettle();
      expect(scale.scale.value, 1);
      expect(taps, 1);
      expect(
        t.getSemantics(find.byType(Pressable)),
        matchesSemantics(isButton: true, hasTapAction: true, label: 'Go'),
      );
    });

    testWidgets('reduced motion: an opacity dip, no scale', (t) async {
      await t.pumpWidget(
        _host(Pressable(onTap: () {}, child: const Text('x')), reduce: true),
      );
      expect(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
    });
  });

  group('ScoreRing', () {
    testWidgets('speaks its value and state', (t) async {
      await t.pumpWidget(
        _host(
          const ScoreRing(
            label: 'Recovery',
            value: 72,
            unit: '%',
            color: C.recGreen,
          ),
        ),
      );
      expect(find.bySemanticsLabel('Recovery 72 percent'), findsOneWidget);
      await t.pumpWidget(
        _host(
          const ScoreRing(
            label: 'Recovery',
            value: 58,
            unit: '%',
            color: C.recYellow,
            state: RingState.provisional,
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Recovery 58 percent, provisional'),
        findsOneWidget,
      );
      expect(find.text('Provisional'), findsOneWidget);
    });

    testWidgets('no data never shows a number', (t) async {
      await t.pumpWidget(
        _host(
          const ScoreRing(
            label: 'Sleep',
            value: 80,
            color: C.sleep,
            state: RingState.noData,
          ),
        ),
      );
      expect(find.text('No data'), findsOneWidget);
      expect(find.text('80'), findsNothing);
      expect(_ringValue(t), 0);
      expect(find.bySemanticsLabel('Sleep: no data'), findsOneWidget);
    });

    testWidgets('calibrating fills to progress with a segmented ring', (
      t,
    ) async {
      await t.pumpWidget(
        _host(
          const ScoreRing(
            label: 'Recovery',
            color: C.recGreen,
            state: RingState.calibrating,
            progress: .5,
            value: 70,
          ),
        ),
      );
      expect(_ringValue(t), .5);
      expect(find.text('70'), findsNothing);
    });

    testWidgets('sweeps once per playKey, then draws immediately', (t) async {
      await t.pumpWidget(
        _host(
          const ScoreRing(
            label: 'Recovery',
            value: 80,
            color: C.recGreen,
            playKey: 'recovery:2026-09-28',
          ),
        ),
      );
      expect(_ringValue(t), 0);
      await t.pump(const Duration(milliseconds: 350));
      expect(_ringValue(t), inExclusiveRange(0, .8));
      await t.pumpAndSettle();
      expect(_ringValue(t), closeTo(.8, 1e-9));

      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        _host(
          const ScoreRing(
            label: 'Recovery',
            value: 80,
            color: C.recGreen,
            playKey: 'recovery:2026-09-28',
          ),
        ),
      );
      expect(_ringValue(t), closeTo(.8, 1e-9));
    });

    // The real screen sequence: AsyncValue loading → data in the same slot.
    Widget ring(RingState s, {String? key}) => _host(
      ScoreRing(
        label: 'Recovery',
        value: s == RingState.loading ? null : 70,
        color: C.recGreen,
        state: s,
        playKey: key,
      ),
    );

    testWidgets('loading → measured with a fresh key sweeps from 0', (t) async {
      await t.pumpWidget(ring(RingState.loading, key: 'k1'));
      await t.pumpWidget(ring(RingState.measured, key: 'k1'));
      expect(_ringValue(t), 0);
      await t.pump(const Duration(milliseconds: 350));
      expect(_ringValue(t), inExclusiveRange(0, .7));
      await t.pumpAndSettle();
      expect(_ringValue(t), closeTo(.7, 1e-9));
    });

    testWidgets('loading → measured with a played key is drawn at once', (
      t,
    ) async {
      await t.pumpWidget(ring(RingState.loading, key: 'k2'));
      await t.pumpWidget(ring(RingState.measured, key: 'k2'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox()); // remount
      await t.pumpWidget(ring(RingState.loading, key: 'k2'));
      await t.pumpWidget(ring(RingState.measured, key: 'k2'));
      expect(_ringValue(t), closeTo(.7, 1e-9));
    });

    testWidgets('loading → measured without a key is drawn at once', (t) async {
      await t.pumpWidget(ring(RingState.loading));
      await t.pumpWidget(ring(RingState.measured));
      expect(_ringValue(t), closeTo(.7, 1e-9));
    });

    testWidgets('a later value change morphs from the current arc', (t) async {
      await t.pumpWidget(ring(RingState.measured));
      await t.pumpWidget(
        _host(const ScoreRing(label: 'Recovery', value: 30, color: C.recGreen)),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(_ringValue(t), inExclusiveRange(.3, .7));
      await t.pumpAndSettle();
      expect(_ringValue(t), closeTo(.3, 1e-9));
    });

    testWidgets('reduced motion: no sweep', (t) async {
      await t.pumpWidget(
        _host(
          const ScoreRing(
            label: 'Recovery',
            value: 60,
            color: C.recGreen,
            playKey: 'rm',
          ),
          reduce: true,
        ),
      );
      await t.pump();
      expect(_ringValue(t), closeTo(.6, 1e-9));
    });
  });

  group('TrendArrow renders only when significant', () {
    testWidgets('noise and flat: nothing', (t) async {
      for (final tr in const [
        TrendResult(
          direction: TrendDirection.up,
          slopePerDay: 1,
          significant: false,
          n: 20,
        ),
        TrendResult(
          direction: TrendDirection.flat,
          slopePerDay: 0,
          significant: true,
          n: 20,
        ),
        null,
      ]) {
        await t.pumpWidget(_host(TrendArrow(trend: tr, upIsGood: true)));
        expect(find.byType(Icon), findsNothing);
      }
    });

    testWidgets('significant: an arrow with a spoken direction', (t) async {
      await t.pumpWidget(
        _host(
          const TrendArrow(
            trend: TrendResult(
              direction: TrendDirection.down,
              slopePerDay: -1,
              significant: true,
              n: 30,
            ),
            upIsGood: false,
            metric: 'Resting HR',
          ),
        ),
      );
      expect(find.byIcon(Icons.south_east_rounded), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('Resting HR falling, a significant change'),
        ),
        findsOneWidget,
      );
    });
  });

  group('honesty components', () {
    testWidgets(
      'StatusCard.fromNote: title, body, fix; action only with a callback',
      (t) async {
        const note = StatusNote(
          metric: 'hrv',
          title: 'No HRV',
          body: 'Not reported.',
          fix: 'Wear it',
        );
        await t.pumpWidget(
          _host(StatusCard.fromNote(note, actionLabel: 'Help')),
        );
        expect(find.text('No HRV'), findsOneWidget);
        expect(find.text('Wear it'), findsOneWidget);
        expect(find.text('Help'), findsNothing);
        await t.pumpWidget(
          _host(
            StatusCard.fromNote(note, actionLabel: 'Help', onAction: () {}),
          ),
        );
        expect(find.text('Help'), findsOneWidget);
      },
    );

    testWidgets('FreshnessLine wording and staleness', (t) async {
      final now = DateTime(2026, 9, 28, 9);
      final fresh = FreshnessLine(
        now: now,
        lastDataAt: now.subtract(const Duration(minutes: 12)),
        lastSyncAt: now.subtract(const Duration(minutes: 2)),
      );
      expect(
        fresh.text,
        'Last data from your tracker 12 min ago · synced 2 min ago',
      );
      expect(fresh.stale, isFalse);
      final none = FreshnessLine(now: now);
      expect(none.text, 'No data from your tracker yet · not synced yet');
      expect(none.stale, isTrue);
      final syncing = FreshnessLine(
        now: now,
        lastDataAt: now.subtract(const Duration(hours: 7)),
        syncing: true,
      );
      expect(syncing.text, 'Last data from your tracker 7 h ago · syncing…');
      expect(syncing.stale, isTrue);
      await t.pumpWidget(_host(fresh));
      expect(find.bySemanticsLabel(fresh.text), findsOneWidget);
    });

    testWidgets('FreshnessLine never shows a raw exception (QA-07)', (t) async {
      final now = DateTime(2026, 9, 28, 9);
      final s = SyncStatus(
        phase: SyncPhase.error,
        lastDataAt: now.subtract(const Duration(minutes: 10)),
        lastSyncAt: now.subtract(const Duration(minutes: 5)),
        message: 'DatabaseException(database_closed 1)',
        lastDataByApp: {'Samsung Health': now},
      );
      final line = FreshnessLine.fromStatus(s, now: now);
      expect(line.text, contains(FreshnessLine.readError));
      expect(line.text, isNot(contains('DatabaseException')));
      final perApp = FreshnessLine.perApp(s, now: now);
      for (final w in perApp.cast<FreshnessLine>()) {
        expect(w.text, isNot(contains('DatabaseException')));
        expect(w.text, contains(FreshnessLine.readError));
      }
      await t.pumpWidget(_host(line));
      expect(find.textContaining('DatabaseException'), findsNothing);
    });

    testWidgets('CalibrationBanner', (t) async {
      await t.pumpWidget(
        _host(CalibrationBanner.of(const Calibration(haveNights: 9))),
      );
      expect(find.text('Baseline night 9 of 14'), findsOneWidget);
      expect(
        CalibrationBanner.shouldShow(const Calibration(haveNights: 14)),
        isFalse,
      );
      expect(
        CalibrationBanner.shouldShow(const Calibration(haveNights: 3)),
        isTrue,
      );
    });

    testWidgets('DemoBadge says what it means', (t) async {
      await t.pumpWidget(_host(const DemoBadge()));
      expect(find.bySemanticsLabel(RegExp('synthetic')), findsOneWidget);
    });
  });

  group('MetricTile', () {
    testWidgets('health mapping: value, band, delta, provenance', (t) async {
      await t.pumpWidget(
        _host(
          SizedBox(
            width: 180,
            child: MetricTile.health(
              const HealthMetricStatus(
                kind: HealthMetricKind.hrv,
                state: BandState.above,
                value: 59,
                baseline: Baseline(mean: 47, sd: 4, count: 20),
                provenance: Provenance(
                  SourceKind.googleHealthApi,
                  'ghapi_deep_sleep_rmssd',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('59'), findsOneWidget);
      expect(find.text('Above your range'), findsOneWidget);
      expect(find.text('+12 vs usual 47'), findsOneWidget);
      expect(find.text('Deep-sleep RMSSD · Enhanced mode'), findsOneWidget);
    });

    testWidgets('skin temperature is signed; no value says No data', (t) async {
      await t.pumpWidget(
        _host(
          SizedBox(
            width: 180,
            child: MetricTile.health(
              const HealthMetricStatus(
                kind: HealthMetricKind.skinTemp,
                state: BandState.inRange,
                value: .3,
              ),
            ),
          ),
        ),
      );
      expect(find.text('+0.3'), findsOneWidget);
      await t.pumpWidget(
        _host(
          SizedBox(
            width: 180,
            child: MetricTile.health(
              const HealthMetricStatus(
                kind: HealthMetricKind.restingHr,
                state: BandState.noData,
              ),
            ),
          ),
        ),
      );
      expect(find.text('No data'), findsOneWidget);
    });
  });

  group('controls', () {
    testWidgets('DaySwitcher: labels, and next is disabled at the latest day', (
      t,
    ) async {
      final shifts = <int>[];
      await t.pumpWidget(
        _host(
          DaySwitcher(
            date: '2026-09-28',
            latest: '2026-09-28',
            today: '2026-09-28',
            onShift: shifts.add,
          ),
        ),
      );
      expect(find.text('Today'), findsOneWidget);
      await t.tap(find.byIcon(Icons.chevron_right_rounded));
      await t.tap(find.byIcon(Icons.chevron_left_rounded));
      await t.pumpAndSettle();
      expect(shifts, [-1]);
      await t.pumpWidget(
        _host(
          DaySwitcher(
            date: '2026-09-21',
            today: '2026-09-28',
            onShift: shifts.add,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Mon 21 Sep'), findsOneWidget);
      expect(shortDay('2026-09-28'), 'Mon 28 Sep');
    });

    testWidgets('SegmentedRange reports the tapped window', (t) async {
      int? picked;
      await t.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            child: SegmentedRange(days: 30, onChanged: (d) => picked = d),
          ),
        ),
      );
      await t.tap(find.text('90D'));
      await t.pumpAndSettle();
      expect(picked, 90);
    });

    testWidgets('showExplainSheet opens, with and without motion', (t) async {
      for (final reduce in [false, true]) {
        await t.pumpWidget(const SizedBox()); // fresh navigator each pass
        await t.pumpWidget(
          _host(
            Builder(
              builder: (c) => AppButton(
                label: 'Explain',
                onTap: () => showExplainSheet<void>(
                  c,
                  title: 'Recovery',
                  children: const [
                    ExplainSection(title: 'Formula', formula: 'a = b'),
                  ],
                ),
              ),
            ),
            reduce: reduce,
          ),
        );
        await t.tap(find.text('Explain'));
        await t.pumpAndSettle();
        expect(find.text('Recovery'), findsOneWidget);
        expect(find.text('a = b'), findsOneWidget);
        expect(find.textContaining('Not medical advice'), findsOneWidget);
      }
    });

    test('ProvenanceChip.describe', () {
      expect(
        ProvenanceChip.describe(
          const Provenance(
            SourceKind.googleHealthApi,
            'ghapi_deep_sleep_rmssd',
          ),
        ),
        'Deep-sleep RMSSD · Enhanced mode',
      );
      expect(
        ProvenanceChip.describe(
          const Provenance(SourceKind.healthConnect, 'hc_sleep_mean_hr'),
        ),
        'Sleep mean HR · Health Connect',
      );
    });
  });
}
