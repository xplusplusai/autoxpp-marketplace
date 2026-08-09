# ensure_skip_discovery.ps1
# Opens Tools > Options > Power Platform Tools > General and ensures
# "Skip Discovery when connecting to Dataverse" is checked.
# Uses UIA ValuePattern + SendMessage for fully headless operation
# (works when RDP is minimized or disconnected).
#
# Emits:
#   SKIP_DISCOVERY_ALREADY_CHECKED
#   SKIP_DISCOVERY_CHECKED (was unchecked, now checked)
#   SKIP_DISCOVERY_FAIL <reason>

param(
    [int]$TimeoutSeconds = 30,
    [int]$MenuTimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
Add-Type -AssemblyName UIAutomationTypes  -ErrorAction SilentlyContinue

. "$PSScriptRoot\uia_helpers.ps1"

# --- SendMessage P/Invoke for headless keyboard input to HWND ---
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class UdeSkipDiscoveryMsg {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const uint WM_KEYDOWN = 0x0100;
    public const uint WM_KEYUP   = 0x0101;
    public const uint WM_COMMAND = 0x0111;
    public const int  VK_RETURN  = 0x0D;
    public const int  VK_DOWN    = 0x28;
    public const int  IDOK       = 1;
    public const int  IDCANCEL   = 2;
}
"@ -ErrorAction SilentlyContinue

# --- DTE helper script content (written to temp and run via Start-Process) ---
$script:DteHelperScript = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("00000016-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IOleMessageFilter {
    [PreserveSig] int HandleInComingCall(int a, IntPtr b, int c, IntPtr d);
    [PreserveSig] int RetryRejectedCall(IntPtr a, int b, int c);
    [PreserveSig] int MessagePending(IntPtr a, int b, int c);
}
public class MF : IOleMessageFilter {
    [DllImport("ole32.dll")] static extern int CoRegisterMessageFilter(IOleMessageFilter f, out IOleMessageFilter old);
    public static void Register() { IOleMessageFilter old; CoRegisterMessageFilter(new MF(), out old); }
    public int HandleInComingCall(int a, IntPtr b, int c, IntPtr d) { return 0; }
    public int RetryRejectedCall(IntPtr a, int b, int c) { return c == 2 ? 300 : -1; }
    public int MessagePending(IntPtr a, int b, int c) { return 2; }
}
"@
[MF]::Register()
$dte = [System.Runtime.InteropServices.Marshal]::GetActiveObject("VisualStudio.DTE.17.0")
$dte.ExecuteCommand("Tools.Options")
'@

# --- Track DTE helper process for cleanup ---
$dteProc = $null

# --- Get VS process ---
$vs = Get-VsProcess
if (-not $vs) {
    Write-Host "SKIP_DISCOVERY_FAIL VS not running"
    exit 1
}

$vsElem = Get-VsAutomationElement -VsPid $vs.Id
if (-not $vsElem) {
    Write-Host "SKIP_DISCOVERY_FAIL cannot get VS automation element"
    exit 1
}

$AE  = [System.Windows.Automation.AutomationElement]
$TS  = [System.Windows.Automation.TreeScope]
$CT  = [System.Windows.Automation.ControlType]

$winCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Window)
$cbCond  = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::CheckBox)
$menuItemCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::MenuItem)

# Script-scope ref to search box ValuePattern -- used to clear search before OK/Cancel lookups
$script:searchVP = $null

# --- Close any stale Options dialog via WM_COMMAND ---
$windows = $vsElem.FindAll($TS::Descendants, $winCond)
foreach ($w in $windows) {
    if ($w.Current.Name -eq 'Options') {
        Write-Host "Closing stale Options dialog..."
        $h = $w.Current.NativeWindowHandle
        if ($h -and $h -ne 0) {
            [UdeSkipDiscoveryMsg]::SendMessage([IntPtr]$h, [UdeSkipDiscoveryMsg]::WM_COMMAND, [IntPtr][UdeSkipDiscoveryMsg]::IDCANCEL, [IntPtr]::Zero) | Out-Null
        }
        Start-Sleep -Milliseconds 1000
        break
    }
}

# --- Pre-flight: dismiss unexpected dialogs, verify not at Start Window ---
$null = Dismiss-UnexpectedDialog
if (Test-VsStartWindow) {
    Write-Host "SKIP_DISCOVERY_FAIL VS is at the Start Window (no menu); run dismiss_start_window.ps1 first."
    exit 1
}

