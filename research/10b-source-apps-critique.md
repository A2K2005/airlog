# 10b: Critique of research/10 (source apps)

**Date:** 2026-09-30 · **Status:** critique only; no app code changed · **Reviews:** `research/10-source-apps.md` · **Binding inputs:** `PRODUCT_PLAN.md` §3 principles and §7, `research/09b-hrv-critique.md` (its vetoes and §7 rule stand) · **Code read:** `domain/engine/source_apps.dart`, `notes.dart`, `day_engine.dart`, `recovery.dart`, `stats.dart`, `health_monitor.dart`; `data/resolver/resolver.dart`, `source_choice.dart`; `data/sync/score_pipeline.dart`; `data/db/raw_rows.dart`, `schema.dart`; `data/services/health_connect/hc_mapper.dart`, `health_connect_service.dart`; `android/.../HealthConnectBridge.kt`, `AndroidManifest.xml`; `test/data/fixtures/hc_apps.dart`

**Veto criteria (from the brief):**
1. Unverified, or verified only from declared APK permissions, but presented as fact about what reaches Health Connect.
2. Invents or estimates data.
3. Untestable here without a device, unless it's clearly flagged and has a safe default.
4. Needs a server, an embedded secret or a partnership, or breaks a vendor's terms.
5. Scope that doesn't serve "How am I + what to do".

**Labels:** [V-official] = I read the vendor page this pass. [V-code] = I read it in our source. [Not re-checked] = I took 10's word for it.

---

## 0. Verdict in one screen

| # | Recommendation | Verdict | Criterion | Reason in one line |
|---|---|---|---|---|
| R1 | Add 8 package names | **ADOPT WITH CHANGES** | — | All 8 Play titles check out. Mark Health Sync as a relay; skip the redundant `<queries>` entries |
| R2 | Per-app setup copy table | **ADOPT WITH CHANGES** | 1, 09b §7 | Setup steps only, and only the vendor-documented ones. Drop the "usually shares" list: 09b §7 limits that table to research and fixtures. Fix the wrong Polar fix line |
| R3 | "Shares / computes / missing" card | **ADOPT WITH CHANGES (reduced)** | 1, 5 | "Shares" and "doesn't share" come from observed data and the engine's own outputs. No parallel basis helper, no declared-type "missing" list |
| R4 | Profile-value guard | **ADOPT WITH CHANGES** | 2 | The bug is real and bigger than 10 says: a profile value can also win the RHR origin from a real writer. Guard rules in §2 |
| R5 | Relay attribution | **ADOPT WITH CHANGES** | 3 | Copy only. Name the device only when metadata has one; fall back to "Health Sync" |
| R6 | WHOOP membership fix line | **ADOPT WITH CHANGES** | 1 | WHOOP's page contradicts itself on tiers. Hedge the copy and leave out tier names |
| R7 | Fixtures per app shape | **ADOPT WITH CHANGES** | — | Also fix the existing Oura fixture, which writes RHR, respiratory rate and skin temp that Oura doesn't share |
| R8 | Polar BLE SDK nightly spike | **REJECT (for now)** | 3, 5, §7 | Not the vetoed overnight BLE RR, and its RMSSD is measured. But Polar's docs make it exclusive with Flow, there's no Polar device here, and it adds a rung to a [U][R] ladder |
| R9 | Samsung Health Data SDK flag | **REJECT** | 3, 4, 5 | Developer mode is "NOT for app users", release needs a partnership, there's no Galaxy wearable here, and skin temp alone doesn't pay for native code |
| R10 | Point users to Health Sync | **REJECT (say nothing)** | 4 (spirit), 1 | A paid relay that runs Garmin data through its own cloud. §2.5 already rejects aggregators for that reason. The generic "another app" fix already covers users who install one |

**Net for the bottom line of 10:**
- Point 6 flips: **no** vendor SDK passes.
- Point 3 needs a hedge: WHOOP's tier gating is ambiguous.
- Point 2: Mi Fitness and FitCloudPro are declared-only.

---

## 1. Spot checks of 10's primary sources

