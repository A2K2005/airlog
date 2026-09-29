# Day 1 with the Fitbit Air: the Phase 0 probe

The app runs on synthetic data until the band arrives. This checklist switches it to real data and answers the four questions that gate the design (PRODUCT_PLAN.md §5, Phase 0).

## Before the band arrives
- [ ] Install the debug APK on your phone (`flutter install` or `adb install`, see README).
- [ ] Open it once in demo mode, so you know what "good" looks like.

## Day 1: pair and wear
1. Pair the Air in the **Google Health** app. Turn on **Health Connect sync** there. The app calls it "Sync with Health Connect" (under "Health connect settings"), and its onboarding asks you to let Google Health **write** your data. Allow every type, especially sleep, heart rate, HRV and oxygen saturation.
2. **Wear the band continuously, including to bed.** Baselines need 14 nights, and without the history permission Health Connect only exposes 30 days back.
3. In Airlog: Settings → Sources → **Connect Health Connect**. Grant every permission, including **history** and **background**.
4. Switch Settings → Data mode to **Live**.

## Day 2 morning (after the first night): run the probe
Open Settings → **Diagnostics** and tap *Run probe (7 days)*. Record the results below.

| Question | Where to look | Result | Decision |
|---|---|---|---|
| 1. Do HR, HRV, RHR, respiratory rate, skin temp and **SpO₂** exist **from the Air**? (Google Health declares write permission for all of them; research/07) | Diagnostics → per-type origins/devices (expect `com.fitbit.FitbitMobile` with device "Fitbit Air", not a Pixel Watch) | | If HR or HRV is missing: enable **Enhanced mode** (Google Health API) as the primary source for them |
| 2. HR density | Diagnostics → HEART_RATE median spacing / samples per hour | | ≤ 60 s → full zone-based Strain; sparser → the engine falls back automatically (shown as "estimated" on Strain) |
| 3. HRV frequency | Diagnostics → HEART_RATE_VARIABILITY_RMSSD samples per night | | ≥ 1 per 10 min asleep → nightly mean is solid; 1 per night → still fine for Recovery |
| 4. RR intervals over Bluetooth | Live → connect to the Air (after enabling "share heart rate" on the band) → does *HRV check* unlock? | | Yes → on-demand HRV and stress are available; no → hide them (already automatic) |

Also note:
- **Sync latency:** time from waking to the sleep session appearing.
- **History depth:** first date in Diagnostics.
- **Sleep rewrite:** whether last night's session changes id or length after a few hours (the sync log shows deletions).

Share the probe JSON from Diagnostics → *Share dump* if you want these numbers analysed.

## If Enhanced mode is needed (Google Health API)
1. Create a Google Cloud project, enable the Google Health API, and create an **Android OAuth client**:
   - package `app.airlog.airlog`
   - your debug SHA-1, from `cd android && ./gradlew signingReport`
2. On the OAuth consent screen, add yourself as a test user. Publishing the client "In production" while unverified avoids 7-day re-auth; on day 8, check that tokens still refresh.
3. Build with `--dart-define=GOOGLE_OAUTH_CLIENT_ID=<id>` (see README), then Settings → Sources → **Connect Google Health**.
4. Optional cross-check from this PC: the `ghealth` CLI (Google-Health-API GitHub org) with the same project.

## After 14 nights
- The Recovery calibration banner disappears, and scores move from *provisional* to *established*.
- Compare against how you feel for 2 weeks (Phase 1 exit criterion). Tune only constants, bump `kAlgoVersion`, and recompute; the history is versioned.

## Using another app (Samsung Health, WHOOP, Oura, …)

Airlog reads every app that writes to Health Connect and uses ONE app per metric (Settings → Sources shows which, with its 14-day coverage and any alternatives). Scores are always Airlog's own, computed from the app's measurements; the app's own scores (WHOOP Recovery, Oura Readiness) aren't shown.

1. **Turn on the app's Health Connect sync.** Each app has its own switch, and each data type is a separate permission:
   - **Samsung Health:** Samsung Health → Settings → Health Connect (older versions: Settings → Connected services) → allow it to write. For a sleeping-HR reading, set Heart rate → Measure continuously. Samsung Health doesn't write HRV, resting HR, respiratory rate or skin temperature to Health Connect, so Recovery comes from sleep and "Sleeping HR (4 h mean)", labelled and with lower confidence.
   - **WHOOP:** WHOOP app → More → App settings → Integrations → Health Connect → connect and allow the data types. WHOOP doesn't write HRV to Health Connect, so Recovery is "without HRV".
   - **Oura:** Oura app → Menu → Settings → Health Connect (data sharing) → connect and allow the data types (heart rate, HRV, sleep, temperature).
   - **Garmin Connect, Google Fit, Withings, Polar Flow, COROS, Zepp, Mi Fitness:** look for "Health Connect" in the app's settings or connected-apps list.

   Menu names change between app versions (these paths are unverified on a device); if one isn't where it's listed, search the app's settings for "Health Connect".
2. **Grant Airlog access** in Health Connect (Airlog → Connect Health Connect). If the sheet was dismissed twice, Android won't show it again: open Health Connect → App permissions → Airlog.
3. **Wait for a night.** Recovery needs last night's data. A new app starts its own baseline (reliable after 5 nights, established after 14); Today says it is re-learning your normal meanwhile.
4. **Two apps writing the same metric?** Airlog uses the one with the best 14-day coverage and switches only after 4 days without data from it. To choose yourself, pin the app per metric in Settings → Sources.
