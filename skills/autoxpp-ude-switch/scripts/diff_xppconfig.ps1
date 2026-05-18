# diff_xppconfig.ps1 - identify the new/updated XPP config after a switch
#
# Usage: diff_xppconfig.ps1 -BaselineFile <path> -ExpectedName <ude-name>
# Emits: full path of the XPP config JSON that corresponds to this switch.
#        Picks the JSON that:
#          (a) matches filename pattern "{ExpectedName}___*.json"
#          (b) was created OR modified after the baseline
#          (c) has the most recent LastWriteTime
#
# Exit codes:
#   0 - found, path printed to stdout on a single line starting with "XPP_JSON: "
#   1 - no matching file found

param(
    [Parameter(Mandatory=$true)][string]$BaselineFile,
    [Parameter(Mandatory=$true)][string]$ExpectedName
)

. "$PSScriptRoot\config_helpers.ps1"

$xppDir = Get-XppConfigDir
if (-not (Test-Path $xppDir)) {
    Write-Host "ERROR: XPPConfig folder does not exist: $xppDir"
    exit 1
}

# Parse baseline (optional; if missing/empty, treat all files as candidates)
$baseline = @{}
if (Test-Path $BaselineFile) {
    Get-Content -Encoding UTF8 $BaselineFile | ForEach-Object {
        $parts = $_ -split '\|', 2
        if ($parts.Count -eq 2) { $baseline[$parts[0]] = [datetime]::Parse($parts[1]) }
    }
}

$candidates = Get-ChildItem -Path $xppDir -Filter "$ExpectedName`___*.json" -ErrorAction SilentlyContinue

$changed = @()
foreach ($c in $candidates) {
    $baseTime = if ($baseline.ContainsKey($c.Name)) { $baseline[$c.Name] } else { $null }
    if (-not $baseTime -or $c.LastWriteTime -gt $baseTime) {
        $changed += $c
    }
}

# Fallback: if nothing strictly "newer than baseline", take the newest matching by name.
if ($changed.Count -eq 0 -and $candidates.Count -gt 0) {
    $changed = $candidates
}

if ($changed.Count -eq 0) {
    Write-Host "ERROR: No XPP config JSON found matching '$ExpectedName`___*.json' in $xppDir"
    exit 1
}

$picked = $changed | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "XPP_JSON: $($picked.FullName)"
exit 0
