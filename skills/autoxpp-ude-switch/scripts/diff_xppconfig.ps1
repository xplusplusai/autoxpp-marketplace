# diff_xppconfig.ps1 - identify VS-created artifacts after a switch.
#
# Diffs XPPConfig folder (JSON files, subfolders) and RuntimeSymLinks against
# the Phase A baseline snapshot. Returns the config JSON VS touched, plus any
# new RuntimeSymLinks folder and XPPConfig subfolder.
#
# Usage: diff_xppconfig.ps1 -BaselineFile <path> [-LastKnownVersion <ver>]
#
# Emits (Write-Output, captured by caller):
#   XPP_JSON: <full path>             -- the VS-created/updated config file
#   VS_ORG_NAME: <orgName>            -- Dataverse org ID parsed from filename
#   XREF_DB_NAME: <dbName>            -- CrossReferencesDatabaseName from the JSON
#   NEW_RSL_FOLDER: <folderName>      -- new RuntimeSymLinks folder (if any)
#   NEW_XPP_SUBFOLDER: <folderName>   -- new XPPConfig subfolder (if any)
#
# Exit codes:
#   0 - found, results printed
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

# Parse baseline snapshot. New format has prefixes (JSON:, RSL:, SUB:).
# Old format (no prefix) is treated as JSON: for backward compat.
$baselineJson = @{}
$baselineRsl  = @{}
$baselineSub  = @{}

if (Test-Path $BaselineFile) {
    Get-Content -Encoding UTF8 $BaselineFile | ForEach-Object {
        if ($_ -match '^JSON:(.+)\|(.+)$') {
            $baselineJson[$Matches[1]] = [datetime]::Parse($Matches[2])
        } elseif ($_ -match '^RSL:(.+)\|(.+)$') {
            $baselineRsl[$Matches[1]] = [datetime]::Parse($Matches[2])
        } elseif ($_ -match '^SUB:(.+)\|(.+)$') {
            $baselineSub[$Matches[1]] = [datetime]::Parse($Matches[2])
        } elseif ($_ -match '^(.+)\|(.+)$') {
            # Old format (no prefix) = JSON
            $baselineJson[$Matches[1]] = [datetime]::Parse($Matches[2])
        }
    }
}

# --- 1) Identify changed/new JSON config ---
$all = Get-ChildItem -Path $xppDir -Filter "*.json" -ErrorAction SilentlyContinue
if (-not $all -or @($all).Count -eq 0) {
    Write-Host "ERROR: No XPP config JSON files in $xppDir"
    exit 1
}

$changed = @()
foreach ($f in $all) {
    $base = if ($baselineJson.ContainsKey($f.Name)) { $baselineJson[$f.Name] } else { $null }
    if (-not $base -or $f.LastWriteTime -gt $base) { $changed += $f }
}

$picked = $null
if (@($changed).Count -gt 0) {
    $picked = $changed | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "  Detected changed config: $($picked.Name)"
} elseif ($LastKnownVersion) {
    $vmatch = $all | Where-Object { $_.Name -like "*$LastKnownVersion*" } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($vmatch) {
        $picked = $vmatch
        Write-Host "  No change detected; fell back to version match ($LastKnownVersion): $($picked.Name)"
    }
}
if (-not $picked) {
    $picked = $all | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "  No change/version match; fell back to newest config: $($picked.Name)"
}

Write-Output "XPP_JSON: $($picked.FullName)"

# --- 2) Extract vsOrgName from the VS-generated filename ---
# VS names configs as {orgName}___{version}.json
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($picked.Name)
$orgMatch = [regex]::Match($baseName, '^(.+?)___')
if ($orgMatch.Success) {
    Write-Output "VS_ORG_NAME: $($orgMatch.Groups[1].Value)"
}

# --- 3) Read CrossReferencesDatabaseName from the JSON ---
try {
    $j = Get-Content -Raw -Encoding UTF8 $picked.FullName | ConvertFrom-Json
    if ($j.PSObject.Properties.Name -contains 'CrossReferencesDatabaseName' -and $j.CrossReferencesDatabaseName) {
        Write-Output "XREF_DB_NAME: $($j.CrossReferencesDatabaseName)"
    }
} catch { }

# --- 4) Detect new RuntimeSymLinks folders ---
$rslDir = Get-RuntimeSymLinksDir
if (Test-Path $rslDir) {
    $rslAll = Get-ChildItem -Path $rslDir -Directory -ErrorAction SilentlyContinue
    foreach ($d in $rslAll) {
        if (-not $baselineRsl.ContainsKey($d.Name)) {
            Write-Output "NEW_RSL_FOLDER: $($d.Name)"
            Write-Host "  New RuntimeSymLinks folder: $($d.Name)"
        }
    }
}

# --- 5) Detect new XPPConfig subfolders ---
$subAll = Get-ChildItem -Path $xppDir -Directory -ErrorAction SilentlyContinue
foreach ($d in $subAll) {
    if (-not $baselineSub.ContainsKey($d.Name)) {
        Write-Output "NEW_XPP_SUBFOLDER: $($d.Name)"
        Write-Host "  New XPPConfig subfolder: $($d.Name)"
    }
}

exit 0
