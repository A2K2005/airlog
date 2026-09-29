# 09: HRV when the source doesn't share it

**Date:** 2026-09-29 · **Status:** research only; no app code written · **Decides:** `PRODUCT_PLAN.md` §7 row "HRV when the source doesn't share it" · **Inputs:** [`03-data-access.md`](03-data-access.md), [`07-google-health-apk.md`](07-google-health-apk.md), [`08-whoop-apk.md`](08-whoop-apk.md), [`../app/ARCHITECTURE.md`](../app/ARCHITECTURE.md), `app/lib/data/services/ble/`

**Labels:**
- **V-official**: I read the vendor's or standard body's own page or file, or the paper itself.
- **V-code**: read in source code (ours, a plugin's, or an open-source project's).
- **Community**: a forum post, GitHub issue or blog by someone other than the vendor.
- **Press**: tech press.
- **Unverified**: not confirmed. Nothing unverified is presented as fact.

Pages were fetched on 2026-09-29 unless a date is given. Quotes are verbatim and short.

**Principles this must satisfy** (`PRODUCT_PLAN.md` §3):
- **4, Private:** no server, no account.
- **6, Derived, never invented:** no "HRV" estimated from heart rate.
- **Spot vs nightly:** a morning spot reading is a different measurement from nightly RMSSD. It gets its own baseline and is never merged with the nightly one.

---

## 0. Answers first

1. **Samsung Health does not write HRV to Health Connect.** What the orchestrator told the user earlier is wrong.
   - Samsung's own developer table of "health data that can be synchronized between Samsung Health and Health Connect" (blog, 2025-02-18) has **no `HeartRateVariabilityRmssdRecord`**. It also has no `RestingHeartRateRecord`, no `RespiratoryRateRecord` and no skin temperature. [V-official] https://developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect
   - Samsung's Health Connect FAQ says only: "Activity data, such as steps and exercise, heart rate, and sleep, are synchronized". [V-official] https://developer.samsung.com/health/health-connect-faq.html
   - Samsung's phone-side **Health Data SDK** also has no HRV type in its type list (details in §1.1). [V-official]
   - Users confirm it:
     - a thread titled "HRV, breathing rate, and resting HR won't write to the health connect app from Samsung Health" (2025-09-06); Samsung's moderator didn't dispute it. [Community] https://us.community.samsung.com/t5/Galaxy-Watch/HRV-breathing-rate-and-resting-HR-won-t-write-to-the-health/td-p/3351258
     - an open-wearables issue (2026-09-25) found no HRV or RHR after a full Samsung sync. [Community] https://github.com/the-momentum/open-wearables/issues/1723
   - Samsung adds: "A synchronized data scope can be changed depending on the Samsung Health version", so check again after Samsung Health updates.
   - **Consequence: Samsung is worse than "no HRV".** With no HRV *and* no RHR, `RecoveryEngine.compute` returns null (`recovery.dart:102`), so the "Recovery without HRV" fallback gives Samsung users **no score at all**. See §3, rung 3.
2. **WHOOP: the documented flow needs a client secret held on a server. A public PKCE client is not documented and unverified.**
   - The docs say the secret "should only be used server side and should never be exposed in a client, web, or mobile application". [V-official] https://developer.whoop.com/docs/developing/getting-started/
   - Both the token exchange and the refresh send `client_secret`. [V-official] https://developer.whoop.com/docs/developing/oauth/
   - PKCE isn't mentioned anywhere in the docs.
   - The OAuth server's own discovery document is ambiguous:
     - it lists `"none"` among `token_endpoint_auth_methods_supported`
     - it lists `implicit` among grant types
     - it has **no `code_challenge_methods_supported`** field
     
     That is a server-wide capability list, not proof that a client created on the dashboard can be public. [V-official, server metadata] https://api.prod.whoop.com/oauth/.well-known/openid-configuration
   - Without a WHOOP account it can't be tested here.
   - **A phone-only WHOOP integration is therefore only possible as bring-your-own-credentials in a personal build** (§2, option C). Embedding a shared secret is ruled out by WHOOP's terms: "Developer credentials may not be embedded in open-source projects". [V-official] https://developer.whoop.com/api-terms-of-use/
