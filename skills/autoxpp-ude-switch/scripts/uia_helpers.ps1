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
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();

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
    # Use FromHandle for a reliable UIA tree -- PID-based RootElement.FindFirst
    # returns stale/cached trees during VS startup that miss menu items.
    # FromHandle always returns a fresh element bound to the actual window.
    param([int]$VsPid = 0)
    $p = if ($VsPid -ne 0) {
        Get-Process -Id $VsPid -ErrorAction SilentlyContinue
    } else {
        Get-VsProcess
    }
    if (-not $p -or $p.MainWindowHandle -eq [IntPtr]::Zero) { return $null }
    return [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
}

function Find-ChildWindow {
    # Find a dialog under the VS main window whose name contains any of the substrings.
    # Searches BOTH ControlType.Window (true modal dialogs like "Client assets download")
    # AND ControlType.Pane (Power Platform Tools embedded wizards like Login / URL / Select
    # Solution, which render as panes inside the VS tool window, not separate Windows).
    # Window is preferred when both match - try Window-type matches first, then Pane.
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

function Find-AnyWindow {
    # Find a Window matching any NameContains substring, searching BOTH the desktop's
    # top-level windows AND inside the VS process tree (Window or Pane). Power Platform
    # dialogs vary: the URL popup is a top-level window; the connect/select wizard is
    # "Configure Microsoft Power Platform Solution" which may be top-level or embedded.
    param([Parameter(Mandatory=$true)][string[]]$NameContains)
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $winCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Window)
    foreach ($w in $root.FindAll([System.Windows.Automation.TreeScope]::Children, $winCond)) {
        $nm = $w.Current.Name
        if (-not $nm) { continue }
        foreach ($needle in $NameContains) { if ($nm -like "*$needle*") { return $w } }
    }
    $vs = Get-VsProcess
    if ($vs) {
        $vsElem = Get-VsAutomationElement -VsPid $vs.Id
        if ($vsElem) {
            $w = Find-ChildWindow -Parent $vsElem -NameContains $NameContains
            if ($w) { return $w }
        }
    }
    return $null
}

function Wait-AnyWindow {
    param(
        [Parameter(Mandatory=$true)][string[]]$NameContains,
        [int]$TimeoutSeconds = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $w = Find-AnyWindow -NameContains $NameContains
        if ($w) { return $w }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

function Find-ByAutomationId {
    param(
        [Parameter(Mandatory=$true)]$Parent,
        [Parameter(Mandatory=$true)][string]$AutomationId
    )
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId)
    return $Parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

function Dismiss-UnexpectedDialog {
    # Safely close ANY modal dialog that is NOT a documented part of the UDE-switch
    # flow (e.g. "Please install Modeling SDK", update/error/notice popups) so an
    # undocumented dialog can't block the switch. We do NOT touch:
    #   - the flow's own dialogs (handled by their step scripts) - see $known,
    #   - the main VS window (matched by handle / menu bar),
    #   - tool windows or anything without a real dialog action button.
    # A window only qualifies as a dialog if it has an action button in $action
    # (window chrome Minimize/Maximize/Close never qualify). Returns count dismissed.
    $known = @(
        'Configure Microsoft Power Platform Solution','Configure Power Platform Solution',
        'Enter environment instance url','environment instance','Options',
        'Select Solution','Reconnect','Power Platform Tools','Connect to Dataverse',
        'Client assets','Pick an account','Sign in','choose an account',
        'Updates for Dynamics 365','All files were updated successfully')
    $action = @('OK','Ok','Continue','Cancel','Yes','No')   # qualifies a window as a dialog
    $prefer = @('Cancel','No','OK','Ok','Continue','Yes')    # least-destructive dismiss order (never chrome Close)

    $AE = [System.Windows.Automation.AutomationElement]
    $TS = [System.Windows.Automation.TreeScope]
    $CT = [System.Windows.Automation.ControlType]
    $winCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Window)
    $btnCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button)
    $mbCond  = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::MenuBar)

    $vs = Get-VsProcess
    $mainHwnd = if ($vs) { [int64]$vs.MainWindowHandle } else { 0 }
    $parents = @($AE::RootElement)
    if ($vs) { $vsElem = Get-VsAutomationElement -VsPid $vs.Id; if ($vsElem) { $parents += $vsElem } }

    $count = 0
    foreach ($parent in $parents) {
        foreach ($w in @($parent.FindAll($TS::Children, $winCond))) {
            $nm = "" + $w.Current.Name
            # 1) never touch the main VS window
            $hwnd = 0; try { $hwnd = [int64]$w.Current.NativeWindowHandle } catch {}
            if ($mainHwnd -ne 0 -and $hwnd -eq $mainHwnd) { continue }
            if ($w.FindFirst($TS::Descendants, $mbCond)) { continue }   # has a menu bar => main IDE window
            # 2) leave documented flow dialogs alone
            $skip = $false
            foreach ($k in $known) { if ($nm -like "*$k*") { $skip = $true; break } }
            if ($skip) { continue }
            # 3) qualify + pick a safe action button (else it is not an auto-dismissable dialog)
            $btns = @($w.FindAll($TS::Descendants, $btnCond))
            $target = $null
            foreach ($pref in $prefer) {
                foreach ($b in $btns) { if (("" + $b.Current.Name).Trim() -eq $pref) { $target = $b; break } }
                if ($target) { break }
            }
            if (-not $target) { continue }
            try {
                $target.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                Write-Host "  Dismissed undocumented dialog '$nm' (clicked '$($target.Current.Name)')"
                $count++; Start-Sleep -Milliseconds 600
            } catch {}
        }
    }
    return $count
}

