# Airlog (working name)

Airlog turns supported wearable measurements into its own Recovery, Strain and Sleep estimates, with inputs and missing-data states shown. Scores are computed on your phone; they are wellness heuristics, not clinically validated assessments. There is no Airlog account or analytics service. Optional cloud Coach sends disclosed context to the chosen model provider only after consent; offline coaching stays local.

> Status: Android launch hardening in progress. Automated tests do not establish real-device ingestion, Bluetooth, OAuth or background-sync reliability. Complete [`docs/DAY1_CHECKLIST.md`](docs/DAY1_CHECKLIST.md) before claiming those paths work. Demo data is opt-in; live mode can show no data. iOS is outside this release (planned, not built: see [`../IOS_PLAN.md`](../IOS_PLAN.md)).
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
The UI is a 1:1 build of my own Figma widget designs (`Widget/`), checked by golden diff tests. Numerals use a dot-matrix face (Subway Ticker Grid). Text inks keep the designs' levels; contrast is fixed only at the spots listed in [`docs/DESIGN_REVIEW.md`](docs/DESIGN_REVIEW.md). At large text settings a tile switches to a readable, reflowing alternative. Motion follows short ease-out rules and respects reduced motion. See [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md).

## Architecture
Clean Architecture boundaries, Riverpod MVVM view-models, feature-first presentation. Scoring lives in a pure-Dart domain layer. See [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Build and run (Windows)

The toolchain lives on `D:\dev` (Flutter 3.47.5, JDK 17, Android SDK). Dot-source the env script in every new PowerShell window:

```powershell
. .\tool\env.ps1          # keeps FLUTTER_ROOT, JAVA_HOME, ANDROID_HOME etc. if set; else D:\dev
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

**Release signing fails closed** (`android/app/build.gradle.kts`). A release task needs all four signing variables: `AIRLOG_KEYSTORE`, `AIRLOG_KEYSTORE_PASSWORD`, `AIRLOG_KEY_ALIAS` and `AIRLOG_KEY_PASSWORD` (see [`tool/setup_toolchain.md`](tool/setup_toolchain.md) and [`docs/PLAY_RELEASE.md`](docs/PLAY_RELEASE.md)). Debug signing is never a silent fallback.

**Local sideload build (explicit opt-in).** With `AIRLOG_LOCAL_RELEASE=1` set and **none** of the four variables set, the release is signed with the debug key and Gradle warns "local sideload build, not for the store". A partial set of the four still fails, and a full set always wins. Never upload such a build to Play.

```powershell
$env:AIRLOG_LOCAL_RELEASE = '1'
flutter build apk --release
Remove-Item Env:AIRLOG_LOCAL_RELEASE
```

For startup timing marks in logcat (`adb logcat -s flutter | findstr airlog.timing`), add `--dart-define=AIRLOG_TIMING=true` to a profile or release build.

### Demo mode

The first screen asks how to start:
- **Connect Health Connect.** This reads your own wearable data (live mode).
- **Try with sample data.** This is demo mode: 90 days of synthetic data generated on the phone, in a worker isolate, the first time you choose it. The demo includes a planted illness episode, so the alerts and status cards have something to show.

In demo mode:
- Nothing is read from Health Connect.
- The data is regenerated once a day so that its 90 days end today. Before the night is complete (roughly 00:00–10:30), it is refreshed at most hourly, so Today may show a partial night in the small hours.
- Live Bluetooth heart rate uses a simulated band.

Switch at any time in **Settings → Data mode**. Demo and live data are stored apart and never mix. **Settings → Delete all data** wipes both, and in demo mode the sample data is then generated again.

### Setup: the dot-matrix font

The tile numerals use **Subway Ticker Grid** by K-Type. Its licence doesn't allow redistribution, so `assets/fonts/SubwayTickerGrid/*.ttf` is **gitignored** and a fresh clone doesn't have it. Before building, download it from k-type.com and place it at:

```
assets/fonts/SubwayTickerGrid/SubwayTickerGrid.ttf
```

K-Type's free licence covers personal use only. **Publishing the APK or the repository needs their commercial (Enterprise) licence**, or a swap to an OFL dot-matrix face. **Doto** (OFL) is that licence-free candidate: it is kept in the repo at `assets/fonts/Doto/` with its `OFL.txt`, but it is not declared in `pubspec.yaml`, so it is not bundled.

### Setup: toolchain and signing

See [`tool/setup_toolchain.md`](tool/setup_toolchain.md) for the SDK locations and the release-signing variables.

**Gradle temp directory (this machine).** The user temp path has a space, which breaks the Gradle daemons' loopback socket, and C: is nearly full. The fix can't live in `android/gradle.properties`: a `D:/dev/tmp` path there breaks builds on any machine without it, and daemon JVM arguments can't be made conditional in `settings.gradle.kts`. Put it in the local Gradle file instead. Create `D:\dev\tmp`, then add these lines to `%GRADLE_USER_HOME%\gradle.properties` (`D:\dev\gradle\gradle.properties`):

```
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError -Djdk.net.unixdomain.tmpdir=D:/dev/tmp -Djava.io.tmpdir=D:/dev/tmp
kotlin.daemon.jvmargs=-Djdk.net.unixdomain.tmpdir=D:/dev/tmp -Djava.io.tmpdir=D:/dev/tmp
```

The `tool/env.ps1` banner says "no Gradle tmpdir set" until the file has them.

### Optional: Enhanced mode and the coach

Enhanced mode (Google Health API) needs an OAuth client id:

```powershell
flutter run --dart-define=GOOGLE_OAUTH_CLIENT_ID=<your-android-oauth-client-id>
```

Without it, Enhanced mode shows "Not configured" and everything else works.

The Android redirect scheme derives from this same client ID. If your registered redirect differs, pass `--dart-define=GOOGLE_OAUTH_REDIRECT=<registered-uri>` too. Device OAuth verification remains required.

The coach works on-device with no key. For Claude or Gemini, paste your own API key in **Settings → Coach**; it is kept in Android's encrypted storage. The opt-in live eval (`tool/eval_live.dart`) costs money; see [`docs/EVALS.md`](docs/EVALS.md).

## Credits
- Scoring formulas ported from [Luraxx/pulse](https://github.com/Luraxx/pulse) (Apache-2.0), see `third_party/pulse/`.
- Chart painters, design tokens, the BLE heart-rate parser and the Manrope font adapted from [OpenStrap/edge](https://github.com/OpenStrap/edge) (MIT; fonts OFL), see `third_party/edge/`.
- UI font: DM Sans (OFL). Tile corner smoothing ported from figma-squircle (MIT).
- Methods: Karvonen HRR zones, Banister TRIMP, Plews lnRMSSD smallest worthwhile change, Mann-Kendall trend test, Holm correction.
