// Test doubles for the data layer.

import 'package:airlog/data/resolver/definitions.dart';
import 'package:airlog/data/services/health_connect/hc_types.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';

/// In-memory Health Connect with a changes feed.
class FakeHealthConnect implements HealthConnectSource {
  FakeHealthConnect({
    Set<HcType>? granted,
    this.history = false,
    this.background = true,
  }) : granted = granted ?? HcType.values.toSet();

  Set<HcType> granted;
  bool history;
  bool background;
  HcAvailability avail = HcAvailability.available;

  /// Current records by id (one id may have several records: HR samples,
  /// sleep stages).
  final Map<String, List<HcRecord>> store = {};

  /// Pending change events since the last issued token.
  final List<HcRecord> _upserts = [];
  final List<String> _deletes = [];
  int _tokenSeq = 0;
  bool expireNext = false;
  bool failChangesNext = false;
  final Set<HcType> failingTypes = {};
  final List<(HcType, DateTime, DateTime)> reads = [];
  int changesCalls = 0;

  void put(List<HcRecord> recs, {bool asChange = true}) {
    final ids = {for (final r in recs) r.id};
    for (final id in ids) {
      store[id] = [
        for (final r in recs)
          if (r.id == id) r,
      ];
    }
    if (asChange) {
      // Like the plugin: sleep changes carry the session only.
      _upserts.addAll(
        recs.where((r) => !(r.type == HcType.sleep && r.stage != null)),
      );
    }
  }

  void delete(String id) {
    store.remove(id);
    _deletes.add(id);
  }

  @override
  Future<HcAvailability> availability() async => avail;

  @override
  Future<HcPermissionState> permissionState() async => HcPermissionState(
    availability: avail,
    granted: [
      for (final t in HcType.values)
        if (granted.contains(t)) t.key,
    ],
    missing: [
      for (final t in HcType.values)
        if (!granted.contains(t)) t.key,
    ],
    historyGranted: history,
    backgroundGranted: background,
  );

  @override
  Future<HcPermissionState> requestPermissions() async {
    granted = HcType.values.toSet();
    return permissionState();
  }

  @override
  Future<bool> supports(HcType type) async => true;

  @override
  Future<List<HcRecord>> read(HcType type, DateTime from, DateTime to) async {
    reads.add((type, from, to));
    if (failingTypes.contains(type)) throw StateError('boom $type');
    return [
      for (final l in store.values)
        for (final r in l)
          if (r.type == type && r.end.isAfter(from) && r.start.isBefore(to)) r,
    ];
  }

  @override
  Future<String?> changesToken(List<HcType> types) async {
    _upserts.clear();
    _deletes.clear();
    return 'tok${++_tokenSeq}';
  }

  @override
  Future<HcChangesPage?> changes(String token) async {
    changesCalls++;
    if (failChangesNext) {
      failChangesNext = false;
      return null;
    }
    if (expireNext) {
      expireNext = false;
      return const HcChangesPage(
        upserts: [],
        deletedIds: [],
        nextToken: '',
        hasMore: false,
        expired: true,
      );
    }
    final page = HcChangesPage(
      upserts: [..._upserts],
      deletedIds: [..._deletes],
      nextToken: 'tok${++_tokenSeq}',
      hasMore: false,
      expired: false,
    );
    _upserts.clear();
    _deletes.clear();
    return page;
  }
}

HcRecord hr(
  String id,
  DateTime t,
  double bpm, {
  String origin = kFitbitOrigin,
}) => HcRecord(
  type: HcType.heartRate,
  id: id,
  origin: origin,
  start: t,
  end: t,
  value: bpm,
);

HcRecord hrv(String id, DateTime t, double v) => HcRecord(
  type: HcType.hrv,
  id: id,
  origin: kFitbitOrigin,
  start: t,
  end: t,
  value: v,
);

HcRecord scalar(
  HcType type,
  String id,
  DateTime t,
  double v, {
  String origin = kFitbitOrigin,
  DateTime? end,
}) => HcRecord(
  type: type,
  id: id,
  origin: origin,
  start: t,
  end: end ?? t,
  value: v,
);

/// A sleep session + its stage records (as the plugin returns them).
List<HcRecord> night(
  String id,
  DateTime bed,
  DateTime wake, {
  DateTime? lastModified,
  String origin = kFitbitOrigin,
}) {
  final total = wake.difference(bed).inMinutes;
  final third = total ~/ 3;
  final a = bed.add(Duration(minutes: third));
  final b = bed.add(Duration(minutes: 2 * third));
  return [
    HcRecord(
      type: HcType.sleep,
      id: id,
      origin: origin,
      start: bed,
      end: wake,
      lastModified: lastModified,
    ),
    HcRecord(
      type: HcType.sleep,
      id: id,
      origin: origin,
      start: bed,
      end: a,
      stage: SleepStage.light,
    ),
    HcRecord(
      type: HcType.sleep,
      id: id,
      origin: origin,
      start: a,
      end: b,
      stage: SleepStage.deep,
    ),
    HcRecord(
      type: HcType.sleep,
      id: id,
      origin: origin,
      start: b,
      end: wake,
      stage: SleepStage.rem,
    ),
  ];
}
