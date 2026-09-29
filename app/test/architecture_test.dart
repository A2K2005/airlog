// Enforces the dependency rule in ARCHITECTURE.md §2.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _import = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true);

Iterable<(String file, String target)> _imports(String dir) sync* {
  final root = Directory(dir);
  if (!root.existsSync()) return;
  for (final f in root.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    for (final m in _import.allMatches(f.readAsStringSync())) {
      yield (f.path.replaceAll(r'\', '/'), m.group(1)!);
    }
  }
}

bool _reaches(String file, String target, String layer) {
  if (target.startsWith('package:airlog/$layer/')) return true;
  if (target.startsWith('package:') || target.startsWith('dart:')) {
    return false;
  }
  final resolved = Uri.file(file).resolve(target).path;
  return resolved.contains('/lib/$layer/');
}

void main() {
  test('domain/ is pure Dart and self-contained', () {
    final bad = [
      for (final (f, t) in _imports('lib/domain'))
        if (t.startsWith('package:') ||
            _reaches(f, t, 'data') ||
            _reaches(f, t, 'features') ||
            _reaches(f, t, 'design') ||
            _reaches(f, t, 'app'))
          '$f -> $t'
    ];
    expect(bad, isEmpty);
  });

  test('features/ never import data/', () {
    final bad = [
      for (final (f, t) in _imports('lib/features'))
        if (_reaches(f, t, 'data')) '$f -> $t'
    ];
    expect(bad, isEmpty);
  });

  test('data/ never imports features/ or design/', () {
    final bad = [
      for (final (f, t) in _imports('lib/data'))
        if (_reaches(f, t, 'features') || _reaches(f, t, 'design')) '$f -> $t'
    ];
    expect(bad, isEmpty);
  });

  test('design/ never imports data/ or features/', () {
    final bad = [
      for (final (f, t) in _imports('lib/design'))
        if (_reaches(f, t, 'data') || _reaches(f, t, 'features')) '$f -> $t'
    ];
    expect(bad, isEmpty);
  });
}
