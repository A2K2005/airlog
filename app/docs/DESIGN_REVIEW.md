# Design review

This pass applies Emil Kowalski's design-engineering rules to the design system and to every screen. It also covers what the regenerated goldens show about hierarchy, spacing and contrast. Each row is one issue.

**Status:**
- **Fixed** means the change is in the code and a test or golden covers it.
- **Kept** means the row explains why the current behaviour stays.

## Figma redesign

The UI is now a 1:1 copy of the user's own Figma widget PNGs (`Widget/`), dark only. The sections after this one predate the redesign. Where they mention the light theme, Manrope or Barlow, that no longer applies.

### Fidelity to the PNGs

Diff = pixels differing by more than 12/255 in any premultiplied channel ÷ tile area, at dpr 1 with the PNG's own sample values (`test/goldens/figma_diff_test.dart`). MAE is the mean absolute channel error (0–255). The side-by-side sheets (design | render | diff) are in `docs/screenshots/redesign/compare/<tile>.png`.

| Tile | PNG | Diff | MAE | Limit | What differs |
|---|---|---|---|---|---|
| `SleepSummaryTile` | Large/1 | 3.77 % | 2.49 | 4.5 % | Text anti-aliasing |
| `ReadinessTile` | Large/5 | 10.25 % | 4.39 | 11 % | The step chart is a true linear scale (bar height is data). The design places its sample bars by eye: its two "80" blocks sit 28 px higher than any linear scale puts them. An ordinal scale scored 3.80 % and was rejected (see the conflicts below) |
| `ArcStateTile` | Large/6 | 6.43 % | 4.62 | 7 % | The arc's ribbed hatching is not reproduced (a hatch was tried and raised the diff to 7.8 %); emoji icons are Material icons |
| `WeeklyBarsTile` | Large/7 | 5.43 % | 2.45 | 6 % | Text anti-aliasing |
| `WorkoutSummaryTile` | Large/8 | 5.57 % | 4.60 | 6 % | The design hand-kerns the "1" of 1.820 5 px tighter than the face |
| `HeartRateTile` | Medium/10 | 6.60 % | 3.65 | 7 % | The waveform stroke's anti-aliasing (the line is data; the fixture digitises the PNG's) |
| `ProgressTile` | Medium/12 | 3.01 % | 2.80 | 3.5 % | Text anti-aliasing |
| `WeekDotsTile` | Medium/14 | 4.60 % | 2.87 | 5 % | Text anti-aliasing |
| `ZoneBarTile` | Medium/16 | 5.99 % | 3.63 | 6 % | The design's digits are not DM Sans (an oval zero, a flagged one) |
| `SegmentScaleTile` | Medium/20 | 5.74 % | 3.65 | 6 % | Text anti-aliasing |
| `HealthAlertTile` | Medium/5 | 4.89 % | 2.70 | 5.5 % | Text anti-aliasing |
| `BandMediumTile` | Medium/7 | 5.39 % | 2.50 | 6 % | Text anti-aliasing |
| `ArcScoreTile` | Small/2 | 4.85 % | 3.02 | 5.5 % | Dot-numeral anti-aliasing |
| `RingScoreTile` | Small/5 | 5.20 % | 2.68 | 6 % | The squiggle's exact shape; text anti-aliasing |
| `ArcBaselineTile` | Small/6 | 5.33 % | 3.10 | 6 % | Dot-numeral anti-aliasing |
| `BandBaselineTile` | Small/7 | 4.21 % | 2.56 | 5 % | Text anti-aliasing |
| `LineBaselineTile` | Small/8 | 5.33 % | 3.34 | 6 % | Dot-numeral anti-aliasing |
| `TopArcTile` | Small/9 | 5.32 % | 3.24 | 6 % | Dot-numeral anti-aliasing |

"Text anti-aliasing" means the test rasteriser hints glyphs to the pixel grid and the design tool does not. Supersampling, mask filters and a sub-pixel transform were each tried to soften the hinting. None beat plain text overall, so plain text shipped. Backgrounds match to an RMS of 0.2–1.6/255 and the corner shape to within one anti-aliased pixel.

### Contrast: where the PNG wins

These inks fail WCAG AA in the design itself. The brief says the PNG wins, so they ship as designed. Each is listed in `DesignContrast.spots`, and `test/design/contrast_test.dart` re-measures every ratio. Tile titles and values (`TileInk.primary`, `unit`, `secondary`) clear 4.5:1 on the darkest tile core, and `textContrastGuideline` passes on the rendered screens (`test/features/accessibility_guidelines_test.dart`).

