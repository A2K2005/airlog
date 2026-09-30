// Adapted from OpenStrap/edge test/ui2_tokens_test.dart (MIT, see
// third_party/edge/LICENSE). Changes: scans lib/design, lib/app and
// lib/features (the whole presentation layer); the token boundary is the
// lib/design/tokens/ directory; Color constructors of every form are banned
// (not only 0x literals); Pressable lives in design/components/pressable.dart;
// adds the design/ import rule, the gallery-completeness check against
// lib/features/gallery, and motion/theme token checks.
//
// A design system is only a system while every screen spends the same
// vocabulary. These rules are cheap on the first screen and impossible to
// retrofit on the fortieth.

import 'dart:io';

import 'package:airlog/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dart_source.dart';

const _tokenDir = 'lib/design/tokens/';
const _gestureFile = 'lib/design/components/pressable.dart';

/// The one bounded loop (Motion.dotsCycles, off under reduced motion):
/// the coach's thinking dots (user decision D5, 2026-10-01).
const _loopFile = 'lib/design/components/thinking_dots.dart';
const _scanned = ['lib/design', 'lib/app', 'lib/features'];

class _Rule {
  _Rule(this.name, this.pattern, this.why, {this.allow = _tokensOnly});
  final String name;
  final RegExp pattern;
  final String why;
  final bool Function(String path) allow;
}

bool _tokensOnly(String p) => p.startsWith(_tokenDir);
bool _nowhere(String p) => false;

final _rules = <_Rule>[
  _Rule(
    'raw fontSize:',
    RegExp(r'\bfontSize\s*:'),
    'Type comes from F (F.body, F.cap, F.n32 …); F.scaled for a derived size.',
  ),
  _Rule(
    'Color constructor',
    RegExp(r'\bColor(\.from\w+)?\s*\('),
    'Colour comes from C / P / DomainColors. A new pigment is declared in '
        'lib/design/tokens/colors.dart (and added to C.all so the contrast '
        'test measures it). C.clear is the transparent colour.',
  ),
  _Rule(
    'Colors.white / Colors.black',
    RegExp(r'\bColors\.(white|black)\b'),
    'Hard white is a hole in a dark card. Use p.card / p.ink / p.onFill().',
    allow: _nowhere,
  ),
  _Rule(
    'numeric BorderRadius.circular',
    RegExp(r'BorderRadius\.circular\(\s*\d'),
    'Radii come from R (R.rSm … R.rCard, R.rPill).',
  ),
  _Rule(
    'infinite .repeat()',
    RegExp(r'\.repeat\s*\('),
    'A loop that never ends cannot be stopped by the reduced-motion gate (and '
        'never lets a test settle). Skeletons are static on purpose. The one '
        'exception is ThinkingDots: repeat(count: Motion.dotsCycles), off '
        'under reduced motion.',
    allow: (p) => p == _loopFile,
  ),
  _Rule(
    'Duration literal',
    RegExp(r'\bDuration\s*\((?!\s*\))'),
    'Durations come from Motion.* through motion(context, …) so reduced '
        'motion collapses them. For date arithmetic use DayKey / DateTime '
        'constructors, not a Duration literal.',
  ),
  _Rule(
    'raw gesture detector',
    RegExp(r'\b(GestureDetector|InkWell|RawGestureDetector|Listener)\b'),
    'Pressable is the gesture primitive: it applies the 48 dp floor, the '
        'press feedback, the haptic and the button role.',
    allow: (p) => p == _gestureFile,
  ),
];

