# 09b: Veto review of the HRV workaround proposal (research/09)

**Date:** 2026-09-29 · **Status:** critique only; no app code written · **Reviews:** `research/09-hrv-workarounds.md` (the revised version, including the per-app table and §5 camera) · **Decides:** which of 09's rungs ship, and in what order

**Veto criteria:**
- (a) unverified, where the decision depends on it
- (b) invented under principle 6
- (c) untestable here (emulator plus fixtures only; no WHOOP, Oura, Samsung or strap). Such a path survives only behind a flag, with fixture tests, and only if it's allowed on the other grounds
- (d) needs a server or an embedded secret
- (e) against a vendor's terms
- (f) low value for its complexity under "one job"

**Labels:**
- **V-official:** I read the primary page or paper abstract myself this pass.
- **V-code:** I read it in our source.
- **Community**
- **Unverified**

---

## 0. Verdict in one screen

- **Ship:**
  - nightly HRV from any Health Connect origin (N2 and N3 below);
  - the "without HRV" floor;
  - a **Sleeping HR (4 h mean)** input, as its **own metric**, never written into `restingHr`, used in Recovery only for origins that write no resting HR.
- **Behind a flag:** the BLE morning check. It's a separate metric and a separate tile. It feeds Recovery only under the stability rule (§6).
- **Veto:**
  - the WHOOP API rung (0e);
  - the camera rung (1b);
  - the full-night-HR fallback;
  - overnight BLE capture, which stays "later".
- **Samsung:** Recovery from sleep plus sleeping HR, labelled, **only when Samsung's HR density passes the gate**. Otherwise no Recovery, with a status card whose first fix is Samsung's own "Measure continuously" setting.
- **09 has a blocker of its own:** Rung 3 as written would put the 4-h mean into `DayRecord.restingHr`. From there it reaches Strain, Health Monitor, Coach and export as "Resting HR". That's principle 6 (b). Fixed in §3.
- **09 also understates P1:**
  - live ingest still keeps **only** the Fitbit origin (`hc_mapper.dart:3, 81, 94`), so "Any app" isn't implemented;
  - the resolver groups by `SourceKind` only, so just removing that filter would pool apps (§8).

---

## 1. Decision-critical claims, re-verified

