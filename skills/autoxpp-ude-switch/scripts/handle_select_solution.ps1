# handle_select_solution.ps1 - on step 2 ("Select Solution") of the
# "Configure Microsoft Power Platform Solution" wizard, pick the named solution in
# the combo and click Done.
#
# P-7 fix: find the wizard by its real name ("Configure Microsoft Power Platform
# Solution") rather than "Select Solution"/"Power Platform Tools"; the solution combo
# lives in the AccSolutionSelection group. The earlier name search reported
# SELECT_SOLUTION_MISSING.
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
if (-not $vs) { Write-Output "SELECT_SOLUTION_ERROR VS not running"; exit 1 }

$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$CT = [System.Windows.Automation.ControlType]

$dialog = Wait-AnyWindow -NameContains @(
    'Configure Microsoft Power Platform Solution',
    'Configure Power Platform Solution',
    'Select Solution',
    'Power Platform Tools') -TimeoutSeconds $TimeoutSeconds
if (-not $dialog) {
    Write-Output "SELECT_SOLUTION_MISSING"
    exit 1
}

# Scope to the AccSolutionSelection group if present (else the whole wizard).
$scope = Find-ByAutomationId -Parent $dialog -AutomationId 'AccSolutionSelection'
if (-not $scope) { $scope = $dialog }

# Find the solutions combo box.
$comboCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::ComboBox)
$combos = @($scope.FindAll($TS::Descendants, $comboCond))
if ($combos.Count -eq 0) {
    Write-Output "SELECT_SOLUTION_ERROR No ComboBox found in Select Solution step"
    exit 1
}
$combo = $combos[0]

# Expand and pick the matching ListItem.
try { $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 400 } catch {}

$liCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::ListItem)
$items = @($dialog.FindAll($TS::Descendants, $liCond))
$picked = $false
foreach ($item in $items) {
    if ($item.Current.Name -eq $SolutionName) {
        try { $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $picked = $true; break }
        catch {
            try { $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $picked = $true; break } catch {}
        }
    }
}

if (-not $picked) {
    # Fallback: ValuePattern on the combo (editable combos).
    try { $combo.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($SolutionName); $picked = $true } catch {}
}

if (-not $picked) {
    Write-Output "SELECT_SOLUTION_ERROR Could not select '$SolutionName' - ListItems found: $($items.Count)"
    exit 1
}

Start-Sleep -Milliseconds 300
try { $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}

# Click Done.
$btn = Find-ButtonByName -Parent $dialog -Name "Done"
if (-not $btn) {
    Write-Output "SELECT_SOLUTION_ERROR Done button not found"
    exit 1
}
$click = Invoke-Button -Button $btn -VsHwnd $vs.MainWindowHandle
Write-Output "SELECT_SOLUTION_HANDLED solution=$SolutionName click=$click"
exit 0
