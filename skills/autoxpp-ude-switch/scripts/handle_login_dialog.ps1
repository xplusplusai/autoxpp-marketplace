# handle_login_dialog.ps1 - click Login on "Power Platform Tools -> Connect to Dataverse -> Login"
#
# Pre-conditions expected from defaults:
#   - Deployment Type: Office 365 (radio)
#   - Sign in as current user: checked
# These are the VS defaults and the user's standing setup. We verify rather than force-set
# to avoid disturbing a working config.
#
# Emits:
#   LOGIN_DIALOG_HANDLED clicked=Login
#   LOGIN_DIALOG_MISSING
#   LOGIN_DIALOG_ERROR <reason>

param([int]$TimeoutSeconds = 20)

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Host "LOGIN_DIALOG_ERROR VS not running"; exit 1 }

$vsElem = Get-VsAutomationElement -VsPid $vs.Id
$dialog = Wait-ForChildWindow -Parent $vsElem -NameContains @('Power Platform Tools','Connect to Dataverse') -TimeoutSeconds $TimeoutSeconds

if (-not $dialog) {
    Write-Host "LOGIN_DIALOG_MISSING (dialog did not appear within ${TimeoutSeconds}s)"
    exit 1
}

# Find the Login button inside
$btn = Find-ButtonByName -Parent $dialog -Name "Login"
if (-not $btn) {
    Write-Host "LOGIN_DIALOG_ERROR Login button not found"
    exit 1
}

$result = Invoke-Button -Button $btn -VsHwnd $vs.MainWindowHandle
Write-Host "LOGIN_DIALOG_HANDLED clicked=Login via=$result"
exit 0
