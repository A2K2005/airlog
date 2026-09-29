# Airlog end-to-end review

Reviewed 2026-09-30 at commit `aca8f35`. Review scope: product plan, Android configuration, onboarding and screens, ingestion, persistence, source selection, scoring, live workouts, coach, export/deletion, tests and operational documentation.

**Historical baseline audit.** Findings and line references below describe `aca8f35`, before remediation. Current implementation, regression evidence and unresolved release gates are tracked in [LAUNCH_READINESS.md](LAUNCH_READINESS.md). Do not interpret the original tooling limitations or open findings below as the present working-tree status.

## Review tracker

Scope update: the deeper pass is Android-only. iOS is excluded from the investigation and recommended work.

| Pass | Status | Evidence |
|---|---|---|
| Initial product/data/engine/coach review | Complete, source-level | Findings below; runtime limitations recorded |
| Deeper persistence, background sync and state ownership | Complete at source/protocol level | D01-D09 and D19 below; Android crash/race reproduction pending |
| Deeper scoring/provenance/recomputation contracts | Complete at source level | D10-D12; earlier baseline and verifier findings challenged and retained |
| Deeper coach/privacy/cache boundaries | Complete at source level | D13-D18; no real cloud transmission performed |
| Architecture tests and independent probes | Complete | 215 Dart files / 1,012 internal import-export edges; three SQLite protocol probes and one timezone model reproduced the identified weaknesses |

Finding states in this document mean: **confirmed-source** = traced through active code; **probe-confirmed** = a focused executable probe demonstrates the specified property; **runtime-pending** = device/application reproduction remains necessary; **corrected** = earlier wording was revised after counterevidence. None means fixed unless a later implementation explicitly records it.

## Verdict and evidence limits

Airlog is a substantial Android prototype with a clear product idea: explain wearable measurements and give one useful answer each morning. Its strongest work is the shared deterministic engine, source provenance, explicit demo mode, calibration, and explanations. Its main weakness is that uncertainty is not consistently carried through ingestion, calculations, recommendations and privacy promises.

I would use it for controlled evaluation, but would not yet treat its daily guidance or cloud coach as dependable for public users. Fix the trust defects below before adding more features.

Three agents independently reviewed data integration, domain calculations, and UI/coach; the primary reviewer cross-checked major paths and reviewed live workouts and build readiness. Findings are based on current source. Examples describe deterministic source behavior or race scenarios, not fresh device reproductions.

No Flutter/Dart/ADB commands were available on PATH, the documented `D:\dev` toolchain was absent, and the required Subway Ticker Grid font was missing. No app build, test suite, emulator session, real wearable session, OAuth flow or cloud-model call was run. Existing golden images and the older QA report are historical artifacts, not current runtime proof. No application code was changed.

## What the app actually does

1. A fresh install offers Health Connect access or explicit sample data. Live mode is the repository default. The dashboard is gated behind the onboarding decision.
2. Health Connect provides per-type history and changes. Optional Google Health OAuth adds enrichment/fallback data. Bluetooth provides live HR sessions. Demo data is stored separately from real data.
3. Raw records enter SQLite. HR is also reduced to minute buckets. Source selection chooses one app per metric, with persisted source segments and manual overrides.
4. The resolver builds daily records. The domain engine computes sleep, recovery, strain, baselines, health-monitor status and related outputs. TodayPlanner turns these into a daily plan.
5. Today, Sleep, Strain and Trends are main tabs. More contains Journal, Live, Coach and Settings. A home-screen widget shows score snapshots.
6. Journal compares tagged evenings with next-day Recovery. Coach offers an offline path and optional Claude/Gemini with the user's own key, tool-based data retrieval, verification and policy checks.
7. Settings exposes profile, source controls, diagnostics, CSV/JSON export, methodology and deletion.

Implemented screens and classes should not be confused with field-validated capability. The README says the band has not yet been used for validation. Google payload mapping explicitly contains unverified assumptions. iOS and Takeout import are not implemented. Pulse Age computation is deliberately disabled in v1 despite remaining classes, tests and older planning references.

## Highest-priority defects

### 1. P1: Failed Health Connect reads can become permanent gaps

`app/lib/data/sync/hc_sync.dart:193-211` catches failed read chunks without returning failure/completeness to the caller. Full backfill still saves a changes token at lines 146-148. Incremental sleep rereads likewise advance the token at line 415 after `_readWindow` fails.

**Trigger:** one initial HR/RHR read fails, or a rewritten sleep session cannot be fetched once. The next sync processes later changes; unchanged missing history is not automatically retried. Some partial failures are logged as `ok` if other chunks returned data.

**Fix:** persist failed windows and retry them, or withhold acknowledgement until required reads succeed. Test failure followed by a successful next sync, not just failure logging.

