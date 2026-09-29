# Pulse repo research (Luraxx/pulse)

Local path: `C:/Users/ARMAAN~1/AppData/Local/Temp/claude/C--Users-Armaan-khan-Desktop-Hobbies/edfd83b6-f952-4033-acbc-dcc517766b76/scratchpad/pulse`
License: Apache-2.0. Swift 5.9, iOS 17+. Version reviewed: v0.1.0 (2026-07-22), README/SETUP describe "today" (2026-09-28) as still current.

All claims below are read directly from source/docs unless marked **[UNVERIFIED]** — meaning the repo asserts it but it cannot be confirmed against a real device/API without Google Cloud access, which this task did not have.

---

## 1. Google Health API v4 data mapping

Base URL: `https://health.googleapis.com/v4` (`Core/API/HealthAPIClient.swift:36`). All endpoints are read-only, per-user (`/users/me/dataTypes/{type}/dataPoints[:reconcile]`).

### Read-path resilience (important architectural fact)
Because the API is new (v4, launched May 2026 per SETUP.md:26) and field names aren't fully finalized, Pulse never assumes a fixed schema:
- **Candidate-key JSON extraction** (`Core/API/JSONExtract.swift:56-104`): `firstDouble/firstString/firstDate` do a breadth-first search (depth ≤4) through nested dicts/arrays for the first matching key out of an ordered candidate list (e.g. `["beatsPerMinute", "bpm", "value"]`). This means Pulse doesn't know the exact field name Google will use — it guesses several and takes whichever hits.
- **Read-variant fallback** per data type (`HealthAPIClient.swift:56-140`): tries `…:reconcile` → `list` with a range filter → `list` with only a start filter, in that order, and caches whichever variant worked (`workingVariant` map). A 400/404 tries the next variant; other errors propagate.
- Every metric is fetched independently in `SyncEngine.swift` inside its own `do/catch`; one failing type is logged to a per-metric **sync log** (`SyncLogEntry`) and never blocks the others.

### Data-type table (from SETUP.md:213-224, cross-checked against `SyncEngine.swift`)

| Metric | dataType (URL, kebab-case) | Payload key | Granularity | Candidate value keys (from code) | Fallback / note |
|---|---|---|---|---|---|
| Heart rate (intraday) | `heart-rate` | `heartRate` | Raw samples down to ~5s (SelfTest fixture comment, `SyncEngine.swift:384-389`), downsampled to **1-minute buckets** client-side (`SyncEngine.downsampleToMinutes`, `SyncEngine.swift:492-502`) | `beatsPerMinute`, `bpm`, `value` | None — this is itself the fallback source for resting HR |
| HRV | `heart-rate-variability` | `heartRateVariability` | Samples grouped into **nightly mean** RMSSD (`SyncEngine.groupByNight`, `SyncEngine.swift:152-153,462-468`) | `rmssd`, `rmssdMilliseconds`, `milliseconds`, `dailyRmssd`, `value` | Falls back to daily aggregate type `daily-heart-rate-variability` / payload `dailyHeartRateVariability` (keys `rmssdMilliseconds, rmssd, milliseconds, value`) if the sample stream returns nothing (`SyncEngine.swift:162-181`) |
| Sleep | `sleep` | `sleep` | Session objects with `interval.{startTime,endTime}` + `stages[]` (each with `type`,`startTime`,`endTime`) + `summary.{minutesAsleep,minutesAwake}` | n/a (structured, not scalar) | If `summary.minutesAsleep` missing, computed from stage spans; if that's also empty, estimated as 92% of session duration (`HealthAPIClient.swift:303-307`) |
| Respiration | `daily-respiratory-rate` | `dailyRespiratoryRate` | Daily value, filtered by civil `date` | `breathsPerMinute`, `rate`, `value` | None |
| SpO₂ | `oxygen-saturation` | `oxygenSaturation` | Samples grouped per night → **average + minimum** (`SyncEngine.swift:210-227`) | `percentage`, `averagePercentage`, `value` | None |
| Skin/body temperature | `daily-sleep-temperature-derivations` | `dailySleepTemperatureDerivations` | Nightly derived value, daily type | `nightlyTemperatureCelsius`, `baselineTemperatureCelsius`, `celsius`, `value` | None |
| Resting HR | `daily-resting-heart-rate` | `dailyRestingHeartRate` | Daily value | `beatsPerMinute`, `bpm`, `value` | Fallback: **5th percentile of overnight (00:00–08:00) intraday HR samples** (`SyncEngine.swift:441-453`), used whenever the daily type is absent |
| VO₂max | `daily-vo2-max` | `dailyVo2Max` | Daily value (cardio fitness, ml/kg/min) | `vo2Max`, `vo2max`, `cardioFitnessScore`, `value` | Fallback: heart-rate-ratio estimate in `AgeEngine` (see §3) — not fetched from a different endpoint, computed locally |
| Steps | `steps` | `steps` | Interval samples, **summed per calendar day** | `count`, `steps`, `value` | None |
| Workouts/exercise | `exercise` | `exercise` | Session with `interval.{startTime,endTime}` (older fixtures: `sessionTimeInterval`), `activityName`/`activityType`/`name`, `averageHeartRate`/`avgHeartRate`/`averageHeartRateBpm`, `calories`/`caloriesBurned`/`activeCalories` | n/a | Must be filtered via `interval.civil_start_time` (**civil/local time, no trailing `Z`**) — the only data type with this quirk (`HealthAPIClient.swift:332-338`) |
| Profile | `/users/me/profile` (not a dataType) | `profile` | Once per sync | `displayName`/`fullName`, `birthday`/`dateOfBirth`, `gender`/`sex`/`biologicalSex` | Sex mapped via `BiologicalSex(apiValue:)` (`MALE`/`M`→male, `FEMALE`/`F`→female, else unspecified) |

