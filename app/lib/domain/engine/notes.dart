// Honesty notes: what is missing, why it may be missing, how to fix it.
// [ours, after Edge's StatusCard contract — a missing value is never replaced
// by a guessed number; the UI shows one of these instead]
//
// `metric` is a Metric.code ('hrv', 'rhr', 'resp', 'spo2', 'skin_temp',
// 'sleep', 'hr', 'steps', 'vo2max') or a score key ('recovery', 'strain',
// 'pulse_age').

import '../models.dart';
import '../results.dart';
import 'source_apps.dart';

abstract final class Notes {
  static const _wearFix =
      'Wear your tracker to bed tonight, then open Airlog in '
      'the morning so it can sync.';

  static StatusNote missingHrv({required bool seenBefore}) => StatusNote(
    metric: Metric.hrv.code,
    severity: NoteSeverity.warning,
    title: seenBefore ? 'No HRV for this night' : 'No HRV yet',
    body:
        'Airlog received no heart-rate variability for this night, so '
        'Recovery uses the other inputs. Usual causes: the tracker was not '
        'worn to bed, the Health Connect permission for HRV is off, or the '
        'source app (e.g. Google Health) is not writing HRV to Health '
        'Connect.',
    fix:
        'Wear your tracker overnight and check the HRV permission in '
        'Settings → Sources.',
  );

  static const _otherAppFix =
      'If another app on this phone writes it to Health Connect, choose '
      'that app in Settings → Sources.';

  /// [app] has written other nightly data for several nights but never HRV:
  /// a limit of that app's Health Connect sharing, not a wear problem.
  /// Recovery is scored "without HRV" (never with an estimated HRV).
  /// [scored] false: there is no Recovery at all (see [recoveryNotShared]).
  static StatusNote hrvNotShared(String app, {bool scored = true}) =>
      StatusNote(
        metric: Metric.hrv.code,
        severity: NoteSeverity.warning,
        title: scored ? 'Recovery without HRV' : 'No HRV from $app',
        body: scored
            ? '$app doesn\'t share HRV with Health Connect, so Recovery is '
                  'scored from your other inputs with their weights '
                  're-balanced. It is labelled "without HRV" and has lower '
                  'confidence. Airlog never estimates HRV from other data.'
            : '$app doesn\'t share HRV with Health Connect. Airlog never '
                  'estimates HRV from other data.',
        fix: _otherAppFix,
      );

  /// [app] writes other nightly data but never resting heart rate.
  /// [sleepingHr]: Recovery used "Sleeping HR (4 h mean)" in its slot.
  static StatusNote rhrNotShared(String app, {bool sleepingHr = false}) =>
      StatusNote(
        metric: Metric.restingHr.code,
        severity: NoteSeverity.warning,
        title: 'No resting heart rate from $app',
        body: sleepingHr
            ? '$app doesn\'t share resting heart rate with Health Connect. '
                  'Recovery uses your sleeping heart rate instead (the '
                  'mean of the first 4 hours of sleep, from $app\'s own '
                  'readings) against its own baseline, and has lower '
                  'confidence. It is never shown as resting heart rate.'
            : '$app doesn\'t share resting heart rate with Health Connect, '
                  'so Recovery goes without it. Airlog never estimates it '
                  'from other heart-rate data.',
        fix: _otherAppFix,
      );

  /// Neither HRV nor resting HR: [app] (display name) shares neither (e.g.
  /// Samsung Health). [origin]: its package, used ONLY to pick the fix copy
  /// (Samsung Health's own setting by name); never for scoring.
  static StatusNote recoveryNotShared(String app, {String? origin}) =>
      StatusNote(
        metric: 'recovery',
        severity: NoteSeverity.warning,
        title: 'No Recovery score',
        body:
            '$app doesn\'t share HRV or resting heart rate with Health '
            'Connect, and last night\'s heart rate was too sparse (or the '
            'sleep too short) for a sleeping heart rate. Airlog shows no '
            'score rather than a guess; Sleep and Strain still work.',
        fix:
            '${_continuousHrFix(app, origin)} Or, if another app on this '
            'phone writes HRV or resting heart rate to Health Connect, '
            'choose it in Settings → Sources.',
      );

  /// How to turn on all-day heart rate in [app]: Samsung Health's own
  /// setting by name, a generic sentence for every other app. Copy only.
  static String _continuousHrFix(String app, String? origin) =>
      origin == SourceApps.samsungHealth
      ? 'Turn on continuous heart-rate measurement in $app (Heart rate → '
            'Measure continuously).'
      : 'Turn on continuous heart rate in $app.';

  static StatusNote missingRhr({required bool seenBefore}) => StatusNote(
    metric: Metric.restingHr.code,
    severity: NoteSeverity.warning,
    title: seenBefore ? 'No resting heart rate' : 'No resting heart rate yet',
    body:
        'Resting heart rate is written after a night of wear. It is '
        'missing when the tracker was not worn, the Resting heart rate '
        'permission is off, or the latest sync has not run yet.',
    fix: _wearFix,
  );

