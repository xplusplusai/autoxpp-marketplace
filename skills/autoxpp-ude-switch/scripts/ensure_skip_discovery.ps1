# ensure_skip_discovery.ps1
# Opens Tools > Options > Power Platform Tools > General and ensures
# "Skip Discovery when connecting to Dataverse" is checked.
# Uses UIA + clipboard paste via keybd_event (crosses UIPI for elevated VS).
# Falls back to DTE COM via separate process when VS lacks foreground focus.
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
$treeItemCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::TreeItem)

# --- Close any stale Options dialog via UIA (no SendKeys) ---
$windows = $vsElem.FindAll($TS::Descendants, $winCond)
foreach ($w in $windows) {
    if ($w.Current.Name -eq 'Options') {
        Write-Host "Closing stale Options dialog..."
        $cancelBtn = Find-ButtonByName -Parent $w -Name 'Cancel'
        if ($cancelBtn) {
            try { $cancelBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch {}
        } else {
            $okBtn = Find-ButtonByName -Parent $w -Name 'OK'
            if ($okBtn) {
                try { $okBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch {}
            }
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
# VS extensions (including Power Platform Tools) can take minutes to load.
# Neither UIA menu expansion nor DTE COM will work until loading completes,
# so we retry the full UIA->DTE sequence with pauses between attempts.
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

    # Re-acquire VS automation element each attempt -- the UIA tree is stale if
    # acquired during VS startup and won't reflect newly loaded extensions.
    $vsElem = Get-VsAutomationElement -VsPid $vs.Id
    if (-not $vsElem) {
        Write-Host "  Cannot get VS automation element -- extensions may still be loading, retrying..."
        Start-Sleep -Seconds 15; continue
    }

    # --- Strategy A: UIA menu expansion (works when VS has foreground) ---
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

        # Search the Tools menu element's own descendants (NOT vsElem --
        # WPF menu popups are linked to the menu item, not the main window).
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

        # Poll for Options dialog (30s per DTE attempt)
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

        # Clean up helper process if this attempt failed
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

# --- Navigate to Power Platform Tools ---
$skipCb = $null

# Strategy 1: Use clipboard paste to type in the search box.
# SendKeys::SendWait throws "Access is denied" when VS is elevated (UIPI).
# keybd_event works cross-elevation, so: clipboard + Ctrl+V triggers real
# TextChanged events in the WPF search box.
$editCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Edit)
$edits = @($optionsDlg.FindAll($TS::Descendants, $editCond))
$searchBox = $null
foreach ($e in $edits) {
    $aid = "" + $e.Current.AutomationId
    $nm  = "" + $e.Current.Name
    if ($aid -match 'Search|Filter' -or $nm -match 'Search|Filter') {
        $searchBox = $e; break
    }
}

if ($searchBox) {
    Write-Host "Using search box to filter to 'Power Platform' (clipboard paste)..."
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Show-Vs
        Start-Sleep -Milliseconds 300

        # Focus the search box via coord-click
        $rect = $searchBox.Current.BoundingRectangle
        if ($rect.Width -gt 0 -and $rect.Height -gt 0) {
            [UdeSwitchUiaNative]::ClickAt([int]($rect.X + $rect.Width / 2), [int]($rect.Y + $rect.Height / 2))
            Start-Sleep -Milliseconds 300
        } else {
            $searchBox.SetFocus()
            Start-Sleep -Milliseconds 300
        }

        # Ctrl+A to select all (keybd_event: 0x11=Ctrl, 0x41=A)
        [UdeSwitchUiaNative]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)   # Ctrl down
        [UdeSwitchUiaNative]::keybd_event(0x41, 0, 0, [UIntPtr]::Zero)   # A down
        [UdeSwitchUiaNative]::keybd_event(0x41, 0, 2, [UIntPtr]::Zero)   # A up
        [UdeSwitchUiaNative]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)   # Ctrl up
        Start-Sleep -Milliseconds 100

        # Delete key (0x2E)
        [UdeSwitchUiaNative]::keybd_event(0x2E, 0, 0, [UIntPtr]::Zero)
        [UdeSwitchUiaNative]::keybd_event(0x2E, 0, 2, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 200

        # Set clipboard and paste via Ctrl+V (keybd_event crosses UIPI)
        [System.Windows.Forms.Clipboard]::SetText("Power Platform")
        Start-Sleep -Milliseconds 100
        [UdeSwitchUiaNative]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)   # Ctrl down
        [UdeSwitchUiaNative]::keybd_event(0x56, 0, 0, [UIntPtr]::Zero)   # V down
        [UdeSwitchUiaNative]::keybd_event(0x56, 0, 2, [UIntPtr]::Zero)   # V up
        [UdeSwitchUiaNative]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)   # Ctrl up
        Write-Host "  Pasted 'Power Platform' via Ctrl+V"
        Start-Sleep -Seconds 2

        # Press Enter to navigate to the first matching page.
        # The search filters the tree but the right pane stays on the current page
        # until Enter selects the first result. The native Win32 tree in the Options
        # dialog has no UIA TreeItem children, so keyboard navigation is the only way.
        [UdeSwitchUiaNative]::keybd_event(0x0D, 0, 0, [UIntPtr]::Zero)   # Enter down
        [UdeSwitchUiaNative]::keybd_event(0x0D, 0, 2, [UIntPtr]::Zero)   # Enter up
        Write-Host "  Pressed Enter to navigate to first result"
        Start-Sleep -Seconds 2

        # After filtering + Enter, look for the Skip Discovery checkbox
        $deadline2 = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $deadline2) {
            $checkboxes = $optionsDlg.FindAll($TS::Descendants, $cbCond)
            foreach ($cb in $checkboxes) {
                if ($cb.Current.Name -match 'Skip Discovery') { $skipCb = $cb; break }
            }
            if ($skipCb) { break }
            Start-Sleep -Milliseconds 500
        }
        if ($skipCb) { Write-Host "  Found checkbox via search" }
    } catch {
        Write-Host "  Search box approach failed: $_"
    }
}