### Sync phasing and rate limits
- Two-phase sync (`SyncEngine.sync`, `SyncEngine.swift:54-67`): Phase 1 = all daily/nightly metrics (fast, ~10 sequential steps, weighted 55% of progress bar); Phase 2 = intraday heart rate (expensive, weighted 45%), up to 4 days fetched **concurrently** (`maxConcurrent: Int = 4`, `SyncEngine.swift:349`).
- Incremental/backfill: default `daysBack = 60` (first sync), `hrDaysBack = 14`, both user-configurable in Settings (`AppModel.swift:197-198`). A day's intraday HR is considered "complete" and skipped on future syncs once checked after its own day-end, **except** today and yesterday, which always re-sync (clock/late-sync tolerance) (`SyncEngine.isIntradayComplete`, `SyncEngine.swift:337-342`).
- Rate limiting: client-side throttle enforces a **minimum 0.25s between requests** (~4/s) plus global cooldown after any 429, backing off further per Google's documented **300 requests/min/user** cap (SETUP.md:234; `HealthAPIClient.swift:44-49, 456-479`). Retry-After header respected; otherwise exponential backoff (2,4,8…s) capped at 60s (`HealthAPIClient.retryDelay`, tested in SelfTest).
- HR sample post-processing: spike removal (`SyncEngine.removeSpikes`, maxJump=40bpm, only smooths isolated single-sample artifacts, not genuine ramps) and downsampling to 1-min buckets before storage. Retention: intraday HR pruned after 28 days (`MetricsStore.hrRetentionDays`) to keep the JSON store small.

### Known-missing / unreliable data (explicitly flagged in docs/code)
- SETUP.md troubleshooting section: individual metrics can be empty because "the data type may not be populated for the Fitbit Air yet, or it is named differently"; sleep-derived values (HRV, respiration, SpO₂, temperature) "only appear after you have actually slept wearing the band."
- CHANGELOG.md "Known limitations": Google Cloud project stays in Testing mode → refresh tokens expire every 7 days; Pulse Age needs ~30 days of history before leaving "calibrating"; in-app sync log is German-only (contradicts the bilingual UI claim — a genuine loose end).
- Code comment at `SyncEngine.swift:156-161`: distinguishes "Google sent 0 raw data points" vs "Google sent N raw points but we couldn't decode a value field" — the latter is logged as an error specifically to help diagnose a renamed field.

---

## 2. Auth flow

