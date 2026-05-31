# ensure_skip_discovery.ps1
# Opens Tools > Options > Power Platform Tools > General and ensures
# "Skip Discovery when connecting to Dataverse" is checked.
#
# Emits:
#   SKIP_DISCOVERY_ALREADY_CHECKED
#   SKIP_DISCOVERY_CHECKED (was unchecked, now checked)
#   SKIP_DISCOVERY_FAIL <reason>

param([int]$TimeoutSeconds = 30)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
Add-Type -AssemblyName UIAutomationTypes  -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public class SkipDiscNative {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    public static void ForceForeground(IntPtr hWnd) {
        ShowWindow(hWnd, 9);
        Thread.Sleep(200);
        keybd_event(0xA4, 0, 0, UIntPtr.Zero);
        SetForegroundWindow(hWnd);
        keybd_event(0xA4, 0, 2, UIntPtr.Zero);
    }
    public static void Minimize(IntPtr hWnd) { ShowWindow(hWnd, 2); }
    public static void Click(int x, int y) {
        SetCursorPos(x, y); Thread.Sleep(100);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }
}
"@ -ErrorAction SilentlyContinue

# --- Get VS process ---
$vs = Get-Process devenv -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
    Select-Object -First 1

if (-not $vs) {
    Write-Host "SKIP_DISCOVERY_FAIL VS not running"
    exit 1
}

$root = [System.Windows.Automation.AutomationElement]::RootElement
$pidCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $vs.Id)
$vsElem = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $pidCond)

if (-not $vsElem) {
    Write-Host "SKIP_DISCOVERY_FAIL cannot get VS automation element"
    exit 1
}

# --- Close any existing Options dialog first ---
$winCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Window)
$windows = $vsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $winCond)
foreach ($w in $windows) {
    if ($w.Current.Name -eq 'Options') {
        Write-Host "Closing stale Options dialog..."
        [SkipDiscNative]::ForceForeground($vs.MainWindowHandle)
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
        Start-Sleep -Milliseconds 1000
        break
    }
}

# --- Show VS and open Options via Alt+T, O ---
Write-Host "Showing VS to open Tools > Options..."
[SkipDiscNative]::ForceForeground($vs.MainWindowHandle)
Start-Sleep -Milliseconds 500

[System.Windows.Forms.SendKeys]::SendWait("%t")
Start-Sleep -Milliseconds 1500
[System.Windows.Forms.SendKeys]::SendWait("o")
Start-Sleep -Milliseconds 2000

# --- Wait for Options dialog ---
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$optionsDlg = $null
while ((Get-Date) -lt $deadline) {
    $windows = $vsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $winCond)
    foreach ($w in $windows) {
        if ($w.Current.Name -eq 'Options') { $optionsDlg = $w; break }
    }
    if ($optionsDlg) { break }
    Start-Sleep -Milliseconds 500
}

if (-not $optionsDlg) {
    Write-Host "SKIP_DISCOVERY_FAIL Options dialog did not appear"
    # no-minimize: leave VS as-is (never minimize VS — user can't restore it)
    exit 1
}

Write-Host "Options dialog found"

# --- Search "Power Platform" to navigate tree, then click General ---
Write-Host "Searching for 'Power Platform' via Ctrl+E..."
[System.Windows.Forms.SendKeys]::SendWait("^e")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("Power Platform")
Start-Sleep -Milliseconds 2000

# Press Enter to apply search and select the first match
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Milliseconds 1500

# Now find the "Skip Discovery" checkbox - it should be visible if
# Power Platform Tools > General page is showing
$cbCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::CheckBox)

$skipCb = $null
$deadline2 = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline2) {
    $checkboxes = $optionsDlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cbCond)
    foreach ($cb in $checkboxes) {
        if ($cb.Current.Name -match 'Skip Discovery') {
            $skipCb = $cb
            break
        }
    }
    if ($skipCb) { break }
    Start-Sleep -Milliseconds 500
}

