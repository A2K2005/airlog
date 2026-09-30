# Design system: usage guide

Import everything from one file: `package:airlog/design/design.dart`. The component gallery is at the debug route `/gallery`, and its goldens are under `test/goldens/`.

## Hard rules (enforced by `test/design/tokens_test.dart`, which scans `lib/features` and `lib/app` too)

Outside `lib/design/tokens/`, code must not contain the following. Use the replacement instead.

| Don't use | Use instead |
|---|---|
| `Duration(…)` | `Motion.*` via `motion(context, …)` for animation; `DayKey` or `DateTime(...)` maths for dates |
| `Color(…)`, `Color.fromX(…)` | `C.*`, `P.of(context)` or `DomainColors`. `C.clear` is transparent |
| `fontSize:` | `F.*`, or `F.scaled` |
| numeric `BorderRadius.circular(n)` | `R.*` |
| `Colors.white` / `Colors.black` | palette colours |
| `.repeat(` | nothing: no infinite animations. The one exception is `ThinkingDots` (`repeat(count: Motion.dotsCycles)`, about 17 s, then static; off under reduced motion; user decision 2026-10-01) |
| `GestureDetector`, `InkWell`, `Listener`, `RawGestureDetector` | **`Pressable`** |

Also:
- **Palette:**
  - `p.on(x)` for text and icons (≥4.5:1 on every surface)
  - `p.mark(x)` for chart marks (≥3:1)
  - `p.fill(x)` plus `p.onFill(x)` for filled buttons
  - `p.wash(x)` for tinted backgrounds only
- **Gallery coverage:** every public widget in `lib/design/components` and `lib/design/charts` must appear in the gallery.
- **Components never read providers.** Screens pass plain values or domain types.
- **Features never import each other** (enforced by `test/features/feature_boundaries_test.dart`). Shared widgets and formatters live here in `design/`; shared app seams live in the `app/` kit, which imports no feature:
  - `app/providers.dart`: DI, `clockProvider`, tabs
  - `app/route_names.dart`
  - `app/platform_services.dart`: `fileSharerProvider`, `linkOpenerProvider`, `noRetry`
  - `app/copy.dart`: `hcReadTypes` (the one Health Connect permission list: privacy, onboarding and Sources), `hcTypeName`, `SettingsCopy`
  - `app/hc_rationale.dart`: `HcRationaleList`, `showHcRationale`
  - `app/note_card.dart`: `noteCard` (a `StatusCard` whose button routes to Profile or Sources)
  - `app/ask_entry.dart`: the coach's entry points. `AskAboutThis({required screen, date, prefill, label = 'Ask about this'})` (a quiet compact button), `AskIconButton({screen, date})` (a 48 dp header icon), `openCoach(context, AskContext?, {prefill})`, `CoachArgs` (the `/coach` route arguments) and `askIcon`. They only navigate: no provider is read, so a screen's tests need no coach overrides
  - `app/copy.dart` also holds `CoachCopy` (disclosure, consent, engine, model and cost copy) and `CoachSettingsCopy`, printed by the chat, Coach setup, Settings → Coach and the privacy policy
- **One clock source:** `clockProvider` (`app/providers.dart`) supplies the injectable clock. Reactive presentation watches `currentTimeProvider`, which refreshes on minute boundaries and on resume; imperative actions read `clockProvider`. Presentation code never calls `DateTime.now()`.
- **Navigation:** `Navigator.of(context).pushNamed(Routes.x)`, where `Routes` comes from `app/route_names.dart`.
- **Tab screens** (Today, Sleep, Strain, Trends) are Scaffold-less bodies inside the shell. Pushed screens own their Scaffold.
- **ScoreRing sweep:** the 700 ms sweep plays once per `playKey` (for example `'recovery:2026-09-28'`) per app process. Pass a `playKey` only for today's rings.
- **No animation on day switching.** Key a screen's rings by the day shown (`ValueKey('…-$date')`), so stepping days draws the new day's rings at once. The 280 ms morph is left only for a same-day update, such as a sync. `DaySwitcher`'s label swaps without a crossfade.
- **Loading keeps the data layout.** A tile loads as `TileSkeleton` in its own footprint. Render `DaySwitcherSkeleton` where the switcher will be, and loading rings in the rings' own slot (`reserveCaption: true` on a row of rings). On first launch, when `PreparingNote.shows(sync, hasData: false)` is true, show a `PreparingNote` where the first card will be. Data then replaces all of these in place.
- **Injected clock:** `FreshnessLine` and `DaySwitcher` take `now` / `today` as parameters.
- **Engine constants in copy:** explain sheets and Methodology print the engine's named constants (`RecoveryEngine.hrvMinSd`, `SleepEngine.strainBoostFrom`, …) through `numText`. They never retype a number.

