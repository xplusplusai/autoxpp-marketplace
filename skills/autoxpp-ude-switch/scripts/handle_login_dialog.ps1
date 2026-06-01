# handle_login_dialog.ps1 - click Login on step 1 ("Connect to Dataverse") of the
# "Configure Microsoft Power Platform Solution" wizard.
#
# P-7 fix: the wizard window is named "Configure Microsoft Power Platform Solution"
# (not "Power Platform Tools"), and the Login button's AutomationId is btn_Connect
# (inside CrmLoginCtrl). The earlier name-only search under the VS element reported
# LOGIN_DIALOG_MISSING. We now find the wizard (top-level or embedded) and click
# btn_Connect. With WAM/SSO the click proceeds straight to the URL popup.
#
# Emits:
#   LOGIN_DIALOG_HANDLED clicked=Login
#   LOGIN_DIALOG_MISSING
#   LOGIN_DIALOG_ERROR <reason>

param([int]$TimeoutSeconds = 20)

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Output "LOGIN_DIALOG_ERROR VS not running"; exit 1 }

$dialog = Wait-AnyWindow -NameContains @(
    'Configure Microsoft Power Platform Solution',
    'Configure Power Platform Solution',
    'Power Platform Tools',
    'Connect to Dataverse') -TimeoutSeconds $TimeoutSeconds

if (-not $dialog) {
    Write-Output "LOGIN_DIALOG_MISSING (dialog did not appear within ${TimeoutSeconds}s)"
    exit 1
}

# Login button is the CrmLoginCtrl 'btn_Connect' (displayed text "Login").
$btn = Find-ByAutomationId -Parent $dialog -AutomationId 'btn_Connect'
if (-not $btn) { $btn = Find-ButtonByName -Parent $dialog -Name "Login" }
if (-not $btn) {
    Write-Output "LOGIN_DIALOG_ERROR Login button (btn_Connect) not found"
    exit 1
}

$result = Invoke-Button -Button $btn -VsHwnd $vs.MainWindowHandle
Write-Output "LOGIN_DIALOG_HANDLED clicked=Login via=$result"
exit 0