3. **Oura does support PKCE, but still requires the secret for the code exchange.**
   - The authorization step documents `code_challenge` as "Recommended". The token step lists `client_secret` "Required if not using Basic Authorization". [V-official] https://cloud.ouraring.com/docs/authentication
   - A no-secret "Client-Side Only Flow" (implicit grant) exists, but it has no refresh token and needs re-login every 30 days.
   - RFC 9700 says clients "SHOULD NOT use the implicit grant". [V-official] https://www.rfc-editor.org/rfc/rfc9700
   - Nightly HRV is `sleep.average_hrv` (plus an `hrv` sample series).
   - **Oura already writes HRV to Health Connect** (Oura's page, updated 2026-08-19, lists "Heart rate variability" under data exported to Health Connect) [V-official] https://support.ouraring.com/hc/en-us/articles/10786105824531. So **the Oura API rung is dropped**. The API facts stay in §2.C for reference.
4. **Both vendor APIs have terms that conflict with what Airlog does.** This limits any vendor-API rung to an opt-in, personal-build flag (§2, option C):
   - **WHOOP** (terms effective 2026-10-06; read 2026-09-29) forbids using API materials "to compete, directly or indirectly, with WHOOP", and forbids "permanent copies of WHOOP Data". [V-official] https://developer.whoop.com/api-terms-of-use/
   - **Oura** (effective 2026-06-08) forbids anything that "competes with or merely replicates those of Oura", and says data "may not be stored or retained beyond the duration strictly necessary". [V-official] https://cloud.ouraring.com/legal/api-agreement
   - Airlog computes its own Recovery and keeps 30-day baselines in SQLite.
5. **The recommended ladder** is in §3.
   - Health Connect HRV writers (§1): Google Health (Fitbit) and Oura are confirmed by vendor pages. Withings, COROS, Zepp/Amazfit and Ultrahuman declare the write. Samsung, WHOOP, Garmin, Polar, Google Fit and Mi Fitness don't write it.
   - The camera check (§5) is feasible only with a native timestamped analyzer, and stays flagged until validated on the phone.
   - The Bluetooth RR device list and protocol literature (§4) are still marked **NOT VERIFIED IN THIS PASS**.

---

## 1. Which apps write HRV (RMSSD) to Health Connect

Evidence method, per the research agent:
- **Vendor pages** where they exist (V-official).
- **Each app's declared Health Connect permissions**, from Exodus Privacy's static APK reports (`https://reports.exodus-privacy.eu.org/en/reports/<package>/latest/`) (V-code).
- A missing `WRITE_HEART_RATE_VARIABILITY` is a hard "no" for that build, because Android enforces permissions.
- A declared write only shows the app *can* write HRV. Those rows say "yes (declared)".
- I re-read Oura's page myself.

| App | HC origin package | Writes HRV RMSSD to HC? | Nightly or spot | Other Recovery inputs it writes | Evidence | Label |
|---|---|---|---|---|---|---|
| **Google Health (Fitbit; Pixel Watch data comes in under it too)** | `com.fitbit.FitbitMobile` | **Yes** | Nightly: the longest sleep over 3 h. Community: samples about every 5 min, 60–100 a day | RHR, respiratory rate, skin temp, sleep. SpO₂: the table says read-only, the manifest declares a write | https://support.google.com/googlehealth/answer/14506680 ; research/07 §1 ; https://github.com/FloorLamp/allos/issues/4956 | V-official + V-code + Community |
| **Oura** | `com.ouraring.oura` | **Yes** | Measured in sleep. Record shape in HC **unverified** | HR, sleep. **No RHR, respiratory rate, SpO₂ or skin temp** | "Data Exported from Oura to Health Connect" lists, under Vitals, "Heart rate, Heart rate variability" (page updated 2026-08-19; I read it) | V-official + V-code |
| Withings (Health Mate) | `com.withings.wiscale2` | Yes (declared) | Sleep-measured on ScanWatch models. Shape unverified | RHR, respiratory rate, SpO₂, body temp, sleep (declared) | Build v26.36.0 declares the write. Withings' HC help page lists no types | V-code |
| COROS | `com.yf.smart.coros.dist` | Yes (declared) | **Either**: automatic Overnight HRV *or* a manual daytime check. Which one it writes is unverified. Use the `recordingMethod` split (§1.2) | RHR, respiratory rate, SpO₂, sleep (declared) | Build v4.6.8 declares the write | V-code |
| Zepp / Amazfit | `com.huami.watch.hmwatchmanager` | Yes (declared) | Nightly-sleep baseline on "select Amazfit devices". Shape unverified | RHR, respiratory rate, SpO₂, sleep, VO₂max (declared) | Build v10.8.1 declares it. A Jan 2025 press list had no HRV | V-code + Press |
| Ultrahuman | `com.ultrahuman.android` | Yes (declared) | Measured overnight. Shape unverified | Body temp (not skin temp), sleep. **No RHR, respiratory rate or SpO₂** | Build v2.74.4.0 (Dec 2025 report) declares it | V-code |
| Garmin Connect | `com.garmin.android.apps.connectmobile` | **No** | — | HR, sleep stages. The build also declares an RHR write | Official FAQ lists activity, body fat, floors, HR, sleep stages, steps, weight. Build v5.29 has no HRV permission | V-official + V-code |
| Polar Flow | `fi.polar.polarflow` | **No** | — | SpO₂, sleep. Its "resting HR" is a **profile setting**, not a nightly value | https://support.polar.com/us-en/flow-app-health-connect | V-official + V-code |
| Google Fit | `com.google.android.apps.fitness` | **No** | — | RHR, respiratory rate, SpO₂, sleep (declared) | Fit's data model has no HRV type: https://developers.google.com/fit/datatypes/health | V-official + V-code |
| Mi Fitness | `com.xiaomi.wearable` | **No** | — | HR, SpO₂, sleep. No RHR or respiratory rate | Build v3.59.1i has no HRV permission | V-code |
| Zepp Life | `com.xiaomi.hm.health` | **No** | — | No HC writes at all | Build v6.15.0 (Oct 2025 report) | V-code |
| **Samsung Health** | `com.sec.android.app.shealth` | **No** | — | **RHR, respiratory rate and skin temp also absent** | Samsung's table: steps, glucose, SpO₂, BP, exercise (session, calories, distance, HR, power, speed, VO2max), HR, nutrition, sleep session/stage, weight, body fat, BMR, height | V-official + Community |
| **WHOOP** | `com.whoop.android` | **No** | — | Writes HR, RHR, respiratory rate, SpO₂, sleep | research/08 §1; build v5.465.0 | V-code |
| Health Sync (relay app) | `nl.appyhapps.healthsync` | Yes (declared) | Whatever the relayed source provides | Everything | Build v7.9.1.6. It can relay **Garmin** HRV (from Garmin's cloud) into HC under its own origin | V-code |
| NOOP (open-source WHOOP client) | `com.noop.whoop` | Yes | **One record per night, stamped at local noon** (`HealthConnectWriter.kt:143-155`) | RHR, SpO₂, respiratory rate, sleep | https://github.com/ryanbr/noop | V-code |
| Sleep as Android, Welltory, Elite HRV | `com.urbandroid.sleep`, `com.welltory.client.android`, `com.elitehrv.app` | No | — | — | Builds have no HRV write permission | V-code |
| HRV4Training, Kubios, Huawei Health | — | Unknown | — | — | No evidence found | Unverified |

**What this means for the ladder:**
- **Oura writes HRV to Health Connect, so the Oura API rung (0f) is dropped** (R15).
- **Garmin, Polar, Google Fit, Mi Fitness, Samsung and WHOOP users** are the ones who need rung 1 or 2.
- **Garmin HRV can arrive via Health Sync**, under `nl.appyhapps.healthsync`. It's a real measurement, but the origin is the relay. The baseline key is then `…@nl.appyhapps.healthsync`, and the source line should name the device from the record metadata ("Garmin via Health Sync").
- **Record shapes differ:** many 5-minute samples (Google Health), one nightly record at noon (NOOP), or unknown (Oura and the rest). Rung 0d must therefore group HRV **by the sleep session or wake day, not by the sleep window only**. A noon-stamped record falls far outside `main.start..main.end`.
- **Oura and Ultrahuman write no RHR,** so their users also need the sleeping-HR RHR slot (rung 2 note).

### 1.1 Samsung, in more detail

- **Health Connect path:** covered above. The table is "Samsung Health data → Corresponding Health Connect data type". It has 19 rows, and none is HRV, resting HR, respiratory rate or skin temperature. [V-official] https://developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect
- **Samsung Health Data SDK** (the phone-side SDK that reads Samsung Health directly):
  - Its data-type list (API reference navigation) is: ActiveCaloriesBurnedGoal, ActiveTimeGoal, ActivitySummary, BloodGlucose, BloodOxygen, BloodPressure, BodyComposition, BodyTemperature, **EnergyScore**, ExerciseLocation, Exercise, FloorsClimbed, **HeartRate**, IrregularHeartRhythmNotification, Nutrition, NutritionGoal, **SkinTemperature**, SleepApnea, Sleep, SleepGoal, Steps, StepsGoal, UserProfile, WaterIntake, WaterIntakeGoal.
  - There is **no HRV type**. `HeartRate` carries only `startTime`, `endTime`, `heartRate`, `min` and `max`, with no beat intervals. [V-official] https://developer.samsung.com/health/data/api-reference/-shd/com.samsung.android.sdk.health.data.data.entries/-heart-rate/index.html
  - So it can't supply HRV either. It does have SkinTemperature and an EnergyScore, but EnergyScore is Samsung's score, which Airlog doesn't show (§7 "Whose scores").
- **Samsung Health Sensor SDK** (runs *on the Galaxy Watch*):
  - It streams "Heart rate including inter-beat interval (IBI)". [V-official] https://developer.samsung.com/health/sensor/overview.html
  - Using it means building a separate Wear OS app. Distribution needs Samsung partner approval, and developer mode needs an access key "shared by Samsung Health team after a partnership approval". [V-official] https://developer.samsung.com/health/sensor/guide/developer-mode.html
  - Rejected (§6).

### 1.2 A Health Connect subtlety: spot readings can arrive as HRV too

Spot-check apps can write `HeartRateVariabilityRmssdRecord` as well. The record has only a time and a value, but every record carries `metadata.recordingMethod`:

| `recordingMethod` value | Meaning |
|---|---|
| `RECORDING_METHOD_AUTOMATICALLY_RECORDED` | "A device or sensor recorded the data" |
| `RECORDING_METHOD_ACTIVELY_RECORDED` | "The user initiated the start or end of the recording session" |
| `MANUAL_ENTRY` | the user entered the value |
| `UNKNOWN` | the method can't be verified |

[V-official] https://developer.android.com/health-and-fitness/health-connect/metadata

- The `health` 13.3.2 plugin exposes this as `HealthDataPoint.recordingMethod` (`lib/src/health_data_point.dart:50`, `HealthDataConverter.kt:190`). [V-code]
- **Rule:** only automatically recorded HRV inside (or at the end of) the main sleep may feed the nightly definitions. Actively recorded and manual HRV records are spot readings. They're stored under a spot definition and never enter the nightly baseline.

---

## 2. The options

### 2.A Nightly HRV in Health Connect, from any origin (existing plan, not yet implemented)

- **What exists:**
  - The resolver averages at least 3 RMSSD samples inside the main sleep (`hc_sleep_mean_rmssd`, `resolver.dart:303-313`).
  - `_hrvNotSharedBy` + `Notes.hrvNotShared` already produce the "Recovery without HRV" note (`day_engine.dart:273-279, 385-430`; `notes.dart:36`). [V-code]
- **What's missing** (a prerequisite for every rung below):
  1. **Origins are never set.** No resolver or sync code passes `origin:` to `Provenance` (grep of `data/resolver/` and `data/sync/`). So:
     - `baselineKey` is always the bare definition, and a change of app does **not** start a new segment today;
     - `_hrvNotSharedBy` returns null in live mode, so the "doesn't share HRV" note never fires.
     
     [V-code]
  2. **`Provenance.toJson`/`fromJson` drop `origin`, and `==` ignores it** (`models.dart:94-113`). `ScorePipeline.recompute` loads "clean earlier days … from the store" (`score_pipeline.dart:106-109`). So once origins are set, stored history would lose them, and incremental recomputes would find no matching baseline days. [V-code]
  3. **Per-metric origin choice is stubbed:** `sourceChoices()` returns `{}` and `setSourceChoice` is a no-op (`health_repository_impl.dart:947-950`). [V-code]
  4. **Single-record nightly writers are dropped.** `minHrvSamples = 3` (`resolver.dart:38`) rejects an origin that writes one nightly summary record. NOOP writes one record per night **stamped at local noon** [V-code]. Oura's and the others' record shapes are unverified. So group by sleep session / wake day, not the sleep window only.
- Honesty: best, since it is the source's own measurement. Coverage: depends on §1. Effort: medium (the 4 fixes). Privacy: on device. Testability here: high. The Health Connect Toolbox "supports reading and writing all Health Connect data types", so single-record and spot-record origins can be simulated. [V-official] https://developer.android.com/health-and-fitness/health-connect/test/health-connect-toolbox

### 2.B Google Health API deep-sleep RMSSD (Fitbit users)

This is already in the plan as **Enhanced mode**:
- `daily-heart-rate-variability.deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds`, definition `ghapi_deep_sleep_rmssd`
- else `averageHeartRateVariabilityMilliseconds`, definition `ghapi_daily_rmssd`

[V-official, research/03 §3.2]

Constraints: OAuth PKCE with no secret (Google's native-app flow), a 100-user cap until verification, and CASA. Nothing new here. It helps only Fitbit and Pixel Watch users, who usually get HRV through Health Connect anyway, so its role is the cleaner definition and the Phase 0 fallback.

### 2.C Vendor cloud APIs (WHOOP, Oura): the source's own measurement, fetched from its cloud

| | WHOOP API v2 | Oura API v2 |
|---|---|---|
| HRV field | `recovery.score.hrv_rmssd_milli`, "Heart Rate Variability measured using Root Mean Square of Successive Differences (RMSSD), in milliseconds". **One value per recovery (per sleep/cycle)**, present only when `score_state == "SCORED"` [V-official, OpenAPI `https://api.prod.whoop.com/developer/doc/openapi.json`] | `sleep.average_hrv` (integer, "Average heart rate variability during sleep") per sleep period, plus `sleep.hrv`, a `PublicSample` series with `interval` in seconds. Use the `long_sleep` period for the day [V-official, OpenAPI `https://cloud.ouraring.com/v2/static/json/openapi-1.41.json`] |
| How the source measures it | "WHOOP calculates it during your deepest sleep each night" [V-official] https://www.whoop.com/us/en/thelocker/heart-rate-variability-hrv/ | Unverified beyond the field description |
| Scope | `read:recovery` ("Read Recovery data, including score, heart rate variability, and resting heart rate"), plus `offline` for a refresh token | `daily` ("Daily summaries of sleep, activity and readiness"). Which scope `/v2/usercollection/sleep` needs isn't stated per endpoint in the spec (**unverified**; `daily` is the likely one) |
| Endpoint | `GET /developer/v2/recovery` (limit ≤ 25, paginated) | `GET /v2/usercollection/sleep?start_date&end_date` |
| OAuth for a phone-only app | Secret required; "never … in a mobile application". PKCE undocumented. The server lists `none` and `implicit`, but dashboard clients are unverified (§0.2) | PKCE supported, but the secret is still required for the code and refresh exchange. The no-secret implicit flow has 30-day tokens and no refresh. `flutter_appauth` hard-codes `ResponseTypeValues.CODE` (`FlutterAppauthPlugin.java:421`) [V-code], so implicit needs a different plugin |
| Member limit before review | Sandbox tier: "up to 10 WHOOP members" [V-official] https://developer.whoop.com/docs/developing/app-approval/ | "limited to **10** users before requiring approval" [V-official, OpenAPI info] |
| Rate limits | 100 requests/min and 10,000/day by default [V-official] https://developer.whoop.com/docs/developing/rate-limiting/ | Per-token and per-application limits, not published, 429 with `Retry-After` [V-official, OpenAPI info] |
| Developer prerequisite | "You must have a WHOOP membership to develop an app" [V-official] https://developer.whoop.com/docs/developing/overview/ | An Oura account to register an API application [V-official, OpenAPI info] |
| Terms that bite | "Use any API Materials to compete, directly or indirectly, with WHOOP"; no "permanent copies of WHOOP Data, or keep cached copies longer than permitted by the cache header"; no medical device use; "Developer credentials may not be embedded in open-source projects" [V-official] https://developer.whoop.com/api-terms-of-use/ (effective 2026-10-06) | Nothing that "competes with or merely replicates those of Oura"; data "may not be stored or retained beyond the duration strictly necessary"; no AI training; third-party AI processing must be bound by equally protective terms [V-official] https://cloud.ouraring.com/legal/api-agreement (effective 2026-06-08) |

**How a phone-only app could sign in:**

| Route | Verdict |
|---|---|
| Embed our client secret in the APK | **Rejected.** RFC 8252 §8.5: secrets "statically included as part of an app distributed to multiple users should not be treated as confidential secrets" [V-official] https://www.rfc-editor.org/rfc/rfc8252. WHOOP's docs and terms forbid it outright |
| A tiny token-exchange server (for example a Cloudflare Worker holding the secret) | It works, and it's the only route that scales past one user. But it breaks principle 4: a server Airlog runs sees every user's tokens. **Rejected for v1.** Revisit only with an explicit user decision to relax principle 4 |
| **Bring your own credentials (BYO)** | The user registers their *own* WHOOP or Oura developer app (Sandbox tier, 10 members, so personal use fits), then pastes the client ID and secret into Airlog. Airlog stores them in `flutter_secure_storage` (already used for Google tokens). The secret is used by one person on their own device, so RFC 8252's shared-secret concern doesn't apply. It still runs against WHOOP's "never in a mobile application" guidance. **Allowed only in personal builds, behind a flag, with the user told this in-app** |
| WHOOP public client (PKCE, `token_endpoint_auth_method: none`) | **Unverified.** Test with an account: create an app, attempt a code exchange with `code_verifier` and without `client_secret` |
| Oura implicit flow (no secret) | Works without a secret, but RFC 9700 says SHOULD NOT, there's no refresh, and it needs re-login every 30 days. Weaker than BYO + PKCE |

**Storage conflict.** Airlog needs 30 nights of HRV to build a baseline, but WHOOP forbids "permanent copies" beyond the cache header and Oura forbids retention "beyond the duration strictly necessary".
- One reading: storing a baseline window on the user's own device, at the user's request, is "strictly necessary" for the feature the user asked for.
- The WHOOP prohibitions apply "unless expressly authorized by the WHOOP Data owner", and WHOOP says data "is the sole responsibility of the person that makes it available".
- **Neither reading is verified.** Treat it as a legal open question (§8).

**Verdict:**
- Honesty: high (the source's measurement).
- Coverage: WHOOP and Oura members only.
- Effort: medium (client, mapping, fixtures, BYO settings UI).
- Privacy: the phone talks to the vendor's cloud with the user's own credentials, and no Airlog server exists.
- Testability here: **fixtures only** (no accounts). The OpenAPI specs include example payloads.
- Terms risk: **high for any public build.** Ship as `--dart-define=VENDOR_HRV_API=true` in personal builds only.

### 2.D Bluetooth RR morning check (chest strap or HR broadcast with RR)

- **Already half-built** [V-code]:
  - `LiveController.startHrvCheck` runs 120 s (`kHrvCheckSeconds`, `live_view_model.dart:55`) and is gated on `rrAvailable`.
  - `HrvTools` applies a 300–2000 ms range plus a 20% successive-difference filter, and computes RMSSD only between originally adjacent clean beats, with at least 30 clean beats (`hrv_tools.dart`).
  - `saveSession(kind: 'hrv_check')` writes a `ScalarKind.hrvCheck` raw row (`health_repository_impl.dart:892-912`).
- **What isn't done:**
  - Nothing resolves `hrvCheck` rows into a `DayRecord`. The resolver never reads them.
  - There's no maximum artifact fraction that rejects a whole session; beats are dropped, but a session with 40% corrected beats still produces a value.
  - No posture or time window is captured.
  - The result-screen copy says "compare checks with each other, not with Recovery" (`live_widgets.dart:806-809`). That is correct today and must change if checks feed Recovery.
- Which devices send RR, and the minimum protocol: §4 (not verified in this pass).

### 2.E Overnight Bluetooth RR capture (Airlog measures nightly RMSSD itself)

- If the source's broadcast carries RR, Airlog could record RR all night and compute RMSSD in 5-minute windows inside the source's main sleep. That would be a *measured* nightly HRV under its own definition (`ble_sleep_rmssd`), for exactly the people who have none. Whether WHOOP's broadcast carries RR is **unverified**.
- Costs:
  - the band's broadcast mode costs battery (Google says so for the Air, research/03 §6.1);
  - it needs an all-night Android foreground service with a BLE connection;
  - the phone must stay within range;
  - reconnect gaps must be handled;
  - optical RR quality at night is unknown.
- **Verdict: later / experimental**, not in the v1 ladder. It's honest, but the reliability cost is high, and none of it can be tested until a device with RR is in hand.

### 2.F Phone camera PPG morning check

See §5.
- It's a real measurement of pulse intervals, so it's honest if labelled "experimental".
- One-minute error is wide: limits of agreement −30 to +24 ms (Johansson 2026).
- It needs a native Kotlin analyzer, because the stock plugin's frames have no timestamps.
- It stays behind a flag and out of Recovery until it agrees with an RR reference on this phone.

### 2.G Recovery "without HRV"

- This already exists: `RecoveryEngine` re-weights the inputs that are present (`recovery.dart:188-208`), and `Notes.hrvNotShared` explains it.
- It's honest, covers everyone, and costs nothing.
- **Gap:** when a source writes neither HRV nor RHR (Samsung), `compute` returns null. §3 rung 3 and §7 cover this.

### 2.H HR-only proxies (overnight minimum HR, sleeping-HR dip)

See §7. Verdict: use the 4-h sleeping-HR mean only in the **RHR** slot, and only for sources that write no RHR. Never use it in the HRV slot. Reject the lowest overnight HR and the HR dip.

### 2.1 Ranking

Scores run 1–5, higher is better. Coverage for A depends on §1, which is unverified.

| Option | Honesty | Coverage | Effort (5 = least) | Privacy | Testable here | Place |
|---|---|---|---|---|---|---|
| A. HC nightly HRV, any origin | 5 | 3 (Fitbit, Oura; declared by Withings, COROS, Zepp, Ultrahuman; not Samsung, WHOOP, Garmin, Polar, Fit, Mi Fitness) | 3 (P1–P4) | 5 | 5 (Toolbox) | **Rung 0** |
| B. Google Health API deep-sleep RMSSD | 5 | 2 (Fitbit / Pixel only) | 4 (built) | 4 (Google cloud, no Airlog server) | 4 | **Rung 0** (Enhanced mode) |
| D. BLE RR morning check | 4 (a real measurement, different construct, labelled) | 3 (needs an RR sensor) | 4 (half-built) | 5 | 3 (needs a strap) | **Rung 1** |
| G + sleeping HR. Recovery without HRV (RHR slot from the 4-h sleeping HR when no RHR) | 5 | 5 | 4 | 5 | 5 | **Rung 2 (the floor)** |
| F. Camera PPG morning check | 2 until validated | 5 | 1 | 5 | 3 (no reference) | Flag only |
| C. Vendor APIs (WHOOP, Oura) | 5 as a measurement, but terms conflict | 2 | 3 | 3 | 1 (fixtures only) | Personal flag only |
| E. Overnight BLE RR capture | 5 | ? | 1 | 5 | 1 | Later |
| H. HR-only "HRV" | 0 | — | — | — | — | **Rejected** |

---

## 3. Recommended ladder

Nightly definitions always win over morning ones, through the persisted HRV mode (§3.2). A morning value never enters `Metric.hrv`.

| Rung | Metric slot | Definition string (exact) | Source kind | Baseline key | When used |
|---|---|---|---|---|---|
| 0a | `Metric.hrv` (nightly) | `ghapi_deep_sleep_rmssd` | googleHealthApi | definition | Enhanced mode on, value present |
| 0b | `Metric.hrv` | `ghapi_daily_rmssd` | googleHealthApi | definition | as 0a, no deep-sleep value |
| 0c | `Metric.hrv` | `hc_sleep_mean_rmssd` | healthConnect | `definition@origin` | ≥ 3 automatically recorded samples inside the main sleep, from the chosen origin |
| 0d | `Metric.hrv` | `hc_nightly_rmssd` (**new**) | healthConnect | `definition@origin` | 1–2 automatically recorded records from the chosen origin, stamped in the main sleep or up to N h after it ends (N **unverified**; set it from probe data) |
| 0e | `Metric.hrv` | `whoop_api_recovery_rmssd` (**new**, flagged) | `whoopApi` (**new**) | definition | personal build, BYO credentials, `score_state == SCORED` |
| ~~0f~~ | — | ~~`oura_api_sleep_average_hrv`~~ | — | — | **Dropped**: Oura writes HRV to Health Connect (§1), so rung 0c/0d covers it |
| 1a | **`Metric.hrvMorning` (new, separate)** | `ble_morning_rmssd_<posture>_v1` | ble | `definition@ble:<sensor model>` | the check passed protocol v1 inside the morning window |
| 1b | `Metric.hrvMorning` | `cam_morning_rmssd_<posture>_v1` | `camera` (**new**) | `definition@cam:<phone model>` | flagged until validated on device (§5) |
| 2 | — | — | — | — | Recovery "without HRV" |

**RHR slot, for sources that write no resting HR (Samsung, Oura, Ultrahuman, Mi Fitness):** `hc_sleep_hr_4h_mean@<origin>`, labelled "Sleeping HR (4 h mean)" (§7). It never fills the HRV slot.

---

### 3.2 UX: when the app asks, and how Recovery labels its HRV source

**Detect first, then offer once:**
- The trigger already exists: `_hrvNotSharedBy`. The chosen origin must have written RHR, sleep or respiratory rate on ≥ 3 nights, never HRV, and no HRV must have arrived from any app in 14 days. It only works once origins are set (§2.A fix 1).
- When it fires, the existing "Recovery without HRV" note gets a second fix line, **"Add a 2-minute morning HRV check"**, which opens setup.
- The same offer appears once in Settings → Sources on the HRV row, e.g. "Samsung Health doesn't share HRV", with three choices: morning check with a Bluetooth sensor, morning check with the phone camera (only when the flag is on), or "Keep Recovery without HRV".
- Nothing else nags. Declining is remembered.

**Setup (one time):**
1. **Sensor.** Scan for `0x180D`. A sensor qualifies only after it has sent RR in its first 15 frames (the existing `kRrGraceSamples`). Show the model name; it becomes part of the baseline key.
2. **Posture.** "Lying down" (default) or "Sitting". The choice is fixed in the definition string; changing it later says "starts a new morning baseline".
3. **Reminder.** Off by default (calm). If turned on, one local notification at a time the user picks. No streaks and no "you missed it" copy.

**Each morning:**
- **TodayPlan action.** A new `PlanActionKind.measure`, "Take your 2-minute HRV check". Its why line: "<App> doesn't share HRV; this completes today's Recovery."
  - Shown only when morning-check mode is on, today has no valid check yet, and it's inside the **morning window**. It ranks first; the 3-action cap still holds.
- **The check screen** (reuses Live):
  - instruction: lie still, breathe normally, don't talk;
  - a settle period that isn't analysed, then the analysed recording (durations in §4);
  - a live beat-quality line;
  - the session is abandoned if the artifact share exceeds the §4 limit, with the copy "Too many irregular beats; try again, keep still".
- **The result screen:**
  - RMSSD in ms, placed on the **morning** baseline band once there are ≥ 5 checks (`Baseline.isReliable`, `results.dart:29`). Before that: "Morning baseline: 3 of 5 checks".
  - The copy replaces today's "compare checks with each other, not with Recovery" with: "Morning checks are compared only with your other morning checks. They never mix with overnight HRV."
- **Outside the window:** the check is still saved, as a spot check (`ble_spot_rmssd`). It shows in check history and is excluded from Recovery: "Saved as a spot check. Only checks within the morning window count toward Recovery."
- **Skipped:** Recovery stays "without HRV", exactly as today.

**How Recovery labels the HRV input.** The HRV row's source line comes from the definition, never a generic "HRV":

| Definition | Source line on the Recovery HRV row |
|---|---|
| `ghapi_deep_sleep_rmssd` | "HRV · deep sleep · Google Health API" |
| `hc_sleep_mean_rmssd@<origin>` / `hc_nightly_rmssd@<origin>` | "HRV · overnight · <App> via Health Connect" |
| `whoop_api_recovery_rmssd` | "HRV · overnight · WHOOP account (personal build)" |
| `ble_morning_rmssd_supine_v1@ble:<model>` | "HRV · morning check · <model> · lying · 07:12" |
| `cam_morning_rmssd_supine_v1@cam:<phone>` | "HRV · morning check · phone camera · lying · 07:12 · experimental" |
| (none) | Ring subtitle "without HRV", plus the `hrvNotShared` note |

**Which HRV wins on a day that has both:**
- One persisted **HRV mode**, like `SourceChoice`: *nightly* while the chosen nightly definition keeps arriving, else *morning check*.
- The mode switches only after a sustained absence (the same rule as the "Any app" decision) or on user override. So Recovery doesn't flip between two differently calibrated inputs day to day.
- Both series keep being stored, and Trends shows them as **two separate lines**, never one.

### 3.3 What each rung needs in our codebase

Ownership follows `ARCHITECTURE.md` §9. Changes to contract files (`models.dart`, `results.dart`, `repositories.dart`, `providers.dart`) are additive and go through the orchestrator.

**P: prerequisites (every rung depends on them)**

| # | Change | Files |
|---|---|---|
| P1 | Set `origin:` on every Health Connect `Provenance` the resolver emits, and carry `recordingMethod` on HRV rows (new column + migration) | `data/resolver/resolver.dart`, `data/services/health_connect/hc_types.dart`, `hc_mapper.dart`, `data/db/raw_rows.dart` (`RawHrvRow`), `data/db/schema.dart` |
| P2 | Round-trip `origin` in `Provenance.toJson`/`fromJson`, and include it in `==`/`hashCode` (today it's dropped, so stored `day_record` history loses its segment key) | `domain/models.dart:94-113` (contract) |
| P3 | Implement `sourceChoices()`/`setSourceChoice()` (stubbed today), and add a persisted **HRV mode** (nightly / morning) with the same sustained-absence switching rule | `data/repositories/health_repository_impl.dart:947-950`, `domain/repositories.dart` (contract) |
| P4 | Fix the fixture that models Samsung writing HRV (`samsungHrv`, used to test segment switching). The mechanism test is fine; add a comment that the real Samsung origin writes no HRV, and a Samsung-shaped fixture with no HRV and no RHR | `test/domain/baseline_origin_test.dart` |

**Rung 0d: single-record nightly HRV from an HC origin**
- `data/resolver/definitions.dart`: `hrvNightly(s) => '${s.code}_nightly_rmssd'` and `hrvSpot(s) => '${s.code}_spot_rmssd'`.
- `resolver.dart:303-313`: when the chosen origin has fewer than `minHrvSamples` inside the main sleep, accept its automatically recorded records stamped in `main.start … main.end + N` (N from §1). Route actively recorded and manual records to spot.
- Tests: `test/data/resolver_test.dart` with 1-record, wake-stamped and spot-record fixtures. On device, insert the same shapes with the Health Connect Toolbox.

**Rung 0e/0f: vendor API (personal build, `--dart-define=VENDOR_HRV_API=true`)**
- `domain/models.dart`: `SourceKind.whoopApi('whoop', 'WHOOP account')` and `SourceKind.ouraApi('oura', 'Oura account')` (contract, additive).
- New `data/services/whoop/`:
  - `whoop_auth.dart`: `flutter_appauth` code flow with PKCE, the BYO client ID and secret read from `flutter_secure_storage`, scopes `read:recovery offline`.
  - `whoop_client.dart`: `GET /developer/v2/recovery`, pages of ≤ 25 with `next_token`, 429 handling from the `X-RateLimit-*` headers, single-use refresh tokens.
  - `whoop_mapping.dart`: SCORED recoveries only → `RawScalarRow`.
- Same shape under `data/services/oura/` (`/v2/usercollection/sleep`, `long_sleep`, `average_hrv`).
- `data/db/raw_rows.dart`: `ScalarKind.hrvVendorNightly('hrv_vendor')`.
- `definitions.dart`: `whoop_api_recovery_rmssd` and `oura_api_sleep_average_hrv`, ranked after HC.
- **Android redirect:** `android/app/build.gradle.kts:32` sets one `appAuthRedirectScheme` placeholder, currently for Google. A second provider needs its own intent-filter in `AndroidManifest.xml`. Verify that `flutter_appauth` accepts that.
- UI: a BYO-credentials card in `features/settings/sources_screen.dart`. It explains the secret stays on this phone and that this is personal-use only.
- **Tests with recorded fixtures only** (no accounts). Build `test/data/fixtures/whoop_recovery_v2.json` and `oura_sleep_v2.json` from the OpenAPI examples, then add the edge cases: `PENDING_SCORE`, `UNSCORABLE`, `user_calibrating: true`, missing `score`, a multi-page `next_token`, a 401 → refresh → retry, a 429 with `Retry-After`, and Oura `type` values other than `long_sleep`. `test/data/google_health_test.dart` is the pattern to copy.

**Rung 1a: BLE morning check (`Metric.hrvMorning`)**
- **Domain (contract, additive):**
  - `Metric.hrvMorning('hrv_am')`
  - `DayRecord.hrvMorningRmssd` plus JSON
  - `RecoveryResult.hrvDefinition` (so the UI can label the row)
- **Engine:**
  - `inputs.dart`: `Inputs.hrvMorning`.
  - `baselines.dart`: `valueReader`.
  - `hrv_tools.dart`: `artifactFraction()` plus a session-reject constant (§4).
  - `recovery.dart`: when the mode is morning, the HRV component is scored against the `hrvMorning` segment. The label comes from the provenance, and the weight stays 0.40 by default (§8 Q4).
  - `readiness.dart`: run the Plews SWC on the morning series too; Plews' method was built on waking measures (§4).
  - `day_engine.dart`: notes.
  - `today_planner.dart` + `today_plan.dart`: `PlanActionKind.measure`.
- **Data:**
  - Extend the `hrv_check` save (`health_repository_impl.dart:892-912`) with posture, protocol version, analysed seconds, artifact fraction and sensor model.
  - Classify morning vs spot against the main sleep's end.
  - The resolver emits `Provenance(SourceKind.ble, 'ble_morning_rmssd_supine_v1', origin: 'ble:<model>')`.
- **UI:**
  - `features/live/live_view_model.dart`: settle and record phases, plus posture.
  - `features/live/widgets/live_widgets.dart:806-809`: copy.
  - `features/recovery/`: source line.
  - `features/trends/trends_view_model.dart`: a separate series and average row.
  - `features/settings/sources_screen.dart:566-575`: priority card text.
  - `features/onboarding/`: the offer.
- **Also update:** `domain/coach/tools.dart` (new metric, so the coach never calls a morning check "overnight HRV") and `data/repositories/export.dart` (new columns).
- **Tests:**
  - `test/domain/hrv_tools_test.dart`: artifact rejection.
  - New `test/domain/morning_check_test.dart`. Morning values never enter the `Metric.hrv` segment, Trends' HRV average or Pulse Age. The mode switches only after sustained absence.
  - RR fixtures recorded from a real strap (`test/data/fixtures/rr_*.json`) through the existing `hrs_parser`.

**Rung 1b: camera morning check** (behind a flag):
- A native `PpgAnalyzer.kt` in `android/app/src/main/kotlin/app/airlog/airlog/` (CameraX + Camera2Interop: torch, [30,30] fps, AE/AWB lock, red-ROI mean, `(timestampNs, meanRed)` over an EventChannel; no frames stored). The stock `camera` plugin can't do this (§5.3).
- `data/services/camera_ppg/`: the channel wrapper.
- Pure-Dart `domain/engine/ppg.dart`: timestamp resampling, bandpass, spline to ~180 Hz, peaks, and a quality index. Algorithms ported from HeartPy / NeuroKit2 (MIT). The beat intervals feed the same `HrvTools`.
- `SourceKind.camera('cam', 'Phone camera')`.
- Tests: recorded `(t, red)` traces from the user's phone (`test/domain/fixtures/ppg_*.json`), paired with strap RR where available.
- Add the `CAMERA` permission, and the Play listing device-compatibility statement.

**Rung 3: RHR slot for no-RHR sources**
- `definitions.dart`: `rhrSleepHr4h(s)`.
- Resolver: compute from the chosen origin's HR samples inside the main sleep (`hr_buckets.dart` holds per-minute HR) only when that origin has no `RestingHeartRateRecord`.
- `recovery.dart:167`: the label comes from the definition.
- Tests: a Samsung-shaped fixture (HR + sleep, no RHR or HRV) must produce a Recovery labelled "without HRV", with a "Sleeping HR (4 h mean)" row.

## 4. Bluetooth: who sends RR, and the minimum protocol

**NOT VERIFIED IN THIS PASS:**
- which wearables' broadcasts carry RR in `0x2A37` (WHOOP, Galaxy Watch, Garmin, Oura, Fitbit Air)
- which straps and armbands carry it (Polar H10, Garmin HRM, Wahoo TICKR, Coospo)
- the literature on protocol durations

A research agent was still running at handback. Code facts:
- RR arrives in 1/1024 s ticks behind flag bit 4 (`hrs_parser.dart`).
- The app detects RR at runtime: `rrAvailable` flips on the first frame that has it.
- The HRV check is unlocked only then.

So any sensor works if it sends RR, and none is assumed to.

Protocol v1, **provisional until cited**:
- measure on waking, before caffeine;
- the chosen posture, held still, breathing spontaneously;
- a settle period, then the analysed window (today's check is 120 s in total);
- reject the session when the artifact fraction exceeds a threshold still to be taken from the literature.

Verified support for the morning-measurement concept: "a short resting heart rate and HRV measurement upon waking using a smartphone app can effectively be used in free-living" (Altini & Plews 2021, n=28,175) [V-official] https://doi.org/10.3390/s21237932

## 5. Phone camera PPG

**Verdict:**
- **Feasible as an optional, quality-gated morning lnRMSSD *trend*, but not with the stock Flutter `camera` stream.** It needs a small native analyzer that sends `(sensor timestamp, mean red)` pairs to Dart.
- Single readings are imprecise.
- Peer-reviewed validation specific to Android is thin.
- It stays behind a flag and out of Recovery until it passes an on-device comparison against an RR reference.

### 5.1 Validation literature

| Study | n / reference | Conditions | RMSSD result | Label |
|---|---|---|---|---|
| Plews, Scott, Altini et al. 2017, IJSPP (HRV4Training) | 29 healthy; ECG + Polar H7 | "at rest during 5 min of guided breathing and normal breathing" | "average TEE CV% … 6.35"; differences "trivial"; R = 1.00. **iPhone** | V-official (abstract read) https://pubmed.ncbi.nlm.nih.gov/28290720/ |
| Johansson et al. 2026, Front Physiol (CameraHRV) | 37 athletes; ECG + Polar H10 | supine / 45°, **60 s** | bias −3.0 ms, **limits of agreement −29.7 to +23.7 ms, MAPE 17.5%** (strap 2.2%); ICC 0.83–0.90 | V-official (via agent) https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2025.1707318/full |
| Holmes et al. 2020, Sensors | 31; ECG | seated, ultra-short | lnRMSSD r 0.59–0.76 pre-exercise, 0.41 post | V-official (via agent) https://www.mdpi.com/1424-8220/20/20/5738 |
| Peng et al. 2015 (HTC Android) | 30; ECG | supine ≥ 5 min, **unfixed 20–30 fps** | RMSSD r 0.60–0.78, "not in acceptable agreement" | V-official (via agent) https://pmc.ncbi.nlm.nih.gov/articles/PMC4309304/ |
| Guede-Fernández et al. 2015 / 2020 (Android, 30 Hz) | 23 (2020); ECG | 3 breathing conditions, 2 phones | beat error ≈ 5.4 ms; RMSSD good, LF/HF insufficient; device effect | V-official (via agent) https://pubmed.ncbi.nlm.nih.gov/26737985/ ; https://doi.org/10.1016/j.bspc.2019.101717 |
| HRV4Training Android blog 2017 | 25 × 60 s windows vs H7 | rest + deep breathing | rMSSD RMSE 5 ms; S5, S6, Nexus passed; **S3 failed** | V-official (vendor, not peer-reviewed) https://www.hrv4training.com/blog2/heart-rate-variability-using-the-phone-camera-android-edition |
| Xu et al. 2026 meta-analysis | 43 studies (all PPG types) | — | pooled standardised error for RMSSD 0.188; "not evidence of interchangeability" | V-official (via agent) https://pubmed.ncbi.nlm.nih.gov/42655500/ |

**Reading of the evidence:**
- Resting RMSSD / lnRMSSD is the only metric worth taking; skip LF/HF in 1–2 minutes.
- One-minute error is wide (Johansson), so show trends against the morning baseline, not precise single values.
- The error gets worse after exercise and with motion.

### 5.2 Technical requirements

- **Sampling:**
  - HRV4Training captures at **30 fps and interpolates with a cubic spline to 180 Hz**.
  - Béres: RMSSD within 5% needs ≥ 50 Hz raw, or ≥ 20 Hz *with* interpolation. That assumes **uniformly spaced samples**.
  - Frame jitter is named as "a major source of variability and error across different phone models" (https://pubmed.ncbi.nlm.nih.gov/26737108/).

  [V-official, via agent]
- **Timestamps:**
  - Camera2 `SENSOR_TIMESTAMP` is the exposure start in ns, and it's monotonic. CameraX exposes it as `ImageInfo.getTimestamp()`.
  - Fix the rate with `CONTROL_AE_TARGET_FPS_RANGE` = [30,30] (try [60,60]).
  - High-speed (≥ 120 fps) sessions can't feed an `ImageReader`, so the iPhone 240-fps results don't transfer.

  [V-official] https://developer.android.com/reference/android/hardware/camera2/CaptureResult#SENSOR_TIMESTAMP ; https://developer.android.com/reference/android/hardware/camera2/CaptureRequest#CONTROL_AE_TARGET_FPS_RANGE
- **Signal processing:** red channel; torch on with AE/AWB locked after settling; bandpass filter; peak detection (max first derivative, per Guede 2020); range and successive-difference beat filters; reject by the removed-beat fraction.

### 5.3 Flutter feasibility (read in plugin source by the research agent)

- `camera` 0.12.1 uses `camera_android_camerax` 0.7.5 by default. [V-official] https://pub.dev/packages/camera
- **`CameraImage` has no timestamp.** On CameraX, even `sensorExposureTime` and the other metadata fields are null. [V-code]
- `MediaSettings.fps` does reach ImageAnalysis on CameraX [V-code]. There's still no AWB lock and no manual exposure.
- Frames are analysed on the main executor with a queue depth of one, so they can **drop silently**. Dart arrival times carry platform-channel jitter. [V-code + V-official]
- **So `startImageStream` isn't HRV-grade.** Build the native analyzer instead:
  - Kotlin, CameraX ImageAnalysis + Camera2Interop, or plain Camera2;
  - low resolution; red-ROI mean computed natively on a background executor;
  - an EventChannel carrying `(timestampNs, meanRed)` only;
  - no frames stored or sent anywhere (privacy).
- **Open-source reuse:**
  - **HeartPy (MIT)** and **NeuroKit2 (MIT**; PPG peaks, `ppg_quality`, Kubios-style artifact correction) are safe references to port algorithms from, into pure Dart `domain/engine/ppg.dart`.
  - `flutter_ppg` (MIT) is frame-quantised (~33 ms RR resolution) and has no RMSSD, so don't use it.
  - Avoid **GPL-3.0** code: pyVHR, Aura hrv-analysis.

  [V-code, via agent]
- **Play policy:** apps that use the camera for health functions must state device compatibility in the listing. Non-regulated apps need the "not a medical device …" disclaimer. [V-official, via agent] https://support.google.com/googleplay/android-developer/answer/16679511?hl=en

### 5.4 On-device tests that gate the rung (all doable on the user's phone)

1. Delivered fps under [30,30] and [60,60], with the torch on and AE locked.
2. `SENSOR_TIMESTAMP` jitter, the dropped-frame rate, and `SENSOR_INFO_TIMESTAMP_SOURCE`.
3. Red-channel clipping, and torch heat over 2 minutes.
4. **The decisive test:** RMSSD vs an RR reference (a chest strap, or the band's RR if it has any) over several mornings: bias, limits of agreement, rejection rate.
   - The pass threshold is an open decision (§8).
   - Without a reference device the rung can't graduate from the flag.

## 6. Rejected, and why

| # | Rejected | Why |
|---|---|---|
| R1 | **"HRV" estimated from heart-rate samples** (successive differences of bpm samples, HR→RMSSD regression, "HRV from HR" models) | Principle 6. HC heart-rate samples are averaged bpm, not beat intervals, so RMSSD is undefined for them (§7) |
| R2 | **Merging a morning check into the nightly baseline**, or converting between them with a ratio or offset | Different measurements (posture, state, duration, sensor). The constraint says never merged. Several `Metric.hrv` consumers are **not segment-aware** and would pool them silently: `trends_view_model.dart:299, 414` (HRV band and average), and `day_engine.dart:569` (Pulse Age `rmssdValues`). That is why morning checks get their own `Metric.hrvMorning` [V-code] |
| R3 | **Showing or ingesting the source's own score** (WHOOP Recovery, Oura Readiness, Samsung Energy Score) as an HRV stand-in | §7 decision "Whose scores": always our own. Only the source's *measurement* (`hrv_rmssd_milli`, `average_hrv`) is allowed |
| R4 | **Embedding a shared WHOOP or Oura client secret** in the APK | RFC 8252 §8.5 (shared secrets in distributed apps aren't confidential). WHOOP: "never … in a mobile application" and "may not be embedded in open-source projects". Oura: the credentials may not be disclosed to "any third party" |
| R5 | **An Airlog token-exchange server** (Worker or Lambda holding the secret) | Breaks principle 4 ("no server"), and it would see every user's tokens. Only revisit if the user explicitly relaxes principle 4 for a public WHOOP integration |
| R6 | **Aggregators** (Terra, Thryve, Rook, Open Wearables cloud) | Already rejected in `PRODUCT_PLAN.md` §2.5: their servers sit in the data path |
| R7 | **WHOOP's proprietary BLE protocol** (reverse-engineering strap sync) | WHOOP's API terms forbid circumventing "WHOOP controls or safeguards" and reverse engineering. research/08: scoring happens on WHOOP's servers, so there's nothing on the strap to read that's worth the risk |
| R8 | **Samsung Health Sensor SDK watch app** (IBI on the Galaxy Watch) | A separate Wear OS app plus Samsung partner approval; developer mode needs a key issued after partnership approval [V-official] |
| R9 | **Samsung Health Data SDK** as an HRV source | Has no HRV type (§1.1) [V-official] |
| R10 | **Oura implicit ("client-side only") flow** as the default Oura sign-in | RFC 9700 SHOULD NOT; no refresh token; re-login every 30 days. BYO + code + PKCE is preferred. Implicit stays only as a fallback if the user won't paste a secret |
| R11 | **Lowest overnight HR** as a recovery input | No validation found; the 4-h segment mean is the supported form (§7) |
| R12 | **Nocturnal HR dip** | Clinical and prognostic evidence only; no day-to-day recovery use (§7) |
| R13 | **Spot HRV records from other apps** (Welltory-style, `RECORDING_METHOD_ACTIVELY_RECORDED` or manual) feeding the nightly definition | Wrong measurement for that slot (§1.2). They're stored as `hc_spot_rmssd` and not used by Recovery |
| R15 | **Oura API rung** | Oura already writes HRV to Health Connect (§1). The API would add a server-side dependency and terms risk for no new measurement |
| R14 | **A public build with the vendor-API rung on** | WHOOP's "compete" clause and Oura's "competes with or merely replicates" clause directly target an app that recomputes Recovery. Both storage clauses also conflict with local baselines (§2.C) |

## 7. HR-only proxies (overnight minimum HR, sleeping HR, HR dip)

**Short answer:**
- Overnight HR is a well-supported training-load, illness and alcohol marker **as heart rate**.
- Nothing supports calling any HR-derived number "HRV".
- It belongs in the **existing resting-HR slot (25%)**, and only for a source that writes no resting HR (Samsung). It must never be a second HR input, and never an HRV substitute.

| Proxy | Evidence for day-to-day use | Reliability | Verdict | Sources |
|---|---|---|---|---|
| **Mean HR over a fixed sleep segment: 4 h starting 30 min after sleep onset** | After a maximal 3000-m test, "HR increased … whereas LnRMSSD … decreased … only in 4H and FULL", and "Increments in HR … were greater in 4H compared with FULL and MOR" (Nuuttila 2022, n=23) [V-official, abstract read]. During overload, the 4-h HR response tracked the performance change (r=0.63) better than LnRMSSD (r=−0.50) (Nuuttila 2024) [V-official, via research agent]. Alcohol raised HR in the first 3 h of sleep by +1.4 / +4.0 / +8.7 bpm for low / moderate / high intake (Pietilä 2018, n=4,098) [V-official, via agent] | "very high ICC … .97 to .98 for HR" (Nuuttila 2022). CV 6.0–8.3% (Nuuttila 2024) | **Use, but only as the RHR input for sources without RHR**, under its own definition | https://doi.org/10.1123/ijspp.2022-0145 ; https://doi.org/10.1186/s40798-024-00779-5 ; https://doi.org/10.2196/mental.9519 |
| Full-night mean HR | Sensitive, but less than the 4-h segment (Nuuttila 2022) | CV 6.0% (Nuuttila 2024) | Fallback if the sleep is shorter than 4.5 h | as above |
| Lowest overnight HR / lowest 5-min HR | No paper found validating it as a load marker. It is vendor practice: Oura's "Resting heart rate" contributor is the lowest overnight HR [V-official, vendor] https://support.ouraring.com/hc/en-us/articles/360057791533-Readiness-Contributors | not found | **Don't use.** A minimum is more exposed to artifacts and dropouts than a segment mean, and has no validation | — |
| Nocturnal HR dip (awake vs asleep) | Clinical and prognostic only (mortality hazard ratio 2.67, Ben-Dov 2007). Cuspidi 2017 calls the organ-damage evidence "weak and not univocal". No day-to-day recovery use found | 78% of dippers stayed dippers over 4 weeks | **Reject** | https://doi.org/10.1001/archinte.167.19.2116 ; https://doi.org/10.1111/jch.12969 |
| "HRV" from HR samples (successive differences of bpm samples, or HR-to-RMSSD regression) | HR samples in Health Connect are averaged values, not beat intervals, so RMSSD can't be computed from them. HRV depends on HR, but Sacha's work is a *normalisation*, not a substitute (https://doi.org/10.3389/fphys.2013.00306) [V-official, via agent] | — | **Reject** (principle 6) | — |

Resting HR changes at least as clearly as rMSSD with alcohol and sickness in 28,175 HRV4Training users:
- alcohol: +6% (d=0.97) vs −12% (d=0.55)
- sickness: +6% (d=0.97) vs −10% (d=0.47)

[V-official, abstract read; the first author develops HRV4Training] https://doi.org/10.3390/s21237932

So a Recovery built on RHR, sleep and respiratory rate is not blind to those events. It's just less sensitive to training fatigue (Pichot 2000: the parasympathetic index fell up to 41% while nocturnal HR changed less than 12%).

**Decision:**
- **Definition string for the RHR slot:** `hc_sleep_hr_4h_mean`, keyed `@origin`.
  - Mean of HR samples from the chosen origin, from sleep onset + 30 min to sleep onset + 4 h 30 min.
  - Requires ≥ 1 sample per 5 min over ≥ 80% of the segment (sample density **unverified** for Samsung; measure it in the probe).
  - Label: **"Sleeping HR (4 h mean)"**, never "Resting HR" and never "HRV".
- **Used only when the chosen origin writes no `RestingHeartRateRecord`.** For WHOOP, Fitbit, Garmin (declared), Withings, COROS and Zepp, the source's own RHR stays. Oura, Ultrahuman, Mi Fitness and Samsung write none (§1).
- **Code consequence:** `recovery.dart:167` hard-codes the component label `'Resting HR'`. The label must come from the definition, or the Samsung Recovery screen would be mislabelled.
- **HR-only nights:** with no HRV, re-weighting raises RHR's effective weight from 25% to about 42% (0.25/0.60). That is HR standing in for HRV *indirectly*.
  - Today's mitigation already exists: `RecoveryConfidence.reduced` plus the "without HRV" label.
  - Whether to also cap the RHR weight is an open question (§8). A cap would be a new constant with no source.

## 8. Open questions

1. **HC record shape per origin** (Oura, Withings, COROS, Zepp, Ultrahuman): how many HRV records per night, where they're timestamped, and their `recordingMethod`. The "declared" rows need an observed record. The probe's all-origins dump settles it for installed apps. Also: does COROS write its manual daytime check as HRV?
2. **WHOOP public client:** can a dashboard app exchange a code with PKCE and no secret? It needs a WHOOP membership to test.
3. **Does WHOOP's broadcast carry RR?** Does the Fitbit Air's? That decides rung 1 for those users, and option E.
4. **Morning-check weight in Recovery:** keep 0.40 (one formula for every device) or lower it? No source found for either.
5. **Cap on RHR's effective weight on HR-only nights?** It would be a new constant with no source.
6. **Vendor storage terms vs local baselines:** is a 30-night on-device window "strictly necessary" (Oura)? Does the member count as the "WHOOP Data owner"? A legal question, unresolved.
7. **WHOOP terms version:** read 2026-09-29, with an effective date of 2026-10-06. Re-read before building.
8. **Samsung:** re-check the table after each Samsung Health update ("scope can be changed depending on the Samsung Health version"). Also, what is Samsung's HR sample density in HC, which rung 2's 4-h mean needs?
9. **Hardware on hand:** does the user own an RR chest strap? Which phone model (for camera fps)?
10. **Camera pass threshold:** what bias and limits of agreement vs a strap let the camera rung leave the flag? No published standard; decide before testing.

## 9. Sources (primary, fetched 2026-09-29)

- Samsung: https://developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect ; https://developer.samsung.com/health/health-connect-faq.html ; https://developer.samsung.com/health/data/api-reference/-shd/com.samsung.android.sdk.health.data.data.entries/-heart-rate/index.html ; https://developer.samsung.com/health/sensor/overview.html ; https://developer.samsung.com/health/sensor/guide/developer-mode.html ; https://us.community.samsung.com/t5/Galaxy-Watch/HRV-breathing-rate-and-resting-HR-won-t-write-to-the-health/td-p/3351258 ; https://github.com/the-momentum/open-wearables/issues/1723
- WHOOP: https://developer.whoop.com/docs/developing/oauth/ ; https://developer.whoop.com/docs/developing/getting-started/ ; https://developer.whoop.com/docs/developing/overview/ ; https://developer.whoop.com/docs/developing/rate-limiting/ ; https://developer.whoop.com/docs/developing/app-approval/ ; https://developer.whoop.com/docs/developing/user-data/recovery/ ; https://developer.whoop.com/api-terms-of-use/ ; https://api.prod.whoop.com/developer/doc/openapi.json ; https://api.prod.whoop.com/oauth/.well-known/openid-configuration ; https://www.whoop.com/us/en/thelocker/heart-rate-variability-hrv/
- Oura: https://cloud.ouraring.com/docs/authentication ; https://cloud.ouraring.com/v2/static/json/openapi-1.41.json ; https://cloud.ouraring.com/legal/api-agreement
- OAuth: https://www.rfc-editor.org/rfc/rfc8252 ; https://www.rfc-editor.org/rfc/rfc9700
- Health Connect: https://developer.android.com/health-and-fitness/health-connect/metadata ; https://developer.android.com/health-and-fitness/health-connect/test/health-connect-toolbox
- Literature: https://doi.org/10.1123/ijspp.2022-0145 ; https://doi.org/10.3390/s21237932 ; https://doi.org/10.14814/phy2.70527 ; the other §7 DOIs, via the research agent
- Code: `health-13.3.2` (`health_data_point.dart:50`), `flutter_appauth-12.1.0` (`FlutterAppauthPlugin.java:421`), and Airlog files cited inline