| Tile | Text | Ink | Background (sampled) | Ratio |
|---|---|---|---|---|
| Large/1 | 01:42 | `TileInk.faint` (white .34) | `#292624` | 3.05 |
| Large/7 | Calories Burned | `TileInk.tertiary` (white .40) | `#723D10` | 2.77 |
| Large/7 | KCAL | `TileInk.tertiary` | `#3C250D` | 3.56 |
| Large/7 | M | `TileInk.tertiary` | `#0A0A0A` | 3.77 |
| Large/7 | MIN | `TileInk.tertiary` | `#0A0A0A` | 3.77 |
| Large/7 | Most Active Day: | `TileInk.secondary` (white .55) | `#854212` | 3.45 |
| Large/7 | S | `TileInk.tertiary` | `#0A0A0A` | 3.77 |
| Large/7 | Total | `TileInk.tertiary` | `#0A0A0A` | 3.77 |
| Large/7 | W | `TileInk.tertiary` | `#0A0A0A` | 3.77 |
| Medium/5 | 01:00 | `TileInk.axis` (white .64) | `#1C5C84` | 3.99 |
| Medium/5 | 06:00 | `TileInk.axis` | `#1F678F` | 3.54 |
| Medium/5 | 12:00 | `TileInk.axis` | `#1F678F` | 3.54 |
| Medium/7 | VO2Max | `TileInk.primary` (white) | `#72D88F` | 1.75 |
| Small/2 | ml | `TileInk.unitSoft` (white .70) | `#8C9658` | 2.36 |
| Small/5 | 06:00 | `TileInk.tertiary` | `#132218` | 3.76 |

In the app the labels differ from the PNG's sample text, but the ink and background at each position are the same.

### Before | After | Why

| Before | After | Why |
| --- | --- | --- |
| Rounded-rect cards on a near-black ramp, with a light theme | Squircle tiles (R 24.1, smoothing .98) on sampled glow backgrounds; dark only | The brief: a 1:1 copy of the PNGs, one theme. **Fixed** |
| Manrope for UI, Barlow Condensed for numerals | DM Sans for UI; Subway Ticker Grid for tile numerals, as text (`DotMatrixNumber`) | The PNGs' faces. DM Sans is the closest open-licence match (moderate confidence); the dot face is the design's own. **Fixed** |
| Glow would have meant a blur per frame | Base fill plus fitted ellipses as radial gradients, painted once in a `RepaintBoundary` | No per-frame blur. **Fixed** |
| Today: day switcher, three rings, Health monitor grid, Journal card, profile nudge, summary card | Header (date, one freshness line per app, Sample data chip, ⋯ More), the plan, Recovery (Large/5), Strain and Sleep tiles, vitals against the usual band, an alert tile only when a vital is out of range, calibration, one "Data notes" row | One answer first (the plan), then the three scores, then the evidence. **Fixed** |
| A 0–21 strain number even with no heart rate | "--" and the day's activity facts | No score without its input. **Fixed** |
| A streak | "Consistency X of 7 days" | A streak punishes one missed evening. **Fixed** |
| Insight feed on Today | At most one insight card, on the Recovery, Sleep and Strain screens only | Today stays one answer. **Fixed** |
| Demo badge on some screens | "Sample data" chip on every Scaffold and on Today's header | Sample data must never pass for real data. **Fixed** |
| Tab chosen before process death was lost | Restored (`RestorableInt`, `restorationScopeId`) | QA-18. **Fixed** |
| Onboarding back button marked onboarding as seen; the dashboard flashed first | Back steps back; seen only on a choice; a blank page while the gate decides | QA-04, QA-05. **Fixed** |
| Sources suggestion as a dialog on open | An inline card, asked once per metric and app | A dialog on arrival is a surprise, and its scrim failed the contrast test. **Fixed** |
| Light goldens | Deleted; all goldens are dark | Dark only. **Fixed** |
| Readiness chart on an ordinal scale (3.80 %) | Linear scale (10.25 %) | Bar height is data; PRODUCT_PLAN §7 puts truthful data above pixel match. **Kept** |

## Motion

