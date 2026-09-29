# Airlog copy review (Phase A: audit and proposal)

Status: **proposal, nothing changed in code yet.** Written 2026-09-30 against the source on branch `airlog/fallback-qa` (read-only). Phase B carries out whatever the product owner approves.

What the product owner asked for: copy that reads **"as easy as possible to understand"**, at about a grade 5–6 reading level. It should sound like a friend talking, lead with words, and put the numbers second. Most of this copy is **generated from the day's data**, so templates matter more than static strings (§4).

Sources audited: every `Text(` or string literal under `lib/features/**`, `lib/design/**` and `lib/app/**`, plus `lib/domain/engine/{today_planner,notes,health_monitor,recovery,strain}.dart`, `lib/domain/today_plan.dart`, `lib/domain/results.dart`, `lib/domain/models.dart`, `lib/data/coach/{insight_templates,offline_client}.dart`, `lib/domain/coach/{prompts,safety,coach_service,coach_contracts}.dart`, and the 40 renders in `test/goldens/screens/`.

> **Heads-up: several goldens are stale.** They no longer match the source strings, so this review cites the **source**, not the PNG. Stale examples:
> - The fallback answer "I couldn't check every number in my answer…" comes from `test/support/coach_fixtures.dart:93`. The app's real line is `prompts.dart:155`.
> - Trends shows "Optimal". The source now says "Similar".
> - The onboarding Steps and Skin-temperature lines and the birth-year hint.
> - The Settings Privacy and Licences subtitles.
> - The coach "Anything that names you" line.
>
> Phase B has to re-record every screen golden in any case (§6).

---

## 0. The approach in one picture

Every screen gets three layers. This keeps the words simple **and** keeps the app explainable (principle 1):

| Layer | What goes there | Example (Today, a good morning) |
|---|---|---|
| **1. Words** (headline, summary, action titles and whys) | A plain answer, a plain reason and a plain next step. No score names or units in headlines or action titles. | "Your body is ready" · "Your heart is well rested today." · "A hard workout is fine today" · "A long run, intervals or a tough gym session." |
| **2. Chips** (evidence) | The numbers behind the words, each with its unit and "usual". | `Recovery 78%` · `HRV 53 ms · 13% above usual` |
| **3. ⓘ and detail** (explain sheets, Methodology) | The formulas, constants and citations. They stay, with a plain one-line lede on top. | "How Recovery works" → weights, z-scores, Plews et al. |

---

## 1. Voice and tone

The voice is one calm friend who knows your numbers. Tone shifts with the stakes: warm on good days and onboarding, neutral in settings, plain and serious in safety and data-loss copy.

| # | Rule | Do | Don't |
|---|---|---|---|
| V1 | **Answer first, then the reason, then the number.** The number goes in a chip or ⓘ unless it *is* the instruction (a bedtime). | "Your body is ready." + chip `Recovery 78%` | "Recovery 78%: HRV is 13% above your usual and resting HR below your usual (53 vs 56 bpm)." |
| V2 | **Aim for grade 5–6: short sentences (≤ 15 words), one idea each, everyday words.** | "You're a bit short on sleep from recent nights." | "Tonight's sleep target is 7 h 53 m, with 58 m of sleep debt carried." |
| V3 | **Headlines and action titles carry no score names, units or ranges.** Start actions with a verb, or with "A … workout is fine". | "A hard workout is fine today" | "Room to push: strain 14–17" |
| V4 | **Name things the way people say them, and keep one word per idea** (glossary §2). Tap ⓘ to explain a term the first time it appears on a screen. | "resting heart rate", "breathing rate", "blood oxygen", "your usual", "missed sleep" | "RHR", "respiratory rate", "SpO₂", "baseline", "sleep debt", "normal" and "usual" mixed |
| V5 | **Write numbers and times the way people say them.** Durations: `7h 53m`, `45 min`, `8h`. Times follow the phone's 12/24-hour setting (`11:35 pm` or `23:35`). Show a range only where it helps a decision. | "Try to be asleep by 11:35 pm" | "Aim for bed by 23:35", "7 h 53 m", "7:01" used for a duration |
| V6 | **Stay honest.** Claim only what the data shows. Keep "without HRV", "sample data" and "early estimate" visible but friendly. Never say or imply a guess. | "Airlog is still learning what's normal for you, so today's score may change." | "Last night's signals were at or better than your usual" when the score is only green (not true for every green day) |
| V7 | **Stay calm and non-medical.** Describe the pattern and suggest how to notice it. Never name a condition. No blame and no "!". Safety copy keeps its meaning word for word. | "Your resting heart rate is higher than usual. This is a pattern in your numbers, not a diagnosis." | "Signs of illness", "you failed your target", "Great job!" |
| V8 | **Cut engineering words from the main UI.** Method names, acronyms and implementation details go in ⓘ or Methodology. | "Heart-rate recovery: your heart rate dropped 29 beats in the first minute." | "HRR-60, Cole et al. 1999", "Cross-check: TRIMP 266 (Banister)", "--dart-define=GOOGLE_OAUTH_CLIENT_ID" |

House style: sentence case everywhere. Use "you", never "the user". Avoid "we" in errors. Never assemble a sentence from fragments (each variant in §4 is a full template). Use "Try again" for retries, and verb-first button labels.

---

## 2. Glossary (one term per idea)

The **user word** is the only word the UI uses for the idea. The ⓘ line is the one-sentence explanation shown the first time the term appears on a screen (an explain-sheet lede or a tooltip). Engine names stay as they are in code.

