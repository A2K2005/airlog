import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/recovery.dart';
import 'package:airlog/domain/results.dart';
import 'package:airlog/features/methodology/methodology_screen.dart';
import 'package:airlog/app/platform_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../../support/screens_b_fixtures.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('constants come from the engine', (t) async {
    await pumpB(t, const MethodologyScreen(), repo: ScreensBRepo.demo());
    await t.pumpAndSettle();
    expect(find.text('Algorithm v$kAlgoVersion'), findsOneWidget);
    final hrvWeight = '${(RecoveryEngine.weights['hrv']! * 100).round()} %';
    expect(find.text(hrvWeight), findsOneWidget);
    final tau = const EngineConfig().strainTau.round();
    expect(find.textContaining('÷ $tau'), findsOneWidget);
    expect(find.text('Demanding'), findsOneWidget);
    expect(find.textContaining('Cole CR et al. (1999)'), findsOneWidget);
    expect(find.textContaining('Pulse (Apache-2.0)'), findsOneWidget);
  });

  testWidgets('contents jump and credit links', (t) async {
    final opened = <Uri>[];
    await pumpB(
      t,
      const MethodologyScreen(),
      repo: ScreensBRepo.demo(),
      extra: [
        linkOpenerProvider.overrideWithValue((u) async {
          opened.add(u);
          return true;
        }),
      ],
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Credits').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Pulse (Apache-2.0)'));
    await t.pumpAndSettle();
    expect(opened.single.host, 'github.com');
  });

  testWidgets('no overflow at 320 px and text scale 1.3', (t) async {
    await pumpB(
      t,
      const MethodologyScreen(),
      repo: ScreensBRepo.demo(),
      size: kSmall,
      textScale: 1.3,
    );
    await t.pumpAndSettle();
    await scrollThrough(t, step: 500);
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

    testWidgets('golden strain section · ${b.name}', (t) async {
      await pumpB(
        t,
        const MethodologyScreen(),
        repo: ScreensBRepo.demo(),
        brightness: b,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Strain').first);
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../goldens/screens/methodology_strain_${b.name}.png',
        ),
      );
    });
  }
}
