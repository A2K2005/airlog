# Toolchain setup (reproducible)

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
