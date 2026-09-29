// Beat-interval tools for Bluetooth sessions. [ours, methods cited by
// OpenStrap/edge; its implementations live in an unvendored package, so these
// are written from the published methods]
//
//  * Artefact filter (the common 20 % rule): an RR interval is clean if it lies in
//    300–2000 ms AND differs by ≤ 20 % from the previous ACCEPTED interval
//    (the first is compared with the median of the in-range intervals).
//  * RMSSD (Task Force 1996): root mean square of successive differences,
//    taken ONLY between intervals that were adjacent in the original series
//    and are both clean (never across a removed beat).
//  * Baevsky stress index (Baevsky 2008, as cited by Edge): SI = AMo/(2·Mo·MxDMn)
//    with a 50 ms histogram; AMo = % of intervals in the modal bin, Mo = the
//    modal bin's centre (s), MxDMn = max − min (s).
//  * HRR-60 (Cole et al., NEJM 1999): HR at exercise end minus HR 60 s later.

import 'dart:math' as math;

import '../models.dart';
import 'stats.dart';

abstract final class HrvTools {
  static const double minRrMs = 300;
  static const double maxRrMs = 2000;
  static const double maxRelativeJump = 0.20;
  static const int minCleanForRmssd = 30;
  static const int minCleanForBaevsky = 60;
  static const double baevskyBinMs = 50;

  /// Per-interval clean flags (same length as [rrMs]).
  static List<bool> cleanMask(List<double> rrMs) {
    bool inRange(double v) => v.isFinite && v >= minRrMs && v <= maxRrMs;
    final inRangeValues = [
      for (final v in rrMs)
        if (inRange(v)) v,
    ];
    final mask = List<bool>.filled(rrMs.length, false);
    var ref = Stats.median(inRangeValues);
    if (ref == null) return mask;
    for (var i = 0; i < rrMs.length; i++) {
      final v = rrMs[i];
      if (!inRange(v)) continue;
      if ((v - ref!).abs() / ref <= maxRelativeJump) {
        mask[i] = true;
        ref = v;
      }
    }
    return mask;
  }

  /// Clean intervals, in order.
  static List<double> clean(List<double> rrMs) {
    final mask = cleanMask(rrMs);
    return [
      for (var i = 0; i < rrMs.length; i++)
        if (mask[i]) rrMs[i],
    ];
  }

  /// RMSSD in ms, or null with < 30 clean intervals / no clean pair.
  static double? rmssd(List<double> rrMs) {
    final mask = cleanMask(rrMs);
    final cleanCount = mask.where((m) => m).length;
    if (cleanCount < minCleanForRmssd) return null;
    var sum = 0.0;
    var pairs = 0;
    for (var i = 1; i < rrMs.length; i++) {
      if (!mask[i] || !mask[i - 1]) continue;
      final d = rrMs[i] - rrMs[i - 1];
      sum += d * d;
      pairs++;
    }
    if (pairs == 0) return null;
    final r = math.sqrt(sum / pairs);
    return r.isFinite ? r : null;
  }

  /// Baevsky stress index, or null with < 60 clean intervals or zero range.
  static double? baevsky(List<double> rrMs) {
    final nn = clean(rrMs);
    if (nn.length < minCleanForBaevsky) return null;
    final counts = <int, int>{};
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final v in nn) {
      final bin = (v / baevskyBinMs).floor();
      counts[bin] = (counts[bin] ?? 0) + 1;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final mxDMn = (hi - lo) / 1000;
    if (!(mxDMn > 0)) return null;
    var modeBin = 0;
    var modeCount = -1;
    for (final e in counts.entries) {
      if (e.value > modeCount || (e.value == modeCount && e.key < modeBin)) {
        modeBin = e.key;
        modeCount = e.value;
      }
    }
    final mo = (modeBin * baevskyBinMs + baevskyBinMs / 2) / 1000;
    final amo = modeCount / nn.length * 100;
    final si = amo / (2 * mo * mxDMn);
    return si.isFinite ? si : null;
  }

  /// HRR-60: bpm at [end] minus bpm 60 s later, using the samples nearest to
  /// each instant within ±10 s. Positive = HR dropped. Null if either is
  /// missing.
  static double? hrr60(List<HrSample> samples, DateTime end) {
    final atEnd = _nearest(samples, end);
    final after = _nearest(samples, end.add(const Duration(seconds: 60)));
    if (atEnd == null || after == null) return null;
    final d = atEnd - after;
    return d.isFinite ? d : null;
  }

  static double? _nearest(List<HrSample> samples, DateTime t) {
    HrSample? best;
    var bestUs = 10 * 1000000 + 1;
    for (final s in samples) {
      if (!s.bpm.isFinite || s.bpm <= 0) continue;
      final d = s.t.difference(t).inMicroseconds.abs();
      if (d < bestUs) {
        best = s;
        bestUs = d;
      }
    }
    return best?.bpm;
  }
}
