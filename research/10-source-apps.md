# 10: Source apps. What each wearable app shares with Health Connect, and what Airlog can compute from it

**Date:** 2026-09-30 · **Status:** research only; no app code changed · **Builds on:** [`09-hrv-workarounds.md`](09-hrv-workarounds.md), [`09b-hrv-critique.md`](09b-hrv-critique.md) (its ladder and veto criteria (a)–(f) are reused here), `PRODUCT_PLAN.md` §7 · **Code read:** `app/lib/domain/engine/source_apps.dart`, `notes.dart`, `data/resolver/resolver.dart`, `data/db/raw_rows.dart`, `android/app/src/main/AndroidManifest.xml`

**Evidence tags** (everything was accessed on 2026-09-30):
- **[V-official]**: I read the vendor's own help page, developer doc or licence during this pass.
- **[V-primary]**: a primary artefact that isn't vendor prose. That means an APK's declared Health Connect permissions (Exodus Privacy static report, `reports.exodus-privacy.eu.org/en/reports/<pkg>/latest/`, with the build version and report date), a Google Play listing (title and installs, `play.google.com/store/apps/details?id=<pkg>`), or vendor SDK source on GitHub.
- **[Community]**: a forum post, third-party help centre or press article.
- **[Unverified]**: not confirmed. Never stated as fact.

**Rule carried over from 09b §7.** A declared `WRITE_*` permission shows only that the app *can* write that type. A missing permission is a hard "no" for that build, because Android enforces it. Nothing in Airlog's code may branch on this table; it exists for research, copy and fixtures.

---

## 1. Bottom line

1. **Full Recovery set officially:** only Google Health (Fitbit/Pixel). Oura: HRV, no RHR or respiratory rate. COROS, Zepp/Amazfit, Withings and OHealth only *declare* HRV + RHR + respiratory rate.
2. **HR + sleep only:** Samsung Health (1B+), Mi Fitness, FitCloudPro. Recovery then hinges on the Sleeping-HR gate (Samsung: *Measure continuously*).
3. **WHOOP:** RHR and respiratory rate only on Peak or Life memberships; never HRV.
4. **Polar Flow:** RHR and VO₂max are "physical settings", and HR covers workouts only. Airlog may score that constant as a measured RHR (§5 R4 guard).
5. **No HC writes:** Suunto, Huawei Health, Zepp Life, Da Fit, NoiseFit, boAt, realme, Wearfit. The Health Sync relay bridges some of them, including Garmin HRV.
6. **No-server SDKs:** only the Polar BLE SDK (nightly RMSSD) and Samsung's Data SDK (dev mode, skin temp) pass, both as personal-build flags. Every vendor cloud API is rejected (§4).
7. **Do:** add packages, a copy-only setup table, an observed-data "shares / computes" card, and the RHR/VO₂max profile-value guard.

---

## 2. Capability matrix

### 2.1 What each app writes to Health Connect

**Legend:**
- **W**: the vendor's help page lists it as written **and** the APK declares it.
- **D**: declared in the APK only; the vendor page doesn't list it, or has no list.
- **✗**: not declared in that build.
- **⚠P**: written, but the vendor says it's a profile ("physical settings") value, not a measurement.
- **n/s**: the vendor says it is not synced.

Sleep "+st" means the vendor mentions sleep stages.