| Claim in 10 | Result | Source (all read 2026-09-30) |
|---|---|---|
| Polar: RHR and VO₂max are "physical settings"; HR is workouts only | **True.** 14 rows, including "Resting heart rate: physical settings", "VO2 max: physical settings", "Heart rate: heart rate during workouts", "Steps: per day", and Exercise. Also, "From now on, Health Connect receives your new Flow data". Polar's SDK sync guideline separately lists "Current user physical configuration: … Maximum HR, Minimum HR, VO2Max" as settings, which supports the reading | [V-official] support.polar.com/us-en/flow-app-health-connect ; github.com/polarofficial/polar-ble-sdk `documentation/SyncImplementationGuideline.md` |
| Oura: HRV but no RHR | **True.** Export: "Sleep, Vitals (Heart rate, Heart rate variability)" plus activity and body. No RHR, respiratory rate, temperature or SpO₂. Updated Aug 19, 2026 | [V-official] support.ouraring.com/hc/en-us/articles/10786105824531 |
| Samsung: "HR + sleep only" | **True for Recovery inputs.** 18-row sync-scope table: HR, sleep, SpO₂, exercise (incl. per-exercise VO₂max), steps, weight and others. No HRV, RHR, respiratory rate or skin temp. "Can be changed depending on the Samsung Health version." The setup path (Settings → Health Connect; Sync with Samsung Cloud → On; pull to refresh) is confirmed | [V-official] developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect |
| WHOOP: RHR and respiratory rate on Peak/Life only | **Ambiguous on WHOOP's own page** (last published 10/6/2025):<ul><li>"Data Syncing → Recovery: WHOOP automatically syncs key recovery metrics, including RHR, SpO2, Respiratory Rate".</li><li>"WHOOP One: Sleep, Strain, **Recovery**, and body metrics sync".</li><li>But "WHOOP Peak: **Adds** Health Monitor data, including Resting Heart Rate and Respiratory Rate".</li></ul>No HRV in the export list, and "does not sync … VO2 Max". HR isn't in the export list | [V-official] support.whoop.com/s/article/Google-Health-Integration-For-Android |
| Google Health: SpO₂ is read-only in the help table | **True.** Oxygen saturation appears only in the read column. HR, HRV, RHR, respiratory rate, skin temp, sleep and VO₂max are read and write | [V-official] support.google.com/googlehealth/answer/14506680 |
| Samsung Data SDK dev mode is test-only | **True.** "ONLY intended for testing or debugging your app. It is NOT for app users." Access needs the package and signature "matched with the registered information", and writing needs a partnership access code | [V-official] developer.samsung.com/health/data/guide/developer-mode.html |
| Polar SDK nightly recharge fields | **True.**<ul><li>`meanNightlyRecoveryRMSSD`: "Mean of the PPI (after 0.5h from sleep start to 4.5h after sleep start PPI) calculated RMSSD values".</li><li>`meanNightlyRecoveryRRI`: "Mean of the HR … samples to beat interval time".</li><li>The class also carries Polar's own scores (`ansStatus`, `recoveryIndicator`, `ansRate`), Polar's own baselines (`meanBaselineRMSSD`, `sdBaselineRMSSD`, …) and tips</li></ul> | [V-primary] `…/model/sleep/PolarNightlyRechargeData.kt` (raw source read) |
| Polar SDK coexistence with Flow is "unverified" | **Understated.** For watches, Polar's docs say: "Make sure FlowApp is completely shutdown and that your watch is not connected to any other mobile phone". Polar 360 is "designed to be used with 1 peer device only". "Polar BLE SDK does not currently support reacting to this auto sync mechanism." The docs themselves make it exclusive, so this is documented, not unknown | [V-official] `UsingSDKWithWatches.md`, `products/Polar360.md`, `SyncImplementationGuideline.md` |
| Polar SDK licence | **True.** §4.4 bars using Polar marks or indicating "any association with Polar, express or implied". §3.2: not for "medical purpose". No competing-use clause | [V-official] `Polar_SDK_License.txt` |
| Health Sync: paid, with its own cloud for Garmin | **True.** "One week free trial", then "a one-time purchase or start a six-month subscription"; Withings needs an extra subscription. Status page: "problems on our cloud server involved with the Garmin sync". Sources include Garmin, Polar, Samsung Health, Oura, Suunto, Huawei Health, COROS and Withings | [V-official] Play listing `nl.appyhapps.healthsync` ; healthsync.app/status |
| R1 Play titles | **All 8 true**:<ul><li>`nl.appyhapps.healthsync` "Health Sync"</li><li>`com.ultrahuman.android` "Ultrahuman"</li><li>`com.heytap.health.international` "OHealth"</li><li>`com.hihonor.health` "Honor Health"</li><li>`com.titan.fastrack.reflex` "Fastrack Smart World"</li><li>`com.topstep.fitcloudpro` "FitCloudPro"</li><li>`com.urbandroid.sleep` "Sleep as Android: Smart alarm"</li><li>`com.wahoofitness.fitness` "Wahoo: Ride, Run, Train"</li></ul> | [V-primary] Play page `<title>`, gl=IN |
| Garmin's HC type list | **Not re-verified** (the page returned HTTP 403). Garmin RHR stays "declared, unconfirmed" | — |
| Every "D" cell (Exodus declarations) | [Not re-checked]. Per 09b §7 they're capability only, and criterion 1 applies to every outcome built on them (§4) | — |

---

## 2. R4: trace, verdict and the guard

### 2.1 Trace (confirmed, and wider than 10 states)

