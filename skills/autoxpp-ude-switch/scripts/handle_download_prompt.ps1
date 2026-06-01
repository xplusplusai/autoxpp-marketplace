# handle_download_prompt.ps1 - respond to "Client assets download" prompt
#
# Dialog text (observed):
#   Title: "Client assets download"
#   Body:  "Proceed with downloading the metadata, F&O VS extension and
#           other assets for the version X.Y.Z ?"
#   Buttons: Yes | No
#
# Policy:
#   always       -> click Yes unconditionally
#   ask          -> click Yes (safe default for v1; "ask" becomes "auto-no-if-cached" in v2)
#   skip         -> click No; warn if version not cached
#   skip-if-cached -> click No ONLY if %LocalAppData%\Dynamics365\{version} exists; else Yes
#
# Usage: handle_download_prompt.ps1 -Policy <always|ask|skip|skip-if-cached> [-TimeoutSeconds 120]
#
# Emits:
#   DOWNLOAD_PROMPT_HANDLED choice=<Yes|No> version=<x.y.z> cached=<yes|no>
#   DOWNLOAD_PROMPT_ABSENT (version already downloaded — no prompt shown)
#   DOWNLOAD_PROMPT_ERROR <reason>

param(
    [ValidateSet('always','ask','skip','skip-if-cached')]
    [string]$Policy = 'ask',
    [int]$TimeoutSeconds = 120
)

. "$PSScriptRoot\uia_helpers.ps1"
. "$PSScriptRoot\config_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Host "DOWNLOAD_PROMPT_ERROR VS not running"; exit 1 }

$vsElem = Get-VsAutomationElement -VsPid $vs.Id
$dialog = Wait-ForChildWindow -Parent $vsElem -NameContains @('Client assets download') -TimeoutSeconds $TimeoutSeconds

if (-not $dialog) {
    Write-Host "DOWNLOAD_PROMPT_ABSENT (no prompt within ${TimeoutSeconds}s — assets likely already cached)"
    exit 0
}

# Extract version from dialog text
$textCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Text)
$texts = $dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCond)
$body = ""
foreach ($t in $texts) { if ($t.Current.Name) { $body += " " + $t.Current.Name } }

$version = ""
$m = [regex]::Match($body, 'version\s+([\d\.]+)')
if ($m.Success) { $version = $m.Groups[1].Value }

$cached = $false
if ($version) {
    $verPath = Join-Path (Get-DynamicsRoot) $version
    $cached = Test-Path $verPath
}

$choice = switch ($Policy) {
    'always'         { 'Yes' }
    'ask'            { 'Yes' }  # v1 safe default
    'skip'           { 'No' }
    'skip-if-cached' { if ($cached) { 'No' } else { 'Yes' } }
    default          { 'Yes' }
}

$btn = Find-ButtonByName -Parent $dialog -Name $choice
if (-not $btn) {
    Write-Host "DOWNLOAD_PROMPT_ERROR '$choice' button not found"
    exit 1
}

$click = Invoke-Button -Button $btn -VsHwnd $vs.MainWindowHandle
# Write-Output (not Write-Host) so the parent's $dlOut captures this line and can
# parse 'choice=Yes' to decide whether to wait for the metadata download.
Write-Output "DOWNLOAD_PROMPT_HANDLED choice=$choice version=$version cached=$cached click=$click"
exit 0