### 2. P1: Google decode failure deletes valid stored data

`app/lib/data/sync/ghapi_sync.dart:75-107` replaces stored windows before checking whether a nonempty provider response decoded to zero rows. The error is only logged afterward. Since `failures` increments only for thrown exceptions, the success watermark still advances at lines 194-195.

**Trigger:** a response contains points but its field names differ from guessed mappings. Existing measurements are removed and later sync narrows its reread window. This is especially relevant because `ghapi_mapping.dart:1-18` explicitly documents unverified payload shapes.

**Fix:** validate decoding before destructive replacement, retain the last valid snapshot on malformed responses, and distinguish empty, partial, unsupported and failed reads.

### 3. P1: Missing sleep stages are invented

`app/lib/domain/engine/sleep.dart:208-210` changes an absent stage map into all-Light sleep. `app/lib/features/sleep/sleep_screen.dart:348-351` labels that as Core and defaults absent stages to zero. `sleep_view_model.dart:104-115` derives restorative percentage from those values.

**Example:** eight hours of sleep with no stages becomes eight hours Core, zero Deep, zero REM and 0% restorative. Unknown measurements become unfavorable-looking measurements.

**Fix:** preserve unknown staging; show duration normally and mark stage breakdown/restorative percentage unavailable.

### 4. P1: Low-confidence Recovery can produce “Ready to push”

`app/lib/domain/engine/recovery.dart:97-107` explicitly assigns low confidence to low input coverage. `today_planner.dart:225-242` chooses the ready state from score/calibration/freshness without reading confidence or coverage. Lines 357-399 can then recommend an effort range.

**Source-derived example:** an established HRV baseline of 50 ms and current 55 ms, with no RHR, sleep or respiration, can yield approximately 97 Recovery, 40% model coverage and low confidence, yet “Ready to push” and a 17-20 strain range. The numbers are internally computed correctly; the recommendation overstates their support.

**Fix:** make input coverage, confidence and metric-specific freshness constrain recommendation strength. A detail-screen caveat is insufficient when the headline recommends pushing.

### 5. P1: The coach can validate a user's mistaken number as a measurement

`app/lib/domain/coach/verifier.dart:993-998` accepts numbers found in the question before checking cited measurement evidence. Memory numbers have a measured-metric restriction; question numbers do not.

**Example to reproduce in a regression test:** question “Was my Recovery 99%?”, stored Recovery 58%, answer “Your Recovery is 99% [r1].” The numeric support path accepts 99 because the user supplied it, even if r1 contains 58. This is a verifier bypass, not a claim that a live model always produces that answer.

**Fix:** allow attributed user statements to repeat user numbers, but require stored evidence for claims about measured metrics. Test numeric leading questions and contradicted citations.

### 6. P1: “Delete all data” leaves app-owned health files

`app/lib/features/settings/settings_screen.dart:185-186` promises to erase everything stored on the phone except settings. `health_repository_impl.dart:776-779` writes exports and line 893 writes diagnostic dumps under application documents. `wipeData` at lines 979-998 deletes database content but never removes these files.

**Impact:** raw health exports and diagnostic data remain in app storage after the success message. Copies the user shared externally are a separate issue; Airlog can delete its own originals.

**Fix:** include app-owned exports and diagnostics in deletion, define credential/settings retention explicitly, and verify the filesystem as well as tables. Also coordinate deletion with active sync: the existing `_inflight` lock serializes sync calls within one repository, but deletion does not await/cancel those writes and the worker has its own repository. A pending fetch can repopulate data after deletion; this race was identified in source, not reproduced on a device.

## Other material correctness and product gaps

