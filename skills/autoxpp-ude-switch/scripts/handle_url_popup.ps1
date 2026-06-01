# handle_url_popup.ps1 - enter the Dataverse environment URL and click Ok on the
# "Enter environment instance url" popup that appears after clicking Login.
#
# IMPORTANT (P-5): this popup is a TOP-LEVEL window (a child of the desktop), NOT a
# child of the VS window. Earlier versions searched under the VS element and reported
# URL_POPUP_MISSING even though the popup was on screen. We now search from RootElement.
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

$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$CT = [System.Windows.Automation.ControlType]

function Find-TopLevelWindow {
    # Search the desktop's direct child windows for one whose Name matches.
    param([string[]]$NameContains)
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Window)
    $wins = $root.FindAll($TS::Children, $cond)
    foreach ($w in $wins) {
        $nm = $w.Current.Name
        if (-not $nm) { continue }
        foreach ($needle in $NameContains) { if ($nm -like "*$needle*") { return $w } }
    }
    return $null
}

# Wait for the popup as a top-level window.
$popup = $null
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    $popup = Find-TopLevelWindow -NameContains @('Enter environment instance url','environment instance')
    if ($popup) { break }
    Start-Sleep -Milliseconds 500
}
if (-not $popup) {
    Write-Output "URL_POPUP_MISSING (popup did not appear within ${TimeoutSeconds}s)"
    exit 1
}

# Find the Edit control (there should be exactly one on this popup) and set the URL.
$edit = Find-EditControl -Parent $popup -Index 0
if (-not $edit) {
    Write-Output "URL_POPUP_ERROR Edit control not found"
    exit 1
}
$setResult = Set-EditText -Edit $edit -Text $Url
Start-Sleep -Milliseconds 300

# Click Ok. Match by Name ('Ok'/'OK'), falling back to AutomationId 'btn_Save'.
$btn = Find-ButtonByName -Parent $popup -Name "Ok"
if (-not $btn) { $btn = Find-ButtonByName -Parent $popup -Name "OK" }
if (-not $btn) {
    $idCond = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, 'btn_Save')
    $btn = $popup.FindFirst($TS::Descendants, $idCond)
}
if (-not $btn) {
    Write-Output "URL_POPUP_ERROR Ok button not found"
    exit 1
}

$vs = Get-VsProcess
$vsHwnd = if ($vs) { $vs.MainWindowHandle } else { [IntPtr]::Zero }
$click = Invoke-Button -Button $btn -VsHwnd $vsHwnd
Write-Output "URL_POPUP_HANDLED url=$Url textset=$setResult click=$click"
exit 0
