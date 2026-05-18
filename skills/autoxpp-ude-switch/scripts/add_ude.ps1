# add_ude.ps1 - interactive add flow. Prompts for UDE details and appends to ude-configs.json.
#
# Usage:
#   add_ude.ps1                                  # fully interactive
#   add_ude.ps1 -Name <n> -DataverseUrl <u> ...  # non-interactive (any missing prompted)

param(
    [string]$Name,
    [string]$Description = "",
    [string]$DataverseUrl,
    [string]$FoUrl = "",
    [string]$CustomMetadataFolder,
    [string]$MsAccount = "",
    [string]$SolutionName = "",
    [string]$DefaultCompany = ""
)

. "$PSScriptRoot\config_helpers.ps1"

function Read-Required {
    param([string]$Prompt, [string]$Default = "")
    while ($true) {
        $p = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
        $v = Read-Host $p
        if (-not $v -and $Default) { return $Default }
        if ($v) { return $v.Trim() }
        Write-Host "  (required)"
    }
}

function Read-Optional {
    param([string]$Prompt, [string]$Default = "")
    $p = if ($Default) { "$Prompt [$Default, or Enter to skip]" } else { "$Prompt (optional, Enter to skip)" }
    $v = Read-Host $p
    if (-not $v -and $Default) { return $Default }
    return ($v ?? "").Trim()
}

$cfg = Load-UdeConfigs
$defaults = $cfg.defaults

if (-not $Name) { $Name = Read-Required "UDE name (unique key, e.g. 'customer-dev1')" }

# Check collision
if ($cfg.udeConfigs | Where-Object { $_.name -eq $Name }) {
    Write-Host "ERROR: UDE '$Name' already exists in config. Edit ude-configs.json directly to modify."
    exit 3
}

if (-not $DataverseUrl) { $DataverseUrl = Read-Required "Dataverse URL (e.g. https://org.crm.dynamics.com)" }

if (-not $CustomMetadataFolder) {
    $metaRoot = if ($defaults -and $defaults.defaultCustomMetadataRoot) { $defaults.defaultCustomMetadataRoot } else { "C:\D365Metadata" }
    $suggested = Join-Path $metaRoot "$Name\Metadata"
    $CustomMetadataFolder = Read-Required "Custom metadata folder (full path)" $suggested
}

if (-not $Description) { $Description = Read-Optional "Description (human-readable label)" }
if (-not $FoUrl)       { $FoUrl       = Read-Optional "FO URL (e.g. https://org.sandbox.operations.dynamics.com)" }
if (-not $MsAccount)   { $MsAccount   = Read-Optional "MS account (only if different from default)" }
if (-not $SolutionName){ $SolutionName= Read-Optional "Solution name" "Default" }
if (-not $DefaultCompany) { $DefaultCompany = Read-Optional "Default company (e.g. USMF)" }

# Build entry — omit fields that match defaults or are empty
$entry = [ordered]@{
    name                 = $Name
    description          = $Description
    dataverseUrl         = $DataverseUrl
    customMetadataFolder = $CustomMetadataFolder
}
if ($FoUrl)       { $entry.foUrl = $FoUrl }
if ($DefaultCompany) { $entry.defaultCompany = $DefaultCompany }

# Only store override values (not matching defaults)
$defaultMsAccount = if ($defaults) { $defaults.msAccount } else { "" }
if ($MsAccount -and $MsAccount -ne $defaultMsAccount) { $entry.msAccount = $MsAccount }

$defaultSolName = if ($defaults) { $defaults.solutionName } else { "Default" }
if ($SolutionName -and $SolutionName -ne $defaultSolName) { $entry.solutionName = $SolutionName }

$entryObj = [PSCustomObject]$entry

# Append and save
$newList = @($cfg.udeConfigs) + $entryObj
$cfg.udeConfigs = $newList
Save-UdeConfigs $cfg

Write-Host ""
Write-Host "UDE_ADDED name=$Name"
Write-Host "  Dataverse URL : $DataverseUrl"
Write-Host "  Metadata      : $CustomMetadataFolder"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Ensure '$CustomMetadataFolder' exists (clone your customer's git repo here)"
Write-Host "  2. Run: /autoxpp-ude-switch $Name"
