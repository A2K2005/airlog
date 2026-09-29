// Copy that more than one screen must say identically:
//
//   * hcReadTypes   the Health Connect types Airlog reads and why. The ONE
//                   list behind the privacy policy, the onboarding rationale
//                   and the Sources rationale sheet. Keep it in step with the
//                   permissions declared in android/app/src/main/
//                   AndroidManifest.xml.
//   * hcTypeName    human names for Health Connect record types.
//   * SettingsCopy  labels the privacy policy points at ("Settings → …").
//   * CoachCopy     the coach's disclosure, consent, engine and model copy.
//                   The chat, Coach setup, Settings and the privacy policy
//                   all print these, so what the consent sheet promises is
//                   exactly what the policy says.
//
// Shared kit for features/: imports no feature.

import '../domain/coach/coach_contracts.dart';
import '../domain/coach/insight_contracts.dart';

/// Health Connect data types read, and the feature each one powers. Order
/// and wording follow the manifest and docs/PLAY_RELEASE.md §2.
const hcReadTypes = <(String, String)>[
  ('Heart rate', 'Strain and heart-rate zones across the day.'),
  ('Heart rate variability (RMSSD)', 'The main input to Recovery.'),
  ('Resting heart rate', 'Recovery and the Health Monitor.'),
  ('Respiratory rate', 'Recovery and the Health Monitor.'),
  (
    'Skin temperature',
    'The Health Monitor. A change from your usual range can be an early '
        'sign you are run down.',
  ),
  (
    'Sleep sessions and stages',
    'Sleep performance, debt, consistency, and Recovery.',
  ),
  ('Exercise sessions', 'Per-workout strain.'),
  ('Steps', 'An estimate of strain when heart rate is too sparse.'),
  ('Weight (optional)', 'Only if you grant it, shown next to your trends.'),
  ('VO₂ max', 'A cardio-fitness trend, shown as your tracker’s own estimate.'),
  (
    'Blood oxygen (SpO₂)',
    'Overnight SpO₂ in the Health Monitor, and a Recovery penalty when it '
        'is below 90 %.',
  ),
  ('Distance', 'Needed to read your exercise sessions. Shown on each workout.'),
  (
    'Total calories burned',
    'Needed to read your exercise sessions. Shown on each workout.',
  ),
  (
    'History and background reads (optional)',
    'Older data so baselines start on day 1, and background syncing so '
        'the morning Recovery and the widget are ready.',
  ),
];

/// "Heart rate" for 'HEART_RATE'; unknown keys are title-cased.
String hcTypeName(String key) => switch (key) {
  'HEART_RATE' => 'Heart rate',
  'HEART_RATE_VARIABILITY_RMSSD' => 'Heart rate variability',
  'RESTING_HEART_RATE' => 'Resting heart rate',
  'RESPIRATORY_RATE' => 'Respiratory rate',
  'SKIN_TEMPERATURE' => 'Skin temperature',
  'SLEEP_SESSION' => 'Sleep',
  'WORKOUT' => 'Exercise',
  'STEPS' => 'Steps',
  'WEIGHT' => 'Weight',
  'VO2_MAX' => 'VO₂ max',
  'BLOOD_OXYGEN' => 'SpO₂',
  'DISTANCE_DELTA' => 'Distance',
  'TOTAL_CALORIES_BURNED' => 'Calories',
  'OXYGEN_SATURATION' => 'SpO₂',
  _ =>
    key
        .toLowerCase()
        .split('_')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' '),
};

/// Settings labels that other screens (the privacy policy) refer to by name.
abstract final class SettingsCopy {
  static const exportTitle = 'Export everything';
  static const deleteTitle = 'Delete all data';

  /// "Settings → Delete all data".
  static const deletePath = 'Settings → $deleteTitle';

  /// "Settings → Export everything".
  static const exportPath = 'Settings → $exportTitle';
}

// ── The coach ("Ask") ─────────────────────────────────────────────────────

/// Labels of the coach's settings page (Settings → Coach), which the
/// privacy policy points at.
abstract final class CoachSettingsCopy {
  static const title = 'Coach';