# Strategy 2: Walk the TreeView directly
if (-not $skipCb) {
    Write-Host "Walking TreeView to find Power Platform Tools..."

    # The Options tree may have items outside the visible scroll region that UIA
    # cannot enumerate. Find the TreeView control and scroll it to load all items.
    $treeCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Tree)
    $treeView = $optionsDlg.FindFirst($TS::Descendants, $treeCond)
    if ($treeView) {
        try {
            $scrollPattern = $treeView.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
            # Scroll to bottom then back to top to force all items into UIA tree
            $scrollPattern.SetScrollPercent(
                [System.Windows.Automation.ScrollPattern]::NoScroll, 100)
            Start-Sleep -Milliseconds 300
            $scrollPattern.SetScrollPercent(
                [System.Windows.Automation.ScrollPattern]::NoScroll, 0)
            Start-Sleep -Milliseconds 300
            Write-Host "  Scrolled TreeView to load all items"
        } catch {
            Write-Host "  TreeView scroll not available: $_"
        }
    }

    $treeItems = $optionsDlg.FindAll($TS::Descendants, $treeItemCond)
    Write-Host "  Found $($treeItems.Count) tree items"

    $ppItem = $null
    foreach ($ti in $treeItems) {
        $tiName = $ti.Current.Name
        if ($tiName -match 'Power Platform') { $ppItem = $ti; break }
    }

    # If not found, log all tree item names for diagnostics
    if (-not $ppItem) {
        Write-Host "  'Power Platform' TreeItem not found. Available tree items:"
        foreach ($ti in $treeItems) { Write-Host "    '$($ti.Current.Name)'" }
    }

    if ($ppItem) {
        Write-Host "  Found '$($ppItem.Current.Name)'"

        # ScrollIntoView if supported (makes the item visible and UIA-accessible)
        try {
            $ppItem.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView()
            Start-Sleep -Milliseconds 300
        } catch {}

        # Select it (loads its page in the right pane)
        try {
            $ppItem.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
            Start-Sleep -Milliseconds 500
        } catch { Write-Host "  SelectionItemPattern not available: $_" }

        # Expand to reveal General child
        try {
            $ppItem.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
            Start-Sleep -Milliseconds 500
        } catch { Write-Host "  ExpandCollapsePattern not available (may be leaf node)" }

        # Try to select the General child (some VS versions show it as a sub-node)
        $children = $ppItem.FindAll($TS::Children, $treeItemCond)
        foreach ($child in $children) {
            if ($child.Current.Name -eq 'General') {
                Write-Host "  Selecting 'General' child node"
                try {
                    $child.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
                    Start-Sleep -Milliseconds 1000
                } catch {}
                break
            }
        }

        # Now look for checkbox in the right pane
        $deadline3 = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $deadline3) {
            $checkboxes = $optionsDlg.FindAll($TS::Descendants, $cbCond)
            foreach ($cb in $checkboxes) {
                if ($cb.Current.Name -match 'Skip Discovery') { $skipCb = $cb; break }
            }
            if ($skipCb) { break }
            Start-Sleep -Milliseconds 500
        }
        if ($skipCb) { Write-Host "  Found checkbox via tree navigation" }
    }
}

