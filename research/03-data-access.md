# 03 — Getting data out of the Google Fitbit Air

Research date: 2026-09-28. Scope: data access only. Platform priority, per the user: **Android first**. The app is for personal use now and may go public later. iOS gets only a brief note.

Labels used below:
- **[V-official]**: I read it myself on an official Google page (developers.google.com, developer.android.com, support.google.com, store.google.com, blog.google).
- **[V-staff]**: stated by a Google staff member on an official Google forum, not in the docs.
- **[Community]**: a primary observation in a public GitHub issue, PR or README. It is real data, but a single source that Google hasn't confirmed.
- **[Press]**: tech press or third-party blogs.
- **[Inference]**: my conclusion from the sources above. It is not stated anywhere.

---

## 0. TL;DR (answers first)

1. **On Android, Health Connect is the best base path.** The Google Health app (package `com.fitbit.FitbitMobile`) officially writes these types to Health Connect:
   - heart rate, HRV, resting HR, respiratory rate and skin temperature
   - sleep sessions with stages
   - exercise, steps, distance and total calories
   - VO2 max

   It does **not** write SpO2 or active calories. No scores are written anywhere: readiness, sleep score, cardio load and AZM are all missing. Health Connect needs **no Google Cloud project, no OAuth verification and no CASA**. A public release needs only the Play Console Health apps declaration, a Data safety form, a privacy policy and a rationale activity. [V-official]
2. **Google does not document the granularity or latency of what the Google Health app writes to Health Connect.**
   - Community observation: HRV arrives as RMSSD samples about every 5 minutes (60–100 a day), respiratory rate daily, skin temperature nightly, and calories in 15-minute buckets. [Community]
   - Native heart-rate sample density in Health Connect is **unverified**. Test it on day 1 (section 9).
3. **The Google Health API (v4) is the richest source, but it is gated.**
   - It adds SpO2 (intraday and daily), daily HRV extras (deep-sleep RMSSD, entropy, non-REM HR), active zone minutes, respiratory rate per sleep stage, and a skin-temperature baseline. [V-official]
   - Almost all its scopes are **Restricted**. Unverified apps are capped at 100 users. Testing-mode refresh tokens expire after 7 days. A public app needs OAuth verification plus an annual third-party CASA assessment (likely; see 4.2) at 2–6 weeks and $500–$4,500. [V-official]
4. **Readiness, sleep score and cardio load are not exposed by any sanctioned path.** A WHOOP-style app must compute its own scores from HRV, RHR, sleep and HR. [V-official, by absence from the full REST reference]
5. **The legacy Fitbit Web API is operational until 2026-09-30, per Google's stated timeline (I did not call a legacy endpoint to test this)** [V-staff]. Do not build on it.
6. **Direct BLE is only good for live HR.**
   - The Air can broadcast live heart rate over the standard Bluetooth Heart Rate Profile when HR sharing is on, at a battery cost. [V-official]
   - The proprietary sync channel is AES-EAX-encrypted with a key held only on the tracker and Fitbit's backend. A reverse-engineering attempt on 2026-09-22 hit that wall. There is no OpenStrap equivalent, and Gadgetbridge support is not viable. [Community]

---

## 1. Fitbit Air hardware

| Item | Finding | Label | Source |
|---|---|---|---|
| Announced | May 7, 2026 (pre-order the same day) | V-official | https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/ |
| Shipping | Ships from May 26, 2026; the Special Edition is on shelves in the US on May 26 | V-official / Press | https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/ , https://www.dcrainmaker.com/2026/05/fitbit-air-whoop-competitor-everything-details.html |
| Price | From $99.99; Stephen Curry Special Edition $129.99 | V-official | https://store.google.com/product/google_fitbit_air_specs?hl=en-US , https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/ |
| Sensors | Optical heart rate monitor; 3-axis accelerometer and gyroscope; red and infrared sensors for SpO2; "Device temperature sensor (skin temperature variation available in the Google Health app)"; vibration motor | V-official | https://store.google.com/product/google_fitbit_air_specs?hl=en-US |
| ECG | **None.** No ECG appears in the store specs. The API's device-compatibility row for the Air omits `electrocardiogram`, while the Charge 6 row includes it. Press: "FDA-certified background Afib detection (but not manual ECG)" | V-official (absence) / Press | https://developers.google.com/health/data-types/device-compatibility , https://www.dcrainmaker.com/2026/05/fitbit-air-whoop-competitor-everything-details.html |
| GPS / barometer | None. The Air's API row has no `floors` or `altitude` | V-official (absence) / Press | https://developers.google.com/health/data-types/device-compatibility , https://www.dcrainmaker.com/2026/05/fitbit-air-whoop-competitor-everything-details.html |
| On-device memory | "Saves 7 days of detailed motion data, minute by minute"; "daily totals for the last 30 days"; "**Stores heart rate data at 2-second intervals**" | V-official | https://store.google.com/product/google_fitbit_air_specs?hl=en-US |
| Battery | Up to 7 days; 0–100% charge in 90 min; 5 min of charging gives 1 day. The SpO2 feature "requires more frequent charging" | V-official | https://store.google.com/product/google_fitbit_air_specs?hl=en-US |
| Radio / range | Bluetooth 5.0; syncs up to 30 ft; needs BLE, internet and location permission | V-official | https://store.google.com/product/google_fitbit_air_specs?hl=en-US |
| Phone requirements | Android 11+ or iOS 16.4+; Google Account and Google Health app required | V-official | https://store.google.com/product/google_fitbit_air_specs?hl=en-US |
| Water | 5 ATM (50 m) | V-official | https://store.google.com/product/google_fitbit_air_specs?hl=en-US |
| Subscription | 3 months of Google Health Premium included. "Feature availability varies and some require Google Health Premium membership." Premium costs $9.99/month or $99.99/year | V-official / Press | https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/ , https://store.google.com/product/google_fitbit_air_specs?hl=en-US , https://www.androidauthority.com/google-health-premium-price-inclusions-features-3664507/ |
| Advertised metrics | 24/7 heart rate, heart-rhythm monitoring with AFib alerts, SpO2, resting HR, HRV, sleep stages and duration, automatic workout detection. Reviews also list Daily Readiness (0–100, needs 7 nights), Sleep Score and Cardio Load | V-official / Press | https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/ , https://www.tomsguide.com/wellness/fitness-trackers/fitbit-air-review |
| Live HR broadcast | Supported: "Google Fitbit Air, Fitbit Charge 6, Pixel Watch 2, 3, 4, and 5", over the "Bluetooth Heart Rate Profile". "Sharing real-time heart rate ... impacts battery life" | V-official | https://support.google.com/googlehealth/answer/14236705 |
| Premium split per metric | Which metrics are free and which need Premium is **not verified** from an official Google page. Press says the base app includes activity, sleep and heart-rate tracking, and Premium adds Coach, detailed sleep insights and plans | Press | https://www.androidauthority.com/google-health-premium-price-inclusions-features-3664507/ |

