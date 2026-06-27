# ensure_skip_discovery.ps1
# Opens Tools > Options > Power Platform Tools > General and ensures
# "Skip Discovery when connecting to Dataverse" is checked.
# Uses pure UIA -- NO SendKeys.
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

# --- Navigate to Power Platform Tools via search box (ValuePattern, no SendKeys) ---
$skipCb = $null

# Strategy 1: Find search/filter Edit control and set value via ValuePattern
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
    Write-Host "Using search box to filter to 'Power Platform'..."
    try {
        $vp = $searchBox.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $vp.SetValue("Power Platform")
        Start-Sleep -Seconds 2

        # After filtering, look for the Skip Discovery checkbox
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
    $treeItems = $optionsDlg.FindAll($TS::Descendants, $treeItemCond)

    $ppItem = $null
    foreach ($ti in $treeItems) {
        if ($ti.Current.Name -match 'Power Platform') { $ppItem = $ti; break }
    }

    if ($ppItem) {
        Write-Host "  Found '$($ppItem.Current.Name)'"

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
    } else {
        Write-Host "  'Power Platform' TreeItem not found in Options tree"
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

if (-not $skipCb) {
    Write-Host "Visible checkboxes:"
    $checkboxes = $optionsDlg.FindAll($TS::Descendants, $cbCond)
    foreach ($cb in $checkboxes) { Write-Host "  '$($cb.Current.Name)'" }
    # Close dialog
    $cancelBtn = Find-ButtonByName -Parent $optionsDlg -Name 'Cancel'
    if ($cancelBtn) {
        try { $cancelBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch {}
    }
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
