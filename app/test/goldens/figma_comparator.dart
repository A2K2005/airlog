// The Figma diff comparator: the design PNGs ARE the goldens.
//
// Each tile is rendered at devicePixelRatio 1.0 at its PNG's exact size and
// compared pixel by pixel with the PNG (test/goldens/figma/<name>.png).
//
// Metric (fixed for every tile, never tuned per widget):
//   * both images as straight RGBA, compared premultiplied (colour × alpha)
//     plus alpha, so a transparent corner compares as transparent;
//   * a pixel DIFFERS when any of those four channels is more than
//     [threshold] 8-bit levels apart;
//   * diff % = differing pixels / (width × height);
//   * MAE = mean absolute difference over all pixels and channels (levels).
//
// It never writes a golden: --update-goldens cannot overwrite the design.
// Every comparison writes a side-by-side sheet, Figma | ours | diff, to
// docs/screenshots/redesign/compare/<name>.png, and records its numbers in
// [FigmaComparator.results].

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

class FigmaResult {
  const FigmaResult(this.name, this.width, this.height, this.diff, this.mae);
  final String name;
  final int width, height;

  /// Fraction of differing pixels, 0…1.
  final double diff;
  final double mae;

  String get line =>
      '${name.padRight(12)} ${width}x$height  diff ${(diff * 100).toStringAsFixed(2)} %  '
      'MAE ${mae.toStringAsFixed(2)}';
}

class FigmaComparator extends LocalFileComparator {
  FigmaComparator(super.testFile, {required this.limits, required this.sheets});

  /// Channel tolerance in 8-bit levels.
  static const threshold = 12;

  /// Per-tile pass limit (fraction). 3 % unless the tile is listed with a
  /// reason (≤ 6 %, text anti-aliasing only).
  final double Function(String name) limits;

  /// Where the compare sheets go.
  final Directory sheets;

  static final results = <String, FigmaResult>{};

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    throw StateError(
      'The design PNGs are the goldens; they are never regenerated '
      '($golden).',
    );
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final file = File.fromUri(basedir.resolveUri(golden));
    final ref = await _decode(await file.readAsBytes());
    final ours = await _decode(imageBytes);
    final name = golden.pathSegments.last.replaceAll('.png', '');
    if (ref.width != ours.width || ref.height != ours.height) {
      throw TestFailure(
        '$name: rendered ${ours.width}×${ours.height}, '
        'design is ${ref.width}×${ref.height}',
      );
    }
    final w = ref.width, h = ref.height;
    var differ = 0;
    var sum = 0.0;
    final diffPx = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      final o = i * 4;
      final ra = ref.px[o + 3], oa = ours.px[o + 3];
      var worst = (ra - oa).abs();
      sum += worst;
      for (var c = 0; c < 3; c++) {
        final rv = ref.px[o + c] * ra / 255;
        final ov = ours.px[o + c] * oa / 255;
        final d = (rv - ov).abs();
        sum += d;
        if (d > worst) worst = d.round();
      }
      final bad = worst > threshold;
      if (bad) differ++;
      // Diff view: magenta where it differs, grey ramp of the error elsewhere.
      final g = math.min(255, worst * 4);
      diffPx[o] = bad ? 255 : g ~/ 2;
      diffPx[o + 1] = bad ? 0 : g ~/ 2;
      diffPx[o + 2] = bad ? 255 : g ~/ 2;
      diffPx[o + 3] = 255;
    }
    final r = FigmaResult(name, w, h, differ / (w * h), sum / (w * h * 4));
    results[name] = r;
    await _sheet(name, ref, ours, diffPx, w, h);
    final limit = limits(name);
    if (r.diff > limit) {
      throw TestFailure(
        '${r.line}  > limit ${(limit * 100).toStringAsFixed(1)} %  '
        '(sheet: ${sheets.path}/$name.png)',
      );
    }
    return true;
  }

  Future<void> _sheet(
    String name,
    _Rgba ref,
    _Rgba ours,
    Uint8List diff,
    int w,
    int h,
  ) async {
    const k = 2, gap = 8;
    final sw = (w * 3 + gap * 4) * k, sh = (h + gap * 2) * k;
    final out = Uint8List(sw * sh * 4);
    // Page grey behind the tiles, so the transparent corners show.
    for (var i = 0; i < sw * sh; i++) {
      out[i * 4] = 30;
      out[i * 4 + 1] = 30;
      out[i * 4 + 2] = 30;
      out[i * 4 + 3] = 255;
    }
    void blit(Uint8List src, int col, {bool over = true}) {
      final ox = (gap + col * (w + gap)) * k, oy = gap * k;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final s = (y * w + x) * 4;
          final a = over ? src[s + 3] / 255 : 1.0;
          for (var dy = 0; dy < k; dy++) {
            for (var dx = 0; dx < k; dx++) {
              final d = ((oy + y * k + dy) * sw + ox + x * k + dx) * 4;
              for (var c = 0; c < 3; c++) {
                out[d + c] = (src[s + c] * a + out[d + c] * (1 - a)).round();
              }
            }
          }
        }
      }
    }

    blit(ref.px, 0);
    blit(ours.px, 1);
    blit(diff, 2, over: false);
    final img = await _encode(out, sw, sh);
    sheets.createSync(recursive: true);
    File('${sheets.path}/$name.png').writeAsBytesSync(img);
  }

  static Future<_Rgba> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final r = _Rgba(
      frame.image.width,
      frame.image.height,
      data!.buffer.asUint8List(),
    );
    frame.image.dispose();
    return r;
  }

  static Future<Uint8List> _encode(Uint8List rgba, int w, int h) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final desc = ui.ImageDescriptor.raw(
      buffer,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return png!.buffer.asUint8List();
  }
}

class _Rgba {
  _Rgba(this.width, this.height, this.px);
  final int width, height;
  final Uint8List px;
}
