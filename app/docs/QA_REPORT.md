# Airlog QA report: exploratory testing on the Android emulator

2026-09-29. This run replaced a predecessor QA agent that stopped without writing findings. Its evidence was triaged, re-verified where cheap, and the remaining checklist was completed. The scope was then cut to save spend: no full regression. A full pass comes later, on the reworked build.

**Setup**
- **Device:** emulator-5554, AVD airlog_api35 (Pixel 7, Android 15, 1080x2400). Health Connect is built in. No real band.
- **Builds under test,** both built 2026-09-29 around 00:40:
  - `build/app/outputs/flutter-apk/app-release.apk`, sha1 b5f2f51d ("plain"). This is the build left installed.
  - `build/app/outputs/flutter-apk/app-release-timing.apk`, sha1 79bb99f9 (`AIRLOG_TIMING=true`). Used only for the timing runs.
- **Evidence** is in `docs/screenshots/qa/`:
  - Files **01–172** are from 2026-09-28, on an OLDER build (sha1 52f84cc8). They are cited only as history.
  - Files **201–313** are from the two current builds. The predecessor's `new-release.apk` and `new-timing.apk` hash-match the outputs above.
  - A finding seen only on the old build was re-checked on the current build before being listed.
- **Code references:** file:line as read between 02:00 and 03:20. Other agents were editing the tree at the same time.
  - A † marks a file that changed after the build. Its line may have moved, so locate by the quoted symbol.
  - Every "suspected cause" was read in code. None was confirmed with a debugger.
- **Redesign tagging:** the IA stays Today · Sleep · Strain · Trends. Only purely visual findings (colours, type, tile layout) carry the tag *may be moot after redesign*.

## Summary

| ID | Sev | Area | Title | Status |
|---|---|---|---|---|
| QA-01 | P0 | Data / sync | Background worker closes the app's database every ~15 min. Every screen then fails until the process dies | confirmed (demo and live) |
| QA-02 | P1 | Demo / Today | Demo seeded between midnight and ~03:00 leaves Today empty ("No data / 0.0 / No sleep") for the whole calendar day. Live-mode fix copy shows in demo | confirmed |
| QA-03 | P2 | Performance | Android main thread stalls 1–7 s at startup. Warm start is slower than cold | confirmed |
| QA-04 | P2 | First launch | Today shell ("Preparing 90 days…") shows about 3 s before onboarding slides over it | confirmed |
| QA-05 | P2 | Onboarding | System Back on any onboarding step dismisses onboarding permanently. The on-screen Back goes to the previous step | confirmed |
| QA-06 | P2 | Health Connect | After two denials, "Connect Health Connect" is a dead end: no sheet, same snackbar, no route to HC settings | confirmed |
| QA-07 | P2 | Today | Raw `DatabaseException(database_closed 1)` is shown in the freshness line | confirmed |
| QA-08 | P2 | Widget | Home-screen widget contradicts Today after midnight (78 % / 7h 45m against "No data") | confirmed |
| QA-09 | P3 | Strain copy | "Only 100 % of waking minutes have heart rate… likely under-counts" | confirmed |
| QA-10 | P3 | Health monitor | "Your usual range is still forming" when last night is simply missing, with a 90-day baseline | confirmed |
| QA-11 | P3 | Journal | Before 05:00 the Journal labels Mon 28 Sep "Today" while the Today tab shows Tue 29 Sep | confirmed |
| QA-12 | P3 | Trends | Today's partial day counts as a reading ("Strain: Latest 0 … down 14.9"). The line drops to 0 at Today | confirmed |
| QA-13 | P3 | Sources | Sources doesn't refresh after granting in HC settings, and mode stays Demo despite "the first grant switches Airlog…" | confirmed |
| QA-14 | P3 | Live (demo) | A workout started right after connecting the demo band scores 0.0 strain / TRIMP 0 (the band rests for the first 3 min) | confirmed |
| QA-15 | P3 | Widget / privacy | After Android "Clear storage", the widget keeps showing the last health numbers until the app runs again or a 30-min update passes | confirmed |
| QA-16 | P3 | Landscape | Header, nav bar and Demo pill leave about ¼ of the height for content. The pill overlaps the rings | confirmed |
| QA-17 | P3 | Font scale 1.3 | Truncations: "PERFORMA…", "−0.1 °C vs usual +…", "Demo d…". *May be moot after redesign* | confirmed |
| QA-18 | P3 | Robustness | Process death doesn't restore the tab or selected day | confirmed |
| QA-19 | P3 | Profile | Back discards unsaved Profile edits silently | confirmed |
| QA-20 | P3 | Health Connect | Tested build requests 12 types and no SpO₂. The manifest and PLAY_RELEASE.md §2 list READ_OXYGEN_SATURATION | confirmed in build. The tree has changed since, so re-check |
| QA-21 | P3 | Copy | "Good evening" at 02:00. "Licences" row opens a page titled "Licenses". "Last data from band" in demo mode | confirmed |
| F-1 | – | Health monitor | Delta rounding "55 bpm ±0 vs usual 56" (old build 36/37b) | fixed-in-build |
| F-2 | – | Day nav | Previous-day navigation ran past the start of the data, with live copy (old build 87/88/88b) | fixed-in-build |
| F-3 | – | Splash / icon | Flutter default splash and launcher icon | fixed-in-build |
| N-1 | – | First launch | "System UI isn't responding" dialog (201–203) | not reproduced (system process, emulator) |
| N-2 | – | Export | Share sheet not visible at 4 s (264) | not reproduced (opens in about 3 s with 8 files, 291) |
| N-3 | – | Privacy | Line through "and stages." (250/252) | not a bug: the gesture-nav handle drawn over edge-to-edge content |

