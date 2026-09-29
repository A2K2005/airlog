import 'package:airlog/design/design.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/trends/trends_screen.dart';
import 'package:airlog/features/trends/trends_view_model.dart';
import 'package:airlog/features/trends/widgets/trends_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets(
    'demo: charts, load gauge, averages; no arrows when nothing is significant',
    (t) async {
      final repo = ScreensBRepo.demo();
      await pumpB(t, const TrendsScreen(), repo: repo, tab: true);
      await t.pumpAndSettle();
      expect(find.text('Recovery and strain'), findsOneWidget);
      expect(find.text('Training load'), findsOneWidget);
      // Every drawn arrow is backed by a significant engine trend.
      for (final a in t.widgetList<TrendArrow>(find.byType(TrendArrow))) {
        if (a.trend != null && !a.trend!.significant) {
          expect(TrendArrow.visible(a.trend), isFalse);
        }
      }
      await t.scrollUntilVisible(
        find.text('Averages'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await t.scrollUntilVisible(
        find.textContaining('Mann–Kendall'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Mann–Kendall'), findsOneWidget);
    },
  );

  test('a change of HRV source becomes a mark at its day', () {
    final keys = DayKey.range(DayKey.add(kToday, -29), kToday);
    final records = [
      for (var i = 0; i < keys.length; i++)
        DayRecord(
          date: keys[i],
          hrvRmssd: 45 + (i % 4).toDouble(),
          provenance: {
            Metric.hrv: Provenance(
              i < 20 ? SourceKind.healthConnect : SourceKind.googleHealthApi,
              i < 20 ? 'hc_sleep_mean_rmssd' : 'ghapi_deep_sleep_rmssd',
            ),
          },
        ),
    ];
    final results = Engine.computeRange(records, now: kNow);
    final days = [
      for (var i = 0; i < records.length; i++)
        DayBundle(records[i], results[i]),
    ];
    final view = buildTrendsView(
      TrendsData(latest: kToday, today: kToday, keys: keys, days: days),
      30,
    );
    final hrv = view.metrics.first;
    expect(hrv.sourceChanges, [keys[20]]);
    expect(hrv.sourceChangeMarks.single, closeTo(20 / 29, 1e-9));
  });

  testWidgets('7 days of noise: no arrows, and the footnote says why', (
    t,
  ) async {
    final repo = ScreensBRepo.demo()
      ..rangeOverride = trendingDays()
      ..latestOverride = kToday;
    await pumpB(t, const TrendsScreen(), repo: repo, tab: true);
    await t.pumpAndSettle();
    await t.tap(find.text('7D'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Resting heart rate'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final rhr = t
        .widgetList<MetricTrendCard>(find.byType(MetricTrendCard))
        .where((c) => c.metric.title == 'Resting heart rate')
        .single;
    expect(rhr.metric.trend.significant, isFalse);
    expect(TrendArrow.visible(rhr.metric.trend), isFalse);
    // No arrow is built at all (an empty trailing slot would shift the unit).
    expect(
      t
          .widgetList<TrendArrow>(find.byType(TrendArrow))
          .where((a) => a.metric == 'Resting heart rate'),
      isEmpty,
    );
  });

  testWidgets('a significant rise gets an arrow; noise does not', (t) async {
    final days = trendingDays();
    final hrv = [for (final d in days) d.record.hrvRmssd];
    final rhr = [for (final d in days) d.record.restingHr];
    expect(Engine.trend(hrv).significant, isTrue);
    expect(Engine.trend(rhr).significant, isFalse);
    final repo = ScreensBRepo.demo()
      ..rangeOverride = days
      ..latestOverride = kToday;
    await pumpB(t, const TrendsScreen(), repo: repo, tab: true);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Heart rate variability'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final arrows = t
        .widgetList<TrendArrow>(find.byType(TrendArrow))
        .where((a) => TrendArrow.visible(a.trend))
        .map((a) => a.metric)
        .toList();
    expect(arrows, contains('Heart rate variability'));
    expect(arrows, isNot(contains('Resting heart rate')));
  });

  testWidgets('range switch re-slices without reloading', (t) async {
    final repo = ScreensBRepo.demo();
    await pumpB(t, const TrendsScreen(), repo: repo, tab: true);
    await t.pumpAndSettle();
    await t.tap(find.text('7D'));
    await t.pumpAndSettle();
    expect(find.text('7D'), findsOneWidget);
    await t.tap(find.text('90D').first);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('empty store', (t) async {
    final repo = ScreensBRepo.demo()..emptyStore = true;
    await pumpB(t, const TrendsScreen(), repo: repo, tab: true);
    await t.pumpAndSettle();
    expect(find.text('No trends yet'), findsOneWidget);
  });

  testWidgets('no overflow at 320 px and text scale 1.3', (t) async {
    final repo = ScreensBRepo.demo();
    await pumpB(
      t,
      const TrendsScreen(),
      repo: repo,
      tab: true,
      size: kSmall,
      textScale: 1.3,
    );
    await t.pumpAndSettle();
    await scrollThrough(t);
  });

  for (final b in const [Brightness.dark]) { // dark only
    testWidgets('golden · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo();
      await pumpB(
        t,
        const TrendsScreen(),
        repo: repo,
        tab: true,
        brightness: b,
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/trends_${b.name}.png'),
      );
    });

    testWidgets('golden body · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo();
      await pumpB(
        t,
        const TrendsScreen(),
        repo: repo,
        tab: true,
        brightness: b,
      );
      await t.pumpAndSettle();
      await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/trends_body_${b.name}.png'),
      );
    });
  }
}