- **Ingest drops `recordingMethod` for scalars.**
  - The plugin maps it for every record (`health_connect_service.dart:113-118`).
  - The mapper keeps it only on HRV (`hc_mapper.dart:141`).
  - RHR and VO₂max become plain `RawScalarRow`s with no method (`hc_mapper.dart:144-145, 162-163`; `raw_rows.dart:204`).
  - VO₂max bypasses the plugin entirely. `HealthConnectBridge.kt:78-88` returns id, value, origin, device and lastModified, but not `metadata.recordingMethod`. [V-code]
- **"Daily" mode** (Polar writes the setting every day). This is 10's first failure mode; confirmed.
  - `resolver.dart:430-438` takes `_latest(rhr.rows).value` as the day's `restingHr`. Rows are filtered only by origin (`chosen()`, `resolver.dart:112-116, 206`).
  - Consequences 10 doesn't spell out:
    - Recovery exists every day, because it's null only when HRV, RHR and sleeping HR are all absent (`recovery.dart:128-134`).
    - The RHR component is pinned at 50 %. A constant series has SD 0, so the 0.8 bpm floor applies (`recovery.dart:41, 176-177`), z = 0 and logistic(0) = 0.5. Before 3 values it's `neutralScore` 0.5 (`recovery.dart:29`; `stats.dart:56-60`).
    - So Recovery moves only with sleep, is labelled "without HRV", and becomes "reliable" after 5 nights.
    - Strain builds HR-reserve zones from the setting (`day_engine.dart:283`).
    - Health Monitor RHR can never flag (`health_monitor.dart:58`).
  - That's a principle-6 violation (a setting shown as "Resting HR") and a principle-2 one (false reassurance).
- **"Once" mode** (Polar writes on a settings change). 10's second failure mode; confirmed, and worse:
  - **Engine path:** `day_engine.dart:569-574`. One history day with RHR from the same origin returns null (`if (from == origin) return null`, line 573). The note is then `missingRhr(seenBefore: true)` (`day_engine.dart:392-397`), which tells the user to wear the tracker to bed, a fix that can't work.
  - **Persisted path, which 10 missed:** `SourceChooser.notSharedBy` (`source_choice.dart:322-331`) needs the origin to have **never** written the metric, over all raw rows since the first sync (`score_pipeline.dart:134-136`). So one profile record keeps Polar out of `notShared` **permanently**, not just "while it stays in history".
  - On the one day the record lands, Recovery = sleep + a neutral RHR from a setting.
- **Cross-app path, which 10 missed entirely.**
  - `originDaysOf` counts every HC RHR and VO₂max row as coverage (`source_choice.dart:401-418`). `SourceChooser.best` picks the origin with the best 14-day coverage (`source_choice.dart:162-184`).
  - So a Polar series written daily can **win the RHR origin** over a real writer with gaps (a Fitbit Air on charge days, WHOOP). `chosen()` then drops the real series, and the setting becomes the user's RHR.
  - A guard placed only at `resolver.dart:430` doesn't prevent this.

### 2.2 The guard (a testable rule)

The guard is **data-driven**: no package list. It applies per origin, to Health Connect and context rows only. Demo, BLE and GHAPI rows are untouched.

**Record rule (RHR and VO₂max):**
- `recordingMethod == manual` drops the row everywhere: origin coverage, `notSharedBy`, the resolver.
- MANUAL means user-entered in HC's own semantics.
- Weight and height get **no** guard. Manual entry is normal for them.

**Series rule (RHR only):** applies to rows whose method is `unknown` or null (null covers rows ingested before the column existed). `automatic` and `active` rows are **never** suppressed, so a genuinely stable Fitbit-style series stays. Both tests run on every `updatePlans` over the origin's rows:

| Flag | Condition | Catches | Can't hit |
|---|---|---|---|
| **C: constant** | ≥ 10 UNKNOWN RHR records on ≥ 10 distinct days, whose first and last days are ≥ 14 days apart (inclusive span), all equal after rounding to 0.1 bpm | A setting written daily | A real integer-bpm writer. Day-to-day RHR varies by 1–3 bpm, so 10 identical days is very unlikely, and when it does happen the error goes the safe way (the value is left out) |
| **S: sporadic** | In the last 14 complete days, the origin wrote sleep on ≥ `DayEngine.notSharedNights` (3) days and UNKNOWN RHR on ≤ 1 day | A setting written once | A real daily writer, which has RHR on most of its sleep days |

**Flag, persistence and unflag:**
- **Computation:** a pure `notMeasuredBy(RawRows)` in `source_choice.dart`, run over the **unfiltered** rows.
- **Where flags live:** their **own** settings key (for example `not_measured.resting_hr`, a sorted list), **not** a field on `OriginPlan(restingHr)`.
  - **Why:** once the rows are filtered, a Polar-only user has no RHR rows. `updatePlans` then skips the metric (`score_pipeline.dart:143-146`), so there'd be no plan to hold the flag, and the resolver would let the rows back in.
  - **How they reach consumers:** a new `ResolverConfig.notMeasured` and `EngineConfig.notMeasured`. When the caller passes none, the resolver's fallback computes them from the rows at hand, the same way `plansFor` does.