- **Client type**: iOS OAuth client only, **no client secret** (PKCE) — `Core/API/GoogleAuth.swift:6-31`. Bundle ID default `net.dehlwes.pulse`.
- **Redirect URI derivation**: Google's iOS convention — reversed client ID as URL scheme, e.g. `1234-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.1234-abc:/oauth2redirect` (`GoogleOAuthConfig.reversedClientScheme`/`redirectURI`, `GoogleAuth.swift:14-26`).
- **PKCE**: S256 challenge over a 32-byte random verifier, base64url-encoded (`GoogleAuth.swift:49-79`). Verified against the RFC-7636 test vector in SelfTest (`main.swift:33-38`).
- **Scopes** (4, all `.readonly`, `HealthScopes.read`, `GoogleAuth.swift:35-40`):
  - `googlehealth.health_metrics_and_measurements.readonly`
  - `googlehealth.sleep.readonly`
  - `googlehealth.activity_and_fitness.readonly`
  - `googlehealth.profile.readonly`
- **Authorization URL**: `https://accounts.google.com/o/oauth2/v2/auth` with `response_type=code`, `code_challenge_method=S256`, and notably **no `prompt=` parameter** — SelfTest explicitly checks this is absent, commented as a "Google Health recommendation" (`main.swift:54`) **[UNVERIFIED — reasoning not sourced in-repo beyond the code comment]**.
- **Presentation**: `ASWebAuthenticationSession` via `App/Auth/WebAuthenticator.swift`, non-ephemeral (`prefersEphemeralWebBrowserSession = false`, so it can reuse the user's existing Google session/cookies).
- **Token exchange/refresh**: standard `POST https://oauth2.googleapis.com/token`, form-encoded body, `authorization_code`/`refresh_token` grants (`GoogleAuth.swift:183-228`). On HTTP 401 during any API call, the client refreshes once and retries automatically (`HealthAPIClient.swift:415-418`). `invalid_grant` in the token error body is mapped to `.refreshExpired`.
- **Token storage**: Keychain, `kSecClassGenericPassword`, service `net.dehlwes.pulse.oauth`, `kSecAttrAccessibleAfterFirstUnlock` (`Core/API/Keychain.swift`, `GoogleAuth.swift:127-142`). JSON-encoded `TokenSet {accessToken, refreshToken?, expiry}`.
- **Google Cloud project setup** (SETUP.md Part 1): user creates their own project, enables "Google Health API", sets OAuth consent screen to **External + Testing** publishing status, must add their own Google account under **Audience → Test users**, and manually grants the 4 scopes under Data Access. Creates an **iOS-type** OAuth client (no secret).
- **Testing-mode caveat (explicit, repeated in 3 docs)**: while the Cloud project is unpublished ("Testing"), Google expires refresh tokens after **7 days**; publishing would require Google's verification review for restricted health scopes, "not worth it for personal use" per the README. Pulse surfaces this as a one-tap "Reconnect" flow and a scheduled local notification near expiry (`AppModel.swift` `PulseNotifications.scheduleTokenExpiry`, referenced but notification code itself not in the files I read in full).
- **No shared backend**: explicitly stated in 3 places (README, SETUP, CONTRIBUTING) — everything is local, PKCE means no secret ever exists to leak, every user runs their own Cloud project.

---

## 3. Algorithms (exact formulas, constants, sources)

### Recovery (1–99%) — `Core/Metrics/RecoveryEngine.swift`
Weights (`RecoveryEngine.weights`, line 35-40): **HRV 0.40 · resting HR 0.25 · sleep 0.25 · respiration 0.10**. Missing components are dropped and the rest **re-normalized** (`totalWeight` divisor, lines 106-112) — e.g. no HRV data still allows a recovery score.

- **HRV**: 30-day history of `ln(rmssd)` → baseline (mean, SD, min SD floor 0.03) → z-score `z = (ln(hrv) - mean) / max(sd, 0.03)` → `score = logistic(z * 1.1)` (lines 62-72). Log-transform because RMSSD is right-skewed.
- **Resting HR**: baseline of raw bpm (min SD 0.8) → `score = logistic(-z * 1.1)` (inverted: lower RHR vs. baseline = better) (lines 75-86).
- **Sleep**: uses **previous night's sleep performance** (%) directly, clamped to [0.1, 1.0] (lines 88-91) — not z-scored.
- **Respiration**: baseline (min SD 0.25); only penalized when *elevated* — `score = clamp(0.85 - max(0, z-0.3)*0.2, 0.2, 0.85)` (lines 93-104).
- **Penalties** (subtracted from the 0-100 weighted score, not re-weighted): SpO₂ min < 90% → **−7**; body temp z (min SD 0.15) > **+1.8 SD** → **−5** (lines 125-131).
- Final: `clamp(score, 1, 99)`, rounded to Int.
- **Zones**: green ≥67, yellow 34–66, red <34 (matches published Whoop bands, per README/SETUP).
- **Calibrating flag**: true only if a component that *has* data lacks a reliable baseline (≥5 points) — deliberately scoped per-metric so a device that never reports HRV doesn't permanently block calibration (code comment lines 135-140, and SelfTest section "Recovery-Kalibrierung" confirms 10 nights of RHR-only data calibrates fine without HRV).
- `Baseline.isReliable` = `count >= 5` (`Stats.swift:16`). `Stats.baseline()` requires ≥3 points to exist at all.
- `Stats.logistic(x) = 1/(1+e^-x)` — standard logistic, no scaling beyond the ×1.1 multiplier applied to z before calling it.

### Strain (0–21) — `Core/Metrics/StrainEngine.swift`
TRIMP-style: time-in-heart-rate-reserve-zone, weighted sum, log-mapped to a ceiling.
- **Max HR**: override or **Tanaka formula** `208 − 0.7 × age` (`StrainConfig.maxHR`, lines 16-18).
- **Karvonen HRR zones** (lines 56-58), lower bounds as fraction of HRR `(bpm − restingHR)/(maxHR − restingHR)`:
  | Zone | Lower bound (HRR) | Weight | Label |
  |---|---|---|---|
  | 0 | 0.20 | 0.5 | Very light |
  | 1 | 0.30 | 1.0 | Light |
  | 2 | 0.45 | 2.5 | Moderate |
  | 3 | 0.60 | 5.0 | Demanding |
  | 4 | 0.72 | 8.0 | Hard |
  | 5 | 0.85 | 11.0 | Max |
  Below zone 0 (HRR<20%) counts as "rest" time, no strain contribution.
- **Accumulation**: per HR sample, `dt` = minutes since previous sample (clamped 0–5 to survive gaps), `raw += zoneWeight[zone] * dt` (lines 82-118).
- **Log mapping to the 0–21 scale**: `strain = 21 × (1 − e^(−raw/τ))`, **τ = 450** default (`StrainEngine.strain`, line 60-63). SelfTest calibration points: raw load 60→~2-4 (easy day), 300→~9-12 (solid training), 900→~16-19 (hard day), asymptotically <21 as raw→∞.
- **Fallback without intraday HR**: workout average HR mapped to a zone × workout duration, plus `steps/1000 × 2.0` raw-load points (lines 142-154) — a much coarser proxy.
- **Daily strain target** (the tick mark on the ring): `target = clamp(0.2 × recovery, 3, 18.5)` (line 71) — simple linear function of that day's recovery score, explicitly *not* derived from any Whoop formula, just calibrated by the author to land in Whoop's published ranges (training ~14-18, easy ~10-14).
- **Per-workout strain**: same accumulate/mapping restricted to samples within the workout's time window if ≥3 samples exist; else the single-zone/duration fallback (lines 164-183).

### Sleep — `Core/Metrics/SleepEngine.swift`
- **Need** (minutes): `need = baselineNeed(456 min = 7h36m default) + debt × 0.30 (debtRepayFraction) + strainBoost`, clamped to `[baseline−30, baseline+150]` (lines 76-78, 133-135).
  - `strainBoost = clamp((prevDayStrain − 8)/13, 0, 1) × 45min` (max sleep-need boost is capped at 45 minutes, kicks in above strain 8).
- **Debt accounting** (lines 139-149): debt is computed against `structuralNeed = baseline + strainBoost` (NOT the debt-inclusive displayed need, to avoid compounding/interest — explicit code comment). Nightly delta = `min(structuralNeed − slept, maxDebtGainPerNightMinutes=180)`, then `debt = clamp(debt + delta, 0, maxDebtMinutes=300)`. SelfTest confirms: a single catastrophic short night is capped at +180 min debt gain (not the full deficit), sleeping exactly baseline holds debt flat, oversleeping by X pays back X.
- **Performance** = `min(100, sleptMinutes/need × 100)`.
- **Consistency** (0–100): mean circular deviation of bed+wake times vs. a rolling window of the **last 4 nights**, `consistency = clamp(100 − avgDeviationMinutes/90 × 100, 0, 100)` (lines 151-166) — i.e., 90 minutes of average drift maps to 0.
- **Efficiency** = `minutesAsleep / minutesInBed × 100` (`SleepSession.efficiency`, `Models.swift:76-79`).
- **Bedtime recommendation**: projects tonight's need (same formula, using today's strain) onto the mean of recent wake-clock-times, `bedtime = (habitualWake − need) mod 1440` (`SleepEngine.bedtimeRecommendation`, lines 70-101).
- Stage decoding maps Google's `AWAKE/WAKE/RESTLESS→awake`, `LIGHT/ASLEEP→light`, `DEEP→deep`, `REM→rem`, else `unknown` (`Models.swift:13-21`) — tolerant of both Google Health v4 and legacy Fitbit-style stage enums.

