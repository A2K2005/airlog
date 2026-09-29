# Fitbit Air Companion: Research Synthesis & Product Plan

**Date:** 2026-09-28 · **Status:** pre-build (the band hasn't arrived yet) · **Platform:** Android first

Source reports, each with citations:
- [01 Pulse repo](research/01-pulse-repo.md)
- [02 Edge repo](research/02-edge-repo.md)
- [03 Data access](research/03-data-access.md)
- [04 User sentiment](research/04-user-sentiment.md)
- [05 Competitors](research/05-competitors.md)

---

## 1. Bottom line

1. **This looks feasible on Android, and nobody has built it yet. Verify it on day 1.**
   - Google's official table says the Google Health app writes Fitbit Air data into **Health Connect**: HR, HRV (RMSSD), resting HR, respiratory rate, skin temperature, sleep stages, exercise, steps and VO2 max.
   - That route needs no Google Cloud project, no OAuth verification and no CASA audit.
   - **Caveat:** a 2026-09-19 GitHub PR claims Google Health does *not* write HR, HRV, respiratory rate or resting HR. The community HRV logs may come from a Pixel Watch under the same app origin. HRV drives 40% of Recovery, so Phase 0 must confirm that *Air-origin* HR and HRV are present.
   - The only open-source equivalent (Luraxx/pulse) is iOS-only. No Android app pairs WHOOP-grade analytics with good design for Fitbit data.
2. **We compute our own scores.** No sanctioned path exposes Google's Readiness, Sleep Score or Cardio Load, so Recovery, Strain and Sleep are ours to define. That's a product opportunity as much as a constraint.
3. **Port Pulse's math and lift Edge's chart and design code. Fork neither.**
   - Pulse (Apache-2.0) has complete, cited formulas that run on summary-level data. They have only been tested on fixtures, never on a real device.
   - Edge (MIT) contributes two self-contained files: `lib/ui2/charts.dart` (1,287 lines; Ring, Hypnogram, ZoneBar, LineChart, NightStack and other painters) and `theme.dart`. Both depend only on Flutter.
   - We don't take Edge's analytics. They live in a separate repo, and most need beat-to-beat signals that Health Connect doesn't expose.
4. **One unknown gates the design: heart-rate sample density in Health Connect.** HR is stored at 1 s in the cloud API and the band records at 2 s, but nobody has measured what reaches Health Connect. Measure it on day 1 (see §5, Phase 0).
5. **Differentiate on trust.** Users' top complaints about Google Health are clutter, a hallucinating AI coach, scores stuck on "calibrating", and paywalled explanations. We win with calm, explainable, honest and free-at-core.
6. **Use several sources, not just Health Connect** (see §2.5). The app layers each on top of Health Connect only where it makes the product better:
   - **Google Health API:** SpO2, deep-sleep HRV, AZM, and a fallback if Health Connect lacks HR or HRV.
   - **Live Bluetooth heart rate:** workouts, and possibly spot HRV readings.
   - **Takeout import:** full history for people switching from older Fitbits.
   - **Other Health Connect apps:** weight, nutrition, cycle and phone steps, as context.
   - **Stack is decided: Flutter** (see §4).

---

## 2. What the research found

### 2.1 Data access (the binding constraint)

| Metric | Health Connect | Google Health API v4 | Observed granularity |
|---|---|---|---|
| Heart rate | ✅ | ✅ | **Unverified in HC.** 1 s in the API; the band stores 2 s |
| HRV (RMSSD) | ✅ | ✅ (+ deep-sleep RMSSD, entropy) | About every 5 min, 60–100 a day (community); no RR intervals anywhere |
| Resting HR | ✅ | ✅ | Daily |
| Respiratory rate | ✅ | ✅ (+ per sleep stage) | Daily |
| Skin temperature | ✅ | ✅ | Nightly delta |
| Sleep + stages | ✅ | ✅ | Sessions with stage spans |
| Exercise, steps, distance, total calories | ✅ | ✅ | Calories in 15-min buckets |
| VO2 max | ✅ | ✅ | Daily |
| SpO2 | ⚠️ Declared: Google Health v5.08 requests `WRITE_OXYGEN_SATURATION` (research/07) | ✅ | Unverified in HC; the API is the fallback |
| AZM, active calories | ❌ | ✅ | API only |
| Readiness, Sleep Score, Cardio Load | ❌ | ❌ | Not exposed anywhere |

The Health Connect column comes from Google's official write table. One community PR contradicts it for HR, HRV, respiratory rate and resting HR, so treat that column as **unverified until Phase 0**.

**Update 2026-09-29 (research/07):** the Google Health app's manifest (v5.08) declares Health Connect WRITE permission for heart rate, HRV, resting HR, respiratory rate, skin temperature, sleep, VO₂ max **and SpO₂**. That makes the PR's claim less likely, but it doesn't prove the *Air's* samples are written, or how dense they are. Phase 0 still decides.

Health Connect gotchas we must engineer for:
- Sleep sessions get deleted and rewritten.
- A timezone change writes the same night twice; the later write is correct.
- Future-dated calorie "projection" records exist.
- Other apps may write the same types. Use exactly **one origin per metric**; never sum or mix them. This was a Fitbit-only filter until 2026-09-29; see §7, "Any app".
- By default we can read only 30 days back; older data needs `READ_HEALTH_DATA_HISTORY`.
- Background reads need `READ_HEALTH_DATA_IN_BACKGROUND`.

Routes ruled out:
- **Proprietary BLE sync:** AES-EAX encrypted with a server-held key.
- **Legacy Fitbit Web API:** shut down on 2026-09-30.
- **Standard BLE HR profile (`0x180D`):** works for **live HR only**. That's useful for a live-workout screen.

### 2.2 Reference repos: what to take

| Take | From | Why |
|---|---|---|
| Recovery, Strain, Sleep (need, debt, consistency), Health Monitor and Pulse Age formulas, with constants | Pulse | Designed for Fitbit Air summary data and cited, but **only tested on fixtures**. Pulse's Google Health API field names are guesses. See `research/01` for file:line refs |
| Chart painters (`charts.dart`) and design tokens (`theme.dart`) | Edge | Self-contained (Flutter-only imports), so they can be copied directly under MIT |
| HR-based Banister TRIMP and Plews lnRMSSD with smallest-worthwhile-change readiness | Edge (method citations) | These need only HR and nightly RMSSD, so they port. The rest of Edge's math needs RR intervals |
| Tolerant decoding and a per-metric sync log | Pulse | One missing data type never blocks the rest |
| "Status card instead of a guessed number" for absent metrics | Edge | Honesty pattern; fixes the "calibrating forever" pain |
| Every chart has real axes plus a screen-reader description; trend arrows only when statistically significant | Edge | Credibility and accessibility |
| An immutable, algorithm-versioned `day_result` schema | Edge | Lets us recompute history when formulas change |
| "Consistency (X of Y days)" instead of streaks | Edge | Healthier framing |
| **Don't take:** Edge's BLE layer, its RR/PPG-based analytics, or `AppState` | Edge | Not applicable, or a churn hotspot |

License obligations: keep the Apache-2.0 NOTICE for ported Pulse math and the MIT notice for anything copied from Edge.

### 2.3 Users: pain points and our answer

| Pain point (see `research/04` for sources) | Our answer |
|---|---|
| The Google Health redesign is cluttered | A calm Today screen: three scores, then detail on demand |
| The Gemini coach hallucinates workouts and events | Every insight is a deterministic rule that shows its numbers. The optional coach is grounded: tool calls over local data plus a verifier (§3.4; this superseded the original "no generative coach in v1" on 2026-09-29) |
| Readiness and Sleep Score are stuck on "calibrating" | Visible calibration ("baseline day 9 of 14"), plus provisional scores labelled with confidence |
| Features vanished (live HR, VO2 max) | Live HR over BLE during workouts; a VO2 max trend |
| Explanations are paywalled | Every score's breakdown is free and computed on device |
| Fear of data lock-in during the API migration | One-tap CSV/JSON export of the raw data and the scores |
| Charging leaves gaps in 24/7 data | Gap-aware baselines, so partial days are excluded instead of poisoning the averages |
| Sync bugs (upstream) | We can't fix Google's sync, but a "last data received" freshness line makes stale data obvious |
| The WHOOP app is called ugly; Bevel is the design benchmark | Design-led: baseline bands and trend arrows next to every score |

**Coverage limits of this research:**
- Direct Reddit scraping was blocked, so Reddit evidence comes from search snippets and articles that quote threads. Most thread dates are estimated.
- X/Twitter, r/QuantifiedSelf and YouTube comments are thin or absent.
- Several quotes are paraphrases from AI search summaries; they're flagged in `research/04`.
- Re-verify any quote before using it externally, for example in a portfolio case study.

### 2.4 Competitors: the gap

- **Android options today:**
  - Welltory: 4.56★ on about 61k ratings, $12.99/mo.
  - Sonar: $5.99/mo.
  - Tawen: $4.99 one-time, readiness only.
  - Vora: thin reviews.
  - The best-designed apps (Bevel, Athlytic, Gentler Streak) are iOS-only.
- **Nobody on Android offers:**
  - WHOOP-level strain and journal depth combined with Oura-level visual calm, on Fitbit data
  - behavior-correlation journaling
  - a training-load (ACWR) view
- **Patterns to copy:**
  - Oura's score-first calm layout
  - WHOOP's score ring with trend-window toggles
  - **Garmin's Body Battery drain/recharge gauge** (Google Health has no equivalent)
  - a shaded personal-baseline band with today's value plotted inside it
  - WHOOP Journal's correlation deltas
  - home-screen widgets
- **Anti-patterns:**
  - paywalling the explanation of a free score
  - inconsistent card metaphors
  - feature claims without evidence

### 2.5 Data sources beyond Health Connect

Health Connect stays the base: it's free to publish and needs no cloud project. Each source below is added only for what it improves.

| Source | What it adds to the product | Cost / constraint | Verdict |
|---|---|---|---|
| **Google Health API v4** (cloud REST, OAuth) | **SpO2**: nightly average and minimum, plus intraday. That brings back the "overnight SpO2" feature users say vanished, and powers a Recovery penalty. **Deep-sleep RMSSD**, the cleanest HRV input for Recovery, plus non-REM HR and HRV entropy. Skin temp with Google's own 30-day baseline and SD. Respiratory rate per sleep stage. AZM, active minutes, calories per HR zone. Documented schemas, webhooks and deep history. **It's also the fallback if the Air's HR or HRV isn't in Health Connect** | Google Cloud project plus OAuth PKCE. Unverified cap of **100 users for the project's lifetime**, a warning screen at sign-in, and a mandatory in-app disclosure. Beyond 100 users it needs verification (demo video, domain, privacy policy) **plus annual CASA** ($500–$4,500, 2–6 weeks) | **Add** as an opt-in **"Enhanced mode"**: on in your build, and limited to 100 users in the public build until verification is worth paying for |
| **Live Bluetooth HR** (standard HR profile `0x180D` / `0x2A37`) | **Live workout screen** for a screenless band: real-time HR, zones, strain building live, voice cues at zone changes. **HR recovery (HRR-60, Cole 1999)** after each workout, which needs 1 Hz HR. **If the band sends RR intervals**, it also enables a 2-minute **on-demand HRV check** (HRV4Training/Elite HRV style) and **RR-based stress** (Baevsky) | You enable "share real-time heart rate" on the band, which costs battery. It's only live while connected, so it's not a history source. **RR intervals are unverified** (day-1 test) | **Add.** `flutter_blue_plus` plus Edge's MIT `ble_hrs.dart` parser (84 lines) |
| **Other Health Connect origins** (same API, other apps) | Context for journal correlations and better maths: **weight** from smart scales (calorie and VO2 max accuracy), **nutrition** (Cronometer/MyFitnessPal: late meals, caffeine), **hydration**, **menstrual cycle** (recovery context), **mindfulness sessions**, and **steps from the phone or other apps while the band charges**, which fills the charging gap | A few extra read permissions, each needing its own Play justification. **Since 2026-09-29, other origins are also first-class primary sources** (Samsung Health, WHOOP, Oura, …), one origin per metric with its own baseline segment (§7) | **Add**; context types stay optional until the user grants them |
| **Google Takeout import** | Years of history in one go, so **baselines on day 1** for people switching from older Fitbits (Recovery otherwise needs 14–30 days). Also a restore path | Manual one-off upload of a ZIP (per-day JSON; format unverified for 2026). **Little value for you**, since your band is new | **Add later** (Phase 4, for public users) |
| **Weather** (Open-Meteo: free, no API key) | Context signal: hot or humid nights vs HRV and sleep | Sends coarse location to a third party | **Optional, off by default** (v3) |
| **`ghealth` CLI** (community tool in the Google-Health-API GitHub org) | Not an app feature: it lets us **inspect the Air's API data from this Windows PC on day 1** before writing any code | Needs the Cloud project anyway | **Use in Phase 0** |
| Proprietary Bluetooth sync | Would give everything | AES-128-EAX encrypted with a key held on the server, plus ToS risk | ❌ Not viable |
| Legacy Fitbit Web API | — | Shut down 2026-09-30 | ❌ |
| Gadgetbridge | — | Needs a rooted phone, only gets live data, work paused | ❌ |
| Aggregators (Terra, Thryve, Rook) | Nothing we can't get directly | Paid, and send data through their servers, which breaks the privacy principle | ❌ |

**Merge rules:**
- **Every raw record stores its source** (`hc` / `ghapi` / `ble` / `takeout` / `context`), and the UI shows it ("HRV · deep sleep · Google Health API").
- **For each metric we pick one source by priority. We never average across sources.**
  - HRV: API deep-sleep RMSSD, else Health Connect samples aggregated over sleep.
  - SpO2: API only.
  - Live HR: Bluetooth.
  - History: Health Connect or API, with Takeout only for dates before either.
- **Baselines never mix definitions.** Deep-sleep RMSSD and all-night RMSSD differ, so switching a metric's source starts a new baseline segment.

---

## 3. Product

**One-liner:** *One clear answer each morning (how you are, and what to do today), from the tracker you already use. Built from its own measurements, computed privately on your phone, free.* (Until 2026-09-29: "The WHOOP experience for your Fitbit Air"; widened to any app that writes to Health Connect.)

**Principles**
1. **Explainable.** Tapping any score shows its inputs, their weights and how today compares with your baseline.
2. **Honest.** A missing input shows a status card saying what's missing, why, and how to fix it. We never guess a number.
3. **Calm.** One plain-words answer and at most 3 actions on Today, with the three scores beneath it and detail one tap away. No AI chatter. Everything else (Journal, Live workout, Pulse Age, Coach) lives in a secondary More area.
4. **Private.** Everything is computed on device. No server, no account, no analytics.
5. **Owned.** Export everything, any time.
6. **Derived, never invented.** Every number traces to a measurement from the user's own source app, and our scores are computed from those measurements. We never estimate one metric from another under its name (e.g. no "HRV" guessed from heart rate, no VO₂max estimated from a heart-rate ratio), and we never show a number the data doesn't support.

### 3.1 MVP screens (v1)

| Screen | Shows |
|---|---|
| **Today** | **TodayPlan first**: the state in plain words, its why with numbers, 0–3 actions, and the basis ("without HRV", provisional, re-learning); after the evening cut-off it speaks about tonight. Then the Recovery, Strain and Sleep scores; the Health Monitor vitals against their baselines; one freshness line per source app; one collapsed data-notes row. A ⋯ More menu holds Coach, Journal, Live workout and Settings (§7, 2026-09-29) |
| **Recovery detail** | Score breakdown (HRV / RHR / sleep / respiration contributions) and each input plotted inside its 30-day baseline band |
| **Sleep** | Hypnogram, duration vs need, debt, consistency (bed/wake scatter), efficiency |
| **Strain** | HR timeline coloured by zone, time in each zone, per-workout strain, target strain for the day's recovery |
| **Trends** | Recovery vs Strain, HRV, RHR and sleep over 7, 30 and 90 days, with trend arrows only when the change is significant |
| **Settings / Data** | Health Connect permissions, sync log for each metric, export, algorithm version |

### 3.2 v1 metric engine

| Metric | Inputs (Health Connect) | Method | Origin |
|---|---|---|---|
| Recovery (1–99%) | nightly HRV, RHR, sleep performance, respiratory rate; in Enhanced mode, deep-sleep RMSSD replaces all-night HRV, and SpO2 below 90% applies a penalty | z-score vs a 30-day baseline, through a logistic curve; weights 40/25/25/10; missing inputs re-weighted; green ≥67, yellow 34–66, red <34 | Pulse |
| Strain (0–21) | HR samples, RHR, max HR | Karvonen HRR zones, weighted, then `21·(1−e^(−load/450))`; fallback from exercise sessions and steps if HR is sparse | Pulse (cross-check against Banister TRIMP per Edge) |
| Sleep | sleep sessions and stages | need = 7.6 h baseline + debt share + strain boost; debt capped; consistency from bed/wake deviation | Pulse |
| Health Monitor | RHR, HRV, respiratory rate, skin temp delta | baseline ± max(1.65·SD, floor); alert if ≥2 metrics are off, or 1 is off for ≥2 days | Pulse |
| VO2 max | `Vo2MaxRecord` | display and trend | Health Connect (needs a small platform channel under Flutter) |

The skin-temperature feature (illness/recovery signal) matters here. Google Play applies heightened scrutiny to `READ_SKIN_TEMPERATURE`, and this gives us a concrete user-facing justification.

### 3.3 Later (v2+), and gated

| Feature | Gate |
|---|---|
| **Energy gauge** (Body Battery-style) | Needs about 5-minute HRV and dense HR in Health Connect (verify in Phase 0) |
| **Journal + correlations** ("alcohol → −12% recovery") | None; this is the main differentiator after the MVP |
| **Training load (ACWR 7-day/28-day)** | 4+ weeks of strain history |
| **Live workout screen** (BLE HR, zone voice cues, live strain, HRR-60 after each workout) | HR sharing enabled on the band (costs battery) |
| **On-demand HRV check** and RR-based stress | The band's `0x2A37` notifications carry RR intervals (day-1 test) |
| **Home-screen widget** (`home_widget`) | None |
| **Pulse Age** (VO2 max → FRIEND norms, blended with an HRV age) | 30 days of data |
| **Enhanced mode** (Google Health API): SpO2 card and Recovery penalty, deep-sleep HRV, AZM, per-stage respiratory rate | Cloud project; 100-user cap until verification plus CASA |
| **Context data** (weight, nutrition, cycle, mindfulness, phone steps) feeding the journal correlations | Per-type Health Connect permission granted |
| **Takeout history import** | Takeout format confirmed |
| **Weather context** (optional) | User opt-in |

### 3.4 Ask: the grounded coach (added 2026-09-29, user decision)

This is a **deliberate exception to "no generative coach"**. The user wants Google-Health-style Q&A about their own data, and the design keeps the trust and privacy positioning:
- **Grounded by construction.** The coach answers only through read-only tools over the local store, never from numbers pasted into the prompt. A deterministic verifier checks every number, date and event in the answer against that turn's tool results. It allows one repair round, then falls back to a plain facts table. Sources show as tappable chips. This targets the top complaints: invented events, and missing data treated as real.
- **Private by default.**
  - The default engine is **on-device and deterministic**: intent routing plus templates, with no model and nothing sent.
  - Cloud **Claude** (recommended) or **Gemini** is opt-in with the user's own key:
    - 18+ confirmation, a disclosure of exactly what leaves the phone, and an affirmative consent;
    - a "What was sent" view on every answer;
    - for Gemini, the user confirms the key is on a paid project, because free-tier keys train on prompts.
- **Two modes, WHOOP-style.** "Use my data" or "General only". Plus a brief/detailed length setting.
- **Memory.** A visible, editable "What Coach knows" list in 7 categories, with optional expiry. Nothing is saved without a "Remember this?" tap, and chat history is kept separate.
- **Safety.** A deterministic red-flag router runs before any model call. The coach gives wellness information, never diagnosis or dosing.
- **Compliance.** Google Health API data never goes to a cloud model (its limited-use rule plus CASA). Before a public release, sending Health Connect data to a cloud model needs written confirmation from Play policy support (research/06).
- **Later:** Gemini Nano as a phrasing layer on supported phones (about 5–15% of Air owners) in v1.5; Gemma 4 on-device in v2 after benchmarking.

Research: `research/06-ai-coach.md`, `06b` (Gemini API), `06c` (on-device), `06d` (competitor coaches), `07` (Google Health APK), `08` (WHOOP APK).

**Out of scope:**
- An *ungrounded* generative coach: the #1 trust complaint. See §3.4 for the grounded version we build instead.
- Food logging: a different product.
- All-day stress (Baevsky, LF/HF): needs continuous RR intervals, which no source provides. Spot stress is possible only during Bluetooth HRV checks, if RR is present.
- ~~iOS~~: moved in scope for after Android v1. See §7 and `IOS_PLAN.md`.

---

## 4. Tech plan

**Stack (decided): Flutter.** It builds on Windows for Android, and it's the same stack as Edge, so Edge's chart, theme and heart-rate parser code drops straight in.

| Need | Package |
|---|---|
| Health Connect | `health` 13.3.2, plus a small Kotlin channel for VO2 max |
| Google Health API | `flutter_appauth` (OAuth PKCE) + `flutter_secure_storage` (tokens) + `http` |
| Live Bluetooth HR | `flutter_blue_plus` |
| Local storage | `sqflite` |
| Background sync | `workmanager` |
| Home-screen widget | `home_widget` |

Edge already pins `flutter_blue_plus`, `sqflite`, `workmanager`, `home_widget`, `flutter_secure_storage` and `health`, so this is a proven combination.

I checked the `health` 13.3.2 source (`android/src/main/kotlin/cachet/plugins/health/`) against what we need:

| Need | Supported? |
|---|---|
| HRV (`HeartRateVariabilityRmssdRecord`) | ✅ |
| Skin temperature delta | ✅ |
| HR samples with timestamps | ✅ |
| Sleep stages, resting HR, respiratory rate, exercise, steps | ✅ |
| Change tokens with upsert **and deletion** events, plus token-expiry flag (`HealthDataChanges.kt`) | ✅ |
| History and background permissions | ✅ |
| **VO2 max** | ❌ Needs a ~50-line Kotlin platform channel |
| **Filter by data origin at query time** | ❌ Filter after reading instead. The origin package is in `sourceName`; `sourceId` is always empty on Android (verified in plugin source during the build) |

**Considered and rejected: Kotlin + Jetpack Compose.** It would give first-party Health Connect SDK fidelity and native Glance widgets, but we'd have to rewrite Edge's charts and heart-rate parser, and lose the iOS path. The plugin's two gaps are small: VO2 max needs a small channel, and origin filtering happens after reading.

```
sources/
  hc_source      Health Connect: change tokens; ANY origin, one persisted origin per metric;
                 drop future-dated records; sleep-rewrite + TZ-duplicate handling
  ghapi_source   Google Health API (Enhanced mode): OAuth PKCE, 5 QPS/user, webhooks optional
  ble_hr_source  live 0x2A37 HR (+ RR if present) during workouts / HRV checks
  context_source other Health Connect origins (weight, nutrition, cycle, steps) + optional weather
  takeout_import one-off ZIP → raw tables
        │  every row tagged with source
        ▼
SQLite raw tables ──► resolver (per-metric source priority, baseline segments)
        ──► engine/ (pure Dart: baselines, scores; algo-versioned)
        ──► SQLite day_result ──► UI (Edge charts.dart + theme.dart) + widget
```

- **First sync:** backfill 30 days, or more if the history permission is granted, then store a changes token.
- **Periodic sync:** every 15 minutes or more. Apply upserts and deletions from the changes token, then recompute only the affected days. If the token has expired, do a full re-read.
- **Recompute on rewrite:** when a sleep session is rewritten, that day's `day_result` is recomputed and versioned.
- **`engine/`:** pure Dart with no Flutter or plugin imports. It's unit-tested with synthetic fixtures (port Pulse's demo-data generator idea) plus real payloads captured in Phase 0.
- **iOS stays possible later** through the Google Health API. A cloud CI service such as Codemagic can build iOS without owning a Mac, but you'd still need a $99/yr Apple developer account.