## Top 5 fixes by user impact

1. **QA-01 and QA-07:** stop the background worker from closing the shared sqflite handle.
   - Open with `singleInstance: false` in the worker, or don't close there.
   - Map errors to user copy.
   - Any session longer than about 15 min, or any return to a still-alive process, currently breaks every screen.
2. **QA-02:** make demo Today complete whatever the time of first launch.
   - Seed relative to the last complete wake-up, or re-seed when the night completes.
   - Or default Today to the latest day that has a Recovery.
3. **QA-06:** after denial, offer "Open Health Connect permissions" (`MANAGE_HEALTH_PERMISSIONS` with the package-name extra) and re-check on resume (QA-13).
4. **QA-03 and QA-04:** find and move the 1–7 s of Android main-thread work at startup (Perfetto on a profile build), and decide the onboarding route before the first frame.
5. **QA-05:** map system Back in onboarding to the previous step. Only persist "seen" once the user makes a choice.

## Findings

### QA-01 (P0) The background worker closes the database under the running app

**Steps**
1. Use the app in demo or live mode and leave the process alive, in the foreground or background, for 15 min.
2. WorkManager's periodic job `airlog-periodic-sync` runs in the same pid (`WM-WorkerWrapper: Starting work for …BackgroundWorker`). Job starts were observed at 01:39, 01:54, 02:24, 02:42, 02:57 and 03:12.

**Expected:** the background sync finishes and the UI keeps working.

**Actual:** breakage was confirmed on screen after the 01:39 run (233–235, predecessor), the 01:54 run (265), the 02:24 run (266–272) and the 03:12 run in live mode (305). The 02:42 and 02:57 runs are job-start observations only. After a confirmed run:
- Recovery shows "Could not load Recovery", and "Try again" does not recover.
- Journal shows "Could not open the journal".
- Sync log shows "Sync log could not load".
- The Today tab's previous-day button silently does nothing.
- The next foreground sync writes the raw exception into the freshness line (QA-07).
- Only killing the process recovers.

**Evidence**
- Current build: 233_plain_recovery_after_worker, 234_plain_today_dbclosed, 235_plain_synclog_dbclosed, 261_plain_recovery_sep6, 265_dbclosed_today_after_0154_worker_demo, 266_dbclosed_recovery_try_again_no_recover, 269_dbclosed_trends_after_0224_worker, 270_dbclosed_today_prevday, 271_dbclosed_synclog_after_0224_worker, 272_dbclosed_journal_toggle, 305_live_mode_synclog_after_worker.
- Old build: 38–41, 81, 97, 134, 152, 153.

**Cause** (read in code; still present in the tree at 03:20):
1. The worker runs `DataModule.create(background: true)` in a second FlutterEngine inside the app process, then closes it in `finally`. See `lib/data/sync/background.dart:26-32` and `lib/data/data_module.dart:127`† (`await (await db.settled())?.close()`).
2. `AirlogDatabase.open` calls `openDatabase` with sqflite's default `singleInstance: true` (`lib/data/db/sqlite_stores.dart:40`).
3. sqflite on Android keeps a static, process-wide path-to-id map (`D:/dev/pub-cache/hosted/pub.dev/sqflite_android-2.4.4/android/src/main/java/com/tekartik/sqflite/SqflitePlugin.java:59` `_singleInstancesByPath`, lookup :355, removal on close :471).
4. So the worker is handed the UI engine's connection (id 1, as in "database_closed 1") and closes it.
5. Demo mode is affected too. `backgroundSync()` reads the mode setting before its early return (`lib/data/repositories/health_repository_impl.dart:340-341`†), and that read opens the DB.

