# dismiss_start_window.ps1 - get a freshly-launched VS to a CLEAN main IDE so later
# UIA/menu steps work. A fresh VS shows the "Get Started" Start Window (no usable
# menu bar) and may pop undocumented modal dialogs (e.g. "Please install Modeling
# SDK"). If we don't clear these, SendKeys lands in the "Open recent" search box.
#
# Loops until clean:
#   1. close ANY undocumented dialog (Dismiss-UnexpectedDialog - generic + safe),
#   2. if the Start Window is showing, click "Continue without code",
#   3. succeed when the Start Window is GONE and no undocumented dialog remains.
#
# Readiness is determined by Test-VsStartWindow (the GetToCodeWorkflowView control),
# NOT by "a MenuBar element exists" - the VS shell exposes an empty MenuBar even on
# the Start Window, which previously caused a false "already at IDE" result.
#
# Usage: dismiss_start_window.ps1 [-TimeoutSeconds 90]
# Emits: START_WINDOW_ALREADY_IDE | START_WINDOW_HANDLED | START_WINDOW_TIMEOUT

param([int]$TimeoutSeconds = 90)

. "$PSScriptRoot\uia_helpers.ps1"   # Dismiss-UnexpectedDialog, Test-VsStartWindow, Get-Vs*

$AE  = [System.Windows.Automation.AutomationElement]
$TS  = [System.Windows.Automation.TreeScope]
$CT  = [System.Windows.Automation.ControlType]
$IPP = [System.Windows.Automation.InvokePattern]

function Get-VsElem {
    $vs = Get-VsProcess
    if (-not $vs) { return $null }
    return Get-VsAutomationElement -VsPid $vs.Id
}
function Click-ContinueWithoutCode($vs) {
    if (-not $vs) { return $false }
    foreach ($ct in @($CT::Button, $CT::Hyperlink, $CT::Text, $CT::ListItem)) {
        $cond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $ct)
        foreach ($e in @($vs.FindAll($TS::Descendants, $cond))) {
            if (("" + $e.Current.Name) -like '*Continue without code*') {
                Write-Output "Clicking 'Continue without code'..."
                try { $e.GetCurrentPattern($IPP::Pattern).Invoke(); return $true } catch { return $false }
            }
        }
    }
    return $false
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$did = $false
while ((Get-Date) -lt $deadline) {
    $vs = Get-VsElem
    if (-not $vs) { Start-Sleep -Milliseconds 700; continue }

    $dismissedCount = Dismiss-UnexpectedDialog
    if ($dismissedCount -gt 0) { $did = $true }

    $atStart = Test-VsStartWindow
    if (-not $atStart -and $dismissedCount -eq 0) {
        if ($did) { Write-Output "START_WINDOW_HANDLED" } else { Write-Output "START_WINDOW_ALREADY_IDE" }
        exit 0
    }

    if ($atStart) {
        if (Click-ContinueWithoutCode $vs) { $did = $true; Start-Sleep -Seconds 2 }
    }

    Start-Sleep -Milliseconds 800
}

if (-not (Test-VsStartWindow) -and ((Dismiss-UnexpectedDialog) -eq 0)) {
    Write-Output "START_WINDOW_HANDLED"; exit 0
}
Write-Output "START_WINDOW_TIMEOUT (still at Start Window after ${TimeoutSeconds}s)"
exit 1
