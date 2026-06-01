# diff_xppconfig.ps1 - identify the XPP config JSON that VS created/updated during a switch.
#
# Name-agnostic: instead of matching by filename, it diffs the XPPConfig folder against the
# Phase A baseline snapshot and returns the file that is new or has a newer mtime - that is the
# one VS just touched, regardless of what VS named it (org ID, display name, etc.).
#
# Usage: diff_xppconfig.ps1 -BaselineFile <path> [-LastKnownVersion <ver>]
#
# Emits: XPP_JSON: <full path>   (single line, on success)
#
# Selection order:
#   1. File that is new OR has a newer LastWriteTime than the baseline (newest wins).
#   2. Fallback (assets cached / VS reused config - nothing changed): newest file whose
#      name contains -LastKnownVersion.
#   3. Fallback: newest *.json in the folder.
#
# Exit codes:
#   0 - found, path printed on a line starting with "XPP_JSON: "
#   1 - no XPP config JSON found at all

param(
    [Parameter(Mandatory=$true)][string]$BaselineFile,
    [string]$LastKnownVersion = ""
)

. "$PSScriptRoot\config_helpers.ps1"

$xppDir = Get-XppConfigDir
if (-not (Test-Path $xppDir)) {
    Write-Host "ERROR: XPPConfig folder does not exist: $xppDir"
    exit 1
}

# Parse baseline snapshot (name|ISO-mtime lines). Missing/empty => every file looks new.
$baseline = @{}
if (Test-Path $BaselineFile) {
    Get-Content -Encoding UTF8 $BaselineFile | ForEach-Object {
        $parts = $_ -split '\|', 2
        if ($parts.Count -eq 2) { $baseline[$parts[0]] = [datetime]::Parse($parts[1]) }
    }
}

$all = Get-ChildItem -Path $xppDir -Filter "*.json" -ErrorAction SilentlyContinue
if (-not $all -or @($all).Count -eq 0) {
    Write-Host "ERROR: No XPP config JSON files in $xppDir"
    exit 1
}

# 1) New or newer-than-baseline.
$changed = @()
foreach ($f in $all) {
    $base = if ($baseline.ContainsKey($f.Name)) { $baseline[$f.Name] } else { $null }
    if (-not $base -or $f.LastWriteTime -gt $base) { $changed += $f }
}

$picked = $null
if (@($changed).Count -gt 0) {
    $picked = $changed | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "  Detected changed config: $($picked.Name)"
} elseif ($LastKnownVersion) {
    # 2) Nothing changed (cached) - fall back to a file matching the known version.
    $vmatch = $all | Where-Object { $_.Name -like "*$LastKnownVersion*" } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($vmatch) {
        $picked = $vmatch
        Write-Host "  No change detected; fell back to version match ($LastKnownVersion): $($picked.Name)"
    }
}
if (-not $picked) {
    # 3) Last resort - newest config in the folder.
    $picked = $all | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "  No change/version match; fell back to newest config: $($picked.Name)"
}

# Emit the result on the SUCCESS/output stream (Write-Output) so the parent's
# $diffOut = & diff_xppconfig.ps1 captures it. Write-Host would bypass capture.
Write-Output "XPP_JSON: $($picked.FullName)"
exit 0
