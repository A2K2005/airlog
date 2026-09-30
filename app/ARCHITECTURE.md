# Architecture

Working name **Airlog** (placeholder). This app turns Fitbit Air data into WHOOP-style Recovery, Strain and Sleep scores, computed entirely on the phone. The product rationale is in [`../PRODUCT_PLAN.md`](../PRODUCT_PLAN.md).

## 1. Choice of pattern

We combine three ideas, following Flutter's official app-architecture guide (MVVM with a UI layer and a data layer) and the "combine thoughtfully" advice in *Modern Flutter Architecture Patterns* (Sharma, 2025):

| Concern | Choice | Why for *this* app |
|---|---|---|
| Boundaries | **Clean Architecture**: `domain` ← `data`, `domain` ← `features` | The scoring math is the product. It must be pure, versioned and unit-testable without a device. |
| State | **Riverpod 3** (`flutter_riverpod`, no code generation). One `Notifier` or `AsyncNotifier` per screen acts as the view-model | Riverpod doubles as compile-safe dependency injection, so we don't need GetIt. Tests override providers, and there's no build_runner step. |
| Organisation | **Feature-first** under `features/`, plus a shared `design/` system | Parallel work (one owner per feature), and each screen is self-contained. |

**Rejected:**
- Redux/MVI, for the boilerplate.
- BLoC, because Riverpod already gives us reactive state and DI.
- A use-case class per action: the `Engine` facade *is* the use-case layer, and one-line use-case wrappers would be ceremony.

## 2. Layers and the dependency rule

```
lib/
  main.dart            bootstrap only: DataModule.open() (synchronous; DB opens lazily
                       in repo.start(), overlapping the first frame) → runApp(ProviderScope)
  app/                 composition root: providers.dart (DI), app.dart (MaterialApp,
                       theme, shell + NavigationBar), routes.dart
  domain/              PURE DART. No `package:flutter`, no plugins (test enforces)
    models.dart        entities: DayRecord, SleepSession, HrSample, Provenance, …
    results.dart       DayResult and every score type (+ JSON)
    day_key.dart       calendar-day keys
    repositories.dart  HealthRepository + LiveHrService interfaces (Streams)
    engine/            use cases: Recovery, Strain, Sleep, HealthMonitor, PulseAge,
                       Readiness (Plews SWC), TRIMP, HRR-60, RMSSD/Baevsky from RR
  data/                implements domain/repositories.dart
    services/          one class per external system, no business logic:
      health_connect/  `health` plugin wrapper + change tokens + VO2 channel
      google_health/   Google Health API v4 client (OAuth PKCE via flutter_appauth)
      ble/             flutter_blue_plus + 0x2A37 parser (from Edge ble_hrs.dart)
      demo/            seeded synthetic "Fitbit Air" (60+ days, planted illness)
      takeout/         Google Takeout ZIP parser (later)
    db/                sqflite schema, migrations, DAOs (raw_* tables, day_result)
    resolver/          per-metric source priority → DayRecord (+ Provenance)
    sync/              SyncCoordinator (foreground) + workmanager callback
    repositories/      HealthRepositoryImpl, LiveHrServiceImpl
    data_module.dart   factory that wires everything; used by main.dart
  design/              design system: tokens (Edge theme.dart), charts (Edge charts.dart),
                       components (ScoreRing, BaselineBand, StatusCard, Pressable…), motion
  features/            presentation, one folder per feature:
    today/ recovery/ sleep/ strain/ trends/ live/ settings/ diagnostics/ onboarding/
      <name>_screen.dart      View: dumb widgets, reads view-model state
      <name>_view_model.dart  Riverpod Notifier/AsyncNotifier: loads, maps, exposes state
      widgets/                feature-private widgets
```

