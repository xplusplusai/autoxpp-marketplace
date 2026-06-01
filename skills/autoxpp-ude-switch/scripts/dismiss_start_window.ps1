# dismiss_start_window.ps1 - get a freshly-launched VS past its Start Window and any
# startup dialogs so the main IDE (with a menu bar) is available for later UIA steps.
#
# A fresh VS opens the "Get Started" Start Window, which has NO menu bar, so Tools >
# Options and Tools > Connect-to-Dataverse navigation fails. It may also show modal
# startup dialogs (e.g. "Please install Modeling SDK before proceeding"). This script:
#   1. dismisses modal startup message boxes (clicks their button),
#   2. clicks "Continue without code" to enter the main IDE,
#   3. waits until a menu bar is present.
#
# Best-effort and idempotent: if VS is already at the main IDE (menu bar present),
# it is a no-op and returns success immediately.
#
# Usage: dismiss_start_window.ps1 [-TimeoutSeconds 60]
# Emits:
#   START_WINDOW_ALREADY_IDE   (menu bar already present, nothing to do)
#   START_WINDOW_HANDLED       (dismissed dialogs / clicked Continue without code)
#   START_WINDOW_TIMEOUT       (menu bar still not available)

param([int]$TimeoutSeconds = 60)

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
    $cond = New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty, $p.Id)
    return [System.Windows.Automation.AutomationElement]::RootElement.FindFirst($TS::Children, $cond)
}

function Invoke-Elem($el) {
    try { $el.GetCurrentPattern($IPP::Pattern).Invoke(); return $true } catch { return $false }
}

function Has-MenuBar($vs) {
    if (-not $vs) { return $false }
    $mb = $vs.FindFirst($TS::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::MenuBar)))
    return [bool]$mb
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$didSomething = $false

while ((Get-Date) -lt $deadline) {
    $vs = Get-VsElem
    if (-not $vs) { Start-Sleep -Milliseconds 700; continue }

    if (Has-MenuBar $vs) {
        if ($didSomething) { Write-Output "START_WINDOW_HANDLED" } else { Write-Output "START_WINDOW_ALREADY_IDE" }
        exit 0
    }

    # 1) Dismiss modal startup dialogs (e.g. Modeling SDK error). Any child Window with a button.
    $dlgs = $vs.FindAll($TS::Children,
        (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Window)))
    foreach ($d in $dlgs) {
        $btn = $d.FindFirst($TS::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button)))
        if ($btn) {
            Write-Output "Dismissing startup dialog: $($d.Current.Name)"
            [void](Invoke-Elem $btn); $didSomething = $true; Start-Sleep -Milliseconds 700
        }
    }

    # 2) Click "Continue without code" on the Start Window (Button / Hyperlink / Text).
    $cwc = $null
    foreach ($ctype in @($CT::Button, $CT::Hyperlink, $CT::Text)) {
        $els = $vs.FindAll($TS::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $ctype)))
        foreach ($e in $els) {
            if ($e.Current.Name -like '*Continue without code*') { $cwc = $e; break }
        }
        if ($cwc) { break }
    }
    if ($cwc) {
        Write-Output "Clicking 'Continue without code'..."
        [void](Invoke-Elem $cwc)
        $didSomething = $true
        Start-Sleep -Seconds 2
    }

    Start-Sleep -Milliseconds 800
}

# Final check after the loop.
if (Has-MenuBar (Get-VsElem)) { Write-Output "START_WINDOW_HANDLED"; exit 0 }
Write-Output "START_WINDOW_TIMEOUT (menu bar not available within ${TimeoutSeconds}s)"
exit 1