---

## 5. Roadmap

| Phase | Deliverable | Exit criteria |
|---|---|---|
| **0: Probe** (days 1–3 after the band arrives) | Four checks, run side by side: (1) a small app that reads every Health Connect type from the `com.fitbit.FitbitMobile` origin and dumps JSON plus spacing stats; (2) a cross-check in the Health Connect Toolbox app; (3) `ghealth` CLI pulls of the same days from the Google Health API; (4) a Bluetooth probe that subscribes to `0x2A37` and checks the RR-interval flag | **1. Presence:** HR, HRV, RHR, respiratory rate and skin temp records exist, and their device metadata says "Fitbit Air", not a Pixel Watch. **2. Density:** HR sample spacing and HRV frequency. **3. Also measured:** sync latency, history depth, sleep-rewrite behavior. **Decisions:** (a) If HR is at least one sample per minute, use full HR-zone strain; otherwise use the fallback model. (b) If Air HR or HRV is *absent* from Health Connect, switch to the Google Health API (see Risks) |
| **1: Engine** | `:engine` module with Recovery, Strain, Sleep and Health Monitor, plus tests on synthetic and captured fixtures | Scores are stable and explainable on 2+ weeks of real data |
| **2: MVP UI** | The six v1 screens, the sync log and export | Daily use by you for 2 weeks |
| **3: More sources + differentiators** | Enhanced mode (Google Health API), live-workout screen plus HRR-60 (Bluetooth), HRV check if RR is present, context sources, journal + correlations, widget, Energy gauge (if gated in) | Every metric shows its source; switching sources never corrupts a baseline |
| **4: Release** | Play Console: Health apps declaration ("Fitness, wellness and coaching"), Data safety form, privacy policy (also linked from Health Connect), rationale activity + Android 14 alias, encryption at rest. Ships Health Connect-first; Enhanced mode is labelled beta and capped at 100 users until verification plus CASA. Takeout import for Fitbit migrants | Accepted on the Play Store |

