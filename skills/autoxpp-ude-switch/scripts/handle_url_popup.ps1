# handle_url_popup.ps1 - enter environment URL and click Ok on the small popup
# that appears after clicking Login ("Enter environment instance url" window).
#
# Usage: handle_url_popup.ps1 -Url <dataverseUrl> [-TimeoutSeconds 30]
#
# Emits:
#   URL_POPUP_HANDLED url=<url>
#   URL_POPUP_MISSING
#   URL_POPUP_ERROR <reason>

param(
    [Parameter(Mandatory=$true)][string]$Url,
    [int]$TimeoutSeconds = 30
)

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Host "URL_POPUP_ERROR VS not running"; exit 1 }

$vsElem = Get-VsAutomationElement -VsPid $vs.Id

# The popup title text is "Enter environment instance url"
$popup = Wait-ForChildWindow -Parent $vsElem -NameContains @('Enter environment instance url','environment instance') -TimeoutSeconds $TimeoutSeconds
if (-not $popup) {
    Write-Host "URL_POPUP_MISSING (popup did not appear within ${TimeoutSeconds}s)"
    exit 1
}

# Find the Edit control (there should be exactly one on this popup)
$edit = Find-EditControl -Parent $popup -Index 0
if (-not $edit) {
    Write-Host "URL_POPUP_ERROR Edit control not found"
    exit 1
}

$setResult = Set-EditText -Edit $edit -Text $Url
Start-Sleep -Milliseconds 300

# Click OK (label is "Ok" per screenshot - verify case)
$btn = Find-ButtonByName -Parent $popup -Name "Ok"
if (-not $btn) { $btn = Find-ButtonByName -Parent $popup -Name "OK" }
if (-not $btn) {
    Write-Host "URL_POPUP_ERROR OK button not found"
    exit 1
}

$click = Invoke-Button -Button $btn -VsHwnd $vs.MainWindowHandle
Write-Host "URL_POPUP_HANDLED url=$Url textset=$setResult click=$click"
exit 0
