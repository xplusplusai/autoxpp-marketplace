# scan_residuals.md - scan for stale files left by previous FO versions.
#
# Scans three locations under %LOCALAPPDATA%\Microsoft\Dynamics365:
#   1. RuntimeSymLinks — untracked folders with broken junctions or empty
#   2. XPPConfig — subfolders/JSONs for versions no config references
#   3. Version directories (10.0.*) — platform installs no config references
#
# Source of truth: ude-configs.json (tracked fields + lastKnownVersion).
# Default: scan and report. With -Delete: remove stale items (caller-approved).
#
# Output per stale item:
#   RESIDUAL: <type> | <name> | <reason>
# Summary:
#   RESIDUAL_SUMMARY: total=N rsl=N xpp=N ver=N
#   RESIDUAL_SCAN_CLEAN (when nothing found)
#
# Exit code: 0 always (scan failures are non-fatal warnings).

param(
    [switch]$Delete
)

$ErrorActionPreference = 'Continue'

. "$PSScriptRoot\config_helpers.md"

try {
    $cfg = Load-UdeConfigs
} catch {
    Write-Host "RESIDUAL_SCAN_SKIP: $($_.Exception.Message)"
    exit 0
}

$dynamicsRoot = Get-DynamicsRoot
$xppDir       = Get-XppConfigDir
$rslDir       = Get-RuntimeSymLinksDir

if (-not $cfg.udeConfigs -or @($cfg.udeConfigs).Count -eq 0) {
    Write-Host "RESIDUAL_SCAN_SKIP: ude-configs.json has no udeConfigs entries — nothing to compare against."
    exit 0
}

# --- Build lookup tables from all configured UDEs ---
$trackedRslFolders     = @{}   # folder name -> config name
$trackedXppSubfolders  = @{}   # subfolder name -> config name
$trackedXppConfigFiles = @{}   # json filename -> config name
$activeVersions        = @{}   # version string -> $true

foreach ($ude in $cfg.udeConfigs) {
    $name = $ude.name
    $ver = if ($ude.PSObject.Properties.Name -contains 'lastKnownVersion') { $ude.lastKnownVersion } else { "" }

    if ($ver) { $activeVersions[$ver] = $true }

    $rslF = if ($ude.PSObject.Properties.Name -contains 'runtimeSymLinkFolder' -and $ude.runtimeSymLinkFolder) { $ude.runtimeSymLinkFolder } else { "" }
    if ($rslF) { $trackedRslFolders[$rslF] = $name }

    $xppSub = if ($ude.PSObject.Properties.Name -contains 'xppConfigSubfolder' -and $ude.xppConfigSubfolder) { $ude.xppConfigSubfolder } else { "" }
    if ($xppSub) { $trackedXppSubfolders[$xppSub] = $name }

    $xppFile = if ($ude.PSObject.Properties.Name -contains 'xppConfigFile' -and $ude.xppConfigFile) { $ude.xppConfigFile } else { "" }
    if ($xppFile) { $trackedXppConfigFiles[$xppFile] = $name }
}

$findings = @()

# --- 1. RuntimeSymLinks ---
if (Test-Path $rslDir) {
    $rslFolders = @(Get-ChildItem -Path $rslDir -Directory -ErrorAction SilentlyContinue)
    foreach ($folder in $rslFolders) {
        if ($trackedRslFolders.ContainsKey($folder.Name)) { continue }

        $children = @(Get-ChildItem -Path $folder.FullName -Force -ErrorAction SilentlyContinue)
        if ($children.Count -eq 0) {
            $findings += [PSCustomObject]@{ Type = "RSL"; Path = $folder.FullName; Name = $folder.Name; Reason = "empty directory" }
            continue
        }

        $junctionCount = 0
        $brokenCount = 0
        foreach ($child in $children) {
            if ($child.PSIsContainer -and ($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                $junctionCount++
                try {
                    $null = [System.IO.Directory]::EnumerateFileSystemEntries($child.FullName) | Select-Object -First 1
                } catch {
                    $brokenCount++
                }
            }
        }

        if ($brokenCount -gt 0) {
            $findings += [PSCustomObject]@{ Type = "RSL"; Path = $folder.FullName; Name = $folder.Name; Reason = "broken junctions ($brokenCount/$junctionCount targets missing)" }
        } elseif ($junctionCount -eq 0 -and $children.Count -gt 0) {
            $findings += [PSCustomObject]@{ Type = "RSL"; Path = $folder.FullName; Name = $folder.Name; Reason = "untracked, no junctions ($($children.Count) items)" }
        }
        # Folders with valid junctions that aren't tracked are left alone —
        # they may belong to a tool outside ude-configs.
    }
}

# --- 2. XPPConfig subfolders and JSONs ---
if (Test-Path $xppDir) {
    # Subfolders with version pattern: {orgName}___{version}
    $xppSubDirs = @(Get-ChildItem -Path $xppDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '___' })

    foreach ($sub in $xppSubDirs) {
        if ($trackedXppSubfolders.ContainsKey($sub.Name)) { continue }

        $parts = $sub.Name -split '___'
        $folderVer = if ($parts.Count -ge 2) { $parts[-1] } else { "" }

        # Skip subfolders whose version matches an active config — they may be
        # in use by a config that hasn't populated xppConfigSubfolder yet.
        if ($folderVer -and $activeVersions.ContainsKey($folderVer)) { continue }

        $files = @(Get-ChildItem -Path $sub.FullName -File -ErrorAction SilentlyContinue)
        $sizeMB = [math]::Round(($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB, 1)

        $findings += [PSCustomObject]@{ Type = "XPP"; Path = $sub.FullName; Name = $sub.Name; Reason = "old version $folderVer (no config references it) ($($files.Count) files, ${sizeMB}MB)" }

        # Companion JSON at same level
        $companionJson = "$($sub.Name).json"
        $companionPath = Join-Path $xppDir $companionJson
        if ((Test-Path $companionPath) -and -not $trackedXppConfigFiles.ContainsKey($companionJson)) {
            $findings += [PSCustomObject]@{ Type = "XPP_JSON"; Path = $companionPath; Name = $companionJson; Reason = "companion config for stale subfolder" }
        }
    }

    # Standalone JSONs with version pattern, not tracked by any config
    $xppJsons = @(Get-ChildItem -Path $xppDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '___' })
    foreach ($json in $xppJsons) {
        if ($trackedXppConfigFiles.ContainsKey($json.Name)) { continue }
        # Skip if already flagged as companion above
        if ($findings | Where-Object { $_.Path -eq $json.FullName }) { continue }

        $parts = $json.BaseName -split '___'
        $jsonVer = if ($parts.Count -ge 2) { $parts[-1] } else { "" }

        if ($jsonVer -and -not $activeVersions.ContainsKey($jsonVer)) {
            $findings += [PSCustomObject]@{ Type = "XPP_JSON"; Path = $json.FullName; Name = $json.Name; Reason = "old version $jsonVer config (not tracked)" }
        }
    }
}