**Wear the band from day 1**, even before the app exists. Baselines need 14–30 days, and Health Connect only exposes 30 days of history without the extra permission.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| **The Air's HR or HRV never reaches Health Connect** (a 2026-09-19 PR claims this) | Switch v1 to the Google Health API. Personal build: publish the OAuth client as unverified "In production" to avoid 7-day re-auth (inferred from Google's docs; test on day 8). **Public release would then need OAuth verification plus annual CASA ($500–$4,500, 2–6 weeks).** This is the biggest risk to "publishable for free" |
| HR in Health Connect is too sparse for zone-based strain | Phase 0 decides this; fall back to strain from exercise sessions and steps |
| Google changes what it writes to Health Connect | Per-metric sync log and status cards; the engine re-weights missing inputs |
| Our scores disagree with Google's or WHOOP's | Methodology page with citations; "not medical, not WHOOP's formula" framing |
| Play policy review for health data | Declare only the types we use, one concrete feature per type, no ads, no server |
| Scope creep beyond the one job (food logging, plans, extra scores) | Anything not serving "How am I + what to do" goes to More or is cut (§7). The grounded coach is in scope by user decision (§3.4) |

---

## 7. Decisions

**This table supersedes any earlier section it conflicts with.** Each row is tagged by author: **[U]** is an explicit user decision, **[R]** is research-backed, **[O]** is an orchestrator choice. Precedence: [U] and the §3 principles beat [O] and looser phrasing. Where [U] and a principle collide, [U] sets the form and the principle sets the content (for example, Figma 1:1 governs the look while principle 6 governs what fills each slot).

