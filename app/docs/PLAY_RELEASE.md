# Google Play release: health-data compliance pack (draft)

Status: **draft for Phase 4**. Nothing here has been submitted. Re-check Play policy text at submission time, because health-app policy changes often.

## 1. App category and declarations
- **Category:** Health & Fitness. **Health apps declaration:** "Fitness, wellness and coaching" (not a medical device).
- **Ads:** none. **Accounts:** none. **Server:** none. All computation happens on the device.
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
| READ_SKIN_TEMPERATURE | Health Monitor (illness/recovery signal) | "Nightly skin-temperature change from your baseline is shown in the Health Monitor and can lower Recovery when it is unusually high." (Heightened scrutiny: keep this feature visible and explained.) |
| READ_SLEEP | Sleep screen; sleep need/debt; Recovery | "Sleep sessions and stages power your sleep performance, sleep debt and bedtime recommendation." |
| READ_EXERCISE | Strain per workout | "Workouts are listed with their individual strain." |
| READ_STEPS | Strain fallback; activity context | "Steps estimate strain when heart-rate data is sparse, for example while the band charges." (The exercise-session reader also totals steps inside each session.) |
| READ_WEIGHT (optional, context source off by default) | Context next to trends | "If you log weight in another app, it can be shown next to your trends." |
| READ_VO2_MAX | Cardio fitness trend; Pulse Age | "VO₂ max from your band shows your cardio-fitness trend." |
| READ_OXYGEN_SATURATION | Health Monitor; Recovery penalty | "Overnight SpO₂ in the Health Monitor, and the Recovery penalty when overnight SpO₂ is below 90%." |
| READ_DISTANCE | Reading exercise sessions (Strain per workout) | "Needed to read your workouts: the exercise-session reader totals the distance recorded during each session, and Health Connect refuses the session read without this permission. Airlog stores it with the workout and uses it for nothing else." |
| READ_TOTAL_CALORIES_BURNED | Reading exercise sessions (Strain per workout) | "Needed to read your workouts: the exercise-session reader totals the calories recorded during each session, and Health Connect refuses the session read without this permission. Airlog stores it with the workout and uses it for nothing else." |
| READ_HEALTH_DATA_HISTORY | Baselines on day 1 | "Reading older data lets personal baselines start immediately instead of after 30 days." |
| READ_HEALTH_DATA_IN_BACKGROUND | Fresh scores on waking; home-screen widget | "Syncs in the background so your morning Recovery and widget are ready when you wake up." |

Why READ_DISTANCE and READ_TOTAL_CALORIES_BURNED: the `health` plugin (13.3.2, `HealthDataReader.handleWorkoutData`) reads `DistanceRecord`, `TotalCaloriesBurnedRecord` and `StepsRecord` inside every `ExerciseSessionRecord`'s time range. Without either permission the whole workout read throws. Neither value is shown in the UI today, so a reviewer may ask for a user-visible use. Showing distance and calories on the workout row would give them one.

This table, the manifest's `health.READ_*` list, the in-app privacy policy and the onboarding/Sources rationale (`lib/app/copy.dart` `hcReadTypes`) must list the same 15 permissions. Remove any permission the shipped build doesn't use. Check this against `android/app/src/main/AndroidManifest.xml` before submission.

## 3. Data safety form (draft answers)

| Question | Answer |
|---|---|
| Does the app collect or share user data? | **Collect: no.** In Play's definition, "collected" means sent off the device; the only exception is Enhanced mode below. **Share: no.** |
| Health and fitness data | Processed on device only (ephemeral processing is not declared as collection). With **Enhanced mode**, the app requests the user's own data *from* Google's Health API using their OAuth token; nothing is sent to us. |
| Is data encrypted in transit? | Yes (HTTPS to Google APIs in Enhanced mode). |
| Can users request deletion? | Yes: Settings → Delete all data (on device), plus uninstalling. |
| Location, contacts, identifiers, analytics, crash reports | None. |

## 4. Bluetooth
- `BLUETOOTH_SCAN` is declared with `neverForLocation`, because we don't derive location from scans.
- `BLUETOOTH_CONNECT` is used only while the Live screen is open.

## 5. Enhanced mode (Google Health API) constraints
- Restricted scopes. An unverified client is limited to **100 users for the project's lifetime**, shows a warning screen, and needs an in-app disclosure (the Settings → Sources copy).
- Going public beyond 100 users requires OAuth verification (demo video, domain, privacy policy) **plus an annual CASA assessment** ($500–$4,500, 2–6 weeks). Until that's worth paying for, ship Enhanced mode as an opt-in beta.

## 6. Pre-submission checklist
- [ ] Release signing key (upload key plus Play App Signing).
- [ ] `targetSdk` meets Play's current requirement.
- [ ] Manifest permissions match §2 exactly.
- [ ] The privacy policy URL is live, and the in-app `/privacy` screen matches it.
- [ ] Screenshots from demo mode, labelled as sample data.
- [ ] The store listing makes no medical claims. Include "Not affiliated with Google, Fitbit or WHOOP" and the trademark notice from `third_party/pulse/NOTICE`.
- [ ] Encryption at rest for the local database (for example SQLCipher) is considered, or the plain-SQLite trade-off is justified.