## Components (`lib/design/components/`)

| Component | Signature |
|---|---|
| `Pressable` | `({required child, onTap, onLongPress, onPressDown, onPressUp, onPressCancel, semanticLabel, haptic = PressHaptic.selection, scale = .97, minSize = 48, selected})`. Merges its subtree into one labelled button node. Every down is followed by exactly one up or cancel |
| `AppCard` | `({required child, padding, onTap, tone = CardTone.base\|inset\|tinted, accent, semanticLabel})` |
| `AppButton` | `({required label, onTap, kind = AppButtonKind.primary\|secondary\|quiet, icon, accent, expand, compact})`. `quiet` has no side padding, so its label lines up with the content edge (the hit height stays 48 dp) |
| `AppIconButton` | `({required icon, required semanticLabel, onTap, filled, color, size = 22})` |
| `StatePill` | `({required label, required color, icon, tinted = true})` |
| `ScoreRing` | `({required label, required color, value, max = 100, state = RingState.measured\|provisional\|calibrating\|loading\|noData, valueText, unit, caption, progress, size = 148, playKey, onTap, semanticsLabel, reserveCaption = false})`. `reserveCaption` keeps one caption line of height, with a skeleton bar while loading |
| `MetricTile` | `({required label, value (String?), unit, delta, band = BandStatus.*, caption, chart, provenance, onTap, accent, semanticsLabel})` |
| `MetricTile.health` | `(HealthMetricStatus, {onTap, chart, decimals})`. Delta: `"+4 vs usual 48"`. A signed metric (skin temperature) signs every number and names its unit: `"+0.1 °C vs usual +0.1"`. A delta that rounds to zero reads `"Same as usual"`. Values are rounded before subtracting, and the minus sign is U+2212 |
| `MetricTile.valueText` / `deltaText` / `isSigned` | `(HealthMetricKind, v, …)`: the tile's formatters. Alerts and sheets use them so they write a metric exactly as the tile does |
| `StatusCard` | `({required title, required body, tone = StatusTone.info\|warning, fix, actionLabel, onAction, icon})` |
| `StatusCard.fromNote` | `(StatusNote, {actionLabel, onAction})` |
| `FreshnessLine` | `({required now, lastDataAt, lastSyncAt, syncing, error, source = 'your tracker', staleAfterHours = 6, onTap})` |
| `FreshnessLine.fromStatus` | `(SyncStatus, {required now, onTap})`; helper `ago(t, now)`. A tappable line is a full 48 dp target. A read error says "Couldn’t read your data. Pull to retry." |
| `FreshnessLine.perApp` | `(SyncStatus, {required now, onTap})`: one compact line per source app (Today's header) |
| `PreparingNote` | `({required title, body, icon})`; `PreparingNote.fromStatus(SyncStatus, {required demo})` uses the data layer's message, else "Preparing 90 days of sample data…" / "Reading your data from Health Connect…"; `PreparingNote.shows(sync, {required hasData})`. Static, a polite live region |
| `CalibrationBanner` | `({required have, need = 14, body, onTap})` |
| `CalibrationBanner.of` | `(Calibration)`; also `CalibrationBanner.shouldShow(c)` |
| `DemoBadge` | `({label = 'Demo data', onTap})`: a card-level marker (insight cards). Coach chat messages carry no data-mode label (sample data is shown app-wide). Screens use `SampleDataChip`, except the coach chat and its history |
| `ScreenHeader` | `({required title, subtitle, actions = [], below})` |
| `SectionHeader` | `({required title, subtitle, actionLabel, onAction, trailing})` |
| `SegmentedRange` | `({required days, required onChanged, options = [7, 30, 90]})` |
| `SegmentedControl<T>` | `({required values, required selected, required onChanged, required label, semanticsLabel})`. A 40 px pill inside 48 dp hit rows |
| `showExplainSheet<T>` | `(context, {required title, lede, children, footnote})` |
| `ExplainSection` | `({required title, body, formula, child})` |
| `SkeletonBox` | `({width, height = 14, radius})`; `SkeletonBox.circle(size:)` |
| `SkeletonLines` | `({lines = 3})` |
| `EmptyState` | `({required icon, required title, required body, actionLabel, onAction})` |
| `DaySwitcher` | `({required date, required onShift(±1), latest, earliest, today, onTapDate})`; helpers `shortDay`, `longDay`, `dayMonth`. The label swaps instantly |
| `DaySwitcherSkeleton` | `()`: the switcher's 48 dp footprint while the day is unknown |
| `TrendArrow` | `({required trend (TrendResult?), required upIsGood (bool?), metric, size, showLabel})`. Renders nothing unless the trend is significant |
| `ProvenanceChip` | `({required label, icon, onTap, plain})` |
| `ProvenanceChip.of` | `(Provenance, {plain})`; `describe(p)` |
| `NumberSwap` | `(text, {required style})`: for rare changes only (a sync), never for a number that ticks every second (Live) or changes on a day step |
| `EnterFade` | `({required child, index, enabled, step = Motion.stagger})`: one-time stagger, 30 ms per item by default (`Motion.staggerTiles`, 50 ms, for a few large tiles), capped at 8 items |
| `FadeSwap` | `({required swapKey, required child})`: a status that changes in place (a pill after coming back from Health Connect) crossfades in 160 ms, enter curve in, flipped out; a short fade under reduced motion. `DotStat(swap: true)` uses it for a number that changes on the same screen |
| `ThinkingDots` | `({color, size = 6})`: three dots fading in turn while the coach answers. The only (bounded) loop: `Motion.dotsCycles` cycles of 4 × `Motion.dotStep`, then they rest at 60 %; static under reduced motion |
| `OverLabel` | `(text)`: an uppercase group label |
| `KeyValueLine` | `(label, value, {valueColor})`: the value in tabular figures |
| `BulletLine` | `(text, {icon, strong, large = false})`: a dot or icon line with an optional bold lead-in. `large` uses body size, for the privacy policy |
| `snack` | `(context, message)`: replaces any visible snack bar; uses `snackMotion` |
| `InfoButton` | `({required title, lede, children, semanticLabel, footnote, color})`: the 48 dp ⓘ that opens `showExplainSheet`. Long explanations live there, never as paragraphs. Import it from `app/screen_kit.dart` (it re-exports `design/components/info_button.dart`). Never type the ⓘ character in copy: DM Sans has no glyph for it |
| `IconBadge` | `({required icon, accent, size = 36})`: an icon in a tinted circle; neutral without an accent. Same import as `InfoButton` |
| `StatePill.tone` | `(PillTone, label)`: `good` (health), `off` (neutral), `beta` (lavender), `attention` (amber), `locked` (neutral, lock icon). The label is always required |
| `SettingsTile` | `({required children, title, icon, accent, status, info, glow, dividers = true, semanticLabel})`: a flat card (or a glow panel for a screen's hero tile) with an optional header: badge, title, pill, ⓘ |
| `SettingsRow` | `({required icon, required title, subtitle, pill, trailing, onTap, semanticLabel, accent})`: the subtitle wraps, never truncates; a chevron when tappable |
| `SettingsSwitchRow` | `({required title, required value, onChanged, icon, subtitle, pill, accent})`: the whole row toggles; spoken as one switch |
| `SettingsValueRow` / `SettingsBlock` | `(title, value)` read-only line · `({required child, indent, top, bottom})` any other content, inset to the tile |
| `MetricChip` | `({required label, icon, count, style = used\|available\|add\|penalty\|muted})`: a small non-interactive chip naming a measurement ("HRV 14/14") |
| `NavTile` | `({required icon, required title, accent, status, caption, onTap, selected, semanticLabel})`: a bento tile that navigates (chevron), chooses (`selected`: a radio in a group) or just states (no `onTap`) |
| `NavTileGrid` | `({required children, oneColumnBelow = 296})`: two per row at equal height, one per row at large text; never scaled (unlike `BentoGrid`, it holds controls) |
| `DotStat` | `({required value, unit, caption, color, style = F.dot32, semanticsLabel})`: a dot-matrix number with its unit and caption. The number scales down to fit. Values are unsigned: say the direction in the unit ("pts lower") |

## Charts (`lib/design/charts/`)

Every chart:
- takes a `semanticsLabel`, otherwise it generates a spoken summary;
- has real axes, except `Sparkline`;
- accepts dense series with `null` for gaps;
- shows a `NoData` state when empty.

| Chart | Signature |
|---|---|
| `ChartFrame` | `({required title, required unit, required child, height = 120, yAxis, yAxisRight, unitRight, xLabels, legend, footnote, series, semanticsLabel, empty, xMarks, trailing, showUnit = true})`. `showUnit: false` hides the printed unit when `trailing` already states it; the spoken label keeps it |
| `BaselineBandChart` | `({required title, required unit, required values, required color, mean, lower, upper, highlightIndex, xLabels, axis, format = axisInt, height = 132, footnote, semanticsLabel, emptyMessage, trailing, showUnit = true, xMarks})`. The band may be **one-sided**: pass only `lower` (the SpO₂ floor) or only `upper`, and the shade runs to the open edge and fades out. `xMarks` are dotted verticals at fractions `i / (n − 1)` of the series (a change of source), drawn on the data's own x positions; explain them in `footnote` |
| `ContributionBars.recovery` | `({required components, penalties, required color, score})` |
| `ZoneTimeline` | `({required samples, required start, required end, required zoneFloors (5 bpm), title, workouts, rest, maxGapMinutes = 10, height = 150, axis, semanticsLabel})` |
| `ScatterConsistency` | `({required nights (List<NightWindow?>), title, xLabels, height = 170, semanticsLabel})` |
| `DualAxisChart.recoveryStrain` | `({required recovery, required strain, xLabels})` |
| `AcwrGauge.fromLoad` | `(TrainingLoad?, {title = 'Training load'})`. The title is printed in both the empty and the measured state whenever it is non-null |
| `Sparkline` | `({required values, required color, height = 28, width, lower, upper, mean, showLast, semanticsLabel})`. Either band edge may be null on its own (a one-sided band). `mean` draws the usual as a dotted line when there is no range |
| `HypnogramChart` | `({required stages, start, end, title, height = 132, semanticsLabel})` |
| `InputWeightBar` | `({required parts, semanticsLabel})`, `WeightPart(label, value, color, {valueText, hatched})`: one bar split by share or amount; hatched parts are "up to" amounts. Static |
| `WeightStepBars` | `({required steps ((label, from, weight)), required color, weightText, semanticsLabel})`: multiplier columns; rows at large text |
| `BandScale` | `({required bands (ScaleBand), semanticsLabel})`: equal bands with ranges (the Medium/20 scale without a marker) |

Ported painters: `LineChart`, `Bars`, `Ring`, `DashedRing`, `Hypnogram`, `ZoneBar`, `Actogram`, `HeatMap`, `NightStack`, `DayLanes`.

Axis helpers: `AxisSpec.of`, `axisInt`, `axisHm`, `axisFixed`, `clockHm`, `clockOf`, `denseSummary`. Legend labels use tabular figures.

## Formatters (`lib/design/format.dart`)

| Helper | Output |
|---|---|
| `signed(v, decimals, {plus = true})` | `"+0.1"`, `"−0.3"`, `"0.0"`. Rounds first, then signs; U+2212 minus |
| `numText(v)` | A constant as prose: `8`, `0.03`, `1.65` |
| `sourceName(kind)` | A source as the UI names it: "Enhanced mode" for the cloud source, "Bluetooth", else `SourceKind.label` |
| `durationWords(minutes)` | `"37 min"`, `"1h 05m"` |
| `clockSeconds(seconds)` | `"0:42"`, `"1:02:33"` |
| `dayTime(t)` | `"28 Sep 07:12"` |
| `distanceText(m)` / `kcalText(kcal)` | `"5.21 km"`, `"820 m"`, `"412 kcal"`, or null when missing |
| `zoneRanges(lowerBounds, {withRest})` | `"50–60 %"` … `"90–100 %"` from the engine's zone bounds |

## Tokens

The look is a 1:1 copy of the user's own Figma widget PNGs (`Widget/{Small,Medium,Large}/N.png`). Every colour, size and radius below was sampled from them; nothing is eyeballed. The app is **dark only**: `P` has one palette, `buildTheme()` always returns the dark theme, and screens without a PNG reuse the same tokens and surfaces.

- **Surfaces (`P`):** bg `#080808`, card `#141414`, card2 `#1F1F1F`, sheet `#1A1A1A`, line `#2A2A2A`, track `#262626`, skeleton `#1C1C1C`; ink white, ink2 `#B8B8B8`, ink3 `#A0A0A0`. `P.of(context)` and `const P()` return the same palette.
- **Pigments (`C`):** the PNGs' hues, for example `recGreen #16B364`, `recYellow #FAC515`, `recRed #EF4444`, `strain #EF6820`, `sleep #1570EF`, `health #15B79E`, `amber #F79009`, `lime #A3E635`, `limeSoft #A2EC82`, the `green800…green200` scale of the training-load bands, and the translucent white overlays (`panel`, `plate`, `track`, `tick`, `stripe`, `hatch`, `ring`, `badge`).
- **`TileInk`:** the tiles' text inks, as white at the PNGs' measured opacities: `primary` 1.0, `unit` .88, `soft` .78, `unitSoft` .70, `dim` .65, `axis` .64, `secondary` .55, `tertiary` .40, `faint` .34.
- **Glow (`GlowRecipe`, `GlowRecipes.s2…l8`):** each tile background is a base fill plus 2–4 soft ellipses (`GlowBlob`: centre, radii, rotation, softness, colour, alpha), painted as `RadialGradient`s with 24 erfc stops. No blur runs per frame; a recipe paints once inside a `RepaintBoundary`. `GlowRecipes` is generated by `tool/figma/gen_glow.py` from the fits in `tool/figma/bgfit.json`. Do not edit it by hand.
- **Shape:** `R.tile` 24.1 with Figma corner smoothing `R.tileSmoothing` .98 (`tilePath`, ported from figma-squircle, MIT). `AppCard`, sheets and panels use the same `TileBorder`.
- **Layout (`S`):** `tileW` 164, `tileTallH` 218, `tileWideW` 348, `tileLargeH` 365, `tileGap` 20, `tilePad` 16. Two 164 columns with a 20 gutter make the 348 grid, centred. Below `gridMinWidth` (360 dp), `BentoGrid` scales the whole grid uniformly. Tiles are never stretched.
- **Type (`F`):**
  - `F.ui` is **DM Sans** (variable, OFL), the closest open-licence match to the PNGs' UI face. One family for all UI text. `F.scaled` also updates the `opsz` axis. SpO₂'s subscript ₂ falls back to Manrope 500, because DM Sans has no U+2082.
  - The tile ramp, measured from the PNGs (weight 500, −2 % tracking): `tileHeadline` 24, `tileNumber` 20, `tileTitle`/`tileStatus` 16, `tileBody` 14, `tileLabel` 12, `tileMicro` 10, `tileTiny` 8.
  - The app ramp, for screens without a PNG: `display`, `t1`, `t2`, `head`, `body`, `bodySm`, `cap`, `micro`, `over`.
  - `F.numerals` is **Subway Ticker Grid** (dot matrix): `dot72`, `dot48`, `dot40`, `dot36`, `dot32`, `dot28`, `dot24`. The old numeral names `n96`, `n64`, `n44`, `n32`, `n24` and `n18` map onto it.
- **Motion:**
  - Durations: press 120 ms, release 90 ms, 160, 200 and 280 ms, exit 180 ms, sweep 700 ms. Staggers: 30 ms for lists (`Motion.stagger`), 50 ms per large onboarding tile (`Motion.staggerTiles`), 50 ms for the few cards under a coach answer (`Motion.cardStagger`, first 3 cards).
  - Curves: enter (0.23,1,0.32,1), move (0.77,0,0.175,1), drawer (0.32,0.72,0,1).
  - `motion(c, d, {fade})` zeroes movement under reduced motion.
  - **Exits use the flipped curve.** A reverse runs its curve backwards, so an exit that reuses the enter curve plays as an ease-in. Every reverse or switch-out curve is `Motion.enter.flipped` or `Motion.drawer.flipped`.
  - `sheetMotion(c)` for bottom sheets: 280 ms in, 180 ms out, drawer curve, flipped on exit. It is a hard cut under reduced motion, because the sheet's only transition is a slide.
  - `dialogMotion(c)` for `showDialog`: a centred 160 ms fade on the strong ease-out. Modals never scale from a trigger. The fade stays under reduced motion.
  - `snackMotion(c)` for snack bars: 200 ms in, 160 ms out. No animation under reduced motion.
  - No animation on a tab switch.
- **`DomainColors`:** maps recovery zone, HR zones 0–5, sleep stages, `LoadState` and `BandState` to colours.
- **Contrast exceptions (`DesignContrast.spots`):** where a PNG's own ink fails WCAG, the PNG wins. Each such spot is listed in code with its ratio, checked by `test/design/contrast_test.dart`, and listed in `docs/DESIGN_REVIEW.md`.

## Fonts

| Face | File | Licence | Setup |
|---|---|---|---|
| DM Sans (variable) | `assets/fonts/DMSans/DMSans-Variable.ttf` | OFL 1.1 (`OFL.txt` beside it) | Bundled |
| Subway Ticker Grid | `assets/fonts/SubwayTickerGrid/SubwayTickerGrid.ttf` | K-Type free-font licence (personal use; publishing needs K-Type's Enterprise licence) | **Gitignored.** Place the file yourself (see the README) |
| Doto (variable) | `assets/fonts/Doto/Doto-Variable.ttf` | OFL 1.1 (`OFL.txt` beside it) | **In the repo, not declared in `pubspec.yaml`, so not bundled** |
| Manrope 500 | `assets/fonts/Manrope/` | OFL 1.1 | Bundled; the fallback for ₂ only |

**DM Sans confidence: moderate.** Against 14 text crops from the PNGs (rendered with `tool/figma/measure.py`), DM Sans won 10, with a mean error of 0.319 (Hanken Grotesk 0.327, Figtree 0.367, Plus Jakarta Sans 0.374, Inter 0.382, Manrope 0.399). Letter shapes and widths match well. The digits do not: the design's face has an oval zero and a flagged one, so digit-heavy labels (the minutes on Medium/16) differ most.

Doto (OFL) is the licence-free candidate if the app is published without buying the Subway licence. Swapping means declaring it in `pubspec.yaml`, pointing `F.numerals` at it, registering its `OFL.txt` in `lib/app/licenses.dart`, and re-running the Figma diff harness below (the dot shapes differ, so the dot-numeral tiles will move).

**Dot font coverage.** The face maps ASCII, Latin-1 and U+2212 (minus). `DotMatrixNumber.glyphs` is the set numbers use: `0–9 . , : % + - − /` and space. Missing: the en dash and em dash are in the file but have no ink, and U+2009 (thin space) and U+202F (narrow no-break space) are absent. `DotMatrixNumber.safe` maps these to a hyphen or a space. A missing value is `--` (`DotMatrixNumber.missing`), never a dash glyph.

## Tiles (`lib/design/tiles/`, `lib/design/components/{tile,bento,dot_matrix,sample_data}.dart`)

Every label and value is a parameter; the tiles hold no copy of their own. A missing number is `--` plus a status word ("No data last night", "Learning").

At large text settings, `GlowTile` provides a readable, reflowing alternative based on its complete semantic label instead of shrinking fixed-coordinate labels. Keep that label complete and meaningful, including units, unknown states and action context. Verify both standard and large-type layouts on the release device.

**Kit**

| Widget | Signature |
|---|---|
| `GlowTile` | `({required size (TileSize.small\|tall\|medium\|large), required glow (GlowRecipe), children, onTap, semanticLabel})`. Children are positioned at the PNG's 1× coordinates and clipped to the tile shape |
| `TileText` | `(text, {required baseline, style, x, right, centerX, color, maxWidth})`: text placed by pen x and alphabetic baseline, as measured in the PNG |
| `DotMatrixNumber` | `(text, {style = F.dot32, color, semanticsLabel})`. Text, not a painter. Also `missing`, `glyphs` and `safe()` |
| `BentoGrid` | `({required children, spacing = S.tileGap})`: the 348 grid, scaled uniformly below 360 dp |
| `GlowPanel` | `({required child, glow = GlowRecipes.m8, padding, onTap, semanticLabel, width = S.tileWideW})`: a glow surface of any height (the plan) |
| `TileSkeleton` | `({required size, height})`: a tile's footprint while loading |
| `SampleDataScope` / `SampleDataChip` | The "Sample data" chip. `SampleDataChip.action(context)` returns the chip for an AppBar in sample-data mode, and nothing otherwise. Every Scaffold shows it |
| `PlanTile` | `({required plan (TodayPlan), required onOpen(route)})`. Renders the plan as given: headline, summary, evidence chips, 0–3 actions, and the provisional, stale, evening, basis and re-learning variants |

**Tile → PNG → metric map**

| Tile | PNG | Where | Metric shown |
|---|---|---|---|
| `ReadinessTile` | Large/5 | Today | Recovery %; HRV vs usual; resting HR (or sleeping HR) vs usual; the last days' recovery steps against the usual line |
| `ArcScoreTile` | Small/2 | Today | Strain 0–21 against today's target. Without heart rate there is no score, and activity facts show instead |
| `RingScoreTile` | Small/5 | Today | Sleep performance % and time asleep |
| `LineBaselineTile` | Small/8 | Today | HRV (ms) in the usual band |
| `ArcBaselineTile` | Small/6 | Today | Resting HR (bpm) in the usual band |
| `BandBaselineTile` | Small/7 | Today | Respiratory rate (/min) and SpO₂ (%) in the usual band |
| `TopArcTile` | Small/9 | Today | Skin temperature change (°C) in the usual band |
| `HealthAlertTile` | Medium/5 | Today (only when a vital is out of range) | The readings outside the usual band, with the engine's fixed alert copy |
| `ProgressTile` | Medium/12 | Today (while calibrating) | Nights of baseline collected, "of N nights" |
| `SleepSummaryTile` | Large/1 | Sleep | Time asleep, performance, sleep target, the stage timeline and totals |
| `ArcStateTile` | Large/6 | Strain | Strain vs target, workout calories, active minutes |
| `ZoneBarTile` | Medium/16 | Strain | Minutes in HR zone groups (Light, Moderate, Hard, Max) |
| `WeeklyBarsTile` | Large/7 | Trends | Strain over the last 7 days: average, highest, most strained day |
| `SegmentScaleTile` | Medium/20 | Trends | Training load (ACWR) on the engine's four bands |
| `WeekDotsTile` | Medium/14 | Journal | Consistency: evenings logged, "X of 7 days" |
| `WorkoutSummaryTile` | Large/8 | Gallery only | Not wired: no screen needs it yet |
| `HeartRateTile` | Medium/10 | Gallery only | Not wired: Live keeps its own zone band |
| `BandMediumTile` | Medium/7 | Gallery only | Not wired: VO₂ max stays a Trends chart ("<source>'s estimate") |

**Home-screen widgets** (`docs/WIDGETS_PLAN.md`) are drawn natively in Kotlin from the same recipes, inks and type (`res/raw/airlog_widget_glows.json`, generated and checked by `test/data/widget_glows_test.dart`):

| Widget | PNG | Metric shown |
|---|---|---|
| Recovery (small) | Small/5 (the `RingScoreTile` look) | Recovery % with Today's status word (Good / Fair / Low, Learning, No data) and basis |
| Today plan (medium) | `PlanTile` vocabulary, glow `PlanTile.glowFor` | The plan's basis, headline and first action with its why |
| Today (medium) | Medium/19 (its macros relabelled) | Recovery %, Strain, Sleep performance %, one plate each |

Cut: Small/17 and Medium/8 (Pulse Age, removed from v1). The other PNGs in `Widget/` show metrics the app does not measure, and are unused.

## Figma diff goldens (`test/goldens/figma_diff_test.dart`)

- Each tile is pumped at dpr 1 with the PNG's own sample values (`test/goldens/figma_fixtures.dart`) and compared with a copy of the PNG in `test/goldens/figma/`. The PNGs are never pubspec assets.
- `FigmaComparator` (a `LocalFileComparator`) diffs premultiplied RGBA with a per-channel threshold of 12/255 and reports differing pixels ÷ area. It refuses `--update-goldens`: the golden is the design, not a render.
- The target is under 3 %. A case may set a higher `limit` only with a `why`. The reasons and current numbers are in `docs/DESIGN_REVIEW.md`.
- Side-by-side sheets (design | render | diff) are written to `docs/screenshots/redesign/compare/`.
- `tool/figma/` holds the sampling scripts (corner, background fit, text measurement).
