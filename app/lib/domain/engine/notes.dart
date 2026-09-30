// Honesty notes: what is missing, why it may be missing, how to fix it.
// [ours, after Edge's StatusCard contract — a missing value is never replaced
// by a guessed number; the UI shows one of these instead]
//
// `metric` is a Metric.code ('hrv', 'rhr', 'resp', 'spo2', 'skin_temp',
// 'sleep', 'hr', 'steps', 'vo2max') or a score key ('recovery', 'strain',
// 'pulse_age').
//
// Wording: docs/COPY_REVIEW.md §4.7 (plain words, "your usual", Settings →
// Data sources). Screens route notes with [isCalibrating] and
// [isNewBaseline], never by matching titles themselves.

import '../models.dart';
import '../results.dart';
import 'source_apps.dart';

abstract final class Notes {
  static const _wearFix =
      'Wear your tracker to bed tonight, then open Airlog in the morning.';

  static StatusNote missingHrv({required bool seenBefore}) => StatusNote(
    metric: Metric.hrv.code,
    severity: NoteSeverity.warning,
    title: seenBefore ? 'No HRV for this night' : 'No HRV yet',
    body:
        'Airlog didn’t get HRV for this night, so Recovery used your other '
        'signals. This usually happens when the tracker wasn’t worn to bed, '
        'the HRV permission is off, or your tracker’s app isn’t sharing HRV '
        'with Health Connect.',
    fix:
        'Wear your tracker to bed, and check the HRV permission in Settings '
        '→ Data sources.',
  );

