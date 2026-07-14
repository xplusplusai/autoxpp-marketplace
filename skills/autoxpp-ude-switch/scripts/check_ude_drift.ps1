# check_ude_drift.ps1 - lightweight, machine-readable UDE drift detector.
#
# Compares the UDE that Visual Studio 2022 is CURRENTLY connected to against the
# `activeEnv` recorded in ude-configs.json. Emits ONE parseable verdict line so
# session-start / lifecycle-load can decide whether to warn or auto-fix.
#
# How "current VS UDE" is detected WITHOUT UI automation:
#   VS touches %LOCALAPPDATA%\Microsoft\Dynamics365\XPPConfig\{name}___{version}.json
#   on every (re)connect. The most-recently-modified file is the one VS last loaded,
#   and the filename encodes the UDE name. (Same mechanism as show_current_ude.ps1.)
#
# Output contract (first token is the verdict; key=value pairs follow):
#   IN_SYNC       env=<name>
#   DRIFT         config=<activeEnv> vs=<vsName> vsVersion=<ver> vsConfigFile=<file>
#   VS_UNKNOWN    vs=<vsName> config=<activeEnv>          # VS on a UDE not in ude-configs.json
#   NO_VS_CONFIG  detail=<why>                            # XPPConfig empty / never configured
#   NO_CONFIG     detail=<why>                            # ude-configs.json missing/invalid
#
# Exit code is always 0 - the verdict is on stdout, not the exit code, so callers
# parse the line rather than branching on $LASTEXITCODE.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config_helpers.ps1"

# --- 1. Load config (tolerate missing/invalid) ---------------------------------
try {
    $cfg = Load-UdeConfigs
} catch {
    Write-Host "NO_CONFIG  detail=$($_.Exception.Message)"
    exit 0
}

$activeEnv = Get-ActiveUdeName $cfg
if (-not $activeEnv) {
    Write-Host "NO_CONFIG  detail=no-udeConfigs-entries"
    exit 0
}

# --- 2. Detect the UDE VS last loaded (newest XPPConfig JSON) -------------------
$xppDir = Get-XppConfigDir
if (-not (Test-Path $xppDir)) {
    Write-Host "NO_VS_CONFIG  detail=no-XPPConfig-folder"
    exit 0
}

$latest = Get-ChildItem -Path $xppDir -Filter "*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $latest) {
    Write-Host "NO_VS_CONFIG  detail=no-XPPConfig-json"
    exit 0
}

$m = [regex]::Match($latest.BaseName, '^(?<name>.+)___(?<ver>[\d\.]+)$')
if (-not $m.Success) {
    Write-Host "NO_VS_CONFIG  detail=unparseable-filename:$($latest.Name)"
    exit 0
}

$vsName    = $m.Groups['name'].Value
$vsVersion = $m.Groups['ver'].Value

# --- 3. Compare ----------------------------------------------------------------
if ($vsName -ieq $activeEnv) {
    Write-Host "IN_SYNC  env=$activeEnv"
    exit 0
}

# Names differ. Is the VS-loaded UDE even known to the config?
$vsKnown = $cfg.udeConfigs | Where-Object { $_.name -eq $vsName }
if (-not $vsKnown) {
    Write-Host "VS_UNKNOWN  vs=$vsName config=$activeEnv"
    exit 0
}

Write-Host "DRIFT  config=$activeEnv vs=$vsName vsVersion=$vsVersion vsConfigFile=$($latest.Name)"
exit 0