| Claim in 09 | Result | Source |
|---|---|---|
| Samsung's Health Connect table has no HRV, RHR, respiratory rate or skin temp | **True.** 18 rows (09 says 19). Has HR, sleep, SpO₂ and exercise. The table has **no read/write column**, so it defines the *sync scope*, not "writes". Published 2025-02-18. It adds "A synchronized data scope can be changed depending on the Samsung Health version" | V-official https://developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect ; FAQ lists only "steps and exercise, heart rate, and sleep" https://developer.samsung.com/health/health-connect-faq.html |
| Corroboration | open-wearables issue (2026-09-25): "Samsung Health does not write those record types to Health Connect", with `avg_hrv_rmssd_ms: null` every night | Community https://github.com/the-momentum/open-wearables/issues/1723 |
| Samsung HR sampling | Samsung offers "Measures continuously", "Every 10 mins while still" and "Manual measurement only". The page names no default. **The 10-minute mode fails a 5-minute density gate** | V-official https://www.samsung.com/us/support/answer/ANS10003311/ |
| WHOOP needs a server-side secret | **True.** The secret "should only be used server side and should never be exposed in a client, web, or mobile application". The refresh call sends `client_secret`. PKCE isn't mentioned. Discovery lists `none` and `implicit` but no `code_challenge_methods_supported` | V-official https://developer.whoop.com/docs/developing/getting-started/ ; https://developer.whoop.com/docs/developing/oauth/ ; https://api.prod.whoop.com/oauth/.well-known/openid-configuration |
| WHOOP terms | **True.** Effective 2026-10-06 (a future date; the version in force today wasn't read). Forbids using API materials "to compete, directly or indirectly, with WHOOP". Forbids "permanent copies of WHOOP Data" and caches kept longer than the cache header. "Developer credentials may not be embedded in open-source projects." | V-official https://developer.whoop.com/api-terms-of-use/ |
| Oura needs a secret for the code flow | **True.** `client_secret` is "Required if not using Basic Authorization", and Basic auth carries the secret too. The implicit flow has 30-day tokens and no refresh | V-official https://cloud.ouraring.com/docs/authentication |
| Oura terms | **True.** Nothing that "competes with or merely replicates those of Oura" (Scope of Agreement). API data "may not be stored or retained beyond the duration strictly necessary" (§3(m)). Effective 2026-06-08 | V-official https://cloud.ouraring.com/legal/api-agreement |
| Oura writes HRV to Health Connect | **True.** Export list: "Heart rate, Heart rate variability", sleep and activity. **No RHR, respiratory rate, SpO₂ or temperature.** Updated 2026-08-19 | V-official https://support.ouraring.com/hc/en-us/articles/10786105824531 |
| Nuuttila 2022 supports a "4 h sleeping HR" | **Partly.** 23 recreational runners, measured before and after a 3000-m maximal test, plus reliability over 15 runners × 2 nights. 4H = "a 4-hour (4H) segment starting 30 minutes after going to sleep". HR ICC .97–.98. HR rose after the test "only in 4H and FULL", and more in 4H. **What it supports:** a reliable, load-sensitive nocturnal HR marker in runners. **What it doesn't:** RHR substitution, use in a composite score, non-athletes, or another vendor's sampling. The recording device isn't in the abstract (full text 403) | V-official (abstract) https://doi.org/10.1123/ijspp.2022-0145 via Europe PMC |
| Nuuttila 2024 | 24 runners, **Polar Vantage V2 wrist PPG, "consecutive 5-min averages"**. Sleep4h HR within-person CV **6.6 ± 2.2 %** (09's "6.0–8.3 %" is the range across all nocturnal segments). The overload response in Sleep4h HR correlated with the 3000-m change (r = 0.63), and LnRMSSD at r = −0.50. There's no test of the difference, so "better than LnRMSSD" overstates it. Key for §6: nocturnal and morning responses "were not similarly aligned, especially in LnRMSSD" | V-official (full text, PMC11541970) https://doi.org/10.1186/s40798-024-00779-5 |
| Camera PPG, Plews 2017 | 29 healthy adults, 5 min, guided and normal breathing. TEE CV 6.35 % vs ECG, differences "trivial". 09 says the phone was an iPhone; I didn't re-check that in the full text | V-official (abstract) https://pubmed.ncbi.nlm.nih.gov/28290720/ |
| HRV4Training on Android | Its FAQ says "most phones released in the past few years should work fine" and cites no Android paper. 09's own table: Peng 2015 (Android, unfixed 20–30 fps) "not in acceptable agreement"; Johansson 2026 MAPE 17.5 % over 60 s | V-official (vendor FAQ) https://www.hrv4training.com/faq.html |
| Chest straps that send RR | Polar H7, H9 and H10, and Garmin HRM-Dual and HRM-Pro are listed as sending R-R. Polar OH1 and Verity Sense, Wahoo TICKR FIT and WHOOP ("closed platform") are not. HRV Logger: "Garmin dual straps seem to work as good as the Polar ones"; TICKR "mixed results". HRM-Pro **Plus**: users report no RR to third-party apps. Polar's SDK docs give the H10 "RR Interval in ms" and put Verity Sense PP intervals behind the SDK only | Vendor app pages https://elitehrv.com/heart-variability-monitors-and-elite-hrv-compatible-monitors ; https://www.hrv.tools/hrv-logger-faq.html ; https://github.com/polarofficial/polar-ble-sdk/blob/master/documentation/products/PolarH10.md ; Community https://forums.garmin.com/sports-fitness/running-multisport/f/accessories-sensors/321480/why-does-hrm-pro-plus-not-tracking-rr-intervals |
| Minimum morning protocol | 60 s of lnRMSSD agreed with 5 min at rest (Esco & Flatt 2014: ICC to .98, LoA 0.00 ± 0.22 for 60 s pre-exercise). Kubios: "up to 60-seconds relaxation period", a consistent position, on waking before caffeine. HRV4Training: "60 seconds are sufficient", natural breathing | Abstract via search https://pubmed.ncbi.nlm.nih.gov/25177179/ ; https://www.kubios.com/hrv-app/ ; https://www.hrv4training.com/faq.html |
| HC `recordingMethod` | Four values, including `RECORDING_METHOD_UNKNOWN`. Writers choose one through factory methods (`autoRecorded`, `activelyRecorded`, `manualEntry`, `unknownRecordingMethod`), so **UNKNOWN is a legitimate value for real nightly data** | V-official https://developer.android.com/health-and-fitness/health-connect/metadata |

---

## 2. Verdict table

| Rung or element | Verdict | Criterion | One-line reason |
|---|---|---|---|
| P1 origin on HC provenance + `recordingMethod` column | **KEEP (bigger than stated)** | — | Ingest still drops every non-Fitbit origin, and the resolver groups by `SourceKind` only (§8). P1 must lift the filter *and* choose one origin per metric inside the resolver, not just stamp it |
| P2 `Provenance` origin round-trip | **Drop (already done)** | — | `models.dart` already has `toJson`/`fromJson`, and `==`/`hashCode` include `origin` [V-code] |
| P3 `sourceChoices` + persisted choices | **KEEP** | — | Still stubbed (`health_repository_impl.dart:947-950`) [V-code] |
| P4 Samsung-shaped fixture | **KEEP, do first** | — | Cheap, and it pins every Samsung decision below |
| 0a/0b `ghapi_*` (Enhanced mode) | **KEEP (unchanged)** | — | Existing; off by default |
| 0c `hc_sleep_mean_rmssd@origin` | **KEEP, with a changed filter** | (b) | "Automatically recorded only" would drop real nightly data written as UNKNOWN. Accept AUTOMATIC or UNKNOWN **inside the main sleep**; exclude ACTIVE and MANUAL |
| 0d `hc_nightly_rmssd@origin` | **KEEP, tightened** | (a) | Record shapes are unverified, so the rule must be data-driven: AUTOMATIC only, ≤ 2 per wake day, and a per-origin **persisted** shape so the definition can't alternate night to night (§3) |
| 0e `whoop_api_recovery_rmssd` (BYO, personal build) | **VETO** | (c)(e)(f) | (e): WHOOP says the secret should "never be exposed in a … mobile application", and the "compete" and "permanent copies" clauses hit 30-night baselines. (c): no account to test with. (f): a one-vendor client for users who already get WHOOP's own score and whose app writes RHR, respiratory rate and SpO₂ to HC. A flag doesn't rescue it, because it fails on (e) and (f) too. (BYO in a personal build is not (d)) |
| 0f Oura API | **VETO (confirm the drop)** | (e)(f) | Oura writes HRV to HC. 09's R15 reason ("server-side dependency") is wrong: the reasons are redundancy and the terms |
| 1a `ble_morning_rmssd_<posture>_v1` → `Metric.hrvMorning` | **KEEP-BEHIND-FLAG** | (c) | A real measurement under its own name. But there's no strap here and the emulator has no BLE. The "RR fixtures recorded from a real strap" in 09 can't exist yet, so use synthetic RR fixtures. It leaves the flag after one real-strap session runs end to end on the phone |
| 1a: "RR present" as the sensor qualifier | **KEEP + add a plausibility check** | (b) | An RR flag doesn't prove beat-level RR. Reject a sensor whose RR equals 60000/bpm (within 1 tick) across the first 30 beats: that's derived, not measured [O] |
| 1a: session reject on artifact fraction | **KEEP, as an [O] constant** | — | No primary source for a threshold. A quality gate only suppresses numbers, so err strict (§3) |
| 1b `cam_morning_rmssd_*` | **VETO for v1** | (a)(c)(f) | Validation paradox: it can only graduate against a strap on *this* phone, and a user who owns a strap doesn't need the camera. There's a phone-model effect (HRV4Training's S3 failed; Guede-Fernández found a device effect), and the Android evidence is weak (Peng 2015; Johansson 2026 MAPE 17.5 %). It needs a native CameraX analyzer, a Dart peak detector and a Play listing duty, for a number that serves one job indirectly. **Q10 is moot**; see §3 if it's ever revisited |
| 2.E overnight BLE RR (`ble_sleep_rmssd`) | **VETO for the ladder (later)** | (c)(f) | An all-night foreground service. No device with RR is in hand |
| Floor: Recovery "without HRV" | **KEEP (the default)** | — | Honest, already built, covers everyone |
| Sleeping HR (4 h mean) for no-RHR origins | **KEEP, restructured** | (b) as written | It must be its own metric and field (§3). As written in 09 §3.3, it lands in `restingHr` and reaches Strain, Health Monitor, Coach and export as "Resting HR" [V-code: `strain.dart:270`, `health_monitor.dart:58`, `coach/tools.dart:737`, `export.dart:160`] |
| Full-night HR fallback when sleep < 4.5 h | **VETO** | (b)(f) | A third definition that fragments the baseline and never calibrates. On a short night the input is **absent**, not swapped |
| Lowest overnight HR; HR dip; "HRV from HR" | **VETO (agree with 09)** | (b) | No validation; the dip evidence is clinical only; RMSSD is undefined on bpm samples |
| Readiness (Plews SWC) on the morning series | **Defer** | (f) | Not needed for "How am I + what to do" in v1 |
| Per-app table in 09 §1 as a gate | **Informational only** | (a) | See §7 |

---

## 3. Final ladder (exact definition strings)

**Baseline key:** `definition@origin#device`, as in `Provenance.baselineKey`. Every definition has its own baseline. Values are never merged, converted or pooled across definitions.

### `Metric.hrv` (nightly), in resolver order

| # | Definition | Source | Used when |
|---|---|---|---|
| N1 | `ghapi_deep_sleep_rmssd` | googleHealthApi | Enhanced mode is on and the value is present (existing) |
| N2 | `hc_sleep_mean_rmssd@<origin>` | healthConnect | The chosen HRV origin's persisted shape is **samples**. ≥ 3 records inside the main sleep with `recordingMethod` ∈ {AUTOMATICALLY_RECORDED, UNKNOWN}. Value = the mean |
| N3 | `hc_nightly_rmssd@<origin>` | healthConnect | The persisted shape is **single**. 1–2 AUTOMATICALLY_RECORDED records assigned to the wake day by the resolver's existing `nightDay()`. Value = the mean. UNKNOWN is accepted only inside the main sleep, so daytime spot checks can't leak in |
| N4 | `ghapi_daily_rmssd` | googleHealthApi | Enhanced mode, when N1–N3 gave nothing (existing) |

- **Persisted shape:** decided per origin from its last 14 nights. "Samples" if most nights have ≥ 3 in-sleep records; else "single". It's stored with the source choice and changes only after a sustained change, never per night.
- **Why:** baselines take same-key values (`baselines.dart` `values()`). An alternating definition would split one origin's history into two thin baselines.
- **Spot definition:** `hc_spot_rmssd@<origin>` holds ACTIVE and MANUAL records. They're stored, never used by Recovery, Trends HRV or baselines.

### `Metric.hrvMorning` (new, separate; flag `HRV_MORNING_CHECK`)

| # | Definition | Used when |
|---|---|---|
| M1 | `ble_morning_rmssd_supine_v1@ble:<model>` or `ble_morning_rmssd_seated_v1@ble:<model>` | The check passed protocol v1 inside the morning window |
| — | `ble_spot_rmssd@ble:<model>` | Any check outside the window. Stored and shown in check history only |

**Protocol v1:**
- on waking, after the bladder, before caffeine;
- fixed posture, still, breathing naturally;
- **60 s settle (not analysed) + 60 s analysed** (the existing 120 s `kHrvCheckSeconds`);
- existing filters: 300–2000 ms, 20 % successive difference, ≥ 30 clean beats;
- **reject the session if > 10 % of beats are removed.** [O] constant with no primary source; tune it on synthetic fixtures;
- the RR plausibility check from §2.

### `Metric.sleepingHr` (new, separate; never `restingHr`)

| # | Definition | Used when |
|---|---|---|
| S1 | `hc_sleep_hr_4h_mean@<origin>` | See the rules below |

- **When it's used:** the existing observation `_notSharedBy(…, Metric.restingHr, …)` holds for the chosen sleep/HR origin: that origin has written other nightly data on ≥ `notSharedNights` nights and never written RHR. The result is persisted with the source choice, not re-decided per night.
  - This is data-driven; there's no package list.
  - A new user or a sync gap doesn't trigger it.
  - On a day when an RHR-writing origin simply misses its RHR, the slot is **absent**, not substituted.
- **Segment:** main-sleep start + 30 min to + 4 h 30 min (Nuuttila's 4H). HR comes from the **same origin** as the main sleep. It reads across midnight, so it needs the previous civil day's `HrDay`.
- **Gate:**
  - the main sleep is ≥ 4 h 30 min;
  - ≥ 80 % of the 48 five-minute bins hold ≥ 1 HR sample. The 5-minute resolution follows Nuuttila 2024's 5-min averages; the 80 % is [O].
- **Value:** the mean of the 5-minute bin means, so uneven density can't weight part of the night.
- **Recovery:** component key `sleep_hr`, label **"Sleeping HR (4 h mean)"**. It takes RHR's 0.25 weight **only when `restingHr` is null**. It's scored like RHR: logistic(−1.1·z), min SD 0.8 bpm, against **its own** baseline. That scoring reuse is an [O] choice, disclosed on the Methodology page.
- **Nothing else reads it:** Strain, Health Monitor, Coach "Resting HR", Trends RHR and export `resting_hr` never read it. It gets its own export column, and its own Trends line only if the Trends owner wants one.

### Floor

- **Recovery "without HRV":** the existing re-weighting.
- **No Recovery:** when HRV, `restingHr` and `sleepingHr` are all absent. A status card says what's missing and how to fix it.

### Vetoed (not in the ladder)

`whoop_api_recovery_rmssd`, `oura_api_sleep_average_hrv`, `cam_morning_rmssd_*`, `ble_sleep_rmssd`, `hc_sleep_hr_full_mean`, the lowest overnight HR, the HR dip, and any HR-derived "HRV".

**If the camera is ever revisited (Q10):** it graduates per phone model, only when the TEE vs a chest strap over ≥ 20 paired 60-s readings on ≥ 10 mornings is **below the user's morning SWC** (0.5 × within-person SD of the strap-measured lnRMSSD), and the mean bias is trivial (standardised < 0.2). Plews 2017's 6.35 % TEE CV is the reference.

---

## 4. The Samsung decision

**Recovery from sleep plus Sleeping HR, labelled, only when the density gate passes. Otherwise no Recovery, with a status card.**

- **Why not "no Recovery" always:**
  - Samsung sends HR and sleep. The 4-h nocturnal HR mean is a measured, reliable (ICC .97–.98), load-sensitive marker under its own name.
  - Refusing it leaves the largest Android wearable base with no Today state.
- **Why not a differently named score:**
  - it adds a fourth score concept against the three-score [U] "one job" row and the Figma tile map;
  - it breaks [U] "one formula for every device". The rule "sleeping HR fills the RHR slot when a source writes no RHR" applies equally to Oura, Ultrahuman and Mi Fitness;
  - names follow inputs, not vendors.
- **What the Samsung user sees when the gate passes:**
  - Recovery built 50 % from sleep performance and 50 % from Sleeping HR;
  - coverage 0.50, confidence **reduced** (0.50 is exactly on `lowCoverage`; pin it with a test);
  - ring subtitle "without HRV";
  - basis line: "From sleep and sleeping heart rate. Samsung Health doesn't share HRV or resting HR." The app name comes from `_notSharedBy`, never from a package list;
  - 09's "≈42 % RHR weight" is wrong for Samsung, which has no respiratory rate: it's 50 %.
- **When the gate fails** (for example Samsung's "Every 10 mins while still"): no Recovery, and the status card reads:
  - "Recovery needs your heart rate at least every 5 minutes during sleep."
  - Fix 1: "In Samsung's heart-rate settings choose *Measures continuously* (called *Always* on some watches)."
  - Fix 2 (only when the flag is on): "Or add a 2-minute morning check with a chest strap."
- **Probe item:** record Samsung's actual HC HR density under each of its three settings. Until then the gate decides at runtime, so no unverified number is ever shown.

---

## 5. Default UX

- **Default for everyone:** the floor, plus Sleeping HR for no-RHR origins. Nothing to set up.
- **Morning check:**
  - off and hidden in public builds until the flag is lifted;
  - after that, **opt-in only**;
  - offered once, as a second fix line on the existing "without HRV" note when `_notSharedBy(Metric.hrv)` fires, and on the HRV row in Settings → Sources;
  - declining is remembered.
- **TodayPlan `measure` action:**
  - shown only in the morning window, only when opted in, and only while HRV mode is **morning** (§6);
  - in that case it ranks first, because it completes today's score;
  - while morning checks are only a separate tile, **no TodayPlan action**. The tile is its own entry point (Calm).
- **Reminder:** off by default. No streaks and no "missed" copy (agree with 09).

---

## 6. Recovery-stability rule for morning HRV

**Evidence:** Nuuttila 2024 found nocturnal and morning responses to overload "were not similarly aligned, especially in LnRMSSD". So a morning check is a different construct and never a stand-in for nightly HRV, which confirms 09's R2.

- **Nightly definition exists for the user** (N1–N4 on the persisted origin): morning checks never enter Recovery. They're a separate tile on Recovery detail with their own baseline band, and a separate Trends line.
- **No nightly definition:** HRV mode switches to **morning** only when:
  - the morning baseline is reliable (≥ 5 checks, `Baseline.isReliable`), **and**
  - there are ≥ 10 valid morning checks in the last 14 days.
- It switches back to "separate tile" when fewer than 7 of the last 14 days have a valid check.
- The 10/14 and 7/14 values are **[O] behaviour constants with no physiological source**. The gap between them is hysteresis, so the mode doesn't flap.
- **A missed morning while in morning mode:** that day's Recovery is "without HRV" and labelled so. Never carry a previous check forward.
- **Weight:** HRV keeps 0.40 (one formula). The component label comes from the definition ("HRV · morning check · <model> · lying · 07:12").

---

## 7. Is a declared APK permission evidence of an HRV source?

- **No, and it doesn't need to be.**
  - A declared `WRITE_HEART_RATE_VARIABILITY` shows capability only.
  - A missing one is a strong "no" for that build, but only until the next update.
- **The design must not branch on the table.** Keep these data-driven:
  - reading HRV from any origin;
  - the N2/N3 shape;
  - the Sleeping-HR trigger;
  - the "<App> doesn't share HRV" copy (`_notSharedBy`).
- **No package allow-list or deny-list in code.**
- **The §1 table's only uses:** research, and choosing which Toolbox fixtures to build.

---

## 8. What's wrong or stale in 09

1. **P2 is already done.** `Provenance.toJson`/`fromJson` carry `origin`, and `==`/`hashCode` include it (`models.dart` 97–123).
2. **P1 is understated.**
   - **Ingest is still Fitbit-only.** `hc_mapper.dart` keeps "only the Fitbit origin … for band metrics", with `bandOrigins = {kFitbitOrigin}` (`hc_mapper.dart:3, 81, 94`). Every other origin is dropped, or becomes `context` for steps and weight. So [U] "Any app" isn't implemented, Samsung and Oura users get nothing today, and `_notSharedBy` can't fire in live mode.
   - **The resolver groups by `SourceKind` only:** `scalarByDay[day][scalar][source]`, `hrvBySource`, `hrDays[date][source]`, and `pick()` returning all HC rows (`resolver.dart:139-176, 238-251, 340-357`). So lifting the filter alone would pool apps:
     - `mean(resp.rows)` would average across apps;
     - `_latest(rhr.rows)` would take the latest from any app;
     - HRV samples from two apps inside one sleep would be averaged.
   - Sleep dedup is already per origin (`sleep_dedup.dart` `isDuplicateNight`), so sessions from two apps would both be kept.
   - **So P1 means:** lift the filter, then group and choose by `originPackage` inside the resolver, in the same change.
3. `recovery.dart:102` → the null return is at **`recovery.dart:121`**. Re-weighting is at **205–226**, not 188–208.
4. Samsung's table has **18** rows, not 19. It's a sync-scope table with no direction column.
5. Nuuttila 2024: "CV 6.0–8.3 %" is the range across all segments; Sleep4h is **6.6 %**. "Tracked the performance change better than LnRMSSD" isn't tested in the paper.
6. §7's "≈42 % RHR weight on HR-only nights" doesn't hold for Samsung, Oura, Ultrahuman or Mi Fitness (no respiratory rate): it's **50 %**.
7. The rule "only automatically recorded HRV feeds nightly" (§1.2) would drop UNKNOWN-method nightly data.
8. **Leftovers from the dropped Oura rung:**
   - §3.3 still lists `SourceKind.ouraApi`, `data/services/oura/`, `oura_api_sleep_average_hrv` and `oura_sleep_v2.json`;
   - R14 still argues from the Oura clause;
   - R15's reason ("server-side dependency") is wrong.
9. **Rung numbering is inconsistent** for the Sleeping-HR item: "rung 3" in §0 and §3.3, "Rung 2 (the floor)" in §2.1, and just a note in §3. §7's "Short answer" still says "(Samsung)" only.
10. **Stale references:**
    - Pulse Age is cited as a consumer (R2, 1a tests), but it was removed from v1 (§7 product-critic row);
    - `_hrvNotSharedBy` is really `_notSharedBy(…, Metric.hrv, …)`;
    - §2.1 still says §1 is "unverified".
11. The 09 §3.3 Rung-3 plan ("compute … only when that origin has no `RestingHeartRateRecord`", label fixed at `recovery.dart:167`) writes into `restingHr`. That's the principle-6 blocker covered in §2 and §3.

**Found in passing** (not in 09; flagged, not decided): Strain uses `restingHr ?? 62` (`strain.dart:270, 331`). So every no-RHR origin (Samsung, Oura, Ultrahuman, Mi Fitness) gets HR-reserve zones from a hard-coded 62 bpm. Don't "fix" this silently with Sleeping HR; it's a separate principle-6 decision.

---

## 9. Implementation order for the Data agent

Smallest safe steps first. Contract changes (`models.dart`, `results.dart`, `repositories.dart`) go through the orchestrator. Engine files go to their owner per `ARCHITECTURE.md` §9.

1. **Fixtures first** (`test/domain/baseline_origin_test.dart`, `test/data/resolver_test.dart`):
   - comment on `samsungHrv` that the real Samsung writes no HRV;
   - a Samsung-shaped fixture (HR + sleep, no HRV, RHR or respiratory rate) in two variants: continuous (≈1/min) and 10-min HR;
   - a **two-HC-origin** fixture that expects exactly one origin per metric, never a mean across apps. It stays red until step 2.
2. **Origin-aware ingest and resolver (P1), in one change:**
   - lift the Fitbit-only `bandOrigins` filter;
   - group HC rows by `originPackage`, choose one origin per metric (most recent sustained; override stub), and stamp `origin:`;
   - files: `data/services/health_connect/hc_mapper.dart`, `data/resolver/resolver.dart`, `data/resolver/definitions.dart`.
3. **`recordingMethod` carried through:**
   - files: `data/services/health_connect/health_connect_service.dart` (read `HealthDataPoint.recordingMethod`), `hc_types.dart`, `hc_mapper.dart`, `data/db/raw_rows.dart` (`RawHrvRow`), `data/db/schema.dart` (column + migration);
   - N2 filter: accept AUTOMATIC or UNKNOWN in sleep; ACTIVE and MANUAL go to `hc_spot_rmssd`.
4. **P3:** `sourceChoices()`/`setSourceChoice()` in `data/repositories/health_repository_impl.dart:947-950`, plus the persisted per-origin HRV shape.
5. **N3 `hc_nightly_rmssd`:**
   - files: `definitions.dart` + resolver;
   - fixtures: a noon-stamped single record, a wake-stamped record, one record in sleep, and a daytime ACTIVE spot record that must **not** leak in;
   - also a Toolbox shape list for on-device checks.
6. **`Metric.sleepingHr`:**
   - contract: `Metric.sleepingHr`, `DayRecord.sleepingHr4h` + JSON;
   - resolver: cross-midnight `HrDay` read, the gate, the value;
   - export: a new column in `data/repositories/export.dart`;
   - hand-off to the engine owner: `inputs.dart`, `baselines.dart` `valueReader`, `recovery.dart` (`sleep_hr` component when `restingHr` is null), the `day_engine.dart` gate-fail status note;
   - **tests:**
     - Samsung continuous → 2 components, coverage 0.50, `reduced`;
     - Samsung 10-min → Recovery null plus the status note;
     - sleep < 4.5 h → absent;
     - non-leak: Strain `restingHrUsed`, Health Monitor RHR, Coach "Resting HR" and export `resting_hr` are unchanged by it.
7. **BLE morning check, behind `--dart-define=HRV_MORNING_CHECK=true`:**
   - extend the `hrv_check` save (`health_repository_impl.dart:892-912`) with posture, protocol version, analysed seconds, removed-beat fraction and sensor model;
   - morning vs spot split against the main sleep's end;
   - resolver emits `Metric.hrvMorning`;
   - the plausibility and reject gates go in `hrv_tools.dart` (engine owner);
   - **synthetic** RR fixtures through `hrs_parser`;
   - the mode gate from §6 with a test for the 10/14 and 7/14 hysteresis.
8. **Not built:** the WHOOP API, camera PPG, overnight BLE, the full-night HR fallback.

**For the orchestrator:** the PRODUCT_PLAN §7 [U][R] HRV row lists the vendor API and camera as *allowed*. That is a ceiling, not a requirement, so vetoing them doesn't contradict it. Record the vetoes in that row.

---

## 10. Still unverified (none changes a verdict)

- Nuuttila 2022's recording device (the full text returned 403).
- Whether WHOOP's HR broadcast carries RR. Altini's post returned 403; Elite HRV calls WHOOP closed.
- Garmin HRM 600 RR over BLE.
- Flatt & Esco 2016's stabilisation finding. Only the abstract's "traditional 5-min stabilization + 5-min recording" was seen.
- Samsung's actual HC HR density under each of its settings (a probe item).
- Oura's HC HRV record shape (a probe item; N2/N3 handle either).
- NOOP's `recordingMethod`. It wasn't checked, and N3 needs AUTOMATIC outside sleep, so NOOP's noon-stamped record may not qualify. That's the safe failure (no value), and NOOP gets no special case.
