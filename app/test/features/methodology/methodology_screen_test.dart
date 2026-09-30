import 'package:airlog/app/route_names.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/recovery.dart';
import 'package:airlog/domain/results.dart';
import 'package:airlog/features/methodology/methodology_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

/// Scrolls to the ⓘ spoken as [label] and opens its sheet.
Future<void> openInfo(WidgetTester t, String label) async {
  final f = find.bySemanticsLabel(label);
  await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> closeSheet(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).first).pop();
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('constants come from the engine; the maths is behind ⓘ', (
    t,
  ) async {
    await pumpB(t, const MethodologyScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    expect(find.text('Formula version $kAlgoVersion'), findsOneWidget);
    expect(find.text('Our own formula'), findsOneWidget);
    final hrvWeight = '${(RecoveryEngine.weights['hrv']! * 100).round()}%';
    expect(find.text('HRV $hrvWeight'), findsOneWidget);
    // No method names or citations on the page itself.
    expect(find.textContaining('Karvonen'), findsNothing);
    expect(find.textContaining('WHOOP'), findsNothing);

    await openInfo(t, 'About How Strain works');
    final tau = const EngineConfig().strainTau.round();
    expect(find.textContaining('÷ $tau'), findsOneWidget);
    expect(find.text('Demanding'), findsWidgets);
    await closeSheet(t);

    await t.scrollUntilVisible(
      find.text('Research behind the scores'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Research behind the scores'));
    await t.pumpAndSettle();
    expect(find.textContaining('Cole CR et al. (1999)'), findsOneWidget);
    expect(find.textContaining('WHOOP'), findsNothing);
  });

  testWidgets('Licences and credits opens the licences route', (t) async {
    await pumpB(t, const MethodologyScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Licences and credits'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Licences and credits'));
    await t.pumpAndSettle();
    expect(find.text('route ${Routes.licenses}'), findsOneWidget);
  });

  testWidgets('no overflow at 320 px and text scale 1.3 and 2.0', (t) async {
    for (final scale in const [1.3, 2.0]) {
      await t.pumpWidget(const SizedBox());
      await pumpB(
        t,
        const MethodologyScreen(),
        repo: ScreensBRepo.demo(),
        size: kSmall,
        textScale: scale,
      );
      await t.pumpAndSettle();
      await scrollThrough(t, step: 400);
    }
  });

  for (final b in const [Brightness.dark]) { // dark only
    testWidgets('golden · ${b.name}', (t) async {
      await pumpB(
        t,
        const MethodologyScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/screens/methodology_${b.name}.png'),
      );
    });

    // The Strain tile's ⓘ sheet: the formulas and the scoring bands.
    testWidgets('golden strain section · ${b.name}', (t) async {
      await pumpB(
        t,
        const MethodologyScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await openInfo(t, 'About How Strain works');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/methodology_strain_${b.name}.png',
        ),
      );
    });

    testWidgets('golden recovery info · ${b.name}', (t) async {
      await pumpB(
        t,
        const MethodologyScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await openInfo(t, 'About How Recovery works');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/methodology_recovery_info_${b.name}.png',
        ),
      );
    });
  }
}
