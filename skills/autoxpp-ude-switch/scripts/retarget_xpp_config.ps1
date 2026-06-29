# retarget_xpp_config.ps1 - overwrite ModelStoreFolder/DebugSourceFolder/RuntimePackagesDirectory in an XPP JSON
#
# VS auto-generates the {name}___{version}.json with ModelStoreFolder set to
# whatever path it last saw (often the previous UDE's folder), causing all UDEs
# to collide on the same custom metadata folder. This script rewrites that path
# to the customer-specific folder from ude-configs.json.
#
# Usage: retarget_xpp_config.ps1 -XppJsonPath <path> -MetadataFolder <path> [-DefaultCompany <code>] [-RuntimeSymLinkPath <path>]
#
# Emits XPP_RETARGETED on success.

param(
    [Parameter(Mandatory=$true)][string]$XppJsonPath,
    [Parameter(Mandatory=$true)][string]$MetadataFolder,
    [string]$DefaultCompany = "",
    [string]$RuntimeSymLinkPath = ""
)

if (-not (Test-Path $XppJsonPath)) {
    Write-Host "ERROR: XPP config not found: $XppJsonPath"
    exit 1
}

# Load
$raw = Get-Content -Raw -Encoding UTF8 $XppJsonPath
$j = $raw | ConvertFrom-Json

$changed = $false
$report = @{}

# ModelStoreFolder
if ($j.PSObject.Properties.Name -contains 'ModelStoreFolder') {
    $report.ModelStoreFolder_before = $j.ModelStoreFolder
    if ($j.ModelStoreFolder -ne $MetadataFolder) {
        $j.ModelStoreFolder = $MetadataFolder
        $changed = $true
    }
} else {
    $j | Add-Member -NotePropertyName 'ModelStoreFolder' -NotePropertyValue $MetadataFolder -Force
    $report.ModelStoreFolder_before = "(missing)"
    $changed = $true
}
$report.ModelStoreFolder_after = $MetadataFolder

# DebugSourceFolder
if ($j.PSObject.Properties.Name -contains 'DebugSourceFolder') {
    $report.DebugSourceFolder_before = $j.DebugSourceFolder
    if ($j.DebugSourceFolder -ne $MetadataFolder) {
        $j.DebugSourceFolder = $MetadataFolder
        $changed = $true
    }
} else {
    $j | Add-Member -NotePropertyName 'DebugSourceFolder' -NotePropertyValue $MetadataFolder -Force
    $report.DebugSourceFolder_before = "(missing)"
    $changed = $true
}
$report.DebugSourceFolder_after = $MetadataFolder

# RuntimePackagesDirectory (optional - point to our tracked RuntimeSymLinks folder)
if ($RuntimeSymLinkPath) {
    if ($j.PSObject.Properties.Name -contains 'RuntimePackagesDirectory') {
        $report.RuntimePackagesDirectory_before = $j.RuntimePackagesDirectory
        if ($j.RuntimePackagesDirectory -ne $RuntimeSymLinkPath) {
            $j.RuntimePackagesDirectory = $RuntimeSymLinkPath
            $changed = $true
        }
    } else {
        $j | Add-Member -NotePropertyName 'RuntimePackagesDirectory' -NotePropertyValue $RuntimeSymLinkPath -Force
        $report.RuntimePackagesDirectory_before = "(missing)"
        $changed = $true
    }
    $report.RuntimePackagesDirectory_after = $RuntimeSymLinkPath
}

# DefaultCompany (optional)
if ($DefaultCompany) {
    if ($j.PSObject.Properties.Name -contains 'DefaultCompany') {
        $report.DefaultCompany_before = $j.DefaultCompany
        if ($j.DefaultCompany -ne $DefaultCompany) {
            $j.DefaultCompany = $DefaultCompany
            $changed = $true
        }
    } else {
        $j | Add-Member -NotePropertyName 'DefaultCompany' -NotePropertyValue $DefaultCompany -Force
        $report.DefaultCompany_before = "(missing)"
        $changed = $true
    }
    $report.DefaultCompany_after = $DefaultCompany
}

if (-not $changed) {
    Write-Host "XPP_RETARGET_SKIPPED: already correct"
    Write-Host "  ModelStoreFolder         : $($j.ModelStoreFolder)"
    Write-Host "  DebugSourceFolder        : $($j.DebugSourceFolder)"
    if ($RuntimeSymLinkPath) { Write-Host "  RuntimePackagesDirectory : $($j.RuntimePackagesDirectory)" }
    if ($DefaultCompany) { Write-Host "  DefaultCompany           : $($j.DefaultCompany)" }
    exit 0
}

# Back up original before writing
$backup = "$XppJsonPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -Path $XppJsonPath -Destination $backup -Force

# Write pretty JSON, no BOM - VS rejects a UTF-8 BOM in XPP config files
# ("Configuration file ... is not valid. Default values will be used.").
# The -replace also normalizes PowerShell's double-space-after-colon quirk.
$newJson = ($j | ConvertTo-Json -Depth 20) -replace ':  ', ': '
[System.IO.File]::WriteAllText($XppJsonPath, $newJson, (New-Object System.Text.UTF8Encoding $false))

Write-Host "XPP_RETARGETED: $XppJsonPath"
Write-Host "  Backup                   : $backup"
Write-Host "  ModelStoreFolder         : $($report.ModelStoreFolder_before)  ->  $($report.ModelStoreFolder_after)"
Write-Host "  DebugSourceFolder        : $($report.DebugSourceFolder_before)  ->  $($report.DebugSourceFolder_after)"
if ($RuntimeSymLinkPath -and $report.ContainsKey('RuntimePackagesDirectory_before')) {
    Write-Host "  RuntimePackagesDirectory : $($report.RuntimePackagesDirectory_before)  ->  $($report.RuntimePackagesDirectory_after)"
}
if ($DefaultCompany) {
    Write-Host "  DefaultCompany           : $($report.DefaultCompany_before)  ->  $($report.DefaultCompany_after)"
}
exit 0
