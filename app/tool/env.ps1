# Optional shell setup. Respect existing SDK locations and caches.
# Set FLUTTER_ROOT, JAVA_HOME and ANDROID_HOME before dot-sourcing this file.
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
if (-not $env:ANDROID_HOME -and $env:ANDROID_SDK_ROOT) {
    $env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
}
if (-not $env:ANDROID_HOME) {
    $airlogDefaultSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (Test-Path -LiteralPath $airlogDefaultSdk) { $env:ANDROID_HOME = $airlogDefaultSdk }
}
$airlogBins = @()
if ($env:FLUTTER_ROOT) { $airlogBins += Join-Path $env:FLUTTER_ROOT 'bin' }
if ($env:JAVA_HOME) { $airlogBins += Join-Path $env:JAVA_HOME 'bin' }
if ($env:ANDROID_HOME) {
    $airlogBins += Join-Path $env:ANDROID_HOME 'platform-tools'
    $airlogBins += Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin'
    $airlogBins += Join-Path $env:ANDROID_HOME 'emulator'
}
$env:Path = (($airlogBins | Where-Object { Test-Path -LiteralPath $_ }) -join ';') + ';' + $env:Path
Write-Host 'Airlog: using configured SDKs. Run flutter doctor -v to verify.'
