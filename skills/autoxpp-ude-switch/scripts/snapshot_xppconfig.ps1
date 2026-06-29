# snapshot_xppconfig.ps1 - capture a baseline of XPPConfig\ and RuntimeSymLinks\ before a switch.
# Output: prints each "name|lastWriteTime" line. Caller saves to a file and diffs later.
# Lines are prefixed with section markers: JSON: for config files, RSL: for RuntimeSymLinks folders,
# SUB: for XPPConfig subfolders.

. "$PSScriptRoot\config_helpers.ps1"

$xppDir = Get-XppConfigDir
if (Test-Path $xppDir) {
    # XPP config JSON files
    Get-ChildItem -Path $xppDir -Filter "*.json" -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { "JSON:$($_.Name)|$($_.LastWriteTime.ToString('o'))" }

    # XPPConfig subfolders (hold XRef DB .mdf files)
    Get-ChildItem -Path $xppDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { "SUB:$($_.Name)|$($_.LastWriteTime.ToString('o'))" }
}

# RuntimeSymLinks folders
$rslDir = Get-RuntimeSymLinksDir
if (Test-Path $rslDir) {
    Get-ChildItem -Path $rslDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { "RSL:$($_.Name)|$($_.LastWriteTime.ToString('o'))" }
}