| Priority | Finding and concrete impact | Evidence / fix direction |
|---|---|---|
| P2 | Granting history later does not import the newly accessible history. Enabling context can miss existing weight records. | `hc_sync.dart:98-115` keys backfill only on type-list changes; history/context are absent. Track capability changes and schedule the missing window. |
| P2 | Upstream corrections/deletions to HR older than 14 days can leave obsolete minute buckets and scores. | `db/stores.dart:12`; `sqlite_stores.dart:448-482,265-276`. Raw record identifiers are pruned while buckets remain. Preserve enough provenance to invalidate or reread affected days. |
| P2 | Google HR fallback can be fetched and then ignored. | `ghapi_sync.dart:155-165` fetches when HC has <=60 minutes; `resolver.dart:511-513` accepts any nonempty HC day. Use one selected-source coverage rule for both fetch and resolution. |
| P2 | An app with frequent manual HRV checks can beat a usable nightly source, then provide no eligible HRV. | `source_choice.dart:392-394` counts spot readings for coverage; `resolver.dart:234` excludes them afterward. Select sources using eligible nightly data. |
| P2 | Switching devices/HRV definitions can create a significant “improvement” with no physiological change. | `trends_view_model.dart:274-289` computes trend across the whole series while only drawing source-change markers. Calculate headline trends within comparable segments. |
| P2 | Training-load classification treats sparse and unfinished HR days as valid activity evidence. | `trends_view_model.dart:363-372`; `load_and_trends.dart:75-85`. Unlike the strain chart, ACWR includes today and does not gate partial coverage. Seven under-recorded days can look like detraining. |
| P2 | Live HR zones and live strain can use different max-HR assumptions. Missing RHR silently starts at 62 bpm. | `live_view_model.dart:132-133,319-336,499-504,568-576`; `engine.dart:150`; `day_engine.dart:132-134`. Display can use a loaded observed max while live strain recomputes age-30 max from an empty profile. Pass the same explicit anchors and provenance through both calculations. |
| P2 | Cloud privacy copy promises more than the implementation guarantees. | `app/copy.dart:265-269` says anything naming the user is never sent; `coach_service.dart:196` sends their question verbatim. A name typed into chat is sent. Describe data actually transmitted and any actual redaction, not an absolute identity promise. |
| P2 | Coach budget language and recovery instructions are misleading. | Each model call is metered (`coach_repository_impl.dart:360-367`), but `coach_service.dart:384-390` calls the limit questions and says it can be raised in Settings, where no limit editor exists. A question near the limit can send a request, then fail on its tool follow-up with “nothing was sent” (`coach_repository_impl.dart:293-305`). Distinguish calls, questions, partial transmission and actual available controls. |
| P2 | Adult-only positioning is not consistently enforced. | `features/settings/profile_view_model.dart:49` permits ages ten and above; `domain/coach/safety.dart:177` says scores/coach are built for adults. `coach_service.dart:94-116` checks age statements in the current question and requires adult confirmation only for cloud use. A known minor profile can receive ordinary offline coaching. Decide supported ages and apply that decision across profile, scoring and coach. |
| P2 | A health warning can count nonconsecutive dates as consecutive days. | `day_engine.dart:677-696` passes only existing records; `health_monitor.dart:199-218` counts adjacent array entries. Elevated Sep 27 and Sep 29 with no Sep 28 record can become a two-day streak. Break streaks on missing dates. |
| P2 | Wake-time averaging fails across midnight. | `sleep.dart:123-125` takes a plain arithmetic mean: 23:30 and 00:30 become noon. Use circular time handling and an explicit shift-work policy. |
| P2 | “Export everything” is narrower than a portable archive. | `health_repository_impl.dart:765-784` exports the current mode/enabled sources. `export.dart` omits coach conversations/memory, profile/source configuration, HRV recording method and minute-HR origin metadata; JSON is resolved data/results/journal, not complete raw records. No import/restore path exists. Define readable export vs restorable backup clearly. |

Paths in this table are under `app/lib/` unless stated otherwise. P1 means resolve before depending on real-user advice/privacy claims; P2 means material correctness or usability debt, not cosmetic polish.

## Assumptions that need explicit product decisions

- **Model accuracy:** parity with Pulse proves the port matches a reference, not that Recovery or target strain predicts an individual's readiness. The plan itself acknowledges fixture-only validation. Establish real-data evaluation before presenting these as dependable recommendations.
- **Sleep need:** engine defaults include 456 minutes baseline, 30% debt repayment, a 300-minute debt cap and up to 45 minutes strain boost (`engine.dart:40-53`). These are model defaults, not an individually measured requirement. The UI's “your target” should explain that basis; personal sleep-need configuration is absent.
- **Baseline age:** `baselines.dart:151-176` uses the last 30 comparable observed values, not necessarily 30 calendar days. A long gap need not reset calibration. Decide when old observations stop representing current normal.
- **Observed maximum HR:** the fallback uses a robust observed peak over 90 days. It is labelled, but observed activity may never have reached a meaningful maximum. Explain the uncertainty and keep its use consistent across daily/live scoring.
- **Night schedule:** 18:00 night assignment and the 05:00 morning boundary assume a conventional schedule. Shift work, travel and unusual sleep timing need deliberate behavior and tests.
- **Journal inference:** minimum group sizes, confidence intervals and Holm correction are useful. They do not control correlated habits, illness, measurement changes or self-selection. Unticked factors on saved entries mean absent. Keep associations distinct from causal explanations.
- **Data-source compatibility:** supporting an app origin does not prove it writes every needed metric, with the expected sampling density and metadata. The real-device matrix remains open.
- **Cloud behavior:** local scoring is private by default, but enabling a cloud coach sends questions/history and selected data to the chosen provider. The opening product and release statements need this exception consistently represented. The release draft currently does not account for coach transmission.
- **Conversation behavior:** General-only mode drops prior conversation from requests (`coach_service.dart:122`) despite copy saying conversation history is sent. Clarify that mode's follow-up behavior. Answer reporting is explicitly copy-to-clipboard for manual sharing, with only a temporary in-memory flag, not a durable feedback workflow.

