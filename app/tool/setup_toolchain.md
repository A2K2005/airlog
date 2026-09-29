# Toolchain setup

## Current launch setup (2026-09-30)

Launch hardening uses Flutter **3.47.5**, temporarily installed at `C:\Users\Armaan\AppData\Local\Temp\airlog-flutter-3.47.5`. That temporary path is not a permanent dependency. Set `FLUTTER_ROOT`, `JAVA_HOME` (JDK 17) and `ANDROID_HOME` to your own installed locations, then dot-source `tool/env.ps1` or source `tool/env.sh`. These scripts preserve configured SDK/cache locations and do not install SDKs or require D:.

Run `flutter doctor -v`, `flutter pub get`, `flutter analyze`, `flutter test`, then `flutter build apk --debug`. On Windows, serialize tests/builds in this checkout to avoid native-test DLL locks. Install the packages requested by the current Gradle build; the historical table below is not evidence that they exist on your machine. Machine-specific daemon/temp-path overrides belong in local configuration.

Release tasks require **all four** environment variables: `AIRLOG_KEYSTORE` (prefer an absolute keystore path), `AIRLOG_KEYSTORE_PASSWORD`, `AIRLOG_KEY_ALIAS`, and `AIRLOG_KEY_PASSWORD`. Provision them securely; do not commit keys/passwords or expose them in transcripts. Release signing does not fall back to the debug key. With credentials configured, build the Play artifact using `flutter build appbundle --release`.

Optional Google Health: `--dart-define=GOOGLE_OAUTH_CLIENT_ID=<configured-client-id>` supplies both Dart and Android manifest redirect configuration. `--dart-define=GOOGLE_OAUTH_REDIRECT=<registered-uri>` optionally overrides both together. Verify the registered package, signing certificate, redirect, cancellation and token refresh on a device; these setup notes do not claim OAuth success.

Fonts are bundled under OFL, including Doto. No proprietary-font installation is required. Golden changes need visual review; old Figma fidelity measurements are historical.

## Historical setup record (not current instructions)

The remainder records an earlier machine setup. Its installation, successful-build and emulator claims have not been revalidated for this checkout. In particular, current env scripts and Gradle settings no longer hard-code the D: paths below.

Installed on 2026-09-28 into `D:\dev` (nothing on C: except the Flutter config file):

| Component | Version | Source |
|---|---|---|
| Flutter SDK | 3.47.5 stable (Dart 3.13.4) | storage.googleapis.com/flutter_infra_release (Windows zip) |
| JDK | Temurin 17.0.20.1 | api.adoptium.net |
| Android cmdline-tools | 16111833 | dl.google.com/android/repository |
| platform-tools, platforms/android-36, build-tools/36.1.0, emulator | latest | `android sdk install …` (sdkmanager now forwards to the `android` CLI; package paths use `/`) |
| System image | android-35 / google_apis / x86_64 (Health Connect built in) | same |
| AVD | `airlog_api35` (Pixel 7) | `avdmanager create avd` |

Flutter was pointed at them with `flutter config --jdk-dir=D:/dev/jdk17 --android-sdk=D:/dev/android-sdk`.
Caches: `PUB_CACHE`, `GRADLE_USER_HOME`, `ANDROID_USER_HOME`, `ANDROID_AVD_HOME` all under `D:\dev` (see `env.ps1` / `env.sh`).
Emulator acceleration: WHPX (Windows Hypervisor Platform) is installed and usable.

## Android build requirements (added after the first release build)

Install these with `sdkmanager` (package paths use `;` on the classic tool, `/` on the new `android` CLI):

```
sdkmanager "platforms;android-37.0" "build-tools;36.0.0" "ndk;28.2.13676358" "cmake;3.22.1"
```

| Package | Why |
|---|---|
| `platforms;android-37.0` | `compileSdk = 37` in `android/app/build.gradle.kts`. The AAR metadata of `permission_handler_android` 14.1 requires compile SDK 37. `targetSdk` stays 36 (runtime behaviour) and `minSdk` 26 (the `health` plugin). AGP 9.1 has not been tested against 37 yet, so `android.suppressUnsupportedCompileSdk=37` in `android/gradle.properties` silences the warning. |
| `build-tools;36.0.0` | The build-tools version the Android Gradle Plugin (9.1) resolves by default. Having only 36.1.0 installed is not enough. |
| `ndk;28.2.13676358` | Flutter 3.47's default `flutter.ndkVersion` (`FlutterExtension.kt`). `path_provider_android` 2.3 depends on `jni`, which compiles native code (`externalNativeBuild`). Without this exact NDK, Gradle tries to download it mid-build. |
| `cmake;3.22.1` | `jni`'s `externalNativeBuild { cmake { … } }` needs a CMake from the SDK. |

These are build-time only; the emulator still runs the android-35 / google_apis / x86_64 image above.

### `android/gradle.properties` workarounds (Windows, project on C:, caches on D:)

- **`-Djdk.net.unixdomain.tmpdir=D:/dev/tmp -Djava.io.tmpdir=D:/dev/tmp`**
  - Set on both `org.gradle.jvmargs` and `kotlin.daemon.jvmargs`.
  - **Why:** on Windows, Java NIO creates AF_UNIX loopback sockets in a temp directory. By default that is the user's temp path (`C:\Users\Armaan khan\AppData\Local\Temp`), and the space in it breaks the socket. The Gradle and Kotlin daemons then die with "Unable to establish loopback connection".
  - **Fix:** point both properties at a short path with no spaces. `D:/dev/tmp` must exist; create it once with `mkdir D:\dev\tmp`.
- **`kotlin.incremental=false`**
  - **Why:** the project lives on `C:` and the pub cache, which holds the plugins' Kotlin sources, lives on `D:`. Kotlin incremental compilation relativises source paths against the project root and fails with "different roots" when a source is on another drive, so plugin modules fail to compile.
  - **Cost:** every build recompiles the Kotlin modules in full (seconds for this project); outputs are identical.

### Verify

```
. /d/dev/env.sh            # Git Bash; env.ps1 for PowerShell
flutter doctor -v
flutter build apk --release
```

Optional startup timing marks (logcat `airlog.timing …`, milliseconds since `main()`):

```
flutter build apk --release --dart-define=AIRLOG_TIMING=true
```

## Known quirk: build APKs from PowerShell
If you run `flutter build apk` from Git Bash after a host session restart, it can fail with a Gradle daemon "network_connection" error. The same command from PowerShell, after `. .\tool\env.ps1`, succeeds. `flutter test` and `flutter analyze` work from either shell.
