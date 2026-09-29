# OpenStrap/edge — Repo Research (for Fitbit Air app research)

Repo path researched: `.../scratchpad/edge` (local clone, MIT-licensed, WHOOP-focused
Flutter app). BLE/protocol decoding was skipped per instructions — it does not apply to
Fitbit hardware.

**Critical structural fact, read this first:** the actual metric formulas (HRV, sleep
staging, readiness, strain, stress, etc.) do **not** live in this repo. They live in a
sibling package, `openstrap_analytics` (https://github.com/OpenStrap/analytics), pulled
in as a pinned git dependency (`pubspec.yaml:259-497`, pinned to commit
`0441ef9e6fc6d5681c309ce6341911285e829f20`). `edge` only *calls* that package's exported
functions from `lib/compute/derivation_engine.dart` (8,857 lines) and orchestrates I/O
around it. That analytics repo was **not present in this clone** (not cloned, not
vendored, not in `pub cache` here), so formula-level detail below is reconstructed from
(a) the extensive changelog comments edge keeps in `pubspec.yaml` every time it re-pins
analytics, (b) the `MetricSpec` catalogue in `lib/ui2/screens/metric_detail.dart`
(method + citation strings shown to the end user), and (c) call-site comments in
`derivation_engine.dart`/`onehz_pipeline.dart`. Anything not directly quoted from one of
those three sources is marked unverified.

---

## 1. Analytics — every metric, its inputs, and its citation

Source: `lib/ui2/screens/metric_detail.dart:93-367` (`_specs`, a `Map<String,
MetricSpec>` — each entry literally carries a `method:` string and a `citation:`
string shown on the metric's detail screen) cross-referenced with `InputSignal` values
each spec `requires` (defined in `lib/ble/adapters/signals.dart:27-68`).

| Key | What it is | Method (verbatim from repo) | Citation (verbatim) | Requires (raw signal) |
|---|---|---|---|---|
| `resting_hr` | Resting HR | Lowest sustained sleeping HR over the night | "Nocturnal heart-rate minimum; personal baseline, not population" | `hr1Hz` |
| `hrv` | HRV (RMSSD) | RMSSD over the longest artefact-free window during sleep | "Task Force 1996 · Lipponen & Tarvainen 2019" | `rrIntervals` (beat-to-beat) |
| `readiness` | Recovery/readiness | Weighted composite of several inputs, each scored against a personal baseline | "Plews 2013 (lnRMSSD) · Hopkins smallest-worthwhile-change gate" | composite (rrIntervals, hr1Hz, accel1Hz, skinTempRaw, etc.) |
| `resp_rate` | Respiratory rate | Recovered from respiratory sinus arrhythmia in beat intervals | "Pimentel 2017" | `rrIntervals` |
| `sleep` | Total sleep time | Wrist z-angle sleep window, staged by [a stager] | "van Hees 2015 · Webster / Cole–Kripke rescoring" | `accel1Hz` + `hr1Hz` |
| `efficiency` | Sleep efficiency | Time asleep ÷ time in bed | "AASM sleep-accounting definitions" | `accel1Hz` + `hr1Hz` |
| `deep` | Deep sleep | Low-confidence overlay — "a wrist sensor cannot see slow-wave [sleep directly]" | "Cole–Kripke wake spine + HRV overlay" | `accel1Hz` + `hr1Hz` |
| `rem` | REM sleep | Staged from beat-timing variability + movement | "Webster / Cole–Kripke rescoring + HRV staging" | `accel1Hz` + `hr1Hz` |
| `steps` | Steps | "Counted, never modelled" — needs a gait-capable accel signal | "AN-2554 pedometer · phone pedometer (HealthKit/Health Connect)" | `accelHighRate` (band) or phone pedometer |
| `calories` | Active calories | HR-to-energy regression over the waking span, anchored on BMR | "Keytel 2005 · Harris–Benedict/Mifflin BMR floor" | `hr1Hz` |
| `strain` | Strain (0–21) | Cardiovascular load over the day, log-compressed onto 0–21 | "Banister TRIMP family · log-compressed" | `hr1Hz` |
| `trimp` | TRIMP | Time-in-zone weighted by [zone factor] | "Banister 1975 · Edwards 1993" | `hr1Hz` |
| `stress` | Stress index | Baevsky stress index over a resting window (histogram measure of beat-interval clustering); "deliberately no fallback when the resting window is missing" | "Baevsky 2008" | `rrIntervals` |
| `dip` | Nocturnal HR dip | How far sleeping HR falls below waking average | "Nocturnal dipping literature; personal baseline" | `hr1Hz` |
| `hrr` | Heart-rate recovery | HR drop over 60 s after a bout ends | "Cole 1999 (HRR-60)" | `hr1Hz` |
| `lf_hf` | LF/HF ratio | Ratio of low-/high-frequency power in beat-interval [spectrum] | "Laguna 1998 · Bigger 1992" | `rrIntervals` |
| `hrv_cv` | HRV coefficient of variation | Night-to-night CV of RMSSD | "Within-user dispersion" | `rrIntervals` |
| `brv` | Breathing-rate variability | CV of per-window respiratory rate across the night | "Within-user dispersion" | `rrIntervals` |
| `nap_min` | Nap minutes | Same wrist-window detector as `sleep`, applied outside the main night | "van Hees 2015 window detection + nocturnal HR dip" | `accel1Hz` + `hr1Hz` |
| `active_min` | Active minutes | Minutes above a personal, dynamic-range movement floor | "ENMO over a personal dynamic-range floor" | `accel1Hz` |
| `wear` | Wear time | Minutes with a band record present (not HR validity) | "Record-presence, not heart-rate validity" | `accel1Hz` |
| `skin_temp` | Skin temperature | Night's mean raw ADC reading, expressed as distance from personal baseline | "Relative only — uncalibrated ADC" | `skinTempRaw` |

Additional metrics named only in `pubspec.yaml`'s analytics-repin changelog (formula
detail unverified — analytics source not present in this clone):
- `vo2maxEstimate` / `vo2maxSubmaxEstimate` — VO2max clinical estimate (`lib/src/onehz/clinical/vo2max.dart`); *removed* from the pipeline at analytics commit `98d42b6` ("edge stopped calling those two before this pin, so nothing loses a value" — `pubspec.yaml:335-341`), then a submax variant added back later (`pubspec.yaml:435-443`). **Edge does not currently surface VO2max in the UI** per that note.
- `physiologicalAge` — also removed at the same commit, same reason.
- `cvhrApneaScreen` / `CvhrNight` / `CvhrDistribution` — a cardiovascular-HR-based apnea-adjacent screen; explicitly **not shown as a diagnosis** — see §2's "banned strings" table (r≈0.84 correlation to AHI is called out as "nowhere near enough to put one person in a severity category," `lib/ui2/README.md:466-475`).
- `alertnessForecast` — an alertness/circadian forecast (`lib/src/onehz/human/alertness_forecast.dart`).
- `illness_cusum`, `overreaching_conjunction`, `readiness_glassbox`, `readiness_composite`, `temp_circadian` (interdaily stability / intradaily variability), `hrRecovery` (fitted-tau HRR), `sessionHrCeiling`, `hr_ceiling_bpm`, `journalNumericCorrelations` (Spearman ρ + Theil-Sen slope, Benjamini-Hochberg corrected), Kruskal-Wallis weekday-effect test, `nocturnalRhr`, `dailyActiveMinutes` (replaced an older `dailyStepEstimate`), `estimateBoutCalories` (workout calories with a 150 s HR-sample-gap cap), `hrv_freq.dart` Welch-segmented LF/HF/VLF/ULF (gated on segment time-completeness, not just beat count), `stress_si.dart` gap-aware Baevsky windowing.
- **SpO2 is explicitly and permanently out of scope** — `lib/ui2/README.md:335-339, 437-439`: "SpO2, ODI and anything apnea-shaped… Refused outright — a capability this app does not produce has no entry, no card and no key." No SpO2 metric exists anywhere in the UI catalogue, confirmed by its absence from `metric_detail.dart`'s spec map.
- No skin-temperature-based fever/illness *score* is surfaced as a diagnosis; it feeds `illness_cusum`/circadian analytics only.

### Input-granularity requirement (the crux of the Fitbit-swap question)

`lib/ble/adapters/signals.dart` defines the whole input vocabulary the analytics engine
consumes — 8 raw classes (I1–I8) plus one non-raw class:

- **I1 `rrIntervals`** — "the single most valuable thing a band can emit: nine
  analytics files take interval lists directly" (line 28-30). Feeds `hrv`, `stress`,
  `resp_rate`, `lf_hf`, `hrv_cv`, `brv`, and half of `readiness`.
- **I2 `hr1Hz`** — dense, ~1 sample/second HR. Feeds `resting_hr`, `calories`,
  `strain`, `trimp`, `dip`, `hrr`, and half of `sleep`/`deep`/`rem` staging.
- **I3 `hrSparse`** — coarser/irregular-cadence HR; metrics that need `hr1Hz`
  *abstain* rather than stretch a sparse window over it (comment at line 36-38).
- **I4 `accel1Hz`** — ~1 Hz tri-axial accel; sleep staging + wear detection.
- **I5 `accelHighRate`** — ~100 Hz accel; "the only path to a real step count."
- **I6/I7 `ppgGreen` / `ppgRedIr`** — raw PPG ADC counts (I7 = relative SpO2 *inputs*
  only — "an absolute saturation is a calibration claim no adapter may make," line 52-53).
- **I8 `skinTempRaw`** — raw uncalibrated skin-temp ADC.
- **`vendorScalars`** (not raw) — "Numbers the band computed itself — its RMSSD, its
  sleep score. These land in `observation`, are attributed to the vendor, and are
  **never an input to one of our derivations and never enter a baseline**" (lines 59-62).

**This is the load-bearing fact for a Fitbit Air port.** Google Health Connect / Apple
HealthKit expose exactly the shape of data this codebase calls `vendorScalars` and
`hrSparse`/nightly-summary records — pre-computed sleep stages, a nightly HRV (RMSSD)
number, resting HR, steps, active calories, SpO2 average, skin-temp *delta* (if the OEM
writes it) — not `rrIntervals`, not `accel1Hz`, not `ppgRedIr`. By Edge's own explicit
rule, vendor scalars **cannot** be fed into its from-scratch HRV/stress/respiratory-
rate/sleep-staging/strain math; they can only be displayed as attributed "observations."
See §6 for what that means concretely per metric.

There is also direct evidence Edge itself has not solved "lower-fidelity device →
recovery/strain" even for its *best* non-WHOOP case: `db.dart:108` —
`const Set<String> kDerivableSources = <String>{};` — **is empty**. Despite ~25 BLE
adapters existing (Oura, Garmin, Polar H10, generic BLE HRM, Mi Band, Ultrahuman, rings,
etc., see `lib/ble/adapters/_registry.dart`), **none of them feed the derivation engine
today** — every one of their source files carries a comment like "`kDerivableSources`
does not contain it… this session holds a link and archives bytes, it [doesn't derive]"
(e.g. `lib/ble/adapters/oura.dart:6`, `garmin.dart:7`, `ring11m.dart:9`). Even a generic
BLE heart-rate strap that emits **true `rrIntervals`** is BLE-paired for workouts today
but explicitly **not** wired into recovery/strain yet (README.md:116-117: "Feeding it
into recovery/strain is on the roadmap"). Only the WHOOP gen4/gen5 family is calibrated
(`calibrationFor(_metric_, DeviceFamily)` in the analytics package returns real constants
only for WHOOP; `null`/`unknownFamilyNote(...)` otherwise — `derivation_engine.dart`
references at lines 1020, 6426, 6582, 7139, 7317; `hr_max.dart:48`).

---

## 2. Screens and visualization

Screenshots reviewed directly: `screenshots/today.png`, `sleep.png`, `heart.png`,
`stress.png`, `body.png`, `recap.png`, `workouts.png`, `breathing.png`.

Design system: `lib/ui2/` (66 files), documented in `lib/ui2/README.md`. Dark theme by
default (screenshots all show near-black backgrounds), one accent per domain
(`C.domHome/domHealth/domFood/domMove/domMind`), coral/orange as the primary "headline
number" accent, green = good/low-risk, purple = REM, tan/orange = light sleep, teal =
steps. Bottom nav is a 5-tab pill bar with icons for **Today (sun), Sleep (moon), Heart,
Body (person), Workouts (running figure)** — matches `ShellDomain { home, health,
nutrition, workout, wellness }` in `app_shell.dart` — "there is no sixth tab" (README
line 412).

**Today** (`today.png`): a narrative insight card up top ("Good Morning — You slept 412
minutes with perfect efficiency but your readiness is low at 30 — tap for the
breakdown"), two small pill chips (Stress 22, Sleep 6h52m), a large center **ring gauge**
for Readiness (37, colored, with a text verdict "Run easy" under it), two more pill chips
either side (Heart 60, Strain 9.0), then a 2×2 grid of `SignalCard`s (HRV with a mini
down-trend sparkline, Resting HR, Calories, Steps).

**Sleep** (`sleep.png`): tab switcher (Today/Week/Month/3M), a **hypnogram** bar chart
(`Hypnogram` painter, awake/REM/light/deep lanes, x-axis = clock time e.g. 02:33→09:25),
then percentage breakdown bars for REM/Light/Deep (colored bars + % + duration), then a
"Cycles" card (count, ~duration/cycle, plus a **wavy line chart** of nocturnal HR — this
is `NightStack`, tagged "BETA").

**Heart**: Live Heart Rate big-number card, a "Live HRV spot check" CTA card (60-second
on-demand reading), a Recovery card (ring/verdict "37/100 — HRV-based recovery"), then
HRV and Resting HR side-by-side stat tiles, with a "dip %" mention on Sleeping HR.

**Stress**: a big **gauge/arc ring** (partial circle, not full ring) showing "22 · LOW,"
a "Low" `Pill`, an insight sentence ("Your system is settled — a good day to take on
load"), a `BigButton` CTA ("Calm yourself" → launches breathing), then 3 stat tiles:
Stress Index (Baevsky, raw value shown, e.g. 43.33), LF/HF balance, RMSSD.

**Body**: tab switcher, a "Strain Coach" `ActionCard`-style block with a target-range
number ("3–6 target strain today," tagged "RECOVER"), a Day Strain ring, a "Training
load" table (Active/Total calories, Steps est.), and a teased "Fitness" section
("Building your fitness picture — VO2max needs a hard, near-max effort to estimate").

**Workouts**: empty state is a `StatusCard`-shaped block with an icon, "No workouts,"
"Tap Start, or an effort will be auto-detected," and a "Start a workout" button — matches
the documented always-honest-empty-state design rule.

**Recap** (shareable): a card with app branding, week range, Avg Strain headline number
plus a **row of colored rounded-pill bars** (a bar-chart alternative that reads as
"blobs," one per day) for strain, an inset narrative sentence ("You averaged 6h27m of
sleep a night"), 4 stat tiles (Resting HR, Sleep/Night, Calories, Steps) each with a tiny
inline dot/bar trend, and a full-width "Share my recap" button — this is rendered to an
image and pushed to the OS share sheet (`share_plus`).

**Breathing** (guided coherence session): full-screen minimal UI — a single breathing
circle (green stroke, "Inhale" label, expands/contracts) with a live-updating "Coherence
Score" (McCraty & Zayas 2014 cardiac coherence, per `local_repository.dart:330-332`) and
a Stop Session button. This is the `BreathRing` painter driven by caller-owned time, not
an internal `.repeat()` (per the ui2 rules).

Screens not screenshotted but present in `lib/ui2/screens/`: `readiness_detail.dart`,
`driver_breakdown.dart` (what's driving today's readiness/strain), `circadian_detail.dart`,
`cycle_screen.dart` (menstrual cycle), `day_steps.dart`, `day_timeline.dart`, `ecg.dart`
+ `beats.dart` (Poincaré beat-interval plot), `findings_log.dart`, `investigate.dart`,
`journal_compose.dart`, `log_food.dart` + `nutrition_screen.dart` (+ barcode scanning),
`log_workout.dart`, `month_grid.dart`, `naps.dart`, `rough_night.dart`, `what_changed.dart`
(cross-version diffing), `ai_briefing.dart` + `coach.dart`/`coach_figures.dart` (BYOK AI
chat), `custom_journal_field_sheet.dart`, `metric_detail.dart` (the generic drill-down
every `MetricSpec` routes to), `scan_barcode.dart`, `start_card.dart`.

**Charting/painting**: no third-party chart library is actually used for the custom
visual language — `fl_chart: ^0.69.2` is in `pubspec.yaml` but flagged "for the future
server-analytics view" (comment at line 552-553; unclear if load-bearing today). The real
chart stack is **hand-rolled `CustomPainter`s** in `lib/ui2/charts.dart` +
`lib/ui2/paint_activity.dart`: `LineChart`, `Bars`, `Ring`, `MacroRing`, `Hypnogram`,
`ZoneBar`, `Actogram`, `HeatMap`, `Spectrum` (LF/HF power), `NightStack`, plus activity
painters `RouteMap`, `MuscleMap`, `Elevation`, `PowerCurve`, `LapBars`, `BreathRing`,
`MovementMap`, `IntervalLadder`, `PaceBar`.

**Notably well-designed, worth porting even without WHOOP hardware:**
1. **The absence/honesty contract** — `StatusCard`/`StatusCard.forMetric` is "the only
   way to render a missing value": what's missing → why (from the metric's own machine
   note, never a guessed reason) → what fixes it, and a fix button is refused if it
   wouldn't actually change the outcome (`lib/ui2/README.md:165-188`). This is a UX
   pattern, not WHOOP-specific, and maps directly onto "Google Health gave a thin/absent
   summary for today."
2. **`ChartFrame`** — forces every chart to carry a real y-axis, x-labels that describe
   the actual window, a legend, and a spoken-equivalent `series:` string for
   accessibility; a painter alone is explicitly "not information" (README:296-398).
3. **Trend arrows, not sparkline squiggles**, on list rows — a direction glyph gated on a
   real statistical rule (last 3 values clear ≥0.5 SD of the prior 14; <7 data points →
   nothing shown) rather than a decorative micro-chart nobody can read (README:199-208).
4. **Contrast is a CI gate**, not a design suggestion — `ui2_contrast_test.dart` sweeps
   every accent × surface × theme at a 4.5:1 floor, including painter output.
5. **`Consistency`** ("18 of 24 days") deliberately replaces streaks — "not a streak…
   never resets to zero" (README:224-229) — a healthier engagement pattern than WHOOP's
   own streak mechanics.

---

## 3. Architecture

- **State management**: `provider: ^6.1.2`, single `AppState extends ChangeNotifier`
  (`lib/state/app_state.dart`, 7,315 lines) — "the single ChangeNotifier the UI
  listens to. Orchestrates the BLE↔DB↔UI [flow]" (AGENTS.md:38). This is the
  highest-churn file in the repo (30 bug-fix commits per AGENTS.md's own hotspot count)
  — a straight port would inherit a lot of BLE-specific state that a Fitbit-Air port
  wouldn't need, so this file is a rewrite target, not a reuse target.
- **Local DB**: `sqflite` (SQLite) via `lib/data/db.dart` (11,118 lines). Durable raw
  ledger tables: `decoded_onehz` (1 Hz, `UNIQUE(rec_ts)`, INSERT-OR-REPLACE),
  `decoded_rr` (beats), `raw_archive` (never pruned), `raw_records`, `events`/
  `band_events`. Derived output: **versioned, immutable** `day_result` (PK
  `day_id, algo_version`) and `metric_series` (PK `date, key`, REPLACE) — a schema
  designed so an algorithm-version bump (`kAlgoVersion` in `derivation_engine.dart`)
  never silently overwrites old results (AGENTS.md §2–3).
- **Data-source abstraction — yes, a real device-agnostic seam exists, in two layers:**
  1. `LocalRepository` (`lib/data/local_repository.dart`, 336 lines, all-abstract) is
     the contract **every UI screen** consumes — it is pure Dart, has **zero references
     to BLE, HTTP, or any device type**, and every method just returns
     `Map<String,dynamic>`/typed records read from `db.dart` + `openstrap_analytics`
     output. This is exactly the seam a Health-Connect-backed implementation would
     plug into — the screens would not need to change at all if a new
     `LocalRepositoryImpl` populated the same `day_result`/`metric_series` tables.
  2. `BandAdapter` (`lib/ble/adapters/adapter.dart`) + `InputSignal` (`signals.dart`) is
     the **device-to-signal** seam — one `run(BandLink) → BandEvent` per device,
     declaring which of the 8 raw signal classes it emits, so "blast radius of a new
     metric is one analytics function and one card, zero adapters" (signals.dart:1-22).
     This layer is BLE/GATT-shaped (a `BandLink` write/notify session) and **does not
     fit** a Health Connect/HealthKit polling source, which has no GATT session, no
     handshake, and delivers already-aggregated records, not a byte stream. A Fitbit
     source would bypass this layer entirely and write straight into the same
     `decoded_onehz`/`observation` DB tables the BLE path writes into (see §6).
- **Background sync**: Android — `workmanager` (`WorkManager`) 15-minute watchdog +
  `CompanionDeviceManager` re-attach; foreground service keeps the BLE link alive.
  iOS — `BGTaskScheduler` background processing task + a lighter refresh task, "app-killed
  heavy compute is opportunistic… never guaranteed" (comment in
  `lib/compute/background_derivation.dart`), plus a separate restore `CBCentralManager`
  that relaunches the app on reconnect. None of this BLE-specific machinery is needed
  for a Health Connect source (Health Connect polling is not power/connection
  sensitive the way BLE is), but the **WorkManager periodic-poll pattern itself** is
  directly reusable for "poll Health Connect every N minutes."
- **Notifications**: single emitter, `NotificationCenter.emit` (`lib/notify/
  notification_center.dart`) + `fired_keys.dart` persistent fire-once guard — a pattern
  worth keeping (AGENTS.md invariant #8, and §4.6 documents how often bypassing this
  single path caused duplicate-fire bugs).
- **Localization**: `flutter_localizations` + `intl`, `.arb`-based
  (`lib/l10n/app_{en,de,es,fr,hi,zh}.arb` — 6 locales), generated via `l10n.yaml`
  (`arb-dir: lib/l10n`, template `app_en.arb`).
- **Testing**: 363 test files under `test/`, not flat — `test/adapters/` (per-device BLE
  protocol tests, WHOOP/Oura/Garmin/etc. — skip these, BLE-specific), `test/ui2/`
  (design-system unit tests), plus root-level tests named for the exact regression they
  pin (e.g. `readiness_flash_test`, `readiness_freeze_test`,
  `readiness_baseline_pollution_test`). Golden-image tests:
  `ui2_golden_test.dart`, `ui2_home_health_golden_test.dart`,
  `ui2_onboarding_profile_golden_test.dart` (rendered at 1.0/1.4/2.0/3.0/3.1× text scale,
  overflow-fails the build) plus dedicated `ui2_contrast_test.dart` /
  `zone_contrast_test.dart` for WCAG-style 4.5:1 contrast sweeps. CI
  (`.github/workflows/test.yml`) runs `flutter analyze` + `flutter test` on every PR.
- **AI assistant**: `lib/ai/` + `lib/coach/` — a "deterministic coach" that runs
  read-only SQL over an allow-listed set of `v_*` SQLite views (never raw tables) behind
  a deny-list guard (AGENTS.md invariant #13; tests: `coach_sql_guard_test.dart`,
  `coach_sql_guard_adversarial_test.dart`), plus a BYOK (bring-your-own-key) LLM path
  for briefings/journal AI — user supplies their own API key, prompts include health
  data, sent directly to the user's chosen provider (README.md:216-219).

---

## 4. Dependencies of note (`pubspec.yaml`)

- **BLE**: `flutter_blue_plus ^1.36.8` — irrelevant to a Fitbit Air port.
- **DB**: `sqflite ^2.4.1` (+ `sqflite_common_ffi` for desktop test runs), `path`,
  `path_provider`.
- **Charts**: `fl_chart ^0.69.2` declared but the actual UI is hand-rolled
  `CustomPainter`s (see §2) — `fl_chart` appears to be lightly used/vestigial.
- **Health platform bridge**: `health ^12.2.1` (HealthKit + Health Connect wrapper —
  **this is the exact package a Fitbit-Air integration would also use**), plus
  `android_intent_plus` (to deep-link into the Health Connect settings screen when its
  own permission dialog is unavailable).
- **GPS/maps**: `flutter_map ^7.0.2` + `latlong2` + `geolocator`, tiles from CARTO (not
  Google/Mapbox, no API key) for outdoor workout routes.
- **Crypto**: `pointycastle` (AES-256-GCM + PBKDF2 for encrypted local backup),
  `crypto` (SHA1, for one specific device's auth challenge — BLE-specific).
- **Background work**: `workmanager ^0.9.0`.
- **Notifications**: `flutter_local_notifications ^18.0.1` + `timezone`/
  `flutter_timezone` for correct wall-clock scheduling.
- **Widgets/Live Activity**: `home_widget ^0.6.0` (App-Group snapshot bridge to
  WidgetKit/Android widgets).
- **Telemetry (opt-in, off by default)**: `firebase_core/_crashlytics/_performance/
  _analytics`, `device_info_plus`, `battery_plus`, `connectivity_plus`.
- **Barcode/food log**: `mobile_scanner ^7.3.1` (bundled ML Kit model, no Play Services
  dependency — relevant since this app ships via sideload/GitHub Releases, not Play
  Store).
- **Icons/fonts**: single icon family `lucide_icons_flutter` (chosen deliberately to
  replace a "five-pack mix" that made screens feel inconsistent — pubspec.yaml:24-29);
  bundled `Manrope` + `Barlow Condensed` fonts (not fetched at runtime, for
  offline-first correctness and to avoid a `google_fonts` HTTP call before the consent
  screen is shown — pubspec.yaml:717-722).
- **Sibling packages**: `openstrap_protocol` and `openstrap_analytics`, both pulled via
  `git:` + pinned commit SHA (never a floating branch ref — a whole invariant, #6 in
  AGENTS.md, exists because a floating ref once shipped an unreviewed ANR regression).

---

## 5. License and attribution

- **License**: MIT (`LICENSE`, copyright OpenStrap, 2026). Permissive — reuse, fork, and
  modify are all allowed, including commercially, with attribution (retain the copyright
  notice) and no warranty.
- **NOTICE.md**: states the project is independent, not affiliated with/sponsored by/
  endorsed by WHOOP, Inc.; no WHOOP source/binaries/firmware/assets are included; the
  Bluetooth support was independently reverse-engineered. For a Fitbit-Air-derived fork,
  the equivalent posture is straightforward (Google Health data via published/public
  APIs — Health Connect/HealthKit are Google's/Apple's own public SDKs, not a
  reverse-engineered protocol), but the *fork itself* should carry an equivalent
  not-affiliated-with-Google/Fitbit disclaimer and must keep the MIT license text and
  copyright notice per the license's terms.
- No `NOTICE.md`-style dependency attribution list beyond the WHOOP disclaimer; no
  copyleft dependencies observed in `pubspec.yaml` (all permissive: MIT/BSD/Apache-style
  packages plus the OFL-licensed bundled fonts, noted at pubspec.yaml:722).

---

## 6. Reuse verdict — forking Edge for a Fitbit Air (Health Connect / HealthKit) source

**Bottom line: the UI/UX layer and the local-storage/read contract are highly reusable;
the actual differentiated analytics (the reason someone would want "Edge" instead of the
stock Google Health app) are mostly NOT reusable, because they require raw per-second/
per-beat signals that Health Connect and HealthKit do not expose from Fitbit hardware.**
This is not a guess — it follows directly from Edge's own documented signal model
(`InputSignal`/`vendorScalars`, §1 above) and from the fact that Edge has not even wired
its *easiest* non-WHOOP case (a plain BLE HR strap emitting real `rrIntervals`) into
recovery/strain yet (`kDerivableSources` is empty; README.md:116-117).

**Keep, largely as-is:**
- `lib/ui2/*` — the whole design system (theme, grammar/components, painters, the 5-tab
  shell). This is device-agnostic already; it only consumes `Metric`/`MetricSpec`
  shapes and `LocalRepository` output, never a device type.
- `lib/data/local_repository.dart` (the abstract contract) and the general shape of
  `lib/data/db.dart`'s derived tables (`day_result`, `metric_series`) — a
  Health-Connect-backed app should adopt the same "immutable, algo-versioned derived
  row + separate raw ledger" pattern, since it's what makes recomputation/versioning
  safe.
- `lib/models/metric.dart` — the `Metric{value, unit, confidence, tier, note}` envelope
  and the "never fabricate, absence has a machine-readable reason" convention. This
  maps *better* onto a Health-Connect source than onto BLE, since Health Connect
  frequently has permission-denied/no-data cases that need exactly this kind of honest
  abstention.
- The **notification single-emitter** and **background WorkManager poll** patterns
  (structure, not code) — trivially adaptable to "poll Health Connect on a timer."
- The **BYOK AI coach architecture** (allow-listed SQL views + deny-list guard) is
  fully device-agnostic and directly portable.
- l10n scaffolding, golden/contrast test approach, MIT license terms.

**Rewrite (structure reusable, content is not):**
- `LocalRepositoryImpl` — same interface, entirely new implementation, because it will
  read Health Connect/HealthKit records (via the already-present `health` package)
  instead of WHOOP `Substrate`/`day_result` rows the analytics pipeline wrote.
- `AppState` — needs a Health-Connect-appropriate rewrite (no BLE connection
  state machine, no drain/ACK state, but still "one ChangeNotifier orchestrates
  read → store → notify UI").
- The whole **BLE layer** (`lib/ble/`) and **protocol package** — drop entirely; not
  applicable to Fitbit Air (per your instructions, also out of scope to research).

**Drop / cannot be ported at all in its current form:**
- `lib/compute/derivation_engine.dart`, `onehz_pipeline.dart`, `crossday_pipeline.dart`,
  `substrate.dart` and the `openstrap_analytics` package they call — these are all
  written against **per-second HR, per-beat RR intervals, per-second accelerometer, and
  raw PPG/skin-temp ADC counts**, none of which Health Connect or HealthKit deliver from
  Fitbit Air (Fitbit's own on-device firmware does the PPG/accel processing and only
  ever publishes already-derived summaries: nightly RMSSD, sleep *stages* (not raw
  accel), resting HR, an SpO2 nightly average, steps, active-energy, and — if Google
  changes policy — Fitbit's own readiness score, none of which is a raw signal). Per
  Edge's own `vendorScalars` rule, none of these values may legally (by Edge's own
  design contract, not a real law) feed its derivation math or its rolling baselines —
  they can only be shown as attributed "observations," a strictly weaker category
  the codebase already has a table for (`observation`, populated via
  `LocalDb.putObservations`).
- Concretely, per metric in §1's table: **`hrv`, `stress`, `resp_rate`, `lf_hf`,
  `hrv_cv`, `brv`, `deep`/`rem` staging** all require `rrIntervals` this source will not
  have (Health Connect's `HeartRateVariabilityRmssdRecord`, if present at all, is
  already a nightly scalar, not a beat list) — **cannot be recomputed, can only be
  displayed as the vendor's own number.** `resting_hr`, `calories`, `strain`, `trimp`,
  `dip`, `hrr` need `hr1Hz` — Health Connect's `HeartRateRecord` sample density from
  Fitbit is **unverified** in this research (need to check empirically what interval
  Fitbit actually writes; if it's every few seconds during workouts but sparse
  otherwise, these degrade to low-confidence/estimate tier at best). `sleep`/
  `efficiency`/`nap_min`/`active_min`/`wear` need `accel1Hz`, which Health Connect does
  not expose raw at all — these can only be taken as Fitbit's own pre-staged
  `SleepSessionRecord`/`SleepStageRecord`, i.e. displayed, not recomputed.
  `skin_temp` needs raw ADC counts — Health Connect's `SkinTemperatureRecord` (if
  populated) is likely already a delta-from-baseline, again a vendor scalar.
  `steps` is the one metric Health Connect handles natively and well
  (`StepsRecord`), matching Edge's own citation ("phone pedometer (HealthKit/Health
  Connect)" is already one of the two sources Edge cites for this metric today).

**Practical recommendation:** fork `lib/ui2/` + the `Metric`/`LocalRepository`
contracts + the DB versioning pattern wholesale; write a new, much smaller
`HealthConnectRepository` that reads Health Connect/HealthKit records directly and
maps Fitbit's own pre-computed scores into the `Metric` envelope at `tier:
MetricTier.relative` or `estimate` (attributed to Fitbit, per the `vendorScalars`
precedent) rather than pretending to recompute WHOOP-grade HRV/stress/sleep-staging
math Google's API doesn't give raw data for. The value-add over stock Google Health
would then be almost entirely in **presentation** (the honest-absence UX, the ring/
gauge/hypnogram visual language, trend arrows, weekly recap, journal+correlations,
BYOK AI coach over the user's own Health Connect history) rather than in novel
analytics — which is a legitimate and still-substantial reuse case, just a different
one than "port WHOOP's math."
