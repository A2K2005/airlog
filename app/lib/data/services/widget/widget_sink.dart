// Home-screen widget bridge. The repository pushes the newest day after
// every recompute; the Android AppWidgetProvider (AirlogWidgetProvider.kt)
// renders the snapshot without running Dart.

import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../../../domain/repositories.dart';
import '../../../domain/results.dart';

/// What the widget shows: the SAME day Today shows (the newest day with
/// data; QA-08), marked [stale] when that day isn't today, so the widget
/// never shows yesterday's numbers as today's.
class WidgetSnapshot {
  const WidgetSnapshot({
    this.date,
    this.recovery,
    this.zone,
    this.strain,
    this.sleepMinutes,
    this.demo = false,
    this.stale = false,
    this.quality = const [],
  });
  final String? date;
  final int? recovery;
  final String? zone;
  final double? strain;
  final double? sleepMinutes;
  final bool demo;
  final List<String> quality;

  /// The day shown is not [today] (no data for today yet).
  final bool stale;

  /// [days] newest first; [today] is the phone's current day key.
  factory WidgetSnapshot.fromDays(
    List<DayBundle> days, {
    required bool demo,
    String? today,
  }) {
    if (days.isEmpty) return WidgetSnapshot(demo: demo);
    final d = days.first;
    final strain = d.result.strain;
    final recovery = d.result.recovery;
    final sleep = d.result.sleep;
    return WidgetSnapshot(
      date: d.date,
      recovery: recovery?.calibrating == true ? null : recovery?.score,
      zone: recovery?.calibrating == true ? null : recovery?.zone.name,
      strain: strain == null || strain.method == StrainMethod.none
          ? null
          : strain.strain,
      sleepMinutes: sleep?.hasData == true && sleep!.sleptMinutes > 0
          ? sleep.sleptMinutes
          : null,
      quality: [
        if (recovery?.calibrating == true)
          'learning'
        else if (recovery != null &&
            (!d.result.calibration.established ||
                recovery.confidence != RecoveryConfidence.high))
          'provisional recovery',
        if (strain != null &&
            strain.method != StrainMethod.none &&
            strain.partial)
          'partial strain',
      ],
      demo: demo,
      stale: today != null && d.date != today,
    );
  }

  /// One payload keeps date, mode and values from different updates unmixed.
  Map<String, Object?> toJson({required DateTime updatedAt}) {
    final minutes = sleepMinutes?.round();
    return {
      'date': date ?? '',
      'recovery': recovery,
      'zone': zone ?? 'none',
      'strain': strain?.toStringAsFixed(1) ?? '–',
      'sleep': minutes == null || minutes <= 0
          ? '–'
          : '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m',
      'demo': demo,
      'quality': quality.join(' · '),
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }
}

abstract class WidgetSink {
  Future<void> push(WidgetSnapshot snapshot);
}

class NoopWidgetSink implements WidgetSink {
  const NoopWidgetSink();
  @override
  Future<void> push(WidgetSnapshot snapshot) async {}
}

/// Keys shared with android/app/src/main/kotlin/.../AirlogWidgetProvider.kt.
abstract final class WidgetKeys {
  static const snapshot = 'airlog_snapshot_v1'; // atomic JSON snapshot
  static const recovery = 'airlog_recovery'; // int 1..99 or -1
  static const zone = 'airlog_zone'; // green|yellow|red|none
  static const strain = 'airlog_strain'; // String "12.4" or "–"
  static const sleepHours = 'airlog_sleep'; // String "7h 12m" or "–"
  static const date = 'airlog_date'; // yyyy-MM-dd
  static const demo = 'airlog_demo'; // bool
  static const stale = 'airlog_stale'; // bool: the day shown isn't today
  static const updatedAt = 'airlog_updated_at'; // epoch ms
}

class HomeWidgetSink implements WidgetSink {
  const HomeWidgetSink();

  static const String androidProvider =
      'app.airlog.airlog.AirlogWidgetProvider';

  @override
  Future<void> push(WidgetSnapshot s) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        WidgetKeys.snapshot,
        jsonEncode(s.toJson(updatedAt: DateTime.now())),
      );
      // Retire pre-upgrade values even when no launcher widget is pinned.
      // The renderer reads only the atomic payload above.
      for (final key in const [
        WidgetKeys.recovery,
        WidgetKeys.zone,
        WidgetKeys.strain,
        WidgetKeys.sleepHours,
        WidgetKeys.date,
        WidgetKeys.demo,
        WidgetKeys.stale,
        WidgetKeys.updatedAt,
      ]) {
        await HomeWidget.saveWidgetData<Object>(key, null, deleteFile: false);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: androidProvider);
    } catch (_) {
      // No widget host (tests, desktop) or plugin missing in this isolate.
    }
  }
}