**Fix direction:**
- Open with `singleInstance: false` in the worker, or never `close()` a handle the worker didn't create.
- Also avoid DB access in the worker when demo mode is on. Read the mode from a non-DB store.

### QA-02 (P1) Demo Today stays empty all day if the seed ran before ~03:00

**Steps**
1. First launch, or delete data, between 00:00 and about 03:00. Tap "Explore with demo data".
2. Open Today. Relaunch later the same day.

**Expected:** demo Today shows a full morning (Recovery, Sleep) like every other demo day. Failing that, it falls back to the latest complete day.

**Actual:**
- Recovery "No data", Strain "0.0", Sleep "No data".
- Cards say "Wear the band to bed tonight, then open Airlog in the morning" and "Check that heart-rate data from the band reaches Health Connect", which is live-mode advice inside demo.
- "Last data from band 46 min ago" is frozen at seed time.
- It stays that way after 03:00 and for the rest of the calendar day (306, 03:13).
- A wipe at 03:15 re-seeds with the night cut at "now − 5 min": a 3h 53m night, Sleep 49 %, Recovery 61 % (311).

**Affected window,** from the generator code, confirmed at 00:52–03:13 and 03:15. It covers any demo seed between midnight and the demo's planned wake-up (about 07:30):
- Before bedtime + 4 h (about 03:00), Today is empty all day.
- From then until wake-up, the night is truncated at "now − 5 min". The low Sleep and Recovery that result stay frozen until midnight.

**Evidence:** 209_new_today_demo_light, 210_new_today_demo_scroll, 223_plain_today_0105, 257_plain_today_demo_after_switch, 267_demo_today_0212_empty_good_evening, 306_demo_today_0314_still_empty, 311_demo_today_after_wipe_reseed_0315.

**Cause**
- `lib/data/services/demo/demo_generator.dart:426-432`: a night is included only if `now` is past the planned wake time, or at least 4 h after bedtime. Today's minute HR ends at the seed's `now`.
- `lib/data/sync/demo_seeder.dart:50-52`: `isFresh()` re-seeds only when the calendar day changes. The partial day is therefore frozen until midnight.
- The fix copy comes from `lib/domain/engine/notes.dart` (`_wearFix`, `strainPartialHr`†), with no demo variant.

**Fix direction:**
- Generate the demo relative to a fixed "morning" (for example, treat the current day as the last complete wake-up).
- Or re-seed when the night becomes complete.
- Or make Today default to the latest day with a Recovery when today has none.

### QA-03 (P2) The startup main thread stalls; warm start is slower than cold

**Steps:** run the timing build and follow the method in the timing section.

**Actual:**
- `Choreographer: Skipped 40–128 frames! The application may be doing too much work on its main thread` appears between `first_frame_built` and `db_open`. This was captured in full logcat for cold 4 and warm 4.
- `db_open` took 87–2276 ms on cold starts and 2261–7660 ms on warm starts.
- `first_frame_rasterized` was 1.1–2.5 s after `main()`.
- Warm starts measured 3.6–9.4 s, while cold starts measured 2.1–4.8 s.

**Expected:** first rasterized frame under about 500 ms after `main()`, and warm not slower than cold.

**Cause (unconfirmed, needs a Perfetto trace on a profile build):**
- Plugin work on the Android main thread right after `runApp` delays both the sqflite open reply and first-frame rasterisation.
- Candidates are the calls made from `DataModule.open()`: `BackgroundSync.register()` → `Workmanager().initialize` / `registerPeriodicTask` (`lib/data/sync/background.dart:41-51`), path_provider, and the home_widget push.
- For warm starts, a second engine attaching in the same process repeats all of this.

### QA-04 (P2) First launch shows the Today shell before onboarding

**Steps:** `pm clear`, then launch.

**Actual:**
- For about 3 s the Today tab is visible, with skeleton rings, "No data from band yet · syncing…", "Preparing 90 days of demo data…" and the "Demo data" pill.
- Only then does onboarding slide in.
- A new user's first frame is an empty dashboard labelled demo, before they have chosen anything.

**Evidence:** 201_new_timing_launch_t0, 202_new_timing_launch_t1, 273_first_launch_t_amstart (taken about 3 s after `am start`).

**Cause:**
- `maybeShowOnboarding` pushes `/onboarding` only after the shell's first frame. It awaits `FileOnboardingStore.seen()`, a path_provider call that queues behind the main-thread stall from QA-03.
- See `lib/features/onboarding/onboarding_view_model.dart:88-103` and `:46-53`.

