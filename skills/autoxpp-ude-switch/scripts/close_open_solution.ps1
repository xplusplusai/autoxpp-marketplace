# close_open_solution.ps1 - close any open solution before switching UDE.
# Uses File -> Close Solution. If no solution is open, the menu item is grayed out
# and invoke is a no-op; we detect that and succeed silently.
#
# Emits:
#   SOLUTION_CLOSED
#   SOLUTION_NONE
#   SOLUTION_CLOSE_ERROR <reason>

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Host "SOLUTION_CLOSE_ERROR VS not running"; exit 1 }

$vsElem = Get-VsAutomationElement -VsPid $vs.Id

$menuItemCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::MenuItem)
$items = $vsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuItemCond)

$fileMenu = $null
foreach ($mi in $items) { if ($mi.Current.Name -eq 'File') { $fileMenu = $mi; break } }
if (-not $fileMenu) { Write-Host "SOLUTION_CLOSE_ERROR File menu not found"; exit 1 }

try {
    $fileMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    Start-Sleep -Milliseconds 400
} catch {
    Write-Host "SOLUTION_CLOSE_ERROR Cannot expand File menu"
    exit 1
}

$items2 = $vsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuItemCond)
$close = $null
foreach ($mi in $items2) {
    if ($mi.Current.Name -eq 'Close Solution') { $close = $mi; break }
}

if (-not $close) {
    # No "Close Solution" item - likely nothing is open
    try { $fileMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
    Write-Host "SOLUTION_NONE"
    exit 0
}

# Check if it's enabled
if ($close.Current.IsEnabled -eq $false) {
    try { $fileMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
    Write-Host "SOLUTION_NONE (Close Solution disabled)"
    exit 0
}

try {
    $close.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 500

    # If VS asks "Save changes?" - handle Yes/No/Cancel
    Start-Sleep -Milliseconds 500
    $vsElem2 = Get-VsAutomationElement -VsPid $vs.Id
    $saveDlg = Find-ChildWindow -Parent $vsElem2 -NameContains @('Microsoft Visual Studio','Save')
    if ($saveDlg) {
        $yes = Find-ButtonByName -Parent $saveDlg -Name "Yes"
        if ($yes) { Invoke-Button -Button $yes -VsHwnd $vs.MainWindowHandle | Out-Null }
    }

    Write-Host "SOLUTION_CLOSED"
    exit 0
} catch {
    Write-Host "SOLUTION_CLOSE_ERROR $($_.Exception.Message)"
    exit 1
}
