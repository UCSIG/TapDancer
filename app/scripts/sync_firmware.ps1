<#
.SYNOPSIS
    Stages the latest built firmware so the app can bundle it for OTA updates.

.DESCRIPTION
    Build + two-step copy:
      0. Build the firmware with PlatformIO (skip with -SkipBuild).
      1. PlatformIO build output  ->  firmware project's release folder
         <repo>/firmware/.pio/build/<env>/{firmware_tapdancer.zip,.hex,.uf2,version.json}
         -> <repo>/firmware/release/
      2. Release folder           ->  app assets (bundled & flashed via nordic_dfu)
         <repo>/firmware/release/{firmware_tapdancer.zip,version.json}
         -> app/assets/firmware/

    Run this whenever the firmware is rebuilt, before building the app.
    build_release.ps1 calls this automatically.
#>
[CmdletBinding()]
param(
    # PlatformIO build environment (subfolder under firmware/.pio/build).
    [string]$BuildEnv = 'xiaoble_adafruit',

    # Reuse the existing build output instead of running PlatformIO first.
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot                       # ...\app
$firmwareDir = Join-Path (Split-Path -Parent $projectRoot) 'firmware'
$buildDir = Join-Path $firmwareDir ".pio/build/$BuildEnv"
$releaseDir = Join-Path $firmwareDir 'release'
$assetsDir = Join-Path $projectRoot 'assets/firmware'

# ── Step 0: build the firmware via PlatformIO ───────────────────────────────────
if (-not $SkipBuild) {
    $pio = (Get-Command pio -ErrorAction SilentlyContinue).Source
    if (-not $pio) {
        $penv = Join-Path $env:USERPROFILE '.platformio/penv/Scripts/pio.exe'
        if (Test-Path $penv) { $pio = $penv }
    }
    if (-not $pio) {
        throw "PlatformIO CLI (pio) not found on PATH or in ~/.platformio. Install it, or pass -SkipBuild to use the existing build output."
    }

    Write-Host "Building firmware ($BuildEnv)..." -ForegroundColor Cyan
    & $pio run -d $firmwareDir -e $BuildEnv
    if ($LASTEXITCODE -ne 0) {
        throw "PlatformIO build failed (exit $LASTEXITCODE)."
    }
}

# ── Step 1: PlatformIO build output -> firmware/release ─────────────────────────
$buildZip = Join-Path $buildDir 'firmware_tapdancer.zip'
if (-not (Test-Path $buildZip)) {
    throw "Firmware build output not found at $buildZip. Build the firmware first (pio run -e $BuildEnv)."
}

New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

# Build artifacts promoted into the release folder (the .elf stays in the build
# folder — it isn't shipped).
$releaseArtifacts = @(
    'firmware_tapdancer.zip',
    'firmware_tapdancer.hex',
    'firmware_tapdancer.uf2',
    'version.json'
)
foreach ($name in $releaseArtifacts) {
    $from = Join-Path $buildDir $name
    if (Test-Path $from) {
        Copy-Item $from (Join-Path $releaseDir $name) -Force
        Write-Host "  release <- $name" -ForegroundColor DarkGray
    }
    elseif ($name -eq 'version.json') {
        Write-Warning "No version.json in $buildDir — rebuild the firmware to generate it (see tools/generate_build_info.py)."
    }
}
Write-Host "Promoted build output -> $releaseDir" -ForegroundColor Green

# ── Step 2: firmware/release -> app assets ──────────────────────────────────────
$src = Join-Path $releaseDir 'firmware_tapdancer.zip'
$versionSrc = Join-Path $releaseDir 'version.json'
$dest = Join-Path $assetsDir 'firmware_tapdancer.zip'

if (-not (Test-Path $src)) {
    throw "Firmware package not found at $src. Build the firmware first (it should produce firmware/release/firmware_tapdancer.zip)."
}

New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null
Copy-Item $src $dest -Force

$size = '{0:N0} KB' -f ((Get-Item $dest).Length / 1KB)
Write-Host "Synced firmware -> $dest ($size)" -ForegroundColor Green

# The version manifest lets the app compare bundled vs on-device firmware.
if (Test-Path $versionSrc) {
    Copy-Item $versionSrc (Join-Path $assetsDir 'version.json') -Force
    Write-Host "Synced version.json ($(Get-Content $versionSrc -Raw | ConvertFrom-Json | Select-Object -ExpandProperty version))" -ForegroundColor Green
}
else {
    Write-Warning "No version.json in $releaseDir — the app won't be able to show the bundled firmware version. Rebuild the firmware to generate it."
}
