// The Figma diff: every design tile against its PNG, at devicePixelRatio 1.0
// and the PNG's exact size, with the PNG's own sample values.
//
//   flutter test test/goldens/figma_diff_test.dart
//
// Prints the per-tile diff table and writes the compare sheets (Figma | ours
// | diff) to docs/screenshots/redesign/compare/. The PNGs are never
// regenerated: this file turns --update-goldens off for itself and the
// comparator refuses to write.

import 'dart:io';

import 'package:airlog/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fonts.dart';
import 'figma_comparator.dart';
import 'figma_fixtures.dart';

void main() {
  late GoldenFileComparator previous;
  final byName = {for (final c in figmaCases) c.name: c};

  setUpAll(() async {
    await loadAppFonts();
    autoUpdateGoldenFiles = false;
    previous = goldenFileComparator;
    goldenFileComparator = FigmaComparator(
      Uri.file('${Directory.current.path}/test/goldens/figma_diff_test.dart'),
      limits: (n) => byName[n]?.limit ?? .03,
      sheets: Directory('docs/screenshots/redesign/compare'),
    );
  });

  tearDownAll(() {
    goldenFileComparator = previous;
    final rows = FigmaComparator.results.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    // The table the design review quotes.
    // ignore: avoid_print
    print(
      'FIGMA DIFF (threshold ${FigmaComparator.threshold}/255)\n'
      '${rows.map((r) => r.line).join('\n')}',
    );
  });

  for (final c in figmaCases) {
    testWidgets('figma ${c.name}', (t) async {
      final size = c.size.size;
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const key = ValueKey('tile');
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: key, child: c.build()),
          ),
        ),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('figma/${c.name}.png'),
      );
    });
  }
}