  static const StatusNote missingResp = StatusNote(
    metric: 'resp',
    title: 'No respiratory rate',
    body:
        'Respiratory rate is only measured during sleep. It is missing '
        'when the tracker was not worn to bed or the Respiratory rate permission '
        'is off. Recovery re-weights the other inputs.',
    fix: _wearFix,
  );

  static const StatusNote missingSpo2 = StatusNote(
    metric: 'spo2',
    title: 'No SpO₂',
    body:
        'No overnight blood-oxygen readings arrived for this night. Some '
        'apps don\'t share SpO₂ with Health Connect; for a Fitbit it can '
        'come from the Google Health API (Enhanced mode). Without it '
        'Recovery skips the low-oxygen check.',
    fix:
        'Check the Blood oxygen permission in Settings → Sources, or turn '
        'on Enhanced mode for a Fitbit.',
  );

  static const StatusNote missingSkinTemp = StatusNote(
    metric: 'skin_temp',
    title: 'No skin temperature',
    body:
        'Skin temperature is measured during sleep and reported as a '
        'change from the tracker\'s own baseline. It is missing when the '
        'tracker was not worn to bed, the Skin temperature permission is '
        'off, or the tracker is still establishing its baseline (first few '
        'nights).',
    fix: _wearFix,
  );

  static StatusNote missingSleep({required bool seenBefore}) => StatusNote(
    metric: 'sleep',
    severity: NoteSeverity.warning,
    title: seenBefore ? 'No sleep recorded' : 'No sleep recorded yet',
    body:
        'No sleep session arrived for this night, so there is no sleep '
        'performance and sleep debt is carried forward unchanged. Usual '
        'causes: the tracker was not worn to bed, the Sleep permission is '
        'off, or the source app has not finished processing the night yet.',
    fix: _wearFix,
  );

  static const StatusNote missingHr = StatusNote(
    metric: 'hr',
    title: 'No heart-rate samples',
    body:
        'No intraday heart rate arrived for this day. It is missing when '
        'the tracker was not worn, the Heart rate permission is off, or the '
        'latest sync has not run yet.',
    fix: 'Check the Heart rate permission in Settings → Sources.',
  );

  static const StatusNote missingSteps = StatusNote(
    metric: 'steps',
    title: 'No step count',
    body:
        'No steps arrived for this day, so the fallback strain estimate '
        'cannot include everyday activity. Check the Steps permission.',
    fix: 'Check the Steps permission in Settings → Sources.',
  );

  static const StatusNote recoveryUnavailable = StatusNote(
    metric: 'recovery',
    severity: NoteSeverity.warning,
    title: 'No Recovery score',
    body:
        'Recovery needs HRV or resting heart rate from last night. Neither '
        'arrived, so no score is shown rather than a guess.',
    fix: _wearFix,
  );

  /// [haveNights]: baseline nights of the least-calibrated reporting input
  /// ([metricName], e.g. "HRV" right after a source switch).
  static StatusNote recoveryCalibrating(
    int haveNights,
    String metricName,
  ) => StatusNote(
    metric: 'recovery',
    title: 'Calibrating your baseline',
    body:
        'Recovery compares each night with your own baseline. It '
        'becomes reliable after 5 nights of $metricName ($haveNights so far) '
        'and is fully established after 14; until then treat it as '
        'provisional.',
    fix: 'Keep wearing your tracker to bed.',
  );

  static StatusNote strainPartialHr(double coverage) => StatusNote(
    metric: 'strain',
    severity: NoteSeverity.warning,
    title: 'Strain from partial heart rate',
    body:
        'Only ${(coverage * 100).toStringAsFixed(0)} % of waking minutes '
        'have heart rate, so this strain likely under-counts the day. Airlog '
        'scores strain only from measured heart rate, never from steps or '
        'workout type.',
    fix: 'Check that heart-rate data from your tracker reaches Health Connect.',
  );

  static const StatusNote strainUnavailable = StatusNote(
    metric: 'strain',
    severity: NoteSeverity.warning,
    title: 'No Strain score',
    body:
        'No heart rate arrived for this day, so there is no Strain score. '
        'Airlog scores strain only from measured heart rate; any workouts '
        'and steps still show as activity.',
    fix: 'Check the Heart rate and Steps permissions in Settings → Sources.',
  );

