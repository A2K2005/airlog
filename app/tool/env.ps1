# Dot-source in PowerShell before flutter commands:  . .\tool\env.ps1
# Toolchain lives on D:\dev (C: is short on space; also avoids the space in
# the user-profile path that trips some Gradle/pub tooling).
$env:JAVA_HOME         = 'D:\dev\jdk17'
$env:ANDROID_HOME      = 'D:\dev\android-sdk'
$env:ANDROID_SDK_ROOT  = 'D:\dev\android-sdk'
$env:PUB_CACHE         = 'D:\dev\pub-cache'
$env:GRADLE_USER_HOME  = 'D:\dev\gradle'
$env:ANDROID_USER_HOME = 'D:\dev\android-home'
$env:ANDROID_AVD_HOME  = 'D:\dev\avd'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:Path = 'D:\dev\flutter\bin;D:\dev\jdk17\bin;D:\dev\android-sdk\cmdline-tools\latest\bin;D:\dev\android-sdk\platform-tools;D:\dev\android-sdk\emulator;' + $env:Path
Write-Host 'Airlog toolchain: Flutter 3.47.5, JDK 17, Android SDK 36 (D:\dev)'
