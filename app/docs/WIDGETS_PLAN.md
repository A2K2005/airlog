# Home-screen widgets: scope and plan (Android)

Status: scope for branch `airlog/android-widgets`. PRODUCT_PLAN.md §7 decides wherever this file and the plan disagree. In particular: Figma 1:1 governs the look, principle 6 governs the content, and the app is dark only.

## 1. Decision

The widgets are drawn natively by `AppWidgetProvider` code in Kotlin, onto a Canvas, as one bitmap per widget. The fonts come from the Flutter assets already inside the APK (`flutter_assets/`, through home_widget's `HomeWidgetFonts`). Dart writes a single JSON snapshot. No Flutter engine is needed to draw, the font is never copied into `res/`, and there is no Glance.

The four options, and why this one wins:

| Option | Figma 1:1 | Font licence | Works without the engine | Verdict |
|---|---|---|---|---|
| `HomeWidget.renderFlutterWidget` (the real tiles to a PNG) | Exact, since it uses the app's own tiles | Fine (uses the asset font) | **No.** It dereferences `PlatformDispatcher.instance.implicitView!`, which doesn't exist in the workmanager isolate, so a live-mode background sync would update the numbers but could never redraw them. A baked image also can't relabel itself at midnight (QA-08), because the relabel runs natively on clock broadcasts with no Dart. And `test/architecture_test.dart` forbids `lib/data` (where the sink lives) from importing `lib/design` (where the tiles live) | Ruled out |
| RemoteViews XML with DM Sans in `res/font` | Loose. XML can't draw the glow, the squircle, the ring or dot numerals; DM Sans could be committed (OFL), but Subway Ticker Grid couldn't | Only DM Sans | Yes | Ruled out: not 1:1 |
| Copy Subway Ticker Grid into `res/font` plus a gitignore entry | Close | Fragile: one `git add -A` publishes a personal-use font. The file would also exist twice in the APK | Yes | Ruled out |
| **Native Canvas + fonts read from `flutter_assets`** | Close to 1:1. It is a port of the tile's own coordinates, `tilePath` and `GlowRecipe.paint` | **Nothing new is committed.** The font is read in place from the APK, where pubspec already bundles it | Yes. It redraws on any broadcast, alarm or resize | **Chosen** |

`HomeWidgetFonts.typeface(context, family)` (home_widget 0.10.0) reads `flutter_assets/FontManifest.json` and loads the family's file with `Typeface.createFromAsset`. If the font is missing, it returns null, and the widget falls back to DM Sans and then to the system font. DM Sans is variable, so its weight and optical size are set with `Paint.fontVariationSettings` (API 26, the app's minSdk).