**Dependency rule** (enforced by `test/architecture_test.dart`):
- `domain/` imports nothing outside `domain/` and `dart:*`.
- `features/` imports `domain/`, `design/` and the shared `app/` files that import no feature (`providers.dart`, `route_names.dart`, `platform_services.dart`, `copy.dart`, `hc_rationale.dart`, `note_card.dart`, `ask_entry.dart`, `insight_card.dart`), never `data/`. Features never import each other, and presentation code reads time only through `clockProvider`. Both rules are enforced by `test/features/feature_boundaries_test.dart`.
- `data/` imports `domain/` and plugins, never `features/` or `design/`.
- `design/` imports only Flutter and `domain/` value types.

## 3. Data flow

```
Health Connect ─┐  Google Health API ─┐  BLE 0x2A37 ─┐  Demo generator ─┐
                ▼                     ▼               ▼                  ▼
            services/*  ── every row tagged with SourceKind + origin app + device ──►
            db raw_* tables (idempotent upserts keyed by source record id;
                      HR minute buckets kept per origin app)
                ▼
            origin plans: ONE app per metric, persisted as dated segments
                      (resolver/source_choice.dart, via ScorePipeline)
                ▼
            resolver: for each day + metric pick ONE source by priority and
                      ONE origin by the plan (never sum or average), emit
                      DayRecord + Provenance (definition, origin, device)
                ▼
            Engine.computeRange(records)  (pure, algoVersion-stamped)
                ▼
            db day_result (JSON, algo_version, computed_at)
                ▼
            HealthRepositoryImpl  ── revisions stream ──►  view-models  ──►  screens
```