  /// Heart rate arrived but there is no max HR to build zones from: no birth
  /// year, no override, and too little heart rate to observe a maximum.
  static const StatusNote strainNeedsMaxHr = StatusNote(
    metric: 'strain',
    severity: NoteSeverity.warning,
    title: 'Strain needs your max heart rate',
    body:
        'Heart-rate zones need a maximum heart rate. No birth year or max HR '
        'is set, and there is not yet enough heart rate to use your highest '
        'observed value, so no Strain score is shown rather than a guess.',
    fix: 'Add your birth year (or a measured max HR) in Settings → Profile.',
  );

  static const StatusNote strainInvalidAnchors = StatusNote(
    metric: 'strain',
    severity: NoteSeverity.warning,
    title: 'Heart-rate zones unavailable',
    body:
        'Heart rate arrived, but the maximum and resting heart rates do not '
        'provide a usable range. No Strain score is calculated from these anchors.',
    fix: 'Review your max HR in Settings → Profile and your resting-HR source.',
  );

  /// No resting HR today: zones use % of max HR (Swain 1994) instead of
  /// heart-rate reserve, and there is no TRIMP cross-check.
  static const StatusNote zonesFromMaxHr = StatusNote(
    metric: 'strain',
    title: 'Zones from max heart rate',
    body:
        'No resting heart rate arrived, so heart-rate zones use a share of '
        'your max heart rate (a published conversion) instead of your heart-'
        'rate reserve. Airlog never assumes a resting heart rate.',
  );

  /// No birth year: zones use the highest heart rate observed in the last
  /// 90 days (DayEngine.observedMaxDays).
  static StatusNote observedMaxHr(double maxHr) => StatusNote(
    metric: 'strain',
    title: 'Zones use your highest observed heart rate',
    body:
        'No birth year is set, so heart-rate zones use the highest heart '
        'rate seen in the last 90 days (${maxHr.toStringAsFixed(0)} bpm). '
        'If you rarely train hard, zones and strain may read high.',
    fix: 'Add your birth year (or a measured max HR) in Settings → Profile.',
  );

  /// No longer emitted (algo v2 never assumes an age); kept only while
  /// screens still reference its title.
  static StatusNote assumedMaxHr(double maxHr) => StatusNote(
    metric: 'strain',
    title: 'Using an assumed max heart rate',
    body:
        'Heart-rate zones use ${maxHr.toStringAsFixed(0)} bpm, the '
        'Tanaka estimate for age 30, because no birth year or max HR is '
        'set. Zones and strain may be off.',
    fix: 'Add your birth year (or a measured max HR) in Settings → Profile.',
  );

  /// [names]: display names for origin packages the known-package table
  /// lacks (platform app labels, from EngineConfig.appNames).
  static StatusNote newBaseline(
    Metric metric,
    Provenance now,
    Provenance before,
    int nights, {
    Map<String, String> names = const {},
  }) {
    final m = _metricName(metric);
    final sameMeasure =
        now.source == before.source && now.definition == before.definition;
    final String body;
    if (sameMeasure &&
        now.origin == before.origin &&
        now.device != null &&
        before.device != null &&
        now.device != before.device) {
      // Same app, different device (e.g. a Fitbit Air, then a Pixel Watch).
      body =
          '${_cap(m)} now comes from your ${now.device} instead of your '
          '${before.device}. Each device measures in its own way, so Airlog '
          'started a fresh baseline instead of mixing the two; it has '
          '$nights earlier nights so far.';
    } else if (sameMeasure && now.origin != before.origin) {
      // Same measurement, different app (e.g. Fitbit → Samsung Health).
      body =
          '${_cap(m)} now comes from ${appName(now, names)} instead of '
          '${appName(before, names)}. Each app measures in its own way, so '
          'Airlog started a fresh baseline instead of mixing the two; it has '
          '$nights earlier nights so far.';
    } else {
      body =
          '${_cap(m)} now comes from ${_describe(now, names)}, which is '
          'measured differently from before (${_describe(before, names)}). '
          'Airlog started a fresh baseline instead of mixing the two; it has '
          '$nights earlier nights so far.';
    }
    return StatusNote(
      metric: metric.code,
      title: 'New $m baseline',
      body: body,
    );
  }

  /// App name for [p]: the known-package table, else [names] (platform
  /// label), else the package, else the source label.
  static String appName(Provenance p, [Map<String, String> names = const {}]) {
    final o = p.origin;
    if (o != null) {
      final known = SourceApps.knownName(o);
      if (known != null) return known;
      final label = names[o];
      if (label != null && label.isNotEmpty) return label;
    }
    return SourceApps.nameOf(p);
  }

  static String _describe(Provenance p, Map<String, String> names) =>
      p.origin == null ? p.label : '${p.label} from ${appName(p, names)}';

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _metricName(Metric m) => switch (m) {
    Metric.hrv => 'HRV',
    Metric.restingHr => 'resting HR',
    Metric.respiratoryRate => 'respiratory rate',
    Metric.spo2 => 'SpO₂',
    Metric.skinTemp => 'skin temperature',
    _ => m.code,
  };
}