### Health Monitor (±1.65 SD bands) — `Core/Metrics/HealthMonitor.swift`
- Per metric (restingHR, HRV, respiratoryRate, spo2, bodyTemp): 30-day baseline, band half-width = `max(1.65 × SD, kind.minimumHalfWidth)` (line 83) — the 1.65 SD constant approximates a **90% two-tailed** normal interval; minimum half-widths exist per metric to prevent overly tight bands from a very stable baseline (RHR≥3bpm, HRV≥10ms, resp≥0.8/min, SpO₂≥1.5%, temp≥0.4°C).
- SpO₂ is one-sided: only a *low* band matters, with a hard floor of 90% (lines 87-91).
- **Proactive alert** (`HealthMonitor.alert`, lines 153-195): needs ≥6 days of history. Two independent trigger rules over a 3-day lookback:
  1. **≥2 metrics concerning today** → "possible infection or overtraining" message.
  2. **1 metric concerning for ≥2 consecutive days** → streak warning naming that metric.
  "Concerning" direction is metric-specific: HRV/SpO₂ trigger on *low*, RHR/respiration/temp trigger on *high* (lines 127-132).

### Pulse Age (biological age) — `Core/Metrics/AgeEngine.swift`
Backbone = VO₂max → fitness age via **FRIEND reference norms** (Kaminsky et al., *Mayo Clin Proc* 2015, 50th percentile, sex-specific, decade midpoints — hardcoded lookup tables `AgeNorms.vo2maxMale/Female`, lines 21-24), because "VO₂max is the strongest single predictor of all-cause mortality" (Mandsager et al., *JAMA Netw Open* 2018, n=122,007; cited in both SETUP.md and code comments).
- **VO₂max source priority**: measured (`daily-vo2-max`, needs ≥3 days, median taken) preferred over estimated. If <3 measured days: estimate via **heart-rate-ratio method** (Uth et al. 2004): `VO2max ≈ 15.3 × HRmax/HRrest`, clamped to [15,80] ml/kg/min (lines 226-241, `uthFactor = 15.3`). `HRmax` = user override, else a **"trustworthy" observed max** (97.5th percentile of intraday HR, only accepted if in physiologic range [150,220]), else **Nes/HUNT formula** `211 − 0.64×age`.
- **Fitness age**: inverts the piecewise-linear VO₂max-vs-age curve (`AgeNorms.fitnessAge`), clamped to [20,90] (chosen because FRIEND norms start at the 20-29 decade).
- **HRV age**: separate reference curve `AgeNorms.rmssdRef` (decade midpoints 25→60ms … 65→23ms, sex-agnostic — "differences here are small and inconsistent" per code comment), inverted and clamped to [18,85]. Requires ≥7 RMSSD readings.
- **Core age** = weighted mean of the two equivalent ages available: **VO₂max weight 0.7, HRV weight 0.3** (`fitnessWeight`/`hrvWeight`, lines 213-214). If only one is available, its weight alone is used (renormalized).
- **Capped adjustments** (added to core, summed and capped to **±5 years total**, lines 344-349):
  - Resting HR: `clamp((rhr − sexRef)/10 × 2.5, −3, 3)` years, where sexRef = 60(M)/63(F)/61(unspecified) bpm. Anchored on **+10bpm ≈ HR 1.09 for all-cause mortality** (Zhang et al., *CMAJ* 2016, n≈1.2M) — "roughly 2.5 aging-years" is the author's own heuristic conversion, not from the paper directly **[flag: heuristic, not literature-sourced]**.
  - **Skipped entirely if VO₂max was estimated** (not measured) — explicit anti-double-counting: the HR-ratio VO₂max estimate already has resting HR in its denominator (lines 262-271, tested in SelfTest "Doppelzählungs-Schutz").
  - Sleep: `clamp((78 − meanPerformance)/12, −1.5, 1.5)` years — target corridor ~78% performance.
  - Activity: `clamp((1 − clamp(steps/8000,0,1.6)) × 1.5, −1.5, 1.5)` years — target ~8000 steps/day.
