# Dynamic UI contract

Updated 2026-09-30. This is a source-level coverage map and regression plan, not a claim of physical-device verification. Active screens use repository/domain values; explicit sample data and the debug Gallery remain intentionally synthetic. Static colors, geometry, thresholds, units and weekday names are presentation or algorithm configuration, not invented measurements.

## Active design tiles

| Surface / widget | Dynamic source and behavior | Missing/partial behavior |
|---|---|---|
| Today: `PlanTile` | `TodayMapper` / `TodayPlanner`, selected bundle, current time, journal state | Waiting, calibration, stale and low-confidence variants; no effort prescription from low confidence |
| Today: `ReadinessTile` | Recovery score/quality, component values versus baseline, recorded recovery history | Missing/calibrating score withheld; historical steps are recorded scores, not fixture bars |
| Today: `ArcScoreTile` | Daily strain and strain/21 progress | No usable score means no arc marker; activity facts remain context |
| Today: `RingScoreTile` | Sleep performance and duration | Missing sleep has no value marker. Ring squiggle is a decorative end marker, not a measured waveform |
| Today: `LineBaselineTile` | HRV value, status and normalized baseline position | Unknown or one-sided bounds now hide the marker rather than inventing centre |
| Today: `ArcBaselineTile` | Resting/sleeping HR value, status and baseline position | Same unknown-bound rule |
| Today: `BandBaselineTile` | Respiration or SpO₂ value and status | SpO₂'s one-sided floor is not a two-sided distribution; measured text remains but normalized marker is hidden |
| Today: `TopArcTile` | Temperature delta, status, baseline position | Missing measurement/bounds suppress position |
| Today: `HealthAlertTile` | Actual out-of-range readings and judged-metric counts | Only shown for an alert. Count segments have no misleading per-vital axis |
| Today: `ProgressTile` | `Calibration.haveNights`, `needNights`, progress | No fabricated progress or elapsed-day substitution |
| Sleep: `SleepSummaryTile` | `SleepAnalysis`, main-sleep stage intervals, real start/end, recorded totals | Unknown staging stays unavailable; no fabricated Light/Core minutes |
| Strain: `ArcStateTile` | Daily strain, target, recorded workout calories and zone-derived active minutes | Score unavailable if inputs/anchors invalid; no second primary score ring |
| Strain: `ZoneBarTile` | Aggregated real zone minutes, four display groups | Only shown with usable scored input |
| Trends: `WeeklyBarsTile` | Last seven calendar slots of eligible strain, measured-value average/max/day | Nulls are gaps. Title says Last 7 days, not calendar This week |
| Trends: `SegmentScaleTile` | Computed acute/chronic ratio, engine cut-points | Only eligible load; marker maps piecewise into four equal-width bands. Labels describe recorded load, not validated fitness outcomes |
| Journal: `WeekDotsTile` | Actual saved evening entries and their dates | Unlogged days stay unfilled; no invented streak |
| Gallery-only: `WorkoutSummaryTile`, `HeartRateTile`, `BandMediumTile` | Explicit Gallery samples | Not wired to active metric screens; do not mistake them for live measurements |

## Other active cards and charts

| Area | Inputs | Refresh / qualification |
|---|---|---|
| Today headers, source freshness and metric sheets | Current repository mode, source timestamps, selected day, stored metric history | Repository revisions plus reactive `currentTimeProvider` minute/resume ticks; missing data is stated |
| Recovery breakdown, bands and history | Recovery components, penalties, provenance, calibration, historical records | Selected day and sync revisions; estimated score is not measured physiology |
| Sleep target/debt, bedtime, hypnogram, stages, naps, consistency | Engine need breakdown/debt, circular wake history, actual session intervals | Selected night/range; no second primary performance ring; missing stages/restorative share unavailable |
| Strain target basis, timeline, zone totals, workouts and TRIMP | Engine output plus raw HR samples/workout intervals | Same HR anchors drive scoring and colors; partial coverage remains qualified |
| Trends recovery/strain, metric charts, bands and averages | Dense calendar slots and comparable-source/definition data | Selected range and repository revision; unknown days are not zero; current/partial strain excluded from load |
| Live BPM, zones, elapsed time, session summary, HRV check | Connected HR/RR samples, session timer, known HR anchors | Stream/timer driven; no invented 62/187 defaults; unavailable if anchors missing |
| Journal tags and associations | Saved entries, eligible recovery data and corrected association calculations | Saves/revisions; insufficient samples stay unavailable; association is not causation |
| Coach cards/chat | Offline templates or consented provider response with tool context | Not static fixture messages; numerical verification and policy checks are safeguards, not correctness guarantees |
| Sources, profile, sync log, diagnostics | Repository configuration/status, source metadata, probe results | Reads/actions update state; diagnostics require actual permission/device access |
| Methodology, privacy, licences, onboarding explanations | Shipped policy/method text and named constants | Intentionally static explanatory content, not health measurements |
| Loading skeletons | Fixed layout placeholders | Intentionally static, no counterfeit measurements |

## Android launcher widget

Path: repository `_pushWidget` → `WidgetSnapshot.fromDays` → `HomeWidgetSink` → `AirlogWidgetProvider`.

- Snapshot reflects the newest selected-mode day, never yesterday's recovery combined with today's strain.
- Sleep uses the same engine `sleptMinutes` as the app. Duration rounds once before splitting hours/minutes, so 479.8 minutes becomes `8h 00m`, not `7h 60m`.
- Calibration withholds the recovery number. Confidence/calibration and partial-strain qualifiers travel with the snapshot. Empty/deleted data sends placeholders.
- One `airlog_snapshot_v1` JSON preference publishes date, mode, values and quality together. Native rendering does not combine individually updated keys. Pre-upgrade split keys are ignored until the app publishes a new snapshot.
- Native render computes stale date against `LocalDate.now()`, rather than persisting a sticky stale flag. Old data shows its actual date; demo says sample data; empty state says waiting for data.
- Date, time and timezone broadcasts request a redraw; Android's configured periodic update is 30 minutes. These redraw cached data, not a network sync. Android power/scheduling restrictions can delay delivery; this is not guaranteed real-time updating.
- App initialization, successful scoring/sync, profile/source/mode changes, live-session saves and deletion publish refreshed snapshots through the repository. Out-of-order publication protection is part of repository coordination, not the JSON serialization itself.

## Regression coverage and limits

`test/features/dynamic_ui_contracts_test.dart` covers changed input → changed widget score, engine sleep parity, duration carry, recovery calibration, quality flags, empty/deletion payload, no invented baseline position, and load-band marker placement. Existing feature tests cover selected dates, ranges, missing data, source changes and live samples.

New tests must be run in the parent's serialized Flutter integration pass. Kotlin compilation and native widget checks are separate: pin/remove widget, sync, switch demo/live, delete, interrupt sync, cross midnight/change timezone, restart phone, and verify labels at large font sizes. No physical-device or Android scheduling success is established by this document. Source PNG fixtures and explicit demo/Gallery data are preserved.
