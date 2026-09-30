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
    'The Health Monitor compares changes with your usual recorded range. '
        'A change is not a diagnosis.',
  ),
  (
    'Sleep sessions and stages',
    'Sleep performance, debt, consistency, and Recovery.',
  ),
  ('Exercise sessions', 'Per-workout strain.'),
  (
    'Steps',
    'Activity context alongside your trends. Steps do not produce a strain score.',
  ),
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
  static const exportTitle = 'Export readings and scores';
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

  static const withdrawTitle = 'Turn off cloud answers';
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

/// Everything the coach discloses, in one place: the chat, the Connect
/// sheet in Settings → Coach and the privacy policy print these strings, so
/// the consent sheet and the policy cannot drift apart.
abstract final class CoachCopy {
  /// Version of the consent text. Bump it when what the Connect sheet
  /// promises changes; a consent stored with an older version asks again.
  /// Wording-only edits (COPY_REVIEW D9) keep the version.
  static const consentVersion = 1;

  // ── standing lines ──────────────────────────────────────────────────────
  static const notMedical = 'Wellness info, not medical advice.';
  static const askAboutThis = 'Ask about this';
  static const askAboutToday = 'Ask about today';

  /// The chat's empty state when the engine is on this phone.
  static const onDeviceCan =
      'The on-phone coach answers set questions about your Recovery, Sleep, '
      'Strain, trends and journal. It isn’t an AI, so it can’t chat freely.';

  /// The chat's one, dismissible nudge towards a cloud engine.
  static const connectHint =
      'For fuller answers, connect Claude or Gemini in Settings';

  // ── engines ─────────────────────────────────────────────────────────────
  static const onDeviceBody =
      'Nothing leaves your phone. Answers set questions about your data.';
  static const claudeBody =
      'Uses your own Anthropic API key. Anthropic doesn’t train on it, and '
      'deletes it within 30 days.';
  static const geminiBody =
      'Uses your own Gemini API key, which must be from a paid Google Cloud '
      'project.';
  static const geminiWarning =
      'With a free Gemini key, Google may use what you send to train its '
      'models, and people at Google may read it. Only use a key from a paid '
      'project. Gemini is for adults 18 and over, and isn’t for medical '
      'advice.';