**Fix direction:** decide the initial route before the first frame, for example with a synchronous flag from `MainActivity.getInitialRoute` or SharedPreferences read in `main`.

### QA-05 (P2) System Back skips onboarding for good

**Steps**
1. Fresh install, onboarding step 1 or step 2.
2. Press system Back.
3. Relaunch the app.

**Expected:** Back on step 2 returns to step 1, like the on-screen "Back" button. On step 1, Back either exits the app or asks. Onboarding comes back next launch unless a choice was made.

**Actual:**
- Onboarding is popped from any step and the app lands in demo Today. After midnight that is the empty Today of QA-02.
- The dismissal is persisted, so onboarding never returns.
- The user never sees the privacy step or the Health Connect or Demo choice.

**Evidence:** 222_plain_onboarding_back, 274_onboarding_system_back_result, 313_onboarding_step2_system_back_exits. Relaunch confirmed with no onboarding.

**Cause:** `lib/features/onboarding/onboarding_screen.dart:84-89` wraps the flow in `PopScope(onPopInvokedWithResult: … markSeen())`. The comment says it is intentional ("Backing out counts as seen"). System Back isn't mapped to the page-level Back.

### QA-06 (P2) Dead end after two Health Connect denials

**Steps**
1. Settings → Sources → Connect Health Connect → Continue → Don't allow.
2. Repeat step 1 once more.
3. Try a third time.

**Expected:** after Android stops showing the sheet, the app explains this and offers to open Health Connect's Airlog permissions page. The intent `android.health.connect.action.MANAGE_HEALTH_PERMISSIONS` with the package-name extra works on this device.

**Actual:**
- The third and fourth attempts show no sheet at all.
- The same snackbar appears each time: "No access granted. Airlog cannot read your band without it."
- There is no other action. Onboarding step 3 behaves the same (239, "Not connected" with "Try again").

**Evidence:** 297_hc_sheet_first_request, 298_hc_third_request_result, 299_hc_fourth_request_snackbar, 238_plain_hc_denied_onboarding, 239_plain_hc_third_request.

**Cause:** `lib/features/settings/sources_screen.dart:87-103`† (`connectHc`) and `lib/features/onboarding/onboarding_screen.dart:472`. Neither has a branch for "request returned with nothing granted and no sheet shown".

### QA-07 (P2) Raw exception text in the Today freshness line

**Steps:** trigger QA-01, then return to Today once a foreground sync has run (on resume, after 5 min).

**Expected:** plain-language error copy with a next step.

**Actual:** "Last data from band 10 min ago · DatabaseException(database_closed 1)".

**Evidence:** 234_plain_today_dbclosed, 265_dbclosed_today_after_0154_worker_demo. Old build: 37b.

**Cause:**
- `lib/data/repositories/health_repository_impl.dart:416`† sets `message: '$e'`.
- `lib/design/components/status_lines.dart:52,84` prints it verbatim.

**Fix direction:** map errors to user copy ("Couldn't read stored data. Restart Airlog.") and log the detail.

### QA-08 (P2) The widget and Today disagree after midnight

**Steps:** in demo at 01:35, compare the home-screen widget with the Today tab.

**Expected:** the widget and Today show the same day's numbers, or the widget says which day each value is from.

**Actual:**
- Widget: "Airlog · demo 78 % Recovery, 0.0 Strain, 7h 45m Sleep". That is Monday's recovery and sleep mixed with Tuesday's strain.
- Today tab, same moment: Recovery "No data", Sleep "No data".

**Evidence:** 257_plain_today_demo_after_switch, 258_plain_widget_demo.

**Cause:** this is by design in `lib/data/services/widget/widget_sink.dart:9-11,29-42` (newest day *with* each value). The Today tab uses the calendar day.

**Fix direction:** pick one rule for both. The widget's rule is the friendlier one. Label the day on the widget if the values come from different days.

### QA-09 (P3) The strain note contradicts itself: "Only 100 % of waking minutes"

**Steps:** in demo, open Today for the current day before about 05:00, then scroll to the notes.

**Expected:** the note gives the real reason: few samples so far, because the day has only just started.

**Actual:** Today, early in the day, shows "Strain from partial heart rate. Only 100 % of waking minutes have heart rate and there are no workouts or steps…".

**Evidence:** 210_new_today_demo_scroll, 311_demo_today_after_wipe_reseed_0315.

**Cause:**
- `lib/domain/engine/strain_fallback.dart:156`† sets `sparse = s.length < minSamples || coverage < minCoverage`. The note fires on the sample count (under 300 samples early in the day).
- `lib/domain/engine/notes.dart:185-190`† then prints only the coverage.

