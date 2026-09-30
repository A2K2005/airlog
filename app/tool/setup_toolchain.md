# Toolchain setup

## Environment scripts

Dot-source `tool/env.ps1` (PowerShell) or source `tool/env.sh` (Git Bash) in every new shell. Both scripts:
- **respect variables that are already set** (another machine sets its own `FLUTTER_ROOT`, `JAVA_HOME`, `ANDROID_HOME` and caches first);
- **default an unset variable to `D:\dev`** when that path exists: `FLUTTER_ROOT=D:\dev\flutter`, `JAVA_HOME=D:\dev\jdk17`, `ANDROID_HOME` and `ANDROID_SDK_ROOT=D:\dev\android-sdk`, `PUB_CACHE=D:\dev\pub-cache`, `GRADLE_USER_HOME=D:\dev\gradle`, `ANDROID_USER_HOME=D:\dev\android-home`, `ANDROID_AVD_HOME=D:\dev\avd`. C: is low on space, so caches never default to C:. Without `D:\dev`, `ANDROID_HOME` falls back to Android Studio's `%LOCALAPPDATA%\Android\Sdk`;
- put the Flutter, JDK and Android SDK tools on `PATH`, install nothing, and print one banner line.

Then run `flutter doctor -v`, `flutter pub get`, `flutter analyze` and `flutter test`. On Windows, run one test or build process at a time in this checkout (native-test DLL locks; the laptop also lags under parallel runs).

### Gradle temp directory (needed on this machine)

On Windows, Java NIO creates AF_UNIX loopback sockets in the user temp directory. Here that is `C:\Users\Armaan khan\AppData\Local\Temp`: the space breaks the socket ("Unable to establish loopback connection"), and C: has little free space. PR #1 took the machine paths out of `android/gradle.properties`, so the setting now lives in the local Gradle configuration, `%GRADLE_USER_HOME%\gradle.properties` (`D:\dev\gradle\gradle.properties` with the defaults above). Create `D:\dev\tmp` once, then put these two lines in that file:

```
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError -Djdk.net.unixdomain.tmpdir=D:/dev/tmp -Djava.io.tmpdir=D:/dev/tmp
kotlin.daemon.jvmargs=-Djdk.net.unixdomain.tmpdir=D:/dev/tmp -Djava.io.tmpdir=D:/dev/tmp
```

The user-home file overrides `org.gradle.jvmargs` in the project file, so the heap settings belong in it too. While the file is missing, the `tool/env.ps1` banner ends with "no Gradle tmpdir set". Before PR #1 the same two properties sat in `android/gradle.properties` (with `-Xmx8G -XX:MaxMetaspaceSize=4G`), and release builds passed. The file-based setup is untested: no build was run after the merge.

### Release signing

Release tasks require **all four** environment variables: `AIRLOG_KEYSTORE` (prefer an absolute keystore path), `AIRLOG_KEYSTORE_PASSWORD`, `AIRLOG_KEY_ALIAS` and `AIRLOG_KEY_PASSWORD`. Provision them securely; never commit keys or passwords or expose them in transcripts. A missing or partial set fails the build. With them set, build the Play artifact with `flutter build appbundle --release`.

**Local sideload build (explicit opt-in).** Set `AIRLOG_LOCAL_RELEASE=1` with **none** of the four variables set: the release is signed with the debug key, and Gradle warns "local sideload build, not for the store". A full set of the four always wins; a partial set still fails. Never upload such a build.

### Google Health (optional)

`--dart-define=GOOGLE_OAUTH_CLIENT_ID=<configured-client-id>` supplies both the Dart and the Android manifest redirect configuration. `--dart-define=GOOGLE_OAUTH_REDIRECT=<registered-uri>` optionally overrides both together. Verify the registered package, signing certificate, redirect, cancellation and token refresh on a device; these notes do not claim OAuth works.

### Fonts

The dot-matrix numerals use **Subway Ticker Grid** (K-Type, personal-use licence). It is gitignored: place `assets/fonts/SubwayTickerGrid/SubwayTickerGrid.ttf` yourself (see the README). Doto (OFL) is kept in `assets/fonts/Doto/` as the licence-free candidate for publishing, but it is not declared in `pubspec.yaml`, so it is not bundled.

## Setup record (D:\dev, 2026-09-28)

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

### `android/gradle.properties` workaround (Windows, project on C:, caches on D:)

- **`kotlin.incremental=false`**
  - **Why:** the project lives on `C:` and the pub cache, which holds the plugins' Kotlin sources, lives on `D:`. Kotlin incremental compilation relativises source paths against the project root and fails with "different roots" when a source is on another drive, so plugin modules fail to compile.
  - **Cost:** every build recompiles the Kotlin modules in full (seconds for this project); outputs are identical.
- The temp-directory properties moved to the user-home Gradle file: see "Gradle temp directory" above.

### Verify

```
. tool/env.sh              # Git Bash; tool/env.ps1 in PowerShell
flutter doctor -v
flutter build apk --release   # needs the signing variables, or AIRLOG_LOCAL_RELEASE=1 (above)
```

Optional startup timing marks (logcat `airlog.timing …`, milliseconds since `main()`):

```
flutter build apk --release --dart-define=AIRLOG_TIMING=true
```

## Known quirk: build APKs from PowerShell
If you run `flutter build apk` from Git Bash after a host session restart, it can fail with a Gradle daemon "network_connection" error. The same command from PowerShell, after `. .\tool\env.ps1`, succeeds. `flutter test` and `flutter analyze` work from either shell.
