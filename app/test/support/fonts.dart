// Loads every font the app bundles (DM Sans, Subway Ticker Grid, MaterialIcons)
// into the test engine, so goldens show real glyphs instead of Ahem boxes.
// Reads FontManifest.json, which is exactly what the app ships.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _loaded = false;

Future<void> loadAppFonts() async {
  if (_loaded) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = json.decode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final entry in manifest) {
    final m = entry as Map<String, dynamic>;
    final family = m['family'] as String;
    final loader = FontLoader(
      family.startsWith('packages/') ? family.split('/').last : family,
    );
    for (final f in m['fonts'] as List<dynamic>) {
      final asset = (f as Map<String, dynamic>)['asset'] as String;
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
  _loaded = true;
}
