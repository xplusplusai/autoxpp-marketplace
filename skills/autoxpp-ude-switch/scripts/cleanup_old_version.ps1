# cleanup_old_version.ps1 - remove artifacts from a previous version after a version change.
#
# Detaches the old XRef DB from LocalDB, deletes old XPPConfig subfolder (with .mdf files),
# old config JSON, and old RuntimeSymLinks folder. Only acts on explicitly named artifacts;
# never scans or deletes speculatively.
#
# Usage:
#   cleanup_old_version.ps1 [-OldXrefDbName <name>] [-OldXppSubfolder <name>]
#                           [-OldConfigJson <name>] [-OldRslFolder <name>]
#
# All parameters are optional. Only supplied artifacts are cleaned up.
# Emits: CLEANUP_<artifact>_OK or CLEANUP_<artifact>_SKIP per artifact.
# Exit code: always 0 (cleanup failures are non-fatal warnings).

param(
    [string]$OldXrefDbName = "",
    [string]$OldXppSubfolder = "",
    [string]$OldConfigJson = "",
    [string]$OldRslFolder = ""
)

. "$PSScriptRoot\config_helpers.ps1"

$xppDir = Get-XppConfigDir
$rslDir = Get-RuntimeSymLinksDir

# --- 1) Detach old XRef DB from LocalDB ---
if ($OldXrefDbName) {
    try {
        $checkDb = & sqlcmd -S "(LocalDB)\MSSQLLocalDB" -Q "SELECT name FROM sys.databases WHERE name = '$OldXrefDbName'" -h -1 -W 2>&1
        if ($checkDb -match $OldXrefDbName) {
            Write-Host "  Detaching old XRef DB: $OldXrefDbName"
            & sqlcmd -S "(LocalDB)\MSSQLLocalDB" -Q "EXEC sp_detach_db '$OldXrefDbName', 'true'" 2>&1 | Out-Null
            Write-Host "CLEANUP_XREF_DB_OK: detached $OldXrefDbName"
        } else {
            Write-Host "CLEANUP_XREF_DB_SKIP: $OldXrefDbName not found in LocalDB (already detached)"
        }
    } catch {
        Write-Host "CLEANUP_XREF_DB_WARN: failed to detach $OldXrefDbName - $($_.Exception.Message)"
    }
}

# --- 2) Delete old XPPConfig subfolder (holds .mdf/.ldf files) ---
if ($OldXppSubfolder) {
    $subPath = Join-Path $xppDir $OldXppSubfolder
    if (Test-Path $subPath) {
        try {
            Remove-Item -Path $subPath -Recurse -Force
            Write-Host "CLEANUP_XPP_SUBFOLDER_OK: deleted $OldXppSubfolder"
        } catch {
            Write-Host "CLEANUP_XPP_SUBFOLDER_WARN: failed to delete $subPath - $($_.Exception.Message)"
        }
    } else {
        Write-Host "CLEANUP_XPP_SUBFOLDER_SKIP: $OldXppSubfolder does not exist"
    }
}

# --- 3) Delete old config JSON ---
if ($OldConfigJson) {
    $jsonPath = Join-Path $xppDir $OldConfigJson
    if (Test-Path $jsonPath) {
        try {
            Remove-Item -Path $jsonPath -Force
            Write-Host "CLEANUP_CONFIG_JSON_OK: deleted $OldConfigJson"
        } catch {
            Write-Host "CLEANUP_CONFIG_JSON_WARN: failed to delete $jsonPath - $($_.Exception.Message)"
        }
    } else {
        Write-Host "CLEANUP_CONFIG_JSON_SKIP: $OldConfigJson does not exist"
    }
    # Also remove any .bak files for the old config
    Get-ChildItem -Path $xppDir -Filter "${OldConfigJson}.bak-*" -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
}

# --- 4) Delete old RuntimeSymLinks folder ---
if ($OldRslFolder) {
    $rslPath = Join-Path $rslDir $OldRslFolder
    if (Test-Path $rslPath) {
        try {
            Remove-Item -Path $rslPath -Recurse -Force
            Write-Host "CLEANUP_RSL_FOLDER_OK: deleted $OldRslFolder"
        } catch {
            Write-Host "CLEANUP_RSL_FOLDER_WARN: failed to delete $rslPath - $($_.Exception.Message)"
        }
    } else {
        Write-Host "CLEANUP_RSL_FOLDER_SKIP: $OldRslFolder does not exist"
    }
}

exit 0
