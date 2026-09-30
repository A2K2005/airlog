// Phase 0 probe maths: per data type count, origins, devices, first/last,
// median spacing, samples/hour, plus plain-English verdicts that answer the
// PRODUCT_PLAN §5 Phase 0 decisions.

import '../../domain/repositories.dart';
import '../common/time.dart';

class ProbePoint {
  const ProbePoint(this.t, this.origin, {this.device, this.recordId});
  final DateTime t;
  final String origin;
  final String? device;
  final String? recordId;
}

/// Gaps longer than this are wear/charging gaps, not sample spacing.
const Duration kSpacingGapCap = Duration(minutes: 30);

DiagnosticsTypeStat buildTypeStat(
  String type,
  List<ProbePoint> pts, {
  String? primaryOrigin,
}) {
  final origins = <String, int>{};
  final devices = <String, int>{};
  for (final p in pts) {
    origins.update(p.origin, (v) => v + 1, ifAbsent: () => 1);
    final d = p.device;
    if (d != null && d.isNotEmpty) {
      devices.update(d, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  if (pts.isEmpty) {
    return DiagnosticsTypeStat(
      dataType: type,
      records: 0,
      origins: origins,
      devices: devices,
    );
  }
  // Spacing on the primary origin when given, else the dominant one.
  final origin = primaryOrigin != null && origins.containsKey(primaryOrigin)
      ? primaryOrigin
      : (origins.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
  final ts = [
    for (final p in pts)
      if (p.origin == origin) p.t,
  ]..sort();
  final gaps = <double>[];
  for (var i = 1; i < ts.length; i++) {
    final g = ts[i].difference(ts[i - 1]);
    if (g > Duration.zero && g <= kSpacingGapCap) {
      gaps.add(g.inMilliseconds / 1000);
    }
  }
  final hours = {for (final t in ts) t.millisecondsSinceEpoch ~/ 3600000}
      .length;
  final all = [for (final p in pts) p.t]..sort();
  return DiagnosticsTypeStat(
    dataType: type,
    records: pts.length,
    origins: origins,
    devices: devices,
    first: all.first,
    last: all.last,
    medianSpacingSec: gaps.isEmpty ? null : median(gaps),
    samplesPerHour: hours == 0 ? null : ts.length / hours,
  );
}

String _fmtSpacing(double s) =>
    s < 90 ? '${s.round()} s' : '${(s / 60).toStringAsFixed(1)} min';

List<String> buildVerdicts(
  Map<String, DiagnosticsTypeStat> stats, {
  required bool demo,
  HcPermissionState? perms,
  bool googleConfigured = false,
  int futureDated = 0,
  String Function(String origin)? appName,
}) {
  final v = <String>[];
  final prefix = demo ? 'Demo data: ' : '';
  String name(String o) => appName?.call(o) ?? o;
  // Any app counts (decision "Any app", 2026-09-29).
  int records(String type) => stats[type]?.records ?? 0;

  final hr = stats['HEART_RATE'];
  if (hr == null || records('HEART_RATE') == 0) {
    v.add(
      '${prefix}No heart rate from any app → no Strain score (Airlog only '
      'scores Strain from measured heart rate)',
    );
  } else {
    final s = hr.medianSpacingSec;
    if (s == null) {
      v.add(
        '${prefix}Heart rate: ${_count(hr.records, 'reading')}, spacing '
        'unknown',
      );
    } else if (s <= 70) {
      v.add('${prefix}Heart rate every ${_fmtSpacing(s)} → full Strain');
    } else {
      // "sparse" is the Diagnostics screen's concern keyword.
      v.add(
        '${prefix}Heart rate only every ${_fmtSpacing(s)} → sparse, so '
        'Strain uses the readings there are and is marked partial',
      );
    }
  }

  final hrv = stats['HEART_RATE_VARIABILITY_RMSSD'];
  if (hrv == null || records('HEART_RATE_VARIABILITY_RMSSD') == 0) {
    v.add(
      '${prefix}No HRV from any app → Recovery works without HRV (never '
      'guessed)',
    );
  } else {
    final s = hrv.medianSpacingSec;
    v.add(
      '${prefix}HRV: ${_count(hrv.records, 'reading')}'
      '${s == null ? '' : ', about every ${_fmtSpacing(s)}'} → nightly HRV '
      'from your main sleep',
    );
  }

  for (final (key, label) in [
    ('RESTING_HEART_RATE', 'Resting heart rate'),
    ('RESPIRATORY_RATE', 'Breathing rate'),
    ('SKIN_TEMPERATURE', 'Skin temperature'),
    ('SLEEP_SESSION', 'Sleep sessions'),
  ]) {
    final n = records(key);
    v.add(
      n > 0
          ? '$prefix$label: ${_count(n, 'record')}'
          : '$prefix$label: none from any app → Recovery works without it',
    );
  }

  if (!demo) {
    final devices = <String, int>{};
    for (final s in stats.values) {
      s.devices.forEach(
        (k, n) => devices.update(k, (x) => x + n, ifAbsent: () => n),
      );
    }
    if (devices.isEmpty) {
      v.add(
        'Device metadata: not captured (open the app in the foreground to read it)',
      );
    } else {
      final top =
          (devices.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
      v.add('Device metadata: most records come from "$top"');
    }
    for (final s in stats.values) {
      if (s.origins.length < 2) continue;
      final list =
          (s.origins.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .map((e) => '${name(e.key)} (${e.value})')
              .join(', ');
      v.add(
        'Several apps share ${s.dataType}: $list → Airlog uses one app per '
        'measurement (Settings → Data sources), never a mix',
      );
    }
    if (perms != null) {
      v.add(
        perms.historyGranted
            ? 'History allowed: Airlog reads up to 90 days back'
            : 'No history permission: Health Connect only shares about 30 '
                  'days before you first allowed it',
      );
      if (!perms.backgroundGranted) {
        // "not granted" is the Diagnostics screen's concern keyword.
        v.add(
          'Background reads not granted: Airlog syncs only while it’s open',
        );
      }
    }
    if (futureDated > 0) {
      v.add(
        '${_count(futureDated, 'record')} dated in the future (like calorie '
        'forecasts), ignored',
      );
    }
    final spo2 = records('BLOOD_OXYGEN');
    v.add(
      spo2 > 0
          ? 'Blood oxygen: ${_count(spo2, 'record')} → nightly value from '
                'your sleep'
          : googleConfigured
          ? 'Blood oxygen: none in Health Connect → comes from Enhanced mode'
          : 'Blood oxygen: none in Health Connect → Recovery skips the '
                'low-oxygen check',
    );
  } else {
    v.add(
      'Demo data: Sample data: a pretend tracker. Connect Health Connect to '
      'check your real one.',
    );
  }
  return v;
}

/// "1 record", "12 records".
String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';