| Idea (engine name) | User word | ⓘ one-liner | Replaces |
|---|---|---|---|
| Recovery score | **Recovery** | "How ready your body is today, from 1 to 99%. Airlog compares last night's heart and sleep data with your usual." | — |
| Recovery zones green / yellow / red | **Good / Fair / Low** (colours stay) | "Good is 67–99%, Fair is 34–66%, Low is 1–33%." | "Green zone", "Green · 67 and above" (Today already says Good/Fair/Low) |
| Strain score | **Strain** on detail screens and **effort** in Today's words | "How hard your heart worked today, from 0 to 21. The higher it gets, the harder it is to climb." | "load" in user copy |
| Strain target (`StrainResult.targetStrain`, shown as the range `targetRange`) | **effort goal** (label: **Goal**) | "How much effort suits today. It comes from your Recovery: lower Recovery, lighter goal." | "strain target", "target strain", "Target" |
| Effort bucket (new, §4.1) | **rest / easy / moderate / hard / very hard** | (the action's why gives an example activity) | "Room to push", "Move gently: strain 2–5" |
| Heart-rate display zones 1–5 | **Zone 1 Very light · 2 Light · 3 Moderate · 4 Hard · 5 Max** | "Zones show how hard your heart is working, from your resting heart rate up to your max." | "70–80 % HRR", bare "Zone 3" |
| HRV (RMSSD) | **HRV** (spelled out once: "heart rate variability") | "Heart rate variability: tiny changes in the time between heartbeats. Higher than your usual often means you're well rested." | "RMSSD", "Sleep mean RMSSD", "Deep-sleep RMSSD" (these stay in Methodology and provenance ⓘ only) |
| Resting HR | **resting heart rate** in sentences; **Resting HR** only in tiles and chips | "Your heart rate when you're fully at rest, mostly during sleep. Lower than your usual often means you're well rested." | "RHR", "resting-HR" |
| Sleeping HR (4 h mean) | **sleeping heart rate** | "Your average heart rate in the first 4 hours of sleep. Airlog uses it when your app doesn't share resting heart rate." | "Sleeping HR (4 h mean)" |
| Respiratory rate | **breathing rate** | "Breaths per minute while you sleep." | "Respiration", "respiratory rate" |
| SpO₂ | **blood oxygen** | "How much oxygen your blood carries overnight, as a percent." | "SpO₂" as a label (keep "SpO₂" in the Health Connect permission list, where Android uses it) |
| Skin temperature delta | **skin temperature** | "How much warmer or cooler your skin was overnight than your tracker's usual." | "Skin temp" (tile title may keep "Skin temp" to fit) |
| Baseline (mean) | **your usual** | "Your own average over your last 30 nights. Airlog compares you with you, not with other people." | "baseline", "normal", "normal for you", "your normal" |
| Band (mean ± 1.65 SD, floored) | **your usual range** | "Where about 9 in 10 of your nights fall." | "band", "shaded band", "band of normal variation" |
| Calibrating (< 5 nights) | **Learning** ("Learning · 3 of 14 nights") | "Airlog needs a few nights to learn your usual. Scores start after 5 nights and settle after 14." | "Calibrating", "Baseline night 3 of 14", "Still learning your baseline" |
| Provisional (5–13 nights, or low confidence) | **early estimate** | "Airlog is still learning your usual, so this score may shift." | "Provisional", "provisional" |
| New source re-learning | **learning your {App} data** | "You switched apps, and each app measures a little differently, so Airlog is learning your usual again." | "Re-learning your normal", "New HRV baseline" |
| Without HRV (`withoutHrv`) | **without HRV** (keep, as principle 6 requires) | "Your app didn't share HRV, so Recovery used your other signals. It's less exact." | — |
| Sleep target / need (`needMinutes`) | **sleep goal** | "How much sleep suits you tonight: your usual amount, plus a little extra if you're short on sleep or had a hard day." | "sleep target", "sleep need", "need" |
| Sleep debt | **missed sleep** | "Sleep you needed but didn't get over recent nights. It goes down when you sleep longer than your goal." | "sleep debt", "debt", "Debt after the night" |
| Sleep performance | **% of your sleep goal** (label: **Sleep**) | "How much of your sleep goal you got. 100% means you met it." | "Performance", "sleep performance" |
| Need breakdown: baseline / debt share / strain boost | **usual need / catch-up / extra after a hard day** | (in "How your sleep goal is set") | "Baseline", "Debt share", "Strain boost" |
| Sleep consistency | **Consistency** | "How close your bed and wake times were to your last 4 nights. 100% means the same times." | "43 % against your previous 4 nights" |
| Restorative (deep + REM) | **Deep + REM** | "The deepest and dreaming stages of sleep." | "Restorative" |
| Efficiency | **asleep in bed** | "The share of your time in bed that you were asleep." | "Efficiency", "asleep of in bed" |
| Light stage (HC "light") | **Light** | — | "Core" (sleep_screen.dart:349, Apple's word) |
| Training load (ACWR) | **Training load**, with the verdict **Less than usual / About usual / More than usual / Much more than usual** | "Your effort over the last 7 days compared with the last 4 weeks." | "Acute:chronic ratio", "Lower / Similar / Elevated / High", "Optimal", "Detraining" |
| TRIMP | (not in the main UI) | Methodology only: "A second way to measure effort, used to double-check Strain." | "Cross-check: TRIMP 266 (Banister)", "TRIMP (cross-check)" |
| HRR-60 | **heart-rate recovery** | "How far your heart rate drops in the first minute after you stop." | "HRR-60", "Cole et al. 1999" (move to Methodology) |
| Health Monitor | **Overnight signals** (the Today tiles and alert) | "Five things your tracker measures while you sleep, each compared with your usual range." | "Health Monitor" in user copy (keep it as the Methodology section name) |
| Concerning vital | **outside your usual range** / **higher (or lower) than usual** | — | "elevated", "values outside your baseline", "off your usual" |
| Demo mode | **Sample data** | "Made-up data so you can look around. None of it is yours." | "Demo", "Demo data", "Synthetic", "Synthetic data" |
| Live mode | **My data** | — | "Live" (it clashes with "Live heart rate") |
| The wearable | **tracker** | — | "band" (status_lines.dart:207, safety.dart:141,159, offline_client.dart:682,1009,1118, Diagnostics) |
| Coach feature | **Coach** (screen title and More menu). Entry buttons stay verbs: "Ask about this". | — | "Ask" as a feature name (screen title `coach_screen.dart:251`, privacy title "Ask, the coach", "Ask is turned off") |
| On-device engine | **On this phone** | "Answers set questions from your data. No AI, nothing sent." | "On-device", "On-device (no AI model)" |
| Cloud engine | **Claude** / **Gemini** (with "your key") | — | "cloud engine" in buttons ("Turn off the cloud engine" → "Turn off Claude") |
| Coach modes | **With my data / General only** (the same words in the chip and in setup) | "With my data: Coach looks up your numbers and checks every one it quotes. General only: it can't see your data." | "Use my data" vs "Uses your data" (two forms of one idea) **(decision D7)** |
| Verified answer | **numbers checked** | "Coach found every number in this answer in your data." | "Checked against your data · 3 numbers" |
| Fallback facts table | **just your numbers** | — | "Showing facts only — couldn't verify the answer" |
| Memory | **What Coach knows** (keep) | — | — |
| Version | **Score formula version** | — | "Algorithm version" |

---

## 3. Screen by screen

How to read the tables:
- **P1** confusing, jargon or dishonest. **P2** clunky. **P3** polish.
- **Why** names the rule it breaks (V1–V8 in §1, or G for the glossary).
- **Where** is `file:line` under `lib/`.
- `{name}` marks a placeholder the code fills in.
- Proposed strings are **paste-ready**: exact text, sentence case, curly apostrophes where the file already uses them.
- "Keep" rows list strings that were reviewed and need no change, so coverage stays visible.
- Generated text (TodayPlan, notes, insight cards and the other templates) is summarised in §3 and spelled out in full in **§4**.

**Who changes what** (coordinator, 2026-09-30):
- **[Phase B]**: `copy.dart` (existing entries), `today_planner.dart`, `notes.dart`, `health_monitor.dart`, `insight_templates.dart`, the Today, Recovery, Sleep, Strain and Trends screens, and the coach chat UI.
- **[Revamp]**: the UI-revamp agent owns and rebuilds Methodology, Settings and its sub-pages (Profile, Sources, Sync log, Privacy, Licences, Diagnostics), Journal, the Live intro and summary, Onboarding, and coach setup, memory and settings. It pastes the strings from this document. Phase B does not edit those screens' inline strings.
- Shared strings in `copy.dart` that revamp screens print (CoachCopy, SettingsCopy, hcReadTypes) are changed **once, in `copy.dart`, by Phase B**. Revamp screens keep reading them from there.

### 3.1 Today [Phase B]

The plan card's generated text is in §4.1. The strings below are the rest of the screen.

| ID | P | Current | Proposed | Why | Where |
|---|---|---|---|---|---|
| T01 | P3 | "Couldn’t load today" / "The stored data could not be read. Nothing was changed." / "Try again" | "Couldn’t load today" / "Airlog couldn’t open your saved data. Nothing was changed." / "Try again" | V8: "stored data" is engineer talk | features/today/today_screen.dart:90-92 |
| T02 | P2 | "No data yet" / "Recovery, Strain and Sleep appear once your tracker’s data reaches Health Connect. Wear it tonight and open Airlog in the morning." / "Check sources" | "No data yet" / "Wear your tracker to bed tonight. Your scores show up here in the morning." / "Check data sources" | V1, V2: lead with what to do | today_screen.dart:153-158 |
| T03 | P3 | "Nothing recorded yet today" / "No data has arrived for {longDay} yet. It will appear after your tracker syncs." | "Nothing yet for today" / "Today’s data shows up after your tracker’s app syncs." | V2 | today_screen.dart:169-172 |
| T04 | P2 | ProgressTile "Learning your normal" · "{have}" "of {need} nights" (and its spoken label) | "Learning your usual" · "{have}" "of {need} nights"; spoken: "Learning your usual: {have} of {need} nights. {body}" | G: one word for baseline | today_screen.dart:190-197 |
| T05 | P2 | "Data notes · {n}" | "About today’s data · {n}" | V2: "data notes" is vague | today_screen.dart:204 |
| T06 | P1 | Recovery tile title "Recovery · without HRV · provisional · re-learning" | Title "Recovery". Put **one** tag in the status slot, in this order of priority: "without HRV", then "early estimate", then "learning". The other tags stay on the plan card's top line. | G; layout: the tile is fixed-width and single-line, and 4 tags overflow into the stats column (§5) | today_screen.dart:219-228 |
| T07 | P3 | status "Learning" / "No data" / "Good" / "Fair" / "Low" | "Learning" / "No score" / "Good" / "Fair" / "Low" | G: Good/Fair/Low become the only zone words | today_screen.dart:233-241 |
| T08 | P3 | "HRV vs usual" / "Resting HR vs usual" / "Sleeping HR vs usual"; value "Same as usual" | keep the labels; value "About usual" | G | today_screen.dart:247; today_view_model.dart:126,330-331,387,390 |
| T09 | P1 | Spoken tile label (shown **as the tile's text** above 1.3× text size): "{title}, {score} percent, {status}. HRV vs usual {+13%}. Resting HR vs usual {−3 bpm}. Opens the breakdown." | "Recovery {score}%, {status}. HRV {13% above} your usual. Resting heart rate {3 bpm below} your usual. Tap for details." With no data: "Recovery: no score today. Tap for details." | V2, V4. At large text sizes this **is** the visible tile (`GlowTile`, design/components/tile.dart:216) | today_screen.dart:254-257 |
| T10 | P2 | Strain tile caption "Target {15.6}" / "Estimated · Target {15.6}" / "of 21" / "No heart rate yet" | "Goal {15.6}" / "Estimate · Goal {15.6}" / "out of 21" / "No heart rate yet" | G: target → goal | today_view_model.dart:479-480; today_screen.dart:267-268 |
| T11 | P2 | Spoken "Strain {v} of 21. {unit}. Opens Strain." / "Strain: no score without heart rate. {unit}. Opens Strain." | "Strain {v} out of 21. {unit}. Tap for details." / "No Strain score yet: no heart rate. {unit}. Tap for details." | V2 | today_screen.dart:276-278 |
| T12 | P3 | Sleep tile "No sleep recorded"; spoken "Sleep performance {pct} percent, {7h 1m}. Opens Sleep." | "No sleep recorded" (keep); spoken "Sleep {pct}% of your goal, {7h 1m} asleep. Tap for details." | G: performance → % of goal | today_screen.dart:289-294 |
| T13 | P3 | Vital status "In range" / "Above usual" / "Below usual" / "Learning" / "No data last night" | "In range" / "Above usual" / "Below usual" / "Learning" / "No reading" | V2 | today_screen.dart:309-315 |
| T14 | P1 | Tile titles "SpO₂" / "Respiration" (and "HRV", "Resting HR", "Skin temp") | "Blood oxygen" / "Breathing" (keep "HRV", "Resting HR", "Skin temp") | G, V4 | today_screen.dart:329-358 |
| T15 | P2 | Spoken vital "{label}, {value} {unit}, {word}. Opens its 30 nights." | "{Plain name} {value} {unit}, {in your usual range / above your usual range / below your usual range / still learning / no reading}. Tap to see 30 nights." | V2; this is the text shown at large sizes | today_screen.dart:324-325 |
| T16 | P2 | Alert tile "Worth a look"; reading "{label} · above/below"; "{n} outside your usual" / "{m} within" | "Worth a look" (keep); "{label} · higher" / "{label} · lower"; "{n} outside your usual range" / "{m} in range" | G | today_screen.dart:387-396 |
| T17 | P3 | "What to do" (alert sheet section); More menu "Coach", "Journal", "Live workout", "Settings", "More" | keep | — | today_screen.dart:66,407,457-470 |
| T18 | P2 | Alert sheet title, body and fix (generated) | see §4.6 | V2, V7 | today_view_model.dart:670-750 |
| T19 | P1 | Ring caption "No HRV or RHR" | "No heart data" | V4: "RHR" | today_view_model.dart:424 |
| T20 | P1 | "Provisional"; zone names "Green zone" / "Yellow zone" / "Red zone" | "Early estimate"; "Good" / "Fair" / "Low" | G | today_view_model.dart:439,462-466 |
| T21 | P2 | "No HR data" / "No sleep" | "No heart rate" / "No sleep data" | V4 | today_view_model.dart:470,487 |
| T22 | P3 | "1 more night" / "{n} more nights" | keep | — | today_view_model.dart:431 |
| T23 | P2 | Metric sheet lede: "Last night {v} {unit}, inside your usual range ({range})." (plus above/below variants); "Last night {v} {unit}. Your usual range appears after {5} nights ({n} so far)."; "No reading for this night." | "Last night: {v} {unit}. That’s in your usual range ({range})." / "Last night: {v} {unit}. That’s above your usual range ({range})." / "Last night: {v} {unit}. That’s below your usual range ({range})." / "Last night: {v} {unit}. Your usual range shows up after {5} nights. You have {n} so far." / "No reading for this night." | V2 | features/today/widgets/health_monitor.dart:149-163 |
| T24 | P1 | "Your usual range is the average of your last {30} nights (same source) ± {1.65} standard deviations, which holds about 90 % of nights, and never narrower than ± {3} {unit}." / SpO₂: "For SpO₂ only a low value matters: the range has a floor at your average minus the same margin, and never below {90} %." | "Your usual range is where about 9 in 10 of your last {30} nights fall. It’s never narrower than ± {3} {unit}, so tiny changes don’t count." / "For blood oxygen, only a low reading matters. The range has a floor, and the floor is never below {90}%." | V2, V8: move "standard deviations" to the formula line | health_monitor.dart:164-170 |
| T25 | P2 | "Last {n} nights"; "Band: your usual range, {range}"; "How the range works"; "{rule} A night outside it is a prompt to look at the others, not a diagnosis."; "Source" / "A change of source starts a new baseline, so two ways of measuring are never mixed." | "Last {n} nights"; "Shaded: your usual range, {range}"; "How the range works"; "{rule} One night outside it is a prompt to check your other signals. It’s not a diagnosis."; "Source" / "If this starts coming from a different app, Airlog learns your usual again instead of mixing the two." Formula lines unchanged. | G, V7 | health_monitor.dart:177-206 |
| T26 | P1 | Plan card top line: "Tonight" · "Data may be behind" · "Provisional" · "New source: re-learning your normal ({app})" | "Tonight" · "Your data may be out of date" · "Early estimate" · "Learning your {app} data" | G, V2 | design/tiles/plan_tile.dart:35-43 |
| T27 | P2 | Gap tags "without HRV" / "without heart rate" / "without sleep" / "without respiratory rate" / "without skin temperature" / "without SpO₂" | "without HRV" / "without heart rate" / "without sleep data" / "without breathing rate" / "without skin temperature" / "without blood oxygen" | G; keep "without HRV" visible (principle 6) | plan_tile.dart:46-53 |
| T28 | P3 | "Nothing to change today." | keep | — | plan_tile.dart:109 |
| T29 | P3 | Spoken chip "{label} {value}, {comparison}" | keep the pattern (it follows the chips in §4.1) | — | plan_tile.dart:155-156 |
| T30 | P2 | **Dead code, not rendered:** `SummaryVm`/`summary()`/`signals()`; `SummaryCard`; `JournalCard` ("Logged tonight", "Log tonight’s factors", "Alcohol, late caffeine, screens before bed… A few taps now; in a few weeks you see what moves your recovery.", "Tag your evenings to see what moves your next-day recovery."); `ProfileNudge` ("Add your birth year. Heart-rate zones use an assumed maximum until you do." — **false** since algo v2); `HealthMonitorSection` and `showHealthMonitorSheet` ("Health monitor", "How it works", "Five overnight signals…", "Your usual range", "When a card appears", "Method") | Delete in Phase B. Rewording copy nobody sees wastes effort, and the ProfileNudge text contradicts the engine (`notes.dart:274`). | V6 | today_view_model.dart:76-84,496-614; widgets/today_cards.dart:12-150,237-281; widgets/health_monitor.dart:15-101,217-251 |

### 3.2 Recovery detail [Phase B]

| ID | P | Current | Proposed | Why | Where |
|---|---|---|---|---|---|
| R01 | P3 | "Could not load Recovery" / "The stored data could not be read. Nothing was changed." / "Try again" | "Couldn’t load Recovery" / "Airlog couldn’t open your saved data. Nothing was changed." / "Try again" | V8 | features/recovery/recovery_screen.dart:34-36 |
| R02 | P3 | "Recovery" / "Recovery · without HRV" / "How Recovery works" | keep | — | recovery_screen.dart:45,60,66 |
| R03 | P2 | "No Recovery yet" / "Recovery needs a night of HRV or resting heart rate from your tracker. Wear it to bed and open Airlog in the morning." | "No Recovery yet" / "Wear your tracker to bed tonight. Your first Recovery shows up in the morning." | V1 | recovery_screen.dart:101-104 |
| R04 | P3 | "Nothing recorded" / "No data arrived for this day." | keep | — | recovery_screen.dart:112-113 |
| R05 | P1 | "How it was built" / "Points each input earned of its weight" | "What made your score" / "Points from each signal, out of its share" | V2, flagged by the product owner | recovery_screen.dart:172 |
| R06 | P2 | "The exact formula" | "See the formula" | V3 | recovery_screen.dart:207 |
| R07 | P1 | "Inputs against your baseline" / "Last {30} nights · shaded band is your usual range" | "Your signals vs your usual" / "Last {30} nights. The shaded area is your usual range." | G | recovery_screen.dart:221-223 |
| R08 | P1 | "HRV over the week" / "Plews 7-night rolling average" | "Your HRV this week" / "Average of the last 7 nights" | V8: an author name in a subtitle | recovery_screen.dart:229 |
| R09 | P3 | "Recovery history" / "About this night’s data" | keep | — | recovery_screen.dart:235,244 |
| R10 | P1 | Hero chip "Green · 67 and above" / "Yellow · 34 to 66" / "Red · below 34" | "Good · 67–99" / "Fair · 34–66" / "Low · 1–33" | G, flagged | features/recovery/recovery_view_model.dart:308-313 |
| R11 | P1 | Meaning line (generated) "Last night’s signals were at or better than your usual. A good day for a harder session. Target strain 15.6." | see §4.3 (it is **also untrue** on some green days) | V1, V6 | recovery_view_model.dart:315-334 |
| R12 | P1 | Ring captions "No HRV or resting HR" / "Baseline night {n} of {14}" / "Provisional · baseline night {n} of {14}" | "No heart data" / "Learning · night {n} of {14}" / "Early estimate · night {n} of {14}" | G | recovery_view_model.dart:290-303 |
| R13 | P1 | Breakdown details "{89} % of need · {7h 1m} of {7h 51m}" / "{v} {unit} · no baseline yet, scored neutral" / "{v} {unit} · usual {m} {unit}" | "{89}% of your sleep goal · {7h 1m} of {7h 51m}" / "{v} {unit} · still learning your usual, so half points for now" / "{v} {unit} · usual {m} {unit}" (keep) | G | recovery_view_model.dart:357-371 |
| R14 | P1 | "No {respiratory rate} last night: its {10} points were shared out across the other inputs in proportion to their weights." | "No {breathing rate} last night, so its {10} points went to your other signals." Plural: "No {HRV or breathing rate} last night, so their {50} points went to your other signals." | V2 | recovery_view_model.dart:383-403 |
| R15 | P1 | "No baseline yet for {HRV}, so it scores a neutral half of its points until there are nights to compare with." | "Airlog is still learning your usual {HRV}, so {it gets / they get} half points for now." | G, V2 | recovery_view_model.dart:405-415 |
| R16 | P2 | Labels "Heart rate variability" / "Resting heart rate" / "Sleep performance" / "Respiratory rate"; short names "HRV" / "resting HR" / "respiratory rate" | "Heart rate variability (HRV)" / "Resting heart rate" / "Sleep" / "Breathing rate"; short names "HRV" / "resting heart rate" / "breathing rate" | G | recovery_view_model.dart:216-226 |
| R17 | P2 | Input footnotes "Last night {v} {unit}" / "{t} · usual {mean} ± {sd} {unit}" / "No reading last night" | "Last night {v} {unit}" / "{t} · usual {mean} {unit}" / "No reading last night" | V8: drop "± SD" from the main view | recovery_view_model.dart:66-70 |
| R18 | P2 | "No personal band: performance is hours slept against the night’s sleep target (100 % = target met)." | "No usual range here. This is how much of your sleep goal you got (100% means you met it)." | G | recovery_view_model.dart:471-473 |
| R19 | P1 | HRV-week chip "Steady" / "Above your usual band" / "Below your usual band"; body "Your 7-night HRV average ({avg}) is inside / below / above the band of normal variation around your baseline ({band}). [below:] A week-long dip is a better reason to ease off than any single night." | "Steady" / "Above your usual range" / "Below your usual range"; "Your HRV this week ({avg}) is in your usual range ({band})." / "Your HRV this week ({avg}) is below your usual range ({band}). A whole week lower is a better reason to ease off than one low night." / "Your HRV this week ({avg}) is above your usual range ({band})." | G, V2 | recovery_view_model.dart:95-113 |
| R20 | P2 | "Needs 7 nights of HRV for a baseline and at least 3 of the last 7 nights." | "Shows up after 7 nights of HRV, with at least 3 in the last week." | V2 | recovery_view_model.dart:277-280 |
| R21 | P2 | Input status "In your range" / "Above your range" / "Below your range" / "Calibrating" | "In your usual range" / "Above your usual range" / "Below your usual range" / "Learning" | G | features/recovery/widgets/recovery_widgets.dart:32-43 |
| R22 | P2 | "Band: your usual range {lo}–{hi} {unit} · dashed: your average"; spoken "{label} over the last {n} nights, {unit}" / "usual range {lo} to {hi}" | "Shaded: your usual range, {lo}–{hi} {unit}. Dashed line: your usual." Spoken: keep. | G | recovery_widgets.dart:86-95 |
| R23 | P1 | "7-night HRV trend" / "Day-to-day variation {3.2} %" / "Plews method" | "7-night HRV" / "Night-to-night swing {3.2}%" / "How this works" | V8 | recovery_widgets.dart:142-206 |
| R24 | P2 | History "Last {n} days" / "Green {n}" "Yellow {n}" "Red {n}" / "Average {61} % · green 67 and above, yellow 34–66, red below 34" / "No Recovery scores in these days" | "Last {n} days" / "Good {n}" "Fair {n}" "Low {n}" / "Average {61}%" / "No Recovery scores in this period" | G | recovery_widgets.dart:397-415 |
| R25 | P2 | Explain sheet (ⓘ): "This differs from WHOOP’s own Recovery; here’s why." / "This differs from Oura’s Readiness; here’s why." / "Not the app’s own score" / "Why they differ" | Keep the meaning (PRODUCT_PLAN §7 requires it): "This isn’t WHOOP’s Recovery. Here’s why." / "This isn’t Oura’s Readiness. Here’s why." / "Not {app}’s own score" / "Why they differ" | Decision D6 | features/recovery/widgets/recovery_explain.dart:32-56 |
| R26 | P2 | "Recovery compares last night with your own recent nights, not with anyone else. Every number below is computed on this phone." | "Recovery compares last night with your own recent nights, not with anyone else’s. Everything below is worked out on this phone." | V2 | recovery_explain.dart:46-47 |
| R27 | P2 | "Weights" body "…did not arrive is left out and the others are scaled up so the weights still sum to 100: no number is guessed." | "{weights line}. If a signal is missing, the others count for more, so the total is still 100. Nothing is guessed." | V2 | recovery_explain.dart:75-80 |
| R28 | P2 | "Each input, scored 0 to 1" / "Each input is compared with your baseline: the last {30} nights measured the same way (a change of source starts a new baseline). z is how many standard deviations tonight sits from your mean." | "Each signal, scored 0 to 1" / "Each signal is compared with your usual: your last {30} nights, measured the same way. (z is how far last night was from your usual, in standard deviations.)" Formulas unchanged. | G | recovery_explain.dart:83-100 |
| R29 | P3 | "Penalties" / "Score and zones" / "Calibration" bodies | Replace "green/yellow/red" with "Good (green) / Fair (yellow) / Low (red)", "Calibrating" with "Learning" and "Provisional" with "early estimate". Formulas and citations unchanged. | G | recovery_explain.dart:103-141 |
| R30 | P2 | HRV sheet lede "One night’s HRV is noisy. The 7-night average moves only when something real has changed, so it is judged against a band of normal variation rather than a single cut-off." / "Reading it" body "Inside the band: your HRV is steady. A week below the band is a more reliable reason to ease off than one low night. A rising day-to-day variation can flag instability even when the average looks normal." | "One night of HRV jumps around. A 7-night average moves only when something real has changed." / "In your usual range: your HRV is steady. A whole week below it is a better reason to ease off than one low night. If the night-to-night swing keeps growing, your body may be less settled, even when the average looks fine." The Method, formula and Sources blocks stay unchanged. | V2 | recovery_explain.dart:157-204 |

### 3.3 Sleep [Phase B]

| ID | P | Current | Proposed | Why | Where |
|---|---|---|---|---|---|
| S01 | P2 | "How the sleep target works" | "How your sleep goal works" | G | features/sleep/sleep_screen.dart:43 |
| S02 | P3 | "Sleep" / "Latest" / "Could not load this night" / "The stored data could not be read. Nothing was changed." / "Try again" | "Sleep" / "Latest" / "Couldn’t load this night" / "Airlog couldn’t open your saved data. Nothing was changed." / "Try again" | V8 | sleep_screen.dart:39,65,87-89 |
| S03 | P2 | "No sleep yet" / "Wear your tracker to bed. The night appears here in the morning, once its app has written it to Health Connect." / "Check sources" | "No sleep yet" / "Wear your tracker to bed. Your night shows up here in the morning, after its app syncs." / "Check data sources" | V2 | sleep_screen.dart:140-144,162 |
| S04 | P3 | "Nothing recorded" / "No data arrived for {day}." / "No sleep recorded" / "No sleep session arrived for this night." | "Nothing recorded" / "No data came in for {day}." / "No sleep recorded" / "No sleep was recorded for this night." | V2 | sleep_screen.dart:152-169 |
| S05 | P3 | "Main sleep" | keep | — | sleep_screen.dart:220 |
| S06 | P1 | "Consistency" / "Bed and wake times, last {n} nights" / "{43} % against your previous 4 nights" | "Consistency" / "Bed and wake times, last {n} nights" / "{43}% · compared with your last 4 nights" | V2, flagged | sleep_screen.dart:248-251 |
| S07 | P1 | "Sleep debt carried forward unchanged: {58m}." | "No sleep data for this night, so your missed sleep stays at {58m}." | G, V2 | sleep_screen.dart:286 |
| S08 | P1 | Hero "Time asleep" `7:01` / "Performance" `89%` / "Sleep target" `7:51` | "Asleep" `7h 1m` / "Of your goal" `89%` / "Sleep goal" `7h 51m`. Durations must not use clock format. | V5: 7:01 reads as a time of day; flagged | sleep_screen.dart:300-331 |
| S09 | P1 | Stage legend "Awake" / "REM" / "Core" / "Deep" | "Awake" / "REM" / "Light" / "Deep" (the hypnogram already says "Light") | G: one word per stage | sleep_screen.dart:347-350 |
| S10 | P2 | Spoken "Sleep {7 hours 1 minute}, performance {89} percent of a {7 hours 51 minutes} target. … Opens how the target works." | "Asleep {7 hours 1 minute}, {89} percent of your {7 hours 51 minutes} sleep goal. … Tap for how the goal works." | G | sleep_screen.dart:354-358 |
| S11 | P2 | "{+47m} last night" | "up {47m} last night" / "down {12m} last night" | V2 | features/sleep/widgets/sleep_widgets.dart:39 |
| S12 | P1 | "Target and sleep debt" / "Debt after the night {58m}" / " (the cap)" | "Sleep goal and missed sleep" / "Missed sleep: {58m}" / " (the most Airlog counts)" | G, flagged | sleep_widgets.dart:44-48 |
| S13 | P3 | "Time asleep includes {20 min} of naps." | "Includes {20 min} of naps." | V2 | sleep_widgets.dart:55 |
| S14 | P1 | "How the target is worked out" | "How your sleep goal is set" | G, flagged | sleep_widgets.dart:66 |
| S15 | P1 | Need bar legend "Baseline" / "Debt share" / "Strain boost" / "Slept"; spoken "Target {7h 51m}: baseline {7h 36m}, debt share {3m}, strain boost {12m}. Slept {7h 1m}." | "Usual need" / "Catch-up" / "Extra after a hard day" / "Slept"; spoken "Sleep goal {7h 51m}: usual need {7h 36m}, catch-up {3m}, extra after a hard day {12m}. You slept {7h 1m}." | G, flagged | sleep_widgets.dart:95-102,172-173 |
| S16 | P1 | "Restorative" / "Unavailable" / "deep + REM" / "deep + REM · {36} %"; "Efficiency" / "{95} %" / "asleep of in bed"; "In bed" | "Deep + REM" / "No stage data" / "of your sleep" / "{36}% of your sleep"; "Asleep in bed" / "{95}%" / "of your time in bed"; "In bed" | G, V8 | sleep_widgets.dart:216-229 |
| S17 | P3 | "Nap" / "Naps" / "{11:20}–{11:50}" / "{30 min} asleep" / "Naps count toward the night’s total and its performance." | "Nap" / "Naps" / (times follow the phone setting) / "{30 min} asleep" / "Naps count toward your sleep goal." | G, V5 | sleep_widgets.dart:247-271 |
| S18 | P1 | Bedtime card "TONIGHT" / "Aim to be asleep by {23:35}" / "Tonight’s target is {7h 53m}, including {17m} toward your {58m} of debt, and you usually wake at {07:28}." | see §4.4 | V1, V5, flagged | sleep_widgets.dart:280-330 |
| S19 | P2 | Sleep-goal sheet: title "Sleep target"; lede "How much sleep a night asks for: a fixed baseline, plus part of any debt, plus a little more after a hard day." | Title "Sleep goal"; lede "How much sleep suits tonight: your usual need, plus some catch-up for missed sleep, plus a little extra after a hard day." | G | sleep_widgets.dart:364-367 |
| S20 | P2 | "This night": "baseline {x}\n+ debt share {y}\n+ strain boost {z}\n= target {t} · slept {s} → {89} %" | "usual need {x}\n+ catch-up {y}\n+ extra after a hard day {z}\n= goal {t} · slept {s} → {89}%" | G | sleep_widgets.dart:371-377 |
| S21 | P2 | "Need" body "Baseline {base}. Add {repay} % of the debt carried into the night, and up to {boost} when the previous day’s strain was above {from} (the full {boost} at {to}). The total stays between {lo} and {hi}." | Heading "Sleep goal"; body "Your usual need is {base}. Add {repay}% of your missed sleep, and up to {boost} extra when yesterday’s Strain was above {from} (the full {boost} at {to}). The goal always stays between {lo} and {hi}." Formula lines unchanged. | G | sleep_widgets.dart:380-389 |
| S22 | P2 | "Debt" body "Each night adds (baseline + strain boost − slept) to the running debt, or pays it down when you sleep longer. It is capped at {5h} and can grow by at most {3h} in one night. A night without data leaves it unchanged." | Heading "Missed sleep"; body "Each night, any sleep you missed is added. Sleeping longer than your goal pays it back. It never goes above {5h}, and it grows by at most {3h} in one night. A night with no data leaves it as it was." | G, V2 | sleep_widgets.dart:392-397 |
| S23 | P2 | "Performance and consistency" body "Performance is sleep (naps included) against the target, capped at 100 %. Consistency compares tonight’s bed and wake times with your previous {4} main sleeps: 100 % is the same times, and it reaches 0 % at an average shift of {90} minutes." | Heading "Sleep % and consistency"; body "Your sleep % is how much of your goal you slept, naps included, up to 100%. Consistency compares your bed and wake times with your last {4} nights: 100% means the same times, and it reaches 0% when they’re {90} minutes off on average." | G | sleep_widgets.dart:400-406 |
| S24 | P2 | "Tonight’s bedtime" body "Your average wake time over the last {14} days minus tonight’s projected target. It is when to be asleep, so allow time to fall asleep." / "Sources" "…Stages are the band’s own classification via Health Connect." | "Your usual wake-up time over the last {14} days, minus tonight’s sleep goal. It’s when to be **asleep**, so get into bed a little earlier." / "…Sleep stages come from your tracker, through Health Connect." | G, V6 | sleep_widgets.dart:409-419 |

### 3.4 Strain [Phase B]

| ID | P | Current | Proposed | Why | Where |
|---|---|---|---|---|---|
| ST01 | P3 | "Strain could not load" / "The data store did not answer. Pull down on Today to sync, or check Settings → Sync log." | "Couldn’t load Strain" / "Airlog couldn’t open your saved data. Pull down on Today to try again." | V8 | features/strain/strain_screen.dart:59-62 |
| ST02 | P1 | "No strain yet" / "Strain needs heart-rate measurements and usable heart-rate anchors. Workouts and steps alone provide activity context." / "Open data sources" | "No Strain yet" / "Strain needs heart rate from your tracker. Your workouts and steps still show below." / "Check data sources" | V8: "anchors" | strain_screen.dart:71-75 |
| ST03 | P3 | "Strain" / "How strain is calculated" | "Strain" / "How Strain works" | V2 | strain_screen.dart:93,97,208 |
| ST04 | P2 | "Nothing recorded this day" / "Your tracker sent no heart rate, workouts or steps for this date. Step to another day." | "Nothing recorded this day" / "No heart rate, workouts or steps came in for this day." | V2 | strain_screen.dart:142-145 |
| ST05 | P3 | "Heart rate by zone" / "No heart-rate samples for this day" / "Workouts" / "No workouts recorded. Strain still counts every minute your heart rate was up." | "Heart rate by zone" / "No heart rate for this day" / "Workouts" / keep | V2 | strain_screen.dart:180-232 |
| ST06 | P2 | "Strain today" / "Target {14.8}" | "Strain today" / "Goal {14.8}" | G | strain_screen.dart:257 |
| ST07 | P3 | "Calories" / "Active" | keep (the "min" unit already follows) | — | strain_screen.dart:269-276 |
| ST08 | P2 | Spoken "Strain {v} of 21. {caption}. Workout calories {k}, active {a} minutes. Opens how strain is calculated." / "Strain score unavailable. {caption}." | "Strain {v} out of 21. {caption}. Workout calories {k}, active {a} minutes. Tap for how Strain works." / "No Strain score. {caption}." | G | strain_screen.dart:282-285 |
| ST09 | P3 | Zone groups "Light" / "Moderate" / "Hard" / "Max"; "Heart rate zones"; spoken "Minutes in heart-rate zones: …" | keep (they now match the zone names in §2) | G | strain_screen.dart:293-306 |
| ST10 | P2 | "{8,432} steps" / "No heart rate or activity" / "Heart rate recorded; score unavailable" | keep / keep / "Heart rate came in, but there’s no score yet" | V2 | features/strain/strain_view_model.dart:78-83 |
| ST11 | P1 | Recommendation line (generated): "Room for about {4.2} more strain today for a {74} % recovery." and the other variants | see §4.5 | V1, V3 | strain_view_model.dart:101-127 |
| ST12 | P1 | "No effort target" / "Target basis" / "Recovery does not support an effort target for this day" / "No recovery this morning" / "from {74} % recovery" / "Estimated" / "From heart rate" | "No effort goal" / "Goal" / "No effort goal for this day: there’s no Recovery score" / "No Recovery this morning" / "set by your {74}% Recovery" / "Estimate" / "From heart rate" | G | features/strain/widgets/strain_widgets.dart:31-48 |
| ST13 | P3 | "This stored score used an older estimation method." | "This score was worked out an older way." | V8 | strain_widgets.dart:87 |
| ST14 | P1 | **"Cross-check: TRIMP {266} (Banister)"** (coordinator flag: a method citation in the main UI) | **Remove it from the card.** It shows only in the ⓘ sheet (ST26), as "Second opinion (TRIMP): {266}". | V8 | strain_widgets.dart:97 |
| ST15 | P2 | Spoken "Strain {v} on a 0 to 21 scale" / "Strain {v} against a target of {t}, on a 0 to 21 scale" | "Strain {v} out of 21" / "Strain {v} out of 21. Goal {t}." | G | strain_widgets.dart:120-122 |
| ST16 | P2 | Bar label "Target {14.8}" | "Goal {14.8}" | G | strain_widgets.dart:145 |
| ST17 | P1 | Time-in-zones rows "Zone 5" + "90–100 % · 174–187 bpm" (or "{lo}+ bpm") | "Zone 5 · Max" + "174–187 bpm". Drop the % of reserve; it lives in ⓘ. Names: Zone 1 Very light, 2 Light, 3 Moderate, 4 Hard, 5 Max. | V8, G | strain_widgets.dart:260-313 |
| ST18 | P2 | "Time in zones" / "Time in zones: no minutes above zone 1" / "No recorded minutes in zones 1–5" | "Time in zones" / "Time in zones: none above resting" / "No time in any zone" | V2 | strain_widgets.dart:268-276 |
| ST19 | P1 | "Below zone 1: {14h 10m}, sleep included. Zones are shares of your heart-rate reserve…" | "Resting (below zone 1): {14h 10m}, including sleep." Move the reserve sentence to ⓘ. | V8 | strain_widgets.dart:333-336 |
| ST20 | P1 | Workout row "strain {9.2}" / "average {152} bpm" / "peak {171} bpm" / "TRIMP {30}" / "distance {5.2 km}" / "{410} calories"; stat labels "STRAIN" / "Avg HR" / "Peak HR" / "TRIMP" / "Distance" / "Calories" | "Strain {9.2}" / "average {152} bpm" / "peak {171} bpm" / (drop TRIMP) / "{5.2 km}" / "{410} calories"; labels "STRAIN" / "Avg heart rate" / "Peak heart rate" / (drop) / "Distance" / "Calories" | V8 | strain_widgets.dart:389-395,444-461 |
| ST21 | P2 | "Estimated" / "Too little heart rate inside this workout, so its strain comes from its recorded average HR." | "Estimate" / "Not enough heart rate during this workout, so its Strain comes from its average heart rate." | V4 | strain_widgets.dart:482-487 |
| ST22 | P3 | ⓘ lede "How hard your heart worked across the day, on a 0–21 scale that gets harder to climb the higher you go. Minutes spent near your maximum count many times more than easy ones." | keep | — | features/strain/widgets/strain_explain.dart:30-32 |
| ST23 | P2 | "Heart-rate zones (Karvonen)" / "Each minute is placed by its share of your heart-rate reserve, the span between resting and maximum heart rate." | "Heart-rate zones" / "Each minute is placed by how close your heart rate was to your max, counting up from your resting heart rate (the Karvonen method)." Formula unchanged. | V8 | strain_explain.dart:35-43 |
| ST24 | P2 | "Load weights" / "Load is minutes × a weight that climbs steeply with effort. These six load zones (from Pulse) drive the number; the five zones on the chart are the familiar 50–100 % display bands." | "How minutes count" / "Harder minutes count for much more. Six scoring bands (from Pulse) set the number. The five zones on the chart are simpler bands for display." | V2 | strain_explain.dart:46-50 |
| ST25 | P1 | "Target" / "The suggested strain for a day is {0.2} × that morning’s recovery, kept between {3} and {18.5} (Pulse). A low recovery lowers it; it is a guide, not a goal." | "Effort goal" / "Your goal for the day is {0.2} × that morning’s Recovery, kept between {3} and {18.5} (from Pulse). Today shows it as a range: the goal ± {1.5}. Low Recovery means a lighter goal. It’s a guide, not a rule." | G: the old "not a goal" contradicts the new word | strain_explain.dart:63-70 |
| ST26 | P2 | "Cross-check: Banister TRIMP" / "An independent training-impulse score over the same minutes, weighted exponentially by %HRR (Banister 1991; Morton et al. 1990). It never replaces strain; a big disagreement is a sign the zones deserve a look." | "Second opinion (TRIMP)" / "A different way to count the same minutes of effort (Banister 1991; Morton et al. 1990). It never replaces Strain. If the two disagree a lot, your zones may need a look." Formula unchanged. | V8 | strain_explain.dart:73-83 |
| ST27 | P3 | "When heart rate is sparse" body; "Sources" citations; table headers "ZONE" / "FROM" / "WEIGHT" / "MIN" | Heading "When heart rate is patchy"; body, citations and headers keep | V2 | strain_explain.dart:85-148 |
| ST28 | P2 | Method chip "From heart-rate zones" / "Estimated from workouts + steps — heart-rate data was sparse" / "No data" | "From heart rate" / "Estimate from workouts and steps (not enough heart rate)" / "No data" | V2 | strain_explain.dart:203-206 |

### 3.5 Trends [Phase B]

| ID | P | Current | Proposed | Why | Where |
|---|---|---|---|---|---|
| TR01 | P3 | "Trends could not load" / "The data store did not answer. Try again after the next sync, or check Settings → Sync log." | "Couldn’t load Trends" / "Airlog couldn’t open your saved data. Try again after your next sync." | V8 | features/trends/trends_screen.dart:49-52 |
| TR02 | P3 | "No trends yet" / "Trends need a few days of data. Wear your tracker day and night; the first lines appear after two or three days." / "Open data sources" | keep / keep / "Check data sources" | — | trends_screen.dart:61-65 |
| TR03 | P3 | "Trends" / "How trends are tested" | "Trends" / "How trends work" | V2 | trends_screen.dart:83,87 |
| TR04 | P2 | "Body" / "Each line inside your usual range" | "Body" / "Shaded areas show your usual range" | V2: the old line reads like a claim | trends_screen.dart:138 |
| TR05 | P3 | "Fitness" / "Averages" | keep | — | trends_screen.dart:142,145 |
| TR06 | P1 | Week tile "Last 7 days" / "Most strained day:" / "Average strain" "OF 21" / "Highest" "STRAIN" | "Last 7 days" / "Hardest day:" / "Average strain" "OUT OF 21" / "Hardest" "STRAIN" | V2 | trends_screen.dart:179-184 |
| TR07 | P1 | Load tile "Training load" `1.09` "vs recent" **"Similar"**; bands "Lower <0.8" / "Similar 0.8–1.3" / "Elevated 1.3–1.5" / "High >1.5" (the stale golden still shows "your load is Optimal") | "Training load" `1.09` "vs usual" **"About usual"**; bands "Less <0.8" / "About usual 0.8–1.3" / "More 1.3–1.5" / "Much more >1.5" | G, flagged | trends_screen.dart:196-224 |
| TR08 | P2 | Spoken "Training load {1.09}, {label}: seven-day load against the 28-day average." / "Recorded strain in the last 7 days: average {x}, highest {y} on {day}." | "Training load {1.09}: {about usual}. Your last 7 days compared with your last 4 weeks." / "Strain in the last 7 days: average {x}, hardest {y} on {day}." | G | trends_screen.dart:189-191,225-227 |
| TR09 | P2 | "Dashed line: your average sleep target here ({7h 36m}). Duration has no personal band." | "Dashed line: your average sleep goal ({7h 36m})." | G | features/trends/trends_view_model.dart:466-467 |
| TR10 | P2 | Series names "Respiratory rate"; "VO₂ max ({app}’s estimate)"; "Skin temperature change" | "Breathing rate"; "Cardio fitness (VO₂ max, {app}’s estimate)"; "Skin temperature change" | G, V4 | trends_view_model.dart:193,479,488,533,605 |
| TR11 | P3 | Other series names "Heart rate variability" / "Resting heart rate" / "Sleep duration" / "Recovery" / "Strain" / "HRV" / "Resting HR" / "Sleep" / "Weight" / "Today" | keep | — | trends_view_model.dart:362-617 |
| TR12 | P2 | "Average recovery {61} % · average strain {9.7}"; legend "Recovery (%, left)" / "Strain (right)" | "Average Recovery {61}% · average Strain {9.7}"; legend "Recovery % (left scale)" / "Strain (right scale)" | V2 | features/trends/widgets/trends_widgets.dart:47-49; design/charts/dual_axis_chart.dart:123-124 |
| TR13 | P1 | "Needs at least {21} days with sufficient HR coverage in the last {28} days, including {4} in the last week. Today is excluded." | "Shows up after {21} days with heart rate in the last {28}, including {4} in the last week." | V8 | trends_widgets.dart:82-85 |
| TR14 | P1 | "Recorded effort this week is lower than / close to / above / well above your recent average." | "This week you did less than usual." / "This week you did about the same as usual." / "This week you did more than usual." / "This week you did a lot more than usual." | V2 | trends_widgets.dart:86-95 |
| TR15 | P1 | "Acute:chronic ratio: mean daily strain over the last {7} days ÷ the last {28} (Gabbett 2016). {0.8}–{1.3} is the steady zone. Based on {40} days." | "Your average daily Strain for the last {7} days, divided by your last {28} days. {0.8}–{1.3} means about usual. Based on {40} days." Gabbett moves to ⓘ. | V8 | trends_widgets.dart:104-111 |
| TR16 | P2 | "Band: your usual range {lo}–{hi} {unit}" / "Dotted line: the source changed on {14 Sep}, so a new baseline starts there." | "Shaded: your usual range, {lo}–{hi} {unit}" / "Dotted line: your data came from a different app from {14 Sep}, so Airlog learned your usual again." | G | trends_widgets.dart:136-142 |
| TR17 | P3 | "Nothing measured in this range" / "no data" | "Nothing recorded in this period" / "no data" | V2 | trends_widgets.dart:20,161 |
| TR18 | P1 | "Arrows mark a statistically significant change (Mann–Kendall test, p < 0.05, at least {10} days). No arrow means no reliable change yet, not no change." / "No arrows here: nothing in these {30} days is a statistically significant change (…). Day-to-day wobble is not a trend." | "An arrow means a real change, not just day-to-day ups and downs. No arrow means no clear change yet." / "No arrows: nothing in these {30} days is a clear change yet. Day-to-day ups and downs aren’t a trend." | V8 | trends_widgets.dart:255-259 |
| TR19 | P2 | ⓘ "How trends are tested" lede "A line that drifts is not a trend until the drift is bigger than the day-to-day noise. Airlog only draws an arrow when it is."; headings "The test" / "The size" / "Bands" / "New baselines"; "Bands" body "…your {30}-night baseline ± {1.65} SD…"; "New baselines" body "If a metric starts coming from a different source (say, deep-sleep HRV from the Google Health API instead of all-night HRV from Health Connect), the old and new values are not mixed: a new baseline starts, and the chart marks the day with a dotted line." | Title "How trends work"; lede "A line that wobbles isn’t a trend. Airlog only draws an arrow when the change is bigger than the usual ups and downs."; headings "The test" / "The size" / "Usual range" / "Switching apps"; "Usual range" body "The shaded area is your usual range: where about 9 in 10 of your last {30} nights fall, with a minimum width so a very steady signal isn’t too touchy."; "Switching apps" body "If a signal starts coming from a different app, or is measured a different way, Airlog doesn’t mix old and new. It learns your usual again, and the chart marks that day with a dotted line." The Mann–Kendall and Sen text stays unchanged. | G | trends_widgets.dart:271-309 |
| TR20 | P1 | Load gauge "Needs 4 weeks of strain history"; spoken "Training load: acute to chronic ratio {1.09}" / "7-day mean strain {x}, 28-day mean {y}" / "Optimal range 0.8 to 1.3"; axis "7d {x} · 28d {y}" | "Needs 4 weeks of Strain history"; spoken "Training load {1.09}. Last 7 days average Strain {x}, last 4 weeks {y}. About usual is 0.8 to 1.3."; axis "7 days {x} · 4 weeks {y}" | G: "Optimal" contradicts the tile's words | design/charts/acwr_gauge.dart:24-92,147 |

### 3.6 Coach chat and conversations [Revamp] · insight-card chrome (IC rows) [Phase B]

**Ownership changed on 2026-09-30.** The UI-revamp branch now owns the coach chat UI: the answer view, source chips, verification pills, the facts-only fallback, the safety card, and the top chips and banner. Phase B does **not** edit these strings or widgets, so the proposals below are paste-ready for the revamp. Some of them live in `copy.dart` (`CoachCopy`) or `prompts.dart`, which Phase B otherwise owns. **D12** asks who edits those shared constants; the default here is that Revamp edits the chat-facing `CoachCopy` entries. The IC rows (insight-card chrome, `InsightCopy`) stay with Phase B.

| ID | P | Current | Proposed | Why | Where |
|---|---|---|---|---|---|
| C01 | P1 | Screen title "Ask"; "Ask is turned off" / "Turn it back on to ask about your data." / "Turn on" | "Coach"; "Coach is turned off" / "Turn it on to ask about your data." / "Turn on" | G: one name for the feature | features/coach/coach_screen.dart:251,301-303 |
| C02 | P1 | Engine chip "On-device" / "Claude · Opus 5.5"; mode chip **"Uses your data"** / "General only"; spoken "Engine: {label}. Change in setup" / "Mode: {label}. Change in setup" | "On this phone" / "Claude · Opus 5.5"; **"With my data"** / "General only"; spoken "Answers from: {label}. Tap to change." / "{Coach can see your data / Coach can’t see your data}. Tap to change." | G, flagged; decision D7 | copy.dart:161-165,291-294; coach_screen.dart:562-572 |
| C03 | P1 | Empty state "Ask about your data" + "On-device answers a fixed set of questions about your Recovery, Sleep, Strain, trends and journal, from the numbers on this phone. It has no AI model, so it cannot hold an open conversation." / "Try asking" | "Ask about your data" + "The on-phone coach answers set questions about your Recovery, Sleep, Strain, trends and journal. It isn’t an AI, so it can’t chat freely." / "Try asking" | V2 | copy.dart:141-144; coach_screen.dart:376,384 |
| C04 | P2 | Cloud empty state "{Claude} answers from general sleep and training science, without your data." / "{Claude} looks up the numbers it needs on this phone, and every number it quotes is checked." | keep / "{Claude} looks up the numbers it needs, and Airlog checks every number it quotes." | V2 | coach_screen.dart:349-352 |
| C05 | P1 | Verified pill **"Checked against your data · {3} numbers"** / "· 1 number" | **"All {3} numbers match your data"** / "The number matches your data" | V2, flagged | copy.dart:135; features/coach/widgets/message_widgets.dart:105-120 |
| C06 | P1 | Fallback pill **"Showing facts only — couldn't verify the answer"** | **"Couldn’t check the answer, so here are just your numbers"** | V2, flagged | copy.dart:136 |
| C07 | P1 | Fallback answer lead "I couldn't phrase an answer without adding details your data doesn't show, so here are the facts I found instead:" (the golden's "I couldn't check every number in my answer, so here are the facts from your data:" is fixture text) | "I couldn’t answer without guessing, so here are the numbers I found:" | V2, flagged | domain/coach/prompts.dart:155-157; test/support/coach_fixtures.dart:93 |
| C08 | P2 | "I couldn't answer that from your data without guessing, and I found no recorded values to show. Try asking about a specific day or metric." | "I couldn’t answer that without guessing, and I found no numbers to show. Try asking about one day or one score, like “How did I sleep last night?”" | V2 | prompts.dart:159-161 |
| C09 | P1 | Button **"What was sent"**; sheet title "What was sent"; rows "To" / "Model" / "Size" / "Tools" / "None"; "About {n} characters" / "About {n}k characters"; "Data in this question" / "None of your data: only the question." / "Never sent" | Button **"What was shared"**; sheet title "What this answer shared"; rows "Sent to" / "Model" / "Size" / "Data looked up" / "None"; keep sizes; "Your data in this question" / "None of your data, only your question." / "Never sent" | V2, flagged | message_widgets.dart:329; widgets/coach_sheets.dart:53-97 |
| C10 | P3 | "Report answer" / "Reported"; sheet "Report this answer" / "Flag an answer that is wrong, unsafe or unhelpful. The flag stays on this phone: Airlog has no server, so nothing is sent. The question, the answer and its sources are copied, so you can share them with the developer if you choose." / "Flag and copy details" / "Cancel"; snackbar "Flagged on this phone. Details copied." | keep / keep; "Report this answer" / "Flag an answer that’s wrong, unsafe or unhelpful. The flag stays on this phone, and nothing is sent. Airlog copies the question and answer so you can send them to the developer if you want." / "Flag and copy" / "Cancel"; keep | V2 | message_widgets.dart:336; coach_sheets.dart:115-141; coach_screen.dart:130 |
| C11 | P3 | Report clipboard text "Airlog coach report" / "Engine: …" / "Question: …" / "Answer: …" / "Source {n}: …" / "Verification: {n} checked, …" | keep (a technical report for the developer) | — | coach_screen.dart:136-149 |
| C12 | P2 | Model note **"via {3.5 Flash-Lite}"**; "Answered on this phone — {why}."; reasons "{Claude} didn't accept your API key. Check it in Settings → Coach" / "your {Claude} account is out of credit or quota" / "today’s {Claude} limit is reached" / "{Claude} couldn't be reached" / "{Claude} is unavailable right now"; "Ask {Claude} again" | **"Answered by {3.5 Flash-Lite}"**; "Answered on this phone: {why}."; "{Claude} didn’t accept your API key. Check it in Settings → Coach" / "your {Claude} account is out of credit" / "today’s {Claude} limit is used up" / "{Claude} couldn’t be reached" / "{Claude} isn’t available right now"; "Ask {Claude} again" | V2, flagged ("model lines") | copy.dart:262-283 |
| C13 | P2 | AI disclosure "You’re chatting with an AI: {Claude}, by {Anthropic}. It can be wrong. Numbers with a source chip come from your data. Wellness info, not medical advice." | "You’re chatting with an AI: {Claude}, by {Anthropic}. It can make mistakes. Numbers with a small tag come from your data. Wellness info, not medical advice." (wording only; the provider's policy requires the disclosure) | V2 | copy.dart:361-364 |
| C14 | P3 | Standing lines "Wellness info, not medical advice." / "AI can make mistakes. Not medical advice." | keep | V7 | copy.dart:134,416 |
| C15 | P3 | "Sources" (answer section); spoken "Source {n}: {label}, {value}. Opens the screen." | keep | — | message_widgets.dart:189-198,277 |
| C16 | P2 | "Remember this?" / "“{text}”" / "Use until {date}" / "Category: {label}. Change" / "Remember" / "No thanks" / "Saved to What Coach knows" / "View" | keep | — | message_widgets.dart:400-482 |
| C17 | P3 | Health-detail confirm "Remember how you feel?" / "Remember this health detail?" / "“{text}” is {category}. Coach keeps it on this phone and may use it in later answers. You can delete it any time in What Coach knows." / "Cancel" / "Yes, remember" | keep | — | coach_screen.dart:163-178 |
| C18 | P2 | "Coach could not start" / "Its storage on this phone did not answer. Nothing was sent anywhere." / "Try again" | "Coach couldn’t start" / "Airlog couldn’t open Coach’s saved data. Nothing was sent." / "Try again" | V8 | coach_screen.dart:229-233 |
| C19 | P2 | "Finish setting up {Claude}" / "Add your API key, or switch back to on-device." / "Confirm what {Claude} may receive before the first question." / "Open setup" | "Finish setting up {Claude}" / "Add your API key, or switch back to On this phone." / "Before your first question, confirm what {Claude} can receive." / "Open setup" | G | coach_screen.dart:315-319 |
| C20 | P2 | "Today’s limit reached" / "Open setup"; banner "Today’s model-request limit for your AI provider is used up. It resets tomorrow. On-device answers still work." | "Today’s limit reached" / "Open setup"; "You’ve used today’s limit for {Claude}. It resets tomorrow. The on-phone coach still works." (needs `usageSpent(p)`, or keep a generic "your AI provider") | V2 | coach_screen.dart:328-332; copy.dart:424-427 |
| C21 | P3 | "Ask about this card" / "Follow up" / "Suggested: {q}. Fills the question box." / "Ask: {q}" | keep | — | coach_screen.dart:368,388-390,480; message_widgets.dart:818-820 |
| C22 | P2 | "Discussing: {headline}" | "About this card: {headline}" | V2 | message_widgets.dart:757-776 |
| C23 | P3 | "For your safety" (safety card title) | keep | V7 | message_widgets.dart:520 |
| C24 | P2 | Error cards: "Review coach settings" / "Coach is not ready, or its settings changed during this answer. Review setup or switch to on-device. No further requests were sent." / "Open setup" | "Check Coach settings" / "Coach’s settings changed while it was answering, so nothing more was sent. Check setup, or switch to On this phone." / "Open setup" | V2 | message_widgets.dart:581-586 |
| C25 | P2 | "Your key was not accepted" / "{Claude} did not accept the saved API key. Paste it again in setup; the old one is replaced." / "Fix the key" | "Your key didn’t work" / "{Claude} didn’t accept your API key. Paste it again in setup." / "Fix the key" | V2 | message_widgets.dart:589-594 |
| C26 | P3 | "Too many questions at once" / "{Claude} asked for a short pause. Wait a moment, then try again." / "Try again" | keep | — | message_widgets.dart:597-600 |
| C27 | P2 | "Your provider account is out of credit" / "Add credit or raise the limit in the {Claude} console, or switch to on-device in setup." / "Open setup" | "Your {Anthropic} account is out of credit" / "Add credit in your {Anthropic} account, or switch to On this phone in setup." / "Open setup" | V2 | message_widgets.dart:603-608 |
| C28 | P3 | "Today’s limit reached" / "Open setup"; "No connection" / "No answer arrived from {Claude}. Check your connection and try again. A request may already have reached the provider." / "Try again" | keep | — | message_widgets.dart:611-624 |
| C29 | P2 | "Coach couldn't answer that" / "The model declined this question. Try asking it another way." | "{Claude} didn’t answer that" / "Try asking it another way." | V8 | message_widgets.dart:627-628 |
| C30 | P2 | "{Claude} had a problem" / "Their service returned an error. Try again in a moment." / "Something went wrong" / "The answer did not complete. Your question may remain in chat. Try again." | keep / keep / "Something went wrong" / "The answer didn’t finish. Try again." | V2 | message_widgets.dart:633-644 |
| C31 | P3 | "Working on it…" / "Checking your data…"; composer "Ask about your sleep, recovery or training" / "Waiting for the answer" / "Send"; "Brief" / "Detailed" / "Answer length" | keep; "Short" / "Detailed" / "Answer length" | V2 | message_widgets.dart:697; widgets/composer.dart:21,106-126 |
| C32 | P2 | Service messages "Empty question." / "Ask is turned off. Turn it on in Settings → Coach." / "Coach settings or data mode changed. No further requests were sent. Start a new question with your current settings." / "The AI provider took too long to answer." / "Data mode changed while answering. Start a new question." / "(no answer text was produced)" | "Type a question first." / "Coach is turned off. Turn it on in Settings → Coach." / "Your settings changed, so Coach stopped. Nothing more was sent. Ask again." / "{Claude} took too long to answer." / "You switched data while Coach was answering. Ask again." / "(No answer came back.)" | V8 | domain/coach/coach_service.dart:94-100,415-457,502 |
| C33 | P2 | "You've reached today's limit for {Claude} ({50 model requests}). No further requests will be sent. It resets at midnight. You can switch to the on-device coach in Settings → Coach." | "You’ve used today’s limit for {Claude} ({50} requests). Nothing more will be sent. It resets at midnight. The on-phone coach still works." | V2 | coach_service.dart:610-614 |
| C34 | P3 | "Review and accept what is sent to {Claude} before asking (Settings → Coach)." / "What is sent to {Claude} has changed. Review and accept it again in Settings → Coach." / "{Claude} can only be used by adults. Confirm you are 18 or older in Settings → Coach." / "Your API key was rejected. Check it in Settings → Coach." / "The AI provider is rate-limiting requests. Try again in a minute." / "Your AI provider account is out of credit or quota." / "You've reached today's limit. No further requests were sent. It resets at midnight." / "No answer arrived from the AI provider. A request may already have reached it. Check your connection and try again." / "The AI provider had a problem. Try again shortly." / "Set up the coach in Settings → Coach." / "Something went wrong answering that." / "I can't help with that one. I can answer questions about your recovery, sleep, strain and training data." | keep. Two exceptions: "The AI provider is rate-limiting requests. Try again in a minute." → "Too many questions at once. Try again in a minute."; "Your AI provider account is out of credit or quota." → "Your AI account is out of credit." | V8 | coach_service.dart:83-84,648-689 |
| C35 | P3 | Engine long names "On-device (no AI model)" / "Claude (Anthropic)" / "Gemini (Google)" | "On this phone (no AI)" / keep / keep | G | domain/coach/coach_contracts.dart:22-24 |
| C36 | P2 | Suggested questions: "What drove this Recovery?" / "What drove my Recovery today?" / "Was that a lot for my Recovery today?" / "What strain should I aim for today?" / "How much sleep debt do I have?" / "How does my HRV compare with my baseline?" (plus the others) | "What changed my Recovery?" / "What changed my Recovery today?" / "Was that too much for today?" / "How hard should I go today?" / "How much sleep have I missed?" / "How does my HRV compare with my usual?"; the rest keep. **Phase B must add router aliases** for "missed sleep", "how hard should I go" and "usual" (the router matches `\bdebt\b`, `strain target`, and `calibrat\|baseline` → methodology, offline_client.dart:198-256), so each rewritten suggestion lands on the same intent. | G | features/coach/coach_providers.dart:239-334; coach_service.dart:811-879 |
| C37 | P3 | Conversations "Conversations" / "No conversations" / "Chats with the coach are kept here, on this phone only." / "Stored on this phone only. Deleting a chat never deletes what Coach knows." / "Delete every conversation?" / "Every chat stored on this phone is erased. What Coach knows (your confirmed memories) stays. It cannot be undone." / "Cancel" / "Delete all" / "Conversation deleted." / "Could not delete it." / "All conversations deleted." / "Could not delete." / "Could not load conversations" / "The chats stored on this phone could not be read." / "Try again" / "Delete all conversations" / "Delete {title}" | keep, except: "Every chat on this phone will be deleted. What Coach knows stays. This can’t be undone." / "Delete all chats" (button) / "Couldn’t delete it." / "Couldn’t delete." / "Couldn’t load conversations" / "Airlog couldn’t open your saved chats." | V2; the confirm button repeats the consequence | features/coach/coach_history_screen.dart:46-186 |
| C38 | P3 | "New chat" / "Conversations" (app-bar actions) | keep | — | coach_screen.dart:256,261 |
| C39 | P3 | `ask_entry.dart` "Ask the coach" | "Ask Coach" | G | app/ask_entry.dart:127 |
| IC01 | P2 | Card chips "Sleep" / "Recovery" / "Strain" / "Workout" / "Health" / "This week"; actions **"Discuss"** / "AI summary" / "Card options" / "Hide this card" / "Why am I seeing this?" / "Coach messages settings" / "Card hidden" / "Using what you told me" | "Sleep" / "Recovery" / "Strain" / "Workout" / "Overnight signals" / "This week"; **"Ask about this"** / "AI summary" / "Card options" / "Hide this card" / "Why am I seeing this?" / "Coach notes settings" / "Card hidden" / "Using what you told me" | G: one verb for "ask about this" | copy.dart:438-454 |
| IC02 | P3 | Why sheet "Coach writes a short note when there is something new in your data for this day. It is built from these numbers:" / "Written on this phone with fixed wording, from the numbers above. Nothing was sent anywhere." / "What you told Coach, used here" / "Delete memory: {text}" | keep | — | copy.dart:456-466; app/insight_card.dart:737 |
| IC03 | P3 | Card body text (generated) | see §4.8 | — | data/coach/insight_templates.dart |

### 3.7 Shared components and data-layer strings [Phase B]

| ID | P | Current | Proposed | Why | Where |
|---|---|---|---|---|---|
| X01 | P1 | Calibration banner "Baseline night {n} of {14}" / "Scores are estimates until 5 nights are in. Wear the band to bed." / "Scores are provisional until your baseline settles." | "Learning your usual · night {n} of {14}" / "Scores start to mean something after 5 nights. Wear your tracker to bed." / "Scores may shift until Airlog knows your usual." | G ("band" → "tracker") | design/components/status_lines.dart:200-208 |
| X02 | P1 | Watermark "Demo data" / "Sample data"; "{label}: these numbers are synthetic, not from your band" | "Sample data" (one word everywhere); "Sample data: made-up numbers, not from your tracker" | G | status_lines.dart:80,272,299 |
| X03 | P2 | "Couldn’t read your data. Pull to retry." | "Couldn’t read your data. Pull down to try again." | V2 | status_lines.dart:88 |
| X04 | P3 | Freshness "just now" / "{m} min ago" / "{h} h ago" / "1 day ago" / "{d} days ago"; "your tracker"; "no data yet" / " · syncing…" / "{source} · {when}{tail}" / "No data from {source} yet" / "Last data from {source} {ago}" / "syncing…" / "not synced yet" / "synced {ago}" | "{h}h ago" (V5 duration style); "Latest data from {source} {ago}"; keep the rest | V5 | status_lines.dart:19-130 |
| X05 | P3 | "Preparing 90 days of sample data…" / "Reading your data from Health Connect…" / "This happens once, on first launch, and takes a few seconds. Your scores appear here as soon as it is done." | keep | — | status_lines.dart:338-342; data/repositories/health_repository_impl.dart:227 |
| X06 | P2 | Status card "Warning" / "Note" / "To fix: {fix}" | "Heads-up" / "Note" / "How to fix: {fix}" | V7: calmer | design/components/status_card.dart:71-74 |
| X07 | P3 | Explain-sheet footer "Computed on this phone from your own data. Not medical advice." | keep | V7 | design/components/explain_sheet.dart:49 |
| X08 | P2 | Metric tile "Same as usual" / "{dv} {unit} vs usual {usual}" / "In your range" / "Above your range" / "Below your range" / "No data" / "no data today" | "About usual" / keep / "In your usual range" / "Above your usual range" / "Below your usual range" / "No data" / "no data today" | G | design/components/metric_tile.dart:126-175,229 |
| X09 | P2 | Band chart "Not enough nights yet" / "Band: your usual range {range} {unit}"; spoken "usual range {lo} to {hi}", "latest is above/below/inside the usual range", "{title}, {unit}" | keep / "Shaded: your usual range, {range} {unit}" / keep | G | design/charts/baseline_band_chart.dart:37-156 |
| X10 | P3 | Contribution bars "No inputs reported for this day."; spoken "{total} breakdown: no inputs available" / "{label}: minus {n} points" / "{label}: {n} of {max} points" / "Total {n}" | "No signals came in for this day."; spoken keep | G | design/charts/contribution_bars.dart:96-127 |
| X11 | P2 | Chart empty states and legends: "Nothing recorded in this range" / "No data yet" / "Sleep stages" / "No stage data for this night" / "Bed and wake times" / "No nights recorded in this range" / "clock time" / "Bedtime" / "Wake" / "Dashed: median bedtime {23:09} · median wake {07:33}" / "No readings yet" / "Trend. {label}" / "Heart rate" / "No heart-rate samples for this window" / "Heart rate · zones unavailable" / "Rest" / "Zone {z}" | keep, except: "Nothing recorded in this period"; drop "clock time"; "Dashed lines: your typical bedtime {11:09 pm} and wake time {7:33 am}"; "No heart rate for this time"; "Resting" | V2, V5 | design/charts/dual_axis_chart.dart:35; frame.dart:417; hypnogram_chart.dart:20-23; scatter_consistency.dart:27-115; sparkline.dart:46-48; zone_timeline.dart:23-116 |
| X12 | P3 | Spoken chart summaries "measured in {unit}" / "from {a} to {b}" / "Key: …" / "Latest {v}" / "ranging {lo} to {hi}" / "roughly level across {n} readings" / "… across {n} readings" / "{title} from {a} to {b}" / "Lowest {lo}, peak {hi} at {t}" | keep | — | design/charts/frame.dart:106-111; axis.dart:275-290; hypnogram_chart.dart:45-47; zone_timeline.dart:76-84 |
| X13 | P3 | Day switcher "Showing {Today}" / "Yesterday" / "Previous day" / "Next day"; trend arrows "Rising" / "Falling" / "…, a significant change over {n} days" | keep; "…, a clear change over {n} days" | V8 | design/components/navigation_bits.dart:116-233 |
| X14 | P1 | Provenance chip "Deep-sleep RMSSD" / "Sleep-mean RMSSD" / "Daily resting HR" / "{name} · {source}" / "Source: {label}"; definition label "{Sleep mean RMSSD} · {Demo data}" (seen on Recovery and Trends); source labels "Bluetooth HR" / "Demo data" / "Google Takeout" | "Deep-sleep HRV" / "Overnight HRV" / "Daily resting HR" / keep / keep; "Overnight HRV · Sample data"; "Bluetooth heart rate" / "Sample data" / keep | G, V8 | design/components/provenance_chip.dart:41-126; domain/models.dart:17-22,87 |
| X15 | P3 | "Sample data" / "Showing sample data" | keep | — | design/components/sample_data.dart:26-37 |
| X16 | P2 | Score ring spoken "{label} {n}{unit}, provisional" / "{label} calibrating, {caption}" / "{label}: no data" / "No data" | "{label} {n}{unit}, early estimate" / "{label} learning, {caption}" / keep | G | design/components/score_ring.dart:169-176,256 |
| X17 | P2 | **Four duration formats**: `PlanFormat.hm` "7 h 36 m" / "45 m"; `durationWords` "1h 05m" / "37 min"; `CoachFormat.duration` "7h 12m" / "45 min"; `sleepHm`/`axisHm`; plus sleep-hero `h:mm` | One rule everywhere: **"7h 36m", "45 min", "8h", "0 min"** (the CoachFormat style, which the verifier and answer_text's unit regex already expect) | V5, flagged | domain/engine/today_planner.dart:78-85; design/format.dart:7-13; domain/coach/format.dart; features/sleep/sleep_view_model.dart:289; design/charts/axis.dart:224 |
| X18 | P1 | **Hard-coded 24h clocks everywhere**: `PlanFormat.clock/time/when`, `CoachFormat.clock`, `clockHm`/`clockOf`, `dayTime`, sleep_screen.dart:302,325, sleep_view_model.dart:283 | Follow the phone setting (`MediaQuery.alwaysUse24HourFormat`): "11:35 pm" or "23:35". Axis labels in 12h style: "10 pm" (no ":00"). See decision D2 for the plumbing. | V5, flagged | today_planner.dart:87-109; design/charts/axis.dart:239-248; design/format.dart:39; domain/coach/format.dart |
| X19 | P2 | `HealthMetricKind` labels 'Resting HR' / 'HRV' / 'Respiratory rate' / 'SpO₂' / 'Skin temp'; unit '/min' | 'Resting HR' / 'HRV' / **'Breathing rate'** / **'Blood oxygen'** / 'Skin temp'; unit 'breaths/min'. These labels feed tiles, chips, the alert, insight cards and coach source chips, so check the verifier and `answer_text.dart:40` (it already matches "/min"). | G | domain/results.dart:663-668 |
| X20 | P2 | Recovery component details "{53} ms · baseline {47} ms" / "{89} % performance" / "{14.9} /min · baseline {15.3}"; penalties "Overnight SpO₂ dipped to {88} %" / "Skin temperature well above your baseline"; "Sleeping HR (4 h mean)" | "{53} ms · usual {47} ms" / "{89}% of your sleep goal" / "{14.9} breaths/min · usual {15.3}"; "Blood oxygen dipped to {88}% overnight" / "Skin temperature well above your usual"; "Sleeping heart rate" | G | domain/engine/recovery.dart:112-283 |
| X21 | P1 | Sync-log messages written by the data layer: "Sync failed: {SocketException}" (a class name!) / "Scores not computed: {error}" / "Could not create a changes token; next sync re-reads" / "Changes call failed; doing a full re-read" / "Changes token expired; doing a full re-read" / "Background reads not granted; syncing when the app opens" / "Permission not granted" / "Not supported by this Health Connect version" / "Health Connect {name}" / "Heart rate response could not be decoded; stored data retained" / "Health Connect covers {n} day(s); fallback only" / "Not configured" / "Not signed in" / "Token refresh failed (sign in again): {e}" / "Google Health response exceeded pagination limit; stored data retained" / "No read variant worked: {e}" / "Provider returned records but the plugin decoded none" / "An empty background read cannot be verified; retry when Airlog opens" / "Seeded {90} synthetic days (seed {42})" / "Could not prepare demo data: {e}" | "Sync failed. Check your connection and try again." / "Couldn’t work out scores for this sync." / "Next sync will read everything again." / "Reading everything again." / "Reading everything again." / "Background sync is off, so Airlog syncs when you open it." / "Not allowed" / "Not supported by your Health Connect version" / keep / "Couldn’t read heart rate from Google. Your saved data is safe." / "Health Connect had {n} days; Google filled the rest" / "Not set up" / "Not signed in" / "Sign-in expired. Reconnect Google Health in Data sources." / "Google sent too much at once. Your saved data is safe." / "Couldn’t read this from Google." / "Couldn’t read these records." / "Will try again when you open Airlog." / "Made {90} days of sample data" / "Couldn’t make sample data." (Put the raw error in logs, not in the UI.) | V8 | data/sync/hc_sync.dart:72-347; data/sync/ghapi_sync.dart:53-208; data/sync/sync_coordinator.dart:118-139; data/services/google_health/*.dart; data/services/health_connect/health_connect_service.dart:320,350; data/repositories/health_repository_impl.dart:298,494,554 |
| X22 | P1 | Source status details: "Sample data: {90} synthetic days, seed {42}, …" / "Reading {n} data types from {apps}" / "Connect Health Connect to see your data" / "Health Connect is not installed" / "Update Health Connect to continue" / "Health Connect is not available on this device" / **"Not configured: add a Google Cloud OAuth client ID (--dart-define=GOOGLE_OAUTH_CLIENT_ID=…)"** / "Signed in: SpO₂, deep-sleep HRV, respiratory rate, skin temperature" / "Sign in to add SpO₂ and deep-sleep HRV" / "Simulated live heart rate (demo)" / "Live heart rate while the band shares it over Bluetooth" / "Weight from any app in Health Connect (shown, never scored)" / "Coming later: import a Google Takeout export" / "Health Connect is not available in this build/device" | "Sample data: {90} made-up days" / keep / keep / keep / keep / keep / **"Not available in this version"** (the build flag goes in logs) / "Signed in: blood oxygen, deep-sleep HRV, breathing rate, skin temperature" / "Sign in to add blood oxygen and deep-sleep HRV" / "Pretend live heart rate (sample data)" / "Live heart rate while your tracker shares it over Bluetooth" / "Weight from any app in Health Connect (shown, not used in scores)" / delete (the Takeout row was cut, PRODUCT_PLAN §7) / "Health Connect isn’t available on this phone" | V8, V6 | data/repositories/health_repository_impl.dart:591-649,940 |
| X23 | P3 | Workout type names from Health Connect ("Treadmill run", "Indoor cycling", "Strength training", "Pool swim", "Open-water swim", "Rowing machine", …); "Live workout" | keep | — | data/services/health_connect/hc_mapper.dart:57-69; health_repository_impl.dart:1138 |
| X24 | P3 | Shell tabs "Today" / "Sleep" / "Strain" / "Trends"; app title "Airlog"; note-card buttons "Profile" / "Open profile" / "Sources" / "Open sources" | keep; "Data sources" / "Open data sources" | G | app/shell.dart:26-29; app/app.dart:30; app/note_card.dart:15-18 |
| X25 | P3 | Status notes (generated): titles, bodies and fixes | see §4.7 | — | domain/engine/notes.dart |

### 3.8 Journal [Revamp]

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| J01 | P3 | "Could not open the journal" / "The stored entries could not be read. Nothing was changed." / "Try again" | "Couldn’t open the journal" / "Airlog couldn’t open your saved entries. Nothing was changed." / "Try again" | V8 | features/journal/journal_screen.dart:31-33 |
| J02 | P3 | "Journal" | keep | — | journal_screen.dart:48 |
| J03 | P2 | "What applies this evening?" / "What applied that evening?" | "What happened this evening?" / "What happened that evening?" | V2 | journal_screen.dart:102-103 |
| J04 | P2 | "Tap everything that fits. Airlog compares it with the next morning’s Recovery." | "Tap all that fit. Airlog checks each one against your Recovery the next morning." | V2 | journal_screen.dart:108-109 |
| J05 | P3 | "Could not save the last change. Tap again to retry." / "Saved on this phone as you tap." / "{n} tagged · saved on this phone" | "Couldn’t save that. Tap it again." / keep / keep | V2 | journal_screen.dart:141-144 |
| J06 | P2 | "What moves your recovery" (both headers) | "What moves your Recovery" | G: score names are capitalised | journal_screen.dart:156,170 |
| J07 | P2 | "Patterns take a few weeks" / "Each factor needs at least {10} tagged days with it and {10} without, each followed by a Recovery score. Keep tagging your evenings, including the ordinary ones." | "Patterns take a few weeks" / "Each habit needs {10} tagged days with it and {10} without, each followed by a Recovery score. Keep tagging your evenings, even the ordinary ones." | V2 | journal_screen.dart:160-165 |
| J08 | P1 | "Next-morning Recovery, days with a factor vs days without" | "Your next-morning Recovery, with and without each habit" | V2 | journal_screen.dart:171 |
| J09 | P2 | "No clear effects yet: every difference so far is within day-to-day noise." | "No clear links yet. So far, every difference could be chance." | V8: "noise" | journal_screen.dart:175-176 |
| J10 | P1 | "Emerging" / "Enough days, but the difference is still within noise" | "Maybe" / "Enough days, but it could still be chance" | V8 | journal_screen.dart:192-193 |
| J11 | P3 | "Not enough days yet: {list}. Each needs {10} days with it and {10} without." | keep | — | journal_screen.dart:209-211 |
| J12 | P1 | "Correlation, not causation" / "These are differences in your own data, not proof of cause: other things often change on the same days. "Solid" means the gap is more than twice its standard error (Welch)." | "A link, not a cause" / "These are differences in your own data, not proof that one thing causes another. Other things often change on the same days. “Clear” means the gap is more than twice its likely error (Welch’s test)." | V2, V8 | journal_screen.dart:229-240 |
| J13 | P1 | Insight line "{Alcohol} is associated with {25} points {lower} recovery the next day" / "{Alcohol}: no difference in next-day recovery"; badge "Solid" / "Emerging"; "{15} vs {64} days"; detail "{15} days with vs {64} without · average {43} % vs {67} %" | **Option A (recommended, decision D8):** "{After alcohol}, your next-day Recovery was {25} points {lower}". It uses a per-habit lead-in: After alcohol / After late caffeine / After a late meal / After a stressful day / After feeling sick / After screens before bed / After a workout / After travel / After meditating. No-difference line: "{Alcohol}: no difference in your next-day Recovery". Badge "Clear" / "Maybe"; "{15} days with, {64} without"; detail "{15} days with, {64} without · average {43}% vs {67}%". **Option B** (keeps §7's "associated with" idea): "{Alcohol} is linked to {25} points {lower} Recovery the next day". | V2; D8 | journal_screen.dart:352-420; features/journal/journal_view_model.dart:205-215 |
| J14 | P3 | "With" / "Without"; "Consistency" / "{n} of 7 days"; spoken "Consistency: {n} of the last 7 evenings logged." | keep | — | journal_screen.dart:432-459 |
| J15 | P2 | Habit label **"Trained"** (others: Alcohol, Late caffeine, Late meal, Stress, Feeling sick, Screens before bed, Travel, Meditation) | **"Worked out"**, others keep. The enum is shared code, so **Phase B** edits `models.dart` and adds "worked out" to the on-device coach alias list (offline_client.dart:714). | V2: "Trained is associated with…" doesn't read | domain/models.dart:531 |

### 3.9 Live heart rate [Revamp: intro and summary. The scan, recording and HRV-check stages are in the same files; I assume Revamp, see D12]

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| L01 | P3 | App bar "Live heart rate" / "Workout summary" / "HRV check" | keep | — | features/live/live_screen.dart:23-25 |
| L02 | P2 | "Leave this session?" / "The heart rate recorded so far is not saved yet. Leaving discards it." / "Stay" / "Discard and leave" | "Leave this workout?" / "Your workout isn’t saved yet. If you leave, it’s deleted." / "Stay" / "Delete and leave" | V2; the button names the consequence | live_screen.dart:58-70 |
| L03 | P2 | "Heart rate, live" | "Live heart rate" | V2 | live_screen.dart:117 |
| L04 | P2 | "See your heart rate, zone and strain as you train, straight from your tracker over Bluetooth. Nothing leaves this phone." | "See your heart rate and effort as you train. Your tracker sends it straight to this phone over Bluetooth. Nothing leaves your phone." | V2 | live_screen.dart:123-124 |
| L05 | P3 | "Before you start" | keep | — | live_screen.dart:134 |
| L06 | P2 | "Turn on heart-rate broadcast on your tracker (on a Fitbit: Google Health → ‘Share heart rate’). It costs some battery, so turn it off afterwards." | "Turn on heart-rate sharing on your tracker (on a Fitbit: Google Health app → ‘Share heart rate’). It uses battery, so turn it off afterwards." | V2 | live_screen.dart:137-139 |
| L07 | P3 | "Keep your tracker snug on your wrist and the phone within a few metres." | keep | — | live_screen.dart:143-144 |
| L08 | P1 | "Demo mode: a simulated tracker stands in for yours." | "Sample data: a pretend tracker stands in for yours." | G | live_screen.dart:149 |
| L09 | P3 | "Find my tracker"; "Strong signal" / "Good signal" / "Weak signal"; spoken "Connect to {name}, {signal}" | keep | — | live_screen.dart:157-206 |
| L10 | P1 | "Nearby heart-rate sensors" / "Scanning for the Heart Rate service (0x180D)…" / "Devices broadcasting the Heart Rate service (0x180D)" | "Trackers nearby" / "Looking for trackers…" / "Trackers sharing heart rate" | V8: a hex service ID | live_screen.dart:195-198 |
| L11 | P2 | "No heart-rate sensors found" / "Most trackers broadcast heart rate only while sharing is on. Turn it on (on a Fitbit: Google Health → ‘Share heart rate’), keep the tracker close, then scan again." / "Scan again" | "No trackers found" / "Most trackers only share heart rate while sharing is on. Turn it on (on a Fitbit: Google Health app → ‘Share heart rate’), keep the tracker close, then look again." / "Look again" | V2 | live_screen.dart:248-253 |
| L12 | P2 | "Don’t see your tracker? Turn on heart-rate broadcast (on a Fitbit: Google Health → ‘Share heart rate’), then scan again." / "Scan again" | "Don’t see your tracker? Turn on heart-rate sharing (on a Fitbit: Google Health app → ‘Share heart rate’), then look again." / "Look again" | V2 | live_screen.dart:260-269 |
| L13 | P3 | "Connecting to {name}…" / "Keep your tracker close to the phone." | keep | — | live_screen.dart:299-305 |
| L14 | P3 | "Bluetooth permission needed" / "Airlog needs “Nearby devices” permission to find your tracker. It is used only while this screen is open, never for location." / "Allow it when Android asks, or in Android Settings → Apps → Airlog → Permissions." | keep / "Airlog needs the “Nearby devices” permission to find your tracker. It’s used only while this screen is open, never for location." / keep | V2 | live_screen.dart:325-329 |
| L15 | P3 | "Bluetooth is off" / "Turn Bluetooth on to connect to your tracker." / "Swipe down for Quick Settings and tap Bluetooth." | keep | — | live_screen.dart:332-334 |
| L16 | P2 | "Bluetooth LE isn’t available" / "This phone does not support Bluetooth Low Energy, which heart-rate straps and trackers use." | "This phone can’t connect to trackers" / "It doesn’t support the kind of Bluetooth that heart-rate trackers use." | V8 | live_screen.dart:337-339 |
| L17 | P1 | "Live heart rate isn’t available" / "This build has no Bluetooth service wired in." | "Live heart rate isn’t available" / "This version of Airlog can’t use Bluetooth." | V8 | live_screen.dart:343-344 |
| L18 | P2 | "Your tracker isn’t sharing heart rate" / "It connected, but it is not broadcasting heart rate, so there is nothing to read." / "Turn on heart-rate broadcast on your tracker (on a Fitbit: Google Health → ‘Share heart rate’), then try again." | keep / "It connected, but it isn’t sharing heart rate, so there’s nothing to read." / "Turn on heart-rate sharing on your tracker (on a Fitbit: Google Health app → ‘Share heart rate’), then try again." | V2 | live_screen.dart:348-352 |
| L19 | P2 | "Couldn’t connect" / "Your tracker did not accept the connection. It may have stopped sharing heart rate, or another app is connected to it." / "Check that heart-rate broadcast is on (on a Fitbit: ‘Share heart rate’ in Google Health), then try again." | keep / "Your tracker didn’t accept the connection. It may have stopped sharing heart rate, or another app is connected to it." / "Check that heart-rate sharing is on (on a Fitbit: ‘Share heart rate’ in the Google Health app), then try again." | V2 | live_screen.dart:355-359 |
| L20 | P3 | "Something went wrong" / "The Bluetooth scan stopped unexpectedly." / "Try again" | keep / "The search for trackers stopped. Try again." / keep | V2 | live_screen.dart:362-379 |
| L21 | P3 | "Waiting for heart rate" / "{b} beats per minute" / "Waiting for heart rate…" | keep | — | features/live/widgets/live_widgets.dart:24-35 |
| L22 | P1 | Zone text "Below zone 1" / "Zone {z}" / "under {x} bpm" / "{lo}–{hi} bpm" / "{x}+ bpm"; spoken "{name}, {range}, estimated from maximum heart rate" / "{name}, {pct} of heart-rate reserve" / "Zone unknown" | "Resting" / "Zone {z} · {Very light / Light / Moderate / Hard / Max}" / keep / keep / keep; spoken "{name}, {range}, based on your max heart rate" / "{name}, {range}" / "Zone unknown" | G, V8 | live_widgets.dart:84-98 |
| L23 | P1 | Zone line **"Zone 3 · 70–80 % HRR · 147–159 bpm"**; "Zone appears with the first reading" | **"Zone 3 · Moderate · 147–159 bpm"**; "Your zone shows with the first reading" | V8: "HRR" | live_widgets.dart:141-142 |
| L24 | P2 | "Connection lost" / "Your session so far is kept. Move the phone closer to the tracker; it reconnects when you tap below." / "Your tracker stopped sending. Move the phone closer and reconnect." / "Reconnect" | "Connection lost" / "Your workout so far is safe. Move your phone closer to your tracker, then tap Reconnect." / "Your tracker stopped sending. Move your phone closer, then reconnect." / "Reconnect" | V2 | live_widgets.dart:213-221 |
| L25 | P3 | "Tracker" / "Recording" / "Cool-down" | keep | — | live_widgets.dart:236-253 |
| L26 | P1 | "Heart rate is available. Zones and strain need a usable maximum heart rate." | "Heart rate is coming in. Add your birth year in Profile to see zones and Strain." | V1: say the fix | live_widgets.dart:271 |
| L27 | P2 | "Elapsed" / "Strain" / "Avg bpm" | "Time" / "Strain" / "Avg bpm" | V2 | live_widgets.dart:282-295 |
| L28 | P3 | "This session" / "Stop" / "Start workout" / "Disconnect" | keep | — | live_widgets.dart:324-357 |
| L29 | P1 | "After Stop, keep still for 60 seconds: the drop in heart rate over that minute is your heart-rate recovery." | "After you tap Stop, stay still for 1 minute. Airlog measures how fast your heart rate drops." | V2 | live_widgets.dart:366-367 |
| L30 | P1 | "{left}" / "Stay still for {left} s" / "Measuring heart-rate recovery (HRR-60)." / "Skip" | keep / keep / "Measuring how fast your heart rate drops." / keep | V8 | live_widgets.dart:400-420 |
| L31 | P1 | "HRV check" / "Two minutes sitting still. RMSSD from the time between individual beats." | "HRV check" / "Sit still for 2 minutes while Airlog measures your HRV." | V8 | live_widgets.dart:449-451 |
| L32 | P1 | "HRV check unavailable" / "Your tracker sends heart rate but not the time between beats (RR intervals), and HRV is computed from those. Its broadcast may simply not include them. Your nightly HRV from sleep is unaffected." | "HRV check isn’t available" / "Your tracker shares heart rate, but not the timing of each beat, which HRV needs. Your nightly HRV isn’t affected." | V8 | live_widgets.dart:455-459 |
| L33 | P1 | "Unlocks after you connect, if your tracker sends beat-to-beat (RR) intervals." / "Checking whether your tracker sends beat-to-beat intervals…"; chips "No RR data" / "Locked"; "Start HRV check" | "Works after you connect, if your tracker shares the timing of each beat." / "Checking if your tracker shares beat timing…"; "Not available" / "Locked"; keep | V8 | live_widgets.dart:463-502 |
| L34 | P1 | Summary rows "STRAIN" / "Duration" / "Average" / "Peak" / **"TRIMP (cross-check)"** | "STRAIN" / "Duration" / "Average" / "Peak" / **remove the TRIMP row** | V8 (coordinator flag) | live_widgets.dart:552-565 |
| L35 | P1 | "Heart-rate recovery"; value "−{29}" + "bpm in the first minute"; spoken "Heart-rate recovery {29} beats per minute in the first minute" / "Heart-rate recovery not measured"; body "How fast your heart rate falls after effort (HRR-60, Cole et al. 1999). A bigger drop generally means a fitter recovery; compare it with your own past sessions rather than a chart." | "Heart-rate recovery"; value "{29}" + "bpm drop in the first minute" (if it rose: "{n}" + "bpm rise in the first minute"); spoken "Heart-rate recovery: your heart rate dropped {29} beats per minute in the first minute" / keep; body "How fast your heart rate falls after you stop. A bigger drop usually means better fitness. Compare it with your own past workouts, not with a chart." | V8; the "−" sign reads as bad | live_widgets.dart:582-619 |
| L36 | P2 | "Not measured: the 60-second cool-down was skipped." / "Not measured: no reading at Stop and 60 s later (within 10 s). Keep your tracker connected through the cool-down next time." | "Not measured: you skipped the 1-minute cool-down." / "Not measured: your tracker didn’t send a reading during the cool-down. Keep it connected until the minute is up next time." | V2 | live_widgets.dart:625-628 |
| L37 | P2 | "Saved" / "The workout is in today’s strain and workouts list." / "Back to live" / "Saving…" / "Save workout" / "Workouts under a minute are not saved." / "Could not save: {error}" / "Discard" | "Saved" / "It now counts toward today’s Strain and shows in your workouts." / "Back to live heart rate" / "Saving…" / "Save workout" / "Workouts under 1 minute aren’t saved." / "Couldn’t save: {error}" / "Delete" | V2 | live_widgets.dart:638-671 |
| L38 | P2 | "Connection lost" / "Beats stopped arriving. Cancel and try again with the phone closer to your tracker." | "Connection lost" / "Your tracker stopped sending. Cancel, move your phone closer, and try again." | V2 | live_widgets.dart:701-704 |
| L39 | P3 | "{n} seconds left" / "LEFT" / "Sit still and breathe normally" / "{n} beats so far" / "Cancel" | keep | — | live_widgets.dart:720-761 |
| L40 | P1 | "Rest your arm, keep quiet, and breathe the way you usually do. Paced or deep breathing raises RMSSD, so natural breathing keeps checks comparable with each other." | "Rest your arm, stay quiet, and breathe the way you normally do. Deep breathing changes the result." | V8 | live_widgets.dart:746-748 |
| L41 | P1 | "Not enough clean beats" / "RMSSD needs at least 30 clean beat-to-beat intervals ({12} arrived; movement and missed beats are filtered out). No number is shown rather than a guess." / "Sit still with your tracker snug, then try again." / "Back to live" | "Not enough clear beats" / "Airlog needs at least 30 clear beats and got {12}. Moving can blur beats. Airlog shows no number rather than a guess." / keep / "Back to live heart rate" | V8, V6 | live_widgets.dart:786-792 |
| L42 | P1 | Result label "RMSSD" / "Beats analysed" / "RMSSD is the beat-to-beat variation your vagus nerve drives: higher is more relaxed, for you. A spot check while awake reads differently from your overnight HRV, so compare checks with each other, not with Recovery." | "HRV" / "Beats checked" / "Higher usually means more relaxed, for you. A daytime check reads differently from your overnight HRV, so compare checks with each other, not with Recovery." | V8 | live_widgets.dart:800-823 |
| L43 | P3 | "Saved" / "The check is stored with today’s data." / "Back to live" / "Saving…" / "Save HRV check" / "Discard" | "Saved" / "Saved with today’s data." / "Back to live heart rate" / keep / keep / "Delete" | V2 | live_widgets.dart:832-849 |

### 3.10 Onboarding [Revamp]

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| O01 | P3 | "Next" / "Back" / "Waiting for Health Connect…" / "Continue to Health Connect" / "Try with sample data instead" / "Open Health Connect settings" / "Try again" / "{n} of 3" / spoken "Step {n} of {total}" | keep | — | features/onboarding/onboarding_screen.dart:35-124,189,249 |
| O02 | P1 | "Airlog" / "Recovery, strain and sleep from your tracker, computed on this phone and explained in full." | "Airlog" / "Each morning: how you are, and what to do today. Worked out on this phone from your tracker’s data." | V1: lead with the one job | onboarding_screen.dart:291-294 |
| O03 | P3 | "What it is" / "What it isn’t" | keep | — | onboarding_screen.dart:296,317 |
| O04 | P1 | "Recovery." "How ready you are, each morning, from HRV, resting heart rate, sleep and breathing against your own baseline." | "Recovery." "How ready your body is each morning, compared with your usual." | V2 | onboarding_screen.dart:299-302 |
| O05 | P2 | "Strain." "How hard your heart worked across the day, by heart-rate zone." | "Strain." "How hard your heart worked today." | V2 | onboarding_screen.dart:305-308 |
| O06 | P1 | "Sleep." "What you needed, what you got, and the debt carried forward." | "Sleep." "How much you slept, and how much sleep you need tonight." | G | onboarding_screen.dart:311-314 |
| O07 | P2 | "Not medical." "It notices patterns against your own normal; it does not diagnose anything." | "Not medical." "It spots patterns in your own numbers. It doesn’t diagnose anything." | V2 | onboarding_screen.dart:320-323 |
| O08 | P1 | **"Not WHOOP’s formula."** "Published methods, every formula on view. Numbers will differ from WHOOP’s and Fitbit’s." | **"Our own formula."** "Open methods you can read in the app. Your numbers will differ from other apps." | Brand rule; D6 | onboarding_screen.dart:326-329 |
| O09 | P3 | "Independent." "Not affiliated with Google, Fitbit or WHOOP." | keep (a legal disclaimer names the marks it disclaims; D6) | — | onboarding_screen.dart:332-334 |
| O10 | P3 | "It stays on this phone" / "Every score is computed here. There is nothing to sign up for." | "It stays on this phone" / "Every score is worked out here. There’s nothing to sign up for." | V2 | onboarding_screen.dart:347-348 |
| O11 | P2 | "Scores are computed on the phone, from data already on the phone." | "Your scores are worked out on this phone, from data already on it." | V2 | onboarding_screen.dart:351-352 |
| O12 | P3 | "No Airlog server and no account." / "No analytics, no ads, no tracking." | keep | — | onboarding_screen.dart:356,360 |
| O13 | P3 | "Export readings and scores, or delete local data, whenever you like." | "Save a copy of your data, or delete it, whenever you like." | V2 | onboarding_screen.dart:364 |
| O14 | P2 | "If you opt in to a cloud coach, your questions and permitted context are sent to the provider you choose. On-device coaching does not send them." | "If you turn on Claude or Gemini for Coach, your questions and the data they need go to that company. The on-phone coach sends nothing." | G, V2 | onboarding_screen.dart:368-370 |
| O15 | P3 | "Read the privacy policy"; spoken "{title}. {body}" | keep | — | onboarding_screen.dart:377,411 |
| O16 | P3 | "How do you want to start?" / "You can switch at any time in Settings. Sample and real data are kept apart." / "Check your setup" | keep / "You can switch any time in Settings. Sample data and your data are kept apart." / keep | G | onboarding_screen.dart:443-450 |
| O17 | P2 | "Connect Health Connect" / "We’ll find the apps you already use. You choose each data type." | "Use my tracker’s data" / "Airlog reads it through Health Connect. You choose what to share." | V2: "Connect Health Connect" stutters; avoid "we" | onboarding_screen.dart:459-460 |
| O18 | P3 | "Try with sample data" / "90 days of sample data, labelled “Sample data” everywhere. Good for a look around first." | keep | — | onboarding_screen.dart:467-469 |
| O19 | P2 | "Birth year (optional)" / "For adults 18+. Used to estimate maximum heart rate." | "Birth year (optional)" / "Sets your heart-rate zones. Airlog is for people 18 and over." | V1 | onboarding_screen.dart:480-481 |
| O20 | P1 | "What Airlog will read" / "Health Connect asks you type by type next. Each one powers one feature; anything you leave off shows as missing, never guessed. Read only: Airlog writes nothing back." | "What Airlog will read" / "Next, Health Connect asks about each kind of data. Allow the ones you want. Anything you skip shows as missing, never guessed. Airlog only reads your data. It never changes it." | V2 | onboarding_screen.dart:496-500; app/hc_rationale.dart:65-73 |
| O21 | P3 | Rationale buttons "Continue to Health Connect" / "Not now"; list item "{type}." | keep | — | app/hc_rationale.dart:21,92,98 |
| O22 | P3 | "Health Connect isn’t installed" / "Install Health Connect from Google Play, turn on sync in your tracker’s app, then connect from Settings → Sources." | keep / "Install Health Connect from Google Play, turn on syncing in your tracker’s app, then connect in Settings → Data sources." | G | onboarding_screen.dart:514-516 |
| O23 | P3 | "Health Connect needs an update" / "Update it from Google Play, then connect from Settings → Sources." | keep / "Update it from Google Play, then connect in Settings → Data sources." | G | onboarding_screen.dart:519-520 |
| O24 | P3 | "Health Connect isn’t available here" / "This device cannot run Health Connect. You can still explore everything with sample data." | keep / "This phone can’t run Health Connect. You can still look around with sample data." | V2 | onboarding_screen.dart:523-525 |
| O25 | P2 | "No access granted" / "Airlog cannot read your data without at least one data type. Nothing was changed." / "Health Connect did not answer. Try again in a moment." / "Not connected" | "Nothing shared yet" / "Airlog needs at least one kind of data to work. Nothing was changed." / "Health Connect didn’t answer. Try again in a moment." / keep | V2 | onboarding_screen.dart:528-536 |
| O26 | P3 | "Airlog is for adults. Enter a birth year between {y−100} and {y−18}, or leave it blank." / "Could not start sample data. Your choice was not completed. Try again." / "Access was granted, but setup could not finish. Try again." | keep / "Couldn’t load sample data. Try again." / "Access is on, but setup didn’t finish. Try again." | V2 | features/onboarding/onboarding_view_model.dart:173-174,235,267 |
| O27 | P1 | **Shared list** `hcReadTypes` (onboarding, Sources rationale and the privacy policy). **Phase B edits it in copy.dart; Revamp only reads it.** **The type names stay unchanged**: they match Android's own Health Connect permission screen, which the user sees next, and `test/features/privacy_copy_test.dart:29-45` pins them to the manifest (PLAY_RELEASE §2). Only the descriptions change, and only in wording. | Heart rate — "Strain and your heart-rate zones." · Heart rate variability (RMSSD) — "HRV: the biggest part of your Recovery score." · Resting heart rate — "Recovery, and the overnight signals on Today." · Respiratory rate — "Your breathing rate. Used for Recovery and the overnight signals on Today." · Skin temperature — "The overnight signals on Today. A change isn’t a diagnosis." · Sleep sessions and stages — "Your Sleep score, missed sleep, consistency and Recovery." · Exercise sessions — "Strain for each workout." · Steps — "Shown next to your trends. Steps don’t count toward Strain." · Weight (optional) — "Only if you allow it. Shown next to your trends." · VO₂ max — "A cardio-fitness trend, shown as your tracker’s own estimate." · Blood oxygen (SpO₂) — "Overnight blood oxygen. Recovery drops a little if it goes below 90%." · Distance — "Needed to read your workouts. Shown on each one." · Total calories burned — "Needed to read your workouts. Shown on each one." · History and background reads (optional) — "Older data, so Airlog knows your usual from day 1, and syncing in the background, so your morning Recovery is ready." | G, V2 | app/copy.dart:22-58 |

### 3.11 Settings [Revamp]

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| SE01 | P3 | "Settings"; section labels "Data" / "Your data" / "About" | keep | — | features/settings/settings_screen.dart:84,90,170,231 |
| SE02 | P1 | "Data mode" / segments **"Demo" / "Live"** | "Data" / **"Sample data" / "My data"** | G: "Live" clashes with Live heart rate; "Demo" vs "Sample" | settings_screen.dart:106-116 |
| SE03 | P2 | "Sample data: 90 days generated on this phone, so you can explore every screen. Nothing here is your data." / "Live: your tracker’s data from Health Connect (and Enhanced mode, if on). Demo and live data are kept apart; switching never mixes them." | keep / "My data: your tracker’s data from Health Connect (and Enhanced mode, if it’s on). Sample data and your data are kept apart. Switching never mixes them." | G | settings_screen.dart:126-130 |
| SE04 | P2 | Rows "Sources" / "Health Connect, Enhanced mode, Bluetooth"; "Profile" / "Birth year, sex, max heart rate"; "Sync log" / "Every sync, per data type"; "Coach" / "Engine, messages and what it remembers" | "Data sources" / "Health Connect, Enhanced mode, Bluetooth"; "Profile" / "Birth year, sex, max heart rate"; "Sync log" / "What came in with each sync"; "Coach" / "Who answers, notes, and what it remembers" | G, V8 | settings_screen.dart:141-164 |
| SE05 | P2 | Row subtitles "Demo data in use" / "Health Connect connected" / "Health Connect not connected" / "Health Connect unavailable" / "Enhanced mode not configured" / "Enhanced mode on" / "Enhanced mode off" / "Born {y}" / "No birth year" / "Female" / "Male" / "Sex not specified" / "Max HR {n}" | "Sample data in use" / keep / keep / "Health Connect not available" / "Enhanced mode not set up" / keep / keep / keep / keep / keep / keep / keep / "Max heart rate {n}" | G | features/settings/settings_view_model.dart:63-89 |
| SE06 | P2 | Export title "Export readings and scores" (SettingsCopy) / body "Readings, scores and journal entries for the current data mode and enabled sources, as CSV and JSON. This is a readable export, not a restorable backup. Coach chats, memory and settings are not included." / "Exporting…" / "Export" | keep title / "Your readings, scores and journal as CSV and JSON files you can open in a spreadsheet. It’s a copy to read, not a backup to restore. Coach chats and settings aren’t included." / keep / keep | V2 | app/copy.dart:86; settings_screen.dart:182-192 |
| SE07 | P3 | "Exported {n} files. Choose where to keep them." / "Export failed: {error}"; share subject "Airlog export" / body "Airlog readable data export for the selected mode and enabled sources, as CSV and JSON. Not a restorable backup."; "Could not create or share the export. Try again." | keep / "Couldn’t export: {error}"; keep / keep; "Couldn’t make the export. Try again." | V2 | settings_screen.dart:33-34; settings_view_model.dart:182-189 |
| SE08 | P2 | Delete card "Delete all data" / "Deletes health records, journal entries, live sessions, coach chats and memories, and exports held by Airlog. Settings, profile, cloud keys and source sign-ins stay. Shared copies stay elsewhere. Demo data is regenerated in Demo mode." / "Deleting…" / "Hold to delete" / spoken "Press and hold for two seconds to delete" / "Keep holding to confirm" | keep / "Deletes your readings, scores, journal, workouts, coach chats and memories, and any exports Airlog stored. Your settings, profile, keys and sign-ins stay. Copies you already shared stay where they are." / keep / keep / keep / keep | V2; serious tone kept | settings_screen.dart:212-222; widgets/hold_to_confirm.dart:33,172 |
| SE09 | P2 | Dialog "Delete all data?" / "Deletes stored readings, scores, journal entries, live sessions, coach chats and memories, and exports held by Airlog. Settings, profile, cloud keys and source sign-ins stay. Copies already shared elsewhere and records in Health Connect or Google stay. Demo data is regenerated in Demo mode. This cannot be undone." / "Cancel" / "Delete" | "Delete all data?" / "This deletes your readings, scores, journal, workouts, coach chats and memories, and any exports Airlog stored. Your settings, profile, keys and sign-ins stay. Data in Health Connect or Google, and copies you already shared, stay too. With sample data on, fresh sample data is made. This can’t be undone." / "Cancel" / **"Delete all data"** | The confirm button repeats the consequence (skill rule) | settings_screen.dart:55-71 |
| SE10 | P3 | "Stored records deleted. Settings and keys kept." / "Deletion did not finish. Some records may already be removed." / "Deletion did not finish. Some records may already be removed. Try again to complete it." / "Could not switch data mode. Check the selected mode and try again." / "Wait for the current action to finish." | "Your data was deleted. Settings and keys are kept." / "Delete didn’t finish. Some data may already be gone." / "Delete didn’t finish. Some data may already be gone. Try again to finish." / "Couldn’t switch. Try again." / keep | V2 | settings_screen.dart:44-45; settings_view_model.dart:163-204 |
| SE11 | P2 | About rows "How scores work" / "Every formula, constant and source"; "Diagnostics" / "What reaches this phone, per data type"; "Privacy" / "Local by default. Optional cloud coach explained"; "Licences" / "Pulse (Apache-2.0), Edge (MIT), DM Sans (OFL)" | "How scores work" / "The formulas behind every score"; "Diagnostics" / "Check what data arrives from your tracker"; "Privacy" / "What stays on your phone, and what doesn’t"; "Licences" / "Open-source software Airlog uses" | V8 | settings_screen.dart:237-256 |
| SE12 | P2 | "Algorithm version" / "v{3}"; "App version" | "Score formula version" / "{3}"; "App version" | G | settings_screen.dart:265-268 |
| SE13 | P3 | Footer "Not medical advice. Not affiliated with Google, Fitbit or WHOOP." | keep (legal; D6) | — | settings_screen.dart:273 |

### 3.12 Profile [Revamp]

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| P01 | P3 | "Profile"; "Discard changes?" / "Your edits to the profile are not saved." / "Keep editing" / "Discard" | keep; "Discard changes?" / "Your changes aren’t saved." / "Keep editing" / "Discard" | V2 | features/settings/profile_screen.dart:32-63 |
| P02 | P3 | "Profile could not load" / "The data store did not answer. Go back and try again." | "Couldn’t load your profile" / "Go back and try again." | V8 | profile_screen.dart:72-74 |
| P03 | P3 | "Saved. Every score was recalculated with it." / "Check the highlighted fields." | "Saved. All your scores were updated." / keep | V2 | profile_screen.dart:115-116 |
| P04 | P2 | "Four facts that make the maths yours. They stay on this phone." | "A few details that make your scores fit you. They stay on this phone." | V2 | profile_screen.dart:176 |
| P05 | P1 | "Birth year" / "Sets your age-predicted max heart rate ({208} − {0.7} × age, Tanaka 2001), which places every heart-rate zone. **Without it Airlog assumes 30 and says so.**" | "Birth year" / "Sets your max heart rate, which sets your heart-rate zones. Without it, Airlog uses the highest heart rate it has seen from you." | **V6: false.** The engine never assumes an age (notes.dart:274-275, `observedMaxHr`) | profile_screen.dart:182-193 |
| P06 | P1 | "Sex" / "Female" / "Male" / "Not specified" / "Picks the TRIMP weighting curve, which differs by sex. “Not specified” uses the average of both." | "Sex" / keep / keep / keep / "Doesn’t change your scores. It’s only used for a second-opinion effort number on the How Strain works page. “Not specified” uses the average of both." | V6, V8: sex only feeds TRIMP (methodology_screen.dart:357-363), and users will assume it changes their scores | profile_screen.dart:198-218 |
| P07 | P2 | "Max heart rate (optional)" / "From your data" / "Predicted {184}" / "Only if you have measured it in a hard, all-out effort. Without it or a birth year, zones use the highest heart rate your data has shown." / "Only if you have measured it in a hard, all-out effort. It replaces the prediction ({184} bpm) for zones and strain. Leave empty to use the prediction." | "Max heart rate (optional)" / "From your data" / "From your age: {184}" / "Only fill this in if you’ve measured it in an all-out effort. Without it or a birth year, Airlog uses the highest heart rate it has seen from you." / "Only fill this in if you’ve measured it in an all-out effort. Otherwise Airlog uses {184} bpm, based on your age." | V2 | profile_screen.dart:223-239 |
| P08 | P3 | "Weight (optional)" / "Not used in any score. It stays with your profile on this phone." / "Saving…" / "Save" / "Saving recalculates every day’s scores with the new values." | keep / keep / keep / keep / "Saving updates all your scores." | V2 | profile_screen.dart:244-264 |
| P09 | P3 | Validation "Airlog is for adults. Enter a year between {a} and {b}" / "Between 100 and 240 bpm" / "Between 30 and 300 kg" | keep / "Enter 100 to 240 bpm" / "Enter 30 to 300 kg" | V2: errors say how to fix | features/settings/profile_view_model.dart:48-67 |

### 3.13 Sync log [Revamp]

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| SY01 | P2 | Status words "OK" / "Nothing new" / "Failed" / "No permission" / "Skipped" | "Updated" / "Nothing new" / "Failed" / "Not allowed" / "Skipped" | V2 | features/settings/sync_log_screen.dart:40-44 |
| SY02 | P2 | "Nothing synced yet" / "Demo data is generated on this phone, so there is nothing to sync. Connect Health Connect to see every read here." / "Each sync lists every data type it read, with a count, so a missing type is easy to spot." | "Nothing synced yet" / "Sample data is made on this phone, so there’s nothing to sync. Connect Health Connect to see each sync here." / "Each sync lists every kind of data it read, with a count, so anything missing is easy to spot." | G | sync_log_screen.dart:80-85 |
| SY03 | P3 | "Sync log could not load" / "The data store did not answer. Go back and try again." / "Sync log" / "{n} record(s)" / spoken "{type} from {source}: {word}" / "{day time} ({ago})" | "Couldn’t load the sync log" / "Go back and try again." / keep / keep / keep / keep | V8 | sync_log_screen.dart:91-206 |
| SY04 | P1 | The message lines come from the data layer ("Sync failed: SocketException", "Token refresh failed (sign in again): …" and others) | see X21 (Phase B changes them at the source) | V8 | — |

### 3.14 Data sources [Revamp]

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| SO01 | P2 | Title "Data sources" / "Sources could not load" / "The data store did not answer. Go back and try again." | keep / "Couldn’t load data sources" / "Go back and try again." | V8 | features/settings/sources_screen.dart:51-67 |
| SO02 | P1 | "Each metric comes from one source, picked by priority, never averaged. Switching a metric’s source starts a new baseline instead of mixing two kinds of measurement." | "Each measurement comes from one app at a time, never an average. If you switch apps, Airlog learns your usual again instead of mixing the two." | G, V8 | sources_screen.dart:74-76 |
| SO03 | P2 | "Sample data is in use. Connect Health Connect below; the first grant switches Airlog to your own data." | "You’re looking at sample data. Connect Health Connect below to switch to your own data." | V2 | sources_screen.dart:191-192 |
| SO04 | P2 | HC card "Health Connect" / "Main source · every app that writes to it" / "Connected" / "Not connected" / "Unavailable" / "Read from Health Connect" / "{9} of {10} data types granted" / "Missing: {Weight}" / "History (older than 30 days)" / "Background reads (sync while closed)" / "Get Health Connect" / "Update Health Connect" / "Waiting for Health Connect…" / "Review permissions" / "Connect Health Connect" | "Health Connect" / "Main source · reads every app that shares with it" / keep / keep / "Not available" / keep / "{9} of {10} kinds of data allowed" / "Not allowed: {Weight}" / keep / "Background sync (while Airlog is closed)" / keep / keep / keep / keep / keep | G | sources_screen.dart:419-477 |
| SO05 | P3 | Status lines "Install Health Connect from Google Play first." / "Update Health Connect from Google Play first." / "Health Connect is not available on this device." / "No access granted. Airlog cannot read your data without it." / "Reading {n} data types." | keep / keep / "Health Connect isn’t available on this phone." / "Nothing shared yet. Airlog can’t read your data until you allow it." / "Reading {n} kinds of data." | V2 | sources_screen.dart:104-112 |
| SO06 | P3 | "Health Connect won’t ask again" / "Access was declined twice, so Android no longer shows the request. Grant it in Health Connect’s own settings." / "Open Health Connect settings" | keep / "You said no twice, so Android won’t ask again. Allow it in Health Connect’s settings." / keep | V2 | sources_screen.dart:271-275 |
| SO07 | P1 | Enhanced card "Enhanced mode" / "Google Health API" / "Beta" / "Not configured" / "Signed in" / "Off" / "Adds overnight SpO₂, deep-sleep HRV (the cleanest Recovery input) and breathing rate by sleep stage. Optional." / "Connect Google Health" / "Disconnecting…" / "Disconnect" / "Waiting for Google…" | "Enhanced mode" / "Google Health API" / "Beta" / "Not set up" / "Signed in" / "Off" / "Adds overnight blood oxygen, a more accurate HRV from deep sleep, and breathing rate by sleep stage. Optional." / keep / keep / keep / keep | G, V8 | sources_screen.dart:505-571 |
| SO08 | P1 | Enhanced notice "Enhanced mode signs in to Google with your account and reads your own data straight from the Google Health API. This build’s sign-in is not verified by Google yet, so Google shows an “unverified app” warning screen before you continue, and an unverified app can be used by at most 100 people in total. The data goes from Google to this phone only: Airlog has no server. Disconnecting signs out and deletes the Google data stored here." | "Enhanced mode signs in to your Google account and reads your own data straight from Google. Google hasn’t verified this version of Airlog yet, so it shows an “unverified app” warning before you continue, and only 100 people in total can use it. Your data goes from Google to this phone only. Airlog has no server. Turning it off signs out and deletes the Google data stored here." (meaning unchanged) | V2 | sources_screen.dart:24-30 |
| SO09 | P2 | Sign-in dialog "Before you sign in" / "Cancel" / "Continue to Google"; "Enhanced mode is on. The first sync can take a minute." / "Sign-in did not complete. Nothing was changed." | keep; keep / "Sign-in didn’t finish. Nothing was changed." | V2 | sources_screen.dart:122-145 |
| SO10 | P2 | "Turn off Enhanced mode?" / "Signs out of Google and deletes the Google Health data stored on this phone. Metrics fall back to Health Connect." / "Cancel" / "Disconnect" | "Turn off Enhanced mode?" / "This signs you out of Google and deletes the Google Health data stored on this phone. Your data will come from Health Connect again." / "Cancel" / "Turn off" | V2; the button repeats the action | sources_screen.dart:154-166 |
| SO11 | P2 | "Bluetooth heart rate" / "Unavailable" / "Connected" / "Live only" / "{detail}. Only while the Live screen is open; never a history source." / "Open live heart rate" | "Bluetooth heart rate" / "Not available" / keep / keep / "{detail}. Used only on the Live heart rate screen. It isn’t saved as history." / "Open Live heart rate" | V2 | sources_screen.dart:228-243 |
| SO12 | P2 | "Other apps" / "On" / "Off" / "{detail}. Off until you turn it on." / "Use context from other apps" | "Other apps (weight)" / keep / keep / keep / "Use data from other apps" | V8: "context" | sources_screen.dart:255-265 |
| SO13 | P2 | Priority table "HRV" / "Deep-sleep RMSSD (Google Health API), else sleep-mean RMSSD (Health Connect)"; "Resting HR, sleep, breathing, skin temp, workouts, steps, HR" / "Health Connect, else Google Health API"; "SpO₂" / "Health Connect (overnight, from any app), else Google Health API"; "Live heart rate" / "Bluetooth only"; header "Priority, first available wins"; "{metric}:"; footnote "Each metric reads one app’s records (see above); a change of app starts a new baseline." | "HRV" / "Deep-sleep HRV from Google, else overnight HRV from Health Connect"; "Resting heart rate, sleep, breathing, skin temperature, workouts, steps, heart rate" / "Health Connect, else Google"; "Blood oxygen" / "Health Connect (overnight, from any app), else Google"; keep; "Where each comes from (first available)"; keep; "Each measurement comes from one app (see above). Switching apps means Airlog learns your usual again." | G, V8 | sources_screen.dart:586-611 |
| SO14 | P1 | Metric names in the picker "Heart rate" / "HRV" / "Resting heart rate" / "Respiratory rate" / "SpO₂" / "Skin temperature" / "VO₂ max" / "Sleep" / "Workouts" / "Steps" / "Weight" / **"Sleeping HR (4 h mean)"** | keep / keep / keep / "Breathing rate" / "Blood oxygen" / keep / keep / keep / keep / keep / keep / **"Sleeping heart rate"** | G | features/settings/widgets/source_picker.dart:20-31 |
| SO15 | P2 | "Switching starts a new baseline. Scores are provisional for about 2 weeks." | "If you switch, Airlog learns your usual again. Scores may shift for about 2 weeks." | G | source_picker.dart:36-37 |
| SO16 | P1 | "{Oura} has newer {hrv} data. Switch? Recovery re-learns for up to 14 nights." (**bug**: `.toLowerCase()` prints "hrv" and "spo₂") / "Switch to {Oura}" / "Not now" | "{Oura} has newer {HRV} data. Switch to it? Airlog takes up to 14 nights to learn your usual again." (keep the metric's casing) / keep / keep | V2, bug | source_picker.dart:82-97 |
| SO17 | P3 | "Automatic" / "The app with the most recent data" / "{9} of the last 14 days"; "Switch app?" / "Cancel" / "Switch"; spoken "{label}, {sub}" | keep | — | source_picker.dart:123-203 |
| SO18 | P2 | "Where each metric comes from" / "One app per metric, never averaged" / "Once Health Connect has data, each metric shows the app it reads here, and you can pick another." | "Where each measurement comes from" / "One app each, never mixed" / "Once Health Connect has data, you’ll see which app each measurement comes from here, and you can pick another." | G | source_picker.dart:225-238 |
| SO19 | P3 | "Found in Health Connect" / "No apps have written data to Health Connect yet. When your tracker’s app syncs, it appears here with what it covers." / "{app} · {device}" / "{HRV} {12}/14" / "No recent data" / "Last 14 days: …" | keep / "No apps have shared data with Health Connect yet. When your tracker’s app syncs, it shows up here." / keep / "{HRV} {12} of 14 days" / keep / keep | V2 | source_picker.dart:291-333 |
| SO20 | P1 | Status detail strings from the repository (the dev hint "--dart-define=…" and others) | see X22 (Phase B changes them at the source) | V8 | data/repositories/health_repository_impl.dart:591-649 |

### 3.15 Privacy and Licences [Revamp; the CoachCopy strings are edited by Phase B in copy.dart]

The privacy policy is legal text, so edits are **wording only** and meaning is kept. If the product owner accepts any change here, bump "Last updated" (`privacy_screen.dart:17`).

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| PR01 | P3 | "Privacy" / "Private by default. Cloud only by choice." / "Last updated {date}" | keep | — | features/privacy/privacy_screen.dart:17,47-58 |
| PR02 | P3 | Bullets "Every score is computed on this phone." / "There is no Airlog server and no account." / "No analytics, no ads, no crash reporting, no tracking." / "Export your readings and scores, or delete local data." / "The coach runs on this phone unless you turn on a cloud engine with your own key." | "Every score is worked out on this phone." / keep / keep / "Save a copy of your readings and scores, or delete them." / "Coach runs on this phone unless you turn on Claude or Gemini with your own key." | G | privacy_screen.dart:68-85 |
| PR03 | P2 | "What Airlog reads from Health Connect" / "Airlog asks Health Connect for read access to the data types below, written there by your tracker’s app. You choose which to grant, and you can revoke any of them at any time in Health Connect settings. A type you do not grant shows as missing; it is never guessed." | keep / "Airlog asks Health Connect to read the kinds of data below, which your tracker’s app puts there. You choose which to allow, and you can turn any of them off at any time in Health Connect’s settings. Anything you don’t allow shows as missing. It’s never guessed." | V2 | privacy_screen.dart:110-116 |
| PR04 | P3 | "Where it is kept" / "Data read from Health Connect, and the scores computed from it, are stored in a database in the app’s private storage on this phone. Nothing is uploaded, unless you turn on a cloud engine for the coach (below). Uninstalling Airlog deletes it." | "Where it’s kept" / "Data read from Health Connect, and the scores worked out from it, are stored in Airlog’s private storage on this phone. Nothing is uploaded unless you turn on Claude or Gemini for Coach (below). Uninstalling Airlog deletes it." | G | privacy_screen.dart:124-129 |
| PR05 | P3 | "Enhanced mode (optional)" (body) / "Live heart rate over Bluetooth" (body) | keep | — | privacy_screen.dart:132-146 |
| PR06 | P2 | CoachCopy privacy section: title "Ask, the coach"; `privacyOnDevice` "Ask answers questions about your data. By default it runs entirely on this phone: a fixed set of questions answered from the scores stored here, with no AI model. Nothing is sent anywhere."; `privacyDelete` "…Delete any chat or memory, or all of them, in Ask. {Settings → Coach} → {Turn off the cloud engine} deletes the key…" | "Coach"; "Coach answers questions about your data. By default it runs entirely on this phone: set questions, answered from the scores stored here, with no AI. Nothing is sent anywhere."; "…Delete any chat or memory, or all of them, in Coach. {Settings → Coach} → {Turn off cloud answers} deletes the key…". `privacyCloud`, `privacyGeneral` and `privacyMemories`: replace "cloud engine" with "Claude or Gemini" and keep everything else. | G | app/copy.dart:386-412 |
| PR07 | P3 | "{retention text} A Gemini key must be on a paid project: free keys may be used for training and human review." | keep | — | privacy_screen.dart:158-161 |
| PR08 | P3 | "Export and delete" / "{Settings → Export readings and scores} writes your raw data and every score as CSV and JSON files to this phone, to keep or share as you choose. {Settings → Delete all data} erases the local store. Revoking Health Connect access stops all further reads." | keep / "{Settings → Export readings and scores} saves your raw data and every score as CSV and JSON files on this phone, to keep or share as you choose. {Settings → Delete all data} deletes everything Airlog stored on this phone. Turning off Health Connect access stops all further reads." | V8 | privacy_screen.dart:167-173 |
| PR09 | P3 | "Not medical advice" / "Airlog is a wellness app, not a medical device. …Talk to a clinician about any health concern." / "Changes" / "If this policy changes, the new version ships inside the app with a new date at the top of this page." | keep (already calm and clear) | V7 | privacy_screen.dart:176-187 |
| LI01 | P3 | Licence page legalese "Computed on your phone. Not medical advice.\nNot affiliated with Google, Fitbit or WHOOP." | "Worked out on your phone. Not medical advice.\nNot affiliated with Google, Fitbit or WHOOP." | V2 | app/routes.dart:55-57 |
| LI02 | P3 | Package names "OpenStrap Edge (design system, charts)" / "Pulse (score formulas)" / "DM Sans (font)" / "Subway Ticker Grid (font)" / "Manrope (fallback font)" / "figma-squircle (tile corner construction)"; licence texts | keep; licence texts are verbatim legal text | — | app/licenses.dart:16-95 |

### 3.16 Diagnostics [Revamp] (a power-user page: keep it technical, but friendly at the top)

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| D01 | P2 | "Diagnostics" / "What actually reaches this phone from your tracker, per data type and app. Run it the morning after your first night." | "Diagnostics" / "See exactly what data reaches this phone from your tracker. Best run the morning after your first night." | V2 | features/diagnostics/diagnostics_screen.dart:32-40 |
| D02 | P1 | "Synthetic data" / "In demo mode the probe describes the demo generator, not a real band. Connect Health Connect and switch to Live for the real probe." | "Sample data" / "This check describes the sample data, not a real tracker. Switch to My data to check your tracker." | G | diagnostics_screen.dart:58-65 |
| D03 | P2 | "Look back" / "{d} days" / spoken "Probe window" / "Reading…" / "Run probe ({7} days)" | keep / keep / "How far back to check" / "Checking…" / "Check the last {7} days" | V8: "probe" | diagnostics_screen.dart:81-99 |
| D04 | P2 | "The probe stopped" / "Try again"; "No dump to share yet. Run the probe first." | "The check stopped" / "Try again"; "Nothing to share yet. Run the check first." | V8 | diagnostics_screen.dart:27,112-115 |
| D05 | P2 | "{Synthetic · }Generated {28 Sep 19:30} · last {7} days · {5} data types"; "Decisions" / "What the numbers settle" | "{Sample data · }Checked {28 Sep, 7:30 pm} · last {7} days · {5} kinds of data"; "What this means" / "How Airlog will use this data" | V2 | diagnostics_screen.dart:133-140 |
| D06 | P2 | Finding lines "HR density: 1 sample / {60 s} → full zone-based strain" / "HRV: {616} RMSSD samples, ~1 / {5.0 min} → nightly HRV = mean inside main sleep" / "{label}: {n} record(s)" / "{label}: none from any app → Recovery re-weights without it" / "{n} future-dated record(s) found (e.g. calorie projections) — dropped at ingest" / "SpO₂: {n} record(s) → nightly SpO₂ from the samples inside sleep" / "Demo data: synthetic tracker — connect Health Connect for the real probe" | "Heart rate every {60 s} → full Strain" / "HRV about every {5 min} → nightly HRV from your main sleep" / "{label}: {n} records" / "{label}: none from any app → Recovery works without it" / "{n} records dated in the future (like calorie forecasts), ignored" / "Blood oxygen: {n} records → nightly value from your sleep" / "Sample data: a pretend tracker. Connect Health Connect to check your real one." (the code lives in data/repositories; Revamp can paste these or Phase B can change them at the source, D12) | V8 | data/repositories/diagnostics.dart:102-197 |
| D07 | P3 | "App per metric" / "The app each metric reads, and the others found" / "{app}{ (automatic)}" / "{n}/14 days" / "Per data type" / "Nothing arrived" / "No records from any app in this window. Check that your tracker’s app syncs to Health Connect and that Airlog has permission." / "Share JSON dump" / "The dump could not be written on this device." | "App for each measurement" / "The app each one comes from, and the others found" / keep / "{n} of 14 days" / "By kind of data" / keep / "Nothing came in from any app in this time. Check that your tracker’s app syncs to Health Connect and that Airlog is allowed to read it." / "Share raw report (JSON)" / "Couldn’t save the report on this phone." | V8 | diagnostics_screen.dart:151-205 |
| D08 | P3 | Per-type card "RECORDS" / "First" / "Last" / "Median spacing" / "Samples per hour" / "Written by" / "In use" / "Synthetic" / "Available" / "Device"; raw type names (HEART_RATE) | keep, except "Synthetic" → "Sample". Raw type names stay (power users). | G | diagnostics_screen.dart:327-387 |
| D09 | P3 | Shared report text "Airlog probe ({7} days)" / "Airlog Phase 0 probe — SYNTHETIC demo data, not a real band." / "Airlog Phase 0 probe: what reaches the phone from the band." / "not granted" / "none from any app" / "none in health connect" / "not available" | "Airlog data check ({7} days)" / "Airlog data check: SAMPLE data, not a real tracker." / "Airlog data check: what reaches the phone from your tracker." / "not allowed" / keep / keep / keep | G | features/diagnostics/diagnostics_view_model.dart:156-197 |

### 3.17 Coach setup [Revamp; the CoachCopy strings are edited by Phase B in copy.dart]

Consent wording is **legal**. Every change below is marked **wording-only**: it keeps what the user agrees to. Those changes do not need `consentVersion` bumped (copy.dart:129-131). D9 asks the product owner to confirm.

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| CS01 | P3 | "Coach setup"; "Could not open setup" / "The coach settings on this phone could not be read." / "Try again" | keep; "Couldn’t open setup" / "Airlog couldn’t open Coach’s settings." / "Try again" | V8 | features/coach/coach_setup_screen.dart:96-111 |
| CS02 | P1 | **"Choose who answers"** / "On-device is the default and sends nothing. A cloud engine is optional, uses your own key, and only starts after you agree below." | **"Who answers your questions?"** / "On this phone is the default. It sends nothing. You can also use Claude or Gemini with your own key, once you agree below." | V2, flagged | coach_setup_screen.dart:132-136 |
| CS03 | P1 | Engine cards: "On-device" + badge "Default" + "In use" / "Nothing leaves your phone. Answers a fixed set of questions about your data."; "Claude" + "Your key · Anthropic" / "Bring your own Anthropic API key. Anthropic doesn't train on API data; deletes it within 30 days."; "Gemini" + "Your key · Google" / "Bring your own Gemini API key. It must be on a billing-enabled (paid) Google Cloud project." | "On this phone" + "Default" + "In use" / "Nothing leaves your phone. Answers set questions about your data."; "Claude" + "Your key · Anthropic" / "Uses your own Anthropic API key. Anthropic doesn’t train on it, and deletes it within 30 days."; "Gemini" + "Your key · Google" / "Uses your own Gemini API key, which must be from a paid Google Cloud project." (wording-only) | G, V2 | copy.dart:147-155,161-165; coach_setup_screen.dart:422-460 |
| CS04 | P2 | "Switch to on-device" / "Remove stored keys" / "On-device is in use. Nothing leaves your phone." | "Switch to On this phone" / "Remove saved keys" / "On this phone is in use. Nothing leaves your phone." | G | coach_setup_screen.dart:157-172 |
| CS05 | P2 | "Your Anthropic API key" / "Your Gemini API key"; key storage "Your key is kept in Android’s keystore (encrypted secure storage) on this phone. It is never written to Airlog’s database or exports, is never shown again, and is sent only to the provider, with each question." | keep; "Your key is locked in this phone’s secure storage. Airlog never saves it anywhere else, never shows it again, and sends it only to {Anthropic}, with each question." (wording-only) | V8: "keystore" | coach_setup_screen.dart:183-184; copy.dart:353-357 |
| CS06 | P2 | "Paid keys only" / "Free Gemini keys may be used to train Google’s models, and people at Google may read what is sent. Use a key from a paid project only. Gemini is for adults (18+) and is not for medical advice." | "Paid keys only" / "With a free Gemini key, Google may use what you send to train its models, and people at Google may read it. Only use a key from a paid project. Gemini is for adults 18 and over, and isn’t for medical advice." (wording-only) | V2 | coach_setup_screen.dart:195; copy.dart:156-159 |
| CS07 | P1 | **"Model"** / **"Approximate cost per question · estimates"**; costs "≈ $0.02–0.05" / "≈ $0.01–0.02" / "< $0.01" / "≈ $0.01" / "< $0.01"; note "Estimates at list prices for a typical question; longer answers cost more. {Anthropic} bills your key directly. Set a spending limit in their console." | **"Model"** / **"Rough cost per question"**; "about 2–5¢" / "about 1–2¢" / "under 1¢" / "about 1¢" / "under 1¢" (decision D10: ¢ or $); "For a typical question. Longer answers cost more. {Anthropic} charges your key directly, so set a spending limit in your {Anthropic} account." | V2, V5, flagged | coach_setup_screen.dart:201-222; copy.dart:174-205 |
| CS08 | P1 | "Mode" / **"Use my data"** / "General only"; bodies "Coach looks up only the numbers a question needs (your scores, sleep, workouts and journal), and every number it quotes is checked against its cited evidence. If your history includes Google Health API data, health records stay on-device; use the on-device coach." / "Coach answers from general sleep and training science, like a textbook. It sends your current question, including any personal details you type, but does not read your stored health data." | "Mode" / **"With my data"** / "General only" (D7); "Coach looks up only the numbers a question needs (scores, sleep, workouts and journal), and Airlog checks every number it quotes. Data from Enhanced mode (Google Health) never leaves your phone. To ask about it, use On this phone." / "Coach answers from general sleep and training know-how, like a textbook. It sends only your question, including anything personal you type. It can’t see your health data." (wording-only) | G, V8 | coach_setup_screen.dart:225-235; copy.dart:297-305 |
| CS09 | P2 | "What can leave your phone" / "Per question, only what it needs" / "Never sent"; sent list "Your question and eligible earlier messages from this mode and provider" / "Computed daily scores (Recovery, Strain, Sleep) for the days asked about" / "Sleep and workout summaries (times, durations, stages, averages)" / "Journal tags, such as “Alcohol” or “Late meal”" / "Memories you confirmed"; general "Your current question only; earlier messages are not sent"; never "Raw heart-rate streams, or any second-by-second reading" / "Google Health API (Enhanced mode) data, or scores built from it" / "Account profile details: Airlog has no account" | "What can leave your phone" / "Only what each question needs" / "Never sent"; "Your question, and earlier messages in this chat with the same mode and provider" / "Your daily scores (Recovery, Strain, Sleep) for the days you ask about" / keep / keep / "Facts you told Coach to remember"; "Only your current question. Earlier messages aren’t sent."; "Raw heart-rate readings, second by second" / "Enhanced mode (Google Health) data, or scores built from it" / "Account details: Airlog has no account" (wording-only) | V8: "eligible", "streams" | coach_setup_screen.dart:249-262; copy.dart:311-330 |
| CS10 | P3 | Recipient "Sent to Anthropic (the Claude API), using your key. Never to Airlog: there is no Airlog server." (and the Gemini version); retention lines | keep (policy text) | — | copy.dart:333-351 |
| CS11 | P2 | "{Claude} is on" / "You agreed on {29 Sep}. Changing the model, or narrowing to General only, needs no new consent." / "Save changes" / "Saved." / "Could not save." | keep / "You agreed on {29 Sep}. Switching model, or switching to General only, doesn’t need a new OK." / keep / keep / "Couldn’t save." | V2 | coach_setup_screen.dart:291-311 |
| CS12 | P2 | "Your consent" / "I’m 18 or older" / "Cloud AI engines are for adults only." / "My key is on a paid (billing-enabled) project" / "Free keys may be used for training and human review." / "I agree — turn on {Claude}" / "Turning on…" / "By agreeing, each question you ask sends the items above to {Anthropic}. You can turn it off any time." / "Still needed: {your API key, the 18+ confirmation, the paid-project confirmation}" | "Your consent" / "I’m 18 or older" / "Claude and Gemini are for adults only." / "My key is from a paid (billing-enabled) project" / "With a free key, Google may train on what you send, and people may read it." / "I agree: turn on {Claude}" / keep / "When you agree, each question you ask sends the items above to {Anthropic}. You can turn it off any time." / "Still needed: {your API key, the 18+ box, the paid-project box}" (wording-only, D9) | V2 | coach_setup_screen.dart:320-356; copy.dart:367-372; coach_setup_view_model.dart:97-100 |
| CS13 | P2 | "Turn off {Claude}" / "Remove stored keys"; confirm "Turn off {Claude}?" / "Cancel" / "Turn off"; snackbars "{Claude} is on. You can turn it off any time." / "Could not save. Nothing was turned on." / "Back to on-device. Your key was deleted." / "Withdrawal could not finish. Check the engine and stored keys, then try again." | keep / "Remove saved keys"; keep; keep / "Couldn’t save. Nothing was turned on." / "Back to On this phone. Your key was deleted." / "Couldn’t turn it off. Try again." | G, V8 | coach_setup_screen.dart:42-81,377-378 |
| CS14 | P3 | "Key saved on this phone" / "Key saved ••••{tail}" / "Replace" / "API key" / hints "sk-ant-…" / "AIza…"; validation "Paste your key." / "A key has no spaces." / "Anthropic keys start with “sk-ant-”." / "This key looks too short." / "Gemini API keys start with “AIza”." | keep | — | coach_setup_screen.dart:516-545; coach_setup_view_model.dart:134-144 |
| CS15 | P2 | Withdraw title "Turn off the cloud engine" / body "Deletes your key from this phone and switches back to on-device. Chats and memories stay on this phone until you delete them." | "Turn off cloud answers" / "Deletes your key from this phone and switches back to On this phone. Your chats and memories stay until you delete them." (the privacy policy prints the title as a path: PR06) | G | copy.dart:106,374-376 |

### 3.18 Coach settings [Revamp; CoachCopy strings are edited by Phase B in copy.dart]

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| CT01 | P2 | "Show coach" / "Off hides Ask and the coach cards everywhere. Your chats and memories stay on this phone." | "Show Coach" / "Turn this off to hide Coach and its notes everywhere. Your chats and memories stay on this phone." | G; describe the on/off state plainly | copy.dart:419-422 |
| CT02 | P1 | Section "Engine"; row "{Claude · Opus 5.5}" / "Your key · {Anthropic} · {≈ $0.02–0.05} per question" / "Nothing leaves your phone" / "Not set up yet: finish in setup"; mode row **"Uses your data"** / "Looks up your scores; every number is checked" / "General only" / "Science and training info only; none of your data" | Section "Who answers"; "{Claude · Opus 5.5}" / "Your {Anthropic} key · {about 2–5¢} a question" / keep / keep; **"With my data"** / "Looks up your scores and checks every number" / "General only" / "General know-how only. It can’t see your data." | G, flagged | features/coach/coach_settings_screen.dart:91-198 |
| CT03 | P2 | "Answer length" / "Brief" / "Detailed" | "Answer length" / "Short" / "Detailed" | V2 | coach_settings_screen.dart:208-215 |
| CT04 | P2 | "Use a backup model when busy" / "If the chosen {Claude} model is busy or out of its own quota, the question goes to a smaller {Claude} model with the same key. Never to another company. When none can answer, Coach answers on this phone." | keep / "If your {Claude} model is busy or hits its limit, a smaller {Claude} model answers with the same key. Never another company. If none can answer, Coach answers on this phone." | V2 | copy.dart:253-260 |
| CT05 | P1 | "Today’s usage" / "{3} of {50} model requests · {12k} of {200k} tokens" | "Today’s use" / "{3} of {50} requests · {12k} of {200k} tokens". Add ⓘ: "Tokens are how AI companies measure text. One question uses a few thousand." | V8 | copy.dart:478; coach_settings_screen.dart:24-27 |
| CT06 | P2 | "Coach messages" / "Short notes on the detail screens, written on this phone with fixed wording. Nothing is sent." / "No coach cards. Screens show only your numbers." | "Coach notes" / keep / "No notes. Screens show only your numbers." | V2 | copy.dart:469-476 |
| CT07 | P3 | "On this phone" / "What Coach knows" / "Memory off" / "Nothing yet · only facts you confirm" / "{n} fact(s) you confirmed" / "Conversations" / "Kept on this phone; delete any or all" | keep / keep / keep / keep / keep / keep / "Kept on this phone. Delete any or all." | V2 | coach_settings_screen.dart:343-364 |
| CT08 | P3 | "Consent" / withdraw row (CS15) / "How the coach handles your data" | keep / — / "How Coach handles your data" | G | coach_settings_screen.dart:371-406 |
| CT09 | P3 | "Turn off {Claude}?" / "Cancel" / "Turn off"; "Back to on-device. Your key was deleted." / "Could not complete withdrawal. Try again." / "Could not save. Try again." / "Coach settings could not be read" / "Showing the defaults. Nothing was changed." | keep; "Back to On this phone. Your key was deleted." / "Couldn’t turn it off. Try again." / "Couldn’t save. Try again." / "Couldn’t read Coach settings" / keep | V2 | coach_settings_screen.dart:51-138,268 |
| CT10 | P3 | "Cloud is off, but a stored key could not be deleted. Try removing the key again in coach setup." | "{Claude} is off, but Airlog couldn’t delete your saved key. Remove it again in Coach setup." | V2 | features/coach/coach_providers.dart:103-104 |

### 3.19 What Coach knows (memory) [Revamp; CoachCopy strings are edited by Phase B in copy.dart]

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| CM01 | P2 | Top note "Facts you confirmed are context, not measurements. Health numbers come fresh from your data. Review old facts and edit changes here. Memories stay on this phone, and are sent as context only while a cloud engine is on." | "These are facts you told Coach, not measurements. Your health numbers always come fresh from your data. Facts stay on this phone, and are only sent with your questions while Claude or Gemini is on." (wording-only) | V8: "context" | copy.dart:379-383 |
| CM02 | P3 | "What Coach knows" / "Use memories" / "Coach may use these facts and suggest new ones." / "Off: Coach never reads these or suggests new ones." | keep | — | features/coach/coach_memory_screen.dart:108-121,196 |
| CM03 | P3 | "Nothing yet" / "When Coach offers to remember something, it appears here only after you tap Remember. You can add a fact yourself too." / "Add a fact" / "Delete all memories" | keep | — | coach_memory_screen.dart:131-182 |
| CM04 | P3 | "Delete every memory?" / "Coach forgets everything you confirmed. Your chats stay. It cannot be undone." / "Cancel" / "Delete all" / "All memories deleted." / "Could not delete." / "Forgotten." / "Could not save. Try again." | keep / "Coach forgets every fact you confirmed. Your chats stay. This can’t be undone." / keep / "Delete all memories" / keep / "Couldn’t delete." / keep / "Couldn’t save. Try again." | V2; the button names the consequence | coach_memory_screen.dart:33-64,158 |
| CM05 | P3 | "Could not load memories" / "The memories stored on this phone could not be read." / "Try again" | "Couldn’t load memories" / "Airlog couldn’t open your saved facts." / keep | V8 | coach_memory_screen.dart:73-75 |
| CM06 | P3 | Row meta "Ended {day} · no longer used" / "Confirmed {day}" / spoken "{text}. {note}. Edit" / "Forget “{text}”" | keep | — | coach_memory_screen.dart:229-268 |
| CM07 | P3 | Edit sheet "Add a fact" / "Edit fact" / "Something about you, not a number: a goal, an event, a preference." / "Fact" / "e.g. Training for a half marathon" / "Category" / "Until (optional)" / "No end: kept until you delete it" / "Used until {day}" / "Pick a day" / "Change" / "Clear" / "Save"; categories incl. "About you" / "Health history" | keep | — | coach_memory_screen.dart:344-431; domain/coach/coach_contracts.dart:492-496 |

### 3.20 How scores work (Methodology) [Revamp]

Methodology is the reference page, so the **formula blocks, constant tables and citations stay word for word**. The fix: plain words in the lede and section names, and a one-line **"In short"** paragraph added at the top of each section. `{x}` placeholders are the engine constants the code already interpolates.

| ID | P | Current | Proposed (paste-ready) | Why | Where |
|---|---|---|---|---|---|
| M01 | P3 | "How scores work" / "Every number, explained" / "Contents" | keep | — | features/methodology/methodology_screen.dart:168-205 |
| M02 | P2 | Lede "Each score comes from a published method and your own baseline, computed on this phone. This page lists all of it: formulas, constants, inputs and sources. The constants are read from the engine itself, so the page and the maths cannot disagree." | "Every score, with its formula. Each one uses a published method and your own usual, worked out on this phone. The numbers on this page come straight from the app’s code, so they always match what you see. For the short version, tap ⓘ on any screen." | V2, G | methodology_screen.dart:182-186 |
| M03 | P2 | Chips "Algorithm v{3}" / "Not medical advice" / **"Not WHOOP’s formula"** | "Formula version {3}" / "Not medical advice" / **"Our own formula"** | G; brand (D6) | methodology_screen.dart:194-196 |
| M04 | P2 | Section names "Honesty rules" / "Recovery" / "Strain" / "Sleep" / "Health Monitor" / "HRV readiness" / "Load and trends" / "Live sessions" / "Sources and baselines" / "Other apps’ scores" / "Citations" / "Credits" | "Honesty rules" / "Recovery" / "Strain" / "Sleep" / "Overnight signals" / "HRV this week" / "Training load and trends" / "Live heart rate" / "Data sources and your usual" / "Other apps’ scores" / "Citations" / "Credits" | G | methodology_screen.dart:43-54 |
| M05 | P2 | Honesty bullets: "No guesses." "A missing input shows a card that says what is missing, why, and how to fix it. Airlog never shows a guessed number." · "Calibration is visible." "Scores are “calibrating” for the first {5} nights and “provisional” until {14}; the baseline banner says which." · "Arrows are earned." "A trend arrow appears only for a statistically significant change. No arrow means no reliable change." · "One source per metric." "Each metric comes from one source at a time, never an average. A new source starts a new baseline." · "Versioned." "Every stored result carries the algorithm version, so history can be recomputed when a constant changes." | "No guesses." "When something is missing, a card says what, why, and how to fix it. Airlog never shows a guessed number." · "Learning is shown." "Scores say “Learning” for the first {5} nights and “early estimate” until night {14}. The banner on Today says which." · "Arrows are earned." "A trend arrow shows only for a real change, tested with statistics. No arrow means no clear change." · "One app per measurement." "Each measurement comes from one app at a time, never an average. A new app means Airlog learns your usual again." · "Versioned." "Every saved score records its formula version, so your history can be worked out again if the formula changes." | G, V2 | methodology_screen.dart:224-251 |
| M06 | P2 | Recovery para "How ready you are today, from last night against your own baseline: the {30} most recent nights measured the same way. Each input becomes a 0–1 sub-score; the weighted sum is the score. Missing inputs are left out and the other weights re-normalised. No score at all without HRV or resting heart rate." | "In short: how ready you are today, from last night compared with your usual. Your usual is your {30} most recent nights, measured the same way. Each signal gets a score from 0 to 1, and the weighted total is your Recovery. If a signal is missing, the others count for more. There’s no score at all without HRV or resting heart rate." Table header "Input" → "Signal"; row "Respiratory rate" → "Breathing rate"; "only a raised rate costs" → "only a raised rate costs points". Formula unchanged. | G | methodology_screen.dart:256-292 |
| M07 | P2 | Recovery penalties para "Penalties after weighting: overnight SpO₂ minimum below {90} % costs {n} points; skin temperature more than {z} SD above your baseline (minimum SD {s} °C) costs {n}. Zones: green from {67}, yellow {34}–{66}, red below {34}. HRV uses a minimum SD of {a} on the log scale, resting HR {b} bpm and respiratory rate {c} /min, so a very steady baseline cannot make one night look dramatic. Respiratory rate scores {m} until it is {z} SD above your mean, then loses {k} per SD (never below {q}). An input without a baseline yet scores a neutral {0.5}." | "Penalties after weighting: overnight blood oxygen (SpO₂) below {90}% costs {n} points; skin temperature more than {z} SD above your usual (minimum SD {s} °C) costs {n}. Levels: Good (green) from {67}, Fair (yellow) {34}–{66}, Low (red) below {34}. HRV uses a minimum SD of {a} on the log scale, resting heart rate {b} bpm and breathing rate {c} /min, so a very steady usual can’t make one night look dramatic. Breathing rate scores {m} until it’s {z} SD above your usual, then loses {k} per SD (never below {q}). A signal Airlog hasn’t learned yet scores a neutral {0.5}." | G | methodology_screen.dart:294-310 |
| M08 | P2 | Strain para "How hard your heart worked, on a 0–21 scale. Each minute of heart rate is placed by its share of your heart-rate reserve (Karvonen); harder minutes weigh much more." | "In short: how hard your heart worked today, from 0 to 21. Each minute of heart rate is placed by how close it was to your max, counting up from your resting heart rate (Karvonen). Harder minutes count for much more." Table header "Load zone" → "Scoring band" (so it doesn't clash with the chart's zones 1–5). Formulas unchanged. | G | methodology_screen.dart:316-340 |
| M09 | P2 | "The zones on the charts are the familiar display bands: {50 % / 60 % / 70 % / 80 % / 90 %} of reserve for zones 1–5." | "The five zones on the charts are simpler display bands. They start at {50% / 60% / 70% / 80% / 90%} of your heart-rate reserve (zones 1–5)." | V2 | methodology_screen.dart:343-345 |
| M10 | P2 | "Sparse heart rate: if fewer than {60 %} of waking minutes have a reading (or fewer than {300} samples), zones would under-count, so the day gets no strain score: the screen lists what was measured instead (workouts and steps). A single workout without heart rate inside it uses its own average HR and is labelled “Estimated”." | "Patchy heart rate: if fewer than {60%} of waking minutes have a reading (or fewer than {300} readings), zones would undercount, so the day gets no Strain score. The screen lists what was measured instead (workouts and steps). A single workout with no heart rate inside it uses its own average heart rate and is labelled “Estimate”." | V2 | methodology_screen.dart:348-354 |
| M11 | P1 | "Target: {0.2} × the morning’s recovery, kept between {3} and {18.5}. Cross-check: Banister TRIMP over the same minutes, weighted {a}·e^({b}x) (male) or {c}·e^({d}x) (female), the mean of both when not specified." | "Effort goal: {0.2} × the morning’s Recovery, kept between {3} and {18.5}. Today shows it as a range of ± {1.5}. Second opinion: Banister TRIMP over the same minutes, weighted {a}·e^({b}x) (male) or {c}·e^({d}x) (female), the mean of both when sex isn’t set. It doesn’t change any score." | G, V6 (it says what sex is for) | methodology_screen.dart:357-363 |
| M12 | P2 | Sleep formula "target = {7h 36m} + {33 %} of debt + up to {n} min for strain above {x}" / "boost = …"; para "The target is kept between {a} minutes under and {b} minutes over the baseline. Performance is sleep ÷ target (naps count). Debt carries forward night to night, gains at most {180} min a night and is capped at {5h}. Consistency compares bed and wake times over the last {4} nights: 100 % is the same times, 0 % an average shift of {90} minutes. Tonight’s bedtime is your average wake time over the last {14} days minus the projected target." | Formula: "goal = {7h 36m} + {33%} of missed sleep + up to {n} min for Strain above {x}" / "boost = …" (unchanged). Para: "In short: your sleep goal, missed sleep, and how regular your sleep is. The goal stays between {a} minutes under and {b} minutes over your usual need. Your sleep % is sleep ÷ goal (naps count). Missed sleep carries over from night to night, grows by at most {180} min a night, and never goes above {5h}. Consistency compares bed and wake times over the last {4} nights: 100% means the same times, 0% means {90} minutes off on average. Tonight’s bedtime is your usual wake-up time over the last {14} days, minus the sleep goal." | G | methodology_screen.dart:368-391 |
| M13 | P2 | Health Monitor paras "Each overnight signal is compared with your usual range: baseline ± {1.65} SD (about 90 % of your nights), never narrower than a floor, so a very steady metric is not over-sensitive." / "Each range is built from the last {30} nights measured the same way and appears after {5} of them. SpO₂ has only a floor, never below {90} %." / "An alert needs two metrics out of range on the same day, or one for two days running. Out of range is shown in amber, never alarm red: it is a prompt to look, not a diagnosis."; table "Metric" / "Floor ±" | "In short: five overnight readings, each checked against your usual range. The range is your usual ± {1.65} SD (about 9 in 10 of your nights), and never narrower than a set floor, so a very steady signal isn’t too touchy." / "Each range comes from your last {30} nights measured the same way, and shows up after {5} of them. Blood oxygen (SpO₂) has only a floor, never below {90}%." / "A card appears when two signals are out of range on the same day, or one is out for two days running. Out of range shows in amber, never alarm red: it’s a prompt to look, not a diagnosis."; table "Signal" / "Floor ±" | G, V7 | methodology_screen.dart:395-420 |
| M14 | P2 | HRV readiness para "Following Plews et al.: the {4}+ nights of the last week are averaged on the log scale and compared with your smallest worthwhile change, baseline ± {0.5} SD of ln RMSSD (needs {7} baseline nights). The weekly coefficient of variation is shown alongside; a rising one flags instability even when the mean looks normal." | "In short: your 7-night HRV average, compared with your usual. Following Plews et al., the {4}+ nights of the last week are averaged on the log scale and compared with your smallest worthwhile change: your usual ± {0.5} SD of ln RMSSD (after {7} nights). The night-to-night swing (coefficient of variation) shows alongside. If it keeps rising, your body may be less settled even when the average looks fine." | V2 | methodology_screen.dart:423-433 |
| M15 | P1 | Load para "Training load is the acute:chronic ratio: mean daily strain over {7} days ÷ over {28} days, needing {21} days of strain. Below {0.8} detraining, {0.8}–{1.3} steady, {1.3}–{1.5} elevated, above {1.5} high (Gabbett 2016). Days without data are skipped, not counted as rest." / "Trends use the Mann–Kendall test (…) with Sen’s slope for the size." | "In short: your last 7 days compared with your last 4 weeks. Training load is the acute:chronic ratio: average daily Strain over {7} days ÷ over {28} days, after {21} days of Strain. Below {0.8}: less than usual. {0.8}–{1.3}: about usual. {1.3}–{1.5}: more than usual. Above {1.5}: much more than usual (Gabbett 2016). Days without data are skipped, not counted as rest." / "A trend arrow shows only for a real change. Trends use the Mann–Kendall test (…) with Sen’s slope for the size." (the rest unchanged) | G: the words must match the Trends tile | methodology_screen.dart:435-454 |
| M16 | P2 | Live paras "Heart-rate recovery after a workout, from 1-second Bluetooth heart rate (Cole et al. 1999). The live screen keeps recording for 60 s after Stop to measure it." / "HRV check: beat-to-beat (RR) intervals are cleaned first ({a}–{b} ms, no jump over {20 %} from the previous good beat). RMSSD (Task Force 1996) needs {n} clean intervals. Only available when your tracker sends RR intervals." | "In short: how fast your heart rate drops after a workout, and the HRV check. Heart-rate recovery comes from second-by-second Bluetooth heart rate (Cole et al. 1999). The live screen keeps recording for 60 s after you tap Stop to measure it." / "HRV check: beat-to-beat (RR) intervals are cleaned first ({a}–{b} ms, no jump over {20%} from the previous good beat). RMSSD (Task Force 1996) needs {n} clean intervals. It only works when your tracker sends RR intervals." Formula unchanged. | V2 | methodology_screen.dart:457-474 |
| M17 | P1 | Sources table "Metric" / "First available wins"; row "Resting HR, sleep, breathing, skin temp, workouts, steps, HR" → **"Health Connect › Google Health API › Takeout"** | "Measurement" / "Where it comes from (first available)"; "Health Connect › Google Health API" (**drop Takeout**: it isn't a v1 source and PRODUCT_PLAN §7 cut the row; the Sources screen already says "else Google Health API") | V6 | methodology_screen.dart:477-494 |
| M18 | P2 | "Within Health Connect each metric comes from one app at a time (your pick in Settings → Sources, or the automatic one), never a mix. Each value carries its source, definition and app; a baseline is built only from nights measured the same way by the same app as today, so a change of app, or from all-night to deep-sleep HRV, starts a new baseline instead of mixing the two. Demo and live data are stored apart." / "Calibration: fewer than {5} baseline nights = calibrating; {5}–{13} = provisional; {14} or more = established. A baseline needs at least {3} nights before it exists at all." | "Within Health Connect, each measurement comes from one app at a time (your pick in Settings → Data sources, or the automatic one), never a mix. Your usual is built only from nights measured the same way by the same app as today. So if you switch apps, or go from all-night to deep-sleep HRV, Airlog learns your usual again instead of mixing the two. Sample data and your data are stored apart." / "Learning: fewer than {5} nights = “Learning”; {5}–{13} = “early estimate”; {14} or more = settled. Airlog needs at least {3} nights before it has a usual at all." | G | methodology_screen.dart:496-513 |
| M19 | P3 | Other apps’ scores paras (WHOOP/Oura) | "WHOOP’s Recovery and Oura’s Readiness are those apps’ own scores. Airlog doesn’t show or copy them. It works out its own Recovery from the measurements the app shares with Health Connect (HRV, resting heart rate, sleep, breathing), with the same published formula for every device and your usual on this phone." / "So the two numbers differ. Those apps’ formulas, weights and baselines are their own and unpublished, and they may use measurements they don’t share with Health Connect. Neither number is wrong: compare Airlog’s Recovery with itself over time, not with the other app’s score." (the names stay: D6) | G | methodology_screen.dart:516-531 |
| M20 | P3 | Citations; Credits "Airlog stands on two open-source projects. Ported files name their origin in a header." and the credit bodies; trademark line; spoken "{title}. {body}. Opens the project page." | keep word for word (reference and legal) | — | methodology_screen.dart:534-633 |

---

## 4. Generated-text templates

This is the heart of the change. All of this text is **dynamic**. For each template this section gives:
- the engine fields that drive it;
- the full variant matrix;
- the edge values;
- three or more filled examples, including an awkward one.

### 4.0 Rules every TodayPlan template must pass (from the tests, not taste)

| Constraint | Source | Effect on the copy |
|---|---|---|
| Every number in `planTexts(p)` must be in `allowedNumbers`: headline, summary, chips, action titles and whys, **action chips**, `sources`, `relearningSource`. | test/domain/fixtures/plan_numbers.dart:15-106; `TodayPlan.citedResultFields` (today_plan.dart:157-180) | Fewer numbers is always safe. **Never add** a number that isn't a cited field, such as "out of 21", "2 weeks", "in 5 nights" or a computed "11 more nights". The templates below add **no** new numbers. |
| No `infection\|illness\|sick\|overtrain\|streak\|in a row\|fail\|should have\|!` in any plan text | today_planner_test.dart:703-728 | No "!", no "nights in a row", no "failed". |
| At most **2** summary chips (`maxEvidence`), and the Recovery chip takes slot 1 | today_planner.dart:173,346-365 | Only one of HRV or resting HR fits on the card. Resting HR stays visible on Today through the Recovery tile ("Resting HR vs usual −3 bpm"), so `maxEvidence` can stay at 2. |
| At most **3** actions, in the order effort → sleep → checkIn → recover | today_planner.dart:172,369-512 | See D11 (recover repeats effort on red days). |
| Clocks go through `PlanFormat.clock`, and the fixture allows only those tokens | plan_numbers.dart:74-80 | 12-hour "11:35 pm" produces "11", so the formatter **and** the fixture must take the same `use24h` flag (D2). |
| The plan tile limits text scaling to 1.3× | plan_tile.dart:69 | Longer words are fine. The card grows downward. |

### 4.1 TodayPlan (`today_planner.dart`, `today_plan.dart`, `plan_tile.dart`)

#### 4.1.1 Formatters (`PlanFormat`, today_planner.dart:69-146)

| Function | Current | Proposed | Awkward values |
|---|---|---|---|
| `hm(min)` | "7 h 36 m", "8 h", "45 m", "0 m" | "7h 36m", "8h", "45 min", "0 min" (the same as `CoachFormat.duration`) | 59.6 → "1h" (rounded); 0 → "0 min"; 300 → "5h" |
| `clock(min)` | "23:35" always | `use24h` true: "23:35". False: "11:35 pm". 0 → "12:00 am", 720 → "12:00 pm", 1460 (after midnight) → "12:20 am" | noon and midnight |
| `when(t, now)` | "07:12" / "yesterday 23:10" / "Sep 26 23:10" | 24h: unchanged. 12h: "7:12 am" / "yesterday, 11:10 pm" / "Sep 26, 11:10 pm" | a date 1 year back still reads "Sep 26" (no year: fine, since data is never that stale in practice) |
| `ms`, `bpm`, `pct`, `strain`, `vital` | "52 ms", "54 bpm", "72%", "7.4", "16.8 /min" | unchanged, except `vital` for breathing: "16.8 breaths/min" (follows X19) | — |

#### 4.1.2 Headline: `headlineFor(state, phase, cause)`

The signature changes: `today_plan.dart` is a contract file, so the change is additive, and the old `headlineFor(state)` stays as the today/default path. Drivers: `DayState` (today_planner.dart:237-252), `PlanPhase` (262-264) and the noData cause (`behind`, `beforeWake`, `rec == null`).

| State | Today phase | Tonight phase (18:00–05:00, bedtime known) | Current |
|---|---|---|---|
| ready | **"Your body is ready"** | **"Time to wind down"** | "Ready to push" |
| steady | **"Good for a normal day"** | **"Time to wind down"** | "A normal day" |
| easy | **"Take it easy today"** | **"Rest up tonight"** | "Take it easy" |
| rest | **"Make today a rest day"** | **"Rest up tonight"** | "Make it a rest day" |
| calibrating | **"Still getting to know you"** | same | "Still learning your normal" |
| noData, behind or beforeWake | **"Waiting for your data"** | same | "Waiting for today's data" |
| noData, no Recovery (`rec == null`) | **"No Recovery score today"** | same | "Waiting for today's data". **Misleading:** if the app never shares HRV or resting HR, waiting won't help. |
| under 18 (`age_unsupported`) | "Scores are for adults" (keep) | same | — |

#### 4.1.3 Summary (the "why"): words only

The fields that drive it are listed per row. All numbers move to the chips (4.1.5).

| # | When (first match wins, the same order as today_planner.dart:267-321) | Proposed template | Current |
|---|---|---|---|
| S1 | `behind`, whether or not `lastData` exists | "Nothing has come in for today yet." (the time goes in chip E1) | "Nothing has arrived for today yet." / "Nothing for today has arrived yet; the newest data is from {when}." |
| S2 | `beforeWake` | "Your scores show up after you wake up and your tracker syncs." | "Today's scores arrive after you wake and your tracker syncs." |
| S3 | `rec == null` and the app shares neither HRV nor RHR (`notShared[hrv] == notShared[rhr]`) | "{App} doesn’t share the heart data Recovery needs, so there’s no Recovery score. Sleep and Strain still work." | "{App} doesn't share HRV or resting heart rate with Health Connect, so there is no Recovery score; sleep and strain still work." |
| S4 | `rec == null` otherwise | "Last night’s heart data didn’t come in, so there’s no Recovery score today." | "No HRV or resting heart rate arrived for last night, so there is no Recovery score today." |
| S5 | `recovery.confidence == low` | "Today’s score uses only part of your data, so there’s no workout advice today." | "Recovery {45%} is based on limited inputs. There is not enough information to recommend an effort target." |
| S6 | tonight phase, split on `bedtime.debtMinutes` | < 15: "You’re not short on sleep, so a normal night will do." · 15–59: "You’re a bit short on sleep from recent nights." · 60–179: "You’re short on sleep from recent nights." · ≥ 180 (cap 300): "You’re well short on sleep from recent nights." | "Tonight's sleep target is {7 h 53 m}, with {58 m} of sleep debt carried." |
| S7 | `vitalsDriven` (a concerning vital, and Recovery isn't the cause) | Split the concerning vitals into **H** (above) and **L** (below). Plain names: HRV, resting heart rate, breathing rate, blood oxygen, skin temperature. Only H: "Your {H} {is/are} higher than usual." Only L: "Your {L} {is/are} lower than usual." Both: "Your {L} {is/are} lower than usual, and your {H} {is/are} higher." (join: "a", "a and b", "a, b and c") | "{Resting HR higher (61 vs usual 54 bpm)}; Recovery {60%}." |
| S8 | calibrating, **re-learning** a new source (`sourceChange.to`) | "You switched to {App}, so Airlog is learning your usual again. Today’s score may change." | "Re-learning your normal with {App}: {2} of {14} nights so far, so Recovery {20%} is provisional." |
| S9 | calibrating, `haveNights == 0` | "Airlog is just getting to know you, so today’s score may change." | "Airlog is just starting to learn your normal, so Recovery {p} is provisional." |
| S10 | calibrating, otherwise | "Airlog is still learning what’s normal for you, so today’s score may change." | "{3} of {14} baseline nights so far, so Recovery {20%} is provisional." |
| S11 | ready, steady, easy or rest (not vitals-driven) | **Body sentence** (4.1.4) + optional **sleep clause** + optional **very-low lead** | "Recovery {78%}: HRV is {13%} above your usual and resting HR below your usual ({53} vs {56} bpm)." |

#### 4.1.4 The body sentence (S11)

Drivers: the `hrv` and `rhr` components' `value` and `baseline.mean` (today_planner.dart:658-720). Thresholds stay as they are: HRV is "usual" within ±5% (`hrvUsualPct`, :163) and resting HR within ±1.5 bpm (`rhrUsualBpm`, :164).
- **h**: HRV compared with usual (better = up ≥ 5%, worse = down ≥ 5%).
- **r**: resting HR compared with usual (better = down ≥ 1.5, worse = up ≥ 1.5).
- **none**: no value, or no usual to compare against.

| h ↓ / r → | better | usual | worse | none |
|---|---|---|---|---|
| **better** | "Your heart is well rested today." | "Your heart is well rested today." | "Your heart shows mixed signs today." | "Your heart is well rested today." |
| **usual** | "Your heart is well rested today." | "Your heart looks about the same as usual." | "Your heart is less rested than usual." | "Your heart looks about the same as usual." |
| **worse** | "Your heart shows mixed signs today." | "Your heart is less rested than usual." | "Your heart is less rested than usual." | "Your heart is less rested than usual." |
| **none** | "Your heart is well rested today." | "Your heart looks about the same as usual." | "Your heart is less rested than usual." | Zone sentence: Good "You’ve recovered well." · Fair "You’ve partly recovered." · Low "You haven’t fully recovered yet." |

- **Sleep clause** (`sleep.performance < 70`, :166): replace the final "." with ", but you slept well under your sleep goal." after "well rested" or "about the same". Use ", and you slept well under your sleep goal." after "less rested", "mixed" or a zone sentence.
- **Very-low lead** (rest **and** `recoveryDriven`, :317-319): add "Your body hasn’t recovered yet. " before the body sentence.
- **Without HRV**: h = none, so the sentence comes from resting HR alone. The chip keeps "without HRV" (principle 6).
- **Stale** (green but data older than 12h → steady): same sentence; the top line adds "Your data may be out of date".

Examples:

| Case | Inputs | Output |
|---|---|---|
| Good morning | HRV 53 vs 47 (+13%), RHR 53 vs 56, sleep 89% | "Your heart is well rested today." |
| Normal but short sleep | HRV 44 vs 46 (−4%), RHR 55 vs 55, sleep 64% | "Your heart looks about the same as usual, but you slept well under your sleep goal." |
| Mixed | HRV +9%, RHR 58 vs 55 | "Your heart shows mixed signs today." |
| **Awkward**: rest day, recovery 12 | HRV −22%, RHR +6, sleep 41% | "Your body hasn’t recovered yet. Your heart is less rested than usual, and you slept well under your sleep goal." (23 words across two sentences, still grade ~5) |
| No comparisons yet | calibration established but both baselines missing, Fair | "You’ve partly recovered." |

#### 4.1.5 Chips: the numbers live here

**Summary chips** (max 2, today_planner.dart:323-366):

| # | When | Chip (label · value · comparison) | Current |
|---|---|---|---|
| E1 | behind | "Last update" · "{yesterday, 11:10 pm}" | "Last data" · "{yesterday 23:10}" |
| E2 | `rec == null`, sleep recorded | "Sleep" · "{6h 40m}" · "goal {7h 36m}" | "Sleep" · "6 h 40 m" · "target 7 h 36 m" |
| E3 | tonight: slot 1 | "Sleep goal" · "{7h 53m}" | "Sleep target" · "7 h 53 m" |
| E4 | tonight: slot 2 | debt ≥ 15: "Missed sleep" · "{58m}" (cited `bedtime.debtMinutes`); else the Recovery chip | Recovery chip always |
| E5 | today: slot 1 | "Recovery" · "{78%}" · withoutHrv: "without HRV", provisional: "early estimate", else none | "…· provisional" |
| E6 | today: slot 2, vitals-driven | "{Resting HR}" · "{61 bpm}" · "usual {54 bpm}" | same |
| E7 | today: slot 2, calibrating | "Learning" · "{3} of {14} nights" (re-learning: `sourceChange.nights`). **Hide it when `haveNights == 0`**, because "0 of 14 nights" reads badly. | "Baseline" · "3 of 14 nights" |
| E8 | today: slot 2, otherwise | "HRV" · "{53 ms}" · "{13}% above usual" / "{8}% below usual" / "about usual"; else "Resting HR" · "{53 bpm}" · "usual {56 bpm}" | "HRV" · "53 ms" · "13% above usual" / "normal for you" |

**Action chips (new, decision D5).** `PlanAction.evidence` already exists (today_plan.dart:93), but PlanTile doesn't render it (plan_tile.dart:161-214). Phase B renders them as small chips under the why:

| Action | Chip | Fields (all cited) |
|---|---|---|
| effort (not vitals-driven) | "Effort goal" · "{14–17}" · (progress P1+: "{9.2} so far") | `StrainEngine.targetRange(targetStrain)`, `strain.strain` |
| sleep (today phase) | "Sleep goal" · "{7h 53m}" · (debt ≥ 15: "{58m} missed") | `bedtime.projectedNeedMinutes`, `bedtime.debtMinutes` |
| checkIn | one vital chip per concerning vital **not already** in the summary chips | `health.metrics` |

#### 4.1.6 Actions

**Effort action.** Conditions unchanged (today_planner.dart:373-379): today phase, current, not stale, not calibrating, not limited, and a target exists.

The **effort level** is keyed on `DayState`, **not** on the strain range. At every zone edge both sides give the same range (recovery 66 and 67 both give 12–15; 33 and 34 both give 5–8; 16 and 17 both give 2–5), so a range-to-word map would contradict the headline. The engine math, with cites:
- target = clamp(0.2 × Recovery, 3, 18.5) (`strain.dart:117-119,130-131`)
- range = round(target ± 1.5) (`strain.dart:172-179`)
- green ≥ 67 and yellow ≥ 34 (`recovery.dart:83`)
- rest below 17 (`today_planner.dart:154`)

| Level | When | Recovery → target → range (examples) | Title | Why (P0: no progress to report) |
|---|---|---|---|---|
| rest | state rest | 1–16 → 3.0–3.2 → 2–5 | "Rest or move gently today" | "A short walk or some gentle stretching is plenty." |
| easy | state easy | 17–33 → 3.4–6.6 → 2–5 … 5–8 | "Keep any workout easy today" | "Try a walk, an easy bike ride or yoga." |
| moderate | state steady | 34–66 → 6.8–13.2 → 5–8 … 12–15 | "A normal workout is fine today" | "Try a steady run or bike ride, or your usual gym session." |
| hard | state ready and target < 17.0 | 67–84 → 13.4–16.8 → 12–15 … 15–18 | "A hard workout is fine today" | "Try a long run, intervals or a tough gym session." |
| very hard | state ready and target ≥ 17.0 (Recovery ≥ 85) | 85–99 → 17.0–18.5 → 16–19 … 17–20 | "A very hard workout is fine today" | "Try a race, hard intervals or your toughest session." (D4: is "very hard" ever OK to suggest?) |

Vitals-driven easy or rest days use the same state words (easy or rest). They get **no** goal chip and no progress, because the goal range comes from a green Recovery and would contradict "keep it easy".

**Progress** (moderate, hard and very hard only; rest and easy days never nudge you to do more). Drivers:
- `so` = `strain.strain` when `method != none` and above 0 (:382-387)
- `lo`, `hi` = the target range
- `hour` = `now.toLocal().hour`
- `record.workouts`

| Band | When | Title | Why |
|---|---|---|---|
| P0 | `so == null` or `so < 0.25·lo`, before 12:00 | level title | level example (no progress talk in the morning: the product owner flagged "0.6 so far") |
| P0-pm | same, from 12:00, no workouts recorded | level title | "No workout recorded yet today. {level example}" |
| P0-pm | same, from 12:00, a workout recorded | level title | "Not much effort so far today. {level example}" (a workout doesn't always mean effort, so never say "you haven't trained") |
| P1 | 0.25·lo ≤ so < 0.4·lo | level title | "You’ve made a start." |
| P2 | 0.4·lo ≤ so < 0.7·lo | level title | "You’re about halfway there." |
| P3 | 0.7·lo ≤ so < lo | level title | "You’re nearly there." |
| P4 | lo ≤ so < hi | **"You’ve hit today’s goal"** | "Anything more is extra." |
| P5 | so ≥ hi (every level, even rest and easy) | **"You’ve done enough for today"** | "You’re past today’s goal. Take it easy from here." |

Three filled examples:
1. Ready, target 15.6 (range 14–17), 07:40, so 0.6. P0 gives "A hard workout is fine today" / "Try a long run, intervals or a tough gym session." Chip: "Effort goal 14–17".
2. Steady, target 10.4 (range 9–12), 12:30, so 3.1 (0.34·lo). P1 gives "A normal workout is fine today" / "You’ve made a start." Chip: "Effort goal 9–12 · 3.1 so far".
3. **Awkward:** rest (Recovery 12, target 3, range 2–5), 5:30 pm, so 5.4 (≥ hi 5). P5 gives "You’ve done enough for today" / "You’re past today’s goal. Take it easy from here." That is right for a rest day. Chip: "Effort goal 2–5 · 5.4 so far". From 6:00 pm the phase is tonight, and the effort action disappears.
4. Very hard, Recovery 93 (range 17–20), 16:10, so 17.4. P4 gives "You’ve hit today’s goal" / "Anything more is extra."

**Sleep action** (today_planner.dart:431-474). Drivers:
- `bedtime.recommendedBedtimeMinutes` (bed)
- `habitualWakeMinutes` (wake)
- `projectedNeedMinutes` (need)
- `debtMinutes`
- `now` (to tell whether bedtime has passed)

| Phase | Case | Title | Why | Current |
|---|---|---|---|---|
| today | bed known | **"Try to be asleep by {11:35 pm}"** (D3) | debt < 15: "That gives you enough sleep before your usual wake-up time." · 15–59: "You’re a bit short on sleep from recent nights." · 60–179: "You’re short on sleep from recent nights." · ≥ 180: "You’re well short on sleep from recent nights." | "Aim for bed by 23:35" / "Tonight's sleep target is 7 h 53 m, with 58 m of sleep debt carried." |
| today | bed unknown | "Get a full night’s sleep tonight" | debt ≥ 15: the debt words above; else "Your sleep goal tonight is {7h 36m}." | "Aim for 7 h 36 m of sleep tonight" / "That is tonight's sleep target." |
| tonight | bed known, not yet past | **"Try to be asleep by {11:35 pm}"** | wake known: "You usually wake up at {7:28 am}, so that gives you enough sleep." Otherwise: "That gives you enough sleep tonight." | "Aim for bed by 23:35" / "Your usual wake-up is 07:28." |
| tonight | past bedtime | "Head to bed when you can" | "The best time to be asleep was {10:40 pm}." | "For tonight's target, bedtime was 22:40." |
| tonight | bed unknown | "Get to bed in good time" | "Your sleep goal tonight is {7h 53m}." | "Get to bed in time for tonight's target" / "That leaves room for tonight's sleep target." |

Awkward values:
- Bedtime after midnight (1460 min) gives "Try to be asleep by 12:20 am". The past check wraps correctly (:637-644).
- Exactly at bedtime counts as not past (`n > b`).
- Debt exactly 15 gets "a bit short"; debt 14 gets the no-debt line.
- Debt at the 300 cap gets "well short", and its chip reads "5h missed".

**Check-in action** (today_planner.dart:477-494). Drivers: the concerning vitals, `vitalsDriven` and the phase. The title stays **"Notice how you feel today"** (the safety constant, health_monitor.dart:34). Why:
- vitals-driven, today phase (the summary already names them): "This is a pattern in your numbers, not a diagnosis."
- otherwise: "{S7 sentence} This is a pattern in your numbers, not a diagnosis." For example: "Your skin temperature is higher than usual. This is a pattern in your numbers, not a diagnosis."
- Keep `checkInNote` = "a pattern in your numbers, not a diagnosis" verbatim. Only the surrounding sentence changes. (Safety review: meaning unchanged.)

**Recover action** (today_planner.dart:497-512). Title: today "Take it slow today", tonight "Have a calm evening" (current: "Keep today low-key" / "Keep the evening low-key"). Why:
- vitals-driven: "An easier day gives your body a break." (current: "An easier day gives your body room while resting HR is off your usual.")
- Recovery-driven: "Your Recovery is Low today." (current: "Recovery is in the red zone.")
- Decision D11 asks whether to drop this action when an effort action already says "Keep any workout easy today".

**Wear action** (housekeeping, sole action only, :533-560). Title: "Keep wearing your tracker to bed" (calibrating) / "Wear your tracker to bed tonight" (keep). Why (`_wearWhy`, :598-623):
- `rec == null`: "Last night’s heart data didn’t come in."
- no sleep: "Last night’s sleep didn’t come in, so today’s score leaves it out."
- without HRV, shareable: "Last night’s HRV didn’t come in, so today’s score leaves it out."
- calibrating: "Airlog learns what’s normal for you from each night you wear it."

**Sync action** (:516-531). Title: "Open {App} to sync" / "Open your tracker’s app to sync" (keep; fall back to the generic title when the name looks like a package id, such as `com.x.y`). Why:
- behind: "Last night’s data comes in when it syncs."
- no data ever: "No data has reached Airlog yet."
- stale: "Your latest data is from {yesterday, 11:10 pm}."

**Re-learning line**. It is appended when the wear action is suppressed (:541-549). Current: "Re-learning your normal with {App}: {2} of {14} nights so far". Proposed: "Airlog is learning your {App} data: {2} of {14} nights so far." Engineering note: `PlanTile.basis` checks `summary.startsWith('Re-learning')` (plan_tile.dart:41). Replace that check with a flag (§8).

#### 4.1.7 Whole-card examples (headline / summary / chips / actions)

Numbers come from the golden fixtures unless stated. Times are shown in 12-hour form (phone set to 12-hour).

1. **Ready, 7:40 am** (Recovery 78, HRV 53 vs 47, RHR 53 vs 56, target 15.6, so 0.6, bed 23:35, debt 58)
   - Before: "Ready to push" / "Recovery 78%: HRV is 13% above your usual and resting HR below your usual (53 vs 56 bpm)." / [Recovery 78%] [HRV 53 ms · 13% above usual] / "Room to push: strain 14–17 — Strain 0.6 so far of your 14–17 target." / "Aim for bed by 23:35 — Tonight's sleep target is 7 h 53 m, with 58 m of sleep debt carried."
   - After: **"Your body is ready"** / "Your heart is well rested today." / [Recovery 78%] [HRV 53 ms · 13% above usual] / **"A hard workout is fine today"**: "Try a long run, intervals or a tough gym session." [Effort goal 14–17] / **"Try to be asleep by 11:35 pm"**: "You’re a bit short on sleep from recent nights." [Sleep goal 7h 53m · 58m missed]
2. **Steady, 12:30 pm** (Recovery 52, HRV −8%, RHR 58 vs 56, sleep 64%, range 9–12, so 3.1, bed 22:50, debt 0)
   - "Good for a normal day" / "Your heart is less rested than usual, and you slept well under your sleep goal." / [Recovery 52%] [HRV 41 ms · 8% below usual] / "A normal workout is fine today": "You’ve made a start." [Effort goal 9–12 · 3.1 so far] / "Try to be asleep by 10:50 pm": "That gives you enough sleep before your usual wake-up time." [Sleep goal 7h 36m]
3. **Easy (Low Recovery), 8:15 am** (Recovery 28, HRV −14%, RHR +3)
   - "Take it easy today" / "Your heart is less rested than usual." / [Recovery 28%] [HRV 38 ms · 14% below usual] / "Keep any workout easy today": "Try a walk, an easy bike ride or yoga." [Effort goal 4–7] / "Try to be asleep by 10:40 pm": "You’re short on sleep from recent nights." / "Take it slow today": "Your Recovery is Low today." (see D11)
4. **Rest, Recovery-driven, 9:00 am** (Recovery 12, target 3 → 2–5)
   - "Make today a rest day" / "Your body hasn’t recovered yet. Your heart is less rested than usual." / [Recovery 12%] [HRV 30 ms · 22% below usual] / "Rest or move gently today": "A short walk or some gentle stretching is plenty." / sleep action / "Take it slow today": "Your Recovery is Low today."
5. **Easy, vitals-driven, 7:30 am** (Recovery 72, RHR 61 vs 54)
   - "Take it easy today" / "Your resting heart rate is higher than usual." / [Recovery 72%] [Resting HR 61 bpm · usual 54 bpm] / "Keep any workout easy today": "Try a walk, an easy bike ride or yoga." (no goal chip) / sleep action / "Notice how you feel today": "This is a pattern in your numbers, not a diagnosis."
6. **Awkward: rest with three mixed vitals, 7:05 am** (HRV 30 vs 45 low; RHR 61 vs 54 high; breathing 17.9 vs 15.3 high; Recovery 60)
   - "Make today a rest day" / "Your HRV is lower than usual, and your resting heart rate and breathing rate are higher." / [Recovery 60%] [Resting HR 61 bpm · usual 54 bpm] (the first concerning vital in `HealthMetricKind` order) / "Rest or move gently today": "A short walk or some gentle stretching is plenty." / sleep action / "Notice how you feel today": "This is a pattern in your numbers, not a diagnosis." [HRV 30 ms · usual 45 ms] [Breathing rate 17.9 breaths/min · usual 15.3 breaths/min]
7. **Tonight, 9:15 pm** (ready, debt 58, bed 23:35, wake 07:28, need 473)
   - "Time to wind down" / "You’re a bit short on sleep from recent nights." / [Sleep goal 7h 53m] [Missed sleep 58m] / "Try to be asleep by 11:35 pm": "You usually wake up at 7:28 am, so that gives you enough sleep."
8. **Awkward: tonight, past bedtime, 12:40 am, debt at the cap**
   - "Time to wind down" / "You’re well short on sleep from recent nights." / [Sleep goal 8h 36m] [Missed sleep 5h] / "Head to bed when you can": "The best time to be asleep was 11:35 pm."
9. **Calibrating, night 3, 7:10 am** (Recovery 20)
   - "Still getting to know you" / "Airlog is still learning what’s normal for you, so today’s score may change." / [Recovery 20% · early estimate] [Learning 3 of 14 nights] / "Keep wearing your tracker to bed": "Airlog learns what’s normal for you from each night you wear it."
10. **Re-learning a new app** (switched to Oura, 2 of 14)
    - "Still getting to know you" / "You switched to Oura, so Airlog is learning your usual again. Today’s score may change." / [Recovery 55% · early estimate] [Learning 2 of 14 nights] / sleep action (no wear action while re-learning)
11. **Without HRV (Samsung Health, sleeping HR), steady**
    - "Good for a normal day" / "Your heart looks about the same as usual." / [Recovery 58% · without HRV] [Resting HR 55 bpm · usual 55 bpm] / top line "without HRV" / effort and sleep actions
12. **App shares neither HRV nor RHR**
    - "No Recovery score today" / "Samsung Health doesn’t share the heart data Recovery needs, so there’s no Recovery score. Sleep and Strain still work." / [Sleep 6h 40m · goal 7h 36m] / no actions ("Nothing to change today.")
13. **Behind, 8:00 am** (newest data from yesterday 23:10, Google Health)
    - "Waiting for your data" / "Nothing has come in for today yet." / [Last update yesterday, 11:10 pm] / "Open Google Health to sync": "Last night’s data comes in when it syncs."
14. **Before wake, 2:30 am**
    - "Waiting for your data" / "Your scores show up after you wake up and your tracker syncs." / no chips, no actions
15. **Stale green, 2:00 pm** (newest data 12.5h old)
    - top line "Your data may be out of date" / "Good for a normal day" / "Your heart is well rested today." / [Recovery 81%] [HRV …] / sleep action only (no effort advice while stale)
16. **Limited confidence**
    - "Good for a normal day" / "Today’s score uses only part of your data, so there’s no workout advice today." / [Recovery 45% · early estimate] / sleep action
17. **Sample data**: the text is the same as for real data. The header freshness line reads "Sample data · just now" (X02), and coach answers carry the "Sample data" tag. Nothing in the plan text changes.

#### 4.1.8 Numbers left in the plan text (the eval audit)

| Number | Where | Cited field |
|---|---|---|
| Recovery % | E5 chip | `recovery.score` |
| HRV ms, % above or below | E8 chip | `recovery.components.value/baseline` (`pctVsUsual`) |
| Resting HR bpm and usual | E6/E8 chips | `recovery.components` or `health.metrics` |
| Vital value and usual | E6, checkIn chips | `health.metrics` |
| "{3} of {14} nights" | E7 chip, re-learning line | `calibration`, `sourceChange.nights` |
| Goal range and "so far" | effort action chip | `strain.targetStrain` → `targetRange`, `strain.strain` |
| Sleep goal, missed sleep | E2/E3/E4 chips, sleep action chip, one sleep why | `sleep.needMinutes`, `bedtime.projectedNeedMinutes`, `bedtime.debtMinutes` |
| Bedtime, wake time | sleep action title and why | `bedtime.recommendedBedtimeMinutes`, `habitualWakeMinutes` (12/24h, D2) |
| Last update | E1 chip, sync why | `record.lastDataAt` / `SyncStatus.lastDataAt` |
| App names (may contain digits) | S3, S8, sync title | `notShared`, provenance origins (as today) |

**Removed from the text:**
- the resting HR pair "(53 vs 56 bpm)" in the summary (still on the Recovery tile);
- "Strain 0.6 so far" in the morning;
- "sleep covered 66% of your target" (now words);
- "Recovery 60%" inside S7 (the chip still has it).

`sleep.performance` stays in `citedResultFields` so nothing breaks, but nothing uses it now.

### 4.2 Today tile values (`today_view_model.dart`) [Phase B]

| Template | Drivers | Proposed | Examples (incl. awkward) |
|---|---|---|---|
| HRV vs usual (:385-388) | hrv value, baseline mean | "+{13}%" / "−{8}%" / **"About usual"** (when it rounds to 0) | "+13%"; "−8%"; awkward: value 47.2 vs 47.0 → "About usual" |
| Resting or sleeping HR vs usual (:389-390) | rhr value, baseline | "+{3} bpm" / "−{3} bpm" / **"About usual"** | "−3 bpm"; "+6 bpm"; 55.4 vs 55.2 → "About usual" |
| Recovery ring caption (:421-442) | calibrating, established, zone | "{1} more night" / "{4} more nights" / "Early estimate" / "Good" / "Fair" / "Low"; none: "No heart data" | "1 more night" (singular); "Early estimate"; "Low" |
| Strain ring caption (:468-483) | method, targetStrain | "Goal {15.6}" / "Estimate · Goal {15.6}" / "No heart rate" | "Goal 15.6"; "Estimate · Goal 3.0"; awkward: target null → caption "" → tile shows "out of 21" |
| Sleep caption (:485-494) | sleptMinutes | "{7h 1m}" / "No sleep data" | "7h 1m"; "45 min"; awkward: 0 min stays "0 min" |
| Activity facts (:394-405) | workouts count, steps | "{2} workouts · {8,432} steps" (keep) | "1 workout"; "8,432 steps"; awkward: 0 steps and 0 workouts → null → "No heart rate yet" |
| 7-day steps (:340-366) | recovery scores | "{78}" + delta "+{8}" / "−{20}" / "0" (keep). This is a Figma tile with no caption (P3: consider a micro label "Last 6 days"). | — |

### 4.3 Recovery meaning line (`recovery_view_model.dart:315-334`) [Phase B]

Drivers: `rec.zone`, `strain.targetStrain` (→ `targetRange`), `isToday`.

**Why it changes:**
1. It is untrue on some green days. A score of 67 or more doesn't mean every signal was "at or better than your usual".
2. Its advice ("a harder session") can contradict a vitals-driven "Take it easy" plan on Today. TodayPlan is the only narrator (§7).
3. It prints the raw target.

The new line **describes the zone only** and shows the goal as a range (D13).

| Zone | Today | Past day |
|---|---|---|
| Good | "You’ve recovered well. Effort goal today: {14–17}." | "You had recovered well that day. Effort goal was {12–15}." |
| Fair | "You’ve partly recovered. Effort goal today: {8–11}." | "You had partly recovered that day. Effort goal was {8–11}." |
| Low | "You haven’t fully recovered. Effort goal today: {3–6}." | "You hadn’t fully recovered that day. Effort goal was {3–6}." |
| any, target null | the zone sentence only | the zone sentence only |

Examples:
- Recovery 78 today, target 15.6: "You’ve recovered well. Effort goal today: 14–17."
- Recovery 45 today, target 9.0: "You’ve partly recovered. Effort goal today: 8–11." (7.5 and 10.5 round up)
- **Awkward:** Recovery 20 on a past day, target 4.0: "You hadn’t fully recovered that day. Effort goal was 3–6." On the same day Today may have said "Rest or move gently". The goal range is still true, just not the advice, which is why the line no longer gives advice.

### 4.4 Sleep bedtime card (`sleep_widgets.dart:280-330`) [Phase B]

Drivers: `BedtimeVm.bedtime` (clock), `needMinutes`, `debtShareMinutes`, `debtMinutes`, `wake`.

| Part | Current | Proposed |
|---|---|---|
| Eyebrow | "TONIGHT" | "TONIGHT" |
| Title | "Aim to be asleep by " + **{23:35}** | "Try to be asleep by " + **{11:35 pm}** (the same verb as Today, D3) |
| Body, catch-up ≥ 1 min | "Tonight’s target is {7h 53m}, including {17m} toward your {58m} of debt, and you usually wake at {07:28}." | "That gives you {7h 53m} of sleep before you usually wake up at {7:28 am}, with {17 min} extra to catch up." |
| Body, no catch-up | "Tonight’s target is {7h 36m}, and you usually wake at {07:28}." | "That gives you {7h 36m} of sleep before you usually wake up at {7:28 am}." |
| Spoken | "Tonight: aim to be asleep by {b}. {body}" | "Tonight: try to be asleep by {b}. {body}" |

Examples:
- Debt 58: "Try to be asleep by 11:35 pm" / "That gives you 7h 53m of sleep before you usually wake up at 7:28 am, with 17 min extra to catch up."
- No debt: "Try to be asleep by 10:52 pm" / "That gives you 7h 36m of sleep before you usually wake up at 6:28 am."
- **Awkward**, a late riser at the debt cap with a bedtime after midnight: "Try to be asleep by 12:24 am" / "That gives you 8h 36m of sleep before you usually wake up at 9:00 am, with 1h extra to catch up."

### 4.5 Strain recommendation (`strain_view_model.dart:101-127`) [Phase B]

Drivers: `target`, `strainValue`, `verdict` (onTarget when within ±1 of the target, :94-99), `isToday`, `noInput`.

The numbers are dropped from the sentence: the ring, the target line and "set by your 74% Recovery" already show them.

| Case | Today | Past day | Current (today) |
|---|---|---|---|
| no input | "No heart rate for this day yet." | same | "Nothing to score for this day yet." |
| no target | "No effort goal today: there’s no Recovery score." | "No effort goal that day: there was no Recovery score." | "Recovery does not support an effort target for this day." |
| under | "You still have room for more effort today." | "You finished below that day’s goal." | "Room for about {4.2} more strain today for a {74} % recovery." |
| on target | "You’ve hit today’s goal. Anything more is extra." | "You hit that day’s goal." | "On target for a {74} % recovery. Anything more is extra." |
| over | "You’re past today’s goal. Take it easy this evening." | "You went past that day’s goal." | "{1.3} over today’s target of {14.8}. An easy evening leaves room to recover." |

Examples: strain 0.6 vs target 15.6 at 07:40 gives "You still have room for more effort today." Strain 14.6 vs 14.8 on a past day gives "You hit that day’s goal." **Awkward:** strain 16.3 vs target 15.6 counts as "on target" here (±1), while Today's range is 14–17 (±1.5) and calls it P4 "You’ve hit today’s goal". The two agree only by luck. **D13** proposes one rule for both: the range.

### 4.6 Overnight-signals alert [Phase B]

**Today alert sheet** (`today_view_model.dart:670-750`). Drivers: the concerning vitals (`HealthMonitor.isConcerning`), the streak in days, `health.alertReason`.

| Part | Current | Proposed |
|---|---|---|
| Title, none concerning | "Signals outside your usual range" | keep |
| Title, 2 or more | "{Two} signals outside your usual range" | keep |
| Title, 1 vital, streak of 2+ | "{Resting HR} {high} for {3} days" | "{Resting heart rate} {high} for {3} days" (plain name; "low" for HRV and blood oxygen) |
| Title, 1 vital | "{Resting HR} outside your usual range" | "{Resting heart rate} outside your usual range" |
| Body item | "{resting HR} {higher} ({61} vs usual {54} {bpm})" joined, capitalised, "." | "your {resting heart rate} is {higher} ({61} vs your usual {54} {bpm})" joined with "and", capitalised, "." |
| Fix | "An easier day and an early night are a sensible response. This is a pattern in your numbers, not a diagnosis." | "An easier day and an early night can help. This is a pattern in your numbers, not a diagnosis." (safety review: meaning unchanged) |

Examples:
- 1 vital: "Resting heart rate outside your usual range" / "Your resting heart rate is higher (61 vs your usual 54 bpm)."
- Streak: "Blood oxygen low for 3 days" / "Your blood oxygen is lower (91 vs your usual 96%)."
- **Awkward**, three vitals: "Three signals outside your usual range" / "Your HRV is lower (30 vs your usual 45 ms), your resting heart rate is higher (61 vs your usual 54 bpm) and your breathing rate is higher (17.9 vs your usual 15.3 breaths/min)." (Long, but it's a detail sheet. OK.)

**Engine alert messages** (`health_monitor.dart:184-224`, shown as `alertReason` when the list is empty). Pulse-port copy.

| Rule | Current | Proposed |
|---|---|---|
| 2+ metrics | "{2} values outside your baseline ({HRV, Resting HR}). Notice how you feel; this pattern is not a diagnosis." | "{2} signals are outside your usual range ({HRV and resting heart rate}). Notice how you feel. This is a pattern, not a diagnosis." |
| 1 metric, 2+ days | "{Resting HR} has been {elevated} for {3} days – prioritize recovery." | "Your {resting heart rate} has been {high} for {3} days. Take it easy." |

Tests: `test/domain/pulse_parity_health_monitor_test.dart` may assert these. Check before changing (§6).

### 4.7 Status notes (`notes.dart`) [Phase B]: paste-ready

These cards show under "About today's data" and on detail screens. Fields are the placeholders. Settings paths now read "Settings → Data sources" (SE04).

| Note | Title (current → proposed) | Body (proposed) | Fix (proposed) | Line |
|---|---|---|---|---|
| `_wearFix` | — | — | "Wear your tracker to bed tonight, then open Airlog in the morning." | :14-16 |
| `missingHrv` | "No HRV for this night" / "No HRV yet" (keep) | "Airlog didn’t get HRV for this night, so Recovery used your other signals. This usually happens when the tracker wasn’t worn to bed, the HRV permission is off, or your tracker’s app (like Google Health) isn’t sharing HRV with Health Connect." | "Wear your tracker to bed, and check the HRV permission in Settings → Data sources." | :18-31 |
| `_otherAppFix` | — | — | "If another app on this phone shares it with Health Connect, pick that app in Settings → Data sources." | :33-35 |
| `hrvNotShared` (scored) | "Recovery without HRV" (keep) | "{App} doesn’t share HRV with Health Connect, so Recovery uses your other signals, and each one counts a bit more. It’s labelled “without HRV” and is less exact. Airlog never guesses HRV from other data." | `_otherAppFix` | :41-54 |
| `hrvNotShared` (no score) | "No HRV from {App}" (keep) | "{App} doesn’t share HRV with Health Connect. Airlog never guesses HRV from other data." | `_otherAppFix` | :45-52 |
| `rhrNotShared` (sleeping HR) | "No resting heart rate from {App}" (keep) | "{App} doesn’t share resting heart rate with Health Connect. So Recovery uses your sleeping heart rate instead: your average heart rate in the first 4 hours of sleep, from {App}’s own readings, compared with its own usual. It’s less exact, and it’s never shown as resting heart rate." | `_otherAppFix` | :58-73 |
| `rhrNotShared` (none) | same | "{App} doesn’t share resting heart rate with Health Connect, so Recovery works without it. Airlog never guesses it from other heart-rate data." | `_otherAppFix` | :69-71 |
| `recoveryNotShared` | "No Recovery score" (keep) | "{App} doesn’t share HRV or resting heart rate with Health Connect, and last night’s heart rate was too patchy (or the sleep too short) to use your sleeping heart rate. Airlog shows no score rather than a guess. Sleep and Strain still work." | "{continuous fix} Or, if another app on this phone shares HRV or resting heart rate with Health Connect, pick it in Settings → Data sources." | :78-92 |
| `_continuousHrFix` | — | — | Samsung: "Turn on continuous heart-rate measurement in {App} (Heart rate → Measure continuously)." (keep: vendor path) · others: "Turn on all-day heart rate in {App}." | :96-100 |
| `missingRhr` | "No resting heart rate" / "…yet" (keep) | "Your tracker saves resting heart rate after a night of wear. It’s missing when the tracker wasn’t worn, the Resting heart rate permission is off, or the latest sync hasn’t run yet." | `_wearFix` | :102-111 |
| `missingResp` | "No respiratory rate" → **"No breathing rate"** | "Breathing rate is only measured during sleep. It’s missing when the tracker wasn’t worn to bed or the Respiratory rate permission is off (that’s its name in Health Connect). Recovery uses your other signals." | `_wearFix` | :113-121 |
| `missingSpo2` | "No SpO₂" → **"No blood oxygen"** | "No overnight blood-oxygen readings came in for this night. Some apps don’t share it with Health Connect. For a Fitbit, it can come from Enhanced mode (Google Health). Without it, Recovery skips the low-oxygen check." | "Check the Blood oxygen permission in Settings → Data sources, or turn on Enhanced mode for a Fitbit." | :123-134 |
| `missingSkinTemp` | "No skin temperature" (keep) | "Skin temperature is measured during sleep, as a change from your tracker’s own usual. It’s missing when the tracker wasn’t worn to bed, the Skin temperature permission is off, or the tracker is still learning your usual (the first few nights)." | `_wearFix` | :136-146 |
| `missingSleep` | "No sleep recorded" / "…yet" (keep) | "No sleep came in for this night, so there’s no sleep score, and your missed sleep stays the same. This usually happens when the tracker wasn’t worn to bed, the Sleep permission is off, or your tracker’s app hasn’t finished with the night yet." | `_wearFix` | :148-158 |
| `missingHr` | "No heart-rate samples" → **"No heart rate"** | "No heart rate came in for this day. It’s missing when the tracker wasn’t worn, the Heart rate permission is off, or the latest sync hasn’t run yet." | "Check the Heart rate permission in Settings → Data sources." | :160-168 |
| `missingSteps` | "No step count" (keep) | "No steps came in for this day, so your activity shows without them." (**P1 honesty**: the current body says steps feed a "fallback strain estimate", but copy.dart:40 says steps never produce Strain) | "Check the Steps permission in Settings → Data sources." | :170-177 |
| `recoveryUnavailable` | "No Recovery score" (keep) | "Recovery needs HRV or resting heart rate from last night. Neither came in, so there’s no score rather than a guess." | `_wearFix` | :179-187 |
| `recoveryCalibrating` | "Calibrating your baseline" → **"Learning your usual"** | "Recovery compares each night with your own usual. It starts to mean something after 5 nights of {HRV} ({3} so far) and settles after 14. Until then, treat it as an early estimate." | "Keep wearing your tracker to bed." | :191-203 |
| `strainPartialHr` | "Strain from partial heart rate" → **"Strain from patchy heart rate"** | "Only {45}% of your waking minutes have heart rate, so this Strain is probably too low. Airlog only scores Strain from measured heart rate, never from steps or workout type." | "Check that heart rate from your tracker reaches Health Connect." | :205-215 |
| `strainUnavailable` | "No Strain score" (keep) | "No heart rate came in for this day, so there’s no Strain score. Airlog only scores Strain from measured heart rate. Your workouts and steps still show as activity." | "Check the Heart rate and Steps permissions in Settings → Data sources." | :217-226 |
| `strainNeedsMaxHr` | "Strain needs your max heart rate" (keep) | "Heart-rate zones need a max heart rate. There’s no birth year or max heart rate set, and not enough heart rate yet to use your highest reading, so there’s no Strain score rather than a guess." | "Add your birth year (or a measured max heart rate) in Settings → Profile." | :230-239 |
| `strainInvalidAnchors` | "Heart-rate zones unavailable" → **"Can’t set heart-rate zones"** | "Heart rate came in, but your max and resting heart rates don’t leave a usable range, so there’s no Strain score." | "Check your max heart rate in Settings → Profile, and where your resting heart rate comes from in Settings → Data sources." | :241-249 |
| `zonesFromMaxHr` | "Zones from max heart rate" (keep) | "No resting heart rate came in, so your zones use a share of your max heart rate instead (a published method). Airlog never guesses a resting heart rate." | — | :253-260 |
| `observedMaxHr` | "Zones use your highest observed heart rate" → **"Zones use your highest heart rate"** | "No birth year is set, so your zones use the highest heart rate seen in the last 90 days ({186} bpm). If you rarely train hard, your zones and Strain may read high." | "Add your birth year (or a measured max heart rate) in Settings → Profile." | :264-272 |
| `assumedMaxHr` | "Using an assumed max heart rate" | **Delete.** It's never emitted (algo v2). Only `sortNotes` uses its title (today_view_model.dart:763,789), and that branch goes too (§8). | — | :276-284 |
| `newBaseline` | "New {HRV} baseline" → **"Learning your {HRV} again"** | device: "Your {HRV} now comes from your {Pixel Watch} instead of your {Fitbit Air}. Each device measures a little differently, so Airlog is learning your usual again instead of mixing the two. It has {3} nights so far." · app: "Your {HRV} now comes from {Samsung Health} instead of {Google Health (Fitbit)}. Each app measures a little differently, so Airlog is learning your usual again instead of mixing the two. It has {3} nights so far." · definition: "Your {HRV} is now measured a different way ({Deep-sleep HRV from Google Health}, before: {Overnight HRV from Health Connect}), so Airlog is learning your usual again instead of mixing the two. It has {3} nights so far." | — | :288-329 |
| `_metricName` | 'resting HR' / 'respiratory rate' / 'SpO₂' | 'resting heart rate' / 'breathing rate' / 'blood oxygen' (HRV and skin temperature keep) | — | :350-357 |
| Age gate | "Scores are for adults" / "Airlog does not provide scores or training guidance for people under 18." | keep | — | day_engine.dart:243-244 |

**Examples of `newBaseline`:**
1. App switch: "Learning your HRV again" / "Your HRV now comes from Samsung Health instead of Google Health (Fitbit). … It has 3 nights so far."
2. Device switch: "Learning your resting heart rate again" / "Your resting heart rate now comes from your Pixel Watch instead of your Fitbit Air. …"
3. **Awkward**, 0 nights: "… It has 0 nights so far." Proposed variant for 0: "… It’s starting from tonight."

### 4.8 Insight cards (`insight_templates.dart`) [Phase B]

The voice rules for cards stay: numbers are always shown, at most two sentences, no streak words. Card text must still verify by construction, so every number stays a ref. Ref **labels** show as source chips in the coach; they follow the glossary.

| Card | Part | Current | Proposed | Line |
|---|---|---|---|---|
| Sleep | ref labels | "Asleep · {day}" / "Sleep performance · {day}" / "Sleep need · {day}" / "Sleep debt · {day}" / "Bedtime · {day}" / "Wake time · {day}" / "Deep sleep · {day}" / "REM sleep · {day}" | "Asleep · {day}" / "Sleep % of goal · {day}" / "Sleep goal · {day}" / "Missed sleep · {day}" / keep the rest | :153-222 |
| Sleep | headline | "A solid night's sleep" / "A slightly short night" / "A short night" | keep | :181-185 |
| Sleep | body | "You slept {7h 1m}, a sleep performance of {89%} against a sleep need of {7h 51m}." + " Sleep debt is {58 min}." / " You have no sleep debt." | "You slept {7h 1m}, {89%} of your {7h 51m} sleep goal." + " You’re short {58 min} of sleep from recent nights." / " You’re not short on sleep." | :186-194 |
| Sleep | bullets | "Timing: Bedtime {23:13}, wake time {06:35}" / "Stages: Deep sleep {1h 10m}, REM sleep {1h 20m}" | "Timing: asleep at {23:13}, up at {06:35}" (12h follows D2) / keep | :211-229 |
| Recovery | headline | "{HRV} moved your recovery most" / "Your baseline is still forming" | "{HRV} made the biggest difference" / "Still learning your usual" | :320,330 |
| Recovery | body | "{HRV} was {53 ms}, {above} your baseline of {47 ms}." + " {Resting HR} was {53 bpm} against {56 bpm}." / calibrating "{HRV} was {53 ms} against a baseline of {47 ms} that is still calibrating." / forming "{HRV} was {53 ms}. Recovery firms up once there are enough nights to compare with." | "Your {HRV} was {53 ms}, {above} your usual {47 ms}." + " Your {resting heart rate} was {53 bpm}, against your usual {56 bpm}." / "Your {HRV} was {53 ms}, against your usual of {47 ms}, which Airlog is still learning." / "Your {HRV} was {53 ms}. Your score will settle once Airlog has more nights to compare." | :321-354 |
| Recovery | bullets and refs | "{HRV}: {53 ms} ({40%} of the score), baseline {47 ms}" / "Penalty: {label}: {5 points}"; refs "{name} baseline · {day}" | "{HRV}: {53 ms}, usual {47 ms} ({40%} of the score)" / "Penalty: {label}: {5 points} off"; refs "{name} usual · {day}" | :282-314 |
| Strain | headline | "Past your strain target" / "Close to your strain target" / "A lighter day" / "Your strain for the day" | "Past your effort goal" / "Close to your effort goal" / "A lighter day" / "Your Strain for the day" | :404-415 |
| Strain | body | "Strain was {14.6} against a target of {14.8}." / "Strain was {x}. There is no strain target without a recovery score." / " The most came from the {run}, strain {9.2}." | "Your Strain was {14.6}, against a goal of {14.8}." / "Your Strain was {x}. There’s no effort goal without a Recovery score." / " Most of it came from your {run} (Strain {9.2})." | :405-438 |
| Strain | bullets | "Intensity: {45 min} in zones 2–3, {18 min} in zones 4–5" / "Volume: {2} workouts, {1h 10m}" / "Goal alignment: This training adds to the goal you saved." | "Effort: {45 min} light to moderate (zones 2–3), {18 min} hard (zones 4–5)" / "Workouts: {2}, {1h 10m} in total" / "Your goal: This training adds to the goal you saved." | :459-497 |
| Strain | refs | "Strain target · {day}" | "Effort goal · {day}" | :394 |
| Workout | headline, body | "{Run}: a hard session" / "{Run} recorded" / "Duration {45 min}, average heart rate {152 bpm}, strain {9.2}." | keep / keep / "{45 min}, average heart rate {152 bpm}, Strain {9.2}." | :570-576 |
| Workout | bullets | "Intensity: …" / "Volume: {5.2 km} in {45 min}" / "Goal alignment: This session adds to the goal you saved." | "Effort: …" (as for Strain) / "Distance: {5.2 km} in {45 min}" / "Your goal: This session adds to the goal you saved." | :594-622 |
| Health | headline, body | "A signal outside your usual range" / "Signals outside your usual range"; "{Resting HR} was {61 bpm}, {above} your usual range of {50 bpm} to {58 bpm}. This is a pattern in your numbers, not a diagnosis." / "Some overnight signals are outside your usual range. …"; bullet "Also: …" | keep / keep; "Your {resting heart rate} was {61 bpm}, {above} your usual range of {50 bpm} to {58 bpm}. This is a pattern in your numbers, not a diagnosis." / keep; keep | :695-716 |
| Weekly | headline, body | "Your week in numbers"; "Recovery averaged {61%} and sleep averaged {6h 50m} a night." | keep | :750-817 |
| Weekly | bullets and refs | "Consistency: {3} of {7} met your sleep need"; "Volume: …"; ref "Nights that met your sleep need · {span}" | "Consistency: {3} of {7} nights met your sleep goal"; "Workouts: …"; "Nights that met your sleep goal · {span}" | :772-808 |

Three filled examples, Sleep card:
1. "A solid night’s sleep" / "You slept 7h 1m, 89% of your 7h 51m sleep goal. You’re short 58 min of sleep from recent nights."
2. "A slightly short night" / "You slept 6h 12m, 79% of your 7h 51m sleep goal. You’re not short on sleep." (with debt 0 this pairing is possible, and it's still true)
3. **Awkward:** "A short night" / "You slept 3h 5m, 38% of your 8h 6m sleep goal. You’re short 5h of sleep from recent nights."

Recovery card:
1. "HRV made the biggest difference" / "Your HRV was 53 ms, above your usual 47 ms. Your resting heart rate was 53 bpm, against your usual 56 bpm."
2. "Breathing rate made the biggest difference" / "Your breathing rate was 17.9 breaths/min, above your usual 15.3 breaths/min."
3. **Awkward**, still learning: "Still learning your usual" / "Your HRV was 53 ms. Your score will settle once Airlog has more nights to compare."

### 4.9 Other generated lines (already in §3)

- Journal insight: J13 (D8).
- Training-load verdict: TR07, TR14.
- HRV-week body: R19.
- Reweight and neutral notes: R14, R15.
- Coach verification and fallback: C05–C08.

### 4.10 On-device coach answers (`offline_client.dart`) [owner: Revamp for the chat UI; the templates are Phase B's data layer, see D12]

These answers must verify, so their numbers stay. Only the words change.

| Line | Current | Proposed | P |
|---|---|---|---|
| :746-754 | "I can't see a pattern for "{x}" yet: I need at least **five** logged days with it and **five** without…" / "…at least **five** days with each tag and **five** without." | Use the engine constant: "…at least {10} logged days with it and {10} without…". **P1 honesty:** the Journal needs 10 (`JournalEngine.minDaysPerGroup`, journal.dart:25). | P1 |
| :1008-1009 | "I don't have sleep data for {when}: nothing was recorded (the band was off, charging or not synced), so I can't score it." | "I don’t have sleep data for {when}: nothing was recorded, so I can’t score it." **P1:** the coach's own rule 4 (prompts.dart:31) forbids inventing causes like charging. | P1 |
| :1118-1119 | "I don't have any data {day}: the band wasn't worn or hasn't synced yet." | "I don’t have any data {day}. Nothing was recorded or synced yet." | P1 |
| :682-683 | "On {day} the band recorded no heart rate from …" | "On {day} your tracker recorded no heart rate from …" | P2 |
| :874-887 | "Your strain target {day} is {x}, set from a recovery of {y}" / "I don't have a strain target {day}: it needs a recovery score, and there isn't one." | "Your effort goal {day} is {x}, set from a Recovery of {y}" / "I don’t have an effort goal {day}: it needs a Recovery score, and there isn’t one." | P2 |
| :894-907 | "Your recent training load (average strain over the last week) is {x}… a ratio of {r}"; verdicts "lighter than usual" / "in a balanced range" / "a step up from usual" / "well above what you are used to" | "…"; verdicts "less than usual" / "about usual" / "more than usual" / "much more than usual" (the same words as Trends) | P2 |
| :853, :1183-1184 | "Your baseline is {x}" / "Your baseline is still calibrating, so treat this as provisional." | "Your usual is {x}" / "Airlog is still learning your usual, so treat this as an early estimate." | P2 |
| :1168-1171, 1235 | "Sleep performance was {x}" / "a sleep performance of {x}" | "You got {x} of your sleep goal" / "{x} of your sleep goal" | P2 |
| :1020-1025, 1093-1094 | "Your sleep debt is now {x}" / "Your sleep debt after the latest night is {x}" | "You’ve missed {x} of sleep recently" / "After the latest night, you’ve missed {x} of sleep" | P2 |
| :617-631 | "The Health Monitor raised an alert {day}." / "…shows a value outside your usual range…" + "Out-of-range values can follow hard training, alcohol, heat or illness, so this is not a diagnosis. If you feel unwell, talk to a doctor." | "Airlog flagged your overnight signals {day}." / "…one overnight signal was outside your usual range…" + keep the safety sentence word for word | P3 |
| :479 | "For open questions, connect Claude or Gemini in Settings → Coach." | keep | — |
| :1282-1283, 1293-1295, 1321-1324, 550-571 | general-only, can't-answer, future-date, card-context lines | keep; "a specific day or metric" → "one day or one score" | P3 |
| safety.dart:134-181 | The red-flag, crisis, medication, eating, pregnancy and under-18 messages | **Keep the meaning and the emergency numbers word for word.** Only readability edits: "your band’s data" → "your tracker’s data" (:141, :159). Mark as "needs safety review". | P2 |

---

## 5. Layout risks

How text behaves today, which decides where longer strings break:

- **Tiles** (every Figma tile on Today, plus the Strain, Trends, Sleep and Journal tiles) have **fixed pixel layouts with single-line text** (`TileText`, `maxLines: 1`, design/components/tile.dart:283-354). Text scaling is **pinned** (`TileScope`, :173-190).
  - **Above 1.3× text size**, each tile is replaced by its **spoken label rendered as body text** (`GlowTile`, :216). So the semantic labels in T09, T11, T12, T15, ST08 and TR08 *are* the visible tile at 2×. They must read as plain sentences, and that's why §3 rewrites them.
  - **At 320 px** the whole bento grid scales down uniformly (`BentoGrid`, `FittedBox`, bento.dart:39-45). Tile text shrinks rather than wraps, so a longer tile label means smaller type on narrow phones. With no `maxWidth` it can also run past its slot.
- **The plan card** wraps normally and clamps text scaling at **1.3×** (plan_tile.dart:69). At 2× it stays at 1.3×, so it grows but won't explode.
- **Sheets, cards and list rows** wrap normally at any size.

| String | Where | Growth | Risk at 320 px | Risk at 2× text | Mitigation |
|---|---|---|---|---|---|
| Recovery tile title with tags ("Recovery · without HRV · early estimate · learning") | ReadinessTile title, x = tilePad, no maxWidth | up to about 50 chars | **High**: runs into the stats column at x = 206 | tile shows the spoken label (fine) | T06: title "Recovery" plus **one** tag in the status slot |
| Vital tile titles "Blood oxygen" / "Breathing" (were "SpO₂" / "Respiration") | 164 px tiles | +5 chars | Medium: "Blood oxygen" at tileTitle is about 105 px, which fits the 164 px tile with 16 px padding; check "Skin temp" alignment | spoken label | check the golden; fall back to "Oxygen" if it clips |
| Strain tile caption "Estimate · Goal 15.6" | ArcScoreTile caption | +1 char | low | spoken | — |
| Training load "vs usual" + **"About usual"** | SegmentScaleTile `lead verdict` | "Similar" → "About usual" (+4) | Medium: lead and verdict share one baseline line | spoken | Shorten the lead to "vs usual". If it still clips, drop the lead and show only the verdict. |
| Band labels "Less / About usual / More / Much more" | 4 equal bands (~75 px each at tileMicro) | "About usual" is ~65 px | Medium | spoken | alternative: "Less / Usual / More / Much more" |
| Week tile "Hardest day:" + "Wednesday"; "OUT OF 21" | WeeklyBarsTile | "Most strained day:" (18) → "Hardest day:" (12): **shorter**; "OF 21" → "OUT OF 21" (+4) | low / low | spoken | — |
| Sleep hero labels "Asleep" / "Of your goal" / "Sleep goal" and values "7h 51m" (was "7:51") | 3-column Figma sleep card | values grow by 2–3 chars | Medium: "7h 51m" in the dot-matrix font is wider than "7:51" | spoken | check the golden; the value column is ~100 px |
| Stage legend "Light" (was "Core") | Sleep card legend | same | none | — | — |
| Plan headline "Good for a normal day" / "Still getting to know you" | PlanTile headline (wraps) | up to 26 chars | low (wraps to 2 lines) | 1.3× clamp | — |
| Plan eyebrow "Tonight · Your data may be out of date · Early estimate · without HRV · without breathing rate · Learning your Oura data" | PlanTile eyebrow, tileMicro, wraps | a worst case of about 110 chars | wraps to 3 lines at 320 px | 1.3× | Cap at 3 tags, and put "Learning your {app} data" first |
| Plan chips "Resting HR 61 bpm · usual 54 bpm", "Breathing rate 17.9 breaths/min · usual 15.3 breaths/min" | Wrap of pills | "breaths/min" adds 8 chars | **Medium**: one pill is wider than the card at 320 px + 1.3× (~250 px inner), so its text wraps **inside** the pill (2 lines) | 1.3× | acceptable. Or show the breathing-rate unit as "/min" only inside chips |
| New action chips ("Effort goal 14–17 · 9.2 so far") | under each action's why (new, D5) | new row | the card is ~40 px taller | 1.3× | Only the effort and sleep actions get chips, one each |
| Sleep action title "Try to be asleep by 11:35 pm" | PlanTile action title (wraps) | 12h adds " pm" | low | 1.3× | — |
| **All 12-hour times** | charts: sleep scatter y-axis, hypnogram x-axis, zone timeline x-axis, live session x-axis, diagnostics | "23:00" → "11:00 pm" (+3) | **High on chart axes**: 5 labels across ~300 px collide | charts don't scale text | 12h axis labels drop minutes: "11 pm", "2 am" (X18) |
| Bedtime card big number "11:35 pm" | F.n24 in the Sleep bedtime card | +3 chars | Medium: F.n24 "11:35 pm" is about 120 px, which fits the ~220 px text column | wraps in the card | put "pm" in a smaller span |
| Verification pill "Couldn’t check the answer, so here are just your numbers" | StatePill (one line?) | 49 → 56 chars | **High** if the pill is single-line: it wraps or ellipsises at 320 px | wraps | Revamp: let the pill wrap to 2 lines, or shorten to "Couldn’t check · showing your numbers" |
| Coach mode chip "With my data" (was "Uses your data") | top chip row | shorter | none | — | — |
| Settings segments "Sample data / My data" (were "Demo / Live") | SegmentedRange | +6 / +3 | Medium: each half is ~150 px at 320 px, and "Sample data" is ~95 px | segments at 2× may truncate | Revamp: allow 2-line segments, or use "Sample / Mine" |
| Profile segment "Not specified" | existing | unchanged | already tight | — | — |
| Journal chips "Worked out" (was "Trained") | chip Wrap | +2 | none | wraps | — |
| Need-bar legend "Usual need 7h 36m · Catch-up 3m · Extra after a hard day 12m · Slept 7h 1m" | Sleep need card legend (Wrap) | about +20 chars | wraps to 3 rows at 320 px | wraps | alternative: "Extra (hard day)" |
| Recovery breakdown header "What made your score" / "Points from each signal, out of its share" | section header (wraps) | similar | low | wraps | — |
| Time-in-zones rows "Zone 5 · Max" + "174–187 bpm" | Strain rows | the % text is removed: **shorter** | lower than today | — | — |
| Live zone line "Zone 3 · Moderate · 147–159 bpm" (was "Zone 3 · 70–80 % HRR · 147–159 bpm") | Live screen, bold amber | shorter | lower | — | — |
| Strain ⓘ and Methodology "In short:" paragraphs | sheets | new lines | none (scrolls) | scrolls | — |

---

## 6. Tests and goldens Phase B must update

### 6.1 Tests asserting exact strings (from a grep of `test/`)

**Phase B areas** (update together with the copy):

| Test file | What it pins | Proposed change that breaks it |
|---|---|---|
| `test/domain/today_planner_test.dart` | headlines ("Ready to push", "A normal day", "Take it easy", "Make it a rest day", "Still learning your normal"); summaries (:167-186, 235, 262, 291, 322, 368, 406, 424); action titles and whys (:294, 453-464, 503-530, 554-604, 654-655); chip labels ("Sleep target", "11% above usual"); calm regex (:703-728: keep passing) | §4.1 (everything) |
| `test/domain/fixtures/plan_numbers.dart` | `allowedNumbers` uses `PlanFormat.clock/when` with no flag | add the `use24h` variants (D2) |
| `test/data/today_plan_demo_test.dart` | ≤ 3 actions, ≤ 2 chips, the tonight phase, the state spread | should stay green. Re-run it, because the new action chips add numbers to check. |
| `test/domain/notes_test.dart` | "Calibrating your baseline", "No Recovery score" and other titles | §4.7 |
| `test/domain/baselines_test.dart`, `test/domain/baseline_origin_test.dart` | "New {metric} baseline" titles, "Calibrating your baseline" | §4.7 newBaseline and recoveryCalibrating |
| `test/data/any_app_test.dart`, `any_app_repo_test.dart`, `any_app_sqlite_test.dart` | "Recovery without HRV", "without HRV", "New … baseline" | §4.7 |
| `test/domain/recovery_without_hrv_test.dart` | "Recovery without HRV", "without HRV" | keep those words (the plan keeps them) |
| `test/data/hrv_ladder_test.dart` | "Sleeping HR (4 h mean)" | X20 / SO14. That label is the engine's `RecoveryComponent.label`, so keep it in the engine and change only the displays, or update the test |
| `test/domain/pulse_parity_health_monitor_test.dart:91` | `message.contains('outside your baseline')` | §4.6 engine alert → update to 'outside your usual range' |
| `test/domain/pulse_parity_recovery_test.dart` | component detail "% performance" / "without HRV" | X20 |
| `test/features/today/today_screen_test.dart` | "In range", "Above usual", "Data notes", "Good", "Sample data", "Learning your normal", "just now", "not a diagnosis", "New … baseline" | T04, T05, T13, X04 |
| `test/features/today/seeding_state_test.dart` | "Preparing 90 days…", "Training load" | TR07 if the tile title changes (it doesn't) |
| `test/features/recovery/recovery_screen_test.dart` | "Green ·", "Target ", "Baseline night", "Plews", "RMSSD", "Demo data" | R08, R10, R11, R12, R23, X14 |
| `test/features/sleep/sleep_screen_test.dart` | "Sleep target", "Debt after the night", "Debt share", "Strain boost", "How the target is worked out", "Performance" | S08, S12, S14, S15 |
| `test/features/strain/strain_screen_test.dart` | "TRIMP", "Finished …" | ST14, ST20, §4.5 |
| `test/features/trends/trends_screen_test.dart` | "Training load" (and the verdict words, if asserted) | TR07, TR14 |
| `test/design/components_test.dart` | "Provisional", "Good", "Last data", "Baseline night", "Not medical advice", "RMSSD", "Demo" | X01, X02, X04, X14, X16 |
| `test/design/design_api_test.dart`, `test/design/charts_test.dart` | "Band: your usual range", "Training load", "the band" | X09, R22, TR16 |
| `test/design/shell_routes_test.dart` | "Sample data", "Not medical advice", "Live" | X02 |
| `test/app/insight_card_test.dart` | "What Coach knows", "Coach messages", "Sample data" | IC01 ("Coach notes settings") |
| `test/data/coach/insight_service_test.dart` | "moved your recovery most", "Show coach" | §4.8 recovery headline, CT01 |
| `test/evals/cards_eval_test.dart` | "Sleep need" ref label | §4.8 ref labels |
| `test/domain/coach/tools_test.dart` | "A solid night" | kept |
| `test/domain/coach/policy_test.dart` | "…met your sleep need." (test sentences) | policy fixtures. Update only if the card text they mirror changes. |
| `test/features/privacy_copy_test.dart:29-45` | the `hcReadTypes` **names** | the names stay (O27). The descriptions aren't pinned. |
| `test/support/coach_fixtures.dart:93` | the fallback lead in the fixtures (stale) | align with prompts.dart (C07). This fixture feeds the coach goldens. |
| `test/evals/data/*.jsonl` (benign, golden_grounding, offline_router, policy_good) | user **questions** containing "strain target", "sleep debt", "sleep need" | no change needed. These are inputs, and the router keeps matching the old words (C36 adds aliases). |

**Revamp areas** (the revamp agent updates these alongside its screens):
- `test/features/coach/coach_chat_test.dart`: "Uses your data", "Checked against your data", "What was sent", "Report answer", "On-device", "Answered on this phone", "via ", "Ask Claude again", "For your safety".
- `coach_setup_test.dart`: "Use my data", "Paid keys only".
- `coach_settings_test.dart`: "Coach messages", "Show coach", "Use a backup model", "model requests".
- `coach_discuss_test.dart`: "Discussing", "AI can make mistakes".
- `test/data/coach/model_fallback_test.dart`: "Use a backup model".
- `test/evals/privacy_eval_test.dart`: "What was sent".
- `test/features/journal/journal_screen_test.dart`: "What applies this evening", "Correlation, not causation", "is associated with", "Emerging", "Solid".
- `test/features/live/live_screen_test.dart`: "Find my tracker", "HRV check", "Heart-rate recovery", "HRR", "RMSSD".
- `test/features/onboarding/onboarding_screen_test.dart`: "Try with sample data", "Connect Health Connect".
- `test/features/settings/settings_screens_test.dart`: "Data mode", "Hold to delete", "Algorithm version", "Enhanced mode", "Not configured", "Birth year", "Connect Health Connect".
- `test/features/diagnostics/diagnostics_screen_test.dart`: "Demo data".
- `test/features/methodology/*`.
- Data-layer strings also appear in `test/data/demo_seed_test.dart`, `sqlite_repository_test.dart` and `in_memory_repository_test.dart` ("Connect Health Connect", "Not configured", "Demo data").

### 6.2 Goldens that will change

Several goldens are **already stale** against the source (see the header note), so every screen golden needs a fresh record. Check each image before accepting it.

| Golden(s) | Owner | Why it changes |
|---|---|---|
| `screens/today_dark.png`, `today_full_dark.png` | Phase B | plan card (all text, new action chips), Recovery tile tag, vital titles, Strain caption |
| `screens/recovery_dark.png`, `recovery_full_dark.png` | Phase B | zone chip, meaning line, section headers, HRV-week card, history legend |
| `screens/sleep_dark.png`, `sleep_full_dark.png` | Phase B | hero values and labels, "Light", debt card, need legend, bedtime card, consistency subtitle, 12h axis |
| `screens/strain_dark.png`, `strain_workouts_dark.png` | Phase B | Goal wording, no TRIMP line, zone rows, recommendation line |
| `screens/trends_dark.png`, `trends_body_dark.png` | Phase B | week tile, training-load verdict and bands, band footnotes |
| `screens/coach_insight_cards_dark.png` | Phase B (card chrome) | "Ask about this" button; the card text comes from fixtures |
| `screens/coach_*` (answer, fallback, empty, remember, safety, discuss, waiting, setup, settings, memory) | Revamp | chips, pills, "What was shared", setup and settings copy |
| `screens/journal*`, `live_*`, `onboarding_*`, `settings*`, `sources*`, `methodology*`, `diagnostics*`, `privacy_dark.png` | Revamp | their own rows in §3 |
| `goldens/gallery_*_dark.png` (debug gallery) | Phase B | shared components ("Early estimate", "Sample data", "Learning your usual") |
| `goldens/shell_dark.png` | — | tab labels are unchanged; probably no diff |
| `goldens/figma/*.png` (figma_diff_test) | — | fixtures pass their own strings; they change only if a tile's **internal** label changes (none proposed) |

---

## 7. Decisions needed from the product owner

| # | Question | Recommendation |
|---|---|---|
| D1 | PRODUCT_PLAN §7 [U] says TodayPlan gives "a one-sentence why **with numbers**". The new rule is words first, with numbers in chips. | Numbers stay one tap away and on the chips. Amend §7 to "a plain one-sentence why, with its numbers on chips." |
| D2 | 12/24-hour time needs plumbing. TodayPlanner is pure Dart and can't read `MediaQuery`. | Add an optional `use24h` parameter to `TodayPlanner.plan` and `PlanFormat` (additive; today_plan.dart is a contract file), passed from `MediaQuery.alwaysUse24HourFormat`. Update the eval fixture the same way. **Coach answers stay 24h** for now: the verifier matches `CoachFormat.clock`, and changing it is a verifier change. |
| D3 | The bedtime the engine gives is **sleep onset** ("It is when to be asleep", sleep_widgets.dart:411-413), but you asked for "Go to bed by 11:35 pm". | Honest wording: **"Try to be asleep by 11:35 pm"**. Alternative: keep "Go to bed by" and subtract a fixed wind-down in the engine (a logic change). |
| D4 | Should the plan ever say "A very hard workout is fine today" (Recovery ≥ 85)? And are the example activities OK? They are general guidance, not measured. | Yes to both. They are plain, and the ⓘ can say "Examples only." |
| D5 | Render `PlanAction.evidence` as small chips under each action (the effort goal and sleep goal chips). It makes the card taller by about 40 px. | Yes. It's the only way to keep the range and sleep numbers on Today once the words drop them. |
| D6 | Brand mentions that must stay: legal non-affiliation lines, the trademark line, the plan-mandated "isn't WHOOP’s Recovery / Oura’s Readiness" note, and real source-app names in setup steps. Proposed removals: "Not WHOOP’s formula" as a headline and chip (onboarding, Methodology). | Replace with "Our own formula". Keep the legal lines in Settings, Licences and Methodology. |
| D7 | Coach mode names: "Use my data" (setting) vs "Uses your data" (chip). PRODUCT_PLAN §3.4 names them "Use my data" / "General only". | **"With my data" / "General only"** everywhere. Wording-only for consent. |
| D8 | Journal: §7 says correlations "read 'associated with'". Plain alternative: "After alcohol, your next-day Recovery was 25 points lower", with "A link, not a cause" beside it. | Option A (plain), with the footer kept. |
| D9 | Consent and privacy wording edits (CS03–CS15, PR02–PR08, O14). | Treat as **wording-only**: don't bump `consentVersion`, but bump the privacy "Last updated" date. The product owner confirms, since the privacy policy is legal text. |
| D10 | Cost display: "≈ $0.02–0.05" vs "about 2–5¢". | "about 2–5¢" (people say cents). Keep $ if the user base isn't US-centric. |
| D11 | On Low days the plan shows both "Keep any workout easy today" and "Take it slow today". | Drop the recover action when an effort action is present (a logic change in today_planner.dart:497). |
| D12 | Ownership gaps: (a) the chat-facing `CoachCopy` constants and `prompts.dart` `fallbackNote` / `noFactsNote` (Phase B's files, but coach chat strings, which are now Revamp's); (b) the Live scan, recording and HRV-check stages (same files as Live intro and summary); (c) data-layer status strings shown in Sources and Sync log (X21, X22, D06); (d) `offline_client.dart` answer templates. | (a) Revamp edits the chat-facing CoachCopy values; Phase B edits the rest of copy.dart. (b) Revamp. (c) and (d) Phase B at the source, since they're data-layer files. |
| D13 | One goal rule. Today shows a range (target ± 1.5). The Strain screen shows the single target and judges "on target" within ±1. | Show the **range** everywhere a goal appears ("Goal 14–17"). Judge on target within the range. Keep the single number in ⓘ and Methodology. |
| D14 | "Sleep target" was renamed from "sleep need" in §7 (2026-09-29). The new proposal is **"sleep goal"**. | "Sleep goal": plainer, and it avoids claiming a physiological need. |

---

## 8. Engineering notes for Phase B (logic that depends on copy)

1. **`sortNotes` matches note titles** (today_view_model.dart:794-795: `startsWith('New ') && endsWith('baseline')`). Renaming newBaseline titles breaks the card routing. Key on the note instead: add a `kind` or use `metric` plus a flag, or match the new title with a shared constant.
2. **`PlanTile.basis` matches summary text** (plan_tile.dart:41: `!p.summary.startsWith('Re-learning')`). Replace it with a check on whether the summary names `relearningSource`, or add an additive bool to TodayPlan.
3. **`sortNotes` uses `Notes.assumedMaxHr(0).title`** (today_view_model.dart:763,789). Delete it along with `assumedMaxHr`.
4. **`headlineFor(DayState)`** is public and "copy.dart may restyle, not reword" (today_planner.dart:586). Add `headlineFor(state, {phase, noScore})` alongside it.
5. **The on-device router** keys on words (offline_client.dart:198-256). When suggested questions change (C36), add aliases so they route the same way.
6. **The `JournalFactor` label is matched by the coach router** (offline_client.dart:708-716). Add "worked out" when "Trained" is renamed.
7. **`HealthMetricKind.label` and `.unit` feed coach refs** ("Resting HR · Mon 28 Sep"). Changing them changes coach source-chip labels too (X19). `answer_text.dart:40` already handles "/min" and "br/min"; "breaths/min" also ends in "/min" and matches.
8. **Commit rules for Phase B** (relayed by the coordinator): no `Co-Authored-By` trailer and no AI attribution. Gate every flutter command with `bash /d/dev/airlog-build/gate.sh acquire copy` / `release copy`. C: is nearly full, so write no large files there.

---

## 9. Counts

Rows with a proposed change, by priority. "Keep"-only rows are excluded. §4 template rows are counted in §3 through the rows that point to them.

| Priority | Rows with a change | Meaning |
|---|---|---|
| **P1** | 101 | confusing, jargon or dishonest |
| **P2** | 163 | clunky |
| **P3** | 64 | polish |
| **Total** | 328 | plus 74 rows reviewed and kept as they are |

The §4.7 notes (28 templates), §4.8 cards (18 parts) and §4.1 TodayPlan (headline, 11 summaries, 8 chips, 6 action families) are counted once each, through T18, IC03, X25 and the §4.1 pointer rows.
