# list_udes.ps1 - print configured UDEs with lastUsed + cache status

. "$PSScriptRoot\config_helpers.ps1"

$cfg = Load-UdeConfigs

if (-not $cfg.udeConfigs -or $cfg.udeConfigs.Count -eq 0) {
    Write-Host "No UDEs configured. Run '/autoxpp-ude-switch --add' to add one."
    exit 0
}

$dynRoot = Get-DynamicsRoot
$xppDir  = Get-XppConfigDir

Write-Host ""
Write-Host "Configured UDEs:"
Write-Host ""

$rows = foreach ($u in $cfg.udeConfigs) {
    $ver = if ($u.PSObject.Properties.Name -contains 'lastKnownVersion') { $u.lastKnownVersion } else { "" }
    $lastUsed = if ($u.PSObject.Properties.Name -contains 'lastUsed') { $u.lastUsed } else { "never" }

    $cached = "no"
    if ($ver) {
        $verPath = Join-Path $dynRoot $ver
        if (Test-Path $verPath) { $cached = "yes ($ver)" }
    }

    $xppJson = Get-ChildItem -Path $xppDir -Filter "$($u.name)___*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
    $xppStatus = if ($xppJson) { $xppJson.Name } else { "not-created" }

    [PSCustomObject]@{
        Name          = $u.name
        Description   = if ($u.description) { $u.description } else { "" }
        DataverseUrl  = $u.dataverseUrl
        MetadataCache = $cached
        XppConfig     = $xppStatus
        LastUsed      = $lastUsed
    }
}

$rows | Format-Table -AutoSize
Write-Host ""
Write-Host "Config file: $(Get-UdeConfigPath)"