# --- 3. Version directories (10.0.*) ---
if (Test-Path $dynamicsRoot) {
    $verDirs = @(Get-ChildItem -Path $dynamicsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' })

    foreach ($vd in $verDirs) {
        if ($activeVersions.ContainsKey($vd.Name)) { continue }

        $topItems = @(Get-ChildItem -Path $vd.FullName -ErrorAction SilentlyContinue)
        $findings += [PSCustomObject]@{ Type = "VER"; Path = $vd.FullName; Name = $vd.Name; Reason = "orphaned platform version ($($topItems.Count) top-level items)" }
    }
}

# --- Output ---
$rslCount = @($findings | Where-Object { $_.Type -eq 'RSL' }).Count
$xppCount = @($findings | Where-Object { $_.Type -in @('XPP','XPP_JSON') }).Count
$verCount = @($findings | Where-Object { $_.Type -eq 'VER' }).Count
$total    = $findings.Count

if ($total -eq 0) {
    Write-Host "RESIDUAL_SCAN_CLEAN: No stale residuals found."
    exit 0
}

Write-Host ""
Write-Host "Stale residuals found:"
foreach ($f in $findings) {
    Write-Host "  RESIDUAL: $($f.Type) | $($f.Name) | $($f.Reason)"
}
Write-Host ""
Write-Host "RESIDUAL_SUMMARY: total=$total rsl=$rslCount xpp=$xppCount ver=$verCount"

if (-not $Delete) {
    exit 0
}

# --- Delete mode (caller already obtained user approval) ---
Write-Host ""
Write-Host "Deleting $total stale items..."

$hasSqlcmd = [bool](Get-Command sqlcmd -ErrorAction SilentlyContinue)
if (-not $hasSqlcmd) {
    Write-Host "  NOTE: sqlcmd not on PATH — skipping XRef DB detach (delete .mdf files directly)."
}

$deleted = 0
$failed  = 0

foreach ($f in $findings) {
    try {
        # For XPP subfolders: detach any XRef DBs before removing the .mdf files
        if ($f.Type -eq 'XPP' -and $hasSqlcmd) {
            # Try reading DB name from companion JSON first
            $companionJsonPath = Join-Path $xppDir "$($f.Name).json"
            $dbName = ""
            if (Test-Path $companionJsonPath) {
                try {
                    $j = Get-Content -Raw -Encoding UTF8 $companionJsonPath | ConvertFrom-Json
                    if ($j.PSObject.Properties.Name -contains 'CrossReferencesDatabaseName') {
                        $dbName = $j.CrossReferencesDatabaseName
                    }
                } catch { }
            }
            # Fallback: try .mdf filenames
            if (-not $dbName) {
                $mdfFiles = @(Get-ChildItem -Path $f.Path -Filter "*.mdf" -ErrorAction SilentlyContinue)
                if ($mdfFiles.Count -gt 0) {
                    $dbName = [System.IO.Path]::GetFileNameWithoutExtension($mdfFiles[0].Name)
                }
            }
            if ($dbName) {
                $safeDbName = $dbName -replace "'", "''"
                try {
                    $checkDb = & sqlcmd -S "(LocalDB)\MSSQLLocalDB" -Q "SELECT name FROM sys.databases WHERE name = '$safeDbName'" -h -1 -W 2>&1
                    if ($checkDb -match [regex]::Escape($dbName)) {
                        & sqlcmd -S "(LocalDB)\MSSQLLocalDB" -Q "EXEC sp_detach_db '$safeDbName', 'true'" 2>&1 | Out-Null
                        Write-Host "  Detached XRef DB: $dbName"
                    }
                } catch {
                    Write-Host "  WARN: could not detach DB $dbName - $($_.Exception.Message)"
                }
            }
        }

        Remove-Item -Path $f.Path -Recurse -Force -Confirm:$false -ErrorAction Stop
        Write-Host "  DELETED: $($f.Name)"
        $deleted++
    } catch {
        Write-Host "  WARN: failed to delete $($f.Name) - $($_.Exception.Message)"
        $failed++
    }
}

Write-Host ""
Write-Host "RESIDUAL_CLEANUP_DONE: deleted=$deleted failed=$failed"

exit 0