- **Calibration gating**: needs `validDayCount ≥ 30` (`calibrationNeed`) for a displayed Pulse Age at all; shows "calibrating" with progress `min(validDayCount,30)` before that; a separate `minProvisionalDays = 14` constant exists but per the current `compute()` logic the pulseAge is only set once `hasEnoughDays` (≥30) — the "provisional from 14" claim in the README isn't reflected in the code path I read (`pulseAge` is nil below 30 valid days regardless of the 14-day constant) **[discrepancy: docs say "provisional from 14," code requires 30 for any non-nil value — worth re-checking if building against this]**.
- Sources cited in-repo: Mandsager 2018 (jamanetworkopen.com), Kaminsky/FRIEND 2015 (PMC), Uth 2004 (PubMed), Zhang 2016 (CMAJ) — all linked in SETUP.md.

### Journal correlations — `Core/Models/Journal.swift`
- Fixed list of 8 behavior factors (alcohol, late caffeine, late meal, stress, sick, screen before bed, exercised, sex) — no free text, "to keep correlations sound."
- Compares a factor checked on day D against **recovery on day D+1**.
- Requires **≥5 days with** and **≥5 days without** the factor (Whoop Monthly Performance Assessment threshold, cited explicitly).
- Monthly-view unlock at **≥28 total recovery-days**.
- **Welch's standard error** of the mean difference: `SE = sqrt(var_with/n_with + var_without/n_without)`; confidence = "solid" if `|delta| > 2×SE`, else "trend"/"emerging" (lines 178-197).