  /// "Settings → Coach".
  static const path = 'Settings → $title';

  static const withdrawTitle = 'Turn off the cloud engine';
}

/// A model a cloud engine can use, with its approximate cost per question.
class CoachModel {
  const CoachModel(this.provider, this.id, this.name, this.cost);
  final CoachProvider provider;

  /// The provider's model id, sent with each request ('claude-opus-5-5').
  final String id;

  /// Display name ('Opus 5.5').
  final String name;

  /// Approximate cost of one question at list prices. An estimate: it
  /// depends on the question, and the provider bills the user's own key.
  final String cost;
}

/// Everything the coach discloses, in one place: the chat, Coach setup,
/// Settings → Coach and the privacy policy print these strings, so the
/// consent sheet and the policy cannot drift apart.
abstract final class CoachCopy {
  /// Version of the consent text. Bump it when what the setup screen
  /// promises changes; a consent stored with an older version asks again.
  static const consentVersion = 1;

  // ── standing lines ──────────────────────────────────────────────────────
  static const notMedical = 'Wellness info, not medical advice.';
  static const checked = 'Checked against your data';
  static const fallback = "Showing facts only — couldn't verify the answer";
  static const askAboutThis = 'Ask about this';
  static const askAboutToday = 'Ask about today';

  /// The chat's empty state when the engine is on-device.
  static const onDeviceCan =
      'On-device answers a fixed set of questions about your Recovery, '
      'Sleep, Strain, trends and journal, from the numbers on this phone. '
      'It has no AI model, so it cannot hold an open conversation.';

  // ── engines ─────────────────────────────────────────────────────────────
  static const onDeviceBody =
      'Nothing leaves your phone. Answers a fixed set of questions about '
      'your data.';
  static const claudeBody =
      "Bring your own Anthropic API key. Anthropic doesn't train on API "
      'data; deletes it within 30 days.';
  static const geminiBody =
      'Bring your own Gemini API key. It must be on a billing-enabled '
      '(paid) Google Cloud project.';
  static const geminiWarning =
      'Free Gemini keys may be used to train Google’s models, and people at '
      'Google may read what is sent. Use a key from a paid project only. '
      'Gemini is for adults (18+) and is not for medical advice.';

  static String providerName(CoachProvider p) => switch (p) {
    CoachProvider.offline => 'On-device',
    CoachProvider.claude => 'Claude',
    CoachProvider.gemini => 'Gemini',
  };

  /// Who receives a request.
  static String company(CoachProvider p) => switch (p) {
    CoachProvider.offline => 'nobody',
    CoachProvider.claude => 'Anthropic',
    CoachProvider.gemini => 'Google',
  };

  static const models = <CoachModel>[
    CoachModel(
      CoachProvider.claude,
      'claude-opus-5-5',
      'Opus 5.5',
      '≈ \$0.02–0.05',
    ),
    CoachModel(
      CoachProvider.claude,
      'claude-sonnet-5-5',
      'Sonnet 5.5',
      '≈ \$0.01–0.02',
    ),
    CoachModel(
      CoachProvider.claude,
      'claude-haiku-4-5',
      'Haiku 4.5',
      '< \$0.01',
    ),
    CoachModel(
      CoachProvider.gemini,
      'gemini-3.8-flash',
      '3.8 Flash',
      '≈ \$0.01',
    ),
    CoachModel(
      CoachProvider.gemini,
      'gemini-3.5-flash-lite',
      '3.5 Flash-Lite',
      '< \$0.01',
    ),
  ];

  static List<CoachModel> modelsFor(CoachProvider p) => [
    for (final m in models)
      if (m.provider == p) m,
  ];

  /// The model a cloud engine uses when the settings name none.
  static String? defaultModel(CoachProvider p) => switch (p) {
    CoachProvider.offline => null,
    CoachProvider.claude => 'claude-opus-5-5',
    CoachProvider.gemini => 'gemini-3.8-flash',
  };