- **Exclusion:** **all** of the flagged origin's UNKNOWN or null RHR rows are excluded, retroactively. Recomputation runs from the flagged origin's first RHR or sleep day, whichever is earlier; the `changedFrom` logic sits beside the `_symmetricDifference` path in `score_pipeline.dart:163-168`.
- **Rebuild on flag:**
  - When an origin **enters** `notMeasured`, rebuild the `restingHr` plan from scratch (`SourceChooser.update(…, prev: null)`) unless the user pinned it.
  - **Why:** `SourceChooser.update` only appends segments after `evaluatedThrough` (`source_choice.dart:226-248`). Past segments where the profile series already won would keep selecting rows that are now filtered, and the real writer's RHR on those days would be lost.
- **Unflag (hysteresis):**
  - the origin's last 7 UNKNOWN RHR days hold ≥ 3 distinct values, **and**
  - RHR arrives on ≥ 50 % of its sleep days in the last 14.
- **Constants:** 10 / 14 / 0.1 / 3 / 1 / 7 / 50 % are **[O]** constants, re-checked after §6 Q3 on a device.
- **Safe default:** suppression. A flagged value becomes an absent input with a status card, never a guess.
- **Residual risk:** rule C can't fire before about 14 days of a daily constant. Until then, a Polar-daily user sees Recovery with a "Resting HR" pinned at 50 %, which is removed retroactively once the flag fires. It's only avoided sooner if Polar stamps its records MANUAL (the record rule). §6 Q3 decides; if Q3 shows UNKNOWN plus daily writes, consider lowering C's thresholds.

**VO₂max: the record rule only.** No constancy rule, because real estimates legitimately stay flat for weeks (Fitbit cardio fitness, for example).
- **Residual risk:** a Polar VO₂max stamped UNKNOWN will still show, labelled "the source's own estimate".
- That's acceptable: it's display-only now that Pulse Age is out of v1, and it may genuinely be Polar's fitness-test estimate. Note it on Methodology.

**Where it runs** (one filter, so every consumer sees the same rows):
- Apply `measuredScalars(rows, notMeasured)` (the record rule plus the flagged origins) **before** `originDaysOf`:
  - in `score_pipeline.dart:135-136`;
  - in `health_repository_impl.dart:1127, 1206`;
  - inside `resolver.dart` before `scalarByDay`, using `ResolverConfig.notMeasured`.
- **Result:** Polar's RHR never counts as coverage, so it can't be chosen. For the engine, Polar has written other nightly data and never a measured RHR, so the observed `_notSharedBy(restingHr)` path (`day_engine.dart:539-587`) returns Polar after 3 nights.
- **When another app has written RHR:** a `restingHr` plan exists, and `SourceChooser.notSharedBy` also lists Polar, so the persisted path fires from the first night.
- **Existing behaviour, not new:** `notShared` for a metric that no app has ever written is never persisted (`score_pipeline.dart:143-146`). The observed path covers it.

**Copy.** "Doesn't share" is inaccurate for an app that writes a setting. Add `Notes.rhrNotMeasured(app)`, chosen when the origin is in `notMeasured` (via a new `EngineConfig.notMeasured`; a contract change, so route it through the orchestrator):
- **Title:** `Resting heart rate from $app not used`
- **Body:** `$app writes a resting heart rate to Health Connect that doesn't change from night to night, or arrives only rarely, so it looks like a profile setting or a value typed in by hand rather than a nightly measurement. Airlog leaves it out of Recovery, Health Monitor and Strain rather than score a fixed number.`
- **Fix:** the existing `_otherAppFix`.
- `recoveryNotShared` needs the same variant. Its body says the app "doesn't share … resting heart rate", which is wrong for a not-measured origin. The body should read "doesn't share HRV, and its resting heart rate isn't a nightly measurement" when the origin is in `notMeasured`.

### 2.3 Files (10's list is short)

- `android/app/src/main/kotlin/app/airlog/airlog/HealthConnectBridge.kt` (VO₂max: add `recordingMethod`)
- `lib/data/services/health_connect/health_connect_service.dart` (`_readVo2` parse)
- `lib/data/services/health_connect/hc_mapper.dart` (pass the method for `rhr` and `vo2max` scalars)
- `lib/data/db/raw_rows.dart` (`RawScalarRow.recordingMethod`)
- `lib/data/db/schema.dart`: bump `kSchemaVersion` and add `ALTER TABLE raw_scalar ADD COLUMN recording_method TEXT`
- `lib/data/db/sql_rows.dart`, `lib/data/db/sqlite_stores.dart` (read and write the column)
- `lib/data/resolver/source_choice.dart`: `measuredScalars`, `notMeasuredBy`
- `lib/data/sync/score_pipeline.dart`: persist the flags under their own key; rebuild the plan on flag; `changedFrom`
- `lib/data/repositories/health_repository_impl.dart`
- `lib/data/resolver/resolver.dart` (`ResolverConfig.notMeasured` plus the fallback)
- Engine owner: `lib/domain/engine/notes.dart`, `day_engine.dart`, `engine.dart` (`EngineConfig.notMeasured`)

