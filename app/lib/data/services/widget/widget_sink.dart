// Home-screen widget bridge. The repository pushes the newest day after
// every recompute; the Android AppWidgetProvider (AirlogWidgetProvider.kt)
// renders the snapshot without running Dart.

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
  });
  final String? date;
  final int? recovery;
  final String? zone;
  final double? strain;
  final double? sleepMinutes;
  final bool demo;

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
    return WidgetSnapshot(
      date: d.date,
      recovery: d.result.recovery?.score,
      zone: d.result.recovery?.zone.name,
      strain: strain == null || strain.method == StrainMethod.none
          ? null
          : strain.strain,
      sleepMinutes: d.record.totalSleepMinutes > 0
          ? d.record.totalSleepMinutes
          : null,
      demo: demo,
      stale: today != null && d.date != today,
    );
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
      final sleepMin = s.sleepMinutes ?? 0;
      await HomeWidget.saveWidgetData<int>(
        WidgetKeys.recovery,
        s.recovery ?? -1,
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetKeys.zone,
        s.zone ?? 'none',
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetKeys.strain,
        s.strain == null ? '–' : s.strain!.toStringAsFixed(1),
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetKeys.sleepHours,
        sleepMin <= 0
            ? '–'
            : '${sleepMin ~/ 60}h ${(sleepMin % 60).round().toString().padLeft(2, '0')}m',
      );
      await HomeWidget.saveWidgetData<String>(WidgetKeys.date, s.date ?? '');
      await HomeWidget.saveWidgetData<bool>(WidgetKeys.demo, s.demo);
      await HomeWidget.saveWidgetData<bool>(WidgetKeys.stale, s.stale);
      await HomeWidget.saveWidgetData<int>(
        WidgetKeys.updatedAt,
        DateTime.now().millisecondsSinceEpoch,
      );
      await HomeWidget.updateWidget(qualifiedAndroidName: androidProvider);
    } catch (_) {
      // No widget host (tests, desktop) or plugin missing in this isolate.
    }
  }
}