List<File> _dart(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String _rel(File f) =>
    f.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^\./'), '');

void main() {
  test('the design system exists where the rules expect it', () {
    for (final d in [
      'lib/design/tokens',
      'lib/design/charts',
      'lib/design/components',
    ]) {
      expect(
        Directory(d).existsSync(),
        isTrue,
        reason: 'run from the package root',
      );
      expect(_dart(d), isNotEmpty);
    }
  });

  final files = [for (final d in _scanned) ..._dart(d)];

  for (final rule in _rules) {
    test('no ${rule.name} outside the token boundary', () {
      final hits = <String>[];
      for (final f in files) {
        final rel = _rel(f);
        if (rule.allow(rel)) continue;
        final lines = codeLines(f.readAsStringSync());
        for (var i = 0; i < lines.length; i++) {
          if (rule.pattern.hasMatch(lines[i])) {
            hits.add('$rel:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
      expect(hits, isEmpty, reason: '${rule.why}\n\n${hits.join('\n')}');
    });
  }

  test('design/ imports only Flutter, dart:, itself and domain/', () {
    final import = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    final bad = <String>[];
    for (final f in _dart('lib/design')) {
      for (final m in import.allMatches(f.readAsStringSync())) {
        final t = m.group(1)!;
        final ok =
            t.startsWith('dart:') ||
            t.startsWith('package:flutter/') ||
            t.startsWith('package:airlog/design/') ||
            t.startsWith('package:airlog/domain/') ||
            (!t.startsWith('package:') &&
                !Uri.file(f.absolute.path)
                    .resolve(t)
                    .path
                    .contains('/lib/app/') &&
                !Uri.file(f.absolute.path)
                    .resolve(t)
                    .path
                    .contains('/lib/data/') &&
                !Uri.file(f.absolute.path)
                    .resolve(t)
                    .path
                    .contains('/lib/features/'));
        if (!ok) bad.add('${_rel(f)} -> $t');
      }
    }
    expect(
      bad,
      isEmpty,
      reason:
          'ARCHITECTURE.md §2: design/ imports only Flutter and domain/ '
          'value types (no riverpod, no intl, no providers).',
    );
  });

  test('every public component and chart widget is in the gallery', () {
    final gallery = [
      File('lib/features/gallery/gallery_screen.dart').readAsStringSync(),
      File('lib/features/gallery/gallery_samples.dart').readAsStringSync(),
      File('lib/features/gallery/gallery_tiles.dart').readAsStringSync(),
    ].join('\n');
    final missing = <String>[];
    for (final f in [
      ..._dart('lib/design/components'),
      ..._dart('lib/design/charts'),
      ..._dart('lib/design/tiles'),
    ]) {
      for (final line in codeLines(f.readAsStringSync())) {
        final m = RegExp(
          r'^class ([A-Z]\w*)(<[^>]*>)? extends St(ateless|ateful)Widget',
        ).firstMatch(line);
        final name = m?.group(1);
        if (name == null || _notInGallery.containsKey(name)) continue;
        if (!gallery.contains(name)) missing.add('$name (${_rel(f)})');
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Add a gallery case (lib/features/gallery/gallery_screen.dart) '
          'or list the widget in _notInGallery with the reason.',
    );
  });

  group('motion tokens', () {
    test('UI durations stay under 300 ms; exits are faster than enters', () {
      for (final d in [
        Motion.press,
        Motion.release,
        Motion.fast,
        Motion.base,
        Motion.slow,
        Motion.exit,
      ]) {
        expect(d.inMilliseconds, lessThan(300));
      }
      expect(Motion.release, lessThan(Motion.press));
      expect(Motion.exit, lessThan(Motion.slow));
      expect(Motion.stagger.inMilliseconds, lessThanOrEqualTo(40));
      expect(Motion.cardStagger.inMilliseconds, inInclusiveRange(40, 60));
      expect(Motion.dotStep.inMilliseconds, lessThanOrEqualTo(300));
      // The bounded thinking loop rests after about 17 s.
      expect(
        (Motion.dotStep * 4 * Motion.dotsCycles).inSeconds,
        inInclusiveRange(15, 20),
      );
      expect(Motion.none, Duration.zero);
      // The one deliberate exception: the once-a-day ring sweep.
      expect(Motion.sweep.inMilliseconds, inInclusiveRange(600, 800));
    });

    test('curves are the specified ones, and none is an ease-in', () {
      expect(Motion.enter, const Cubic(0.23, 1, 0.32, 1));
      expect(Motion.move, const Cubic(0.77, 0, 0.175, 1));
      expect(Motion.drawer, const Cubic(0.32, 0.72, 0, 1));
      for (final c in [Motion.enter, Motion.drawer]) {
        // Ease-out: more than half the distance in the first 30 % of time.
        expect(c.transform(.3), greaterThan(.5));
      }
    });

    testWidgets(
      'motion() drops movement but keeps fades under reduced motion',
      (tester) async {
        late BuildContext on, off;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (c) {
                off = c;
                return MediaQuery(
                  data: const MediaQueryData(disableAnimations: false),
                  child: Builder(
                    builder: (c2) {
                      on = c2;
                      return const SizedBox.shrink();
                    },
                  ),
                );
              },
            ),
          ),
        );
        expect(motion(off, Motion.base), Duration.zero);
        expect(
          motion(off, Motion.base, fade: true),
          greaterThan(Duration.zero),
        );
        expect(
          motion(off, Motion.sweep, fade: true),
          lessThanOrEqualTo(Motion.fast),
        );
        expect(animate(off, .3), 1);
        expect(Motion.enabled(off), isFalse);
        expect(sheetMotion(off), AnimationStyle.noAnimation);

        expect(motion(on, Motion.base), Motion.base);
        expect(animate(on, .3), .3);
        expect(Motion.enabled(on), isTrue);
        expect(sheetMotion(on).curve, Motion.drawer);
      },
    );
  });

  group('theme', () {
    for (final b in const [Brightness.dark]) {
      test('${b.name} only: the UI face, gated page transitions, flat surfaces', () {
        final t = buildTheme(b);
        const p = P();
        expect(t.brightness, b);
        // Asking for light still gets the dark theme: the app is dark only.
        expect(buildTheme(Brightness.light).brightness, Brightness.dark);
        expect(t.textTheme.bodyLarge!.fontFamily, F.ui);
        expect(t.scaffoldBackgroundColor, p.bg);
        expect(
          t.pageTransitionsTheme.builders[TargetPlatform.android],
          isA<AirlogPageTransitions>(),
        );
        expect(
          const AirlogPageTransitions().transitionDuration.inMilliseconds,
          lessThan(300),
        );
        expect(
          const AirlogPageTransitions().reverseTransitionDuration,
          lessThan(const AirlogPageTransitions().transitionDuration),
        );
        expect(t.navigationBarTheme.backgroundColor, p.bg);
        expect(t.cardTheme.shape, isA<RoundedRectangleBorder>());
      });
    }

    test('numeral styles all use tabular figures', () {
      for (final s in [
        F.n96,
        F.n64,
        F.n44,
        F.n32,
        F.n24,
        F.n18,
        F.tab(F.cap),
      ]) {
        expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
      expect(F.n64.fontFamily, F.numerals);
      expect(F.numerals, 'Subway Ticker Grid');
      expect(F.ui, 'DM Sans');
    });
  });
}

/// Public widgets deliberately without their own gallery case.
const _notInGallery = <String, String>{
  'TileScope': 'the text scope inside every GlowTile (all tiles are in the gallery)',
  'TileText': 'the text placement inside every tile in the Tiles section',
  'DotValue': 'the number-and-unit inside every tile in the Tiles section',
  'CenteredDotValue': 'the centred number inside Ring/TopArc/ArcState tiles',
  'TileBadge': 'the corner disc of Readiness, Water and Health Alert',
  'TileGlyph': 'the corner glyphs of Readiness, Water and Health Alert',
  'TileIcon': 'the title pictograms of Sleep, Workout Summary and others',
  'SampleDataScope': 'an inherited scope, not a visual',
  'LegendSwatch': 'drawn by every ChartFrame legend in the chart sections',
  'NoData': 'the empty body of every chart in the Edge cases section',
};