# --- Open Options dialog: retry loop with UIA-first + DTE COM fallback ---
Show-Vs
Start-Sleep -Milliseconds 500

$optionsDlg = $null
$menuDeadline = (Get-Date).AddSeconds($MenuTimeoutSeconds)
$attempt = 0

while ((Get-Date) -lt $menuDeadline -and -not $optionsDlg) {
    $attempt++
    $remaining = [math]::Round(($menuDeadline - (Get-Date)).TotalSeconds)
    $elapsed = [math]::Round($MenuTimeoutSeconds - $remaining)
    Write-Host "Opening Tools > Options (attempt $attempt, ${elapsed}s elapsed, ${remaining}s remaining)..."

    $vsElem = Get-VsAutomationElement -VsPid $vs.Id
    if (-not $vsElem) {
        Write-Host "  Cannot get VS automation element -- extensions may still be loading, retrying..."
        Start-Sleep -Seconds 15; continue
    }

    # --- Strategy A: UIA menu expansion ---
    Write-Host "  Trying UIA menu expansion..."
    $items = $vsElem.FindAll($TS::Descendants, $menuItemCond)
    $toolsMenu = $null
    foreach ($mi in $items) {
        if ($mi.Current.Name -eq 'Tools') { $toolsMenu = $mi; break }
    }

    if (-not $toolsMenu) {
        Write-Host "  Tools menu not found -- VS menu bar may still be loading, retrying..."
        Start-Sleep -Seconds 15; continue
    }

    try {
        $toolsMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        Start-Sleep -Milliseconds 1500

        $menuItems = $toolsMenu.FindAll($TS::Descendants, $menuItemCond)
        $optionsItem = $null
        foreach ($mi in $menuItems) {
            $n = $mi.Current.Name
            if ($n -eq 'Options' -or $n -eq 'Options...') { $optionsItem = $mi; break }
        }

        if ($optionsItem) {
            Write-Host "  Found Options via UIA menu"
            $optionsItem.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            $dlgDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-Date) -lt $dlgDeadline) {
                $vsElem = Get-VsAutomationElement -VsPid $vs.Id
                $windows = $vsElem.FindAll($TS::Descendants, $winCond)
                foreach ($w in $windows) {
                    if ($w.Current.Name -eq 'Options') { $optionsDlg = $w; break }
                }
                if ($optionsDlg) { break }
                Start-Sleep -Milliseconds 500
            }
        } else {
            Write-Host "  Options not found in expanded menu (no foreground?)"
            try { $toolsMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
        }
    } catch {
        Write-Host "  UIA menu expansion failed: $_"
    }

    # --- Strategy B: DTE COM via separate process (works without foreground) ---
    if (-not $optionsDlg) {
        Write-Host "  Falling back to DTE COM (separate process)..."

        $helperPath = Join-Path $env:TEMP "ude_dte_open_options.ps1"
        Set-Content -Path $helperPath -Value $script:DteHelperScript -Encoding UTF8

        $dteProc = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-ExecutionPolicy Bypass -File `"$helperPath`"" `
            -PassThru -WindowStyle Hidden

        $dteDeadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $dteDeadline) {
            $vsElem = Get-VsAutomationElement -VsPid $vs.Id
            if ($vsElem) {
                $windows = $vsElem.FindAll($TS::Descendants, $winCond)
                foreach ($w in $windows) {
                    if ($w.Current.Name -eq 'Options') { $optionsDlg = $w; break }
                }
            }
            if ($optionsDlg) { break }
            Start-Sleep -Milliseconds 500
        }

        if (-not $optionsDlg -and $dteProc -and -not $dteProc.HasExited) {
            Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue
            $dteProc = $null
        }
    }

    if (-not $optionsDlg) {
        Write-Host "  Neither UIA nor DTE succeeded this attempt -- retrying..."
        Start-Sleep -Seconds 8
    }
}

if (-not $optionsDlg) {
    Write-Host "SKIP_DISCOVERY_FAIL Options dialog did not appear after $attempt attempts over ${MenuTimeoutSeconds}s"
    exit 1
}
Write-Host "Options dialog found"

# --- Navigate to Power Platform Tools page (fully headless) ---
# Step 1: Find search box by AutomationId and set search text via ValuePattern
$skipCb = $null
$searchBoxCond = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, "PART_SearchBox")
$searchBox = $optionsDlg.FindFirst($TS::Descendants, $searchBoxCond)

if ($searchBox) {
    Write-Host "Using search box to filter to 'Power Platform' (ValuePattern)..."
    try {
        $vp = $searchBox.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $script:searchVP = $vp

        # Clear existing search first
        $vp.SetValue("")
        Start-Sleep -Milliseconds 300

        # Set search text -- ValuePattern.SetValue is programmatic and works headless
        $vp.SetValue("Power Platform")
        $readBack = $vp.Current.Value
        Write-Host "  Set search text: '$readBack'"
        Start-Sleep -Seconds 2

        # Check if search found results
        $liveTextCond = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, "PART_LiveSearchTextBlock")
        $liveText = $optionsDlg.FindFirst($TS::Descendants, $liveTextCond)
        if ($liveText) {
            Write-Host "  Search status: '$($liveText.Current.Name)'"
        }

        # Step 2: Navigate to first result via SendMessage to the Win32 TreeView
        # The Options tree is a SysTreeView32 native control. UIA can't enumerate
        # its virtualized items, but SendMessage targets the HWND directly and works
        # regardless of foreground/rendering state.
        $treeViewCond = New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, "SysTreeView32")
        $treeView = $optionsDlg.FindFirst($TS::Descendants, $treeViewCond)

        if ($treeView -and $treeView.Current.NativeWindowHandle -ne 0) {
            $treeHwnd = [IntPtr]$treeView.Current.NativeWindowHandle
            Write-Host "  Selecting first search result via SendMessage (TreeView HWND: $treeHwnd)..."

            # Down arrow selects the first filtered tree item and loads its page
            [UdeSkipDiscoveryMsg]::SendMessage($treeHwnd, [UdeSkipDiscoveryMsg]::WM_KEYDOWN, [IntPtr][UdeSkipDiscoveryMsg]::VK_DOWN, [IntPtr]::Zero) | Out-Null
            [UdeSkipDiscoveryMsg]::SendMessage($treeHwnd, [UdeSkipDiscoveryMsg]::WM_KEYUP, [IntPtr][UdeSkipDiscoveryMsg]::VK_DOWN, [IntPtr]::Zero) | Out-Null
            Start-Sleep -Seconds 2

            # Look for the Skip Discovery checkbox on the now-loaded page
            $deadline2 = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $deadline2) {
                $checkboxes = $optionsDlg.FindAll($TS::Descendants, $cbCond)
                foreach ($cb in $checkboxes) {
                    if ($cb.Current.Name -match 'Skip Discovery') { $skipCb = $cb; break }
                }
                if ($skipCb) { break }
                Start-Sleep -Milliseconds 500
            }
            if ($skipCb) { Write-Host "  Found checkbox via search + SendMessage navigation" }
        } else {
            Write-Host "  TreeView not found or has no HWND"
        }
    } catch {
        Write-Host "  Search approach failed: $_"
    }
} else {
    Write-Host "  Search box (PART_SearchBox) not found in Options dialog"
}

# --- Fallback: brute-force scan all checkboxes (in case page already loaded) ---
if (-not $skipCb) {
    Write-Host "Scanning all checkboxes in Options dialog..."
    $checkboxes = $optionsDlg.FindAll($TS::Descendants, $cbCond)
    foreach ($cb in $checkboxes) {
        if ($cb.Current.Name -match 'Skip Discovery') { $skipCb = $cb; break }
    }
    if ($skipCb) { Write-Host "  Found checkbox via brute-force scan" }
}

if (-not $skipCb) {
    Write-Host "Visible checkboxes:"
    $checkboxes = $optionsDlg.FindAll($TS::Descendants, $cbCond)
    foreach ($cb in $checkboxes) { Write-Host "  '$($cb.Current.Name)'" }
    # Clean up DTE helper
    if ($dteProc -and -not $dteProc.HasExited) {
        $null = $dteProc.WaitForExit(5000)
        if (-not $dteProc.HasExited) { Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "SKIP_DISCOVERY_FAIL 'Skip Discovery' checkbox not found"
    exit 1
}

Write-Host "Found 'Skip Discovery' checkbox"

# --- Check current state ---
$togglePattern = $skipCb.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
$currentState = $togglePattern.Current.ToggleState

if ($currentState -eq [System.Windows.Automation.ToggleState]::On) {
    Write-Host "SKIP_DISCOVERY_ALREADY_CHECKED"
    # Close dialog via WM_COMMAND IDCANCEL (reliable for #32770 dialogs, works headless)
    $dlgHwnd = $optionsDlg.Current.NativeWindowHandle
    if ($dlgHwnd -and $dlgHwnd -ne 0) {
        $h = [IntPtr]$dlgHwnd
        [UdeSkipDiscoveryMsg]::SendMessage($h, [UdeSkipDiscoveryMsg]::WM_COMMAND, [IntPtr][UdeSkipDiscoveryMsg]::IDCANCEL, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 500
    }
    # Verify
    $vsElem = Get-VsAutomationElement -VsPid $vs.Id
    if ($vsElem) {
        $windows = $vsElem.FindAll($TS::Descendants, $winCond)
        foreach ($w in $windows) {
            if ($w.Current.Name -eq 'Options') {
                Write-Host "  WARNING: Options dialog still open after WM_COMMAND IDCANCEL"
                break
            }
        }
    }
    if ($dteProc -and -not $dteProc.HasExited) {
        $null = $dteProc.WaitForExit(5000)
        if (-not $dteProc.HasExited) { Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue }
    }
    exit 0
}

# --- Toggle ON ---
Write-Host "Checkbox is unchecked - toggling ON..."
$togglePattern.Toggle()
Start-Sleep -Milliseconds 300

$newState = $togglePattern.Current.ToggleState
if ($newState -ne [System.Windows.Automation.ToggleState]::On) {
    # Close dialog via WM_COMMAND IDCANCEL
    $dlgHwnd = $optionsDlg.Current.NativeWindowHandle
    if ($dlgHwnd -and $dlgHwnd -ne 0) {
        [UdeSkipDiscoveryMsg]::SendMessage([IntPtr]$dlgHwnd, [UdeSkipDiscoveryMsg]::WM_COMMAND, [IntPtr][UdeSkipDiscoveryMsg]::IDCANCEL, [IntPtr]::Zero) | Out-Null
    }
    if ($dteProc -and -not $dteProc.HasExited) {
        $null = $dteProc.WaitForExit(5000)
        if (-not $dteProc.HasExited) { Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "SKIP_DISCOVERY_FAIL toggle did not stick (state=$newState)"
    exit 1
}

# --- Click OK to save via WM_COMMAND IDOK ---
$dlgHwnd = $optionsDlg.Current.NativeWindowHandle
if ($dlgHwnd -and $dlgHwnd -ne 0) {
    $h = [IntPtr]$dlgHwnd
    [UdeSkipDiscoveryMsg]::SendMessage($h, [UdeSkipDiscoveryMsg]::WM_COMMAND, [IntPtr][UdeSkipDiscoveryMsg]::IDOK, [IntPtr]::Zero) | Out-Null
    Write-Host "OK sent via WM_COMMAND IDOK"
} else {
    if ($dteProc -and -not $dteProc.HasExited) {
        $null = $dteProc.WaitForExit(5000)
        if (-not $dteProc.HasExited) { Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "SKIP_DISCOVERY_FAIL dialog has no HWND for OK"
    exit 1
}

Start-Sleep -Milliseconds 1000

# Verify dialog closed
$stillOpen = $false
$vsElem = Get-VsAutomationElement -VsPid $vs.Id
if ($vsElem) {
    $windows = $vsElem.FindAll($TS::Descendants, $winCond)
    foreach ($w in $windows) {
        if ($w.Current.Name -eq 'Options') { $stillOpen = $true; break }
    }
}
if ($stillOpen) {
    Write-Host "WARNING: Options dialog still open after OK - sending IDCANCEL"
    [UdeSkipDiscoveryMsg]::SendMessage([IntPtr]$dlgHwnd, [UdeSkipDiscoveryMsg]::WM_COMMAND, [IntPtr][UdeSkipDiscoveryMsg]::IDCANCEL, [IntPtr]::Zero) | Out-Null
}

# Clean up DTE helper process
if ($dteProc -and -not $dteProc.HasExited) {
    $null = $dteProc.WaitForExit(10000)
    if (-not $dteProc.HasExited) {
        Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue
    }
}

# no-minimize: leave VS as-is (never minimize VS - user can't restore it)
Write-Host "SKIP_DISCOVERY_CHECKED"
exit 0
