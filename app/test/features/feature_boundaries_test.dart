// Features never import each other; shared pieces live in app/ or design/.
// Also: one clock (clockProvider), and the shared app kits never reach back
// into features/ (no cycles through app/).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

final _import = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// The app/ files a feature may import (none of them imports a feature).
const _appKit = {
  'providers.dart',
  'route_names.dart',
  'platform_services.dart',
  'copy.dart',
  'hc_rationale.dart',
  'note_card.dart',
  'ask_entry.dart',
  'insight_card.dart',
  'screen_kit.dart',
};

Iterable<File> _dart(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

String _norm(String p) => p.replaceAll(r'\', '/');

/// Absolute-ish lib path of [target] imported from [file], or null for a
/// package/dart import outside the app.
String? _resolve(String file, String target) {
  if (target.startsWith('package:airlog/')) {
    return 'lib/${target.substring('package:airlog/'.length)}';
  }
  if (target.startsWith('package:') || target.startsWith('dart:')) return null;
  final r = _norm(
    Uri.file(File(file).absolute.path).resolve(target).toFilePath(),
  );
  final i = r.indexOf('/lib/');
  return i < 0 ? null : r.substring(i + 1);
}

String? _feature(String libPath) {
  final m = RegExp(r'^lib/features/([^/]+)/').firstMatch(libPath);
  return m?.group(1);
}

void main() {
  test('no feature imports another feature', () {
    final bad = <String>[];
    for (final f in _dart('lib/features')) {
      final path = _norm(f.path);
      final own = _feature(path);
      for (final m in _import.allMatches(f.readAsStringSync())) {
        final to = _resolve(f.path, m.group(1)!);
        if (to == null) continue;
        final other = _feature(to);
        if (other != null && other != own) bad.add('$path -> $to');
      }
    }
    expect(
      bad,
      isEmpty,
      reason:
          'Move the shared piece to lib/app/ (providers, routes, '
          'platform seams, shared copy) or lib/design/ (widgets).',
    );
  });

  test('features import only the shared app kit from app/', () {
    final bad = <String>[];
    for (final f in _dart('lib/features')) {
      for (final m in _import.allMatches(f.readAsStringSync())) {
        final to = _resolve(f.path, m.group(1)!);
        if (to == null || !to.startsWith('lib/app/')) continue;
        if (!_appKit.contains(to.substring('lib/app/'.length))) {
          bad.add('${_norm(f.path)} -> $to');
        }
      }
    }
    expect(bad, isEmpty);
  });

  test('the shared app kit never imports a feature', () {
    final bad = <String>[];
    for (final name in _appKit) {
      final f = File('lib/app/$name');
      expect(f.existsSync(), isTrue, reason: name);
      for (final m in _import.allMatches(f.readAsStringSync())) {
        final to = _resolve(f.path, m.group(1)!);
        if (to != null && to.startsWith('lib/features/')) {
          bad.add('$name -> $to');
        }
      }
    }
    expect(bad, isEmpty);
  });

  test('one clock: nothing defines or reads a second clock provider', () {
    final hits = <String>[];
    for (final dir in ['lib/app', 'lib/features', 'lib/design']) {
      for (final f in _dart(dir)) {
        final lines = codeLines(f.readAsStringSync());
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('screenClockProvider') ||
              RegExp(r'\bDateTime\.now\(\)').hasMatch(lines[i])) {
            hits.add('${_norm(f.path)}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'Read the time from clockProvider (app/providers.dart) so '
          'tests and goldens can pin it.',
    );
  });
}
