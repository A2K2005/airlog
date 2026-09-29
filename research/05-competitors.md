# Competitive & Design Landscape — Recovery/Readiness Wearable Apps (2026)

Research date: 2026-09-28. Compiled for a hobbyist, Android-first, portfolio-quality app targeting Fitbit Air data via Health Connect and/or the new Google Health API. Items marked **[UNVERIFIED]** could not be confirmed from a primary source in this pass — verify before relying on them. All direct quotes below are kept under 15 words per source; longer claims are paraphrased rather than reproduced.

---

## 0. Context: the device, its official app, and the data-access layer underneath it

### 0.1 Google Fitbit Air and Google Health

**Google Fitbit Air** ($99–100) launched 2026 as Google's screenless, WHOOP-style band — HR, SpO2, skin temp, no display, AI "Health Coach" ($10/mo add-on). Reviews agree on one thing: hardware is good, software is the weak link.

- Wareable: calls it a "worthy buy" held back by a cluttered app and paywalled advanced features. ([Wareable](https://www.wareable.com/fitness-trackers/google-fitbit-air-review))
- 9to5Google: the redesigned app looks modern and Gemini-powered but reads as unfinished, and its density buries the stats longtime Fitbit users came for. ([9to5Google](https://9to5google.com/2026/05/28/fitbit-air-review/))
- Android Authority ran a reader survey of 1,500+ people: just over half actively dislike the new Google Health app, citing graphs that are hard to sort and inconsistently placed. A two-month follow-up found Google had at least added home-screen tile reordering in response. ([survey](https://www.androidauthority.com/survey-reveals-50-percent-users-dont-like-new-google-health-app-3672201/), [week-one piece](https://www.androidauthority.com/i-used-new-google-health-app-for-week-and-hate-it-3670318/), [two-month follow-up](https://www.androidauthority.com/google-health-app-two-months-later-3694569/))
- the5krunner frames it bluntly as a design problem, not just a data problem. ([the5krunner](https://the5krunner.com/2026/05/28/google-health-design-fitbit-problem/))
- Android Authority also reports early Fitbit Air units confusing sleep and activity detection. ([Android Authority](https://www.androidauthority.com/google-fitbit-air-tracking-issues-3673689/))

**Core metrics in Google Health**: Daily Readiness (1–100, from sleep quality/RHR/HRV/recent workouts), a weekly Cardio Load compared against a personalized Target Load range (recently changed from a daily to a weekly target so one bad day doesn't tank the score), and sleep stages. The in-app explanation of *why* a score moved is thin, and the useful coaching layer sits behind Health Coach's $10/mo paywall. ([Google Health Help Center](https://support.google.com/googlehealth/answer/15402655?hl=en), [motion-app breakdown](https://motion-app.com/blog/what-is-cardio-load-google-health/))

### 0.2 Data access: Health Connect vs. the new Google Health API — the single most important architectural fact for this project

Two separate, non-overlapping channels exist for getting Fitbit Air data onto Android, and neither one hands you a finished readiness/load score:

**Health Connect (on-device, Android-only).** Google Health writes steps, distance, heart rate, HRV, sleep sessions/stages, weight and nutrition to Health Connect, but the Google Health app itself does not read other apps' data back in — it is a one-way, write-only relationship in that direction. That asymmetry is why Samsung Health, Garmin Connect, Ultrahuman, Welltory, Sonar, Vora and Tawen can all pull Fitbit Air data through Health Connect even though nothing (yet) feeds data the other way into Google Health. Garmin Connect (added Health Connect support June 2025) and most other vendor apps behave the same way — they write out, they don't read in. Samsung Health is a rare full two-way participant. Health Connect's own data model has **no readiness, recovery, or training-load record type** — only raw physiological signals (HR, HRV/RMSSD, sleep stages, SpO2, skin temperature, VO2max, etc.). Any composite score has to be computed by whichever app reads that raw data. ([Fitbit Community](https://community.fitbit.com/t5/Product-Feedback/Import-data-from-Health-Connect-as-well-as-export/idi-p/5278176), [Notebookcheck — Garmin Health Connect](https://www.notebookcheck.net/Garmin-officially-reveals-Google-Health-Connect-support-for-wearables.1054577.0.html))

**The Google Health API (cloud, cross-platform, health.googleapis.com/v4).** This is a genuinely new fact this research surfaced: the classic **Fitbit Web API has a hard cutoff in September 2026** — OAuth tokens do not carry over, and new developer registrations already closed. Its replacement is the Google Health API, a cloud REST API (Google OAuth 2.0, no SDK) that aggregates Fitbit, Pixel Watch and other connected sources, with webhook support and a "reconciled stream" for overlapping data from multiple sources. Its documented data categories are calories/energy, vitals, workouts, nutrition/hydration, steps, sleep, and women's health — again, **raw and aggregated metrics, not Google's own computed Daily Readiness or Cardio Load scores**. Because it's a plain REST/OAuth API rather than an Android-only on-device layer, it is usable from an Android app exactly as it would be from an iOS or web app. ([developers.google.com/health/about](https://developers.google.com/health/about), [Sahha migration guide](https://sahha.ai/blog/fitbit-api-sunset-migration/), [Terra guide to the new API](https://tryterra.co/blog/everything-you-need-to-know-about-google-health-new-api))

**Practical implication for this project**: neither channel lets you simply "re-skin" Google's own Daily Readiness/Cardio Load numbers with better visuals — those scores don't appear to be exposed via either API. Whatever this project builds will need to compute its own recovery/strain/readiness model from the raw HRV, RHR, sleep-stage and activity data both channels do expose, the same way every third-party app in this document (WHOOP, Oura, Bevel, Athlytic, Welltory, Sonar…) already does with its own inputs.

---

## 1. Hardware ecosystems

### WHOOP (4.0 / 5.0 / MG)
- **Metrics**: Recovery % (color-coded red/yellow/green; HRV/RHR/sleep/respiratory rate), Strain 0–21 (log-scale cardiovascular load), Sleep Performance %, sleep stages, Stress Monitor (continuous HRV/RHR-based), Journal (160+ loggable behaviors correlated against Recovery/HRV/RHR/Sleep), Healthspan/WHOOP Age.
- **Visualization**: three color-coded circular scores (Recovery/Strain/Sleep) as the primary visual hierarchy, with a consistent 1-week/1-month/6-month trend-window toggle applied to every metric. The Journal turns each logged behavior into a ranked list of measured impact on next-day HRV/RHR/Recovery — the deepest correlation feature in the category. Independent testers (The Quantified Scientist) generally rate Oura's layout as calmer and faster to a result, WHOOP's as denser and more rewarding for power users, at the cost of a much longer post-wake sync delay. ([the5krunner 2026 review](https://the5krunner.com/2025/10/31/2026-whoop-5-0-mg-review-discount-accuracy-strain-recovery-athletes/), [WHOOP Journal](https://support.whoop.com/s/article/WHOOP-Journal-Overview?language=en_US), [Stress Monitor launch](https://www.whoop.com/us/en/press-center/whoop-launches-new-stress-monitor-feature-first-wearable-to-measure-daily-stress-levels-and-implement-stress-reduction-interventions-in-real-time/))
- **Pricing (2026)**: three annual tiers, subscription-mandatory — One $199/yr (5.0 hardware), Peak $239/yr (5.0 + wireless PowerPack), Life $359/yr (MG hardware; adds on-demand ECG/blood-pressure insights). No perpetual/one-time option. ([Wareable](https://www.wareable.com/wearable-tech/whoop-5-vs-whoop-mg-which-membership-explained), [TrackerVS](https://trackervs.com/pricing/whoop-pricing/))
- **Android/Health Connect**: two-way — WHOOP writes Recovery/Strain/Sleep/body metrics to Health Connect and can import third-party-logged activities (e.g. from Strava) back in. ([WHOOP support](https://support.whoop.com/s/article/Google-Health-Integration-For-Android?language=en_US))
- **Criticism**: hard-bricks to a read-only history view on subscription lapse; MG's headline features are locked to the top $359/yr tier.

### Oura (Ring 4 / Gen3)
- **Metrics**: Sleep Score, Readiness Score (sleep + HRV + RHR + temperature + prior activity), Activity Score, Cardiovascular Age, stress/resilience tagging.
- **Visualization**: consistently rated the calmest, most front-loaded design in the category — scores are ready immediately on wake, presented large with muted supporting color rather than dense charts, and a small crown icon marks days scoring 85+. Native iOS home-screen/lock-screen widgets (small/medium/large) surface Sleep/Readiness/Activity score, ring battery, and temperature/HR graphs without opening the app; a third-party widget app adds Apple Watch complications for Stress, Cardio Age, VO2 Max and Bedtime. ([Oura widgets](https://support.ouraring.com/hc/en-us/articles/11785597429907-Oura-Widgets), [Ring Widget](https://ringwidget.app/blog/how-to-add-oura-ring-widgets-to-iphone-home-screen))
- **Pricing**: hardware + $5.99/mo or $69.99/yr membership (first 12 months bundled free with a Ring 4). ([Lifestack](https://lifestack.ai/blog/oura-ring-pricing), [TrackerVS](https://trackervs.com/pricing/oura-ring-subscription-cost/))
- **Criticism**: subscription-gated even on owned hardware; users reported a mid-2026 bug that intermittently hid Sleep/Readiness scores. ([gadgetsandwearables](https://gadgetsandwearables.com/2026/07/13/oura-missing-sleep-readiness-data-fix/))

### Garmin Connect (Body Battery / Training Readiness / HRV Status)
- **Metrics**: Body Battery (0–100 moment-to-moment energy gauge that drains through the day and recharges with rest), Training Readiness (score plus six contributing factors: sleep, recovery time, HRV status, sleep history, acute load, stress history), Training Status, Acute/Chronic Load (EPOC-based), and HRV Status.
- **Visualization**: on AMOLED watches, Training Readiness is a widget with score, factor breakdown, and a color band; the phone app adds a 30-day trend graph. **HRV Status is a genuine baseline-band pattern**: your personal HRV baseline is drawn as a shaded range (established over ~3 weeks), and each day's 7-day average is plotted against it as Balanced, Unbalanced, Low, or Poor depending on where it falls relative to that band. Reviewers consistently advise reading the week-over-week trend rather than any single day's number. ([Garmin — HRV Status](https://www.garmin.com/en-US/garmin-technology/health-science/hrv-status/), [Wareable — HRV Status guide](https://www.wareable.com/garmin/garmin-hrv-status-explained-what-is-it-how-to-use), [the5krunner — Training Readiness](https://the5krunner.com/garmin-features/training/training-readiness/))
- **Pricing**: free with any Garmin watch; Connect+ AI layer is a separate paid add-on in some markets.
- **Android/Health Connect**: native support since June 2025; writes ~15 data types out, does not read third-party data back in (same write-only asymmetry as Fitbit). ([Notebookcheck](https://www.notebookcheck.net/Garmin-officially-reveals-Google-Health-Connect-support-for-wearables.1054577.0.html))
- **Standout**: Body Battery's continuous depletion/recharge gauge is the most widely copied visual metaphor in the category (Amazfit's BioCharge and Samsung's Energy Score are direct analogues).

### Samsung Health
- **Metrics**: Energy Score (activity + weekly sleep + sleeping HR + sleeping HRV, 0–100), Sleep Score/Sleep Coaching, "Vitals" (HR, HRV, respiratory rate, skin temp, SpO2 vs. personal baseline), an AGEs-based metabolic-aging signal tied to the Galaxy Ring.
- **Visualization**: Energy Score is presented as a single clearly-labeled number with a breakdown underneath — closer to Oura's simplicity than to Google Health's density. ([Trusted Reviews](https://www.trustedreviews.com/explainer/what-is-samsung-energy-score-4542399))
- **Pricing**: free.
- **Android/Health Connect**: full two-way participant — can both read and write.
- **Criticism**: several 2026 user reports of degraded sleep-time accuracy after a recent update. ([SamMobile](https://www.sammobile.com/news/samsung-health-update-improves-sleep-score-trends-accessibility/))

### Ultrahuman (Ring Air)
- **Metrics**: Recovery Score, Movement Index, Metabolic Score (glucose average/variability/time-in-range — unique among rings), "Ultra Age" (Brain Age + Pulse Age + Blood Age composite), caffeine-window recommendation.
- **Visualization**: inconsistent visual grammar at the summary level — different card types use different chart metaphors (gauge, line, bar) — but all normalize to plain bar charts once you drill into detail. Reviewers describe the overall app as data-dense: rewarding for advanced users, overwhelming for anyone else. ([robbsutton.com](https://robbsutton.com/ultrahuman-ring-air-review/), [SmartRingCompare](https://www.smartringcompare.com/ultrahuman-ring-air-review))
- **Pricing**: $349 hardware, no subscription for core metrics — a real differentiator vs. Oura/WHOOP.
- **Criticism**: inconsistent card-to-card visual language; information density skews toward power users.

### Amazfit Helio Strap / Zepp app
- **Metrics**: BioCharge (Garmin Body Battery analogue), Readiness Score (HR/SpO2/skin temp/breathing quality/sleep), sleep score.
- **Visualization**: the Zepp app links workouts, recovery, habits, nutrition and long-term trend into a single continuous feed rather than separate tabs.
- **Pricing**: hardware-only — free app, **no subscription**, marketed explicitly against paywalled rivals. ([gstylemag Helio Strap Pro review](https://gstylemag.com/2026/09/08/amazfit-helio-strap-pro-review/))
- **Criticism**: reviewers say the sleep score still needs recalibration; BioCharge/readiness math is less battle-tested than Garmin's.

### Polar Flow
- **Metrics**: Nightly Recharge (ANS Charge + Sleep Charge, five-point recovery status), Training Load Pro (Cardio Load + Perceived Load as per-session strain graphs), Recovery Pro (orthostatic-test based, select models).
- **Visualization**: the three systems are shown as separate, inspectable graphs rather than one blended number — giving the "why" that Google Health reviewers say is missing. Widely regarded as the most complete free training-analysis package on a sub-$300 watch. ([Polar support](https://support.polar.com/en/recovery-pro-or-nightly-recharge-which-is-the-right-one-for-me), [CorrerJuntos](https://www.correrjuntos.com/blog/en/polar-pacer-pro-review))
- **Pricing**: free with hardware.
- **Criticism**: UI reads as dated next to Oura or Samsung Health.

---

## 2. Third-party analytics apps

| App | Platform | Reads Fitbit/Health Connect? | Price | Rating found |
|---|---|---|---|---|
| Bevel | iOS only, Apple Watch required | No Android app exists | $14.99/mo | N/A on Android |
| Athlytic | iOS only, Apple Watch required | No Android app exists | Free tier; Pro ~$2.99/mo or $24.99/yr | N/A on Android |
| Gentler Streak | iOS only, Apple Watch | No Android app exists | ~$8.99/mo tier ([Health App Insider](https://www.healthappinsider.com/en/reviews/gentler-streak-review)) | N/A on Android |
| Welltory | iOS + Android | Yes — Fitbit via Health Connect, plus a direct Fitbit-Premium path | Free w/ 3-day trial; Premium $12.99/mo or $79.99/yr | **4.56★ / 60,818 ratings** (Play Store, confirmed direct from listing) |
| Visible | iOS + Android | Camera-based HRV/RHR; Health Connect integration not confirmed | Free core; Visible Plus subscription for wearable HRV | Not found in this pass [UNVERIFIED] |
| HRV4Training | iOS + Android | Camera-based capture; also reads Oura's v2 API directly | $11.99 one-time (Android) | 3.18★ / ~1,200 ratings (Android) |
| Elite HRV | iOS + Android | Chest-strap based; not Health-Connect-centric | Free core | Actively maintained in 2026, not discontinued |
| Training Today | iOS confirmed; Android unconfirmed | Normalizes HRV to a 0–10 personal scale, sleep-debt aware | — | — |
| Rise | iOS + Android | Phone-only sleep-debt/circadian model, no wearable required | $69.99/yr after 7-day trial | 4.7★ / 37,000+ reviews (App Store) |
| AutoSleep | iOS/Apple Watch only | HealthKit only | $7.99 one-time, no subscription | — |

### Android-native / Health-Connect-native apps found during this research

These are the apps that actually work today on Android against Fitbit Air/Health Connect data — none of them were in the original brief, and together they define the current state of the gap.

- **Welltory** — see table above. 4.56★/60.8K ratings makes it the most-proven Android option here, but it's HRV/stress-focused; no strain/training-load system.
- **Sonar (Health & Performance)** — iOS + Android, unifies Recovery/Strain/Sleep/Stress/Energy/Nutrition scores across Garmin, Oura, Fitbit, Samsung Health, Health Connect, Strava, Withings, MyFitnessPal, plus an AI Q&A layer. Free core scores; Pro $5.99/mo, $49.99/yr, or $249.99 lifetime. 4.64★/330 ratings on the **App Store**; **no public aggregate rating currently shown on its Android Play listing** (checked directly — likely below Play's display threshold). Reviews praise the UI, but note fewer data points than similarly-priced competitors and occasional sync failures. ([Play Store](https://play.google.com/store/apps/details?id=com.sonarapp.health), [App Store reviews](https://apps.apple.com/us/app/sonar-health-performance/id1595073849?see-all=reviews&platform=iphone))
- **Vora (AI Longevity Coach)** — Android + iOS, free, claims very broad wearable coverage (Apple Watch, Oura, WHOOP, Garmin, Fitbit, Strava) via Health Connect/HealthKit, readiness score from HRV+RHR+sleep+training load+cycle phase, plus muscle-group-level strain/recovery across 20+ groups — a feature nothing else here offers. Android Play rating: **2.67★ from 16 ratings** — too thin a base to trust, and the broad feature claims read as ahead of the app's actual polish/traction. ([Play Store](https://play.google.com/store/apps/details?id=com.vora.vorafitness&hl=en_US))
- **Tawen** — Android-only, on-device daily Readiness Score computed entirely from whatever is already sitting in Health Connect (Garmin, Galaxy Watch, Pixel Watch, Fitbit, Oura, WHOOP, etc.), no cloud round-trip. $4.99 one-time (package `com.icemint.tawen`, confirmed). Its Play listing currently shows **no public aggregate rating** — consistent with being a very new, thinly-reviewed app. Single-metric scope (readiness only; no strain/load/journal). ([tawen.app](https://tawen.app/))
- **Gadgetbridge** — see Open Source section below; Android-only, reads bands directly over Bluetooth and has been improving its Health Connect integration in recent releases, but is not distributed on the Play Store at all (F-Droid only — confirmed by a direct listing lookup returning "not found").

**Direct answer to "which WHOOP-style apps work on Android against Fitbit/Health Connect data today"**: Welltory, Sonar, Vora, and Tawen are the real answers, with Gadgetbridge as the vendor-independent outlier. Of these, only Tawen and Gadgetbridge are Android-first/Android-only — Sonar and Welltory are cross-platform with their review weight sitting elsewhere, and Vora's low, thin rating means it isn't yet a trusted reference point. **None combines WHOOP-level strain/journal depth with Oura-level visual calm, and none has meaningfully proven itself on Android review volume except Welltory.** This is the open lane.

---

## 3. Open source

- **Pulse (`github.com/Luraxx/pulse`)** — the closest thing to a direct precedent for this exact project, confirmed as a real, active repository (Apache-2.0, Swift, iOS 17+, 28 stars, created July 2026). It is a personal, non-commercial iOS app that reads Fitbit Air data through the new Google Health API (not Health Connect, since it's iOS) and computes its own Recovery % (weighted HRV/RHR/sleep/respiration against a personal 30-day baseline), a logarithmic 0–21 Strain score, sleep metrics with a phase hypnogram, a "Pulse Age" biological-age estimate anchored on VO2max, and 7/30/90-day trend views — entirely on-device, no server, no subscription, with a built-in demo mode using 120 days of synthetic data. It explicitly computes its own scores from raw metrics rather than reading Google's Daily Readiness/Cardio Load, which independently confirms that those composite scores are not exposed by Google's API. There is **no Android equivalent of this project found anywhere in this research** — itself a clear data point for the gap. ([Pulse README](https://github.com/Luraxx/pulse), Apache-2.0 license, verified via GitHub API)
- **Gadgetbridge** — Android, distributed via F-Droid/Codeberg only (not on Google Play — confirmed by a direct listing lookup returning not-found), licensed **AGPL-3.0** (confirmed from the repository's own LICENSE file — not MIT as sometimes assumed). Talks directly to bands (Pebble, Mi Band, Amazfit, Garmin, Huawei, Xiaomi and others) over Bluetooth with no vendor account or cloud dependency. The latest 2026 releases specifically improved Garmin, Huawei, Xiaomi and Health Connect handling; Fitbit/Google Health devices are not among its directly-supported bands, so for a Fitbit Air specifically it would complement Health Connect rather than replace the BLE link to the band itself. ([gadgetbridge.org](https://gadgetbridge.org/), [F-Droid](https://f-droid.org/en/packages/nodomain.freeyourgadget.gadgetbridge/), license confirmed via Codeberg)
- **OpenStrap Edge** — reverse-engineers the WHOOP 4/5/MG Bluetooth protocol and computes sleep/recovery/strain from published research formulas entirely on-device, no WHOOP account or subscription required. Android APK + iOS TestFlight, MIT-licensed. A working proof that a hobbyist can out-engineer a locked-down vendor app and its subscription. ([openstrap.site](https://openstrap.site/), [Hackaday](https://hackaday.com/2026/07/15/making-a-locked-down-wearable-work-without-a-subscription/))

Taken together, Pulse and OpenStrap Edge are the two most directly relevant reference implementations for this project's actual math (recovery/strain scoring formulas, baseline logic), even though neither runs on Android — Pulse's methodology notes in particular (`SETUP.md`) are worth reading in full before designing the scoring engine.

---

## 4. Feature-comparison matrix

Y = yes/present, — = not present or not confirmed.

| App/Ecosystem | Recovery/Readiness | Strain/Load | Sleep score | Stress | HRV | RHR | VO2max | Bio-age | Training load/ACWR | Journal/correlations | AI coach | Android-native | Reads Fitbit/HC | Subscription |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| WHOOP | Y (Recovery %) | Y (Strain 0-21) | Y | Y (Stress Monitor) | Y | Y | partial | Y (WHOOP Age) | via Strain trend | Y (160+ behaviors) | limited | app + HC 2-way | n/a (own hw) | $199-359/yr, mandatory |
| Oura | Y (Readiness) | — | Y | partial (resilience) | Y | Y | — | Y (Cardio Age) | — | tags only | limited | app only | n/a (own hw) | $5.99/mo, mandatory after yr 1 |
| Garmin Connect | Y (Training Readiness, HRV Status) | Y (Acute/Chronic Load) | Y | Y | Y | Y | Y | — | Y (Training Status) | — | Connect+ add-on | HC write-only | n/a (own hw) | free core |
| Google Health (Fitbit Air) | Y (Daily Readiness) | Y (Cardio/Target Load) | Y | partial | Y | Y | Y | — | weekly target load | — | Y ($10/mo Health Coach) | HC write-only | n/a (own hw) | free core + $10/mo coach |
| Samsung Health | Y (Energy Score) | — | Y | Y (Vitals) | Y | Y | Y | AGEs metric | — | — | proactive AI layer | full HC 2-way | Y via HC | free |
| Ultrahuman | Y (Recovery) | Y (Movement Index) | Y | — | Y | Y | — | Y (Ultra Age) | — | — | — | via HC | via HC | none |
| Amazfit/Zepp | Y (Readiness) | Y (BioCharge) | Y | Y | Y | Y | partial | — | — | — | — | unverified | unverified | free |
| Polar Flow | Y (Nightly Recharge) | Y (Training Load Pro) | Y | Y | Y | Y | Y | — | Y (Cardio/Perceived Load) | — | — | unverified | unverified | free |
| Bevel | Y | Y (Strain) | Y | Y | Y (no graph) | Y | — | — | — | — | — | no, iOS only | no | $14.99/mo |
| Athlytic | Y | Y (Effort Score) | target sleep | — | Y | Y | — | — | Y (7-day) | — | — | no, iOS only | no | free/$2.99mo |
| Gentler Streak | qualitative Path | qualitative | Y | — | Y | — | — | — | — | cycle sync | — | no, iOS only | no | ~$8.99/mo |
| Welltory | Y | — | — | Y | Y | Y | — | — | — | correlations | — | Y | Y via HC | $12.99/mo |
| Sonar | Y | Y (Strain) | Y | Y | Y | — | — | — | — | AI Q&A | Y | Y | Y | free / $5.99mo |
| Vora | Y | Y (muscle-level) | Y | — | Y | Y | — | — | — | — | Y | Y (2.67★, unproven) | Y | free |
| Tawen | Y (only metric) | — | — | — | Y | Y | — | — | — | — | on-device explainer | Y, Android-only | Y | $4.99 one-time |
| Gadgetbridge | — | — | Y (raw) | — | raw | raw | — | — | — | — | — | Y, Android-only | via BLE, some HC | free/OSS |
| OpenStrap Edge | Y (reimplemented) | Y (reimplemented) | Y | — | Y | Y | — | — | — | — | — | Y, APK | n/a (WHOOP hw) | free/OSS |
| Pulse | Y | Y | Y | — | Y | Y | Y (via Pulse Age) | Y (Pulse Age) | — | — | — | no, iOS only | via Google Health API | free/OSS |

---

## 5. The gap (Android + Fitbit Air specifically)

1. **No app pairs Oura-level visual calm with Garmin/Polar-level metric completeness on Android against Fitbit Air data.** Everything that reads Fitbit via Health Connect today is either single-metric (Tawen), unproven (Vora at 2.67★/16 ratings), narrow (Welltory: strong on HRV/stress, no strain/load system), or spread thin across too many sources to feel purpose-built (Sonar).
2. **The best-designed apps in the category — Bevel, Athlytic, Gentler Streak, AutoSleep — are all iOS/HealthKit-only**, and Pulse (the one open-source project that targets Fitbit Air directly) is iOS-only too, built against the new Google Health API rather than Health Connect. This is a structural gap, not an oversight: there is currently **no Android project, open-source or commercial, that does for Fitbit Air what Pulse does for iOS.**
3. **Nobody on Android does journaling/behavior-correlation well.** WHOOP's Journal (160+ behaviors → measured next-day impact) is the standard, and it's locked to WHOOP hardware and subscription. None of Tawen, Sonar, or Vora offer anything comparable.
4. **Neither Health Connect nor the new Google Health API exposes Google's own computed Daily Readiness or Cardio Load scores.** Both only carry raw signals (HRV, RHR, sleep stages, SpO2, skin temperature, steps, VO2max). This means the realistic scope for this project is not "visualize Google's score better" but "recompute a recovery/strain/readiness model from the same raw inputs Google, WHOOP, Oura and Pulse all use" — exactly the approach Pulse and OpenStrap Edge both take. Google Health's own presentation is still worth improving on visually, but the underlying score has to be built, not borrowed.
5. **Training-load/ACWR-style periodization visualization is absent from every Health-Connect-native Android app found.** Nothing free or indie on Android currently shows acute:chronic load the way Garmin's Training Status or TrainingPeaks' CTL/ATL/TSB do.
6. **Muscle-group-level recovery (Vora's one real differentiator) is interesting but unproven** — worth watching, not worth copying blindly given its 2.67★ rating.
7. **Two proof-points show a hobbyist can out-build the vendor app**: Gadgetbridge (full vendor independence via direct Bluetooth) and OpenStrap Edge (reverse-engineered WHOOP formulas, entirely on-device, no subscription). Pulse adds a third, closer proof-point: a solo-built, Apache-2.0, on-device recovery/strain/sleep app against Fitbit Air data specifically — just not on Android. Studying its methodology (`SETUP.md`) before designing this project's own scoring engine is a direct, low-risk shortcut.

---

## 6. Best-in-class visualization patterns worth copying (top 8)

1. **Oura's front-loaded, calm score presentation** — the three scores are shown large immediately on open, not buried under navigation, with muted supporting color rather than dense charts. Copy this as the home screen's top module.
2. **WHOOP's color-coded circular score plus a consistent trend-window toggle (1wk/1mo/6mo)** applied uniformly across every metric — the toggle pattern is more reusable than WHOOP's specific color scale.
3. **Garmin's Body Battery depletion/recharge gauge** — a single continuous line that visibly drains through the day and recharges with rest; independently copied by Amazfit (BioCharge) and Samsung (Energy Score) because it's the clearest available metaphor for "energy available right now." Google Health has no equivalent — only a static daily number — making this the single highest-value pattern to add for a Fitbit Air app.
4. **Baseline-band visualization** — Garmin's HRV Status draws your personal baseline as a shaded range and plots today's value against it (Balanced/Unbalanced/Low/Poor); Gentler Streak's Activity Path does the same for training load, as a green band with a dotted line marking your current position within it. This is the single most under-used pattern among the Android-native apps surveyed (Tawen, Sonar, Vora all show a bare number with no baseline context) and directly matches what the brief asked for.
5. **WHOOP Journal's correlation deltas** — ranking logged behaviors by their measured effect on next-day HRV/RHR/Recovery is the most-requested, least-copied feature outside WHOOP itself, and a genuine differentiator to build rather than just visualize.
6. **Polar Flow's three-layer recovery stack shown as separate, inspectable graphs** (ANS charge, sleep charge, training load) rather than one blended number — gives the "why" that reviewers say Google Health is missing.
7. **Native OS widgets/complications** — Oura's small/medium/large home-screen and lock-screen widgets, echoed by a popular third-party widget app adding Apple Watch complications, prove there's unmet demand even among official-hardware owners. An Android home-screen widget (and Wear OS complication, if feasible) should be an early feature, not an afterthought.
8. **"Look at the trend, not the day" framing baked into the UI itself** — explicit weekly-trend arrows or sparklines next to every single-day score, addressing the common complaint (leveled at Vora and Tawen alike) that a bare number without context reads as more alarming or reassuring than it should.

**Anti-patterns to avoid**, all sourced from criticism documented above:
- Inconsistent card placement and unsortable graphs (Google Health) — density should not substitute for hierarchy.
- Mixed visual metaphors at the summary level that all flatten to the same bar chart on drill-down (Ultrahuman) — pick one visual language per metric type and hold it consistently.
- Paywalling the *explanation* of a score while showing the bare number for free (Google Health Coach, Bevel's higher tiers) — the single most-repeated complaint across every review sourced here.
- Over-broad feature claims without the polish or review base to back them up (Vora: 500+ integrations and an AI coach at 2.67★/16 ratings) — a narrower, reliable feature set beats a wide, flaky one for a v1.

---

## Sources
- [Wareable — Fitbit Air review](https://www.wareable.com/fitness-trackers/google-fitbit-air-review)
- [9to5Google — Fitbit Air review](https://9to5google.com/2026/05/28/fitbit-air-review/)
- [Android Authority — Google Health survey](https://www.androidauthority.com/survey-reveals-50-percent-users-dont-like-new-google-health-app-3672201/)
- [Android Authority — week-one piece](https://www.androidauthority.com/i-used-new-google-health-app-for-week-and-hate-it-3670318/)
- [Android Authority — two months later](https://www.androidauthority.com/google-health-app-two-months-later-3694569/)
- [Android Authority — Fitbit Air tracking issues](https://www.androidauthority.com/google-fitbit-air-tracking-issues-3673689/)
- [the5krunner — Google Health design problem](https://the5krunner.com/2026/05/28/google-health-design-fitbit-problem/)
- [Google Health Help Center — Cardio Load/Target Load](https://support.google.com/googlehealth/answer/15402655?hl=en)
- [motion-app — Cardio Load explainer](https://motion-app.com/blog/what-is-cardio-load-google-health/)
- [Fitbit Community — Health Connect import limitation](https://community.fitbit.com/t5/Product-Feedback/Import-data-from-Health-Connect-as-well-as-export/idi-p/5278176)
- [developers.google.com/health/about — Google Health API](https://developers.google.com/health/about)
- [Sahha — Fitbit Web API shutdown/migration](https://sahha.ai/blog/fitbit-api-sunset-migration/)
- [Terra — guide to the new Google Health API](https://tryterra.co/blog/everything-you-need-to-know-about-google-health-new-api)
- [the5krunner — WHOOP 5.0/MG 2026 review](https://the5krunner.com/2025/10/31/2026-whoop-5-0-mg-review-discount-accuracy-strain-recovery-athletes/)
- [WHOOP — Journal overview](https://support.whoop.com/s/article/WHOOP-Journal-Overview?language=en_US)
- [WHOOP — Stress Monitor launch](https://www.whoop.com/us/en/press-center/whoop-launches-new-stress-monitor-feature-first-wearable-to-measure-daily-stress-levels-and-implement-stress-reduction-interventions-in-real-time/)
- [Wareable — WHOOP 5.0 vs MG](https://www.wareable.com/wearable-tech/whoop-5-vs-whoop-mg-which-membership-explained)
- [TrackerVS — WHOOP pricing 2026](https://trackervs.com/pricing/whoop-pricing/)
- [WHOOP support — Health Connect integration](https://support.whoop.com/s/article/Google-Health-Integration-For-Android?language=en_US)
- [Oura — Widgets](https://support.ouraring.com/hc/en-us/articles/11785597429907-Oura-Widgets)
- [Ring Widget app](https://ringwidget.app/blog/how-to-add-oura-ring-widgets-to-iphone-home-screen)
- [Lifestack — Oura pricing 2026](https://lifestack.ai/blog/oura-ring-pricing)
- [TrackerVS — Oura subscription cost](https://trackervs.com/pricing/oura-ring-subscription-cost/)
- [gadgetsandwearables — Oura missing scores bug](https://gadgetsandwearables.com/2026/07/13/oura-missing-sleep-readiness-data-fix/)
- [Garmin — HRV Status](https://www.garmin.com/en-US/garmin-technology/health-science/hrv-status/)
- [Wareable — Garmin HRV Status guide](https://www.wareable.com/garmin/garmin-hrv-status-explained-what-is-it-how-to-use)
- [the5krunner — Garmin Training Readiness](https://the5krunner.com/garmin-features/training/training-readiness/)
- [Notebookcheck — Garmin Health Connect support](https://www.notebookcheck.net/Garmin-officially-reveals-Google-Health-Connect-support-for-wearables.1054577.0.html)
- [Trusted Reviews — Samsung Energy Score](https://www.trustedreviews.com/explainer/what-is-samsung-energy-score-4542399)
- [SamMobile — Samsung Health update issues](https://www.sammobile.com/news/samsung-health-update-improves-sleep-score-trends-accessibility/)
- [robbsutton.com — Ultrahuman Ring Air review 2026](https://robbsutton.com/ultrahuman-ring-air-review/)
- [SmartRingCompare — Ultrahuman Ring Air 2026](https://www.smartringcompare.com/ultrahuman-ring-air-review)
- [gstylemag — Amazfit Helio Strap Pro review](https://gstylemag.com/2026/09/08/amazfit-helio-strap-pro-review/)
- [Polar support — Recovery Pro vs Nightly Recharge](https://support.polar.com/en/recovery-pro-or-nightly-recharge-which-is-the-right-one-for-me)
- [CorrerJuntos — Polar Pacer Pro review](https://www.correrjuntos.com/blog/en/polar-pacer-pro-review)
- [autonomous.ai — Bevel app review](https://www.autonomous.ai/ourblog/bevel-app-review)
- [askvora — Bevel vs Athlytic](https://askvora.com/blog/bevel-vs-athlytic-apple-watch-recovery-apps)
- [Health App Insider — Gentler Streak review 2026](https://www.healthappinsider.com/en/reviews/gentler-streak-review)
- [Gentler Streak docs — Activity Path](https://docs.gentler.app/understanding-your-activity-path/what-is-the-activity-path)
- [Welltory — Health Connect help](https://help.welltory.com/en/articles/9214700-how-to-connect-data-source-via-health-connect)
- [Welltory — Play Store listing](https://play.google.com/store/apps/details?id=com.welltory.client.android&hl=en-US)
- [Visible — Play Store](https://play.google.com/store/apps/details?id=com.makevisible.visible&hl=en_US)
- [hrv4training.com](https://www.hrv4training.com/)
- [Rise — risescience.com](https://www.risescience.com/)
- [Rise — Play Store](https://play.google.com/store/apps/details?id=com.risesci.nyx)
- [macstories.net — AutoSleep 5](https://www.macstories.net/reviews/autosleep-5-adds-automatic-apple-watch-sleep-tracking-and-much-more/)
- [Gadgetbridge](https://gadgetbridge.org/)
- [F-Droid — Gadgetbridge](https://f-droid.org/en/packages/nodomain.freeyourgadget.gadgetbridge/)
- [openstrap.site](https://openstrap.site/)
- [GitHub — OpenStrap/edge](https://github.com/OpenStrap/edge)
- [Hackaday — Openstrap Edge coverage](https://hackaday.com/2026/07/15/making-a-locked-down-wearable-work-without-a-subscription/)
- [GitHub — Luraxx/pulse](https://github.com/Luraxx/pulse)
- [tawen.app](https://tawen.app/)
- [Sonar — Play Store](https://play.google.com/store/apps/details?id=com.sonarapp.health)
- [Sonar — App Store reviews](https://apps.apple.com/us/app/sonar-health-performance/id1595073849?see-all=reviews&platform=iphone)
- [Vora — Play Store](https://play.google.com/store/apps/details?id=com.vora.vorafitness&hl=en_US)