**Fix direction:** word the note by the actual trigger, or suppress it while the day is in progress.

### QA-10 (P3) Health monitor says the range is "still forming" when data is only missing

**Steps:** in demo, open Today for the current day before the night is complete, then scroll to Health monitor.

**Expected:** "No data for last night yet" (or similar). The range is not forming, because 90 days of history exist.

**Actual:** on a demo day with 90 days of history but no night yet, the subtitle reads "Last night · your usual range is still forming".

**Evidence:** 210_new_today_demo_scroll.

**Cause:** `lib/features/today/widgets/health_monitor.dart:75` returns this string whenever no tile has a judged value, which covers "no data" as well as "no baseline".

### QA-11 (P3) The Journal calls yesterday evening "Today"

**Steps:** at 01:14 or 02:13, open the Journal.

**Expected:** the same day words as the Today tab, for example "Last evening · Mon 28 Sep".

**Actual:** the header reads "Today, Monday 28 September", while the Today tab reads "Today, Tue 29 Sep". The Today card says "Logged tonight".

**Evidence:** 232_plain_journal, 268_journal_today_label_mon28_at_0213.

**Cause:**
- `lib/features/journal/journal_screen.dart:82` passes the evening key (`eveningKeyOf`, `lib/domain/day_key.dart:65-68`, which rolls over at 05:00) as `today:` to `DayNavigator`.
- `DayNavigator` labels that key "Today" (`lib/design/components/navigation_bits.dart:99-101`).
- Fix direction: label it "Tonight" or "This evening", or pass the calendar day.

### QA-12 (P3) Trends count today's partial day

**Steps:** in demo early in the day, open Trends and switch between 7D, 30D and 90D.

**Expected:** the in-progress day is excluded from trends, or marked as partial.

**Actual:**
- The Trends semantics read "Strain: Latest 0, ranging 0 to 15.8, down 14.9 across 90 readings" at 90D, "down 10.4" at 7D and "down 7.8" at 30D.
- The chart's strain line drops to 0 at "Today" (286).
- The 7-day and 28-day strain means likely include the 0 too.

**Evidence:** 286_font13_trends, 269_dbclosed_trends_after_0224_worker, and the uiautomator text recorded during the 7D/30D/90D checks.

**Fix direction:** exclude the in-progress day from trend deltas and means, or mark it as partial.

### QA-13 (P3) Sources doesn't refresh after granting in Health Connect settings

**Steps**
1. After QA-06, grant all types, history and background in HC → App permissions → Airlog.
2. Return to Airlog.

**Expected:** Sources shows "Connected · 12 of 12" on return. The mode follows what the card promises, or the card copy changes.

**Actual:**
- Sources still reads "Not connected · 0 of 12 data types granted" until you leave and re-enter it.
- Data mode stays Demo, although the card says "the first grant switches Airlog to your band's data".

**Evidence:** 300_sources_stale_after_hc_settings_grant.

**Fix direction:** re-query permissions on resume.

### QA-14 (P3) Demo live workout started right after connecting scores 0.0

**Steps:** Live heart rate → scan → connect the demo band → Start workout immediately → stop at about 2 min → HRR → Save.

**Expected:** a demo workout shows workout-like heart rate and a non-zero strain.

**Actual:**
- Summary shows 0.0 strain, average 64 / peak 70 bpm, TRIMP 0.
- "Saved… in today's strain", but today's strain stays 0.0.
- The live screen shows 120 bpm shortly after.

**Evidence:** 227_plain_live_summary, 228_plain_live_saved, 230_plain_strain_after_live.

**Cause:** `lib/data/services/demo/demo_live_hr_service.dart:147-150` keeps the demo band at rest (about 64 bpm) for the first 180 s after connecting, then ramps.

**Fix direction:** start the demo profile's ramp when a workout starts.

### QA-15 (P3) The widget shows stale health numbers after "Clear storage"

**Steps:** with the widget on the home screen, run `pm clear app.airlog.airlog` (Settings → Apps → Clear storage) and look at the home screen before opening the app.

**Actual:** the widget still shows "Airlog · demo 61 % / 0.0 / 3h 53m".

**Evidence:** 312_widget_after_pm_clear.

**Expected:** the widget clears, or shows "–", once the app data is gone.

**Cause:** `android/app/src/main/res/xml/airlog_widget_info.xml` sets `updatePeriodMillis="1800000"` (30 min), and there is no staleness indicator.

The in-app "Delete all data" refreshed the widget in demo mode (310). That refresh comes from the immediate re-seed pushing new values, so whether a live-mode wipe clears the widget is untested.

