# snapshot_xppconfig.ps1 - capture a baseline of XPPConfig\ before a switch
# Output: prints each "name|lastWriteTime" line. Caller saves to a file and diffs later.

. "$PSScriptRoot\config_helpers.ps1"

$xppDir = Get-XppConfigDir
if (-not (Test-Path $xppDir)) {
    # Folder doesn't exist yet - empty baseline is fine
    return
}

Get-ChildItem -Path $xppDir -Filter "*.json" -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { "$($_.Name)|$($_.LastWriteTime.ToString('o'))" }