## Build, release and validation gaps

- Fresh checkout requires an untracked font declared at `app/pubspec.yaml:92`. The README documents personal-use licensing and a separate publication requirement. Make the setup dependency explicit or provide an appropriately licensed default.
- Toolchain configuration embeds another machine's `D:\dev` paths, including JVM temp paths in `android/gradle.properties:4-5`. Reproducible setup needs configurable paths.
- Release builds use the debug signing configuration (`android/app/build.gradle.kts:39`). Production signing is unfinished.
- README Enhanced-mode setup supplies only the Dart OAuth client ID. Native manifest redirect defaults to `app.airlog.oauth`, while Dart derives `com.googleusercontent.apps.<id>`. Native and Dart configuration must agree (`google_auth.dart:38-43`, `android/app/build.gradle.kts:32-33`). The happy-path setup instructions omit that requirement.
- No checked-in CI workflow or integration-test suite was found. There is substantial unit/widget/eval/golden coverage, but no new pass result from this review.
- Existing grounding evals explicitly use offline responses and scripted hallucinating clients (`test/evals/grounding_eval_test.dart`); planted demo journal effects are marked circular. These are valuable harness checks, not measured real-model or real-user accuracy.
- `docs/QA_REPORT.md` describes an older build. Current source contains fixes for several listed issues, including separate worker DB connections, onboarding gating and widget stale-date labeling. Reconcile the report and retest; do not carry its old P0 forward as a current defect without evidence.
- `docs/DAY1_CHECKLIST.md` still references estimated strain fallback, while the current README says no strain score without heart rate. `PLAY_RELEASE.md` retains old permission/feature assumptions. Update operational docs from the shipped behavior.

## Recommended execution order

1. **Make stored evidence reliable:** failed-read retry/acknowledgement, decode-safe replacement, source eligibility, fallback coverage, old-record correction.
2. **Make conclusions honest:** unknown sleep stages, confidence-gated Today advice, shared live/daily HR anchors, comparable trends and complete-day load metrics.
3. **Close privacy and coach defects:** verifier question-number bypass, accurate transmission copy, complete deletion with sync coordination, budget UX.
4. **Make validation reproducible:** font/toolchain setup, corrected OAuth instructions, automated tests and release signing configuration.
5. **Run actual device acceptance:** fresh install; deny/regrant and history-only grants; one failed read then recovery; sleep rewrite; old HR deletion; multiple origins; overnight/midnight/timezone changes; foreground/background overlap; Bluetooth loss/reconnect; delete during sync; inspect retained files; near-budget cloud question and adversarial numeric prompts.

The highest-value next milestone is one fully proven path from a real night's data to an appropriately qualified morning recommendation, including correction and deletion. Additional Android integrations, Takeout and more coach features can follow that evidence. iOS is out of scope.

## Deeper Android architecture review: pass 2

### What appears to have been mixed

There is evidence of inconsistent contracts across features, but no basis for attributing individual defects to Claude or another author. The current source combines decisions from different product iterations:

| Earlier assumption still active somewhere | Later rule active elsewhere | Observable conflict |
|---|---|---|
| Missing RHR uses 62; absent age uses 30 | Daily strain uses explicit %HRmax/observed-max modes | Live/day scoring differs; daily timeline cannot render the new zone mode |
| A metric's current source tells us whether it is shareable | Scores depend on earlier days, baselines and carried sleep debt | Cloud filters miss restricted inputs to derived outputs |
| Repository-local revision means data changed | A second repository updates SQLite in WorkManager | The open dashboard can miss background changes |
| Successful raw ingestion/checkpoint equals progress | Scores are a separate persisted computation | Process death can leave acknowledged data with permanently old scores |
| Source identity is a raw definition/app/device string | Missing device metadata should inherit the last known device | Recovery, Readiness and chart markers disagree about comparability |
| Clock access is dependency-injected | Time passing should change Today even without new data | No event invalidates the stable clock function at daily boundaries |
| Consent is checked once per question | One question can involve multiple network sends | Withdrawal during a tool loop does not prevent later requests |

These are semantic and state-management problems. An independent import scan found **zero direct violations** of the documented domain/data/features/design boundaries across 215 Dart files and 1,012 internal import/export edges. Moving more classes into folders would not address the failures below.

### Stable issue tracker

