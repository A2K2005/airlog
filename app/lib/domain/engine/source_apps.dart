// Health Connect origin packages → display names. [ours]
//
// Pure Dart so the engine (StatusNote copy), TodayPlanner (TodayPlan.sources)
// and the data layer (SourceApp.displayName) read the same table. Every
// package below was checked against its Google Play listing
// (play.google.com/store/apps/details?id=<package>, page title) on
// 2026-09-29. Unknown packages fall back to the platform app label (data
// layer, PackageManager) and then to the package name itself.

import '../models.dart';

abstract final class SourceApps {
  static const String fitbit = 'com.fitbit.FitbitMobile';
  static const String samsungHealth = 'com.sec.android.app.shealth';
  static const String whoop = 'com.whoop.android';
  static const String oura = 'com.ouraring.oura';
  static const String garmin = 'com.garmin.android.apps.connectmobile';
  static const String googleFit = 'com.google.android.apps.fitness';
  static const String withings = 'com.withings.wiscale2';
  static const String polar = 'fi.polar.polarflow';
  static const String coros = 'com.yf.smart.coros.dist';
  static const String zepp = 'com.huami.watch.hmwatchmanager';
  static const String zeppLife = 'com.xiaomi.hm.health';
  static const String miFitness = 'com.xiaomi.wearable';

  /// Play listing title → the short name used in copy.
  static const Map<String, String> known = {
    fitbit: 'Google Health (Fitbit)',
    samsungHealth: 'Samsung Health',
    whoop: 'WHOOP',
    oura: 'Oura',
    garmin: 'Garmin Connect',
    googleFit: 'Google Fit',
    withings: 'Withings',
    polar: 'Polar Flow',
    coros: 'COROS',
    zepp: 'Zepp',
    zeppLife: 'Zepp Life',
    miFitness: 'Mi Fitness',
  };

  /// Display name for a known package, else null.
  static String? knownName(String? origin) =>
      origin == null ? null : known[origin];

  /// Display name for [origin]: known name, else [fallback] (e.g. the
  /// platform label), else the package itself.
  static String displayName(String origin, {String? fallback}) =>
      known[origin] ??
      (fallback != null && fallback.isNotEmpty ? fallback : origin);

  /// Name of the app behind [p] for copy: the known app name, else the
  /// origin package, else the source ("Health Connect", "Demo data").
  static String nameOf(Provenance p) =>
      knownName(p.origin) ??
      (p.origin != null && p.origin!.isNotEmpty ? p.origin! : null) ??
      p.source.label;
}