  /// The catalogue entry for [id] (or the default), or null on-device. An id
  /// the catalogue does not know is shown as itself.
  static CoachModel? model(CoachProvider p, String? id) {
    if (p == CoachProvider.offline) return null;
    final want = id ?? defaultModel(p)!;
    for (final m in models) {
      if (m.provider == p && m.id == want) return m;
    }
    return CoachModel(p, want, want, '');
  }

  /// "On-device", "Claude · Opus 5.5", "Gemini · 3.8 Flash".
  static String engineLabel(CoachProvider p, String? modelId) {
    final m = model(p, modelId);
    return m == null ? providerName(p) : '${providerName(p)} · ${m.name}';
  }

  static String modeLabel(CoachMode m) => switch (m) {
    CoachMode.useMyData => 'Uses your data',
    CoachMode.generalOnly => 'General only',
  };

  // ── modes ───────────────────────────────────────────────────────────────
  static const useMyDataBody =
      'Coach looks up only the numbers a question needs (your scores, '
      'sleep, workouts and journal), and every number it quotes is checked '
      'against the ones stored on this phone.';
  static const generalOnlyBody =
      'Coach answers from general sleep and training science, like a '
      'textbook. It never looks at your data and sends none of it.';

  // ── what leaves the phone ───────────────────────────────────────────────

  /// Sent with a question in "Use my data", and only what that question
  /// needs.
  static const sentWithData = <String>[
    'Your question and the conversation so far',
    'Computed daily scores (Recovery, Strain, Sleep) for the days asked '
        'about',
    'Sleep and workout summaries (times, durations, stages, averages)',
    'Journal tags, such as “Alcohol” or “Late meal”',
    'Memories you confirmed',
  ];

  /// Sent with a question in "General only".
  static const sentGeneral = <String>[
    'Your question and the conversation so far',
  ];

  /// Never sent, in either mode.
  static const neverSent = <String>[
    'Raw heart-rate streams, or any second-by-second reading',
    'Google Health API (Enhanced mode) data, or scores built from it',
    'Anything that names you: Airlog has no account',
  ];

  /// Who receives it.
  static String recipient(CoachProvider p) => switch (p) {
    CoachProvider.offline => 'Nothing is sent.',
    CoachProvider.claude =>
      'Sent to Anthropic (the Claude API), using your key. Never to Airlog: '
          'there is no Airlog server.',
    CoachProvider.gemini =>
      'Sent to Google (the Gemini API), using your key. Never to Airlog: '
          'there is no Airlog server.',
  };

  /// What the provider does with it.
  static String retention(CoachProvider p) => switch (p) {
    CoachProvider.offline => 'Nothing is sent, so nothing is kept elsewhere.',
    CoachProvider.claude =>
      "Anthropic doesn't train on API data and deletes it within 30 days.",
    CoachProvider.gemini =>
      "On a paid project Google doesn't train on it, and keeps it up to 55 "
          'days to detect abuse.',
  };

  static const keyStorage =
      'Your key is kept in Android’s keystore (encrypted secure storage) on '
      'this phone. It is never written to Airlog’s database or exports, is '
      'never shown again, and is sent only to the provider, with each '
      'question.';

  /// Shown at the start of every cloud chat session (Anthropic's usage
  /// policy asks for it; Google's terms rule out medical advice).
  static String aiDisclosure(CoachProvider p) =>
      'You’re chatting with an AI: ${providerName(p)}, by ${company(p)}. '
      'It can be wrong. Numbers with a source chip come from your data. '
      '$notMedical';

  // ── consent ─────────────────────────────────────────────────────────────
  static const adult = 'I’m 18 or older';
  static const paidKey = 'My key is on a paid (billing-enabled) project';

  /// "I agree — turn on Claude".
  static String agree(CoachProvider p) =>
      'I agree — turn on ${providerName(p)}';

  static const withdrawBody =
      'Deletes your key from this phone and switches back to on-device. '
      'Chats and memories stay on this phone until you delete them.';

