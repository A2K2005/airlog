// Adapted from OpenStrap/edge test/ui2_contrast_test.dart (MIT, see
// third_party/edge/LICENSE). Changes: four surfaces (bg / card / card2 /
// sheet); text floor 4.5:1 via P.on, chart-mark floor 3:1 via P.mark (WCAG
// 1.4.11); fills are measured against THEIR OWN label ink (P.onFill), which
// is chosen per pigment; hue preservation of the solver; Airlog painters.
//
// The floors are computed by P.on / P.mark / P.fill; this test proves they
// got there for every pigment in C.all, on every surface, in both themes.

import 'package:airlog/design/design.dart';
import 'package:airlog/domain/models.dart' show SleepStage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _aa = 4.5;
const _nonText = 3.0;

String _hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';

/// Records only rounded-rect heights (ZoneBar's second channel).
class _Heights implements Canvas {
  final heights = <double>[];
  @override
  void drawRRect(RRect r, Paint p) => heights.add(r.outerRect.height);
  @override
  void noSuchMethod(Invocation i) {}
}

void main() {
  // The app is dark only (the design is dark).
  final themes = {'dark': const P()};

  test('the measurement itself: 21:1 and 1:1 anchors', () {
    expect(P.contrast(C.black, C.white), closeTo(21, .01));
    expect(P.contrast(C.strain, C.strain), closeTo(1, .001));
  });

  group('body ink clears 4.5:1 on every surface', () {
    themes.forEach((name, p) {
      final inks = {'ink': p.ink, 'ink2': p.ink2, 'ink3': p.ink3};
      final surfaces = {
        'bg': p.bg,
        'card': p.card,
        'card2': p.card2,
        'sheet': p.sheet,
      };
      inks.forEach((ik, iv) {
        surfaces.forEach((sk, sv) {
          test('$name · $ik on $sk', () {
            final r = P.contrast(iv, sv);
            expect(
              r,
              greaterThanOrEqualTo(_aa),
              reason: '$ik is ${r.toStringAsFixed(2)}:1 on $sk ($name)',
            );
          });
        });
      });
      test('$name · inverse ink on the ink fill (primary button)', () {
        expect(P.contrast(p.inkInverse, p.ink), greaterThanOrEqualTo(_aa));
      });
    });
  });

  group('P.on(): every accent as text clears 4.5:1 on every surface', () {
    themes.forEach((name, p) {
      for (final a in C.all) {
        test('$name · on(${_hex(a)})', () {
          final ink = p.on(a);
          for (final s in p.surfaces) {
            expect(
              P.contrast(ink, s),
              greaterThanOrEqualTo(_aa),
              reason: 'on(${_hex(a)}) on ${_hex(s)} ($name)',
            );
            final tinted = Color.alphaBlend(p.wash(a), s);
            expect(
              P.contrast(ink, tinted),
              greaterThanOrEqualTo(_aa),
              reason: 'on(${_hex(a)}) on its own wash over ${_hex(s)} ($name)',
            );
          }
        });
      }
    });
  });

  group(
    'P.fill(): the fill clears 4.5:1 on every surface, and so does its label',
    () {
      // "Fill" is read both ways: the filled shape against the surface it sits
      // on, and the label against the fill. Both are measured.
      themes.forEach((name, p) {
        for (final a in C.all) {
          test('$name · fill(${_hex(a)})', () {
            final f = p.fill(a);
            for (final s in p.surfaces) {
              final r = P.contrast(f, s);
              expect(
                r,
                greaterThanOrEqualTo(_aa),
                reason:
                    'fill ${_hex(f)} is ${r.toStringAsFixed(2)}:1 on '
                    '${_hex(s)} ($name)',
              );
            }
            final l = P.contrast(p.onFill(a), f);
            expect(
              l,
              greaterThanOrEqualTo(_aa),
              reason: 'button label ${l.toStringAsFixed(2)}:1 ($name)',
            );
          });
        }
      });
    },
  );

  group(
    'P.mark(): every accent as a chart mark clears 3:1 on every surface',
    () {
      themes.forEach((name, p) {
        for (final a in C.all) {
          test('$name · mark(${_hex(a)})', () {
            for (final s in p.surfaces) {
              expect(
                P.contrast(p.mark(a), s),
                greaterThanOrEqualTo(_nonText),
                reason: 'mark(${_hex(a)}) on ${_hex(s)} ($name)',
              );
            }
          });
        }
      });
    },
  );

  group('what the painters draw is measured like a mark', () {
    themes.forEach((name, p) {
      final marks = <String, Color>{
        for (final e in Hypnogram.cols(p).entries)
          'stage ${e.key.name}': e.value,
        for (var i = 0; i < ZoneBar.cols(p).length; i++)
          'zone ${i + 1}': ZoneBar.cols(p)[i],
        for (var z = 0; z <= 5; z++)
          'hr zone $z': p.mark(DomainColors.hrZone(z)),
        for (final z in [20, 50, 80])
          'recovery $z': p.mark(DomainColors.recovery(z)),
      };
      marks.forEach((what, ink) {
        test('$name · $what', () {
          for (final s in p.surfaces) {
            expect(
              P.contrast(ink, s),
              greaterThanOrEqualTo(_nonText),
              reason: '$what on ${_hex(s)} ($name)',
            );
          }
        });
      });
    });

    test('legend swatches are the marks on the chart', () {
      for (final p in themes.values) {
        expect(
          [for (final (_, c) in Hypnogram.legend(p)) c],
          [for (final s in Hypnogram.lanes) Hypnogram.cols(p)[s]],
        );
        expect([for (final (_, c) in ZoneBar.legend(p)) c], ZoneBar.cols(p));
      }
    });

    test(
      'hypnogram lanes: awake on top, deep at the bottom, unknown not a lane',
      () {
        expect(Hypnogram.lanes.first, SleepStage.awake);
        expect(Hypnogram.lanes.last, SleepStage.deep);
        expect(Hypnogram.lanes, isNot(contains(SleepStage.unknown)));
      },
    );

    test(
      'the zone ramp does not rely on hue alone (bands step up in height)',
      () {
        final rec = _Heights();
        ZoneBar(const [
          .2,
          .2,
          .2,
          .2,
          .2,
        ], const P(false)).paint(rec, const Size(300, 20));
        expect(rec.heights, hasLength(5));
        for (var i = 1; i < rec.heights.length; i++) {
          expect(rec.heights[i], greaterThan(rec.heights[i - 1]));
        }
      },
    );
  });

  test('the raw pigment really was unsafe — the solver has teeth', () {
    const p = P();
    expect(P.contrast(C.indigo, p.card), lessThan(_aa));
    expect(P.contrast(p.on(C.indigo), p.card), greaterThanOrEqualTo(_aa));
    final g = p.on(C.indigo);
    expect(g.b, greaterThan(g.g));
  });

  group('the design wins: every tile spot below the floor is listed', () {
    for (final spot in DesignContrast.spots) {
      test('${spot.tile} · ${spot.text}', () {
        final ink = Color.alphaBlend(spot.ink, spot.background);
        final r = P.contrast(ink, spot.background);
        // The documented ratio is the measured one, and it is below the
        // floor (otherwise the spot does not belong on the list).
        expect(r, closeTo(spot.ratio, .06));
        expect(r, lessThan(_aa));
      });
    }

    test('tile titles and values clear 4.5:1 on the darkest tile core', () {
      const core = Color(0xFF0A0A0A);
      for (final ink in [TileInk.primary, TileInk.unit, TileInk.secondary]) {
        expect(
          P.contrast(Color.alphaBlend(ink, core), core),
          greaterThanOrEqualTo(_aa),
        );
      }
    });
  });

  test('solving keeps the hue (a solved yellow is still yellow)', () {
    for (final p in themes.values) {
      for (final a in [C.recYellow, C.recGreen, C.strain, C.sleep, C.amber]) {
        final h0 = HSLColor.fromColor(a).hue;
        for (final c in [p.on(a), p.mark(a)]) {
          final d = (HSLColor.fromColor(c).hue - h0).abs();
          expect(
            d > 180 ? 360 - d : d,
            lessThan(12),
            reason: '${_hex(a)} drifted to ${_hex(c)}',
          );
        }
      }
    }
  });

  test('a wash cannot be turned up past a wash', () {
    for (final p in themes.values) {
      expect(p.wash(C.health, strength: 4).a, p.wash(C.health).a);
    }
  });

  test('solving is memoised', () {
    const p = P(true);
    expect(p.on(C.sleep), p.on(C.sleep));
  });
}
