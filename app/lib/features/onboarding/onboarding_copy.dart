// Onboarding's strings, in one place (docs/COPY_REVIEW.md §3.10, reworked by
// the onboarding redesign). Plain words, sentence case, verb-first buttons.
//
// No brand names: "Health Connect" is the one platform name allowed, because
// it is the name on the system permission screen the user sees next. The
// non-affiliation line lives in Settings, Licences and Methodology.
// test/features/onboarding/onboarding_screen_test.dart sweeps every step for
// brand names.

abstract final class OnboardingCopy {
  // ── shared ────────────────────────────────────────────────────────────
  static const next = 'Next';
  static const back = 'Back';
  static String counter(int page, int of) => '$page of $of';

  /// Footnote on every onboarding ⓘ sheet (replaces "Not WHOOP’s formula").
  static const sheetFootnote =
      'Our own formula, worked out on this phone. Not medical advice.';

  // ── 1 · welcome ───────────────────────────────────────────────────────
  static const welcomeTitle = 'One clear answer every morning';
  static const getStarted = 'Get started';
  static const notMedical = 'Not medical advice.';

  /// The sample Recovery tile (the same labels Today passes).
  static const heroTitle = 'Your body is ready';
  static const heroScore = '78';
  static const heroStatus = 'Good';
  static const heroStatA = 'HRV vs usual';
  static const heroValueA = '+13%';
  static const heroStatB = 'Resting HR vs usual';
  static const heroValueB = '−3 bpm';
  static const heroLabel =
      'Sample Recovery: your body is ready. 78 percent, Good. HRV 13% above '
      'your usual. Resting heart rate 3 bpm below your usual.';

  static const recovery = 'Recovery';
  static const strain = 'Strain';
  static const sleep = 'Sleep';
  static String about(String name) => 'About $name';

  static const recoveryLede =
      'How ready your body is today. Airlog compares last night’s heart and '
      'sleep data with your usual.';
  static const recoveryZonesTitle = 'Good, Fair, Low';
  static String recoveryZones(String green, String yellow, String greenLess) =>
      'Good is $green% and up. Fair is $yellow–$greenLess%. Low is below '
      '$yellow%.';
  static String strainLede(String max) =>
      'How hard your heart worked today, from 0 to $max. The higher it gets, '
      'the harder it is to climb.';
  static const sleepLede =
      'How much of your sleep goal you got. 100% means you met it.';
  static const missedSleepTitle = 'Missed sleep';
  static const missedSleepBody =
      'Sleep you needed but didn’t get over recent nights. It goes down when '
      'you sleep longer than your goal.';

  // ── 2 · works with ────────────────────────────────────────────────────
  static const worksTitle = 'Works with the tracker you already have';
  static const devices = ['Watch', 'Ring', 'Band', 'Phone'];
  static const healthConnect = 'Health Connect';
  static const airlog = 'Airlog';
  static const worksBody =
      'If your tracker shares data with Health Connect, Airlog can read it.';
  static const worksLabel =
      'Works with watches, rings, bands and phones. $worksBody';
  static const phoneTitle = 'On your phone';
  static const phoneBody =
      'Your scores are worked out here. No account. No ads.';
  static const readOnlyTitle = 'Read only';
  static const readOnlyBody = 'Airlog never changes your data.';
  static const coachCaveat =
      'Coach can use the internet, but only if you turn it on.';
  static const privacyPolicy = 'Read the privacy policy';

  // ── 3 · choose ────────────────────────────────────────────────────────
  static const chooseTitle = 'How do you want to start?';
  static const chooseLede = 'You can switch any time in Settings.';
  static const errorTitle = 'That didn’t work';

  static const trackerTitle = 'Use my tracker';
  static const trackerBody =
      'Airlog reads it through Health Connect. You choose what to share.';
  static const sampleTitle = 'Try sample data';
  static const sampleBody = 'Look around with 90 days of sample data.';
  static const sampleBusy = 'Setting up sample data…';
  static const sampleLabel =
      '$sampleTitle. $sampleBody Every screen is marked Sample data.';

  static const birthYear = 'Birth year';
  static const birthYearCaption = 'Optional · for ages 18+';
  static const birthYearAdd = 'Add';
  static const birthYearAddLabel = 'Add birth year, optional';
  static String birthYearSetLabel(int y) => 'Birth year, $y. Change';
  static const birthYearWhyTitle = 'Why birth year?';
  static const birthYearWhyLede =
      'It sets your heart-rate zones, so Strain fits your body. Without it, '
      'Airlog uses an estimate.';
  static const adultsTitle = 'For ages 18+';
  static const adultsBody = 'Airlog is for people 18 and over.';
  static const changeLaterTitle = 'Change it later';
  static const changeLaterBody = 'Settings → Profile.';

  static const sheetTitle = 'Your birth year';
  static const sheetLede = 'For ages 18+.';
  static const save = 'Save';
  static const removeBirthYear = 'Remove birth year';

  // ── view-model errors (O26) ───────────────────────────────────────────
  static String adultsOnly(int min, int max) =>
      'Airlog is for adults. Pick a year between $min and $max, or leave it '
      'blank.';
  static const sampleFailed = 'Couldn’t load sample data. Try again.';
  static const setupFailed = 'Access is on, but setup didn’t finish. Try again.';

  /// On the tracker tile (or "Try again") while Android's sheet is open.
  static const waitingForHc = 'Waiting for Health Connect…';

  // ── 3b · denied ───────────────────────────────────────────────────────
  static const deniedTitle = 'Not connected';
  static const trySampleInstead = 'Try sample data instead';
  static const tryAgain = 'Try again';
  static const openHcSettings = 'Open Health Connect settings';

  static const notInstalledTitle = 'Health Connect isn’t installed';
  static const notInstalledBody =
      'Install it from your phone’s app store. Turn on syncing in your '
      'tracker’s app. Then connect in Settings → Data sources.';
  static const updateTitle = 'Health Connect needs an update';
  static const updateBody =
      'Update it from your phone’s app store. Then connect in Settings → '
      'Data sources.';
  static const unsupportedTitle = 'Health Connect isn’t available here';
  static const unsupportedBody =
      'This phone can’t run Health Connect. You can still look around with '
      'sample data.';
  static const nothingSharedTitle = 'Nothing shared yet';
  static const nothingSharedBody =
      'Airlog needs at least one kind of data to work. Nothing was changed.';
  static const deniedTwiceBody =
      'Your phone won’t ask again. Open Health Connect settings and allow '
      'Airlog there.';
  static const noAnswerTitle = 'Health Connect didn’t answer';
  static const noAnswerBody = 'Nothing was changed. Try again in a moment.';
}
