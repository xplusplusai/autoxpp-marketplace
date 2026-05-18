# uia_helpers.ps1 - shared UIA primitives for the UDE switch skill.
# Dot-sourced by each dialog handler.

Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
Add-Type -AssemblyName UIAutomationTypes  -ErrorAction SilentlyContinue

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public class UdeSwitchUiaNative {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();

    public const int SW_SHOWMINIMIZED = 2;
    public const int SW_RESTORE = 9;

    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        Thread.Sleep(100);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }

    public static void ForceForeground(IntPtr hWnd) {
        ShowWindow(hWnd, SW_RESTORE);
        Thread.Sleep(200);
        keybd_event(0xA4, 0, 0, UIntPtr.Zero);
        SetForegroundWindow(hWnd);
        keybd_event(0xA4, 0, 2, UIntPtr.Zero);
    }

    public static void MinimizeWindow(IntPtr hWnd) { ShowWindow(hWnd, SW_SHOWMINIMIZED); }
    public static void RestoreWindow(IntPtr hWnd)  { ShowWindow(hWnd, SW_RESTORE); }
}
"@ -ErrorAction SilentlyContinue

function Get-VsProcess {
    Get-Process devenv -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
        Select-Object -First 1
}

function Get-VsAutomationElement {
    param([int]$VsPid = 0)
    if ($VsPid -eq 0) {
        $p = Get-VsProcess
        if (-not $p) { return $null }
        $VsPid = $p.Id
    }
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $pidCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $VsPid)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $pidCond)
}

function Find-ChildWindow {
    # Find a dialog under the VS main window whose name contains any of the substrings.
    # Searches BOTH ControlType.Window (true modal dialogs like "Client assets download")
    # AND ControlType.Pane (Power Platform Tools embedded wizards like Login / URL / Select
    # Solution, which render as panes inside the VS tool window, not separate Windows).
    # Window is preferred when both match — try Window-type matches first, then Pane.
    param(
        [Parameter(Mandatory=$true)]$Parent,
        [Parameter(Mandatory=$true)][string[]]$NameContains
    )
    foreach ($ctl in @([System.Windows.Automation.ControlType]::Window,
                        [System.Windows.Automation.ControlType]::Pane)) {
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ctl)
        $children = $Parent.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        foreach ($w in $children) {
            $nm = $w.Current.Name
            if (-not $nm) { continue }
            foreach ($needle in $NameContains) {
                if ($nm -like "*$needle*") { return $w }
            }
        }
    }
    return $null
}

function Wait-ForChildWindow {
    param(
        [Parameter(Mandatory=$true)]$Parent,
        [Parameter(Mandatory=$true)][string[]]$NameContains,
        [int]$TimeoutSeconds = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $w = Find-ChildWindow -Parent $Parent -NameContains $NameContains
        if ($w) { return $w }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

function Find-ButtonByName {
    param(
        [Parameter(Mandatory=$true)]$Parent,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $btnCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $buttons = $Parent.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
    foreach ($b in $buttons) {
        if ($b.Current.Name.Trim() -eq $Name) { return $b }
    }
    return $null
}

function Invoke-Button {
    # Try UIA InvokePattern first; fall back to coordinate click via ForceForeground.
    param(
        [Parameter(Mandatory=$true)]$Button,
        [IntPtr]$VsHwnd = [IntPtr]::Zero
    )
    try {
        $p = $Button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $p.Invoke()
        return "INVOKE_OK"
    } catch {
        $rect = $Button.Current.BoundingRectangle
        $cx = [int]($rect.X + $rect.Width / 2)
        $cy = [int]($rect.Y + $rect.Height / 2)
        if ($VsHwnd -ne [IntPtr]::Zero) {
            [UdeSwitchUiaNative]::ForceForeground($VsHwnd)
            Start-Sleep -Milliseconds 300
        }
        [UdeSwitchUiaNative]::ClickAt($cx, $cy)
        return "COORD_CLICK at ($cx,$cy)"
    }
}

function Set-EditText {
    # Set value on an Edit control via ValuePattern; fall back to keyboard if not supported.
    param(
        [Parameter(Mandatory=$true)]$Edit,
        [Parameter(Mandatory=$true)][string]$Text
    )
    try {
        $vp = $Edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $vp.SetValue($Text)
        return "VALUE_SET"
    } catch {
        $Edit.SetFocus()
        Start-Sleep -Milliseconds 100
        [System.Windows.Forms.SendKeys]::SendWait($Text) 2>$null
        return "SENDKEYS"
    }
}

function Find-EditControl {
    param(
        [Parameter(Mandatory=$true)]$Parent,
        [int]$Index = 0
    )
    $editCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    $edits = @($Parent.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCond))
    if ($edits.Count -eq 0) { return $null }
    if ($Index -ge $edits.Count) { return $null }
    return $edits[$Index]
}

function Minimize-Vs {
    $p = Get-VsProcess
    if ($p) { [UdeSwitchUiaNative]::MinimizeWindow($p.MainWindowHandle) | Out-Null }
}

function Show-Vs {
    $p = Get-VsProcess
    if ($p) {
        [UdeSwitchUiaNative]::RestoreWindow($p.MainWindowHandle) | Out-Null
        [UdeSwitchUiaNative]::ForceForeground($p.MainWindowHandle)
    }
}
