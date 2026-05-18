# show_current_ude.ps1 - report the currently "active" UDE
#
# VS 2022 does not expose a simple "current" flag. We infer the active UDE by:
#   1. The most-recently-modified XPPConfig\*.json file (VS touches it on (re)connect)
#   2. Cross-check against ude-configs.json activeEnv field
#   3. If they disagree, the filesystem wins (VS is the source of truth for "what it last loaded")

. "$PSScriptRoot\config_helpers.ps1"

$xppDir = Get-XppConfigDir
if (-not (Test-Path $xppDir)) {
    Write-Host "No XPPConfig folder at $xppDir — VS UDE has never been configured on this machine."
    exit 0
}

$latest = Get-ChildItem -Path $xppDir -Filter "*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $latest) {
    Write-Host "No XPP config JSON files found in $xppDir."
    exit 0
}

# Filename pattern: {name}___{version}.json
$m = [regex]::Match($latest.BaseName, '^(?<name>.+)___(?<ver>[\d\.]+)$')
if (-not $m.Success) {
    Write-Host "Unable to parse UDE name/version from filename: $($latest.Name)"
    Write-Host "Most recent XPP config: $($latest.FullName)"
    Write-Host "Last modified: $($latest.LastWriteTime)"
    exit 0
}

$udeName = $m.Groups['name'].Value
$version = $m.Groups['ver'].Value

# Pull more detail from the JSON
$j = Get-Content -Raw -Encoding UTF8 $latest.FullName | ConvertFrom-Json

$cfg = Load-UdeConfigs
$known = $cfg.udeConfigs | Where-Object { $_.name -eq $udeName }

Write-Host ""
Write-Host "Current (most recently loaded) UDE:"
Write-Host ""
Write-Host "  Name              : $udeName"
Write-Host "  Platform version  : $version"
Write-Host "  XPP config file   : $($latest.Name)"
Write-Host "  XPP last modified : $($latest.LastWriteTime)"
Write-Host "  ModelStoreFolder  : $($j.ModelStoreFolder)"
Write-Host "  DebugSourceFolder : $($j.DebugSourceFolder)"
Write-Host "  CrossRef DB       : $($j.CrossReferencesDatabaseName)"

$configActiveEnv = Get-ActiveUdeName $cfg

if ($known) {
    Write-Host ""
    Write-Host "  Known in ude-configs.json: YES"
    Write-Host "  DataverseUrl : $($known.dataverseUrl)"
    if ($known.customMetadataFolder) {
        Write-Host "  Expected metadata folder: $($known.customMetadataFolder)"
        if ($known.customMetadataFolder -ne $j.ModelStoreFolder) {
            Write-Host ""
            Write-Host "  WARNING: XPP config ModelStoreFolder does not match ude-configs.json." -ForegroundColor Yellow
            Write-Host "           Run '/autoxpp-ude-switch $udeName' to retarget." -ForegroundColor Yellow
        }
    }
    if ($configActiveEnv -and $configActiveEnv -ne $udeName) {
        Write-Host ""
        Write-Host "  WARNING: ude-configs.json activeEnv is '$configActiveEnv' but VS last loaded '$udeName'." -ForegroundColor Yellow
        Write-Host "           Run '/autoxpp-ude-switch $udeName' to sync the config." -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "  Known in ude-configs.json: NO (consider '/autoxpp-ude-switch --add' to register)"
}
