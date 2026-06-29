# select_current_xpp_config.ps1 - switch the "Current" XPP config via VS UI
#
# Opens Extensions > Dynamics 365 > Configure Metadata... dialog,
# selects the target config row by name, checks its "Current" checkbox,
# clicks Save, and closes the dialog.
#
# Usage: select_current_xpp_config.ps1 -ConfigName <name> [-TimeoutSeconds 30]
#
# Emits:
#   XPP_CONFIG_SELECTED name=<name>
#   XPP_CONFIG_ALREADY_CURRENT name=<name>
#   XPP_CONFIG_ERROR <reason>
#
# Dot-sources uia_helpers.ps1 for Dismiss-D365UpdateDialog.

param(
    [Parameter(Mandatory=$true)][string]$ConfigName,
    [int]$TimeoutSeconds = 30,
    [int]$MenuTimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
Add-Type -AssemblyName UIAutomationTypes  -ErrorAction SilentlyContinue

# Dot-source shared UIA helpers for Dismiss-D365UpdateDialog
. "$PSScriptRoot\uia_helpers.ps1"

# --- Main logic ---

# Step 1: Ensure VS is running
$vs = Get-VsProcess
if (-not $vs) {
    Write-Host "XPP_CONFIG_ERROR VS not running"
    exit 1
}
$vsElem = Get-VsAutomationElement

# Step 2: Open Extensions > Dynamics 365 > Configure Metadata...
Write-Host "Opening Configure Metadata dialog..."

$menuOpened = $false
$menuDeadline = (Get-Date).AddSeconds($MenuTimeoutSeconds)
$attempt = 0
while ((Get-Date) -lt $menuDeadline) {
    $attempt++
    $remaining = [math]::Round(($menuDeadline - (Get-Date)).TotalSeconds)
    $elapsed = [math]::Round($MenuTimeoutSeconds - $remaining)
    if ($attempt -gt 1) {
        Write-Host "  Retry $attempt in 15s -- D365 menu may still be loading (${elapsed}s elapsed, ${remaining}s remaining)..."
        Start-Sleep -Seconds 15
    }

    try {
        # Re-acquire VS automation element each attempt (stale elements miss menu items)
        $vsElem = Get-VsAutomationElement
        if (-not $vsElem) { throw "Cannot get VS automation element" }

        $menuBar = $vsElem.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, 'MenuBar')))
        if (-not $menuBar) { throw "MenuBar not found" }

        $extMenu = $menuBar.FindFirst(
            [System.Windows.Automation.TreeScope]::Children,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, 'Extensions')))
        if (-not $extMenu) { throw "Extensions menu not found -- D365 extension may still be loading" }

        # UIA ExpandCollapse does not send real Win32 mouse messages, so the D365
        # extension may never lazy-load. After 3 UIA-only attempts, switch to a
        # BoundingRectangle coordinate click which fires WM_LBUTTONDOWN and
        # triggers the extension's activation handler.
        if ($attempt -le 3) {
            $extMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        } else {
            if ($attempt -eq 4) { Write-Host "  Switching to coord-click (UIA Expand may not trigger D365 extension load)" }
            Show-Vs
            $rect = $extMenu.Current.BoundingRectangle
            [UdeSwitchUiaNative]::ClickAt([int]($rect.X + $rect.Width / 2), [int]($rect.Y + $rect.Height / 2))
        }
        Start-Sleep -Milliseconds 1500

        $d365 = $extMenu.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, 'Dynamics 365')))
        if (-not $d365) { throw "Dynamics 365 submenu not found -- extension may still be loading" }

        # Same logic for D365 submenu: coord-click after initial UIA attempts
        if ($attempt -le 3) {
            $d365.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        } else {
            $rect = $d365.Current.BoundingRectangle
            [UdeSwitchUiaNative]::ClickAt([int]($rect.X + $rect.Width / 2), [int]($rect.Y + $rect.Height / 2))
        }
        Start-Sleep -Milliseconds 800

        $cfgItem = $d365.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, 'Configure Metadata...')))
        if (-not $cfgItem) { throw "Configure Metadata menu item not found" }

        $cfgItem.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        $menuOpened = $true
        break
    } catch {
        Write-Host "  Attempt $attempt`: $_"
        # Close any open menus: UIA Collapse for early attempts, Escape key for coord-click
        if ($attempt -le 3) {
            try { if ($extMenu) { $extMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } } catch {}
        } else {
            [UdeSwitchUiaNative]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)
            [UdeSwitchUiaNative]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 300
            [UdeSwitchUiaNative]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)
            [UdeSwitchUiaNative]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
        }
        # Check if the D365 extension update dialog appeared and dismiss it
        Dismiss-D365UpdateDialog | Out-Null
    }
}
if (-not $menuOpened) {
    Write-Host "XPP_CONFIG_ERROR Failed to open Configure Metadata dialog after $attempt attempts over ${MenuTimeoutSeconds}s"
    exit 1
}