**Impact:** with real data, the last health scores stay visible on the home screen after the user cleared the app.

### QA-16 (P3) Landscape leaves little room for content

**Steps:** rotate to landscape (`user_rotation 1`).

**Expected:** a compact header and nav in landscape, with no overlaps. Locking to portrait is also acceptable.

**Actual:**
- The large header and the bottom nav take most of the 1080 px height.
- Today shows only the top half of the rings, and the "Demo data" pill overlaps the Strain ring.
- No crash, and state is kept across rotation.

**Evidence:** 277_rot_today_landscape, 278_rot_strain_landscape, 279_rot_trends_landscape, 280_rot_settings_landscape, 281_rot_back_portrait.

### QA-17 (P3) Truncation at font scale 1.3 (may be moot after redesign)

**Steps:** `settings put system font_scale 1.3`, then visit Today, Recovery, Sleep, Strain, Trends, Settings and Live.

**Expected:** no truncated labels or values.

**Actual:**
- Sleep ring label: "PERFORMA…".
- Health monitor skin-temp tile: "−0.1 °C vs usual +…".
- Provenance line: "Sleep mean RMSSD · Demo d…".
- Everything else reflows.

**Evidence:** 284_font13_sleep, 287_font13_today_monitor, plus 282, 283, 285, 286, 288 and 289, which are OK.

### QA-18 (P3) Process death doesn't restore state

**Steps:** Strain tab → Sat 26 Sep → Home → `am kill` → relaunch.

**Expected:** the app reopens on the Strain tab at Sat 26 Sep, with state restored.

**Actual:** the app returns to the Today tab and today's date.

**Evidence:** 292_process_death_restore.

### QA-19 (P3) Back discards unsaved Profile edits without asking

**Steps:** Settings → Profile → type a birth year → system Back.

**Expected:** a "Discard changes?" prompt, or an autosave.

**Actual:** the value is lost silently. Settings still shows "No birth year".

**Evidence:** 293_profile_1990_typed. Saving works: Pulse Age 24.6 appeared in Trends.

### QA-20 (P3) The tested build doesn't request SpO₂

**Steps:** Settings → Sources → Connect Health Connect → Continue, then scroll the system sheet.

**Expected:** the requested types match the manifest and PLAY_RELEASE.md §2.

**Actual:**
- The system sheet lists 12 types: Distance, Exercise, Heart rate, HRV, Respiratory rate, Resting HR, Skin temperature, Sleep, Steps, Total calories burned, VO₂ max, Weight. History and background come on a follow-up screen.
- Oxygen saturation isn't requested, and Sources says "12 of 12".
- `AndroidManifest.xml` declares `READ_OXYGEN_SATURATION`, and `docs/PLAY_RELEASE.md` §2 lists it among 15 permissions.
- `lib/data/services/health_connect/hc_types.dart`† now includes `spo2`. The file was modified at 02:25, after the build, so re-check on the next build.

**Evidence:** 297_hc_sheet_first_request, 237_plain_hc_sheet_top, 246_plain_live_sources.

### QA-21 (P3) Copy nits

**Steps:** open Today at 02:12, open Settings → Licences, and read the Today freshness line in demo.

**Expected:** consistent, mode-appropriate copy.

- The greeting reads "Good evening" from 00:00 to 04:59 (`lib/features/today/today_screen.dart:41-43`). See 267.
- The Settings row "Licences" opens Flutter's page titled "Licenses".
- Demo mode says "Last data from band 12 min ago". There is no band in demo.

## Fixed in build / not reproduced

- **F-1:** health monitor delta rounding.
  - Old build: "55 bpm ±0 vs usual 56" (37b).
  - Current build: 20 consecutive days (9–28 Sep) of HRV and RHR tiles were scanned, and every delta equals value minus usual. "Same as usual" is used for zero.
- **F-2:** previous-day navigation before the data start.
  - Old build: 87, 88, 88b.
  - Current build: "Previous day" is disabled at Thu 2 Jul, the first demo day.
- **F-3:** splash and launcher icon.
  - The current build has the custom green-ring splash in light and dark (214, 215) and an adaptive launcher icon (217).
  - A monochrome themed-icon layer is present (`res/mipmap-anydpi-v26/ic_launcher.xml`).
- **N-1:** the "System UI isn't responding" dialog (201–203) belongs to the SystemUI process. It did not recur in 2 first launches and about 15 relaunches. Treated as emulator load.
- **N-2:** export. The share sheet opens about 3 s after tapping Export, offline too, with 8 files:
  - `airlog_export.json`
  - `days.csv`
  - `hr_minutes.csv`
  - `raw_hr.csv`
  - `raw_hrv.csv`
  - `raw_scalars.csv`
  - `raw_sleep.csv`
  - `raw_workouts.csv`

  Evidence: 291_airplane_export_sharesheet.
