# Google Play release: health-data compliance pack (draft)

Status: **unsubmitted release checklist, updated 2026-09-30**. Implementation notes are not Play approval or live-device evidence. Re-check policy and declaration wording at submission time. The historical policy assumptions below, including provider verification thresholds, fees and timelines, are not verified current requirements.

## 1. App category and declarations
- **Category:** Health & Fitness. **Health apps declaration:** "Fitness, wellness and coaching" (not a medical device).
- **Ads:** none. **Airlog accounts/server:** none. Scores compute locally. Optional cloud Coach sends disclosed health context and conversation to the selected model provider after consent; do not describe every feature as device-only.
- **Health Connect:** request only the data types listed in §2, each tied to one visible feature.
- **Privacy policy:** hosted URL (for example a GitHub Pages copy of the in-app `/privacy` screen). It must also open from Health Connect's permission screen, which the manifest's rationale activity and `ViewPermissionUsageActivity` alias route to `/privacy`.

## 2. Health Connect permission justifications
Every read permission needs a concrete, user-visible feature.

| Permission | Feature that uses it | Justification text (draft) |
|---|---|---|
| READ_HEART_RATE | Strain score; HR timeline by zone | "Heart-rate samples from your band compute your daily Strain score and the time you spend in each heart-rate zone." |
| READ_HEART_RATE_VARIABILITY | Recovery score (40 % weight); HRV trend | "Overnight HRV is the main input to your Recovery score and HRV trend." |
| READ_RESTING_HEART_RATE | Recovery; Health Monitor | "Resting heart rate is compared with your personal baseline for Recovery and the Health Monitor." |
| READ_RESPIRATORY_RATE | Recovery; Health Monitor | "Breathing rate during sleep is compared with your baseline to flag unusual nights." |
| READ_SKIN_TEMPERATURE | Health Monitor | "Nightly skin-temperature change from your baseline is shown in the Health Monitor and can affect the Recovery estimate." This is not an illness detector. |
| READ_SLEEP | Sleep screen; sleep need/debt; Recovery | "Sleep sessions and stages power your sleep performance, sleep debt and bedtime recommendation." |
| READ_EXERCISE | Strain per workout | "Workouts are listed with their individual strain." |
| READ_STEPS | Activity context | "Steps provide activity context; they do not substitute for heart-rate strain." (The exercise-session reader also totals steps inside each session.) |
| READ_WEIGHT (optional, context source off by default) | Context next to trends | "If you log weight in another app, it can be shown next to your trends." |
| READ_VO2_MAX | Cardio fitness trend | "VO₂ max from your band shows your tracker's cardio-fitness estimate." Pulse Age is not a v1 feature. |
| READ_OXYGEN_SATURATION | Health Monitor; Recovery penalty | "Overnight SpO₂ in the Health Monitor, and the Recovery penalty when overnight SpO₂ is below 90%." |
| READ_DISTANCE | Reading exercise sessions (Strain per workout) | "Needed to read your workouts: the exercise-session reader totals the distance recorded during each session, and Health Connect refuses the session read without this permission. Airlog stores it with the workout and uses it for nothing else." |
| READ_TOTAL_CALORIES_BURNED | Reading exercise sessions (Strain per workout) | "Needed to read your workouts: the exercise-session reader totals the calories recorded during each session, and Health Connect refuses the session read without this permission. Airlog stores it with the workout and uses it for nothing else." |
| READ_HEALTH_DATA_HISTORY | Baselines on day 1 | "Reading older data lets personal baselines start immediately instead of after 30 days." |
| READ_HEALTH_DATA_IN_BACKGROUND | Fresh scores on waking; home-screen widget | "Syncs in the background so your morning Recovery and widget are ready when you wake up." |

READ_DISTANCE and READ_TOTAL_CALORIES_BURNED support the workout reader's aggregate fields. Workout details expose recorded distance and calories when present. Verify denial behavior and visible use on the release build rather than treating plugin behavior as permission approval.