  // ── memories ────────────────────────────────────────────────────────────
  static const memoryAbout =
      'Only facts you confirmed, never health numbers: those always come '
      'fresh from your data. Memories stay on this phone, and are sent as '
      'context only while a cloud engine is on.';

  // ── the privacy policy's section ────────────────────────────────────────
  static const privacyTitle = 'Ask, the coach';
  static const privacyOnDevice =
      'Ask answers questions about your data. By default it runs entirely '
      'on this phone: a fixed set of questions answered from the scores '
      'stored here, with no AI model. Nothing is sent anywhere.';
  static const privacyCloud =
      'You can choose a cloud engine instead: Claude (Anthropic) or Gemini '
      '(Google), with your own API key. Only after you agree on the setup '
      'screen does a question send data off the phone, and then only to '
      'the provider you chose, never to Airlog. In “Use my data” mode that '
      'is:';
  static const privacyGeneral =
      'In “General only” mode, only your question and the conversation are '
      'sent. Never sent, in either mode:';
  static const privacyMemories =
      'Memories are facts you confirmed (“training for a half marathon”), '
      'never health numbers. They stay on this phone, and are sent as '
      'context only while a cloud engine is on.';
  static const privacyDelete =
      'Chats and memories are stored on this phone. Delete any chat or '
      'memory, or all of them, in Ask. ${CoachSettingsCopy.path} → '
      '${CoachSettingsCopy.withdrawTitle} deletes the key and stops all '
      'sending. Deleting on the phone does not reach copies a provider '
      'already holds under the retention above.';

  /// The chat's standing line while a cloud (AI) engine answers. The
  /// on-device engine has no AI model, so it keeps [notMedical].
  static const aiDisclaimer = 'AI can make mistakes. Not medical advice.';

  /// Settings → Coach: the master switch. Off hides every entry point.
  static const showCoach = 'Show coach';
  static const showCoachBody =
      'Off hides Ask and the coach cards everywhere. Your chats and '
      'memories stay on this phone.';

  /// The calm banner when today's cloud budget is spent.
  static const usageSpent =
      'Today’s question limit for your AI provider is used up. It resets '
      'tomorrow. On-device answers still work.';

  /// The tag on coach answers and insight cards in demo mode.
  static const sampleData = 'Sample data';
}

/// The insight cards (the coach's short notes on the detail screens). The
/// card text itself comes from the InsightService; these are the labels
/// around it. Never streak language: the product says "Consistency (X of Y
/// days)".
abstract final class InsightCopy {
  static String kind(InsightKind k) => switch (k) {
    InsightKind.sleep => 'Sleep',
    InsightKind.recovery => 'Recovery',
    InsightKind.strain => 'Strain',
    InsightKind.workout => 'Workout',
    InsightKind.healthMonitor => 'Health',
    InsightKind.weekly => 'This week',
  };

  static const discuss = 'Discuss';
  static const aiSummary = 'AI summary';
  static const options = 'Card options';
  static const hide = 'Hide this card';
  static const why = 'Why am I seeing this?';
  static const settings = 'Coach messages settings';
  static const hidden = 'Card hidden';
  static const usingMemory = 'Using what you told me';

  static const whyLede =
      'Coach writes a short note when there is something new in your data '
      'for this day. It is built from these numbers:';
  static const writtenOnDevice =
      'Written on this phone with fixed wording, from the numbers above. '
      'Nothing was sent anywhere.';
  static const writtenByAi =
      'An AI summary, not a fact: your AI provider reworded the on-device '
      'note from the numbers above, and every number was checked against '
      'your data on this phone.';
  static const memoriesUsed = 'What you told Coach, used here';

  // ── Settings → Coach → Coach messages ───────────────────────────────────
  static const levelTitle = 'Coach messages';

  /// On = InsightLevel.basic (v1 has no AI-written cards).
  static const messagesOnBody =
      'Short notes on the detail screens, written on this phone with fixed '
      'wording. Nothing is sent.';
  static const messagesOffBody =
      'No coach cards. Screens show only your numbers.';

  static const usageTitle = 'Today’s usage';
}
