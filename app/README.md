# Airlog (working name)

Airlog answers one question each morning: **how am I, and what should I do today?** It reads what your wearables already record (Fitbit / Google Health, Samsung Health, Oura, any app that writes to Health Connect) and turns it into Recovery, Strain and Sleep scores of its own. Everything is computed on your phone: no server, no account, no analytics. Every number is derived from a source measurement, never invented, and every score shows its inputs.

> Status: Android build running on **demo data** until the band arrives; the Phase 0 probe runs on the real band on day 1 (see [`docs/DAY1_CHECKLIST.md`](docs/DAY1_CHECKLIST.md)). iOS is planned, not built (see [`../IOS_PLAN.md`](../IOS_PLAN.md)).
> Not affiliated with Google, Fitbit, Samsung or WHOOP. Not medical advice.

## What's inside

| Area | What it does |
|---|---|
| **Today** | One plan for the day: a plain-words state (ready, steady, take it easy, rest, still learning, waiting for data), the 1–2 numbers behind it and up to 3 actions. After 18:00 it talks about tonight. Scores are labelled when an input is missing (e.g. "Recovery · without HRV") |
| **Recovery** | Contribution of each input (HRV, resting HR, sleep, respiration; re-weighted when one is missing); each input inside its 30-day baseline band |
| **Sleep** | Stages; slept vs sleep target (baseline + debt + strain); debt; consistency; bedtime recommendation |
| **Strain** | HR timeline by zone; minutes per zone; per-workout strain; target strain for today's recovery. No strain score without heart rate |
| **Trends** | 7 / 30 / 90 days; trend arrows only when statistically significant (Mann-Kendall) |
| **Journal** | Evening tags and what they are *associated with* in next-day recovery (≥10 days per group, Holm-corrected, with a confidence interval) |
| **Coach** (optional) | Ask about your data in plain words, with your own Claude or Gemini key. Answers are grounded in tool calls and checked by a verifier (every number must match your data), an output policy (no diagnosis, red-flag handling) and a prompt-injection filter. Daily request and token budget. Can be hidden entirely |
| **Sources** | Any app via Health Connect, plus the Google Health API. One source per metric, chosen automatically and changeable; switching sources re-learns your baseline instead of mixing devices |
| **Live** | Bluetooth heart rate (standard 0x180D): live zones and strain |
| **Settings** | Sources, profile, sync log, export (CSV + JSON), methodology with citations, licences, delete everything |
| **Widget** | Home-screen Recovery, Strain and Sleep |

**HRV without guessing:** HRV is taken from the best nightly source available (Google Health deep-sleep RMSSD, then Health Connect sleep RMSSD). Spot readings are ignored, and HRV is never estimated from heart rate. With no HRV, Recovery is shown "without HRV" with its coverage.

## Design
The UI is a 1:1 build of my own Figma widget designs (`Widget/`), checked by golden diff tests. Numerals use a dot-matrix face; motion follows short ease-out rules and respects reduced motion. See [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md).

## Architecture
Clean Architecture boundaries, Riverpod MVVM view-models, feature-first presentation. Scoring lives in a pure-Dart domain layer. See [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Build and run (Windows)

The toolchain lives on `D:\dev` (Flutter 3.47.5, JDK 17, Android SDK). Dot-source the env script in every new PowerShell window:

```powershell
. .\tool\env.ps1
flutter pub get
flutter analyze
flutter test                     # domain, data, coach evals, widgets, goldens
```

**Before the first build, add the dot-matrix font** (see *Setup* below). Without it the build stops at the font asset step.

**Run on the emulator or a phone**

```powershell
flutter emulators --launch airlog_api35   # Pixel 7, Android 15 AVD
flutter run                                # debug, hot reload
flutter run --profile                      # timing and frame checks
```

**Release APKs.** Build from PowerShell; Gradle fails from Git Bash on this machine.

```powershell
flutter build apk --release                  # one APK for every ABI
flutter build apk --release --split-per-abi  # one smaller APK per ABI
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

The outputs are in `build\app\outputs\flutter-apk\`:
- `app-release.apk` (all ABIs);
- `app-arm64-v8a-release.apk` for current phones;
- `app-armeabi-v7a-release.apk` and `app-x86_64-release.apk` for older phones and the emulator.

Release builds are signed with the debug key (`android/app/build.gradle.kts`). That is fine for sideloading but not for Play; see [`docs/PLAY_RELEASE.md`](docs/PLAY_RELEASE.md).

For startup timing marks in logcat (`adb logcat -s flutter | findstr airlog.timing`), add `--dart-define=AIRLOG_TIMING=true` to a profile or release build.

### Demo mode

The first screen asks how to start:
- **Connect Health Connect.** This reads your own wearable data (live mode).
- **Try with sample data.** This is demo mode: 90 days of synthetic data generated on the phone, in a worker isolate, the first time you choose it. The demo includes a planted illness episode, so the alerts and status cards have something to show.

In demo mode:
- A "Sample data" chip sits on every screen. Coach answers are tagged the same way.
- Nothing is read from Health Connect.
- The data is regenerated once a day so that its 90 days end today. Before the night is complete (roughly 00:00–10:30), it is refreshed at most hourly, so Today may show a partial night in the small hours.
- Live Bluetooth heart rate uses a simulated band.

Switch at any time in **Settings → Data mode**. Demo and live data are stored apart and never mix. **Settings → Delete all data** wipes both, and in demo mode the sample data is then generated again.

### Setup: the dot-matrix font

The tile numerals use **Subway Ticker Grid** by K-Type. Its licence doesn't allow redistribution, so `assets/fonts/SubwayTickerGrid/*.ttf` is **gitignored** and a fresh clone doesn't have it. Before building, download it from k-type.com and place it at:

```
assets/fonts/SubwayTickerGrid/SubwayTickerGrid.ttf
```

K-Type's free licence covers personal use only. **Publishing the APK or the repository needs their commercial (Enterprise) licence**, or a swap to an OFL dot-matrix face.

### Optional: Enhanced mode and the coach

Enhanced mode (Google Health API) needs an OAuth client id:

```powershell
flutter run --dart-define=GOOGLE_OAUTH_CLIENT_ID=<your-android-oauth-client-id>
```

Without it, Enhanced mode shows "Not configured" and everything else works.

The coach works on-device with no key. For Claude or Gemini, paste your own API key in **Settings → Coach**; it is kept in Android's encrypted storage. The opt-in live eval (`tool/eval_live.dart`) costs money; see [`docs/EVALS.md`](docs/EVALS.md).

## Credits
- Scoring formulas ported from [Luraxx/pulse](https://github.com/Luraxx/pulse) (Apache-2.0), see `third_party/pulse/`.
- Chart painters, design tokens, the BLE heart-rate parser and the Manrope font adapted from [OpenStrap/edge](https://github.com/OpenStrap/edge) (MIT; fonts OFL), see `third_party/edge/`.
- UI font: DM Sans (OFL). Tile corner smoothing ported from figma-squircle (MIT).
- Methods: Karvonen HRR zones, Banister TRIMP, Plews lnRMSSD smallest worthwhile change, Mann-Kendall trend test, Holm correction.
