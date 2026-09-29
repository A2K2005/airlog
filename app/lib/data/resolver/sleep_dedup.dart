// Health Connect sleep clean-up (PRODUCT_PLAN §2.1 gotchas):
//   * sleep sessions get deleted and rewritten (a stale copy can linger when
//     a deletion is missed) → overlapping sessions of one source+origin are
//     duplicates;
//   * after a time-zone change the same night is written twice, ~N hours
//     apart (same length, same stage mix) → the LATER WRITE wins.
//
// "Later write" = upstream last-modified time when the Kotlin metadata
// channel provided it, else the time we first ingested the row, else the
// later start (deterministic fallback; unverifiable without the band).

import '../common/time.dart';
import '../db/raw_rows.dart';
import '../../domain/models.dart';

bool isDuplicateNight(RawSleepRow a, RawSleepRow b) {
  if (a.source != b.source || a.originPackage != b.originPackage) return false;
  final durA = a.end.difference(a.start).inMinutes;
  final durB = b.end.difference(b.start).inMinutes;
  if (durA <= 0 || durB <= 0) return false;
  final shorter = durA < durB ? durA : durB;
  final ov = overlapMs(a.start, a.end, b.start, b.end) / 60000;
  if (ov >= 0.5 * shorter) return true;

  // Time-zone duplicate: a main-sleep-length night shifted by a whole
  // number of half hours (1..14 h), same duration and stage mix.
  if (shorter < 180) return false;
  if ((durA - durB).abs() > 10) return false;
  final shift = a.start.difference(b.start).inMinutes.abs();
  if (shift < 55 || shift > 14 * 60 + 5) return false;
  final r = shift % 30;
  if (r > 5 && r < 25) return false;
  if (a.stages.isNotEmpty && b.stages.isNotEmpty) {
    for (final s in SleepStage.values) {
      final ma = a.stages
          .where((x) => x.stage == s)
          .fold(0.0, (acc, x) => acc + x.minutes);
      final mb = b.stages
          .where((x) => x.stage == s)
          .fold(0.0, (acc, x) => acc + x.minutes);
      if ((ma - mb).abs() > 15) return false;
    }
  }
  return true;
}

/// True when [a] was written after [b].
bool writtenAfter(RawSleepRow a, RawSleepRow b) {
  final wa = a.writtenAt, wb = b.writtenAt;
  if (wa != null && wb != null && wa != wb) return wa.isAfter(wb);
  if (a.ingestedAt != b.ingestedAt) return a.ingestedAt.isAfter(b.ingestedAt);
  if (a.start != b.start) return a.start.isAfter(b.start);
  return a.sourceRecordId.compareTo(b.sourceRecordId) > 0;
}

/// Removes duplicate nights, keeping the later write of each duplicate set.
List<RawSleepRow> dedupSleep(List<RawSleepRow> rows) {
  final sorted = [...rows]..sort((a, b) => a.start.compareTo(b.start));
  final dropped = <int>{};
  for (var i = 0; i < sorted.length; i++) {
    if (dropped.contains(i)) continue;
    for (var j = i + 1; j < sorted.length; j++) {
      if (dropped.contains(j)) continue;
      // Candidates are at most ~15 h apart in start time.
      if (sorted[j].start.difference(sorted[i].start).inHours > 15) break;
      if (!isDuplicateNight(sorted[i], sorted[j])) continue;
      if (writtenAfter(sorted[j], sorted[i])) {
        dropped.add(i);
        break;
      } else {
        dropped.add(j);
      }
    }
  }
  return [
    for (var i = 0; i < sorted.length; i++)
      if (!dropped.contains(i)) sorted[i],
  ];
}
