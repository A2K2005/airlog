# Airlog (working name)

Airlog turns supported wearable measurements into its own Recovery, Strain and Sleep estimates, with inputs and missing-data states shown. Scores are computed on your phone; they are wellness heuristics, not clinically validated assessments. There is no Airlog account or analytics service. Optional cloud Coach sends disclosed context to the chosen model provider only after consent; offline coaching stays local.

> Status: Android launch hardening in progress. Automated tests do not establish real-device ingestion, Bluetooth, OAuth or background-sync reliability. Complete [`docs/DAY1_CHECKLIST.md`](docs/DAY1_CHECKLIST.md) before claiming those paths work. Demo data is opt-in; live mode can show no data. iOS is outside this release.
> Not affiliated with Google, Fitbit, Samsung or WHOOP. Not medical advice.

## What's inside

| Area | What it does |
|---|---|
| **Today** | One plan for the day: a plain-words state (ready, steady, take it easy, rest, still learning, waiting for data), the 1–2 numbers behind it and up to 3 actions. After 18:00 it talks about tonight. Scores are labelled when an input is missing (e.g. "Recovery · without HRV") |
| **Recovery** | Input contributions, re-weighted when missing, against comparable prior readings. Low-confidence recovery does not support an effort target |
| **Sleep** | Recorded stages or unavailable; slept vs estimated target (baseline + debt + strain); debt; consistency; bedtime recommendation |
| **Strain** | HR timeline by zone; minutes per zone; per-workout strain; target strain for today's recovery. No strain score without heart rate |
| **Trends** | 7 / 30 / 90 days; trend arrows require comparable inputs and statistical significance. Load excludes today and insufficiently covered days |
| **Journal** | Evening tags and what they are *associated with* in next-day recovery (≥10 days per group, Holm-corrected, with a confidence interval) |
| **Coach** (optional) | Offline summaries or consented cloud questions using your Claude/Gemini key. Tool grounding, numeric verification, output policy and budgets reduce risk but do not guarantee correctness. Can be hidden entirely |
| **Sources** | Any app via Health Connect, plus the Google Health API. One source per metric, chosen automatically and changeable; switching sources re-learns your baseline instead of mixing devices |
| **Live** | Bluetooth heart rate (standard 0x180D): live zones and strain |
| **Settings** | Sources, profile, sync log, export (CSV + JSON), methodology with citations, licences, delete everything |
| **Widget** | Home-screen Recovery, Strain and Sleep |

**HRV without guessing:** HRV is taken from the best nightly source available (Google Health deep-sleep RMSSD, then Health Connect sleep RMSSD). Spot readings are ignored, and HRV is never estimated from heart rate. With no HRV, Recovery is shown "without HRV" with its coverage.

## Design
The dark UI is based on my Figma widget designs (`Widget/`), with intentional accessibility and licensing changes. Bundled OFL Doto replaces the original proprietary numeral face; brighter text and readable large-type tile alternatives take precedence over pixel identity. Historical Figma diffs are not current release acceptance evidence. See [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md).

## Architecture
Clean Architecture boundaries, Riverpod MVVM view-models, feature-first presentation. Scoring lives in a pure-Dart domain layer. See [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Build and run (Windows)

```powershell
. .\tool\env.ps1          # respects configured FLUTTER_ROOT, JAVA_HOME, ANDROID_HOME
flutter pub get
flutter test              # domain, data, coach evals, widgets, goldens
flutter run               # phone via USB, or the emulator:  flutter emulators --launch airlog_api35
flutter build apk --debug # build\app\outputs\flutter-apk\app-debug.apk
```

### Setup and release configuration

Fonts are bundled, including `assets/fonts/Doto/Doto-Variable.ttf` and its OFL licence. No proprietary font download is required. See [`tool/setup_toolchain.md`](tool/setup_toolchain.md) for local SDK configuration. Release builds require the four signing environment variables documented there; debug signing is not a release fallback.

For Enhanced mode (Google Health API), which is optional:

```powershell
flutter run --dart-define=GOOGLE_OAUTH_CLIENT_ID=<your-android-oauth-client-id>
```

Without it, Enhanced mode shows "Not configured" and everything else works.

The Android redirect scheme derives from this same client ID. If your registered redirect differs, pass `--dart-define=GOOGLE_OAUTH_REDIRECT=<registered-uri>` too. Device OAuth verification remains required.

## Credits
- Scoring formulas ported from [Luraxx/pulse](https://github.com/Luraxx/pulse) (Apache-2.0), see `third_party/pulse/`.
- Chart painters, design tokens, the BLE heart-rate parser and the Manrope font adapted from [OpenStrap/edge](https://github.com/OpenStrap/edge) (MIT; fonts OFL), see `third_party/edge/`.
- UI font: DM Sans (OFL). Tile corner smoothing ported from figma-squircle (MIT).
- Methods: Karvonen HRR zones, Banister TRIMP, Plews lnRMSSD smallest worthwhile change, Mann-Kendall trend test, Holm correction.