This table, the manifest's `health.READ_*` list, the in-app privacy policy and the onboarding/Sources rationale (`lib/app/copy.dart` `hcReadTypes`) must list the same 15 permissions. Remove any permission the shipped build doesn't use. Check this against `android/app/src/main/AndroidManifest.xml` before submission.

## 3. Data safety form (draft answers)

| Question | Answer |
|---|---|
| Does the app collect or share user data? | **Requires release-owner review.** Do not submit a blanket "no": optional cloud Coach transmits selected context/conversation to Claude or Gemini. Classify each provider flow against current Play definitions and the actual shipped consent settings. |
| Health and fitness data | Scores and offline coaching stay local. Enhanced mode reads from Google; cloud Coach can transmit disclosed health context to the selected provider. User-initiated exports also leave the app through the chosen share destination. |
| Is data encrypted in transit? | Network integrations use HTTPS; verify the release configuration and provider disclosures. This is not a claim of encrypted local SQLite storage. |
| Can users request deletion? | Yes: Settings → Delete all data (on device), plus uninstalling. |
| Location, contacts, identifiers, analytics, crash reports | None. |

## 4. Bluetooth
- `BLUETOOTH_SCAN` is declared with `neverForLocation`, because we don't derive location from scans.
- `BLUETOOTH_CONNECT` is used only while the Live screen is open.

## 5. Enhanced mode (Google Health API) constraints
- Restricted scopes. An unverified client is limited to **100 users for the project's lifetime**, shows a warning screen, and needs an in-app disclosure: the Enhanced mode ⓘ sheet in Settings → Data sources and the "Before you sign in" dialog (`kEnhancedDisclosure`). The 100-user cap is a project limit, not user-facing copy. A build without an OAuth client hides Enhanced mode entirely.
- Going public beyond 100 users requires OAuth verification (demo video, domain, privacy policy) **plus an annual CASA assessment** ($500–$4,500, 2–6 weeks). Until that's worth paying for, ship Enhanced mode as an opt-in beta.

## 6. Pre-submission checklist
- [ ] Release signing key (upload key plus Play App Signing). Configure `AIRLOG_KEYSTORE`, `AIRLOG_KEYSTORE_PASSWORD`, `AIRLOG_KEY_ALIAS`, `AIRLOG_KEY_PASSWORD`; release tasks reject missing or partial credentials and never fall back to debug signing silently.
- [ ] **Not a local sideload build.** `AIRLOG_LOCAL_RELEASE=1` with none of the four variables set signs the release with the debug key (Gradle warns "local sideload build, not for the store"). Unset it for the Play build; Play rejects debug-signed uploads.
- [ ] OAuth build inputs match the registered client: `GOOGLE_OAUTH_CLIENT_ID` and optional `GOOGLE_OAUTH_REDIRECT`; the manifest scheme derives from these same Dart defines. Verify on a signed device build.
- [ ] Numeral font licensed for publishing. The build bundles Subway Ticker Grid (K-Type free licence: personal use only). Before publishing, buy K-Type's Enterprise licence, or swap to Doto (OFL, already in `assets/fonts/Doto/`, not bundled; see docs/DESIGN_SYSTEM.md "Fonts").
- [ ] Physical-device ingestion, permission denial/revocation, background sync, BLE and optional OAuth checks completed with recorded evidence.
- [ ] Refresh Data safety/privacy declarations for optional cloud Coach, consent withdrawal and user-initiated exports.
- [ ] `targetSdk` meets Play's current requirement.
- [ ] Manifest permissions match §2 exactly.
- [ ] The privacy policy URL is live, and the in-app `/privacy` screen matches it.
- [ ] Screenshots from demo mode, labelled as sample data.
- [ ] The store listing makes no medical claims. Include "Not affiliated with Google, Fitbit or WHOOP" and the trademark notice from `third_party/pulse/NOTICE`.
- [ ] Encryption at rest for the local database (for example SQLCipher) is considered, or the plain-SQLite trade-off is justified.
