// Health Connect via the `health` 13.3.2 plugin + our Kotlin channel
// (`airlog/health_connect`, android/app/src/main/kotlin/.../HealthConnectBridge.kt).
//
// Verified in the plugin source (D:/dev/pub-cache/hosted/pub.dev/health-13.3.2):
//   * the origin package is in `sourceName`; `sourceId` is always "";
//   * no device metadata / lastModifiedTime is exposed → our channel's
//     `recordMeta` returns them per record id (joined here by uuid);
//   * the Kotlin reader swallows every exception and returns [] (and [] for
//     types without a granted permission) → we compute 'denied' from the
//     granted-permission set, never from an empty result;
//   * getHealthDataFromTypes throws for the whole list if ONE type is
//     unavailable → we always call it with a single type;
//   * getChanges/getChangesToken return null on failure; deletions carry only
//     a record id; SLEEP_SESSION upserts carry no stages;
//   * VO2 max is not mapped at all → read through the channel.
// The channel is registered by MainActivity, so in the workmanager isolate
// it is missing: VO2 max + device metadata are skipped there (next
// foreground sync fills them) and permissions fall back to the plugin.

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../../../domain/models.dart';
import '../../../domain/repositories.dart';
import '../../common/source_exception.dart';
import 'hc_mapper.dart';
import 'hc_types.dart';

const MethodChannel kHcChannel = MethodChannel('airlog/health_connect');

/// The installed app's label from Android's PackageManager (null when the
/// package isn't visible or the channel is absent, e.g. the background
/// isolate or tests). Visibility comes from the manifest `queries`.
Future<String?> platformAppLabel(String package) async {
  if (!Platform.isAndroid) return null;
  try {
    return await kHcChannel.invokeMethod<String>('appLabel', {
      'package': package,
    });
  } catch (_) {
    return null;
  }
}

HealthDataType? pluginTypeOf(HcType t) => switch (t) {
  HcType.heartRate => HealthDataType.HEART_RATE,
  HcType.hrv => HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
  HcType.restingHr => HealthDataType.RESTING_HEART_RATE,
  HcType.respiratoryRate => HealthDataType.RESPIRATORY_RATE,
  HcType.skinTemp => HealthDataType.SKIN_TEMPERATURE,
  HcType.sleep => HealthDataType.SLEEP_SESSION,
  HcType.exercise => HealthDataType.WORKOUT,
  HcType.steps => HealthDataType.STEPS,
  HcType.weight => HealthDataType.WEIGHT,
  HcType.spo2 => HealthDataType.BLOOD_OXYGEN,
  HcType.distance => HealthDataType.DISTANCE_DELTA,
  HcType.totalCalories => HealthDataType.TOTAL_CALORIES_BURNED,
  HcType.vo2max => null,
};

HcType? hcTypeOfPlugin(HealthDataType t) => switch (t) {
  HealthDataType.HEART_RATE => HcType.heartRate,
  HealthDataType.HEART_RATE_VARIABILITY_RMSSD => HcType.hrv,
  HealthDataType.RESTING_HEART_RATE => HcType.restingHr,
  HealthDataType.RESPIRATORY_RATE => HcType.respiratoryRate,
  HealthDataType.SKIN_TEMPERATURE => HcType.skinTemp,
  HealthDataType.SLEEP_SESSION => HcType.sleep,
  HealthDataType.WORKOUT => HcType.exercise,
  HealthDataType.STEPS => HcType.steps,
  HealthDataType.WEIGHT => HcType.weight,
  HealthDataType.BLOOD_OXYGEN => HcType.spo2,
  _ => null,
};

const _stageTypes = [
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_REM,
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_AWAKE_IN_BED,
  HealthDataType.SLEEP_OUT_OF_BED,
  HealthDataType.SLEEP_ASLEEP,
];

/// Converts one plugin data point (also used for change-token upserts).
HcRecord? recordFromPoint(HealthDataPoint p, {HcType? as, SleepStage? stage}) {
  final type = as ?? hcTypeOfPlugin(p.type);
  if (type == null) return null;
  double? value;
  String? workoutType;
  double? distance, energy;
  final v = p.value;
  if (v is NumericHealthValue) value = v.numericValue.toDouble();
  if (v is SkinTemperatureHealthValue) value = v.temperatureDelta;
  if (v is WorkoutHealthValue) {
    workoutType = v.workoutActivityType.name;
    distance = v.totalDistance?.toDouble();
    energy = v.totalEnergyBurned?.toDouble();
  }
  return HcRecord(
    type: type,
    id: p.uuid,
    origin: p.sourceName.isNotEmpty ? p.sourceName : p.sourceId,
    start: p.dateFrom,
    end: p.dateTo,
    value: type == HcType.sleep || type == HcType.exercise ? null : value,
    stage: stage,
    workoutType: workoutType,
    distanceM: distance,
    energyKcal: energy,
    recordingMethod: switch (p.recordingMethod) {
      RecordingMethod.active => HcRecordingMethod.active,
      RecordingMethod.automatic => HcRecordingMethod.automatic,
      RecordingMethod.manual => HcRecordingMethod.manual,
      _ => HcRecordingMethod.unknown,
    },
  );
}