### 2.4 Tests

New `test/data/profile_value_guard_test.dart` plus additions to `any_app_test.dart` and `notes_test.dart`:

1. **Fitbit-shaped, AUTOMATIC RHR constant at 55 for 14 days:** kept. Recovery has an `rhr` component, and `notMeasured` is empty.
2. **UNKNOWN RHR varying 52–58 daily** (Garmin/WHOOP-shaped): kept.
3. **UNKNOWN RHR alternating 52/53 for 20 days:** kept (C needs a single value).
4. **Polar daily:** UNKNOWN RHR fixed at 55 for 15 days, sleep nightly, HR only inside a workout.
   - Flagged C.
   - `restingHr` is null on **every** day, including the days before the flag fired.
   - Recovery is null, with `recoveryNotShared` (not-measured body), whose fix line is the Polar variant from R2.
   - Non-leak, as in 09b: Health Monitor has no RHR, Strain's `restingHrUsed` is null, and export `resting_hr` is empty.
5. **Polar once:** one UNKNOWN RHR record on day 1, sleep on 14 nights.
   - Flagged S.
   - No `restingHr` plan exists, and the flag is persisted under its own key.
   - Polar's RHR row is excluded in the resolver.
   - The engine's `_notSharedBy(restingHr)` returns Polar, and the note is `rhrNotMeasured`, not `missingRhr(seenBefore: true)`.
6. **A MANUAL RHR row from any origin:** dropped. It's absent from `originDaysOf[restingHr]` and doesn't stop `notSharedBy` from listing that origin.
7. **Cross-app, incremental:** Fitbit AUTOMATIC RHR with 4 gap days out of 15, plus Polar UNKNOWN constant daily.
   - Run `updatePlans` day by day, so a plan can be persisted **before** the flag fires.
   - After the flag, the `restingHr` plan is rebuilt and the origin is Fitbit on every day, including the days Polar had won earlier.
   - A user pin to Polar is kept, and Polar's RHR stays excluded.
8. **Hysteresis:**
   - a flagged origin then writes 7 days with 3+ distinct values on daily coverage: unflagged;
   - with only 2 distinct values: stays flagged.
9. **VO₂max:**
   - MANUAL: not shown;
   - UNKNOWN constant at 45 for 30 days: still shown (no constancy rule).
10. **Migration:** existing `raw_scalar` rows with a null method behave as UNKNOWN, and demo rows are untouched.

---

## 3. Per recommendation

### R1: Add package names · ADOPT WITH CHANGES

**Why adopt:**
- All 8 packages and titles are verified (§1).
- The display names 10 proposes are already short forms ("Sleep as Android", "Wahoo"). They're nominative text only (no logos or brand colours), which is consistent with the no-branding rule.

**Relays and duplicates:**
- `nl.appyhapps.healthsync` is a **pure relay**.
- `com.urbandroid.sleep` is partly one: it tracks sleep itself, but its HR can come from paired wearables.
- `com.google.android.apps.fitness`, already in the table, also re-exports other apps' data.
- None duplicates an existing package. The *data* can duplicate, though (Samsung natively and via Health Sync). The one-origin rule already stops summing.

**Changes:**
- Add `static const Set<String> relays = {healthSync}` to `source_apps.dart`, **copy-only** (it's R5's trigger). Resolver and engine never read it.
- Update the header date to 2026-09-30.
- **Skip the `<queries>` additions.** The existing `VIEW_PERMISSION_USAGE` + `HEALTH_PERMISSIONS` and `ACTION_SHOW_PERMISSIONS_RATIONALE` intent queries (`AndroidManifest.xml:106-119`) already make every Health Connect writer's label visible. The engine already falls back to those labels (`EngineConfig.appNames`, `Notes.appName`). The 12 existing `<package>` lines can stay.

**Value:** low (names already resolve through the platform label). **Effort:** XS.

### R2: Per-app setup copy table · ADOPT WITH CHANGES

**What to keep:**
- A pure-Dart, copy-only `source_setup.dart` keyed by package: setup steps plus fix lines. The same pattern already exists in `Notes._continuousHrFix`.