# Step 3: Wait for dialog to appear (use FocusedElement + parent walk)
Write-Host "Waiting for dialog..."
Start-Sleep -Seconds 2
$dlg = $null
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$walker = [System.Windows.Automation.TreeWalker]::RawViewWalker

while ((Get-Date) -lt $deadline) {
    $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
    $candidate = $focused
    while ($candidate) {
        if ($candidate.Current.Name -eq 'Manage local XPP configurations' -and
            $candidate.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) {
            $dlg = $candidate
            break
        }
        $candidate = $walker.GetParent($candidate)
    }
    if ($dlg) { break }
    Start-Sleep -Milliseconds 500
}

if (-not $dlg) {
    Write-Host "XPP_CONFIG_ERROR Dialog did not appear within ${TimeoutSeconds}s"
    exit 1
}
Write-Host "Dialog found."

# Step 4: Find target config row in LV_configs ListView
$listView = $dlg.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'LV_configs')))
if (-not $listView) {
    Write-Host "XPP_CONFIG_ERROR ListView LV_configs not found"
    exit 1
}

$rows = $listView.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::DataItem)))

$targetRow = $null
$targetCheckBox = $null
foreach ($row in $rows) {
    if ($row.Current.Name -eq $ConfigName) {
        $targetRow = $row
        $targetCheckBox = $row.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'ckBxIsActive')))
        break
    }
}

if (-not $targetRow) {
    $available = @()
    foreach ($row in $rows) { $available += $row.Current.Name }
    Write-Host "XPP_CONFIG_ERROR Config '$ConfigName' not found. Available: $($available -join ', ')"
    $closeBtn = $dlg.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, 'CloseButton')))
    if ($closeBtn) { $closeBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
    exit 1
}

if (-not $targetCheckBox) {
    Write-Host "XPP_CONFIG_ERROR Checkbox ckBxIsActive not found in row '$ConfigName'"
    exit 1
}

# Step 5: Check if already current
$togglePattern = $targetCheckBox.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
$currentState = $togglePattern.Current.ToggleState

if ($currentState -eq [System.Windows.Automation.ToggleState]::On) {
    Write-Host "XPP_CONFIG_ALREADY_CURRENT name=$ConfigName"
    $closeBtn = $dlg.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, 'CloseButton')))
    if ($closeBtn) { $closeBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
    exit 0
}

# Step 6: Toggle checkbox to make it current
Write-Host "Selecting '$ConfigName' as current..."
$togglePattern.Toggle()
Start-Sleep -Milliseconds 500

$newState = $togglePattern.Current.ToggleState
if ($newState -ne [System.Windows.Automation.ToggleState]::On) {
    Write-Host "XPP_CONFIG_ERROR Checkbox did not toggle to On (state=$newState)"
    exit 1
}

# Step 7: Click Save
$saveBtn = $dlg.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'btn_Save')))
if (-not $saveBtn) {
    Write-Host "XPP_CONFIG_ERROR Save button (btn_Save) not found"
    exit 1
}

$saveBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-Host "Save clicked."
Start-Sleep -Seconds 1

# Step 8: Close dialog
$closeBtn = $dlg.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, 'CloseButton')))
if ($closeBtn) {
    $closeBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Host "Dialog closed."
}

Write-Host "XPP_CONFIG_SELECTED name=$ConfigName"
exit 0
