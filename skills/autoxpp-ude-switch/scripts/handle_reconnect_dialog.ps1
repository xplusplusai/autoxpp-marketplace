# handle_reconnect_dialog.ps1 - click "No" on the "Reconnect to Dataverse" dialog
# if it appears. If it doesn't appear within timeout (first-time connect), continue.
#
# Emits:
#   RECONNECT_DIALOG_HANDLED clicked=No
#   RECONNECT_DIALOG_ABSENT
#   RECONNECT_DIALOG_ERROR <reason>

param([int]$TimeoutSeconds = 15)

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Host "RECONNECT_DIALOG_ERROR VS not running"; exit 1 }

$vsElem = Get-VsAutomationElement -VsPid $vs.Id
$dialog = Wait-ForChildWindow -Parent $vsElem -NameContains @('Reconnect to Dataverse') -TimeoutSeconds $TimeoutSeconds

if (-not $dialog) {
    Write-Host "RECONNECT_DIALOG_ABSENT (no prior connection to reuse - proceeding to Login)"
    exit 0
}

$btn = Find-ButtonByName -Parent $dialog -Name "No"
if (-not $btn) {
    Write-Host "RECONNECT_DIALOG_ERROR 'No' button not found on dialog"
    exit 1
}

$result = Invoke-Button -Button $btn -VsHwnd $vs.MainWindowHandle
Write-Host "RECONNECT_DIALOG_HANDLED clicked=No via=$result"
exit 0