**What to change:**
- **Drop the "usually shares" list and the evidence levels.** 09b §7 (binding): the per-app capability table's "only uses: research, and choosing which Toolbox fixtures to build". A declared-only type shown to users also fails criterion 1. What's missing keeps coming from observation (`_notSharedBy`, `OriginPlan.notShared`, R4's `notMeasured`).
- **Ship only [V-official] in-app paths:** Google Health, Samsung Health, Oura, WHOOP, Polar Flow and Withings. Garmin, COROS, Zepp, Mi Fitness, Ultrahuman, Honor, Fastrack, OHealth and FitCloudPro get the generic Android path until §6 Q12 is read off a device.
- **Correct a wrong fix line in today's code.** For a Polar-only user, `recoveryNotShared` ends in `_continuousHrFix` → "Turn on continuous heart rate in Polar Flow." Polar's page says HC gets "heart rate during workouts" only, so no setting fixes it. Polar's entry:
  - **Fix:** `Polar Flow shares heart rate from workouts only, so there's no overnight heart rate for Airlog to use. If another app on this phone writes HRV or resting heart rate to Health Connect, choose it in Settings → Sources.`
- **No static list of apps without Health Connect** (Suunto, Huawei). They never appear as origins, so there's nothing to attach it to. A "works with" list is out of scope (criterion 5).
- **Test:** only `notes.dart` and `features/settings/**` import `source_setup.dart`, never `data/resolver/**` or `recovery.dart` (a grep-based import test, like the existing architecture checks).

### R3: "Shares / computes / missing" card · ADOPT WITH CHANGES (reduced)

**Keep:**
- **"Shares":** metrics seen in 14 days (`SourceApp.daysWithData`, which already exists).
- **"Doesn't share":** from the latest `DayResult.notShared` (the engine's own output, which also covers apps that have no plan for the metric) and R4's `notMeasured` flags, in the existing `SourcePickerSection` rows. It's Settings-only.

**Drop:**
- **The new "computes" helper.** It would re-derive the engine's basis and drift from it: the sleeping-HR density gate and the HRV shape are runtime decisions. If a basis line is wanted, show the engine's own output: `DayResult.notShared` (`day_engine.dart:507-510`) and the Recovery components actually used.
- **The "missing" text sourced from R2** (see R2).

**Effort:** S. This is the lowest priority of the adopted items.

### R4: Profile-value guard · ADOPT WITH CHANGES

See §2. The changes versus 10:
- The rule is split by metric.
- The constancy rule is tightened (≥ 10 records, ≥ 14 days) and applies only to UNKNOWN or null methods.
- A sporadic rule is added for "once" mode.
- The filter moves ahead of `originDaysOf`, so it also protects the origin choice and `notSharedBy`. The flags live under their own settings key, and the `restingHr` plan is rebuilt when an origin is flagged.
- The status copy is "not used", not "doesn't share".
- The file list grows to include the Kotlin bridge and the SQL row mapping.

### R5: Relay attribution · ADOPT WITH CHANGES

**The copy:**
- When `origin ∈ SourceApps.relays` and `Provenance.device` is set: `<device> via Health Sync`.
- Otherwise: `Health Sync`.
- Never hard-code "Garmin". Health Sync's device stamping is unverified (10 §6 Q9).

**Risk to flag, not fix now:**
- A relay without device metadata that forwards **two** sources for one metric (say Garmin and Oura HRV) is one origin to Airlog. N2 would average them.
- That breaks "never average across apps" in a way the resolver can't see.
- Add it to Q9, plus a fixture that documents the current behaviour.

**Tests:**
- relay HRV with device "Forerunner 965": the freshness line reads "Forerunner 965 via Health Sync";
- no device: "Health Sync";
- the baseline key is `…@nl.appyhapps.healthsync#Forerunner 965`.

### R6: WHOOP membership fix line · ADOPT WITH CHANGES

**The trigger** stays data-driven: `_notSharedBy(restingHr)` fires with the WHOOP origin. The line is copy-only, from R2's table.

**The copy is hedged**, because WHOOP's page contradicts itself (§1), and it leaves out tier names, which also avoids promoting a paid upgrade:
- **Appended to `rhrNotShared` for WHOOP:** `WHOOP's help page says resting heart rate and respiratory rate reach Health Connect only on some WHOOP memberships.`
- **Fix:** `Check what WHOOP shares in WHOOP → More → Account & Settings → Integrations → Health Connect.`

**Keep §6 Q6 open.**

### R7: Fixtures per app shape · ADOPT WITH CHANGES

**The existing fixture is wrong.**
- `test/data/fixtures/hc_apps.dart:9-10, 38, 89` gives Oura RHR 50, respiratory rate 13.5 and skin temp.
- Oura's page (updated 2026-08-19) exports only HR and HRV among vitals.
- **Change:** Oura becomes HR + HRV series + sleep + steps, with no RHR, respiratory rate or skin temp. Tests that only need "a second full writer" should use a neutral `AppShape.fullWriter` (package `com.example.full`), not a mislabelled Oura. Users: `any_app_test.dart:75, 139`, `any_app_repo_test.dart:45, 165, 182`, `any_app_sqlite_test.dart:46`.

**Add:**
- Polar-daily and Polar-once (§2.4 cases 4–5);
- Polar + Fitbit (case 7);
- MANUAL RHR (case 6);
- WHOOP One (sleep + steps, HR not dense) and WHOOP Peak (+ RHR, respiratory rate);
- Health Sync with and without device (R5).

**Rule for every fixture:** its header says it's a shape hypothesis from vendor docs or declarations, not a recording. On-device Toolbox reproduction stays a flagged probe item (criterion 3).

### R8: Polar BLE SDK nightly spike · REJECT (for now)

The brief's questions, answered:
- **Does it conflict with the §7 "overnight BLE RR" veto?** Not by mechanism.
  - The veto (09b §2, 2.E) is Airlog capturing RR all night through a foreground service.
  - R8 connects in the morning and downloads a summary the watch already computed.
- **Is nightly RMSSD measured or derived?** Measured, the same class as HC RMSSD from Fitbit. `meanNightlyRecoveryRMSSD` is the device's "Mean of the PPI … calculated RMSSD values".
  - `60000 / meanNightlyRecoveryRRI` and the respiration conversion are exact unit conversions, but they aren't S1's computation (a mean of 5-min HR bins). They would need their own definitions and labels, never the "Sleeping HR (4 h mean)" slot.
  - Never read: `ansStatus`, `recoveryIndicator(SubLevel)`, `ansRate`, `scoreRateObsolete`, every `meanBaseline*` / `sdBaseline*` (Polar's baselines; Airlog computes its own), and the three tips.
- **Can it coexist with Polar Flow?** Per Polar's own docs, no, for watches ("Make sure FlowApp is completely shutdown …"). The Polar 360 takes one peer device.
  - Flow is the Polar user's **only** Health Connect pipe (sleep, SpO₂, workouts, steps).
  - So the spike would trade those for one HRV number, and risk data Flow hasn't synced if any delete call slipped in.

**Why REJECT rather than flag:**
- (3) There's no Polar device here, and the user's device is a Fitbit Air. A personal-build-only flag would never be switched on, so it's dead native code at L effort.
- (5) It serves a population the user isn't in.
- §7: it adds a new rung to the [U][R] HRV ladder, which only the user can amend.

**Record in §7:** "Polar BLE SDK nightly RMSSD: not vetoed on principle 6; blocked by Flow exclusivity and no device. Revisit with a Polar device in hand and a user decision."

### R9: Samsung Health Data SDK flag · REJECT

- **(4) Terms:**
  - Developer mode is "ONLY intended for testing or debugging your app. It is NOT for app users."
  - Using it as a daily data source is app use, not testing.
  - A public build needs a registered package and signature, which is a partnership.
- **(3) Untestable here:** there's no Galaxy wearable, and "the SDK does not support emulators" (10, [V-official]).
- **(5) Low value:** it would give Samsung users exactly one Health Monitor vital.
  - The Health Monitor alert needs ≥ 2 metrics off (or 1 for ≥ 2 days), so a single vital mostly can't alert.
  - The SDK's SkinTemperature is absolute °C, while Airlog's is a delta, so it would need a new definition and baseline.
  - That's native Kotlin plus an SDK from Samsung's developer site for one number. It doesn't pay for itself.
- **Don't reserve a flag or a definition string.**
- **Record in §7:** "revisit only with a Galaxy wearable in hand **and** Samsung partner approval."

### R10: Health Sync in setup copy · REJECT (say nothing)

**Decision:** Airlog names no relay in setup copy, fix lines or status cards.

**Reasons:**
- **Principle 4 and §2.5.** The aggregator row is rejected because "their servers sit in the data path". Recommending Health Sync puts a third-party cloud in the data path at Airlog's suggestion. That contradicts the one-liner "computed privately on your phone" even though Airlog itself stays server-less.
- **Criterion 1.** Whether its Garmin HRV passes N2/N3 (the record shape and `recordingMethod`) is unverified (Q9). A user could pay and still get "without HRV".
- **"Free" positioning.** It's a paid app: a one-week trial, then a one-time purchase or a subscription.
- **Principle 2 is already met.** The generic fix `_otherAppFix` ("If another app on this phone writes it to Health Connect, choose that app in Settings → Sources") covers anyone who installs a relay on their own. R5 then names it honestly.

**If the user overrides this [U],** the only acceptable form is unnamed and neutral, as one sentence appended to the Garmin HRV note:
> `Some third-party apps can copy data from other services into Health Connect. Most are paid and pass your data through their own servers; Airlog hasn't tested them.`

---

## 4. Corrections to 10's matrix and bottom line

1. **§1 point 3 and §2.1 WHOOP row.** Replace "W, Peak/Life only" with "W; tier gating **ambiguous** on WHOOP's page (One syncs 'Recovery', which lists RHR and respiratory rate; Peak 'adds' them). Unconfirmed, see Q6." Apply the same to the §2.2 rows for WHOOP Peak/Life and WHOOP One.
2. **§1 point 2.** Add "(of the Recovery inputs)" after Samsung. Mark Mi Fitness and FitCloudPro "declared, unconfirmed".
3. **§1 point 6 and §4 verdicts.** No SDK passes: Polar BLE is rejected for now (§3 R8), Samsung Data SDK is rejected (R9).
4. **§2.2, criterion 1.** These outcomes rest on declarations only and must read "if declared writes are real" or move to a "declared, unconfirmed" group:
   - Honor Health "Without HRV";
   - Ultrahuman and Fastrack "With HRV";
   - Google Fit "Without HRV";
   - Mi Fitness and FitCloudPro "Sleeping-HR stand-in";
   - Sleep as Android (not in §2.2, but same rule).

   Garmin's row is already conditional; keep it.
5. **§2.2 Polar "today" cell.** Add the persisted path (`source_choice.dart:322-331`, which makes "once" mode permanent) and the cross-app origin hijack (`source_choice.dart:401-418`, `162-184`).
   - The "daily" cell should say the RHR component is pinned at 50 %, not just "a false 'without HRV'".
   - After R4, the status fix line is the Polar variant from R2, not "turn on continuous heart rate".
6. **§2.1 Polar row.** Evidence strengthened: Polar's SDK guideline lists VO₂max and "Minimum HR" as "current user physical configuration".
7. **§4 Polar BLE SDK row.** Coexistence is "**documented as exclusive** for watches ('Make sure FlowApp is completely shutdown'); Polar 360 one peer device", not "unverified".
8. **§2.1 Garmin row.** The Garmin page wasn't re-verified (HTTP 403). RHR stays "D".
9. **§5 R2 "Move `_continuousHrFix`… (`notes.dart:95-100`)".** The function is at `notes.dart:96-100` (its call is at line 89). Minor.
10. **Existing fixtures.** Oura's shape in `test/data/fixtures/hc_apps.dart` contradicts Oura's page. Not in 10; fixed under R7.

---

## 5. Implementation list (value ÷ effort, highest first)

| # | Item | Effort | Files | Test cases |
|---|---|---|---|---|
| 1 | **Fixture truth (R7, part):** correct the Oura shape; add Polar-daily, Polar-once, Polar + Fitbit, MANUAL RHR and a neutral `fullWriter`. The Polar cases start **red** and stay red until #2 lands | S | `test/data/fixtures/hc_apps.dart`, `test/data/any_app_test.dart`, `any_app_repo_test.dart`, `any_app_sqlite_test.dart` | Oura: `restingHr` null and `_notSharedBy(restingHr)` = Oura after 3 nights; mixing tests keep passing on `fullWriter` |
| 2 | **Measured-value guard (R4)** | M | §2.3 list | §2.4 cases 1–10 |
| 3 | **Copy table, V-official only (R2 reduced + R6):** Polar fix line; move the Samsung special case; hedged WHOOP line | S | new `lib/domain/engine/source_setup.dart`, `notes.dart`, `features/settings/sources_screen.dart` | Polar-only → `recoveryNotShared` fix has no "continuous heart rate"; Samsung fix unchanged; WHOOP `rhrNotShared` has the membership sentence and no tier names; import test: the resolver and `recovery.dart` don't import `source_setup.dart` |
| 4 | **Names (R1):** 8 entries + a `relays` set; header date | XS | `lib/domain/engine/source_apps.dart` | `SourceApps.knownName('com.urbandroid.sleep') == 'Sleep as Android'`; `relays == {'nl.appyhapps.healthsync'}` |
| 5 | **Relay attribution (R5)** | S | `source_apps.dart` (`nameOf`), `today_planner.dart` freshness line | Device set → "Forerunner 965 via Health Sync"; no device → "Health Sync"; baseline key includes the device |
| 6 | **Sources rows (R3 reduced):** "Shares" from `daysWithData`; "Doesn't share / Not used" from `notShared` / `notMeasured` | S | `features/settings/sources_view_model.dart`, `widgets/source_picker.dart` | Samsung fixture → "Doesn't share: HRV, Resting heart rate"; Polar-daily → "Not used: Resting heart rate"; nothing on Today |
| — | **Not built:** R8 Polar BLE SDK, R9 Samsung Data SDK, R10 relay pointer | — | — | — |

**For the orchestrator (§7 edits):**
- In the "HRV when the source doesn't share it" row, record R8 (not vetoed on principle 6; blocked by Flow exclusivity and no device) and R9 (developer-mode terms, partnership).
- In "Any app", record R10: no relay is named in copy, and relays are attributed when observed.
- `ResolverConfig.notMeasured` and `EngineConfig.notMeasured` are additive contract changes, plus a new settings key for the persisted flags.