  static const _otherAppFix =
      'If another app on this phone shares it with Health Connect, pick that '
      'app in Settings → Data sources.';

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
            ? '$app doesn’t share HRV with Health Connect, so Recovery uses '
                  'your other signals, and each one counts a bit more. It’s '
                  'labelled “without HRV” and is less exact. Airlog never '
                  'guesses HRV from other data.'
            : '$app doesn’t share HRV with Health Connect. Airlog never '
                  'guesses HRV from other data.',
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
            ? '$app doesn’t share resting heart rate with Health Connect. '
                  'So Recovery uses your sleeping heart rate instead: your '
                  'average heart rate in the first 4 hours of sleep, from '
                  '$app’s own readings, compared with its own usual. It’s '
                  'less exact, and it’s never shown as resting heart rate.'
            : '$app doesn’t share resting heart rate with Health Connect, '
                  'so Recovery works without it. Airlog never guesses it from '
                  'other heart-rate data.',
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
            '$app doesn’t share HRV or resting heart rate with Health '
            'Connect, and last night’s heart rate was too patchy (or the '
            'sleep too short) to use your sleeping heart rate. Airlog shows '
            'no score rather than a guess. Sleep and Strain still work.',
        fix:
            '${_continuousHrFix(app, origin)} Or, if another app on this '
            'phone shares HRV or resting heart rate with Health Connect, '
            'pick it in Settings → Data sources.',
      );

  /// How to turn on all-day heart rate in [app]: Samsung Health's own
  /// setting by name, a generic sentence for every other app. Copy only.
  static String _continuousHrFix(String app, String? origin) =>
      origin == SourceApps.samsungHealth
      ? 'Turn on continuous heart-rate measurement in $app (Heart rate → '
            'Measure continuously).'
      : 'Turn on all-day heart rate in $app.';

  static StatusNote missingRhr({required bool seenBefore}) => StatusNote(
    metric: Metric.restingHr.code,
    severity: NoteSeverity.warning,
    title: seenBefore ? 'No resting heart rate' : 'No resting heart rate yet',
    body:
        'Your tracker saves resting heart rate after a night of wear. It’s '
        'missing when the tracker wasn’t worn, the Resting heart rate '
        'permission is off, or the latest sync hasn’t run yet.',
    fix: _wearFix,
  );

  static const StatusNote missingResp = StatusNote(
    metric: 'resp',
    title: 'No breathing rate',
    body:
        'Breathing rate is only measured during sleep. It’s missing when the '
        'tracker wasn’t worn to bed or the Respiratory rate permission is off '
        '(that’s its name in Health Connect). Recovery uses your other '
        'signals.',
    fix: _wearFix,
  );

  static const StatusNote missingSpo2 = StatusNote(
    metric: 'spo2',
    title: 'No blood oxygen',
    body:
        'No overnight blood-oxygen readings came in for this night. Some '
        'apps don’t share it with Health Connect. For some trackers, it can '
        'come from Enhanced mode instead. Without it, Recovery skips the '
        'low-oxygen check.',
    fix:
        'Check the Blood oxygen permission in Settings → Data sources, or '
        'turn on Enhanced mode there.',
  );

  static const StatusNote missingSkinTemp = StatusNote(
    metric: 'skin_temp',
    title: 'No skin temperature',
    body:
        'Skin temperature is measured during sleep, as a change from your '
        'tracker’s own usual. It’s missing when the tracker wasn’t worn to '
        'bed, the Skin temperature permission is off, or the tracker is '
        'still learning your usual (the first few nights).',
    fix: _wearFix,
  );

  static StatusNote missingSleep({required bool seenBefore}) => StatusNote(
    metric: 'sleep',
    severity: NoteSeverity.warning,
    title: seenBefore ? 'No sleep recorded' : 'No sleep recorded yet',
    body:
        'No sleep came in for this night, so there’s no sleep score, and '
        'your missed sleep stays the same. This usually happens when the '
        'tracker wasn’t worn to bed, the Sleep permission is off, or your '
        'tracker’s app hasn’t finished with the night yet.',
    fix: _wearFix,
  );

  static const StatusNote missingHr = StatusNote(
    metric: 'hr',
    title: 'No heart rate',
    body:
        'No heart rate came in for this day. It’s missing when the tracker '
        'wasn’t worn, the Heart rate permission is off, or the latest sync '
        'hasn’t run yet.',
    fix: 'Check the Heart rate permission in Settings → Data sources.',
  );

  /// Steps never feed Strain (Strain comes only from measured heart rate),
  /// so a missing count only leaves the activity list without them.
  static const StatusNote missingSteps = StatusNote(
    metric: 'steps',
    title: 'No step count',
    body:
        'No steps came in for this day, so your activity shows without '
        'them.',
    fix: 'Check the Steps permission in Settings → Data sources.',
  );

  static const StatusNote recoveryUnavailable = StatusNote(
    metric: 'recovery',
    severity: NoteSeverity.warning,
    title: 'No Recovery score',
    body:
        'Recovery needs HRV or resting heart rate from last night. Neither '
        'came in, so there’s no score rather than a guess.',
    fix: _wearFix,
  );

  /// The calibrating note's title; [isCalibrating] matches on it.
  static const recoveryCalibratingTitle = 'Learning your usual';

  /// [haveNights]: baseline nights of the least-calibrated reporting input
  /// ([metricName], e.g. "HRV" right after a source switch).
  static StatusNote recoveryCalibrating(
    int haveNights,
    String metricName,
  ) => StatusNote(
    metric: 'recovery',
    title: recoveryCalibratingTitle,
    body:
        'Recovery compares each night with your own usual. It starts to '
        'mean something after 5 nights of $metricName ($haveNights so far) '
        'and settles after 14. Until then, treat it as an early estimate.',
    fix: 'Keep wearing your tracker to bed.',
  );

  /// The Recovery calibrating note (Today shows its body in the banner).
  /// Also matches the pre-rewrite title of results stored before it.
  static bool isCalibrating(StatusNote n) =>
      n.metric == 'recovery' &&
      (n.title == recoveryCalibratingTitle ||
          n.title == 'Calibrating your baseline');

  static StatusNote strainPartialHr(double coverage) => StatusNote(
    metric: 'strain',
    severity: NoteSeverity.warning,
    title: 'Strain from patchy heart rate',
    body:
        'Only ${(coverage * 100).toStringAsFixed(0)}% of your waking minutes '
        'have heart rate, so this Strain is probably too low. Airlog only '
        'scores Strain from measured heart rate, never from steps or workout '
        'type.',
    fix: 'Check that heart rate from your tracker reaches Health Connect.',
  );

  static const StatusNote strainUnavailable = StatusNote(
    metric: 'strain',
    severity: NoteSeverity.warning,
    title: 'No Strain score',
    body:
        'No heart rate came in for this day, so there’s no Strain score. '
        'Airlog only scores Strain from measured heart rate. Your workouts '
        'and steps still show as activity.',
    fix:
        'Check the Heart rate and Steps permissions in Settings → Data '
        'sources.',
  );

  /// Heart rate arrived but there is no max HR to build zones from: no birth
  /// year, no override, and too little heart rate to observe a maximum.
  static const StatusNote strainNeedsMaxHr = StatusNote(
    metric: 'strain',
    severity: NoteSeverity.warning,
    title: 'Strain needs your max heart rate',
    body:
        'Heart-rate zones need a max heart rate. There’s no birth year or '
        'max heart rate set, and not enough heart rate yet to use your '
        'highest reading, so there’s no Strain score rather than a guess.',
    fix:
        'Add your birth year (or a measured max heart rate) in Settings → '
        'Profile.',
  );

  static const StatusNote strainInvalidAnchors = StatusNote(
    metric: 'strain',
    severity: NoteSeverity.warning,
    title: 'Can’t set heart-rate zones',
    body:
        'Heart rate came in, but your max and resting heart rates don’t leave '
        'a usable range, so there’s no Strain score.',
    fix:
        'Check your max heart rate in Settings → Profile, and where your '
        'resting heart rate comes from in Settings → Data sources.',
  );

  /// No resting HR today: zones use % of max HR (Swain 1994) instead of
  /// heart-rate reserve, and there is no TRIMP cross-check.
  static const StatusNote zonesFromMaxHr = StatusNote(
    metric: 'strain',
    title: 'Zones from max heart rate',
    body:
        'No resting heart rate came in, so your zones use a share of your max '
        'heart rate instead (a published method). Airlog never guesses a '
        'resting heart rate.',
  );

  /// No birth year: zones use the highest heart rate observed in the last
  /// 90 days (DayEngine.observedMaxDays).
  static StatusNote observedMaxHr(double maxHr) => StatusNote(
    metric: 'strain',
    title: 'Zones use your highest heart rate',
    body:
        'No birth year is set, so your zones use the highest heart rate seen '
        'in the last 90 days (${maxHr.toStringAsFixed(0)} bpm). If you rarely '
        'train hard, your zones and Strain may read high.',
    fix:
        'Add your birth year (or a measured max heart rate) in Settings → '
        'Profile.',
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
    final so = nights == 0
        ? 'It’s starting from tonight.'
        : 'It has $nights ${nights == 1 ? 'night' : 'nights'} so far.';
    final String body;
    if (sameMeasure &&
        now.origin == before.origin &&
        now.device != null &&
        before.device != null &&
        now.device != before.device) {
      // Same app, different device (e.g. a Fitbit Air, then a Pixel Watch).
      body =
          'Your $m now comes from your ${now.device} instead of your '
          '${before.device}. Each device measures a little differently, so '
          'Airlog is learning your usual again instead of mixing the two. '
          '$so';
    } else if (sameMeasure && now.origin != before.origin) {
      // Same measurement, different app (e.g. Fitbit → Samsung Health).
      body =
          'Your $m now comes from ${appName(now, names)} instead of '
          '${appName(before, names)}. Each app measures a little '
          'differently, so Airlog is learning your usual again instead of '
          'mixing the two. $so';
    } else {
      body =
          'Your $m is now measured a different way (${_describe(now, names)}, '
          'before: ${_describe(before, names)}), so Airlog is learning your '
          'usual again instead of mixing the two. $so';
    }
    return StatusNote(
      metric: metric.code,
      title: 'Learning your $m again',
      body: body,
    );
  }

  /// A source-switch note from [newBaseline] (Today gives it a full card).
  /// Also matches the pre-rewrite "New … baseline" titles of stored results.
  static bool isNewBaseline(StatusNote n) =>
      (n.title.startsWith('Learning your ') && n.title.endsWith(' again')) ||
      (n.title.startsWith('New ') && n.title.endsWith(' baseline'));

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

  static String _metricName(Metric m) => switch (m) {
    Metric.hrv => 'HRV',
    Metric.restingHr => 'resting heart rate',
    Metric.respiratoryRate => 'breathing rate',
    Metric.spo2 => 'blood oxygen',
    Metric.skinTemp => 'skin temperature',
    _ => m.code,
  };
}