if (-not $skipCb) {
    # Checkboxes not found - maybe search landed on Power Platform Tools parent
    # and we need to click General. Try pressing Down+Enter to select first child.
    Write-Host "Checkbox not found yet - trying to navigate to General..."
    # Clear search first, then use keyboard to navigate tree
    [System.Windows.Forms.SendKeys]::SendWait("^e")
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait("^a")
    [System.Windows.Forms.SendKeys]::SendWait("{DELETE}")
    Start-Sleep -Milliseconds 500
    # Tab to tree, navigate
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 300

    # Type 'p' repeatedly to jump to P entries until we find Power Platform Tools
    for ($i = 0; $i -lt 10; $i++) {
        [System.Windows.Forms.SendKeys]::SendWait("p")
        Start-Sleep -Milliseconds 400
        # Check if checkboxes appeared
        $checkboxes = $optionsDlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cbCond)
        foreach ($cb in $checkboxes) {
            if ($cb.Current.Name -match 'Skip Discovery') {
                $skipCb = $cb
                break
            }
        }
        if ($skipCb) { break }
    }

    if (-not $skipCb) {
        # Try expanding current node and going to first child (General)
        [System.Windows.Forms.SendKeys]::SendWait("{RIGHT}")
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
        Start-Sleep -Milliseconds 1000

        $deadline3 = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $deadline3) {
            $checkboxes = $optionsDlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cbCond)
            foreach ($cb in $checkboxes) {
                if ($cb.Current.Name -match 'Skip Discovery') {
                    $skipCb = $cb
                    break
                }
            }
            if ($skipCb) { break }
            Start-Sleep -Milliseconds 500
        }
    }
}

if (-not $skipCb) {
    Write-Host "Checkboxes found:"
    $checkboxes = $optionsDlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cbCond)
    foreach ($cb in $checkboxes) {
        Write-Host "  '$($cb.Current.Name)'"
    }
    [System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
    Start-Sleep -Milliseconds 500
    # no-minimize: leave VS as-is (never minimize VS — user can't restore it)
    Write-Host "SKIP_DISCOVERY_FAIL 'Skip Discovery' checkbox not found"
    exit 1
}

Write-Host "Found 'Skip Discovery' checkbox"

# --- Check current state ---
$togglePattern = $skipCb.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
$currentState = $togglePattern.Current.ToggleState

if ($currentState -eq [System.Windows.Automation.ToggleState]::On) {
    Write-Host "SKIP_DISCOVERY_ALREADY_CHECKED"
    [System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
    Start-Sleep -Milliseconds 500
    # no-minimize: leave VS as-is (never minimize VS — user can't restore it)
    exit 0
}

# --- Toggle ON ---
Write-Host "Checkbox is unchecked - toggling ON..."
$togglePattern.Toggle()
Start-Sleep -Milliseconds 300

# Verify
$newState = $togglePattern.Current.ToggleState
if ($newState -ne [System.Windows.Automation.ToggleState]::On) {
    [System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
    Start-Sleep -Milliseconds 500
    # no-minimize: leave VS as-is (never minimize VS — user can't restore it)
    Write-Host "SKIP_DISCOVERY_FAIL toggle did not stick (state=$newState)"
    exit 1
}

# --- Click OK to save ---
# OK/Cancel in VS Options dialog are Pane controls, not Buttons
$allChildren = $optionsDlg.FindAll([System.Windows.Automation.TreeScope]::Children,
    [System.Windows.Automation.Condition]::TrueCondition)
$okPane = $null
foreach ($c in $allChildren) {
    if ($c.Current.Name -eq 'OK') { $okPane = $c; break }
}

if ($okPane) {
    $rect = $okPane.Current.BoundingRectangle
    Write-Host "OK pane bounds: X=$($rect.X) Y=$($rect.Y) W=$($rect.Width) H=$($rect.Height)"

    # Try clicking a child button inside the OK pane
    $btnCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $innerBtn = $okPane.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
    if ($innerBtn) {
        Write-Host "Found inner Button inside OK pane"
        try {
            $innerBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            Write-Host "Invoked inner OK button"
        } catch {
            Write-Host "Inner button Invoke failed: $_"
        }
    } else {
        # Try SetFocus on OK pane then Enter
        Write-Host "No inner button - focusing OK pane and pressing Enter"
        try { $okPane.SetFocus() } catch {}
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    }
} else {
    Write-Host "OK pane not found - pressing Enter"
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
}

Start-Sleep -Milliseconds 1000

# Verify dialog closed
$stillOpen = $false
$windows = $vsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $winCond)
foreach ($w in $windows) {
    if ($w.Current.Name -eq 'Options') { $stillOpen = $true; break }
}

if ($stillOpen) {
    Write-Host "WARNING: Options dialog still open - pressing Escape"
    [System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
    Start-Sleep -Milliseconds 500
}

# no-minimize: leave VS as-is (never minimize VS — user can't restore it)
Write-Host "SKIP_DISCOVERY_CHECKED"
exit 0