All issues are open. `CS` means confirmed-source; `PP` means the described SQL protocol or mathematical model was also reproduced independently. Neither means the Flutter/Android flow has been executed. These IDs are for this deeper pass; the first-pass findings above remain open.

| ID | Priority | State | Issue | Closure evidence required |
|---|---|---|---|---|
| D01 | P1 | CS + PP | Raw/checkpoint commit can survive without its score update | Kill between ingest/checkpoint/recompute, restart, verify historical correction recovers |
| D02 | P1 | CS | Old sync can overwrite newer profile/source configuration | Delayed fetch + settings change; all committed results use current generation |
| D03 | P2 | CS + PP | DayBundle can join measurements and scores from different commits | Interleaved writer between reads cannot produce mismatched bundle |
| D04 | P2 | CS + PP | Earliest-day deletion leaves the old cached day | Delete the only earliest raw record; day disappears from detail/trends/export |
| D05 | P2 | CS | Worker updates do not invalidate foreground providers | Retained foreground container sees external DB commit after resume/refresh |
| D06 | P2 | CS | Worker reports success for swallowed failures | Dispatcher outcome differentiates success, partial and retryable failure |
| D07 | P2 | CS + model | Timezone changes move stored resolved HR timestamps | Write in one timezone/read in another; absolute sample instants remain consistent |
| D08 | P2 | CS | Incremental HC ingestion loses device metadata even foreground | Same-app device replacement is detected from real adapter fixtures |
| D09 | P2 | CS | HRV shape changes fail to invalidate old resolved days | Incremental/full equivalence across samples-to-single shape transition |
| D10 | P2 | CS | Effective provenance differs between Recovery, Readiness and Trends | A/null-device/B fixtures produce consistent membership and switch markers |
| D11 | P2 | CS | No-RHR zone mode renders high HR as Rest | %HRmax score, chart colors, legend and explanation use identical thresholds |
| D12 | P2 | CS | Rejected HR anchors become measured zero strain | Unusable max/RHR pair yields unavailable, excluded from load/trends |
| D13 | P1 | CS | Consent withdrawal leaves an active cloud loop authorized | Withdraw during pending model response; zero further network sends |
| D14 | P1 | CS | Daily cloud filter misses historical derived-data dependencies | Restricted yesterday/clean today cannot transmit restricted derived facts |
| D15 | P1 | CS | Weekly Discuss checks only the final day of an aggregate | Mixed-source week with clean Sunday is filtered over all contributing days |
| D16 | P2 | CS | Sample chat history replays as ordinary real-data context | Demo-to-live transition preserves or excludes sample provenance in transcript |
| D17 | P2 | CS | Failed key deletion is announced as successful | Secure-store deletion failure produces an accurate partial-failure state |
| D18 | P2 | CS | Time-dependent screen state lacks guaranteed invalidation | Retained screen crosses 18:00/05:00/midnight/staleness with no data mutation |
| D19 | P2 | CS | Google fetch has no application deadline and can hold all sync | Never-completing fetch is bounded/cancelled; subsequent sync can proceed |

### D01: No durable pending-recompute state

HC stores its changes token at `data/sync/hc_sync.dart:415`, before the coordinator recomputes scores (`data/sync/sync_coordinator.dart:72-86`). Dirty dates are only an in-memory set. `_needsRecompute` (`data/repositories/health_repository_impl.dart:300-308`) checks algorithm version and whether the latest result exists, not whether raw data changed since computation.

**Failure:** a corrected old night is persisted, its changes token advances, then Android kills the worker. Restart accepts the old result because it has the current algorithm version. Empty subsequent changes do not repair that old date; a later new day can reuse stale historical records.

**Required contract:** raw changes and a durable invalidation marker commit together. Scores acknowledge that marker only after successful computation. Algorithm version, data revision and configuration revision are different concepts.

### D02: Old work can overwrite a successful settings change

`health_repository_impl.dart:471-490` captures profile/enabled sources before awaiting providers. `saveProfile` at lines 755-760 and `setSourceEnabled` at lines 619-633 separately persist settings and recompute. The old sync can later commit using its captured configuration.

**Failure:** save birth year B while a sync using A is waiting. The UI confirms B, then the older sync writes scores calculated with A. Disabling a source has an equivalent race. `_inflight` is only a per-repository sync guard, not a shared mutation contract.

**Required contract:** a persisted configuration generation or serialized writer. Before committing, stale computations must be discarded or recomputed with the current settings. Include the worker, profile, source pin/enable, deletion and live-session paths.

### D03: Atomic writes do not guarantee a coherent read

`health_repository_impl.dart:356-360` awaits `app.record(_mode,date)` and then `app.result(_mode,date)`. `_range` similarly fetches records and results in separate queries (`:412-419`). A writer can commit between them. `DayBundle` has no snapshot identity check. `_mode` itself is read again across awaits.

