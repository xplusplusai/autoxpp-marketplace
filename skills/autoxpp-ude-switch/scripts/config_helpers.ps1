# config_helpers.ps1
# Dot-sourced helper for loading/merging/updating ude-configs.json.
# Usage (from other scripts):
#   . "$PSScriptRoot\config_helpers.ps1"
#   $cfg = Load-UdeConfigs
#   $ude = Resolve-Ude $cfg "<env-name>"

$script:UdeConfigPath = Join-Path $env:USERPROFILE ".autoxpp\ude-configs.json"
$script:UdeLogDir     = Join-Path $env:USERPROFILE ".autoxpp\logs"
$script:XppConfigDir  = Join-Path $env:LOCALAPPDATA "Microsoft\Dynamics365\XPPConfig"
$script:DynamicsRoot  = Join-Path $env:LOCALAPPDATA "Microsoft\Dynamics365"

function Get-UdeConfigPath { return $script:UdeConfigPath }
function Get-UdeLogDir     { return $script:UdeLogDir }
function Get-XppConfigDir  { return $script:XppConfigDir }
function Get-DynamicsRoot  { return $script:DynamicsRoot }

function Load-UdeConfigs {
    if (-not (Test-Path $script:UdeConfigPath)) {
        throw "ude-configs.json not found at $script:UdeConfigPath. Run '/autoxpp-ude-switch --add' to create."
    }
    $raw = Get-Content -Raw -Encoding UTF8 $script:UdeConfigPath
    try {
        return $raw | ConvertFrom-Json
    } catch {
        throw "ude-configs.json is not valid JSON: $($_.Exception.Message)"
    }
}

function Save-UdeConfigs {
    param([Parameter(Mandatory=$true)]$Config)
    $dir = Split-Path -Parent $script:UdeConfigPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = $Config | ConvertTo-Json -Depth 20
    Set-Content -Path $script:UdeConfigPath -Value $json -Encoding UTF8
}

function Resolve-Ude {
    # Returns a merged hashtable with every setting resolved (defaults + per-UDE override).
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $ude = $Config.udeConfigs | Where-Object { $_.name -eq $Name }
    if (-not $ude) {
        $known = ($Config.udeConfigs | ForEach-Object { $_.name }) -join ", "
        throw "UDE '$Name' not found in config. Known UDEs: $known"
    }

    $merged = @{}
    # Copy defaults first
    if ($Config.defaults) {
        $Config.defaults.PSObject.Properties | ForEach-Object {
            $merged[$_.Name] = $_.Value
        }
    }
    # Override with UDE-specific fields
    $ude.PSObject.Properties | ForEach-Object {
        $merged[$_.Name] = $_.Value
    }

    # Validate required fields
    foreach ($req in @('name','dataverseUrl','customMetadataFolder')) {
        if (-not $merged.ContainsKey($req) -or [string]::IsNullOrWhiteSpace([string]$merged[$req])) {
            throw "UDE '$Name' missing required field '$req'"
        }
    }

    return $merged
}

function Get-ActiveUdeName {
    param([Parameter(Mandatory=$true)]$Config)
    if ($Config.PSObject.Properties.Name -contains 'activeEnv' -and
        -not [string]::IsNullOrWhiteSpace($Config.activeEnv)) {
        return $Config.activeEnv
    }
    # Fallback: most recent lastUsed (for configs not yet upgraded)
    $best = $Config.udeConfigs |
        Where-Object { $_.PSObject.Properties.Name -contains 'lastUsed' -and $_.lastUsed } |
        Sort-Object { [datetime]$_.lastUsed } -Descending |
        Select-Object -First 1
    if ($best) { return $best.name }
    # Last resort: first entry
    if ($Config.udeConfigs.Count -gt 0) { return $Config.udeConfigs[0].name }
    return $null
}

function Update-UdeLastUsed {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Version
    )
    $cfg = Load-UdeConfigs
    $ude = $cfg.udeConfigs | Where-Object { $_.name -eq $Name }
    if (-not $ude) { return }

    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Set activeEnv at the top level
    if ($cfg.PSObject.Properties.Name -contains 'activeEnv') {
        $cfg.activeEnv = $Name
    } else {
        $cfg | Add-Member -NotePropertyName 'activeEnv' -NotePropertyValue $Name
    }

    if ($ude.PSObject.Properties.Name -contains 'lastUsed') {
        $ude.lastUsed = $ts
    } else {
        $ude | Add-Member -NotePropertyName 'lastUsed' -NotePropertyValue $ts
    }

    if ($Version) {
        if ($ude.PSObject.Properties.Name -contains 'lastKnownVersion') {
            $ude.lastKnownVersion = $Version
        } else {
            $ude | Add-Member -NotePropertyName 'lastKnownVersion' -NotePropertyValue $Version
        }
    }

    Save-UdeConfigs $cfg
}

function Get-UdeLogFile {
    if (-not (Test-Path $script:UdeLogDir)) {
        New-Item -ItemType Directory -Path $script:UdeLogDir -Force | Out-Null
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return (Join-Path $script:UdeLogDir "ude-switch-$stamp.log")
}

function Write-UdeLog {
    param(
        [Parameter(Mandatory=$true)][string]$LogFile,
        [Parameter(Mandatory=$true)][string]$Step,
        [string]$Status = "INFO",
        [string]$Detail = ""
    )
    $dir = Split-Path -Parent $LogFile
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $ts = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $line = "$ts  [ude-switch]  $Status  $Step"
    if ($Detail) { $line += "  $Detail" }
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}