**Air data types in the Google Health API** (official device-compatibility row, last updated 2026-09-26) [V-official, https://developers.google.com/health/data-types/device-compatibility]:

`active-minutes`, `active-zone-minutes`, `daily-heart-rate-variability`, `daily-oxygen-saturation`, `daily-respiratory-rate`, `daily-resting-heart-rate`, `daily-sleep-temperature-derivations`, `daily-vo2-max`, `distance`, `exercise`, `food-measurement-unit`, `heart-rate`, `heart-rate-variability`, `nutrition-log`, `oxygen-saturation`, `respiratory-rate`, `respiratory-rate-sleep-summary`, `run-vo2-max`, `sedentary-period`, `skin-temperature`, `sleep`, `steps`, `swim-lengths-data`, `total-calories`, `vo2-max`.

Not in the Air's row: `electrocardiogram`, `irregular-rhythm-notification` (even though AFib alerts are advertised), `floors`, `altitude`, `active-energy-burned` and the heart-rate-zone types.

---

## 2. Fitbit Web API status (as of 2026-09-28)

- **Operational until September 30, 2026, then fully decommissioned, per Google's stated timeline (not tested by me).** On 2026-06-10, a Google Health "Community Specialist" on Google's official community forum gave these milestones: "July 15, 2026: Legacy Fitbit Accounts Permanently Deleted", and "September 30, 2026: Fitbit Web API Fully Decommissioned and Disabled". They added that OAuth authorization and refresh-token calls keep working until then, with no intermediate cutoff. [V-staff] https://support.google.com/googlehealth/thread/439040688/clarification-on-fitbit-web-api-and-oauth-availability-until-september-2026-shutdown?hl=en
- The official docs give only the month:
  - dev.fitbit.com banner: "We will be deprecating the legacy Fitbit Web API in September 2026." [V-official] https://dev.fitbit.com/build/reference/web-api/
  - Google Health API About page: "In September 2026, the legacy Fitbit Web API will be turned down and will no longer sync data." [V-official] https://developers.google.com/health/about
- **Migration guidance** [V-official] https://developers.google.com/health/migration :
  - existing access and refresh tokens can't be transferred, so users must re-consent through Google OAuth
  - `users.getIdentity` maps `legacyUserId` to `healthUserId`
  - error 412 means the user has to initialize a Google Health profile
  - revoke legacy tokens after migrating
- **Were new Fitbit Web API registrations closed?** Only a third party says so: "new Fitbit developer registrations have already closed." [Press, unverified] https://openwearables.io/blog/fitbit-web-api-shutdown-2026-migration-guide
- **Was Fitbit Air data ever available through the legacy Web API?** I found no source either way. It doesn't matter now, with 2 days left.
- Correction to the Pulse lead: the Google Health API launch announcement is dated **March 24, 2026**, not May. May 26, 2026 added scopes and data types (ECG, IRN, blood glucose and others). [V-official] https://developers.google.com/health/release-notes

---

## 3. Google Health API (v4)

### 3.1 Basics
- Docs: https://developers.google.com/health. REST reference: https://developers.google.com/health/reference/rest. Service endpoint: `https://health.googleapis.com`, with paths like `/v4/users/me/dataTypes/{type}/dataPoints`. REST and gRPC are both supported. [V-official] https://developers.google.com/health/get-started , https://developers.google.com/health/data-types/vitals
- Supported devices: "All Fitbit devices and Google Pixel watches, current and previous." It also covers manual entries and third-party data, and has a reconciled stream. [V-official] https://developers.google.com/health/about
- There are 43 data types. Operations are `list`, `get`, `reconcile`, `rollUp`, `dailyRollUp`, plus create/update/batchDelete for writable types. [V-official] https://developers.google.com/health/data-types
- `ghealth` CLI (described as a community project, not Google-official, hosted in the Google-Health-API GitHub org): https://github.com/Google-Health-API/google-health-cli [Press] https://www.marktechpost.com/2026/07/02/the-google-health-api-got-a-cli-ghealth-is-an-open-source-tool-for-your-fitbit-air-data/

### 3.2 Metric by metric

| Metric | Data type(s) | Granularity / fields | Label | Source |
|---|---|---|---|---|
| Heart rate | `heart-rate` (Sample) | **API storage resolution is 1 second.** Fields: `beatsPerMinute`, `motionContext` (e.g. SEDENTARY/ACTIVE), `sensorLocation`. The **Air itself stores HR at 2-second intervals**. Third parties report about 5 s in practice. **Don't assume per-second data.** Rollups over heart-rate data are capped at 14 days per query | V-official (1 s, 2 s) / Press (5 s) | https://developers.google.com/health/data-types/vitals , https://store.google.com/product/google_fitbit_air_specs?hl=en-US , https://tryterra.co/blog/everything-you-need-to-know-about-google-health-new-api , Pulse SETUP.md (local clone) |
| HRV, intraday | `heart-rate-variability` (Sample) | `rootMeanSquareOfSuccessiveDifferencesMilliseconds` (range 1–200) plus optional `standardDeviationMilliseconds`. **RMSSD only; no RR intervals.** Sample spacing isn't documented | V-official | https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints |
| HRV, nightly | `daily-heart-rate-variability` (Daily) | `averageHeartRateVariabilityMilliseconds` (RMSSD), `nonRemHeartRateBeatsPerMinute`, `entropy` (Shannon entropy of beat intervals), `deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds` | V-official | same |
| Beat-to-beat data | Only inside `irregular-rhythm-notification` (`heartBeats[]` with bpm computed as 60000/rr). The Air's row does not list this type | V-official | same; https://developers.google.com/health/data-types/device-compatibility |
| Sleep | `sleep` (Session) | Stage segments with start and end times. STAGES type: AWAKE/LIGHT/DEEP/REM; CLASSIC type: AWAKE/RESTLESS/ASLEEP. Summary: minutes asleep, awake, to fall asleep, after wake-up, plus per-stage minutes and counts. **No sleep score field.** Page size is 25 sessions | V-official | same; https://developers.google.com/health/data-types |
| SpO2 | `oxygen-saturation` (intraday Sample) and `daily-oxygen-saturation` (Daily, which includes a 7–30-day standard deviation) | Percentage from 0 to 100 | V-official | https://developers.google.com/health/data-types/vitals |
| Skin temperature | `daily-sleep-temperature-derivations` | `nightlyTemperatureCelsius` (mean during sleep), `baselineTemperatureCelsius` (30-day median), `relativeNightlyStddev30dCelsius` | V-official | https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints |
| Respiratory rate | `daily-respiratory-rate`; `respiratory-rate-sleep-summary` | The sleep summary has deep, light, REM and full-sleep statistics | V-official | same |
| Docs inconsistency | `skin-temperature` and `respiratory-rate` appear in the Air's compatibility row, but the REST reference and the vitals page have **no schema** for them (0 matches in the scraped pages). Treat them as unconfirmed | V-official (inconsistency) | https://developers.google.com/health/data-types/device-compatibility |
| VO2 max / cardio fitness | `vo2-max`, `daily-vo2-max`, `run-vo2-max` | — | V-official | https://developers.google.com/health/data-types |
| Exercise | `exercise` (Session). The release notes mention `exportExerciseTcx` | Page size is 25 | V-official | https://developers.google.com/health/data-types , https://developers.google.com/health/release-notes |
| Steps, distance, total calories, active minutes, AZM | Interval types | 1-minute storage resolution. `total-calories` is rollup-only and needs a time filter | V-official | https://developers.google.com/health/data-types |
| Readiness, sleep score, cardio load, stress | **Not present** (no match anywhere in the full REST reference) | — | V-official (absence) | https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints |

### 3.3 Limits, backfill and latency
- **Rate limits** [V-official] https://developers.google.com/health/rate-limits :
  - 300 requests/min per user (5 QPS)
  - per project: 120,000/min and 86.4M/day
  - "Unverified applications: Max 250 QPS total (capped at 100 users @ 2.5 QPS per user)"
  - over the limit, the API returns HTTP 429
- **Paging and ranges** [V-official] https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/list , https://developers.google.com/health/data-types :
  - `list` returns 1,440 points by default, up to 10,000; sleep and exercise max out at 25
  - rollup and dailyRollup ranges are capped at 14 days for `heart-rate`, `total-calories`, `active-minutes` and `calories-in-heart-rate-zone`, and at 90 days for everything else
  - Google recommends a "hot" first load of 7–14 days, then background backfill
- **Historical backfill depth:** no documented horizon. The docs' own pagination example mentions requesting "all sleep data for the past 10 years", so history appears to be served, but no limit is stated. [V-official, no stated limit] https://developers.google.com/health/data-types
- **Data latency:** not documented. Webhooks give "real-time notifications" when data changes. [V-official] https://developers.google.com/health/webhooks
  - Community report with a Fitbit Air: `dailyRollUp` lagged 15–30 minutes behind the app UI. Summing `steps` data points was closer, and the remaining gap came from the band's own BLE sync to the phone. [Community] https://github.com/iFrodo7/fitbit-dashboard/issues/72
  - Device-to-phone sync happens "throughout the day", and also whenever the app is opened. [V-official] https://support.google.com/googlehealth/answer/14237221?hl=en

### 3.4 Scopes
All scopes use the prefix `https://www.googleapis.com/auth/googlehealth.` (example in https://developers.google.com/health/setup). [V-official] https://developers.google.com/health/scopes
- **Restricted:** `activity_and_fitness.readonly`, `health_metrics_and_measurements.readonly`, `sleep.readonly`, `nutrition.readonly`, `profile.readonly`, `settings.readonly`, and their `.writeonly` versions
- **Sensitive:** `ecg.readonly`, `irn.readonly`, `location.readonly`, `reproductive_health.writeonly`

A WHOOP-style app needs `activity_and_fitness.readonly`, `health_metrics_and_measurements.readonly` and `sleep.readonly`. **All three are Restricted.**

---

## 4. Google Cloud OAuth constraints

### 4.1 Verified facts
- **Testing mode means 7-day tokens** [V-official] https://support.google.com/cloud/answer/15549945?hl=en , https://developers.google.com/identity/protocols/oauth2 , https://developers.google.com/health/setup :
  - Testing is limited to 100 listed test users, and "Authorizations by a test user will expire seven days from the time of consent."
  - Refresh tokens expire too. The Google Health setup page says: "Testing Mode ... refresh tokens ... expire after 7 days."
- **Production mode tokens:** "Once your app is moved to 'In Production' status, refresh tokens generally don't expire unless they are revoked or remain unused for a prolonged period (typically six months)." [V-official] https://developers.google.com/health/setup
- **Unverified cap:** "newly created OAuth clients are in an unverified state with a cap of 100 users for both testing and production purposes." The cap applies over the project's lifetime and can't be reset. [V-official] https://developers.google.com/health/setup , https://support.google.com/cloud/answer/15549945?hl=en
- **Personal-use exemption:** "If the app is for your personal use (fewer than 100 users), you ... can continue using the app without going through verification (users will be allowed to click through 'unverified app' warning screens during sign-in)." [V-official] https://support.google.com/cloud/answer/13464323?hl=en
- **Google Health-specific verification** [V-official] https://developers.google.com/health/app-verification :
  - "Most scopes for the Google Health API are restricted, which means you must complete verification before your app is publicly available."
  - There are two parts: (1) OAuth app verification by Trust & Safety, and (2) an **annual CASA security assessment** by a third-party assessor.
  - CASA takes "2-3 weeks for tier-2 ... 4-6 weeks for tier-3" and costs "$500 to $4,500 USD". The result is a Letter of Validation.
  - HITRUST, SOC 2 or ISO 27001 certification can speed it up.
  - It's separate from Google Play review: an app can be listed on Play but still be capped at 100 users.
- **In-app disclosure is mandatory** for Health API data [V-official] https://developers.google.com/health/app-verification . It must be:
  - inside the app, in the normal usage flow
  - specific about which data is used and how
  - not only in a privacy policy
- **Brand verification requirements** [V-official] https://support.google.com/cloud/answer/13464321?hl=en :
  - a homepage on a verified domain you own
  - a privacy policy on the same domain, linked from both the homepage and the consent screen
  - domain ownership verified in Google Search Console
  - Google branding compliance
  - up-to-date project contacts
- **Restricted-scope requirements** [V-official] https://support.google.com/cloud/answer/13464321?hl=en :
  - an appropriate use case
  - a **YouTube demo video** showing the end-to-end flow, including the full OAuth consent screen in English with the exact scopes
  - Limited Use compliance: no ads, no sale, no human reading without consent
- **Timelines:**
  - brand verification "typically takes 2-3 business days"
  - restricted-scope verification "can potentially take several weeks"
  - Google's unverified-apps page says verification "might require several months"
  - the Health developer checklist says "several days"

  [V-official, inconsistent across pages] https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification , https://support.google.com/cloud/answer/7454865?hl=en , https://developers.google.com/health/developer-checklist
- **Re-verification:** a security assessment is needed "at least every 12 months". [V-official] https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
- **Health API User Data Policy:** Limited Use applies; no selling data or using it for ads, credit or insurance; users' deletion requests must be honored. [V-official] https://developers.google.com/health/policies/health-api-developer-user-data-policy

### 4.2 Open ambiguity (unresolved): is CASA needed for an app with no backend?
- Google's general restricted-scope guide says: "If you store or transmit restricted scope data on servers, then you need to complete a security assessment", and it links CASA to apps that access data "from or through a third-party server". [V-official] https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
- The Google Health API pages say "apps using restricted scopes must also complete an annual security assessment" and "Supporting more than 100 users ... requires completion of a third party security review", with **no on-device exemption**. [V-official] https://developers.google.com/health/app-verification , https://developers.google.com/health/setup
- Trust & Safety decides when CASA starts. **Don't plan on being exempt.**

### 4.3 Realistic paths
**(a) Personal only (you, plus up to 99 others):**
- *Option 1 (verified behaviour):* keep the app in Testing and add yourself as a test user. You re-authorize every 7 days. This is what Pulse does (SETUP.md says "refresh tokens expire after 7 days").
- *Option 2 [Inference; test before relying on it]:* set the publishing status to **In production** without submitting for verification. Per the docs:
  - you would see the "unverified app" warning once at sign-in
  - the 100-user lifetime cap still applies
  - refresh tokens should stop expiring after 7 days, because the setup page ties the 7-day expiry to Testing only
  - This contradicts Pulse's claim that publishing requires verification.
  - Self-test: publish, authorize, then call the token endpoint on day 8.

**(b) Public app using the Google Health API:**
- brand verification
- restricted-scope verification: demo video, in-app disclosure, scope justifications
- annual CASA: expect weeks of work and $500–$4,500 a year
- a homepage, a domain and a privacy policy

That's a heavy lift for a hobby app. **For a public Android build, use Health Connect instead (section 5).** Health Connect avoids the whole Google Cloud track.

---

## 5. On-device stores

### 5.1 Android: Health Connect (top priority)

**What Google Health writes to Health Connect.** This is the official table on the Google Health Help Center, scraped 2026-09-28 [V-official] https://support.google.com/googlehealth/answer/14506680?hl=en

| Category | Google Health **writes** to Health Connect | Notes |
|---|---|---|
| Fitness | Steps, Speed, Step cadence, VO2 max, Floors, Distance, Elevation gained, Exercise, Exercise route, Total calories burned | **Active calories burned are read only, not written** |
| Temperature | Body temperature | |
| Sleep | Sleep session, Sleep stages | |
| Vitals | Skin temperature, Blood glucose, **Heart rate, Heart rate variability, Respiratory rate, Resting heart rate** | **Oxygen saturation is read only, not written** |
| Body | Weight, Body fat % | |
| Nutrition | Hydration, Nutrition | |
| Cycle health | Periods, Flow, Intermenstrual bleeding | |
| Medical records | (full list) | |

- Requirements: Android 9+ and an adult Google Account. [V-official] same page
- **Not available through Health Connect:** SpO2, active calories, AZM, readiness, sleep score, cardio load, ECG. [V-official, by absence from the table]
- **Package / data origin:** the Google Health app is the renamed Fitbit app, and its Play listing is `com.fitbit.FitbitMobile`, titled "Google Health (Fitbit)". [V-official] https://play.google.com/store/apps/details?id=com.fitbit.FitbitMobile . Health Connect records show `dataOrigin = com.fitbit.FitbitMobile`. [Community] https://github.com/owen282000/life-dashboard-companion-app/issues/53 , https://github.com/FloorLamp/allos/issues/1102
- **Conflicting claim, resolved in favour of the official table:**
  - A GitHub PR dated 2026-09-19 says Google Health docs state it "does not write HeartRate, HRV, SpO2, RespiratoryRate or RestingHeartRate". [Community] https://github.com/doronin-as/HealthConnector/pull/30
  - That contradicts the official table scraped today; the PR probably read an older version.
  - Separate community logs show Fitbit-origin HRV, respiratory rate and HR records in Health Connect. [Community] https://github.com/owen282000/life-dashboard-companion-app/issues/53 , https://github.com/FloorLamp/allos/issues/4956
  - A report of SpO2 in Health Connect came from a Galaxy S25 Ultra, so Samsung Health may be the origin; don't read it as Google Health writing SpO2.

**Granularity (not documented by Google):**
| Record | Observed | Label | Source |
|---|---|---|---|
| HRV (`HeartRateVariabilityRmssdRecord`) | "60–100/day, 5-min spacing" (up to 2026-08-28, before the exporter's bucketing change). Another app saw 472 raw HRV records from `com.fitbit.FitbitMobile` in one scan. **RMSSD only; Health Connect has no RR-interval record.** It's not certain the Air produced all of this before Aug 29; afterwards the device showed as "Google Fitbit Air" | Community (secondhand) | https://github.com/FloorLamp/allos/issues/4956 , https://github.com/owen282000/life-dashboard-companion-app/issues/53 |
| Respiratory rate | Daily (47 rows, labelled "daily" in the report) | Community | https://github.com/FloorLamp/allos/issues/4956 |
| Skin temperature | Nightly, as a delta (`delta_celsius`) | Community | https://github.com/FloorLamp/allos/issues/4956 , https://github.com/FloorLamp/allos/issues/1100 |
| Total calories | 15-minute buckets, plus a **future-dated "projection" record that ends at local midnight** | Community | https://github.com/FloorLamp/allos/issues/1102 , https://github.com/mcnaveen/health-connect-webhook/issues/40 |
| **Heart rate (`HeartRateRecord`)** | **Unverified.** The "minute HR" in these reports comes from an exporter that buckets HR into 1-minute records. It says nothing about native sample density | Unverified | https://github.com/FloorLamp/allos/issues/1100 , https://github.com/FloorLamp/allos/issues/4956 |
| Sleep | Sessions with full stage data | Community | https://github.com/owen282000/life-dashboard-companion-app/issues/71 |

**Latency (not documented by Google):**
- The Google Health app shows "Synced just now" or "Synced at XX:XX", and has a manual Sync button. The band syncs to the phone "throughout the day" and whenever the app is opened. No write cadence is published. [V-official] https://support.google.com/googlehealth/answer/14506680?hl=en , https://support.google.com/googlehealth/answer/14237221?hl=en
- Data-integrity gotchas you must handle [Community]:
  - Sleep sessions get deleted and re-written. Sometimes the replacement doesn't arrive in the same window. https://github.com/owen282000/life-dashboard-companion-app/issues/71
  - After a timezone change, the same night is written twice, 6 hours apart; the later write is correct. https://github.com/FloorLamp/allos/issues/3628
  - Future-dated daily projection records can break naive "last sync" cursors. https://github.com/mcnaveen/health-connect-webhook/issues/40
  - When other apps also write the same metric (e.g. Garmin plus Fitbit calories), filter by `dataOrigin` to avoid double counting. https://github.com/FloorLamp/allos/issues/1102

**Health Connect API constraints for your app** [V-official]:
- By default an app can read only data from up to 30 days before it first got permission. Older data needs `PERMISSION_READ_HEALTH_DATA_HISTORY`. https://developer.android.com/health-and-fitness/health-connect/read-data
- Background reads need `READ_HEALTH_DATA_IN_BACKGROUND`. https://developer.android.com/health-and-fitness/health-connect/read-data
- There are fixed periodic and daily rate quotas; background limits are stricter than foreground ones. Use changelog tokens rather than repeated full reads. Google doesn't publish the numbers. https://developer.android.com/health-and-fitness/guides/health-connect/plan/rate-limiting
- The manifest needs an activity handling `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`, plus a `VIEW_PERMISSION_USAGE` activity alias for Android 14+, to show your privacy policy. On Android 14+, Health Connect is part of the OS. https://developer.android.com/health-and-fitness/health-connect/get-started

### 5.2 Google Play policy for apps that read Health Connect (public path)
- **Required steps** [V-official] https://developer.android.com/health-and-fitness/health-connect/publish :
  1. Review the User Data and Health Connect permission policies.
  2. Complete the Data safety section.
  3. Complete the **Health apps declaration form** (Play Console, App content). Pick your health features (e.g. "Activity and fitness", "Sleep management"), then justify each Health Connect data type.
  4. Post a privacy policy on the Play listing. It must be "the same privacy policy that is displayed to users when they click the privacy policy link in Health Connect".
- Approvals are allowlisted per package name, so new versions don't need a new request. Adding data types means re-filing. A public app that never declared access shows users a "can't access Health Connect" dialog. [V-official] same page
- **Approved use case that fits this app:** "Fitness, wellness and coaching". It explicitly includes "companion apps that sync with and display fitness metrics from wearables", "analyzing sleep health", and "post-activity recovery". [V-official] https://support.google.com/googleplay/android-developer/answer/12991134?hl=en
- **Heightened scrutiny:** "clinical vitals (for example, READ_BLOOD_PRESSURE, READ_SKIN_TEMPERATURE)". You must show a user-facing feature that needs skin temperature, such as trend-based illness or recovery signals. [V-official] same page
- Justifications must be specific; Google gives "Needed for app functionality" as an example of an incomplete one. `READ_HEALTH_DATA_IN_BACKGROUND` and `READ_HEALTH_DATA_HISTORY` are in scope too. [V-official] same page
- **Prohibited uses** that matter here [V-official] same page:
  - no ads, sale or broker transfers
  - no "headless apps"
  - "Do not use health and fitness data APIs with apps that sync data between incompatible devices or platforms". Check this before adding any web or iOS companion that mirrors Health Connect data.
- **Security:** "at minimum, data encryption both at rest and in transit". [V-official] same page
- **Personal sideloaded build:** the "can't access" enforcement is described for apps "published in the Play store and released to the public". So a debug or sideloaded personal build probably doesn't need the declaration. [Inference; confirm on device]
- A Google Cloud project, OAuth verification and CASA are **not** part of the Health Connect path. None of the Health Connect publishing docs mention them. [V-official, by absence]

### 5.3 iOS / HealthKit (brief; iOS is out of scope for now)
- Google Health for iOS v5.05 (2026-08-03) added writing to Apple Health. [Press] https://www.macrumors.com/2026/08/03/fitbit-apple-health-syncing/
- The official write list covers steps, VO2 max, floors, active calories, distance, exercise and routes, body temperature, sleep sessions and stages, HR, **SpO2**, respiratory rate, resting HR and blood glucose. It does **not** cover **HRV** or **skin temperature**. [V-official] https://support.google.com/fitbit/answer/17037331?hl=en
- Without HRV, HealthKit is a weak base for a WHOOP-style recovery score. On iOS, the Google Health API is the only full path.

---

## 6. Other routes

### 6.1 Live HR over standard BLE (sanctioned, narrow)
- The Air broadcasts over the Bluetooth Heart Rate Profile (service `0x180D`) once "share real-time heart rate" is enabled. This costs battery. [V-official] https://support.google.com/googlehealth/answer/14236705
- An open-source reader streams live bpm from an Air via `0x180D`. Its own docs hedge on RR intervals ("if the device includes RR"), so **RR intervals from the Air are unverified**. The HR service doesn't advertise around the clock. [Community] https://github.com/AyushSagar16/fitbit-air
- Another project saw an Air advertising `0x180D`. [Community] https://github.com/rajwalgautam/heart-rate-monitor/issues/2
- Use: live workout HR screens. It's not a source for history or sleep.

### 6.2 Proprietary BLE / Gadgetbridge / an "OpenStrap for Fitbit"
- **Not viable.** A 2026-09-22 reverse-engineering report on a **Fitbit Air** found [Community] https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/504 :
  - the sync "megadump" is encrypted with **AES-128-EAX**
  - the phone app only relays it to Fitbit's backend and "never decrypts this format itself"
  - the key lives only on the tracker and Fitbit's backend
- Gadgetbridge's Fitbit work-in-progress PR (Charge 6) has these limits [Community] https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/6273 :
  - pairing has to happen in the official app first
  - it needs a **rooted phone** to extract a DTLS key
  - it gets only "liveactivity" data: current HR, steps and so on
  - sleep, HRV and SpO2 "still depend on the opaque sync dump"
  - the author paused the work in August 2026
- I found no OpenStrap-equivalent project for the Air. This route also carries ToS and anti-circumvention risk.

### 6.3 Google Takeout (one-time backfill)
- Google Account users export through Google Takeout (Fitbit / Google Health category). Individual workouts export as TCX from the app. The official page describes one-time exports and mentions no scheduling. [V-official] https://support.google.com/googlehealth/answer/14236615?hl=en
- The file layout is per-day JSON. HR is "typically one value per 5 seconds during active periods", and there are nightly HRV, sleep-stage and SpO2 files. [Press; not verified for Air or 2026 exports] https://takeoutday.org/guides/fitbit-data-export

---

## 7. Recommendation

### 7.1 Android ranking
| Rank | Path | Data richness | Reliability | Setup friction | ToS risk |
|---|---|---|---|---|---|
| **1** | **Health Connect** (read `com.fitbit.FitbitMobile` records) | Medium-high: HR, HRV (RMSSD), RHR, respiratory rate, skin-temp delta, sleep stages, exercise, steps, total calories, VO2 max. **No SpO2 or AZM** | Medium: cadence undocumented, sleep gets re-written, gotchas listed in 5.1 | **Low.** No cloud project. A public release needs the Play Health declaration, Data safety form, privacy policy and rationale activity; skin temperature gets extra scrutiny | Low (sanctioned) |
| **2** | **Google Health API** (personal-only supplement) | Highest: adds SpO2 (intraday and daily), nightly HRV extras, AZM, respiratory rate per stage, temperature baseline, documented schemas | Good: documented, webhooks, rate limits known | Personal: medium (a Cloud project, then either 7-day re-auth or unverified production). Public: **high** (verification, demo video, annual CASA at $500–$4,500, domain and privacy policy) | Low |
| 3 | Live BLE HR Profile (`0x180D`) | Live bpm only (RR unverified) | Good while sharing is on | Low | Low (standard profile) |
| 4 | Google Takeout | Deep history, one-off | Manual | Low | Low |
| 5 | Proprietary BLE / Gadgetbridge | Would be everything, but encrypted | Not viable | Very high (root) | **High** |

**Suggested architecture [Inference]:**
1. Build the app on **Health Connect**. It's the only path that can ship publicly without Google Cloud verification.
2. Compute your own recovery, strain and sleep scores. No path exposes Google's scores.
3. For your personal build, optionally add the **Google Health API** behind a feature flag to fill in SpO2, AZM and the daily HRV extras.
4. Add live `0x180D` HR later for a workout screen.

### 7.2 iPhone ranking (brief)
1. Google Health API (the only full path, including HRV)
2. HealthKit (no HRV or skin temperature)
3. Live BLE HR
4. Takeout
5. Proprietary BLE (not viable)

---

## 8. Verified vs Unverified

### Verified (primary source read)
- Air price, sensors, lack of ECG, 2-second on-device HR storage, battery, Bluetooth 5.0, OS requirements, 3-month Premium trial, and HR broadcast support (Google Store, Google blog, Help Center).
- The Air's list of 25 API data types (device-compatibility page, updated 2026-09-26).
- Fitbit Web API: officially "September 2026". The exact date of **2026-09-30** comes from a Google Community Specialist [V-staff].
- Google Health API launch on 2026-03-24, data types, fields (RMSSD only, no RR), HR storage resolution of 1 s, rollup caps of 14/90 days, page sizes, rate limits including the unverified 250 QPS / 100-user figure, and scope classifications.
- Restricted scopes: 7-day tokens in Testing, non-expiring tokens in production, the 100-user unverified cap, the personal-use exemption, CASA cost and time, demo video and privacy policy requirements.
- The Google Health write list for Health Connect (no SpO2, no active calories) and for Apple Health (no HRV, no skin temperature).
- Health Connect's 30-day history default, history and background permissions, and rationale activity; Play Health apps declaration steps, approved use cases, heightened scrutiny for skin temperature, and prohibited uses.
- No readiness, sleep score or cardio load field in the API.
- The Google Health app package is `com.fitbit.FitbitMobile`.

### Community-observed (real but single-source)
- HRV in Health Connect about every 5 min (60–100/day); respiratory rate daily; skin temperature nightly; calories in 15-min buckets; future-dated projection records; sleep re-writes and timezone duplicates.
- `dailyRollUp` lagging 15–30 min behind the app with an Air.
- Air advertising `0x180D`; Air sync payload using AES-128-EAX with a server-held key (2026-09-22).

### Unverified / unknown
- **Native `HeartRateRecord` sample density** written by Google Health for the Air.
- Whether the Air's `0x180D` notifications include **RR intervals**.
- Actual HR spacing returned by the API (the 1 s storage, 2 s device and ~5 s third-party figures conflict).
- Whether an **unverified In-production** client really gets non-expiring refresh tokens for Health scopes (docs imply yes; untested).
- Whether a backend-less app is exempt from CASA for Google Health scopes (the docs conflict).
- The Health API's historical backfill horizon, and Health Connect write latency or cadence.
- Whether Google Health backfills history into Health Connect when first connected.
- Whether sideloaded personal builds need no Play declaration (inferred).
- The `skin-temperature` and `respiratory-rate` API types (listed for the Air, but no schema).
- The official free vs Premium split per metric.
- New Fitbit Web API registrations being closed (third-party claim), and whether Air data was ever in the legacy Web API.

---

## 9. Day-1 tests once the band arrives
1. **Health Connect HR density:** read `HeartRateRecord` with `dataOriginFilter = com.fitbit.FitbitMobile` for one hour. Count `samples[]` and compute the gaps between timestamps. Alternatively, inspect the records in the Health Connect Toolbox app.
2. **HRV cadence:** list one night of `HeartRateVariabilityRmssdRecord` and check the spacing (expected about 5 min).
3. **Health Connect latency:** walk 500 steps, then log timestamps for three events: the band syncing to the app, the app's Health Connect "Synced at" time, and the record appearing in your reader.
4. **History:** request `READ_HEALTH_DATA_HISTORY` and check how far back Fitbit-origin records go.
5. **OAuth (personal):** publish the Cloud project to In production without verification, authorize, and confirm the refresh token still works on day 8.
6. **Live BLE:** enable HR sharing, subscribe to `0x2A37`, and check whether the RR-interval flag bit is set.

---

## Sources (all accessed 2026-09-28)
- https://store.google.com/product/google_fitbit_air_specs?hl=en-US
- https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/
- https://support.google.com/googlehealth/answer/14236705
- https://support.google.com/googlehealth/answer/14506680?hl=en
- https://support.google.com/googlehealth/answer/14237221?hl=en
- https://support.google.com/googlehealth/answer/14236615?hl=en
- https://support.google.com/fitbit/answer/17037331?hl=en
- https://support.google.com/googlehealth/thread/439040688/clarification-on-fitbit-web-api-and-oauth-availability-until-september-2026-shutdown?hl=en
- https://dev.fitbit.com/build/reference/web-api/
- https://developers.google.com/health/about
- https://developers.google.com/health/get-started
- https://developers.google.com/health/setup
- https://developers.google.com/health/scopes
- https://developers.google.com/health/app-verification
- https://developers.google.com/health/developer-checklist
- https://developers.google.com/health/rate-limits
- https://developers.google.com/health/data-types
- https://developers.google.com/health/data-types/device-compatibility
- https://developers.google.com/health/data-types/vitals
- https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints
- https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/list
- https://developers.google.com/health/webhooks
- https://developers.google.com/health/migration
- https://developers.google.com/health/release-notes
- https://developers.google.com/health/policies/health-api-developer-user-data-policy
- https://developers.google.com/identity/protocols/oauth2
- https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
- https://support.google.com/cloud/answer/15549945?hl=en
- https://support.google.com/cloud/answer/13464323?hl=en
- https://support.google.com/cloud/answer/7454865?hl=en
- https://support.google.com/cloud/answer/13464321?hl=en
- https://developer.android.com/health-and-fitness/health-connect/publish
- https://developer.android.com/health-and-fitness/health-connect/get-started
- https://developer.android.com/health-and-fitness/health-connect/read-data
- https://developer.android.com/health-and-fitness/guides/health-connect/plan/rate-limiting
- https://support.google.com/googleplay/android-developer/answer/12991134?hl=en
- https://play.google.com/store/apps/details?id=com.fitbit.FitbitMobile
- https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/504
- https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/6273
- https://github.com/AyushSagar16/fitbit-air
- https://github.com/rajwalgautam/heart-rate-monitor/issues/2
- https://github.com/FloorLamp/allos/issues/4956
- https://github.com/FloorLamp/allos/issues/1100
- https://github.com/FloorLamp/allos/issues/1102
- https://github.com/FloorLamp/allos/issues/3628
- https://github.com/owen282000/life-dashboard-companion-app/issues/53
- https://github.com/owen282000/life-dashboard-companion-app/issues/71
- https://github.com/mcnaveen/health-connect-webhook/issues/40
- https://github.com/doronin-as/HealthConnector/pull/30
- https://github.com/iFrodo7/fitbit-dashboard/issues/72
- https://www.dcrainmaker.com/2026/05/fitbit-air-whoop-competitor-everything-details.html
- https://www.androidauthority.com/google-health-premium-price-inclusions-features-3664507/
- https://www.tomsguide.com/wellness/fitness-trackers/fitbit-air-review
- https://www.macrumors.com/2026/08/03/fitbit-apple-health-syncing/
- https://tryterra.co/blog/everything-you-need-to-know-about-google-health-new-api
- https://openwearables.io/blog/fitbit-web-api-shutdown-2026-migration-guide
- https://takeoutday.org/guides/fitbit-data-export
- https://www.marktechpost.com/2026/07/02/the-google-health-api-got-a-cli-ghealth-is-an-open-source-tool-for-your-fitbit-air-data/
- Pulse SETUP.md (local clone of Luraxx/pulse)