**Failure:** the detail screen receives the old HRV record with the new Recovery result and displays an explanation that cannot produce its score. This can happen even though `SqliteAppStore.putDays` correctly wraps writes in a transaction.

**Required contract:** read records/results from one snapshot, with mode captured once and an immutable result/data/configuration identity. A joined read or read transaction is a smaller change than replacing the repository architecture.

### D04: Deletion boundary is incorrectly narrowed

`score_pipeline.dart:250-252` clamps `keepFrom` to the new raw span's earliest date. Its final write then clears only from that clamped date (`:279-284`).

**Failure:** Sep 1 and Sep 2 exist; delete Sep 1's last raw record. Dirty date is Sep 1, but new raw span starts Sep 2. Sep 1's stored record and result survive. Clearing and recomputing need separate start boundaries: invalidate from the deleted date, resolve from the first remaining raw day.

### D05-D06: Background persistence, foreground refresh and job success are disconnected

The revision counter/stream belongs to one repository instance (`health_repository_impl.dart:131-132,323-325`). Riverpod caches on it (`app/providers.dart:24-41`). WorkManager opens a separate DataModule. When that worker consumes changes, the foreground's next sync can be empty and skip `_bump` (`health_repository_impl.dart:508-509`). Pull-to-refresh calls that same sync path. The screen can remain stale while sync status updates.

Separately, `background.dart:31-34` returns success after `backgroundSync`, but repository `_sync` catches failures into local status (`health_repository_impl.dart:512-521`). The worker then closes that status-owning instance. The scheduler cannot distinguish these failures from success; an exception before log persistence may also lack a durable record.

**Required contract:** persist an observable data revision and typed sync outcome. Foreground resume/refresh must compare persisted revision, even when it fetched nothing. Worker retry decisions must consume the outcome, not the absence of an exception.

### D07: Two persisted HR representations disagree after travel

Raw `hr_day` saves an absolute `day_start`; resolved `day_record.hr` saves a blob without its epoch anchor (`data/db/schema.dart:130-138`, `sql_rows.dart:115-124`). `hr_buckets.dart:119-127` decodes the latter using the current timezone's midnight.

**Failure:** a 09:00 India sample originally at 03:30 UTC becomes 09:00 UTC when read after moving the phone to UTC. Stored sleep/workout timestamps retain their actual instants. Raw re-resolution and cached history therefore disagree, including during incremental computation.

**Required contract:** preserve the original absolute blob anchor and define whether historical civil-day labels remain fixed or are intentionally rebucketed. Do not silently reinterpret offsets.

### D08-D10: There is no single resolved provenance contract

**D08:** full HC reads enrich metadata using `_withMeta` (`data/services/health_connect/health_connect_service.dart:291,321-334`). Incremental changes use `recordFromPoint` directly (`:407`), without device enrichment. This also happens in foreground. Baselines carry the last known device, so a same-app switch from one wearable to another can continue its old baseline indefinitely. Tests feeding pre-enriched `HcRecord` fakes miss the adapter boundary.

**D09:** HRV shape is persisted as a current global property. `ScorePipeline.updatePlans` updates it, but `OriginPlan.firstDifference` compares origins only (`data/resolver/source_choice.dart:102-109`). A samples-to-single transition changes resolver meaning without widening the dirty range. A later full recompute can change historical HRV/definitions that an incremental recompute left untouched. Store dated shape segments or invalidate the affected history explicitly.

**D10:** `day_engine.dart:706-709` matches Readiness's rolling window against raw provenance, while `Baselines.values` matches carried-device provenance (`baselines.dart:157-161`). A/null/B sequences can include B's unlabelled readings in A's rolling window but exclude them from A's baseline. Trends also compares raw baseline keys (`features/trends/trends_view_model.dart:207-218`), so A/null/A produces two switch markers even though the engine correctly treats it as A throughout.

**Required contract:** resolve definition/app/device/shape once and pass that effective identity to baseline selection, calibration, readiness, trend markers, source selection and privacy logic. Preserve “unknown” explicitly until justified, rather than giving each consumer a different fallback.

### D11-D12: Strain's result type hides important calculation states

**D11:** daily scoring supports %HRmax when RHR is missing (`domain/engine/strain_fallback.dart:155-158,208-213`). The view model instead gives the HR timeline no thresholds (`features/strain/strain_view_model.dart:160-183`). `ZoneTimeline.zoneOf` treats that empty list as Rest (`design/charts/zone_timeline.dart:60-65,101-111`). At max HR 180 and current HR 170, the engine produces zone 4 while the timeline says Rest. The zone explanation also still describes HR reserve.

