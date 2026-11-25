<#
.SYNOPSIS
    Builds the TapDancer Android APK and Windows desktop app and copies the
    artifacts into the release/ folder, named with the pubspec version.

.DESCRIPTION
    Run from anywhere; paths are resolved relative to this script.

    Outputs (for version X.Y.Z):
      release/tapdancer-vX.Y.Z-android.apk
      release/tapdancer-vX.Y.Z-windows.zip   (zipped portable build folder)

.PARAMETER Target
    Which platform(s) to build: All (default), Android, or Windows.

.PARAMETER Clean
    Run `flutter clean` before building.

.EXAMPLE
    pwsh scripts/build_release.ps1
    pwsh scripts/build_release.ps1 -Target Android
    pwsh scripts/build_release.ps1 -Clean
#>
[CmdletBinding()]
param(
    [ValidateSet('All', 'Android', 'Windows')]
    [string]$Target = 'All',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

# Project root is the parent of this script's folder.
$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $projectRoot 'release'

Push-Location $projectRoot
try {
    # ── Read version from pubspec.yaml (strip any "+build" suffix) ────────────
    $versionLine = Get-Content 'pubspec.yaml' | Where-Object { $_ -match '^\s*version:\s*(.+)$' } | Select-Object -First 1
    if (-not $versionLine) { throw 'Could not find version: in pubspec.yaml' }
    $version = ($versionLine -replace '^\s*version:\s*', '').Trim().Split('+')[0]
    Write-Host "Building TapDancer v$version (target: $Target)" -ForegroundColor Cyan

    New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

    if ($Clean) {
        Write-Host 'Running flutter clean...' -ForegroundColor Yellow
        flutter clean
    }

    flutter pub get

    # Refresh the bundled firmware DFU package from ../firmware/release.
    & (Join-Path $PSScriptRoot 'sync_firmware.ps1')

    # ── Android ───────────────────────────────────────────────────────────────
    if ($Target -in @('All', 'Android')) {
        Write-Host 'Building Android APK...' -ForegroundColor Cyan
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }

        $apk = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk'
        if (-not (Test-Path $apk)) { throw "APK not found at $apk" }
        $apkDest = Join-Path $releaseDir "tapdancer-v$version-android.apk"
        Copy-Item $apk $apkDest -Force
        Write-Host "  -> $apkDest" -ForegroundColor Green
    }

    # ── Windows ─────────────────────────────────────────────────────────────────
    if ($Target -in @('All', 'Windows')) {
        Write-Host 'Building Windows app...' -ForegroundColor Cyan
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }

        # Flutter 3.x emits to build/windows/x64/runner/Release; older to build/windows/runner/Release.
        $candidates = @(
            (Join-Path $projectRoot 'build/windows/x64/runner/Release'),
            (Join-Path $projectRoot 'build/windows/runner/Release')
        )
        $winDir = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $winDir) { throw 'Windows build output folder not found.' }

        # The .exe needs its sibling DLLs and data/ folder, so zip the whole thing.
        $zipDest = Join-Path $releaseDir "tapdancer-v$version-windows.zip"
        if (Test-Path $zipDest) { Remove-Item $zipDest -Force }
        Compress-Archive -Path (Join-Path $winDir '*') -DestinationPath $zipDest
        Write-Host "  -> $zipDest" -ForegroundColor Green
    }

    Write-Host "`nDone. Artifacts in $releaseDir" -ForegroundColor Cyan
    Get-ChildItem $releaseDir | Format-Table Name, @{Name = 'Size'; Expression = { '{0:N1} MB' -f ($_.Length / 1MB) } }
}
finally {
    Pop-Location
}