function Test-VsStartWindow {
    # Reliable check for the VS "Get Started" Start Window (which has NO usable menu
    # bar). Do NOT rely on "a MenuBar element exists" - the VS shell exposes an (empty)
    # MenuBar in the UIA tree even on the Start Window, which gives false positives.
    # The Start Window is the Custom control class 'GetToCodeWorkflowView', and it
    # carries a "Continue without code" button.
    $vs = Get-VsProcess
    if (-not $vs) { return $false }
    $vsElem = Get-VsAutomationElement -VsPid $vs.Id
    if (-not $vsElem) { return $false }
    $AE = [System.Windows.Automation.AutomationElement]
    $TS = [System.Windows.Automation.TreeScope]
    $CT = [System.Windows.Automation.ControlType]
    $cust = New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, 'GetToCodeWorkflowView')
    if ($vsElem.FindFirst($TS::Descendants, $cust)) { return $true }
    $btnCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button)
    foreach ($b in @($vsElem.FindAll($TS::Descendants, $btnCond))) {
        if (("" + $b.Current.Name) -like '*Continue without code*') { return $true }
    }
    return $false
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

function Bring-SelfToFront {
    # Return view to the agent's own terminal WITHOUT minimizing VS. Minimizing VS
    # left the user unable to restore the window, so instead of hiding VS we raise
    # our console window over it. Best-effort: depends on the console window being
    # attached to the host terminal.
    $h = [UdeSwitchUiaNative]::GetConsoleWindow()
    if ($h -ne [IntPtr]::Zero) {
        [UdeSwitchUiaNative]::ShowWindow($h, [UdeSwitchUiaNative]::SW_RESTORE) | Out-Null
        [UdeSwitchUiaNative]::SetForegroundWindow($h) | Out-Null
    }
}
# Back-compat: callers say Minimize-Vs, but we no longer minimize VS - we raise the terminal.
Set-Alias Minimize-Vs Bring-SelfToFront

function Show-Vs {
    $p = Get-VsProcess
    if ($p) {
        [UdeSwitchUiaNative]::RestoreWindow($p.MainWindowHandle) | Out-Null
        [UdeSwitchUiaNative]::ForceForeground($p.MainWindowHandle)
    }
}

function Dismiss-D365UpdateDialog {
    # Detect and dismiss the "Updates for Dynamics 365 Finance and Operations"
    # dialog that sometimes appears when clicking Extensions > Dynamics 365.
    # The dialog says "All files were updated successfully" with an OK button.
    # Returns $true if a dialog was found and dismissed, $false otherwise.
    $AE = [System.Windows.Automation.AutomationElement]
    $TS = [System.Windows.Automation.TreeScope]
    $CT = [System.Windows.Automation.ControlType]

    $winCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Window)
    $btnCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button)

    $needles = @('Updates for Dynamics 365', 'All files were updated successfully')

    # Search top-level windows
    foreach ($w in @($AE::RootElement.FindAll($TS::Children, $winCond))) {
        $nm = "" + $w.Current.Name
        $matched = $false
        foreach ($needle in $needles) {
            if ($nm -like "*$needle*") { $matched = $true; break }
        }
        if (-not $matched) { continue }

        # Found the update dialog -- click OK
        foreach ($b in @($w.FindAll($TS::Descendants, $btnCond))) {
            if (("" + $b.Current.Name).Trim() -eq 'OK') {
                try {
                    $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                } catch {
                    $rect = $b.Current.BoundingRectangle
                    [UdeSwitchUiaNative]::ClickAt([int]($rect.X + $rect.Width / 2), [int]($rect.Y + $rect.Height / 2))
                }
                Write-Host "  D365_UPDATE_DIALOG_DISMISSED (clicked OK)"
                Start-Sleep -Milliseconds 800
                return $true
            }
        }
    }

    # Also search inside VS process tree (dialog may be a child window)
    $vs = Get-VsProcess
    if ($vs) {
        $vsElem = Get-VsAutomationElement -VsPid $vs.Id
        if ($vsElem) {
            foreach ($w in @($vsElem.FindAll($TS::Descendants, $winCond))) {
                $nm = "" + $w.Current.Name
                $matched = $false
                foreach ($needle in $needles) {
                    if ($nm -like "*$needle*") { $matched = $true; break }
                }
                if (-not $matched) { continue }
                foreach ($b in @($w.FindAll($TS::Descendants, $btnCond))) {
                    if (("" + $b.Current.Name).Trim() -eq 'OK') {
                        try {
                            $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                        } catch {
                            $rect = $b.Current.BoundingRectangle
                            [UdeSwitchUiaNative]::ClickAt([int]($rect.X + $rect.Width / 2), [int]($rect.Y + $rect.Height / 2))
                        }
                        Write-Host "  D365_UPDATE_DIALOG_DISMISSED (clicked OK)"
                        Start-Sleep -Milliseconds 800
                        return $true
                    }
                }
            }
        }
    }

    return $false
}
