import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/diagnostics/diagnostics_screen.dart';
import 'package:airlog/features/diagnostics/diagnostics_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

void main() {
  setUpAll(loadAppFonts);

  test('verdicts split into finding and decision', () {
    final v = splitVerdict(
      'Demo data: HR density: 1 sample / 60 s → full zone-based strain',
    );
    expect(v.finding, 'HR density: 1 sample / 60 s');
    expect(v.decision, 'full zone-based strain');
    expect(v.concern, isFalse);
    expect(
      splitVerdict('No Fitbit Air HRV found → switch to Google Health API')
          .concern,
      isTrue,
    );
  });

  testWidgets(
    'demo: labelled synthetic; probe window and run call the repository',
    (t) async {
      final repo = ScreensBRepo.demo();
      await pumpB(t, const DiagnosticsScreen(), repo: repo);
      await t.pumpAndSettle();
      expect(find.text('Synthetic data'), findsOneWidget);
      await t.tap(find.text('14 days'));
      await t.pumpAndSettle();
      await t.tap(find.text('Run probe (14 days)'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('diagnostics:14'));
      expect(find.text('Decisions'), findsOneWidget);
      expect(find.textContaining('full zone-based strain'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Heart rate'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Synthetic'), findsWidgets);
    },
  );

  testWidgets(
    'live: lists every origin (none singled out by brand), shares the dump',
    (t) async {
      final repo = ScreensBRepo.demo()..report = demoReport(demo: false);
      await repo.setMode(DataMode.live);
      final sharer = RecordingSharer();
      await pumpB(t, const DiagnosticsScreen(), repo: repo, sharer: sharer);
      await t.pumpAndSettle();
      expect(find.text('Synthetic data'), findsNothing);
      await t.tap(find.text('Run probe (7 days)'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('com.fitbit.FitbitMobile').first,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // Device-neutral: no app is flagged by brand; an origin no metric
      // reads is "Available".
      expect(find.text('Fitbit'), findsNothing);
      expect(find.text('Available'), findsWidgets);
      await tapOn(t, find.text('Share JSON dump'));
      await t.pumpAndSettle();
      expect(sharer.shared.single, ['/tmp/airlog-probe.json']);
    },
  );

  testWidgets('no overflow at 320 px and text scale 1.3', (t) async {
    await pumpB(
      t,
      const DiagnosticsScreen(),
      repo: ScreensBRepo.demo(),
      size: kSmall,
      textScale: 1.3,
    );
    await t.pumpAndSettle();
    await tapOn(t, find.text('Run probe (7 days)'));
    await t.pumpAndSettle();
    await scrollThrough(t);
  });

  for (final b in const [Brightness.dark]) { // dark only
    testWidgets('golden demo · ${b.name}', (t) async {
      await pumpB(
        t,
        const DiagnosticsScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Run probe (7 days)'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/diagnostics_${b.name}.png'),
      );
    });

    testWidgets('golden live types · ${b.name}', (t) async {
      final repo = ScreensBRepo.demo()..report = demoReport(demo: false);
      await repo.setMode(DataMode.live);
      await pumpB(t, const DiagnosticsScreen(), repo: repo, brightness: b);
      await t.pumpAndSettle();
      await t.tap(find.text('Run probe (7 days)'));
      await t.pumpAndSettle();
      await t.drag(find.byType(Scrollable).first, const Offset(0, -760));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/diagnostics_live_${b.name}.png',
        ),
      );
    });
  }
}