**Source priority** is per `SourceKind` first. Within Health Connect it's the metric's chosen origin (any app: Google Health, Samsung Health, WHOOP, Oura, …; `resolver/source_choice.dart`). First available wins, per day:
- **HRV** (the ladder, research/09b §3): `ghapi_deep_sleep_rmssd` (Enhanced mode) > `hc_sleep_mean_rmssd@<origin>` (the app writes a series: ≥ 3 AUTOMATIC/UNKNOWN records inside the main sleep, mean) or `hc_nightly_rmssd@<origin>` (the app's persisted HRV shape is "single": its 1–2 nightly records, mean) > `ghapi_daily_rmssd` > `demo_*`. ACTIVE/MANUAL readings are spot checks: stored, never scored.
- **Sleeping HR (4 h mean)**, `hc_sleep_hr_4h_mean@<origin>`: its own metric (`Metric.sleepingHr`), never resting HR. From the sleep's own app, sleep start + 30 min for 4 h, gated (sleep ≥ 4.5 h, ≥ 80 % of 5-min bins). Recovery uses it in resting HR's slot only when the app never shares resting HR.
- **RHR, respiratory rate, skin temp, sleep, workouts, steps, HR:** Health Connect > Google Health API > Takeout
- **SpO2:** Health Connect (nightly samples inside sleep) > Google Health API
- **Weight** (not scored): the context-only path (`SourceKind.context`, only when enabled).
- **Live HR:** BLE only
- In demo mode the demo source is the only source.

**One origin per metric.** The automatic plan picks the app with the best 14-day coverage and moves only after `kSustainedAbsenceDays` = 4 complete days without a datum from it while another app has data; the new segment is backdated to the first silent day. A user pin (`setSourceChoice`) starts at the pinned app's first day and never moves. When another app has fresher data, `SourceChoice.suggestedOrigin` is set so the UI can ask. Plans persist in settings (`origin_plan.<metric>`); a changed plan recomputes from the first affected day.

**Baselines** are keyed by `Provenance.baselineKey` = `definition@origin#device`: a change of definition, app or device starts a new segment. A day without device metadata (background reads) takes its app's most recent known device.

## 4. Sync

**Startup:**
- `runApp` runs before any I/O.
- Every repository read awaits `start()`, which opens SQLite, seeds or recomputes if needed, then emits a revision. Storage failures surface as `DataUnavailableException`, never a raw `DatabaseException`.
- **A fresh install is live** with an honest empty state. Demo ("Try with sample data") is an explicit choice; nothing is seeded before it, and any real source with data switches back to live. A small-hours demo seed refreshes (at most hourly) until the latest demo wake-up.
- **The workmanager worker** opens its own SQLite connection (`singleInstance: false`): it runs in the app's process, and closing a shared handle would close the app's database (QA-01).
- **Demo seed** (after the user picks it):
  - Generation, resolving, the engine and payload encoding run in `Isolate.run`.
  - The UI isolate then writes everything in a single transaction, as multi-row `INSERT … SELECT … FROM (VALUES …)` statements of at most 999 bound values.
  - While it runs, the status reads "Preparing 90 days of sample data…".

1. **First run:** backfill 30 days, or longer if history permission is granted, then store a Health Connect changes token.
2. **Periodic** (workmanager, 15 min minimum, plus on app resume):
   - Apply upserts and deletions from the token.
   - Mark the affected days dirty.
   - Re-resolve and recompute from the earliest dirty day onward, because sleep debt carries forward.
   - If the token has expired, do a full re-read.
3. **Clean-up while reading:**
   - Drop future-dated records.
   - Read every origin (no Fitbit-only filter). Each row keeps its origin package and, for HRV, its `recordingMethod`. For each metric use ONE persisted origin (see §3), never summed or mixed; the phone-steps gap fill was cut for that reason.
   - Provenance carries the origin and device; baselines are keyed by `definition@origin#device` (§3).
   - Dedupe inside one origin: for a timezone-duplicated night, keep the later write.
   - On resume, Health Connect permissions are re-checked; a new grant syncs at once.
4. **Per-type sync log:** one failing type never blocks the rest (Pulse's tolerant decoding).

## 5. Error handling

- Services throw typed `SourceException(kind, dataType, cause)`.
- The sync layer catches per data type, writes a `SyncLogEntry`, and continues.
- The repository never throws for a missing metric. The engine emits a `StatusNote` instead: honest status cards, never a guessed number.
- View-models expose `AsyncValue`, and screens render loading, error and data states explicitly.

## 6. Testing

| Level | What | Where |
|---|---|---|
| Domain unit | Every engine formula. **Parity tests** port Pulse's `SelfTest` fixtures with exact expected values | `test/domain/` |
| Architecture | Import rules above | `test/architecture_test.dart` |
| Data | Resolver priority, change-token apply/delete, demo generator determinism, DB round-trip (sqflite_common_ffi) | `test/data/` |
| Widget | Each screen with an overridden repository (loading, empty, calibrating, full data) | `test/features/` |
| Golden | Rendered PNG of each MVP screen in demo mode (fonts loaded), dark only | `test/goldens/` |
| Figma diff | Each design tile against its PNG at dpr 1, with a per-tile diff limit | `test/goldens/figma_diff_test.dart` |

## 7. Design system rules (from Edge `theme.dart`, plus Emil Kowalski's motion rules)

- **Tokens are centralised:**
  - Colours, sizes, radii and durations come only from `design/tokens/`.
  - Muted text and accents go through the contrast helpers, which enforce WCAG AA.
- **Motion:**
  - Everything goes through the `motion()` gate, which returns zero under reduced motion.
  - Durations stay under 300 ms for UI. Use a strong ease-out, `Cubic(0.23, 1, 0.32, 1)`, for enters, and ease-in-out, `Cubic(0.77, 0, 0.175, 1)`, for on-screen moves. Never ease-in.
  - Pressables scale to 0.97 in 120 ms. Nothing enters from scale 0: start at 0.95 plus opacity.
  - Staggers are 40 ms or less per item.
  - No animation on things seen tens of times a day, beyond press feedback. Score rings animate only on first appearance each day.
- **Charts:** Edge's `charts.dart` painters, with real axes and a `Semantics` description on every chart.
- **Look:** a 1:1 copy of the user's own Figma widget PNGs (`Widget/`), dark only. Tile backgrounds are fitted gradients, not per-frame blurs. `test/goldens/figma_diff_test.dart` diffs each tile against its PNG; see `docs/DESIGN_SYSTEM.md`.
- **Fonts:** DM Sans (variable, OFL) for UI, with Manrope 500 as the fallback for ₂ only. Subway Ticker Grid (K-Type, gitignored; see the README) for tile numerals. Nothing is fetched at runtime.

## 8. What we reuse, and from where

| Asset | From | License |
|---|---|---|
| Recovery / Strain / Sleep / HealthMonitor / Age formulas and constants, demo-data idea, journal correlations, sync-log pattern, PKCE | Luraxx/pulse @ `1f8975c` (`Core/`) | Apache-2.0, see `third_party/pulse/` |
| `charts.dart`, `theme.dart` (tokens, contrast solver, motion gate), `ble_hrs.dart` parser, Manrope font (now the ₂ fallback only) | OpenStrap/edge @ `74ed359` (`lib/ui2/`, `lib/ble/adapters/`) | MIT (fonts OFL), see `third_party/edge/` |
| Figma corner smoothing (`tilePath` in `design/components/tile.dart`) | figma-squircle (phamfoo/figma-squircle) | MIT |
| DM Sans | Google Fonts (github.com/google/fonts, `ofl/dmsans`) | OFL 1.1, see `assets/fonts/DMSans/OFL.txt` |
| Subway Ticker Grid | K-Type | K-Type free-font licence; not in the repository |
| Banister TRIMP, Plews lnRMSSD SWC, HRR-60 (Cole 1999), Baevsky SI | Published methods cited by Edge | — |

Every copied or ported file starts with a header naming its origin file and license.

## 9. Ownership (the build agents)

| Area | Owner | Must not touch |
|---|---|---|
| `domain/engine/**`, `test/domain/**` | engine | `data/`, `features/` |
| `data/**`, `test/data/**`, `android/**` (manifest, Kotlin) | data-platform | `features/`, `design/` |
| `design/**`, `features/**`, `test/features/**`, `test/goldens/**` | ui | `data/`, `domain/engine/` |
| `domain/models.dart`, `results.dart`, `repositories.dart`, `engine/engine.dart` signatures, `app/providers.dart` | orchestrator (contract) | everyone: **additive changes only, and report them** |

## 10. Coach (optional AI Q&A)

**Layers.** The coach follows the same dependency rule.
- `domain/coach/` (pure Dart):
  - `coach_contracts.dart`: settings, messages, `LlmClient`, `CoachRepository`, and the errors, including `ModelUnavailable`.
  - `coach_service.dart`: the ask use case.
  - `tools.dart`, `verifier.dart`, `policy.dart`, `safety.dart`, `prompts.dart`.
  - `personal_context.dart` (PR #1): `PersonalContext.plan`, a small deterministic retrieval plan for personal questions (memories, today, the 28-day trend of the metric asked about, journal or training load), and `MemoryContext` (corrections, review age, selection).
- `data/coach/`:
  - Raw-HTTP `ClaudeClient` and `GeminiClient`, with `http_retry.dart`.
  - `OfflineClient`, the on-device engine.
  - `provider_models.dart`: model ids, prices, wire names and the fallback chains.
  - `CoachRepositoryImpl`: SQLite for chats and memories, the keystore for API keys, and the `MeteredClient` daily budget.
- `features/coach/`: chat, setup, Settings → Coach, memory and history. UI strings live in `app/copy.dart`.

**One question** (`CoachServiceImpl.ask`) goes through these steps:
1. The input router (red flags, minors and similar) returns fixed copy with no model.
2. The consent gate, for cloud providers.
3. The scoped history (PR #1): a cloud question replays only earlier answers built under the same provider, mode, payload version (`kCoachPayloadVersion`) and memory scope, and sample-data answers only in demo mode. A correction ("actually…") replays nothing.
4. The daily budget, which fails fast.
5. The card seed, sent as quoted data in the user message. A cloud provider gets a withholding notice instead of the card's facts; it reads current facts through the guarded data tools.
6. The personal context (PR #1): `PersonalContext.plan` runs its tool calls before the model answers, and the results ride in the same user message. Only memories actually retrieved (and not due for review) can ground an answer.
7. The tool loop: ≤ 4 rounds, append-only, each model turn replayed unchanged. Before every request the settings, consent, data mode and memory scope must still be the question's own; the repository's generation fence also stops a request (and its HTTP retries) after a settings, key, memory or chat change. A stale question stops with "No further requests were sent" and does not fall back.
8. The verifier and the output policy, then one repair round, then the deterministic facts table.
9. The stored message, with refs, `Verification` and `SentPayload` (which also records the privacy scope: provider, mode, payload version, memory scope).

**Transport.** `http_retry.dart` retries a busy answer (429 per minute, 503, 529) at most twice inside one client call. It waits for `Retry-After` or Gemini's `retryDelay` when given, else about 2 s and then 6 s with jitter, and stays under the service's 150 s request timeout. A 429 for a day quota is never retried.

**Model fallback** (PRODUCT_PLAN §7, "Use a backup model when busy", on by default):
- **The chain** is `ProviderModels.chains`, the single source of truth. Gemini goes 3.8 Flash → 3.5 Flash-Lite. Claude goes Opus 5.5 → Sonnet 5.5 → Haiku 4.5. The chain starts at the chosen model, uses the same key, and **never reaches another provider**, because consent covers one.
- **Model-specific failures** make the clients throw `ModelUnavailable`:
  - a per-model day quota (429);
  - 429 / 503 / 529 still failing after the retries;
  - 404, model not found.

  The service then **restarts the whole question** on the next model: a fresh toolbox, evidence, refs and transcript. Thinking blocks and thought signatures are bound to their model, so models are never mixed inside one tool loop. A repair round stays on the model of its attempt.
- **Anything else** skips the chain and answers **on this phone** with `OfflineClient` and no network. That covers:
  - account-wide failures: 401/403 key, 402 or out of credit, a project-wide day quota;
  - network and timeout;
  - the last model failing;
  - the setting being off.
- **Every attempt** gets the verifier and the output policy. `MeteredClient` counts every call the provider answered, failed ones included. A retried busy answer counts once per call.
- **The stored message** carries `answeredBy` (a model id, or `on-device`), `fallbackFrom` (the chosen model) and `fallbackReason`. For Claude, `answeredBy` is taken from the response's `model`, because a server-side refusal fallback can switch it. The chat shows a quiet line under the answer: "via 3.5 Flash-Lite", or "Answered on this phone — Gemini is unavailable right now." The reason-specific version names a rejected key or an account out of credit.
- A refusal is an answer, not a failure: it never triggers the chain.
- **Context parity.** Every attempt, backup models and the on-device fallback included, gets exactly the first attempt's context: the scoped history, the card seed (its withholding notice for a cloud question), the personal context, the grounded memories, the tools, the system prompt and the length. The on-device fallback of a cloud question runs behind the same source firewall as the cloud attempt (`CoachToolbox(cloud: true)`), because its answer joins the cloud chat's history. So for a user with Google Health API history, that fallback sees only what the cloud could see. Tests: `test/data/coach/fallback_context_test.dart` (Gemini byte-identical, Claude identical but for the model id, on-device transcript/tools/length/system identical).
- **Same reasoning level.** A backup model keeps the chosen length's reasoning: Gemini `thinkingLevel`, Claude `output_config.effort`, and Haiku 4.5's manual thinking budget (`LlmModelSpec.thinkingBudget`).
- **Skip known-down models.** `noteModelUnavailable` marks a model down until its day quota resets (midnight Pacific, persisted in `coach.models_down`) or its retry delay passes (in memory). Later questions skip it without a failed request, and the chat offers "Ask <provider> again" once it is back.
- **Replay of fallback answers.** A backup model's answer is scoped by its `SentPayload`. An on-device fallback that sent nothing records `ChatMessage.replayScope` and is replayed only while that scope still holds.
- **Quality bar.** A backup model stays in the chain only if its live pass rate is at least 90 % of the primary's (docs/EVALS.md §5; unmeasured until a paid-key run).