  static String providerName(CoachProvider p) => switch (p) {
    CoachProvider.offline => 'On this phone',
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

  /// A model's short name: the catalogue's ('3.5 Flash-Lite'), else read
  /// from the id ('claude-opus-4-8' → 'Opus 4.8'; a provider can answer
  /// with a model outside the catalogue), else the id itself.
  static String modelName(CoachProvider p, String id) {
    for (final m in models) {
      if (m.provider == p && m.id == id) return m.name;
    }
    final c = RegExp(r'^claude-(opus|sonnet|haiku)-(\d+)-(\d+)').firstMatch(id);
    if (c != null) {
      final family = c.group(1)!;
      return '${family[0].toUpperCase()}${family.substring(1)} '
          '${c.group(2)}.${c.group(3)}';
    }
    final g = RegExp(r'^gemini-(\d+(?:\.\d+)?)-(flash|pro)(-lite)?')
        .firstMatch(id);
    if (g != null) {
      final kind = g.group(2) == 'pro' ? 'Pro' : 'Flash';
      return '${g.group(1)} $kind${g.group(3) == null ? '' : '-Lite'}';
    }
    return id;
  }

  // ── model fallback ──────────────────────────────────────────────────────
  static const backupModels = 'Use a backup model when busy';

  static String backupModelsBody(CoachProvider p) {
    final who = providerName(p);
    return 'If your $who model is busy or hits its limit, a smaller $who '
        'model answers with the same key. Never another company. If none '
        'can answer, Coach answers on this phone.';
  }

  /// Which engine wrote an answer, when it wasn't the chosen model: "Answered
  /// by 3.5 Flash-Lite", or why it was answered on this phone (the answer's
  /// ⋯ menu). Null when the chosen model answered.
  static String? answeredByNote(CoachProvider p, ChatMessage m) {
    final by = m.answeredBy;
    if (!m.fellBack || by == null) return null;
    if (by != ChatMessage.onDevice) return 'Answered by ${modelName(p, by)}';
    final who = providerName(p);
    final why = switch (m.fallbackReason) {
      'invalidKey' =>
        '$who didn’t accept your API key. Check it in '
            '${CoachSettingsCopy.path}',
      'quotaExceeded' => 'your $who account is out of credit',
      'dailyLimit' => 'today’s $who limit is used up',
      'network' => '$who couldn’t be reached',
      'notConfigured' =>
        '$who needs a quick review in ${CoachSettingsCopy.path}',
      _ => '$who isn’t available right now',
    };
    return 'Answered on this phone: $why.';
  }

  /// The action under an answer written on this phone as the fallback.
  static String askAgain(CoachProvider p) => 'Ask ${providerName(p)} again';

  /// "On-device", "Claude · Opus 5.5", "Gemini · 3.8 Flash".
  static String engineLabel(CoachProvider p, String? modelId) {
    final m = model(p, modelId);
    return m == null ? providerName(p) : '${providerName(p)} · ${m.name}';
  }

  static String modeLabel(CoachMode m) => switch (m) {
    CoachMode.useMyData => 'With my data',
    CoachMode.generalOnly => 'General only',
  };

  // ── modes ───────────────────────────────────────────────────────────────
  static const useMyDataBody =
      'Coach looks up only the numbers a question needs (scores, sleep, '
      'workouts and journal), and Airlog checks every number it quotes. '
      'Data from Enhanced mode (Google Health) never leaves your phone. To '
      'ask about it, use On this phone.';
  static const generalOnlyBody =
      'Coach answers from general sleep and training know-how, like a '
      'textbook. It sends only your question, including anything personal '
      'you type. It can’t see your health data.';

  // ── what leaves the phone ───────────────────────────────────────────────

  /// Sent with a question "With my data", and only what that question
  /// needs.
  static const sentWithData = <String>[
    'Your question, and earlier messages in this chat with the same mode '
        'and provider',
    'Your daily scores (Recovery, Strain, Sleep) for the days you ask about',
    'Sleep and workout summaries (times, durations, stages, averages)',
    'Journal tags, such as “Alcohol” or “Late meal”',
    'Facts you told Coach to remember',
  ];

  /// Sent with a question in "General only".
  static const sentGeneral = <String>[
    'Only your current question. Earlier messages aren’t sent.',
  ];

  /// Never sent, in either mode.
  static const neverSent = <String>[
    'Raw heart-rate readings, second by second',
    'Enhanced mode (Google Health) data, or scores built from it',
    'Account details: Airlog has no account',
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
      'Your key is locked in this phone’s secure storage. Airlog never '
      'saves it anywhere else, never shows it again, and sends it only to '
      'your provider, with each question.';

  /// [keyStorage], naming the provider that receives the key.
  static String keyStorageFor(CoachProvider p) =>
      'Your key is locked in this phone’s secure storage. Airlog never '
      'saves it anywhere else, never shows it again, and sends it only to '
      '${company(p)}, with each question.';

  /// Shown at the start of every cloud chat session (Anthropic's usage
  /// policy asks for it; Google's terms rule out medical advice).
  static String aiDisclosure(CoachProvider p) =>
      'You’re chatting with an AI: ${providerName(p)}, by ${company(p)}. '
      'It can make mistakes. $notMedical';

  // ── consent ─────────────────────────────────────────────────────────────
  static const adult = 'I’m 18 or older';
  static const paidKey = 'My key is from a paid (billing-enabled) project';

  /// "I agree: turn on Claude".
  static String agree(CoachProvider p) =>
      'I agree: turn on ${providerName(p)}';

  static const withdrawBody =
      'Deletes your key from this phone and switches back to On this phone. '
      'Your chats and memories stay until you delete them.';

  // ── memories ────────────────────────────────────────────────────────────
  static const memoryAbout =
      'These are facts you told Coach, not measurements. Your health numbers '
      'always come fresh from your data. Facts stay on this phone, and are '
      'only sent with your questions while Claude or Gemini is on.';

  // ── the privacy policy's section ────────────────────────────────────────
  static const privacyTitle = 'Coach';
  static const privacyOnDevice =
      'Coach answers questions about your data. By default it runs entirely '
      'on this phone: set questions, answered from the scores stored here, '
      'with no AI. Nothing is sent anywhere.';
  static const privacyCloud =
      'You can choose Claude (Anthropic) or Gemini (Google) instead, with '
      'your own API key. Only after you agree in ${CoachSettingsCopy.path} '
      'does a question send data off the phone, and then only to the '
      'provider you chose, never to Airlog. Names or identifying details '
      'you type in questions or memories are not redacted. In “With my '
      'data” mode that is:';
  static const privacyGeneral =
      'In “General only” mode, only your current question is sent. Earlier '
      'messages are not sent. If your history includes Google Health API '
      'data, health records and derived scores stay on-device while Claude '
      'or Gemini is on. The on-device coach can still use them. Data '
      'handling:';
  static const privacyMemories =
      'Memories are facts you confirmed (“training for a half marathon”), '
      'never health numbers. They stay on this phone, and are sent as '
      'context only while Claude or Gemini is on.';
  static const privacyDelete =
      'Chats and memories are stored on this phone. Delete any chat or '
      'memory, or all of them, in Coach. ${CoachSettingsCopy.path} → '
      '${CoachSettingsCopy.withdrawTitle} deletes the key and stops all '
      'sending. Deleting on the phone does not reach copies a provider '
      'already holds under the retention above.';

  /// The chat's one quiet line while a cloud (AI) engine answers. The
  /// on-phone engine has no AI model, so it keeps [notMedical].
  static const aiDisclaimer = 'AI can make mistakes. Not medical advice.';

  /// Settings → Coach: the master switch. Off hides every entry point.
  static const showCoach = 'Show Coach';
  static const showCoachBody =
      'Turn this off to hide Coach and its notes everywhere. Your chats and '
      'memories stay on this phone.';

  /// Settings → Coach, under today's usage, once the cloud budget is spent.
  static const usageSpent =
      'You’ve used today’s limit for your AI provider. It resets tomorrow. '
      'The on-phone coach still answers.';

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
