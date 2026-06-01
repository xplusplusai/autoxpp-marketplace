# handle_select_solution.ps1 - on the "2. Select Solution" dialog, pick the named
# solution in the combo and click Done.
#
# Usage: handle_select_solution.ps1 [-SolutionName "Default"] [-TimeoutSeconds 60]
#
# Emits:
#   SELECT_SOLUTION_HANDLED solution=<name>
#   SELECT_SOLUTION_MISSING
#   SELECT_SOLUTION_ERROR <reason>

param(
    [string]$SolutionName = "Default",
    [int]$TimeoutSeconds = 60
)

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Host "SELECT_SOLUTION_ERROR VS not running"; exit 1 }

$vsElem = Get-VsAutomationElement -VsPid $vs.Id
$dialog = Wait-ForChildWindow -Parent $vsElem -NameContains @('Select Solution','Power Platform Tools') -TimeoutSeconds $TimeoutSeconds
if (-not $dialog) {
    Write-Host "SELECT_SOLUTION_MISSING"
    exit 1
}

# Find the combo box
$comboCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::ComboBox)
$combos = @($dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, $comboCond))
if ($combos.Count -eq 0) {
    Write-Host "SELECT_SOLUTION_ERROR No ComboBox found on Select Solution dialog"
    exit 1
}
$combo = $combos[0]

# Try ExpandCollapse + Selection
try {
    $ep = $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $ep.Expand()
    Start-Sleep -Milliseconds 400
} catch {}

# Look for ListItem matching $SolutionName under the dialog
$liCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::ListItem)
$items = $dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, $liCond)

$picked = $false
foreach ($item in $items) {
    if ($item.Current.Name -eq $SolutionName) {
        try {
            $sp = $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            $sp.Select()
            $picked = $true
            break
        } catch {
            try {
                $ip = $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                $ip.Invoke()
                $picked = $true
                break
            } catch {}
        }
    }
}

if (-not $picked) {
    # Fallback: try ValuePattern on the combo itself (works for editable combos)
    try {
        $vp = $combo.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $vp.SetValue($SolutionName)
        $picked = $true
    } catch {}
}

if (-not $picked) {
    Write-Host "SELECT_SOLUTION_ERROR Could not select '$SolutionName' - ListItems found: $($items.Count)"
    exit 1
}

Start-Sleep -Milliseconds 300

# Close combo (collapse) if still open
try {
    $ep = $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $ep.Collapse()
} catch {}

# Click Done
$btn = Find-ButtonByName -Parent $dialog -Name "Done"
if (-not $btn) {
    Write-Host "SELECT_SOLUTION_ERROR Done button not found"
    exit 1
}

$click = Invoke-Button -Button $btn -VsHwnd $vs.MainWindowHandle
Write-Host "SELECT_SOLUTION_HANDLED solution=$SolutionName click=$click"
exit 0