**Glance: ruled out.** home_widget already brings `glance-appwidget:1.2.0` in as an `api` dependency, so its APK cost is already paid. Authoring widgets in Glance, though, means `@Composable` code in the app module. That needs the Compose compiler plugin matched to the project's Kotlin (2.4.0, AGP 9.1 built-in Kotlin) and makes every Gradle build heavier, on a laptop that already struggles. It would also buy nothing: Glance can't draw custom-font text either (home_widget's own font helper draws text into bitmaps), and it can't draw the glow. We only call plain Kotlin functions from `HomeWidgetFonts`.

**Keeping the port faithful.** The glow recipes are not retyped in Kotlin. A Dart test, `test/data/widget_glows_test.dart`, serialises the `GlowRecipes` that the widgets use, plus `PlanTile.glowFor`, into `android/app/src/main/res/raw/airlog_widget_glows.json`. The test fails if the committed file is out of date, and `AIRLOG_WRITE_WIDGET_GLOWS=1` rewrites it. The tile coordinates are copied from the Dart tiles, with a comment naming the source line. A Figma-vs-emulator screenshot comparison is part of step 3.

## 2. Widgets and sizes

Each widget is one fixed-aspect tile, as in the design (tiles never stretch). The bitmap is scaled to fit the cell the launcher gives it and centred there. The corners are the tile's own squircle, with transparent corners.

| # | Widget | Design size (dp) | Look (PNG) | Slot → metric | Opens |
|---|---|---|---|---|---|
| 1 | **Recovery** (small) | 164 × 218 | Small/5 (`RingScoreTile`, glow `s5`) | Title "Recovery"; dot value = `RecoveryResult.score` (hidden while calibrating); ring progress = score / 100, with the squiggle at the value; caption = the same status words as Today's Recovery tile: Good / Fair / Low (zone), "Learning" (calibrating), "No data". Basis words ("without HRV", "provisional") come from `RecoveryResult.withoutHrv` and `confidence`, the same as Today | `/recovery` |
| 2 | **Today plan** (medium) | 348 × 164 | The `PlanTile` vocabulary on a medium glow panel (no PNG; the glow comes from `PlanTile.glowFor(state)`) | The eyebrow is the basis ("Tonight · Provisional · without HRV"); then `TodayPlan.headline`; then the first action's `title` and `why` (1 line each, ellipsised). With no actions: "Nothing to change today." Everything comes from `Engine.planToday(...)`: no copy is written for the widget except the two fixed strings in §4 | `/` (Today, where the plan lives) |
| 3 | **Today** (medium). This is **the existing widget, migrated.** Same provider class, so pinned instances keep working | 348 × 164 | Medium/19 (three plates; the macros are relabelled, as §7 allows) | Plates: Recovery `score` %, Strain `strain` (1 dp, "of 21"), Sleep performance % (`SleepAnalysis.performance`, time asleep as the unit line). Missing = `--` (the dot face has no en dash) | Each plate is its own tap target: `/recovery`, `/strain`, `/sleep` |

**Deferred: Large Today summary (Large/5 `ReadinessTile`).** It needs 6 days of recovery steps and "HRV vs usual" / "RHR vs usual" text, which today are built in `features/today/today_view_model.dart`. `lib/data` can't import that file, and retyping its strings in the sink would fork the copy. Doing it properly means moving those formatters into `domain/` or `design/format.dart` first, so it gets a branch of its own.

**Tile sizes on the launcher** (`appwidget-provider`): Recovery `targetCellWidth/Height` 2×2, with `minWidth` 110 dp and `minHeight` 110 dp (it shrinks uniformly). The two medium widgets are 4×2, with `minWidth` 250 dp and `minHeight` 110 dp. All three have `resizeMode` horizontal|vertical, and each redraws at its new size in `onAppWidgetOptionsChanged`.

## 3. Data: one snapshot

`airlog_snapshot_v1` (a single JSON string in home_widget's SharedPreferences) stays the only thing the widgets read. That keeps date, mode and values from ever mixing across updates. The change is additive: new keys are added, and the existing keys and their meaning stay.

- **Kept (QA-08, unchanged):** the snapshot shows the same day Today shows (the newest day with data). `stale` is true when that day isn't today's key. Recovery is null while calibrating, so yesterday's recovery is never shown as today's. The native provider also compares `date` with `LocalDate.now()` on every draw, so the label appears at midnight even if Dart hasn't run.
- **New keys:** `sleepPerf`, `strainOf` (the strain target for the unit line), `recStatus` (the status word), `recBasis`, the plan `{state, headline, eyebrow, action, why, until}`, `demo` (existing), and `v: 2`.
- `plan.until` is the epoch ms of the next planner phase boundary (05:00 or 18:00, from `TodayPlanner.tonightFromHour/UntilHour`). After it, the native side drops the action line (it was advice for the other phase) and shows "Open Airlog for the latest plan". That rule keeps the widget honest when no Dart has run: it never shows effort advice in the evening.
- The plan is built in `HealthRepositoryImpl._pushWidget` with `Engine.planToday(bundle, sync: status, now: clock())` over the same bundle Today uses: before 05:00, that is the evening's day (`eveningKeyOf`), as in `TodayViewModel`. `lib/data` → `lib/domain` is an allowed import.

## 4. States

| State | What every widget shows |
|---|---|
| Fresh | Values as above |
| Stale (the day shown isn't today) | The values stay, labelled with the day ("From 29 Sep") in the caption or eyebrow. The plan widget shows its planner-built "Waiting for today's data" state (the planner is itself stale-aware) |
| Empty (no data at all) | `--` in every dot slot, and a caption of "No data yet"; the plan widget shows "Open Airlog to get started" |
| Sample data (demo mode) | A **"Sample data"** chip on every widget, drawn like `SampleDataChip` (amber wash, 10 sp, weight 600). The Today widget's plates keep their numbers. The chip is never hidden in demo mode |

The only widget-specific copy is "Open Airlog for the latest plan", "Open Airlog to get started", "No data yet" and "From <d MMM>". It lives in one Kotlin object (`WidgetCopy`), next to the renderer.

## 5. Update triggers

1. **After every recompute.** `HealthRepositoryImpl._pushWidget` already runs after sync, mode change, wipe, profile edits, live sessions and so on (10 call sites). `HomeWidgetSink.push` writes the snapshot, then asks **all three** providers to update. Today it only updates `AirlogWidgetProvider`.
2. **Background sync (live mode).** Workmanager (15 min minimum, already there) runs `_sync` and then `_pushWidget`. No Flutter drawing is needed, which is why the native renderer matters.
3. **Clock.** `TIME_SET` and `TIMEZONE_CHANGED` are exempt from the Android 8 implicit-broadcast ban. `DATE_CHANGED` is not, so it isn't reliable, and it stays only as a harmless extra. Each draw schedules one **inexact, non-wakeup RTC alarm** (`AlarmManager.set(RTC, …)`) for the next boundary among 00:00, 05:00 and 18:00. That needs no exact-alarm permission and doesn't wake the phone: it fires when the phone next wakes, which is when the home screen can be seen anyway.
4. **`updatePeriodMillis`** goes from 30 min to **3 h**, as a safety net only. It wakes the device, so the fewer the better; the alarm covers the moments that matter.
5. **Resize.** `onAppWidgetOptionsChanged` redraws at the new size.

WorkManager isn't used for the widgets beyond the existing sync.

## 6. Tap targets and deep links

A PendingIntent opens `MainActivity` with action `app.airlog.airlog.OPEN_ROUTE` and a `route` extra. `MainActivity` accepts only a fixed allow-list (`/`, `/recovery`, `/strain`, `/sleep`): it passes the route as the initial route on a cold start, and uses `navigationChannel.pushRoute` on a warm start. That is the same mechanism `/privacy` already uses. Each target is at least 48 dp: the Today widget's plates are about 100 × 64 dp at design size.

## 7. Privacy

- `widgetCategory="home_screen"` only, never `keyguard`: health numbers stay off the lock screen.
- There is **no "hide values" setting in the app today** (`settings_screen.dart` and `copy.dart` were checked), so there is nothing to honour. When one is added, the snapshot gets a `private` flag and the renderer shows the tile with `--` and no plan text. That is recorded as deferred.
- The widget reads nothing but the snapshot. There is no network, and no Health Connect access from the provider. `contentDescription` carries the same summary the tile's semantic label speaks.
- The widget picker preview is a static layout with no data.

## 8. Cost

- **Battery:** drawing happens only when a broadcast arrives, and only for pinned widgets (`onUpdate` gets their ids). Each draw takes a few milliseconds of Canvas work. With no widget pinned, the only cost is one SharedPreferences write per recompute plus a no-op broadcast. There are no wakeups beyond the 3 h safety net.
- **Memory:** the bitmap is drawn at the widget's actual size, at up to 2.625 px/dp. At that density, the small widget is 430 × 572 px (0.98 MB) and a medium one is 913 × 430 px (1.57 MB). The RemoteViews bitmap budget is 1.5 × screen width × height × 4 bytes, about 15 MB on a 1080 × 2400 screen. The Typefaces are cached per process.
- **APK:** no new dependency, and no duplicated fonts. The glow JSON is about 10 KB.

## 9. Tests and checks

- Dart unit tests (`test/data/widget_sink_test.dart`) cover the payload for fresh, stale, empty and sample-data days, the plan fields and the `plan.until` boundary, `--` never being an en dash in a dot slot, and QA-08 (the existing test stays and still passes).
- `test/data/widget_glows_test.dart` checks that the glow JSON matches `GlowRecipes`.
- The native check is a gated `flutter build apk --debug`.
- On the emulator (`airlog_api35`), in demo mode: pin each widget (via a debug-only `requestPinAppWidget` path), then take screenshots in `docs/screenshots/widgets/`. The screenshots check whether the custom fonts render.

## 10. Deferred

- The Large Today summary (Large/5), once the recovery "vs usual" formatters live outside `features/`.
- The "hide values" privacy flag, once the app has the setting.
- iOS widgets (IOS_PLAN.md).
- Widget picker preview images made from real renders.

## 11. Built, verified, deferred (1 Oct 2026)

**Built.** The three widgets in §2 (Recovery small, Today plan medium, Today medium), drawn natively on a Canvas in `AirlogWidgetRender.kt` and the three providers, reading only `airlog_snapshot_v1` (v2 keys). A debug-only `DebugWidgetPinReceiver` pins them from adb.

**Verified.**
- `flutter analyze`: no issues. Tests: `test/data/widget_sink_test.dart`, `test/data/widget_glows_test.dart`, `test/data/in_memory_repository_test.dart`, `test/design/`, `test/architecture_test.dart` and `test/features/feature_boundaries_test.dart` pass (262, 0 failures). `flutter build apk --debug` succeeds.
- On the `airlog_api35` emulator (Pixel launcher), with each widget pinned through `requestPinAppWidget`. Screenshots are in `docs/screenshots/widgets/`:
  - sample data at 00:31, before the 05:00 planner boundary (`*_sample_night`, `plan_sample_tonight`);
  - sample data at 10:00 (`*_sample_day`);
  - the next day, with no Dart run: the clock was moved forward, then `TIME_SET` and the debug refresh were sent (`*_sample_stale`). Every widget shows "From 1 Oct", and the plan widget drops its action line for "Open Airlog for the latest plan";
  - app data cleared (`*_empty`): `--` in every dot slot, with "No data yet" and "Open Airlog to get started", and no Sample data chip.
- Both fonts render from `flutter_assets`: Subway Ticker Grid for the dot numerals, including `--`, and DM Sans for the labels. Every sample-data state shows the "Sample data" chip.
- Tapping the Today widget's Sleep plate opens the Sleep screen.
- Fixed during verification: the Today layout used a plain `<View>` spacer, which RemoteViews refuses to inflate, so the launcher showed "Can't load widget". It is now a `FrameLayout`.

**Observations (not changed).**
- The Today widget's plates follow Medium/19 and show only the `%` unit. "of 21" and the time asleep are in the `contentDescription` only, not drawn as §2's table says. Figma wins (see the Status line).
- Between 00:00 and 05:00, the Recovery widget and the Recovery plate show "No data", because today's recovery doesn't exist yet. The plan widget says "Tonight" (the evening's day). This matches the app's own Today screen at the same hour.
- No pixel-level comparison of Figma against the emulator was made; the screenshots were checked by eye against `Widget/Small/5.png` and `Widget/Medium/19.png`.

**Deferred.**
- Everything in §10.
- Not exercised on the device: the Recovery and Strain plate taps, the cold-start versus warm-start routing, resizing (`onAppWidgetOptionsChanged`), the RTC boundary alarm firing on its own, and a live-mode background (workmanager) redraw.
- Also not exercised: the Dart-driven stale plan, which is the planner's "Waiting for today's data" state from §4. The stale screenshots show only the native rollover, where Dart hasn't run and the `until` rule applies.