- **N-3:** the "strike-through" on the Privacy screen is the system gesture-nav handle drawn over edge-to-edge content (a crop of 250 was checked).
- **Dark flash:** none. Frame brightness from screen recordings of a cold start: dark mode goes home → dark splash → dark app with no bright frame (275). Light mode goes home → light splash → app with no dark frame (276).

## Startup timing (app-release-timing.apk, emulator, 02:27–02:34)

**Method**
- `am start -W` gives TotalTime ("Displayed").
- `logcat -s flutter` gives the `airlog.timing` marks, in ms since `main()`.
- **Cold:** `force-stop`, then start.
- **Warm:** system Back, so the activity is destroyed while the process lives, then start.
- **Hot:** Home, then start.
- **First launch:** `pm clear`, then start. The seed starts at `main()`, before the user taps anything.

| Run | Displayed (ms) | first_frame_built | db_open at / took | first_frame_rasterized | demo_seed total (generate / bucket / resolve+engine / encode / write) | data ready (`sync_demo` at) |
|---|---|---|---|---|---|---|
| First launch (pm clear) | 2740 | 60 | 1183 / 1177 | 1309 | 3494 (1709 / 71 / 379 / 337 / 998) | 5012 (about 6.8 s wall-clock after `am start`) |
| Relaunch after a kill mid-seed (+3.2 s) | 2050 | 45 | 981 / 973 | 1102 | 1492 (706 / 51 / 145 / 143 / 447) | 2654. All 90 days present (Trends 90D "across 90 readings", 2 Jul to Today) |
| Cold 1 | 2395 | 148 | 1133 / 1124 | 1255 | – | – |
| Cold 2 | 2120 | 1006 | 1025 / 1016 | 1137 | – | – |
| Cold 3 | 2780 | 73 | 99 / 87 | 1495 | – | – |
| Cold 4 | 4809 | 113 | 2285 / 2276 | 2541 | – | – |
| Warm 1 | 4947 | 265 | 2665 / 2641 | 3125 | – | – |
| Warm 2 | 9375 | 485 | 7693 / 7660 | 8417 | – | – |
| Warm 3 | 3638 | 392 | 2282 / 2261 | 2704 | – | – |
| Warm 4 | 3990 | 645 | 2736 / 2727 | 2960 | – | – |
| Hot 1 / 2 / 3 | 1076 / 1162 / 1409 | – | – | – | – | – |

**Summary:**

| Start type | Displayed | Median | first_frame_rasterized after `main()` |
|---|---|---|---|
| Cold | 2.1–4.8 s | ≈2.6 s | 1.1–2.5 s |
| Warm | 3.6–9.4 s | ≈4.5 s | – |
| Hot | 1.1–1.4 s | – | – |

- **First launch:** data is ready 5.0 s after `main()`, and the seed takes 3.5 s.
- **Plain build, cold, for reference:** 3679 ms in this run and 4168 ms in the predecessor's run.
- Emulator numbers are inflated compared with a phone. See QA-03 for the frame-skip evidence.

## Checklist coverage (original brief)

