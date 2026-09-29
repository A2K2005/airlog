// Heart-rate downsampling: raw samples → 1-minute buckets per local day.
//
// Stored as a compact little-endian Uint16 blob (round(bpm*10), 0 = empty),
// so a day costs ~3 KB and a 90-day range reads 90 small rows instead of
// ~130 000 minute rows over the sqflite platform channel.

import 'dart:collection';
import 'dart:typed_data';

import '../../domain/day_key.dart';
import '../../domain/models.dart';
import '../common/time.dart';
import 'raw_rows.dart';

int minutesInDay(String date) =>
    DayKey.end(date).difference(DayKey.start(date)).inMinutes;

/// Key of one HR bucket day: (source, origin package or '', local day).
typedef HrDayKey = (SourceKind, String, String);

/// The origin part of an HR bucket key ('' when the row has none).
String hrOrigin(RawRow r) => r.originPackage ?? '';

/// Groups [rows] by (source, origin, local day) and builds one [HrDay]
/// each. Samples outside 25..250 bpm are dropped as artefacts.
Map<HrDayKey, HrDay> bucketHr(Iterable<RawHrRow> rows) {
  final groups = <HrDayKey, List<RawHrRow>>{};
  for (final r in rows) {
    groups.putIfAbsent((r.source, hrOrigin(r), dayKeyOf(r.t)), () => []).add(r);
  }
  return {
    for (final e in groups.entries)
      e.key: buildHrDay(e.key.$1, e.key.$3, e.value, origin: e.key.$2),
  };
}

HrDay buildHrDay(
  SourceKind source,
  String date,
  List<RawHrRow> rows, {
  String origin = '',
  HrDay? base,
  DateTime? clearFrom,
  DateTime? clearTo,
}) {
  final start = DayKey.start(date);
  final n = minutesInDay(date);
  final sum = Float64List(n);
  final cnt = Int32List(n);
  DateTime? last = base?.lastT;
  String? device = base?.device;
  var samples = 0;
  for (final r in rows) {
    if (r.bpm < 25 || r.bpm > 250) continue;
    final i = r.t.difference(start).inSeconds ~/ 60;
    if (i < 0 || i >= n) continue;
    sum[i] += r.bpm;
    cnt[i]++;
    samples++;
    if (last == null || r.t.isAfter(last)) last = r.t;
    device ??= r.device;
  }
  final out = Uint16List(n);
  if (base != null && base.tenths.length == n) {
    out.setAll(0, base.tenths);
    if (clearFrom != null && clearTo != null) {
      final a = clearFrom.difference(start).inMinutes.clamp(0, n);
      final b = clearTo.difference(start).inMinutes.clamp(0, n);
      for (var i = a; i < b; i++) {
        out[i] = 0;
      }
    }
  }
  for (var i = 0; i < n; i++) {
    if (cnt[i] > 0) out[i] = (sum[i] / cnt[i] * 10).round().clamp(1, 65535);
  }
  return HrDay(
    source: source,
    origin: origin,
    date: date,
    dayStart: start,
    tenths: out,
    device: device,
    samples: samples + (base?.samples ?? 0),
    lastT: last,
  );
}

Uint8List encodeTenths(Uint16List tenths) {
  final bd = ByteData(tenths.length * 2);
  for (var i = 0; i < tenths.length; i++) {
    bd.setUint16(i * 2, tenths[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

Uint16List decodeTenths(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final out = Uint16List(bytes.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = bd.getUint16(i * 2, Endian.little);
  }
  return out;
}

/// Encodes a resolved day's 1-minute HR samples (for day_record storage).
int sampleAnchor(List<HrSample> samples) => samples
    .map((s) => s.t.millisecondsSinceEpoch ~/ 60000 * 60000)
    .reduce((a, b) => a < b ? a : b);

Uint8List encodeSamples(String date, List<HrSample> samples, {int? startMs}) {
  final start = startMs == null ? DayKey.start(date) : fromMs(startMs);
  final n = startMs == null
      ? minutesInDay(date)
      : samples
            .map((s) => s.t.difference(start).inMinutes + 1)
            .fold<int>(0, (a, b) => a > b ? a : b);
  final t = Uint16List(n);
  for (final s in samples) {
    final i = s.t.difference(start).inSeconds ~/ 60;
    if (i < 0 || i >= n) continue;
    t[i] = (s.bpm * 10).round().clamp(1, 65535);
  }
  return encodeTenths(t);
}

List<HrSample> decodeSamples(String date, Uint8List bytes, {int? startMs}) {
  final start = startMs ?? DayKey.start(date).millisecondsSinceEpoch;
  final t = decodeTenths(bytes);
  return [
    for (var i = 0; i < t.length; i++)
      if (t[i] > 0)
        HrSample(
          DateTime.fromMillisecondsSinceEpoch(start + i * 60000),
          t[i] / 10.0,
        ),
  ];
}

/// Decodes lazily: creating ~1 440 local DateTimes per day is the dominant
/// cost of a 90-day range() read, and most range consumers (trends) never
/// touch intraday HR. Materialises on first element access.
class LazyHrSamples extends ListBase<HrSample> {
  LazyHrSamples(this.date, this.bytes, {this.startMs});
  final String date;
  final Uint8List bytes;
  final int? startMs;
  List<HrSample>? _m;
  int? _n;

  List<HrSample> get _list =>
      _m ??= decodeSamples(date, bytes, startMs: startMs);

  @override
  int get length {
    final m = _m;
    if (m != null) return m.length;
    return _n ??= decodeTenths(bytes).where((v) => v > 0).length;
  }

  @override
  set length(int n) => _list.length = n;

  @override
  HrSample operator [](int index) => _list[index];

  @override
  void operator []=(int index, HrSample value) => _list[index] = value;

  @override
  void add(HrSample element) => _list.add(element);
}

/// Copy of [r] with a different hrSamples list (DayRecord.hrSamples is final).
/// Keep in sync with DayRecord's fields (contract: additive changes only).
DayRecord withHrSamples(DayRecord r, List<HrSample> samples) => DayRecord(
  date: r.date,
  hrvRmssd: r.hrvRmssd,
  restingHr: r.restingHr,
  respiratoryRate: r.respiratoryRate,
  spo2Avg: r.spo2Avg,
  spo2Min: r.spo2Min,
  skinTempDelta: r.skinTempDelta,
  vo2max: r.vo2max,
  steps: r.steps,
  weightKg: r.weightKg,
  sleepingHr4h: r.sleepingHr4h,
  sleepSessions: r.sleepSessions,
  workouts: r.workouts,
  hrSamples: samples,
  hrvSamples: r.hrvSamples,
  provenance: r.provenance,
  lastDataAt: r.lastDataAt,
);