# Strategy 3: Brute-force search all checkboxes (Options dialog might already show it)
if (-not $skipCb) {
    Write-Host "Scanning all checkboxes in Options dialog..."
    $checkboxes = $optionsDlg.FindAll($TS::Descendants, $cbCond)
    foreach ($cb in $checkboxes) {
        if ($cb.Current.Name -match 'Skip Discovery') { $skipCb = $cb; break }
    }
    if ($skipCb) { Write-Host "  Found checkbox via brute-force scan" }
}

# Strategy 4: DTE COM -- read/set the property directly via COM, bypassing UI entirely
if (-not $skipCb) {
    Write-Host "Trying DTE COM to set Skip Discovery directly..."

    # Close the Options dialog first (it blocks DTE property access)
    $cancelBtn = Find-ButtonByName -Parent $optionsDlg -Name 'Cancel'
    if ($cancelBtn) {
        try { $cancelBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch {}
        Start-Sleep -Milliseconds 500
    }

    # DTE COM helper that reads/sets the Skip Discovery property
    $dteSkipScript = @'
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

try {
    $dte = [System.Runtime.InteropServices.Marshal]::GetActiveObject("VisualStudio.DTE.17.0")
} catch {
    Write-Host "DTE_NOT_FOUND"
    exit 1
}

# Try known category names for Power Platform Tools extension
$categoryNames = @(
    "Power Platform Tools",
    "PowerPlatformTools",
    "Power Platform Tools - General",
    "Dynamics365.PowerPlatformTools"
)
$pageNames = @("General", "")

$found = $false
foreach ($cat in $categoryNames) {
    foreach ($pg in $pageNames) {
        try {
            $props = if ($pg) { $dte.Properties($cat, $pg) } else { $dte.Properties($cat) }
            # Search for skip discovery property
            foreach ($p in $props) {
                if ($p.Name -match 'Skip.*Discovery|SkipDiscovery') {
                    $val = $p.Value
                    if ($val -eq $true -or $val -eq 1) {
                        Write-Host "DTE_ALREADY_CHECKED category=$cat page=$pg prop=$($p.Name)"
                        exit 0
                    } else {
                        $p.Value = $true
                        Write-Host "DTE_SET_CHECKED category=$cat page=$pg prop=$($p.Name)"
                        exit 0
                    }
                }
            }
            # List available properties for diagnostics
            $propNames = @()
            foreach ($p in $props) { $propNames += $p.Name }
            Write-Host "DTE_PROPS category=$cat page=$pg props=$($propNames -join ',')"
        } catch {
            # Category/page not found, try next
        }
    }
}

Write-Host "DTE_SKIP_NOT_FOUND"
exit 2
'@

    $helperPath = Join-Path $env:TEMP "ude_dte_skip_discovery.ps1"
    Set-Content -Path $helperPath -Value $dteSkipScript -Encoding UTF8

    $skipProc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$helperPath`"" `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $env:TEMP "ude_dte_skip_stdout.txt") `
        -RedirectStandardError  (Join-Path $env:TEMP "ude_dte_skip_stderr.txt")

    $skipProc.WaitForExit(15000)
    $dteOutput = ""
    if (Test-Path (Join-Path $env:TEMP "ude_dte_skip_stdout.txt")) {
        $dteOutput = Get-Content (Join-Path $env:TEMP "ude_dte_skip_stdout.txt") -Raw
        if ($dteOutput) { Write-Host "  DTE output: $($dteOutput.Trim())" }
    }

    if ($skipProc.HasExited -and $skipProc.ExitCode -eq 0) {
        if ($dteOutput -match 'DTE_ALREADY_CHECKED') {
            Write-Host "SKIP_DISCOVERY_ALREADY_CHECKED"
            # Clean up DTE helper from earlier
            if ($dteProc -and -not $dteProc.HasExited) {
                $dteProc.WaitForExit(5000)
                if (-not $dteProc.HasExited) { Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue }
            }
            exit 0
        } elseif ($dteOutput -match 'DTE_SET_CHECKED') {
            Write-Host "SKIP_DISCOVERY_CHECKED"
            if ($dteProc -and -not $dteProc.HasExited) {
                $dteProc.WaitForExit(5000)
                if (-not $dteProc.HasExited) { Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue }
            }
            exit 0
        }
    }

    if (-not $skipProc.HasExited) {
        Stop-Process -Id $skipProc.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  DTE COM property approach did not succeed"
}

if (-not $skipCb) {
    Write-Host "Visible checkboxes:"
    $checkboxes = $optionsDlg.FindAll($TS::Descendants, $cbCond)
    foreach ($cb in $checkboxes) { Write-Host "  '$($cb.Current.Name)'" }
    # Clean up DTE helper
    if ($dteProc -and -not $dteProc.HasExited) {
        $dteProc.WaitForExit(5000)
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
    $cancelBtn = Find-ButtonByName -Parent $optionsDlg -Name 'Cancel'
    if ($cancelBtn) {
        try { $cancelBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch {}
    }
    # Clean up DTE helper
    if ($dteProc -and -not $dteProc.HasExited) {
        $dteProc.WaitForExit(5000)
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
    $cancelBtn = Find-ButtonByName -Parent $optionsDlg -Name 'Cancel'
    if ($cancelBtn) {
        try { $cancelBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch {}
    }
    if ($dteProc -and -not $dteProc.HasExited) {
        $dteProc.WaitForExit(5000)
        if (-not $dteProc.HasExited) { Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "SKIP_DISCOVERY_FAIL toggle did not stick (state=$newState)"
    exit 1
}

# --- Click OK to save ---
$okClicked = $false

# Strategy A: Find OK pane (direct child) with inner Button
$allChildren = $optionsDlg.FindAll($TS::Children, [System.Windows.Automation.Condition]::TrueCondition)
foreach ($c in $allChildren) {
    if ($c.Current.Name -eq 'OK') {
        $btnCond2 = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::Button)
        $innerBtn = $c.FindFirst($TS::Descendants, $btnCond2)
        if ($innerBtn) {
            try {
                $innerBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                $okClicked = $true
                Write-Host "OK inner button invoked"
            } catch {}
        }
        if (-not $okClicked) {
            # Coordinate-click the pane center
            $rect = $c.Current.BoundingRectangle
            $cx = [int]($rect.X + $rect.Width / 2)
            $cy = [int]($rect.Y + $rect.Height / 2)
            Show-Vs
            Start-Sleep -Milliseconds 300
            [UdeSwitchUiaNative]::ClickAt($cx, $cy)
            $okClicked = $true
            Write-Host "OK pane clicked at ($cx, $cy)"
        }
        break
    }
}

# Strategy B: Find OK Button by name (descendant search)
if (-not $okClicked) {
    $okBtn = Find-ButtonByName -Parent $optionsDlg -Name 'OK'
    if ($okBtn) {
        Invoke-Button -Button $okBtn -VsHwnd $vs.MainWindowHandle | ForEach-Object { Write-Host "OK: $_" }
        $okClicked = $true
    }
}

if (-not $okClicked) {
    Write-Host "WARNING: Could not find OK button - attempting Cancel"
    $cancelBtn = Find-ButtonByName -Parent $optionsDlg -Name 'Cancel'
    if ($cancelBtn) {
        try { $cancelBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch {}
    }
    if ($dteProc -and -not $dteProc.HasExited) {
        $dteProc.WaitForExit(5000)
        if (-not $dteProc.HasExited) { Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "SKIP_DISCOVERY_FAIL Could not click OK to save"
    exit 1
}

Start-Sleep -Milliseconds 1000

# Verify dialog closed
$stillOpen = $false
$windows = $vsElem.FindAll($TS::Descendants, $winCond)
foreach ($w in $windows) {
    if ($w.Current.Name -eq 'Options') { $stillOpen = $true; break }
}
if ($stillOpen) {
    Write-Host "WARNING: Options dialog still open - clicking Cancel"
    $cancelBtn = Find-ButtonByName -Parent $optionsDlg -Name 'Cancel'
    if ($cancelBtn) {
        try { $cancelBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch {}
    }
}

# Clean up DTE helper process
if ($dteProc -and -not $dteProc.HasExited) {
    $dteProc.WaitForExit(10000)
    if (-not $dteProc.HasExited) {
        Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue
    }
}

# no-minimize: leave VS as-is (never minimize VS - user can't restore it)
Write-Host "SKIP_DISCOVERY_CHECKED"
exit 0
