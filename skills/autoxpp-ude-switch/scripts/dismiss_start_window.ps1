# dismiss_start_window.ps1 - get a freshly-launched VS to a CLEAN main IDE so later
# UIA/menu steps work. A fresh VS shows the "Get Started" Start Window (no menu bar)
# and may pop modal dialogs (e.g. "Please install Modeling SDK before proceeding").
# If we don't get past this, SendKeys lands in the "Open recent" search box.
#
# This script loops until the IDE is clean:
#   1. dismiss modal "Microsoft Visual Studio" message boxes (top-level OR VS child),
#   2. click "Continue without code" on the Start Window,
#   3. succeed only when a menu bar is present AND no message box remains.
#
# Best-effort and idempotent: a no-op if already at a clean main IDE.
#
# Usage: dismiss_start_window.ps1 [-TimeoutSeconds 90]
# Emits: START_WINDOW_ALREADY_IDE | START_WINDOW_HANDLED | START_WINDOW_TIMEOUT

param([int]$TimeoutSeconds = 90)

Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
Add-Type -AssemblyName UIAutomationTypes  -ErrorAction SilentlyContinue

$AE  = [System.Windows.Automation.AutomationElement]
$TS  = [System.Windows.Automation.TreeScope]
$CT  = [System.Windows.Automation.ControlType]
$IPP = [System.Windows.Automation.InvokePattern]

function Get-VsElem {
    $p = Get-Process devenv -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if (-not $p) { return $null }
    $c = New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty, $p.Id)
    return $AE::RootElement.FindFirst($TS::Children, $c)
}
function Invoke-Elem($el) { try { $el.GetCurrentPattern($IPP::Pattern).Invoke(); return $true } catch { return $false } }
function Find-Cond($parent, $scope, $ct) {
    @($parent.FindAll($scope, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $ct))))
}
function Has-MenuBar($vs) {
    if (-not $vs) { return $false }
    [bool]($vs.FindFirst($TS::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::MenuBar))))
}

# Dismiss "Microsoft Visual Studio" message boxes, searching top-level desktop windows
# AND the VS child windows. Returns $true if any was dismissed.
function Dismiss-Dialogs($vs) {
    $dismissed = $false
    $parents = @($AE::RootElement)
    if ($vs) { $parents += $vs }
    foreach ($parent in $parents) {
        foreach ($w in (Find-Cond $parent $TS::Children $CT::Window)) {
            if ($w.Current.Name -ne 'Microsoft Visual Studio') { continue }
            $btns = Find-Cond $w $TS::Descendants $CT::Button
            if ($btns.Count -eq 0) { continue }
            $target = $null
            foreach ($b in $btns) { if ($b.Current.Name -in @('OK','Ok','Close','Continue','Yes')) { $target = $b; break } }
            if (-not $target) { $target = $btns[0] }
            Write-Output "Closing dialog: Microsoft Visual Studio (button '$($target.Current.Name)')"
            [void](Invoke-Elem $target); $dismissed = $true; Start-Sleep -Milliseconds 700
        }
    }
    return $dismissed
}
function Has-VsDialog($vs) {
    $parents = @($AE::RootElement)
    if ($vs) { $parents += $vs }
    foreach ($parent in $parents) {
        foreach ($w in (Find-Cond $parent $TS::Children $CT::Window)) {
            if ($w.Current.Name -eq 'Microsoft Visual Studio') { return $true }
        }
    }
    return $false
}
function Click-ContinueWithoutCode($vs) {
    if (-not $vs) { return $false }
    foreach ($ct in @($CT::Button, $CT::Hyperlink, $CT::Text, $CT::ListItem)) {
        foreach ($e in (Find-Cond $vs $TS::Descendants $ct)) {
            if ($e.Current.Name -like '*Continue without code*') {
                Write-Output "Clicking 'Continue without code'..."
                return (Invoke-Elem $e)
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

    if (Dismiss-Dialogs $vs) { $did = $true }

    if ((Has-MenuBar $vs) -and -not (Has-VsDialog $vs)) {
        if ($did) { Write-Output "START_WINDOW_HANDLED" } else { Write-Output "START_WINDOW_ALREADY_IDE" }
        exit 0
    }

    if (Click-ContinueWithoutCode $vs) { $did = $true; Start-Sleep -Seconds 2 }

    Start-Sleep -Milliseconds 800
}

$vs = Get-VsElem
if ((Has-MenuBar $vs) -and -not (Has-VsDialog $vs)) { Write-Output "START_WINDOW_HANDLED"; exit 0 }
Write-Output "START_WINDOW_TIMEOUT (clean main IDE not reached within ${TimeoutSeconds}s)"
exit 1