---

## 4. Architecture

- **Core/** is platform-neutral (no UIKit/SwiftUI imports — enforced by CONTRIBUTING.md as a rule, and structurally by shipping a separate `Core/Package.swift` so it can be unit-tested on macOS via `SelfTest/`).
  - `Models/`: `DayRecord` (one struct per calendar day — all metrics, sleep sessions, workouts, HR samples, sync timestamps), `MetricsStore` (JSON persistence), `Journal.swift` (behavior factors + correlation engine), `DayKey` (yyyy-MM-dd string helpers, local timezone), `Language.swift` (DE/EN localization extensions).
  - `Metrics/`: one engine per score (`RecoveryEngine`, `StrainEngine`, `SleepEngine`, `AgeEngine`, `HealthMonitor`), plus `Stats.swift` (baseline/z-score/logistic/percentile primitives + `TrendMath` for moving-average/weekly aggregation).
  - `API/`: `GoogleAuth` (OAuth/PKCE/Keychain), `HealthAPIClient` (HTTP + retry/throttle + typed fetchers), `JSONExtract` (tolerant decoding), `Keychain` (thin wrapper).
  - `Sync/SyncEngine.swift`: orchestrates the two-phase sync described above.
  - `Demo/DemoData.swift`: deterministic (`SeededRNG`, xorshift64, seed 42) generator of **120 days** of correlated synthetic data (training rhythm by weekday, recovery dips after hard days/alcohol, occasional bad nights, intraday HR for the most recent 28 days only). Used both for onboarding-without-a-Fitbit and as the SelfTest fixture — meaning the metric engines are validated end-to-end against this synthetic data, not against real Fitbit Air payloads.
- **App/** (iOS-only): `AppModel` (`@Observable` singleton holding store/auth/settings and all derived metric dictionaries, recomputed via `recomputeAll()` on every settings change or sync), `Auth/WebAuthenticator` (ASWebAuthenticationSession wrapper), `UI/*` (SwiftUI screens), `WidgetBridge` (writes a small snapshot to an App Group `UserDefaults` for the widget), `NotificationManager` (not fully read, but referenced: morning recovery push, bedtime reminder, token-expiry warning, health alerts), background sync via `BGAppRefreshTask` (`AppModel.swift:640-679`, best-effort scheduling, not punctual per docs).
- **Storage**: everything in `Application Support/Pulse/` as flat JSON — `days.json` (all `DayRecord`s, ISO-8601 dates, sorted keys, atomic write) and a **separate** `journal.json` (kept separate deliberately so a sync's full-store replace never clobbers journal entries). No SQLite/CoreData. No server, no analytics — repeated as a hard requirement in CONTRIBUTING.md.
- **PulseWidget/**: two widget sizes (recovery ring small; 3-ring daily overview medium), reads only the App-Group `UserDefaults` snapshot, not the full store.
- **SelfTest/**: standalone SwiftPM executable (`swift run pulse-selftest`), imports `Core` as `PulseCore`, ~700 lines of plain assertions (no XCTest) covering PKCE vector, DTO decoding fixtures (hand-written Google Health v4 JSON samples), every metric engine against the demo dataset, roundtrip persistence, and localization. Run in CI on every push (`.github/workflows/tests.yml`).

---

## 5. UI (screens, charts)

Charting: **Swift Charts** (`import Charts`, confirmed in `App/UI/ChartViews.swift` and 4 other UI files). No custom chart engine.

Chart components (`ChartViews.swift`):
- `HRDayChart` — intraday HR line, downsampled client-side to ≤240 points for rendering, with a drag/scrub selection (`chartXSelection`) showing bpm + time at the touched point.
- `RecoveryBarsChart` — daily recovery bars, colored per zone.
- `StrainLineChart` — filled area + line, 0–21 y-domain.
- `SleepTrendChart` — bars (slept hours) + dashed need line.
- `BaselineLineChart` — line + shaded ±1 SD band + dashed mean rule; supports a log-space baseline (used for HRV, since its baseline is stored in log space).
- `RecoveryStrainChart` — combo bar(recovery, 0-100)+line(strain, rescaled ×100/21 onto the same axis)+optional 7-day moving-average overlay line; switches to weekly bar units at the 90-day range.
- `Sparkline` — minimal axis-less line, used in Health Monitor cards.

Screens (`App/UI/*.swift`):
- **DashboardView** ("Today") — horizontal day-picker chips (21-day window, colored dot = recovery zone), then a reorderable/hideable list of module cards: overview triple-ring, Recovery ring+components, Pulse Age, Sleep ring, Strain arc-gauge with target marker + per-workout strain, Workouts, Steps, Health Monitor status list, Journal factor checklist. Sync progress banner, error banner, proactive health-alert banner.
- **RecoveryDetailView**, **SleepDetailView**, **StrainDetailView**, **AgeDetailView**, **OverviewDetailView** — drill-down per metric; SleepDetailView adds `StagesTimelineView` (a "flowing" hypnogram: one row per stage span with label+duration, not a classic scatter timeline) and `StageDistributionView`.
- **HealthMonitorView** — one card per metric (resting HR, HRV, respiration, SpO₂, skin temp) showing value, band status pill (in-range/above/below/calibrating/no-data), the ±1.65 SD normal range text, and a 30-day sparkline.
- **TrendsView** — 7/30/90-day segmented range picker; summary stat row; Recovery-vs-Strain combo chart (30-day view overlays 7-day moving averages on dimmed daily bars); Sleep-vs-need chart; HRV and RHR baseline-band charts; Journal correlations list with solid/trend confidence badges and a progress bar toward the 28-day monthly-assessment unlock.
- **DashboardCustomize** — drag-reorder + show/hide sheet for dashboard modules.
- **OnboardingView / ProfileSetupView** — client-ID entry, demo-mode entry point, age/sex/height/weight profile setup.
- **SettingsView / SyncLogView** — connection management, sync window sizes, notifications toggle, the per-metric sync log (German-only per CHANGELOG).
- Components (`Components.swift`): `TripleRingView` (overview), `JournalCard`, `ZoneBarsView` (strain zone minutes), hypnogram + stage distribution views.
- Theming: single `Theme.swift`, light/dark, DE/EN throughout via `PulseLanguage`/`Fmt`.

---

## 6. Gaps and weaknesses (explicit or inferred)

1. **Never run against a real Fitbit Air.** All engine validation (SelfTest) runs against hand-written JSON fixtures and the synthetic `DemoData` generator, not captured real API responses. Field names, granularity, and even whether some data types exist for this specific device are **[UNVERIFIED]** by this repo itself — that's the whole reason for the candidate-key/variant-fallback design.
2. **7-day token expiry** in Testing-mode Google Cloud projects is a real, unavoidable friction point for any hobbyist clone unless they complete Google's restricted-scope verification (author explicitly says not worth it for personal use).
3. **Sleep-derived metrics (HRV, respiration, SpO₂, temperature) require actually sleeping with the band on** — no data otherwise; this is a device/protocol constraint, not a Pulse bug, but it caps what a personal-use app can show for nap-only or non-wearing users.
4. **Pulse Age calibration threshold discrepancy**: README/SETUP say results appear "provisional from 14 days," but the `AgeEngine.compute()` code path I read only returns a non-nil `pulseAge` once `validDayCount ≥ 30` (`hasEnoughDays`) — the `minProvisionalDays = 14` constant is defined but not visibly used to unlock an earlier/provisional value in the compute path shown. Worth re-verifying against the latest commit before relying on the "provisional at 14" claim.
5. **RHR "+10bpm ≈ 2.5 years" conversion in AgeEngine is the author's own heuristic**, not a value taken directly from the cited Zhang 2016 hazard-ratio paper (the paper gives a mortality hazard ratio, not an age-year equivalence) — flagged in code as a "conservative heuristic."
6. **Strain-target formula (`0.2 × recovery`, capped 3–18.5)** is explicitly "transparent linear," calibrated by eye to match Whoop's *published* ranges — not a reverse-engineered Whoop formula.
7. **In-app sync log is German-only** (CHANGELOG "Known limitations") despite the rest of the UI being bilingual — a real, acknowledged inconsistency.
8. **Background sync timing is best-effort** (`BGAppRefreshTask`, iOS decides when it actually runs) — "not punctual," per SETUP.md troubleshooting.
9. **No App Store distribution** — sideload only; free Apple ID builds expire after 7 days.
10. **Roadmap items explicitly not yet built**: live intraday-HRV/HR "stress monitor," Apple Watch complication, webhook-based sync instead of polling, CSV/Health Connect export (README "Roadmap").
11. **Height/weight profile fields are collected but currently feed no score** (`AppModel.swift:85-91` comments confirm this directly).
12. No handling shown for **workouts/exercise data type's `civil_start_time`-only filter** being a documented one-off API quirk — a sign the v4 API's filtering semantics are inconsistent across data types and could break again if Google changes it (this is the exact class of risk the whole tolerant-decoding architecture exists to absorb, but it's still a fragility, not a solved problem).

---

## Files referenced (path:line for load-bearing claims)
- `Core/API/HealthAPIClient.swift` (56-140 variant fallback, 332-360 exercise/civil-time, 372-488 HTTP/throttle/retry)
- `Core/API/JSONExtract.swift` (56-104 candidate-key BFS)
- `Core/API/GoogleAuth.swift` (14-31 redirect scheme, 34-45 scopes, 156-169 auth URL, 183-260 token flows)
- `Core/API/Keychain.swift` (full file)
- `Core/Sync/SyncEngine.swift` (54-327 two-phase sync + per-metric fetch, 337-457 intraday HR + resting-HR fallback, 470-502 spike removal/downsampling)
- `Core/Metrics/RecoveryEngine.swift` (35-153 full scoring)
- `Core/Metrics/StrainEngine.swift` (16-18 Tanaka, 56-71 zones/target, 60-63 log mapping, 82-183 accumulation)
- `Core/Metrics/SleepEngine.swift` (17-29 config constants, 70-101 bedtime rec, 112-189 debt/consistency)
- `Core/Metrics/HealthMonitor.swift` (69-140 bands, 149-196 alert rules)
- `Core/Metrics/AgeEngine.swift` (19-114 norms/inversion, 212-364 compute pipeline)
- `Core/Metrics/Stats.swift` (full file)
- `Core/Models/Models.swift`, `Journal.swift`, `MetricsStore.swift`, `DayKey.swift`, `Language.swift` (full files)
- `Core/Demo/DemoData.swift` (full file)
- `App/AppModel.swift` (full file), `App/Auth/WebAuthenticator.swift` (full file), `App/WidgetBridge.swift` (full file)
- `App/UI/ChartViews.swift`, `DashboardView.swift`, `HealthMonitorView.swift`, `TrendsView.swift`, `SleepDetailView.swift` (partial)
- `SelfTest/Sources/pulse-selftest/main.swift` (full file — used to cross-validate every formula above)
- `README.md`, `SETUP.md`, `CHANGELOG.md`, `CONTRIBUTING.md` (full files)