| App · package · Play title · installs | HR | HRV | RHR | Resp | Skin temp | SpO₂ | Sleep | Exercise | Steps | VO₂max | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Google Health (Fitbit, Pixel Watch)** · `com.fitbit.FitbitMobile` · "Google Health (Fitbit)" · 100M+ | W | W | W | W | W | **D** (the help table lists SpO₂ as *read only*) | W +st | W | W | W | Help table "Data types that Google Health can write" [V-official] support.google.com/googlehealth/answer/14506680 · APK v5.06.1, report 2026-08-23 [V-primary] |
| **Samsung Health** (Galaxy Watch, Ring, Fit) · `com.sec.android.app.shealth` · "Samsung Health" · 1B+ | W | ✗ | ✗ | ✗ | ✗ | W | W +st | W | W (one daily total, per Health Sync [Community]) | W (per exercise) | 18-row sync table (sync scope, "can be changed depending on the Samsung Health version") [V-official] developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect · APK v7.00.6.011, 2026-09-17 [V-primary] · healthsync.app/about [Community] |
| **Garmin Connect** · `com.garmin.android.apps.connectmobile` · "Garmin Connect™" · 50M+ | W (activity + all-day) | ✗ | **D** (not in Garmin's list) | ✗ | ✗ | ✗ | W (stages) | W | W | ✗ | "Sharing Your Garmin Connect Data With Health Connect": one-way, Android 14+ [V-official] support.garmin.com/en-US/?faq=JToBEy0jfe6pIygark2Ui5 · APK v5.29, 2026-09-25 [V-primary] |
| **Oura** · `com.ouraring.oura` · "Oura" · 1M+ | W | W | ✗ | ✗ | ✗ | ✗ | W (stages not stated) | W | W | ✗ (read only) | Oura HC article, updated 2026-08-19 [V-official] support.ouraring.com/hc/en-us/articles/10786105824531 · APK v7.22.0, 2026-08-11 [V-primary] |
| **WHOOP** · `com.whoop.android` · "WHOOP" · 1M+ | **D** (not in WHOOP's list) | ✗ | W, **Peak/Life only** | W, **Peak/Life only** | ✗ | W | W | W | W | n/s | "Health Connect Integration For Android", published 2025-10-06 [V-official] support.whoop.com/s/article/Google-Health-Integration-For-Android · APK v5.465.0, 2026-08-19 [V-primary] |
| **Polar Flow** · `fi.polar.polarflow` · "Polar Flow" · 5M+ | W, **workouts only** | ✗ | **⚠P** "physical settings" | ✗ | ✗ | W | W +st | W | W | **⚠P** "physical settings" | [V-official] support.polar.com/us-en/flow-app-health-connect · APK v7.36.2, 2026-07-21 [V-primary] |
| **COROS** · `com.yf.smart.coros.dist` · "COROS" · 1M+ | D | D | D | D | ✗ | D | D | D | D | ✗ | COROS names HC as supported but lists no types [V-official] support.coros.com/hc/en-us/articles/360040256531 · APK v4.6.8, 2026-06-30 [V-primary] |
| **Zepp (the Amazfit app)** · `com.huami.watch.hmwatchmanager` · "Zepp" · 10M+ | D | D | D | D | ✗ | D | D | D | D | D | APK v10.8.7-play, 2026-09-29 [V-primary]. Play search "Amazfit" returns this package, so Amazfit = Zepp [V-primary]. No official type list found |
| **Zepp Life** (older Mi Bands) · `com.xiaomi.hm.health` · "Zepp Life" · 100M+ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | APK v6.15.0, 2025-10-30: **stale report** [V-primary] |
| **Mi Fitness (Xiaomi)** · `com.xiaomi.wearable` · "Mi Fitness (Xiaomi Wear)" · 50M+ | D | ✗ | ✗ | ✗ | ✗ | D | D | D | D | ✗ | APK v3.59.1i, 2026-09-24 [V-primary] |
| **Huawei Health** · `com.huawei.health` | — | — | — | — | — | — | — | — | — | — | Not on Google Play (US and IN listings return "Not Found") [V-primary]; installed from Huawei's site [V-official] consumer.huawei.com/en/support/content/en-us15981770/. "Huawei Health does not offer native support for Google's Health Connect" [Community] steppi.crisp.help. Exodus report is from 2020: stale |
| **Withings** · `com.withings.wiscale2` · "Withings" · 5M+ | D | D | D | D | ✗ (body temp only) | D | D | D | D | D | Withings documents the export steps but lists no types [V-official] support.withings.com/hc/articles/27322856325905 · APK v26.36.0, 2026-09-09 [V-primary] |
| **Ultrahuman** · `com.ultrahuman.android` · "Ultrahuman" · 100K+ | D | D | ✗ | ✗ | ✗ (body temp only) | ✗ | D | D | D | D | APK v2.74.4.0, 2025-12-30: **stale** [V-primary]. No official list found |
| **Google Fit** · `com.google.android.apps.fitness` · "Google Fit: Activity Tracking" · 100M+ | D | ✗ | D | D | ✗ | D | D | D | D | ✗ | APK 2025.10.23, 2025-12-04: stale [V-primary]. "Google Fit APIs will be supported until the end of 2026" [V-official] developer.android.com/health-and-fitness/health-connect/migration/fit. Fit users to be migrated into Google Health "later this year" [Community/press] 9to5google.com 2026-05-07 |
| **Suunto** · `com.stt.android.suunto` · "Suunto" · 1M+ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | APK v6.13.7, 2026-09-17: **no `android.permission.health.*` at all** [V-primary] |
| **Wahoo** · `com.wahoofitness.fitness` · "Wahoo: Ride, Run, Train" · 1M+ | D (workouts) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | D | D | ✗ | APK v7.1.0, 2026-09-23 [V-primary]. ELEMNT (`com.wahoofitness.boltcompanion`, 500K+): no HC writes |
| **Health Sync** (relay) · `nl.appyhapps.healthsync` · "Health Sync" · 1M+ | D | D | D | D | D | D | D | D | D | D | APK v7.9.1.6, 2026-08-15 [V-primary]. Reads Garmin, Huawei Health, Polar Flow, Samsung Health, Suunto, COROS, Oura, Withings and more; vitals include "HRV … and temperature" [V-official] healthsync.app/about. Garmin HRV relay to HC confirmed by the developer [Community] reddit.com/r/Garmin/comments/1luvd2j; it runs through Health Sync's own cloud ("problems on our cloud server involved with the Garmin sync") [V-official] healthsync.app/status |

**HR density: unverified for every app.** "W" or "D" under HR means HR records exist, not that there are enough of them for the Sleeping-HR gate (≥ 1 sample per 5 min). The only documented density behaviour is Samsung's, which depends on a setting: "Measure continuously" vs "Every 10 mins while still" (09b). Polar's HR is workouts only [V-official]. Everything else is §6 Q1.

**Other apps with ≥10M installs that write Recovery-relevant types** (APK declarations only [V-primary]):

| App · package · installs | HR | HRV | RHR | Resp | SpO₂ | Sleep | Other | Report |
|---|---|---|---|---|---|---|---|---|
| Honor Health · `com.hihonor.health` · 100M+ | D | ✗ | D | ✗ | D | D | VO₂max, body temp, exercise | v17.20.0.303, 2026-03-29 |
| Fastrack Smart World · `com.titan.fastrack.reflex` · 10M+ | D | D | ✗ | D | D | D | body temp, exercise | v6.25.0.16840, 2026-06-25 |
| FitCloudPro (budget watches) · `com.topstep.fitcloudpro` · 10M+ | D | ✗ | ✗ | ✗ | D | D | body temp; **no exercise** | v2.6.3, 2026-07-07 |
| Sleep as Android · `com.urbandroid.sleep` · 10M+ | D | ✗ | D | ✗ | D | D | whether its RHR is measured is [Unverified] | 20260916, 2026-09-26 |
| OHealth (OPPO/OnePlus watches) · `com.heytap.health.international` · **1M+** (below the bar, but a full declarer) | D | D | D | D | D | D | VO₂max | v4.61.7, 2026-08-16 |
| Strava · `com.strava` · 100M+ / adidas Running · `com.runtastic.android` · 50M+ | adidas: D | ✗ | ✗ | ✗ | ✗ | ✗ | exercise only (context and Strain) | 2026-09-16 / 2026-09-12 |

**≥10M-install wearable apps with no HC writes** in their latest report [V-primary]:
- Da Fit (`com.crrepa.band.dafit`, 100M+, 2026-09-13)
- NoiseFit (`com.noisefit`, 50M+, 2026-02-01)
- boAt Crest (`com.coveiot.android.boat`, 10M+, 2025-12-24)
- realme Link (`com.realme.link`, 10M+, 2026-07-15)
- Wearfit Pro (`com.wakeup.howear`, 10M+, 2026-01-23)
- Sleep Cycle (`com.northcube.sleepcycle`, 10M+; writes sleep only)
- the Galaxy Wearable (1B+) and Google Pixel Watch (10M+) companion apps, whose data reaches HC through Samsung Health and Google Health instead.

**What changed since 09 §1:**
- WHOOP gates RHR and respiratory rate by membership, and doesn't list HR, though its APK declares HR.
- Polar's RHR *and* VO₂max are profile values, and its HR covers workouts only.
- Google Health's own table says SpO₂ is read-only, although the APK declares the write.
- Suunto and Huawei have no HC path.
- Samsung is confirmed again on a newer build (7.00.6.011): still no HRV, RHR, respiratory rate or skin temp.

### 2.2 What Airlog can compute per app (Q4)

This uses the 09b ladder:
- **Nightly HRV:** N2 samples or N3 single records from the HC origin.
- **RHR:** the origin's own `RestingHeartRateRecord`.
- **Sleeping HR (4 h mean):** used only when the origin never writes RHR, and only when ≥ 80 % of the 5-min bins have HR.
- **Respiratory rate** and **sleep** as usual.
- **Floor:** "without HRV"; no Recovery when HRV, RHR and sleeping HR are all absent.

Health Monitor vitals are RHR, HRV, respiratory rate and skin-temp delta (PRODUCT_PLAN §3.2).

| App | Recovery outcome | Recovery inputs | Health Monitor vitals | Hinges on |
|---|---|---|---|---|
| Google Health (Fitbit/Pixel) | **Full** | HRV, RHR, resp, sleep | RHR, HRV, resp, skin temp | Phase 0: Air-origin density |
| Oura | **With HRV** | HRV, sleep, sleeping HR (no RHR) | HRV | Oura's HR density at night [Unverified] |
| COROS · Zepp/Amazfit · Withings · OHealth | **Full, if the declared writes are real** | HRV, RHR, resp, sleep | RHR, HRV, resp (no skin temp; Withings writes body temp, which is a different type) | Observed writes (§6) |
| Ultrahuman · Fastrack Smart World | **With HRV** | HRV, sleep, sleeping HR; Fastrack also resp | HRV (+ resp for Fastrack) | Stale or declared-only |
| WHOOP Peak/Life | **Without HRV** | RHR, resp, sleep | RHR, resp | Membership |
| WHOOP One | **Sleeping-HR stand-in or none** | sleep, plus sleeping HR only if WHOOP's HR is written densely | none | HR write is declared, not listed |
| Garmin Connect | **Without HRV** if RHR is written; otherwise sleeping-HR stand-in or none | RHR (declared) or sleeping HR, sleep | RHR (if written) | Whether RHR arrives; all-day HR density |
| Samsung Health | **Sleeping-HR stand-in or none** (09b §4: 50 % sleep + 50 % sleeping HR, "without HRV") | sleep, sleeping HR | none (SpO₂ exists but isn't a Health Monitor input) | "Measure continuously"; watch-to-phone sync delay |
| Mi Fitness · FitCloudPro | **Sleeping-HR stand-in or none** | sleep, sleeping HR | none | HR density |
| Honor Health | **Without HRV** | RHR, sleep | RHR | Declared only |
| **Polar Flow** | **None, once R4 lands** (no HRV; RHR is a profile value; no night HR, so no sleeping HR). **Today, depending on how often Polar writes the value** (§6 Q3): <ul><li>If Polar writes it **daily**, the resolver takes the day's RHR as-is (`resolver.dart:430-432`), giving a false "without HRV" built on a constant.</li><li>If Polar writes it **once**, that single record marks Polar as an RHR sharer (`day_engine.dart` `_notSharedBy`: `if (from == origin) return null`) for as long as it stays in history.</li></ul> | sleep only | none | R4 guard; §4 Polar SDK flag |
| Google Fit | Without HRV if a device feeds Fit (RHR, resp declared) | RHR, resp, sleep | RHR, resp | Being wound down |
| Wahoo · Strava · adidas | **None** (workouts only) | — | — | — |
| Suunto · Huawei Health · Zepp Life · Da Fit · NoiseFit · boAt · realme · Wearfit | **None** directly | — | — | Only through a relay |
| Health Sync (relay) | Whatever the relayed source carries (e.g. Garmin HRV [Community]) | per source | per source | Origin is the relay; device from metadata |

---

## 3. Setup paths (copy-ready)

**Generic, works for every app** [V-official] support.google.com/android/answer/12201227:
- **Android 14+:** Settings → Security and privacy → Privacy controls → Health Connect. OEM menus vary.
- **Android 13 and lower:** install Health Connect from Play, then Settings → Apps → All apps → Health Connect → Open.
- Google's own tip: "some apps may require you to begin in the connected app itself". So the sequence is: turn sharing on in the app, then check its write permissions in Health Connect.

| App | In-app path | Gotchas |
|---|---|---|
| Google Health | Connections (top left) → Partner apps → Sync your favorite health apps → Set up → Accept → Allow all → allow history and background access [V-official 14506680] | New data types need re-granting (a "NEW" tag on the Health Connect tile) [V-official] |
| Samsung Health | ⋮ → Settings → Health Connect → Get started → pick data → Allow. Also Settings → Sync with Samsung Cloud → On [V-official, Samsung blog]. **On the watch:** Samsung Health → Settings → Measurement → Heart rate → **Measure continuously** [V-official] samsung.com/us/support/answer/ANS10006858 | "continuous heart rate data from the Galaxy Watch is not sent to the Samsung Health application on the smartphone immediately"; opening or pulling to refresh Samsung Health's home screen triggers a sync. It shares "new or updated data", with no backfill stated [V-official blog]. The alternative setting "Every 10 mins while still" fails the 5-min gate (09b) |
| Garmin Connect | Garmin's page points to Android's "Get started with Health Connect", so grant from the Health Connect side. The in-app entry point varies by version [Unverified] | Android 14+ only; one-way; "syncs data to Health Connect after each successful device sync" [V-official] |
| Oura | Menu (top left) → Settings → Data Sharing → Health Connect → toggle types [V-official] | Imports may fail "if apps weren't opened before midnight", with Background App Refresh off, or in Low Power Mode. Open both apps daily [V-official] |
| WHOOP | More → Account & Settings → Integrations → Health Connect → Set Up → grant [V-official] | RHR and respiratory rate need **WHOOP Peak or Life**. Reinstalling WHOOP removes the permissions [V-official] |
| Polar Flow | General settings → Health Connect on → select data → Allow [V-official] | "From now on, Health Connect receives your new Flow data" (forward only). HR is workouts only; RHR and VO₂max are profile values [V-official] |
| Withings | Profile → Settings (gear) → Export health data to Health Connect → Next → toggle types → Allow → Done [V-official] support.withings.com/hc/articles/27322856325905 | Types depend on the device (a scale writes no HRV) [Unverified] |
| COROS | Profile → Settings → 3rd Party Apps → Health Connect [Unverified; from a search summary, not read on a COROS page] | — |
| Zepp / Amazfit | Profile → (third-party accounts) → Health Connect → Sync with Health Connect → Allow all [Community] yumuuv.com/help/faq/connecting-zepp-amazfit-to-yumuuv (steps 4–6; steps 1–3 unseen) | — |
| Mi Fitness | Profile → Third-party data → Health Connect [Community; the same menu that held Google Fit] | — |
| Ultrahuman · Honor Health · Fastrack · OHealth · FitCloudPro | [Unverified]; use the generic path | — |
| Suunto · Huawei Health · Zepp Life · NoiseFit · boAt · Da Fit | No Health Connect export. Only a relay app bridges them | Health Sync: paid, and routes through its own cloud for Garmin [V-official healthsync.app] |

---

## 4. Direct SDK/API options (no server, no embedded secret)

The veto criteria are 09b's:
- (a) unverified where it matters
- (b) invented
- (c) untestable here
- (d) server or embedded secret
- (e) against the terms or requires business partnership
- (f) low value for its complexity

| Option | Auth and approval | Adds over HC | Verdict |
|---|---|---|---|
| **Polar BLE SDK** (on-device BLE, GitHub `polarofficial/polar-ble-sdk`) | **No account, no server.** The licence allows use "for your private as well as for commercial use". It forbids using Polar marks or implying association (§4.4) [V-official, licence] | Polar 360/**Loop**, Vantage V3/M3, Grit X2 (Pro) and Ignite 3 export "Nightly recharge data per night", "24/7 HR samples as 5 min averages", "24/7 PPi samples" and "24/7 Skin temperature data with 5 min interval" [V-official] `documentation/products/Polar360.md`. `PolarNightlyRechargeData` carries `meanNightlyRecoveryRMSSD` ("after 0.5h from sleep start to 4.5h after"), `meanNightlyRecoveryRRI` and `meanNightlyRecoveryRespirationInterval`, plus Polar's own `ansStatus`/`recoveryIndicator` scores, which Airlog wouldn't show [V-primary, SDK source]. That's the same 4-h window as 09b's Sleeping HR | **Keep behind a flag, personal build only, and spike it only with a Polar device in hand**, under (a)(c). Risks [V-official]: <ul><li>Polar 360 accepts "1 peer device only" and refuses pairing overwrite.</li><li>For watches, "Make sure FlowApp is completely shutdown", then re-pair from the SDK app.</li><li>The SDK "does not currently support reacting to" Flow's auto-sync.</li><li>The delete APIs would remove data Flow hasn't synced yet.</li></ul>Coexistence with Polar Flow is **unverified**. Never call `doFirstTimeUse`, `doFactoryReset` or any delete API. This is the only no-server nightly-HRV path for Polar users, whose HC data supports no Recovery |
| **Samsung Health Data SDK** v1.1.0 (2026-03-12) | Read works in **Samsung Health developer mode** with no approval (Settings → About Samsung Health → tap version ×10 → "Developer Mode for Data Read"). But: "ONLY intended for testing or debugging your app. It is NOT for app users". Release needs a partner request with package + SHA-256, "Otherwise, the app … works only with the developer mode turned on". Writing needs an access code after approval. "The SDK does not support emulators" [V-official] developer.samsung.com/health/data/guide/developer-mode.html, …/process.html, …/overview.html. The partner form needs a Samsung sign-in, so eligibility for an individual is [Unverified] | **SkinTemperature** series (°C with min/max; "continuously measured while the user sleeps"). Sleep with Samsung's sleep score (not shown). HR series (same as HC). Also BloodOxygen, EnergyScore (Samsung's score; not shown). **No HRV and no RHR type** | **Defer; personal-build flag at most.** Gain: one Health Monitor vital (skin temp) for Samsung users. It can't be tested here (c), and public release needs a partnership (e). Revisit only if the user owns a Galaxy Watch or Ring |
| Samsung Health Sensor SDK (watch) | Partnership key needed even for developer mode | IBI | Reject (09 R8) |
| **Garmin Health API / Connect Developer Program** | "available for enterprise use … only for business use"; OAuth 2.0; cloud-to-cloud; "Beat-To-Beat Interval \* Commercial use requires a license fee" [V-official] developer.garmin.com/gc-developer-program/program-faq/, …/health-api/ | HRV, stress, respiration, Pulse Ox | **Reject** (d)(e) |
| Garmin Health SDKs (Standard/Companion) | "Available to Garmin Health enterprise partners", with evaluation licences [V-official] developer.garmin.com/health-sdk/overview/ | Real-time beat-to-beat intervals, all-day metrics | **Reject** (e) |
| Garmin Connect IQ + Mobile SDK | Public SDK on Maven; phone↔watch traffic goes "through a Garmin Connect Mobile service" [V-official]. `heartBeatIntervals` is available only inside a `registerSensorDataListener` callback. `SensorHistory` offers HR, stress, Body Battery, SpO₂ and temperature history, with **no HRV** [V-official API docs] | A live RR check from a Garmin watch, not nightly HRV | **Reject for v1** (f): it needs a separate Monkey C watch app. At most, a later input for the flagged `hrvMorning` check |
| Huawei Health Kit | Individual developers: the app must be "released on AppGallery"; "advanced openness level is currently not open to individual developers"; enterprises need ≥ CNY 1M paid-up capital [V-official] developer.huawei.com/…/health-application-qualifications-as-V5. That page covers HarmonyOS; the Android HMS terms weren't read [Unverified]. Needs HMS Core | Huawei HRV, sleep | **Reject** (e) |
| Polar AccessLink | Partner registration; token call uses "Basic auth with … client_id:client_secret"; webhooks [V-official] polar.com/accesslink-api | Nightly Recharge, sleep, continuous HR | **Reject** (d). The BLE SDK row above covers the same data without a server |
| Withings Public API | Token request needs `client_secret`, or a signature made from it [V-official] developer.withings.com/api-reference (oauth2-getaccesstoken) | Intraday `rmssd` "over a few seconds", respiratory rate | **Reject** (d); HRV is also declared to HC (f) |
| COROS Partner API | "Registered company", "Established platform with demonstrated user base"; COROS issues "Client ID and Secret" [V-official] support.coros.com/…/53181766856724 | — | **Reject** (d)(e). The self-service COROS MCP targets AI assistants and wasn't evaluated [Unverified] |
| Suunto API | "We currently don't offer the API access for personal use"; companies and organisations only [V-official] apizone.suunto.com | FIT files with R-R | **Reject** (e) |
| Ultrahuman Partner API | OAuth code exchange sends `client_secret` [V-official] vision.ultrahuman.com/developer-docs?type=oauth | RHR, temp | **Reject** (d); HRV is declared to HC (f) |
| WHOOP API · Oura API | See 09 / 09b | — | **Vetoed** (09b §2) |

---

## 5. Recommended implementation changes

Everything here respects 09b §7: **no package allow- or deny-list in logic.** Tables are for copy and display only, and outcomes come from observed data.

| # | Change | Files | Effort | Respects |
|---|---|---|---|---|
| R1 | **Add known packages** (display names = Play titles checked 2026-09-30): `nl.appyhapps.healthsync` "Health Sync", `com.ultrahuman.android` "Ultrahuman", `com.heytap.health.international` "OHealth", `com.hihonor.health` "Honor Health", `com.titan.fastrack.reflex` "Fastrack Smart World", `com.topstep.fitcloudpro` "FitCloudPro", `com.urbandroid.sleep` "Sleep as Android", `com.wahoofitness.fitness` "Wahoo". Optionally show Zepp as "Zepp (Amazfit)", since Play titles it "Zepp". Mirror them in `<queries>` (belt and braces; the `VIEW_PERMISSION_USAGE` query already exposes labels) | `domain/engine/source_apps.dart`, `android/app/src/main/AndroidManifest.xml` | S | [U] Any app; names only |
| R2 | **Per-app setup copy table** in pure Dart: package → setup steps (§3), gotchas, and a "usually shares" list with an evidence level. Consumers: the Sources setup card, status-note fix lines and gap explanations. Move `Notes._continuousHrFix`'s Samsung special case (`notes.dart:95-100`) into this table. Nothing in the resolver or engine reads it | new `domain/engine/source_setup.dart`; `notes.dart`; `features/settings/sources_screen.dart` | S–M | Principle 2 (a missing input says how to fix it); 09b §7 |
| R3 | **"What this app shares / what Airlog can compute" card** per detected app on Settings → Sources: <ul><li>**Shares:** types actually seen in 14 days (`SourceApp.daysWithData`).</li><li>**Computes:** the Recovery basis derived from those observed types ("with HRV", "without HRV", "from sleep and sleeping HR", "not available") via a pure helper.</li><li>**Missing:** explained from R2's table ("Samsung Health doesn't share HRV with Health Connect"), labelled "per <App>'s documentation" or "declared, not yet seen".</li></ul>Settings only; never on Today | `features/settings/sources_view_model.dart`, `sources_screen.dart`, new pure helper under `domain/engine/` | M | Principles 1, 2; [U] one job (Today stays calm) |
| R4 | **Profile-value guard (principle 6).** <ul><li>Carry `recordingMethod` on RHR and VO₂max scalar rows (today it's only on HRV rows: `raw_rows.dart:100-111`).</li><li>In the resolver, an origin's RHR or VO₂max series is **not measured** when its records are `MANUAL_ENTRY`, or when their `recordingMethod` isn't AUTOMATIC **and** the value is identical across ≥ 7 wake days. An automatically recorded series is never suppressed, so a genuinely stable user keeps their RHR (principle 2). The 7 is an **[O] constant** to confirm on device.</li><li>Not-measured RHR is excluded from Recovery, Health Monitor and Strain, and the sleeping-HR rule then applies (`_notSharedBy(… restingHr …)`).</li><li>Not-measured VO₂max isn't shown as "the source's estimate".</li><li>Fixture: Polar-shaped (constant RHR, workout-only HR, sleep) must give **no Recovery** plus a status card.</li></ul> | `data/services/health_connect/hc_mapper.dart`, `data/db/raw_rows.dart` + `schema.dart` (column + migration), `data/resolver/resolver.dart`, `test/data/resolver_test.dart` | M | Principle 6; 09b §7 (data-driven, no Polar package check) |
| R5 | **Relay attribution.** For origin `nl.appyhapps.healthsync`, name the device from record metadata ("Garmin via Health Sync"). The baseline key is already `definition@origin#device` | `source_apps.dart` (name), `notes.dart` / `today_planner.dart` copy via `SourceApps.nameOf` | S | Principle 1 (explainable source) |
| R6 | **Membership-aware WHOOP fix line.** When a WHOOP origin writes sleep but never RHR, the fix copy from R2 says RHR and respiratory rate need Peak or Life | R2 table, `notes.dart` | S | Principle 2 |
| R7 | **Fixtures per app shape**: Samsung (HR + sleep, continuous and 10-min), WHOOP One (sleep only), WHOOP Peak (RHR + resp), Oura (HRV, no RHR), Polar (profile RHR, workout HR), Mi Fitness, Health Sync relay with device metadata. On device, reproduce each with the Health Connect Toolbox | `test/data/resolver_test.dart`, `test/domain/*` | M | 09b §9 order; the product-critic row's "non-Fitbit fixtures" |
| R8 | **Polar BLE SDK nightly spike**, behind `--dart-define=POLAR_SDK=true`, personal build, only after §6 Q8 passes. <ul><li>Definitions: `polar_nr_rmssd_4h@ble:<model>` (nightly HRV slot, its own baseline); sleeping HR as `60000 / meanNightlyRecoveryRRI` under `polar_nr_hr_4h` (the same measurement in different units, its own definition, never `restingHr`); respiratory rate from the respiration interval.</li><li>Never read or show `ansStatus` or `recoveryIndicator`.</li><li>Never call delete, FTU or reset APIs.</li></ul> | new `data/services/polar/` (Kotlin plugin `com.polar:polar-ble-sdk`), `definitions.dart`, `SourceKind` (contract, additive) | L | Principles 4 and 6; [U] "Whose scores" |
| R9 | **Samsung Health Data SDK flag** (`SAMSUNG_SDK=true`): read `SkinTemperatureType` only, as `samsung_sdk_skin_temp_sleep_mean@com.sec.android.app.shealth` → Health Monitor. **Deferred** until the user has a Galaxy wearable, and never in a public build without partner approval | Kotlin channel, `data/services/samsung/`, `definitions.dart` | M–L | Principle 6; Samsung's dev-mode terms |
| R10 | **Decision for [U]:** should setup copy for Garmin, Huawei, Suunto and Polar mention a relay (Health Sync)? It's paid and routes data through a third-party cloud. Airlog stays server-less either way; the question is only whether to point users at it | R2 copy | S | Principle 4 (spirit); needs a user decision |

---

## 6. Open questions that need a real device

1. **HR density in HC per app**, which decides the Sleeping-HR gate: Samsung under each of its three settings, Oura, Garmin, Mi Fitness, WHOOP (HR is declared, not listed), and Google Health for the Air (Phase 0).
2. **Declared vs actually written:** COROS, Zepp/Amazfit, Withings, OHealth, Fastrack and Ultrahuman. For each, record the HRV record shape (N2 samples vs N3 single) and its `recordingMethod`. Also Garmin RHR, Google Health SpO₂ and WHOOP HR.
3. **Polar RHR and VO₂max records:** is `recordingMethod` MANUAL_ENTRY or UNKNOWN? Is the value written daily or once per settings change, and does it ever change? This sets R4's rule, its 7-day constant, and which of the two "today" failure modes in §2.2 applies.
4. **Sync latency:** Samsung's watch-to-phone continuous-HR delay; Garmin after a device sync; Oura's "open before midnight" behaviour. This drives the freshness-line copy.
5. **Backfill on first connect:** Polar is forward-only [V-official] and Samsung shares "new or updated" data. Every other app is unknown. This sets the "wear it for 14 days" expectation per app.
6. **WHOOP membership effect:** confirm that a One member gets no RHR or respiratory rate in HC.
7. **Samsung Health Data SDK:** does developer-mode read work on the user's phone with a real Galaxy Watch or Ring, and is SkinTemperature populated? The emulator is unsupported.
8. **Polar BLE SDK vs Polar Flow:** can a second app on the same phone read nightly recharge from a Loop or Vantage without re-pairing, a first-time-use reset, or breaking Flow's sync? Test with no delete calls.
9. **Health Sync relay:** which device metadata does it stamp, what shape is the Garmin HRV it writes, and does its `recordingMethod` pass N2/N3?
10. **Galaxy Ring + Galaxy Watch together:** duplicate sleep sessions under one origin? (Sleep dedup is per origin, 09b §8.)
11. **Stale reports:** re-check Zepp Life, Ultrahuman, Google Fit and Huawei when those apps update.
12. **Unverified in-app paths:** Garmin, COROS, Zepp, Mi Fitness, Ultrahuman, Honor, Fastrack and OHealth. Read them off a device before shipping R2 copy.

---

## 7. Sources (all accessed 2026-09-30)

- **Health Connect / Android:** support.google.com/android/answer/12201227 ; developer.android.com/health-and-fitness/health-connect/migration/fit
- **Google Health:** support.google.com/googlehealth/answer/14506680 ; support.google.com/googlehealth/answer/17068213
- **Samsung:** developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect ; developer.samsung.com/health/data/overview.html ; …/data/guide/developer-mode.html ; …/data/process.html ; …/data/faq.html ; …/data/release-note.html ; …/data/api-reference/-shd/…/-skin-temperature/index.html ; …/-sleep-type/index.html ; …/-heart-rate-type/index.html ; samsung.com/us/support/answer/ANS10006858/
- **Garmin:** support.garmin.com/en-US/?faq=JToBEy0jfe6pIygark2Ui5 ; developer.garmin.com/gc-developer-program/overview/ ; …/health-api/ ; …/program-faq/ ; developer.garmin.com/health-sdk/overview/ ; developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-android/ ; …/api-docs/Toybox/Sensor/HeartRateData.html ; …/api-docs/Toybox/SensorHistory.html
- **Oura:** support.ouraring.com/hc/en-us/articles/10786105824531
- **WHOOP:** support.whoop.com/s/article/Google-Health-Integration-For-Android
- **Polar:** support.polar.com/us-en/flow-app-health-connect ; github.com/polarofficial/polar-ble-sdk (README, `Polar_SDK_License.txt`, `documentation/products/Polar360.md`, `PolarVantageV3andGritX2Pro.md`, `UsingSDKWithWatches.md`, `SyncImplementationGuideline.md`, `…/model/sleep/PolarNightlyRechargeData.kt`) ; polar.com/accesslink-api
- **Withings:** support.withings.com/hc/en-us/articles/23104637348241 ; support.withings.com/hc/articles/27322856325905 ; developer.withings.com/api-reference ; developer.withings.com/developer-guide/v3/integration-guide/public-health-data-api/get-access/oauth-authorization-url
- **COROS:** support.coros.com/hc/en-us/articles/360040256531 ; …/53181766856724 ; …/360058469472
- **Huawei:** consumer.huawei.com/en/support/content/en-us15981770/ ; developer.huawei.com/consumer/en/hms/huaweihealth/ ; developer.huawei.com/consumer/en/doc/atomic-guides-V5/health-application-qualifications-as-V5 ; steppi.crisp.help (Community)
- **Suunto:** apizone.suunto.com
- **Ultrahuman:** vision.ultrahuman.com/developer-docs?type=oauth
- **Health Sync:** healthsync.app/about ; healthsync.app/status ; healthsync.app/f-a-q ; reddit.com/r/Garmin/comments/1luvd2j (Community)
- **Press:** 9to5google.com/2026/05/07/google-fit-shut-down-health-replacement-migration-tool-coming/
- **APK declarations:** reports.exodus-privacy.eu.org/en/reports/<package>/latest/ for every package in §2, with the version and report date inline
- **Play listings:** play.google.com/store/apps/details?id=<package>&hl=en (gl=US, and gl=IN for the Indian-market apps)