| Before | After | Why |
| --- | --- | --- |
| `sheetMotion` set no `reverseCurve`, so a closing sheet ran Flutter's `legacyDecelerate` backwards, which is an ease-in | `reverseCurve: Motion.drawer.flipped`, 280 ms in and 180 ms out | A reverse runs its curve backwards. An exit has to start fast, at the moment the user is watching. **Fixed** |
| `NumberSwap` used `switchOutCurve: Motion.enter`, which plays backwards as an ease-in on the outgoing number | `switchOutCurve: Motion.enter.flipped` | Exits ease out too. **Fixed** |
| The onboarding step `AnimatedSwitcher` had the same backwards `switchOutCurve` | `Motion.enter.flipped` | Same as above. **Fixed** |
| `showDialog` used Material's default: 150 ms, `easeOut` both ways (so the exit ran as an ease-in) | `dialogMotion`: a centred 160 ms fade, `Motion.enter` in and `Motion.enter.flipped` out | Modals stay centred and do not scale from a trigger. A fade survives reduced motion. **Fixed** |
| Snack bars used the default 250 ms in and 250 ms out | `snackMotion`: 200 ms in, 160 ms out; no animation under reduced motion | Exits are faster than enters. **Fixed** |
| The onboarding dots were an `AnimatedContainer` animating `width`, a layout property | One fixed-size `CustomPaint` whose painted pill moves, 200 ms `Motion.move` | Animate paint, not layout. The row never re-lays out. **Fixed** |
| Live `ZoneBand` segments were an `AnimatedContainer` (it animates whatever changes) | `TweenAnimationBuilder<Color?>` on the colour only | This is the `transition: all` equivalent. Name the one property that animates. **Fixed** |
| The `DaySwitcher` label crossfaded through `NumberSwap` on every day step | Plain `Text`, swapped instantly | People step days tens of times a day, so it gets no animation. **Fixed** |
| On a day step, every ring (Today's three, the Sleep, Strain and Recovery heroes) morphed for 280 ms from the previous day's value | Rings are keyed by the day shown, so a new day's ring is drawn at once. The morph is left only for a same-day update, such as a sync | Same as above. **Fixed** |
| The Live BPM crossfaded with a blur every second | Instant tabular swap, `F.n96` | A 200 ms blur every 1000 ms leaves the number blurred a fifth of the time. A number that updates at 1 Hz gets no animation. **Fixed** |
| The Live stats (elapsed, strain, average) crossfaded every second | Instant tabular swap | Same as above. **Fixed** |
| Today's rings sat inside the card stagger (`EnterFade` index 0), so on first data they vanished and faded back in | The rings are outside the stagger; their once-a-day sweep is their entrance | One entrance per element, and no flash between the skeleton and the data. **Fixed** |
| Hold-to-delete was a Material `TextButton` with its own `AnimatedScale` press feedback beside Pressable's | Built on the new `Pressable.onPressDown` / `onPressUp` / `onPressCancel`: a 2 s linear fill while pressed and a 200 ms ease-out snap back on release | One press primitive. Slow where the user decides, fast where the system answers. **Fixed** |
| The page transition is a 280 ms fade plus a 3 % rise; the back transition is 180 ms | Unchanged | It already follows the rules: under 300 ms, exit faster, ease-out, and fade-only under reduced motion. **Kept** |
| The bottom sheet is a hard cut under reduced motion (no fade) | Unchanged | Flutter's modal sheet route has only a slide. A fade would need a custom route for one rarely seen case. **Kept** |
| `themeAnimationDuration` lerps every theme colour over 200 ms | Unchanged | It changes colour only (no layout), and only when the system theme flips. **Kept** |
| `ExplainSheet` sections stagger in (30 ms) while the sheet slides up | Unchanged | Sheets open occasionally. The stagger is at most 30 ms per item, capped at 8 items, and never blocks input. **Kept** |
| Popovers that scale from their trigger | Not applicable | The app has no menus, popovers or tooltips. Sheets and dialogs are modal and stay centred. **Kept** |
| Pull to refresh uses Material's default indicator motion | Unchanged | It is the platform idiom. **Kept** |

## Interaction and accessibility

| Before | After | Why |
| --- | --- | --- |
| Tappable rings, metric tiles and cards were an unlabelled button node wrapped around a labelled container. `labeledTapTargetGuideline` failed on Today | `Pressable` merges its subtree (`MergeSemantics`), so the child's spoken summary becomes the button's label | One focus stop with one label for a screen-reader user. **Fixed**, and guarded by `test/features/accessibility_guidelines_test.dart` on 5 screens × 2 themes |
| `SegmentedControl` segments were 34 dp tall | The pill stays 40 px, but each segment's hit area is the full 48 dp row | Android's 48 dp floor. **Fixed** |
| A tappable `FreshnessLine` was a 32 dp target | 48 dp. Today's header spacer above it was removed so the rhythm stays the same | 48 dp floor. **Fixed** |
| With a screen reader on, a tap on hold-to-delete deleted at once | A screen-reader tap opens the confirm dialog | A delete should never be a single tap. **Fixed** |
| A full 2 s hold opened a second "Delete all data?" dialog | The completed hold is the confirmation | The hold is the deliberate act. Asking twice teaches people to click through. **Fixed** |
| Legend labels carrying numbers ("Green 15", "Baseline 7h 36m") used proportional figures | `F.tab` in `LegendSwatch` | Tabular figures on changing numbers. **Fixed** |
| The quiet `AppButton` had 8 px side padding, so Recovery and Sleep nudged it back with `Transform.translate(-8)` | The quiet kind has no side padding (the hit height stays 48 dp), and the translate hacks are gone | Text buttons line up with the content edge they sit on. **Fixed** |
| Methodology's contents list relied on the quiet buttons' padding for spacing | `Wrap(spacing: S.x4)` | Same as above. **Fixed** |
| Press feedback | Every `Pressable` scales to 0.97 in 120 ms and releases in 90 ms, with an opacity dip under reduced motion | Already correct. **Kept** |

## Hierarchy, layout and honesty

| Before | After | Why |
| --- | --- | --- |
| On first launch, Today, Sleep, Strain and Trends showed a bare skeleton for several seconds while 90 days were seeded | A calm `PreparingNote` ("Preparing 90 days of demo data…") under skeleton rings | People should know why they are waiting, and that it happens only once. **Fixed** |
| On first data, the header grew (the day switcher row appeared) and the ring captions pushed the cards down 20 px | `DaySwitcherSkeleton` holds the switcher's 48 dp, and the rings reserve their caption line (`reserveCaption`) | No layout jump. The test asserts that the ring rect and the switcher top are unchanged. **Fixed** |
| The Sleep hero row centred the ring against the text column, so loading and loaded differed by 1 px | Both are top-aligned | Same as above. **Fixed** |
| The Recovery input cards drew their own header row to avoid `ChartFrame` printing the unit twice beside today's value | `ChartFrame(showUnit: false, trailing: value)` | One header component everywhere. **Fixed** |
| Trends' Training load card printed its own title, because the gauge printed one only when empty | `AcwrGauge` prints its title whenever it is given | Consistent card headers. **Fixed** |
| A change of source appeared only as a footnote on Trends charts | A dotted vertical line at the day, plus the footnote "Dotted line: the source changed…" | Show the break where it happens, not only in prose. **Fixed** |
| The SpO₂ band was faked with `upper: 100` | A one-sided band from the floor, fading toward the open side, with a firm edge | SpO₂ has a floor and no ceiling, so the chart must not invent one. **Fixed** |
| Skin temperature read "±0.0 vs usual 0.1" | "+0.1 °C vs usual +0.1", a real minus sign, and "Same as usual" for a delta that rounds to zero | Signed metrics are signed everywhere. The arithmetic is done on the rounded numbers, so what is shown always adds up. **Fixed** |
| Engine constants were retyped in the explain sheets and on Methodology (1.1, 0.03, 0.8, 90 %, −7, 8/13, 90 min, 208 − 0.7 × age …) | Named constants in the engine, printed through `numText` | The copy cannot drift from the maths. **Fixed** |

## Golden review

These rows come from opening every regenerated golden in the Read tool, not from the code.

I checked 54 changed goldens: Today, Sleep, Strain, Trends, Recovery, Journal, Diagnostics, Live recording, Methodology, the onboarding rationale, Privacy, Settings and Profile, 12 gallery sections and the shell, each in dark and light. The contrast evidence is `textContrastGuideline`, which passes on 9 screens × 2 themes in `test/features/accessibility_guidelines_test.dart`, together with the existing `test/design/contrast_test.dart`.

| Before | After | Why |
| --- | --- | --- |
| On Trends, the unit on a chart with no significant trend ("bpm", "/min") stopped 8 px short of the card edge | `MetricTrendCard` passes a `TrendArrow` only when it is visible. The empty slot used to keep its spacer | Header readouts end on the content edge, like every other card. **Fixed** |
| The Training load readout ("7d 10.4 · 28d 9.5") floated in the middle of its row | `Expanded` instead of `Spacer` plus a loose `Flexible`, so right-aligned text sits on the edge | Same as above. **Fixed** |
| The Live zone band disappeared after it moved from `AnimatedContainer` to a childless `DecoratedBox`, which sizes to nothing. The first preview render caught this | `DecoratedBox(child: SizedBox.expand())`, and a test asserts six 12 px segments | A regression from this pass, caught by looking at the render. **Fixed** |
| Today had about 47 px from the freshness line to the rings once the line became a 48 dp target | The rings' top padding drops from 12 to 4, bringing it back to about 35 px, close to the old rhythm | Spacing rhythm under the header. **Fixed** |
| Profile said weight is "kept as context for future calorie and VO₂ max estimates" | "Not used in any score. It stays with your profile on this phone." | That promise was inaccurate, and the permission list was rewritten to match (weight appears only beside Trends). **Fixed** |
| Adding the one-sided band and signed-tile cases pushed the gallery tiles section past its golden viewport | Kept. The overflow test (`components_test`) still pumps the whole section at 320 px and 1.3× text | The gallery golden is one viewport by design. **Kept** |
| A workout's five stats wrap Calories to a second row at 412 px | Kept | Wrapping is the honest layout for optional stats. The row reads left to right: heart rate, then distance and calories. **Kept** |
| `BulletLine` lines with a dot and with an icon indent their text differently when mixed | Kept | No screen mixes the two kinds in one list; only the gallery does. **Kept** |