| Decision | Outcome (2026-09-28) |
|---|---|
| [U] App name | Deferred; not important. Use a working placeholder |
| [O] Stack (delegated by user) | **Flutter** (§4) |
| [O][R] Data sources | **Health Connect is the base.** Add the Google Health API (Enhanced mode), live Bluetooth HR and Health Connect context sources; add Takeout import later. See §2.5 |
| [U] AI coach (2026-09-29) | **Build a grounded coach.** On-device deterministic by default; Claude or Gemini with your own key, opt-in; a verifier on every answer. See §3.4 |
| [U] Precedence rule (user, 2026-09-29) | **Explicit decisions and the research-backed principles beat looser phrasing.** Where a later casual request contradicts a decision in this table, the decision stands and the conflict is noted here |
| [U] Any app (user, 2026-09-29) | **Read every origin in Health Connect**: Google Health / Fitbit, Samsung Health, WHOOP, Oura, Garmin and others. Rules: one persisted origin per metric (never summed or averaged); the baseline is keyed by definition plus origin, so a change of app starts a new segment; the automatic choice switches only after a sustained absence or on user override. Replaces the Fitbit-only origin filter |
| [U] Whose scores (user, 2026-09-29) | **Always our own**, computed from the source's measurements with one formula for every device. Source apps' own scores (WHOOP Recovery, Oura Readiness) aren't shown. The user's loose wording "derived from the sources" is read as "from their measurements", in line with key decision 2 in §1 |
| [U] The one job (user, 2026-09-29) | **"How am I + what to do."** Today leads with a deterministic TodayPlan: the state in plain words, a one-sentence why with numbers, and 0–3 concrete actions (effort range, bedtime, wear or sync). Then the three scores, the Health Monitor vitals, and freshness and calibration. Journal, Live workout, Pulse Age and Coach move to a More area. TodayPlan is the only narrator of the day's state; detail-screen insight cards never restate it |
| [U][R] HRV when the source doesn't share it (2026-09-29) | **Final ladder after researcher and critic review** (research/09 plus 09b; the critic's vetoes are binding).
- **Nightly HRV:** Google Health API deep-sleep RMSSD, then Health Connect sleep-mean RMSSD from any origin (automatic or unknown recording method), then single nightly HC records, then Google Health API daily RMSSD.
- **Morning Bluetooth check** (chest strap with RR intervals, e.g. Polar H10): opt-in behind a flag, stored as its own `hrvMorning` metric. It feeds Recovery only when there's no nightly HRV and at least 10 checks in 14 days. **Not built in v1; the flag is reserved for v1.1.**
- **"Sleeping HR (4 h mean)":** its own metric, standing in for resting HR only when the app never shares one (Samsung, Oura, Ultrahuman, Mi Fitness). Never labelled or stored as resting HR.
- **Floor:** Recovery "without HRV" by default; no Recovery, plus a status card, when HRV, resting HR and sleeping HR are all absent.
- **Vetoed:**
  - WHOOP API: needs a server-side secret, and the terms forbid competing use.
  - Oura API: redundant, since Oura writes HRV to Health Connect.
  - Camera PPG: weak Android evidence and can't be validated here.
  - Overnight BLE RR.
  - Any HRV or "resting HR" estimated from heart rate.