class HealthConnectPluginSource implements HealthConnectSource {
  HealthConnectPluginSource({Health? health, this.channel = kHcChannel})
    : _h = health ?? Health();

  final Health _h;
  final MethodChannel channel;
  bool _configured = false;

  Future<void> _cfg() async {
    if (_configured) return;
    await _h.configure();
    _configured = true;
  }

  static List<String> get allPermissions => [
    for (final t in HcType.values) t.permission,
    kPermHistory,
    kPermBackground,
  ];

  @override
  Future<HcAvailability> availability() async {
    if (!Platform.isAndroid) return HcAvailability.unsupported;
    try {
      await _cfg();
      final s = await _h.getHealthConnectSdkStatus();
      return switch (s) {
        HealthConnectSdkStatus.sdkAvailable => HcAvailability.available,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
          HcAvailability.updateRequired,
        HealthConnectSdkStatus.sdkUnavailable => HcAvailability.notInstalled,
        null => HcAvailability.unsupported,
      };
    } catch (_) {
      return HcAvailability.unsupported;
    }
  }

  Future<Set<String>?> _grantedViaChannel() async {
    try {
      final l = await channel.invokeListMethod<String>('grantedPermissions');
      return l?.toSet();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  HcPermissionState _state(HcAvailability a, Set<String> granted) {
    final g = <String>[], m = <String>[];
    for (final t in HcType.values) {
      (granted.contains(t.permission) ? g : m).add(t.key);
    }
    return HcPermissionState(
      availability: a,
      granted: g,
      missing: m,
      historyGranted: granted.contains(kPermHistory),
      backgroundGranted: granted.contains(kPermBackground),
    );
  }

  @override
  Future<HcPermissionState> permissionState() async {
    final a = await availability();
    if (a != HcAvailability.available) {
      return HcPermissionState(
        availability: a,
        granted: const [],
        missing: [for (final t in HcType.values) t.key],
      );
    }
    final viaChannel = await _grantedViaChannel();
    if (viaChannel != null) return _state(a, viaChannel);
    // Background isolate: ask the plugin type by type.
    final granted = <String>{};
    for (final t in HcType.values) {
      final pt = pluginTypeOf(t);
      if (pt == null) continue;
      try {
        if (await _h.hasPermissions([pt]) == true) granted.add(t.permission);
      } catch (_) {}
    }
    try {
      if (await _h.isHealthDataHistoryAuthorized()) granted.add(kPermHistory);
      if (await _h.isHealthDataInBackgroundAuthorized()) {
        granted.add(kPermBackground);
      }
    } catch (_) {}
    return _state(a, granted);
  }

  @override
  Future<HcPermissionState> requestPermissions() async {
    final a = await availability();
    if (a != HcAvailability.available) return permissionState();
    try {
      // One sheet for every type + VO2 + history + background.
      final res = await channel.invokeListMethod<String>('requestPermissions', {
        'permissions': allPermissions,
      });
      if (res != null) return _state(a, res.toSet());
    } on MissingPluginException {
      // fall through to the plugin
    } on PlatformException {
      // fall through to the plugin
    }
    final types = [
      for (final t in HcType.values)
        if (pluginTypeOf(t) != null) pluginTypeOf(t)!,
    ];
    try {
      await _h.requestAuthorization(types);
      await _h.requestHealthDataHistoryAuthorization();
      await _h.requestHealthDataInBackgroundAuthorization();
    } catch (_) {}
    return permissionState();
  }

  @override
  Future<bool> supports(HcType type) async {
    if (type == HcType.skinTemp) {
      try {
        return await _h.isSkinTemperatureAvailable();
      } catch (_) {
        return false;
      }
    }
    if (type == HcType.vo2max) {
      try {
        await channel.invokeMethod<int>('sdkInt');
        return true;
      } catch (_) {
        return false; // channel absent (background isolate)
      }
    }
    return true;
  }

  Future<List<HealthDataPoint>> _points(
    HealthDataType t,
    DateTime from,
    DateTime to,
  ) => _h.getHealthDataFromTypes(types: [t], startTime: from, endTime: to);

  @override
  Future<List<HcRecord>> read(HcType type, DateTime from, DateTime to) async {
    await _cfg();
    try {
      if (type == HcType.vo2max) return await _readVo2(from, to);
      final pt = pluginTypeOf(type)!;
      final out = <HcRecord>[
        for (final p in await _points(pt, from, to))
          ?recordFromPoint(p, as: type),
      ];
      if (type == HcType.sleep) {
        for (final st in _stageTypes) {
          try {
            final stage = hcStageFromKey(st.name);
            for (final p in await _points(st, from, to)) {
              final r = recordFromPoint(p, as: HcType.sleep, stage: stage);
              if (r != null && stage != null) out.add(r);
            }
          } catch (_) {
            // one stage type failing must not drop the others
          }
        }
      }
      return await _withMeta(type, from, to, out);
    } on SourceException {
      rethrow;
    } catch (e) {
      throw SourceException(SourceKind.healthConnect, type.key, e);
    }
  }

  Future<List<HcRecord>> _withMeta(
    HcType type,
    DateTime from,
    DateTime to,
    List<HcRecord> recs,
  ) async {
    if (recs.isEmpty) return recs;
    try {
      final raw = await channel.invokeListMethod<Map<Object?, Object?>>(
        'recordMeta',
        {
          'type': type.key,
          'startMs': from.millisecondsSinceEpoch,
          'endMs': to.millisecondsSinceEpoch,
        },
      );
      if (raw == null || raw.isEmpty) return recs;
      final meta = <String, HcRecordMeta>{
        for (final m in raw)
          m['id'] as String: HcRecordMeta(
            m['id'] as String,
            origin: m['origin'] as String?,
            device: m['device'] as String?,
            lastModified: m['lastModified'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    (m['lastModified'] as num).toInt(),
                  ),
          ),
      };
      return [
        for (final r in recs)
          meta[r.id] == null
              ? r
              : r.withMeta(
                  device: meta[r.id]!.device,
                  lastModified: meta[r.id]!.lastModified,
                ),
      ];
    } catch (_) {
      return recs; // background isolate / older bridge: no metadata
    }
  }

  Future<List<HcRecord>> _readVo2(DateTime from, DateTime to) async {
    final List<Map<Object?, Object?>>? raw;
    try {
      raw = await channel.invokeListMethod<Map<Object?, Object?>>(
        'readVo2Max',
        {
          'startMs': from.millisecondsSinceEpoch,
          'endMs': to.millisecondsSinceEpoch,
        },
      );
    } on MissingPluginException catch (e) {
      throw SourceException(
        SourceKind.healthConnect,
        'VO2_MAX',
        e,
        status: 'skipped',
      );
    }
    return [
      for (final m in raw ?? const <Map<Object?, Object?>>[])
        HcRecord(
          type: HcType.vo2max,
          id: m['id'] as String,
          origin: (m['origin'] as String?) ?? '',
          start: DateTime.fromMillisecondsSinceEpoch(
            (m['time'] as num).toInt(),
          ),
          end: DateTime.fromMillisecondsSinceEpoch((m['time'] as num).toInt()),
          value: (m['vo2'] as num?)?.toDouble(),
          device: m['device'] as String?,
          lastModified: m['lastModified'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (m['lastModified'] as num).toInt(),
                ),
        ),
    ];
  }

  @override
  Future<String?> changesToken(List<HcType> types) async {
    await _cfg();
    final pts = [
      for (final t in types)
        if (pluginTypeOf(t) != null) pluginTypeOf(t)!,
    ];
    if (pts.isEmpty) return null;
    try {
      return await _h.getChangesToken(types: pts);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<HcChangesPage?> changes(String token) async {
    await _cfg();
    try {
      final r = await _h.getChanges(changesToken: token);
      if (r == null) return null;
      return HcChangesPage(
        upserts: [
          for (final c in r.changes)
            if (c.type == HealthChangeType.upsert && c.dataPoint != null)
              ?recordFromPoint(c.dataPoint!),
        ],
        deletedIds: r.deletedRecordIds,
        nextToken: r.nextChangesToken,
        hasMore: r.hasMore,
        expired: r.changesTokenExpired,
      );
    } catch (_) {
      return null;
    }
  }
}