**D12:** `StrainEngine.accumulateSeries` rejects max HR <= RHR + 20 by returning an empty accumulator (`domain/engine/strain.dart:212-213`). The caller nevertheless labels it a measured `hrZones` score of zero (`strain_fallback.dart:181-203`). With RHR 60 and observed max 70, sufficiently dense data can therefore produce an apparently valid zero, which enters load/trends.

**Required contract:** a typed scoring basis containing method, actual thresholds, anchors, validity and coverage. Distinguish valid zero, unknown and rejected calculation. Charts should render the engine's thresholds, not independently reconstruct them.

### D13: Cloud consent is a startup check, not a send-time condition

`domain/coach/coach_service.dart:85-118` captures settings and a provider client holding the API key. Each subsequent tool-loop request (`:201-219`) checks budget but not current consent, provider, mode or key state. Setup remains reachable while sending (`features/coach/coach_screen.dart:265`). `withdrawCloud` deletes stored keys and selects offline, but cannot remove the key already held by that client.

**Failure:** a first model call is pending; the user withdraws consent; its response arrives asking for data tools; the next request can still send those results. Switching to offline also makes `usageToday()` return null, so the old loop's budget gate becomes weaker.

**Required contract:** snapshot a consent/configuration generation and revalidate before tool execution and every network send. Abort additional work after revocation. Already transmitted data cannot be recalled, but later requests must stop.

### D14-D15: Cloud restrictions follow current records, not derived facts

**D14, daily:** today's sleep need/performance/debt uses prior strain and carried debt (`day_engine.dart:238`, `sleep.dart:162-177`); Recovery then uses sleep performance (`day_engine.dart:272`). Coach only checks current-record provenance before exporting those results (`domain/coach/tools.dart:699,932-950,1181,2194`). Restricted Google Health data from yesterday can therefore influence facts sent today when today's direct source is Health Connect.

**D15, weekly:** weekly insight templates aggregate seven days but their aggregate refs omit contributing dates (`data/coach/insight_templates.dart:722-819`). Discuss checks the card's date plus the refs' explicit dates (`domain/coach/tools.dart:2039`), effectively Sunday alone. Restricted data Monday-Saturday can influence a card transmitted when Sunday is unrestricted.

**Required contract:** derived facts must carry dependency lineage, including contributing dates and restricted sources. Apply eligibility to that lineage or compute a separate permitted derivation. A current-day source label cannot enforce a historical aggregate policy. These are code paths that can violate Airlog's own disclosure, not claims of observed real-world transmission or legal conclusions.

### D16-D17: Stored state is not the same as the user's current privacy choice

**D16:** assistant messages store a `sampleData` flag, but `_history` strips down earlier answers to plain conversation text without checking that flag (`domain/coach/coach_service.dart:489-499`). Conversations have no demo/live partition. A cloud conversation about sample workouts can be reopened in live mode and replayed as ordinary personal context. Numeric verification does not reliably protect qualitative conclusions. Isolate chats by data mode or preserve/enforce sample provenance in replay.

**D17:** `features/coach/coach_providers.dart:84-87` swallows secure-key deletion errors. The UI still says the key was deleted (`coach_settings_screen.dart:80`) and updates its key-presence map to false. Saving offline mode may succeed while credential removal failed. Report those operations separately and verify storage state before claiming removal.

### D18: An injectable clock is not an observable clock

`app/providers.dart:80` exposes a stable function. Today reads it during provider rebuilds (`features/today/today_view_model.dart:211,825`), while tabs remain mounted in an IndexedStack. `data/data_module.dart` does have an app-resume listener, but it only delegates to repository sync logic; it does not guarantee clock-dependent providers are invalidated when sync is skipped or produces no revision.

**Failure:** a retained screen crosses 18:00/05:00/midnight or a freshness threshold with no data event. Guidance can remain in the previous phase. Add a shared boundary/lifecycle signal and test with an existing provider container, not only separate builds at pinned times.

### D19: A hung enrichment request can hold the entire sync flow

`data/services/google_health/google_health_client.dart:84-93` awaits HTTP without an application timeout. Its source wrappers and `GhSync` add no deadline. All callers reuse the repository's `_inflight` future (`health_repository_impl.dart:424-426`), and Google fetch precedes recomputation in `sync_coordinator.dart:68-86`.

**Failure:** a never-completing Google request leaves the current sync pending, so later refreshes attach to it. Already ingested HC changes can also wait behind enrichment before their scores update. Transport/OS behavior may eventually fail the request, but the application has no bounded contract.

**Required contract:** bounded per-source requests with cancellation and a recoverable sync outcome. Preserve useful HC progress when optional enrichment fails. Use a deliberately non-completing fake transport to verify recovery.

### Executed probes and their limits