- **Verified:** Samsung writes no HRV, resting HR, respiratory rate or skin temp to Health Connect. |
| [R] Demo data (2026-09-29) | **"Try with sample data" is an explicit choice**, watermarked on every screen. Any real source overrides it, and it's never the silent default once a source is connected (principle 6) |
| [U][O] Google Health UX patterns (2026-09-29) | **Adopt only where they fit the principles; the findings win on any conflict (user rule [U]; the adoption list is [O]).** Amended by the critic review row below. Adopted: "Discuss" from an insight into a chat seeded with its facts; one deterministic insight card per detail screen with feedback and "Why am I seeing this?"; visible memory use; a Coach messages level Off / Basic / Full (Full is opt-in and labelled "AI summary"). Rejected: a Health tab that folds in Trends (the complaints say features were moved); an AI feed on Today; a floating Ask pill; a "Vitals N of M" aggregate; customizable tiles (principle 3 and research/04 §1a). Added a "Show coach" master switch that hides every coach entry point. |
| [U][O] iOS (user, 2026-09-30) | **Planned after Android v1 is in daily use** (sequencing is [O]). Parity plus a home and lock-screen widget, a live-workout Live Activity (lock screen + Dynamic Island) and Siri shortcuts. Flutter stays; builds go through cloud macOS CI to TestFlight, since there is no Mac. Apple Health HRV is SDNN, so it gets its own definition and baseline. Estimate 2.5–3.5 weeks. Details, phases and prerequisites: `IOS_PLAN.md` |
| [U][O] Coach model fallback (user, 2026-09-30) | **When the chosen model fails, the coach falls back instead of showing an error** (the ask is [U]; the chain is [O]). Chain: (1) the next model **from the same provider with the same key**: Gemini 3.8 Flash → 3.5 Flash-Lite; Claude Opus 5.5 → Sonnet 5.5 → Haiku 4.5. This happens only on model-specific failures: the per-model daily quota, 429/503/529 after retries, or model not found. Account-wide failures (invalid key, billing, out of credit) skip straight to step 2. (2) The **on-device answer** (deterministic tools and facts, no network). **Never another provider**: consent covers one provider (§3.4). The whole question restarts on the fallback model; models are never mixed inside one tool loop, because thinking blocks and thought signatures are bound to their model. The verifier runs as usual, and the answer shows which model or on-device path produced it. Setting: "Use a backup model when busy", on by default. Fallback rules: context parity, same reasoning level, skip known-down models. |
| [U][R] More source apps (user, 2026-09-30) | **"Support Samsung Health etc." is met through Health Connect, made honest per app** (research/10 + critic 10b; the critic's vetoes are binding). Build: (1) a **measured-value guard**. MANUAL resting-HR and VO₂max rows never feed scores. UNKNOWN resting HR is flagged when it's constant (≥10 identical days over ≥14) or sporadic, as with Polar Flow's "physical settings" RHR. AUTOMATIC and ACTIVE rows are untouched. This is principle 6, and it fixes a live bug where a constant RHR pinned Recovery. (2) Setup copy from vendor-documented paths only (Samsung "Measure continuously", a Polar line, a WHOOP membership line without tier names). (3) 8 more known apps (Ultrahuman, OHealth, Honor Health, Fastrack, FitCloudPro, Sleep as Android, Wahoo, Health Sync as a relay), with relays attributed as "<device> via <relay>". (4) Sources rows "Shares / Doesn't share / Not used" from observed data, never a "usually shares" list. (5) Corrected per-app test fixtures. **Not built:** Polar BLE SDK (Polar requires Flow to be shut down; no device), Samsung Health Data SDK (developer mode is "not for app users"; release needs a partnership), and any copy that names or recommends the Health Sync relay (paid; routes data through its own cloud, the pattern §2.5 rejects) |
| [U] Codex PR #1 merge (user, 2026-09-30) | **Merge it into a local branch together with our uncommitted work; no push without the user's OK.** Keep the PR's data integrity (durable sync, generation-fenced writes, schema v4 rebuild from raw, algorithm v3), its "missing inputs stay unavailable" rule, its coach history isolation and personal context (combined with model fallback: context parity holds for every model), and its accessibility fixes. Overrides: **the font stays Subway Ticker Grid for now.** Doto (OFL, from the PR) is kept in the repo as the licence-free candidate for publishing but isn't bundled. **The text colours keep the Figma levels**: the PR's flattening of secondary, tertiary and faint to 80% white is reverted, and contrast is fixed only at the spots DESIGN_REVIEW lists. The toolchain scripts respect existing variables and default to D:\dev. The release-signing guard stays; a local sideload build needs an explicit opt-in |
| [U] Figma 1:1 (user, 2026-09-29) | **The UI is a pixel-faithful copy of the user's own Figma widget pack** (app/Widget/**), dark only, fonts Subway Ticker Grid (dot-matrix) plus a matched UI font. 1:1 governs **visual form only**. Every slot shows a measured or derived metric, per principle 6. Tiles whose content can't be filled honestly are relabelled with a measured metric or left out: Stress Level, Wellness Score, Health Alert "Critical", Biological/Fitness Age, "Top 15% for your age", Sleep Quality score, Streak (→ Consistency X of Y days), and glucose, BP, body fat, macros, water, vitamin D and mood. The tile → metric map lives in docs/DESIGN_SYSTEM.md |
| [O][R] Product-critic review (2026-09-29) | **Accepted:**
<ul>
<li>TodayPlan renders first and is the only narrator (the old SummaryCard is removed); it carries a basis (missing inputs), an evening "tonight" phase, strain progress, and a re-learning state; housekeeping moves to the freshness line.</li>
<li>Explicit demo only; nothing is seeded before the choice; a badge on every screen and on coach answers.</li>
<li>Principle-6 cuts: **Pulse Age removed from v1** (it estimated VO₂max from a heart-rate ratio); **no 0–21 strain without heart rate** (show activity facts instead); **max HR from birth year**, asked in onboarding, else the observed maximum, labelled.</li>
<li>The Baevsky "stress" number, the Takeout "Later" row, the phone-steps gap fill (it mixed origins), and **Coach messages "Full"** (the LLM rewrite of cards) are all cut.</li>
<li>Insight-card thumbs are cut (votes went nowhere); Hide and "Why am I seeing this?" stay.</li>
<li>Journal correlations need ≥10 days per group with Holm correction and read "associated with".</li>
<li>"Sleep need" is renamed "sleep target".</li>
<li>VO₂max is labelled as the source's own estimate.</li>
<li>The baseline key includes the device when metadata has it; the app prompts when a new source appears; one freshness line per source.</li>
<li>A "differs from WHOOP's/Oura's own score" note when the origin is WHOOP or Oura.</li>
<li>Settings → Coach is always reachable.</li>
<li>Enhanced mode stays off by default (a named HRV definition, Phase-0 fallback).</li>
<li>Evals add the research/06 hallucination probes through the real verifier, the raw pre-repair unsupported rate, a TodayPlan eval, and non-Fitbit fixtures.</li>
</ul>
**Rejected, with reasons:**
<ul>
<li>Coach off by default: the user asked for AI Q&A [U]. It lives in More, and cloud AI stays opt-in.</li>
<li>Cutting Live workout: live HR is a top pain point (research/04 #4, §2.3) [R]. It degrades gracefully when the band doesn't broadcast, and moves to More.</li>
<li>Cutting ACWR: a differentiator (§2.4) [R]. It stays on Trends, gated on 28 days.</li>
<li>Cutting insight cards entirely: plain-words reads on detail screens are the user's "clearer terms" ask [U]. They stay, deterministic, with Discuss.</li>
</ul> |