| # | Item | Result | Evidence (current build unless noted) |
|---|---|---|---|
| 1 | First launch: timings | done | timing table |
| 1 | Splash, launcher icon, dark flash | pass | 214, 215, 217, 275, 276 |
| 1 | Onboarding 3 steps, "Explore with demo data" | pass, with QA-04 and QA-05 | 203–208, 273, 274, 313 |
| 2 | Today, Recovery (ring tap), Sleep, Strain | pass, with QA-02, QA-09 and QA-10 | 209–211, 257, 260–263, 282–285 |
| 2 | Cross-screen consistency | pass | Yesterday on Today (78 / 12.8 / 98) matches Recovery 78 %, Strain 12.8 and Sleep 98 % (282–285). Sep 6: Today 34 / 4.5 / 100 matches Recovery, Strain and Sleep (260–263). Exceptions are the widget (QA-08) and the Journal (QA-11) |
| 2 | Trends 7/30/90, Pulse Age after birth year | pass, with QA-12 | 286, semantics text; Pulse Age 24.6 shown after saving 1990 |
| 2 | Journal toggle, insights, kill and relaunch persistence | pass, with QA-11 | 232, 268; Alcohol + Late caffeine persisted across force-stop |
| 2 | Live demo: scan → connect → workout → stop → HRR → save | pass, with QA-14 | 224–228, 230 |
| 2 | HRV check | partial: started and cancelled on the current build, completed on the old build | 229; old 60–62 |
| 2 | Settings, Sources, Profile, Sync log | pass, with QA-13 and QA-19 | 245, 246, 248, 259, 212 |
| 2 | Export share sheet and file list | pass | 291 (8 files) |
| 2 | Methodology, Licences, Privacy, Diagnostics probe | pass, with QA-21 | 295; 249 (live probe); 250 |
| 2 | Delete all data: hold and cancel, then wipe | pass | Release at 1 s cancels. A 2.6 s hold gives "All data deleted." The sync log keeps only the new seed, journal tags are gone, the widget updates (307–311). In demo mode the wipe re-seeds at once (see QA-02) |
| 3 | Day switching to the illness episode (Sep 5–8) | pass | 260, 260b, 261–263 (Recovery 34 % yellow, 4 signals out of range, monitor alert); Sep 8 28 %; 20-day tile scan |
| 4 | Live mode, empty HC: honest status cards | pass | 243, 244, 301 ("No data yet / No sleep yet / No strain yet / No trends yet", no NaN) |
| 4 | Real HC sheet: types, history and background screen | done, with QA-20 | 237, 241, 241b, 297 |
| 4 | Deny permissions | fail (QA-06) | 238, 239, 298, 299 |
| 4 | Switch back to Demo, data still there | pass | 256, 257; Yesterday 78 % after switching at 03:13 |
| 4 | BLE in live mode: permission prompt, deny, allow, scan | pass | 302, 303, 304 ("No heart-rate sensors found" guidance) |
| 5 | Privacy policy from HC (warm and cold) and the rationale intent | pass | 250, 251, 252 |
| 6 | Home-screen widget | pass, with QA-08 and QA-15 | placed via the launcher picker by the predecessor (old 107–110). Live 254, demo 258, after wipe 310, after clear 312 |
| 7 | Rotation | pass, with QA-16 | 277–281 |
| 7 | Background/foreground (hot) | pass | hot starts 1.1–1.4 s |
| 7 | Kill mid-seed on first launch | pass | timing table, row 2 |
| 7 | Font scale 1.3 | pass, with QA-17 | 282–289 |
| 7 | Reduced motion | pass | With Android "Remove animations" (all three global scales at 0), cold start and day change show no multi-frame motion (frame-diff of screen recordings). `animator_duration_scale=0` alone does not trigger it, because Flutter follows `transition_animation_scale`, so test with the real setting |
| 7 | Offline (airplane mode) | pass | 290, 291 (demo, Trends and Export all work) |
| 7 | Process death (`am kill` in background) | pass, with QA-18 | 292 |
| 7 | Clear data | pass, with QA-15 | onboarding returns after `pm clear`. The widget is stale (312) |
| 8 | Logcat after each step | no app `E flutter` / `FATAL` / `AndroidRuntime` lines in any run | The release build does not log the QA-01 exception either, so it is invisible in logcat |

## Not tested (and why)

- **Real band:** BLE connection, HR streaming and RR-based HRV check. There is no device, and the emulator has no BLE peripherals.
- **Enhanced mode:** Google Health API sign-in. Signing in to accounts is out of bounds for this run.
- **Live mode with real Health Connect data:** backfill, change tokens, per-type sync log with records. HC on the emulator is empty and no test data was inserted.
- **HRV check to completion** on the current build. Stopped after the scope cut; it was completed on the old build (60–62).
- **Themed icon re-render** on the current build. The monochrome layer exists in res. The predecessor's home-screen shots (219, 219b) are ambiguous.
- **Full dark-mode pass** of every screen on the current build. Only splash and cold start were checked; the old build has 160–169. Deferred to the post-rework regression.
- **Root cause of the QA-03 main-thread stall.** It needs a Perfetto/systrace capture on a profile or debuggable build, and no rebuild was allowed.
- **Midnight rollover** while the app is open, timezone and DST changes, Doze or battery saver effects on the worker, low storage, TalkBack walkthrough.
- **Coach features.** Not part of this charter; the code is being reworked.

## Device state left behind

- **Installed:** `app-release.apk` (plain). The app was reset with `pm clear` and onboarding completed with "Explore with demo data". Health Connect permissions granted during testing may persist at HC level.
- **Restored settings:**
  - font_scale 1.0
  - animator_duration_scale deleted (it was unset)
  - transition and window animation scales 1.0
  - user_rotation 0
  - accelerometer_rotation 1
  - night mode off
  - airplane mode off
- **Widget:** still placed on the home screen.