Reproduce with `python app/tool/audit_probe.py` from the repository root. The helper uses only Python's standard library, reads the checked-in SQLite schema, creates in-memory databases, and prints results. It does not read personal data, contact providers or change application files.

| Probe | Observed output | What it establishes |
|---|---|---|
| Split read with writer commit between queries | Old measurement 50 paired with new score 97 | Separate queries do not guarantee one snapshot, despite atomic writes |
| Earliest deletion boundary | Dirty Sep 1, clearFrom Sep 2, cached Sep 1 survives | The chosen invalidation boundary leaves a deleted day |
| Interrupted raw/checkpoint-to-score protocol | Raw 80, cached measurement 50/score 58; startup stale/missing checks both false | Current startup predicates cannot detect this interrupted state |
| Model of minute-blob decoding across timezone change | 03:30 UTC becomes 09:00 UTC, +330 minutes | Dropping the original epoch anchor permits historical time movement |
| Independent import inventory | 215 Dart files, 1,012 internal edges, zero documented direct-layer violations | Folder/import separation exists; it does not validate the semantic contracts |

The first three are SQLite protocol reproductions using actual schema and SQL predicates plus explicit source-derived interleavings. The timezone case models the decoder mathematically. **None executes Dart, Flutter, Android, Health Connect or a cloud model.** Their purpose is to make architecture claims falsifiable while full runtime tooling is unavailable.

### Why existing tests miss these cases

- `test/data/recompute_window_test.dart` compares full/incremental recomputation over unchanged demo records. It does not mutate/delete source history, cross a shape threshold, switch timezones or interrupt a commit sequence.
- `test/data/background_worker_db_test.dart` verifies connection ownership and typed closed-store errors. It does not verify concurrent settings changes, external revision visibility or dispatcher failure outcomes.
- Privacy evals taint direct current-day values. They do not taint prior-day dependencies or mixed-source weekly Discuss cards.
- Coach consent tests cover entry conditions, not withdrawal while a tool round is in flight. Secure-store success fixtures miss partial withdrawal.
- Provenance fixtures typically supply the metadata the real incremental adapter drops. Component-level correctness cannot establish adapter-to-baseline correctness.
- Screen tests generally inject a clock, build once and inspect output. They do not establish time-driven invalidation of retained screens.
- Architecture tests check imports. They do not establish snapshot identity, durable invalidation, comparable measurements or send-time authorization.

### Counterevidence and corrections log

- **No blanket architecture rewrite is justified.** Dependency directions are largely coherent; most issues need shared contracts and coordinated state transitions.
- **Algorithm-version invalidation exists.** Its limitation is not tracking raw/configuration revisions, not its absence.
- **The old worker-closes-main-DB bug has a source fix.** The deeper issue is cross-instance visibility and coordination, not shared-handle closing.
- **Baseline A-to-B-to-A reuse is deliberate.** `test/domain/baseline_origin_test.dart:99-118` expects earlier A history to resume. Do not file reuse itself as a defect; align fresh-baseline copy with that decision.
- **The last-30-observations finding stands.** Pipeline history is not cropped upstream to 30 calendar days.
- **The question-number verifier bypass stands.** Citation-token validity and output-policy checks do not reject the described numeric contradiction before its early success return.
- **HC change-event ordering remains unverified.** The app splits deletions and upserts, but whether the provider can emit the relevant conflicting sequence in one window has not been established. Do not treat the hypothetical resurrection case as confirmed.
- **Clinical validity, vendor compatibility and device performance remain unverified.** A source audit or schema probe cannot establish them.

### Architecture repair sequence, without rebuilding the app

1. **Persist consistent progress.** Add durable pending dirty range, data revision and configuration generation. Make worker/foreground writes share the same rules; acknowledge checkpoints only with recoverable pending work. Read coherent bundles.
2. **Make computation inputs explicit.** Define effective provenance, immutable time anchors, calculation basis, validity and coverage once. Consume them in score engines, charts and explanations.
3. **Carry lineage through derivation.** Scores/cards need their contributing inputs/dates/sources for recompute and sharing decisions. Include HRV shape and historical dependencies.
4. **Make privacy transitions enforceable.** Check current consent before every send, partition sample history, and report deletion outcomes accurately.
5. **Publish state changes reliably.** Observe durable revisions across isolates; invalidate clock-dependent state at lifecycle and day/phase boundaries; report typed job outcomes.
6. **Test transitions before visual polish.** Add the closure cases in the issue tracker. Run them against real SQLite and controlled delayed/failing adapters, then validate Android-specific behavior on a device.

Avoid introducing a new state-management framework, microservices, or a generic event-sourcing platform just to solve these issues. A small set of explicit invariants within the existing architecture is the appropriate starting point.
