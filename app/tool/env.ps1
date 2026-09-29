# Airlog shell setup for PowerShell. Dot-source it: . .\tool\env.ps1
#
# Respects SDK and cache locations that are already set. Where one is unset
# and its D:\dev default exists, it defaults there: C: is low on space, so
# caches never default to C:. Installs nothing. See tool/setup_toolchain.md.
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
if (-not $env:ANDROID_HOME -and $env:ANDROID_SDK_ROOT) {
    $env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
}
$airlogDefaults = [ordered]@{
    FLUTTER_ROOT      = 'D:\dev\flutter'
    JAVA_HOME         = 'D:\dev\jdk17'
    ANDROID_HOME      = 'D:\dev\android-sdk'
    PUB_CACHE         = 'D:\dev\pub-cache'
    GRADLE_USER_HOME  = 'D:\dev\gradle'
    ANDROID_USER_HOME = 'D:\dev\android-home'
    ANDROID_AVD_HOME  = 'D:\dev\avd'
}
foreach ($airlogName in $airlogDefaults.Keys) {
    $airlogPath = $airlogDefaults[$airlogName]
    if (-not [Environment]::GetEnvironmentVariable($airlogName, 'Process') -and
        (Test-Path -LiteralPath $airlogPath)) {
        Set-Item -Path "Env:$airlogName" -Value $airlogPath
    }
}
# Another machine without D:\dev: the Android Studio SDK location.
if (-not $env:ANDROID_HOME -and $env:LOCALAPPDATA) {
    $airlogStudioSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (Test-Path -LiteralPath $airlogStudioSdk) { $env:ANDROID_HOME = $airlogStudioSdk }
}
if (-not $env:ANDROID_SDK_ROOT -and $env:ANDROID_HOME) {
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
}
$airlogBins = @()
if ($env:FLUTTER_ROOT) { $airlogBins += Join-Path $env:FLUTTER_ROOT 'bin' }
if ($env:JAVA_HOME) { $airlogBins += Join-Path $env:JAVA_HOME 'bin' }
if ($env:ANDROID_HOME) {
    $airlogBins += Join-Path $env:ANDROID_HOME 'platform-tools'
    $airlogBins += Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin'
    $airlogBins += Join-Path $env:ANDROID_HOME 'emulator'
}
$airlogBins = @($airlogBins | Where-Object { Test-Path -LiteralPath $_ })
if ($airlogBins.Count -gt 0) { $env:Path = ($airlogBins -join ';') + ';' + $env:Path }
# The Gradle daemons' temp dir must not be the user temp path (it has a space
# on this machine): see tool/setup_toolchain.md "Gradle temp directory".
$airlogGradleNote = ''
if ($env:GRADLE_USER_HOME) {
    $airlogGradleProps = Join-Path $env:GRADLE_USER_HOME 'gradle.properties'
    if (-not ((Test-Path -LiteralPath $airlogGradleProps) -and
            (Select-String -LiteralPath $airlogGradleProps -Pattern 'unixdomain.tmpdir' -Quiet))) {
        $airlogGradleNote = ' | no Gradle tmpdir set: see tool/setup_toolchain.md'
    }
}
Write-Host "Airlog env: Flutter $env:FLUTTER_ROOT | JDK $env:JAVA_HOME | SDK $env:ANDROID_HOME | caches $env:PUB_CACHE, $env:GRADLE_USER_HOME$airlogGradleNote"
