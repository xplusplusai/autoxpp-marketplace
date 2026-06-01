# open_connect_dataverse_menu.ps1 - drive VS menu: Tools -> Connect to online Dataverse
#
# Uses Alt-key navigation since the full menu path is localized and deep.
# Sequence: Alt+T (Tools) then search menu items for "Connect to online Dataverse".
#
# Emits:
#   MENU_OPENED
#   MENU_ERROR <reason>

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Host "MENU_ERROR VS not running"; exit 1 }

Show-Vs
Start-Sleep -Milliseconds 500

$vsElem = Get-VsAutomationElement -VsPid $vs.Id
if (-not $vsElem) { Write-Host "MENU_ERROR Cannot get automation element"; exit 1 }

# Find Tools menu (MenuItem) by name
$menuItemCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::MenuItem)
$items = $vsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuItemCond)

$toolsMenu = $null
foreach ($mi in $items) {
    if ($mi.Current.Name -eq 'Tools') { $toolsMenu = $mi; break }
}

if (-not $toolsMenu) {
    Write-Host "MENU_ERROR Tools menu not found via UIA"
    exit 1
}

# Expand Tools menu
try {
    $ep = $toolsMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $ep.Expand()
    Start-Sleep -Milliseconds 500
} catch {
    Write-Host "MENU_ERROR Cannot expand Tools menu: $($_.Exception.Message)"
    exit 1
}

# Now walk the menu items looking for "Connect to online Dataverse"
$items2 = $vsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuItemCond)
$target = $null
foreach ($mi in $items2) {
    $n = $mi.Current.Name
    if ($n -match 'Connect to online Dataverse' -or $n -match 'Connect.*Dataverse') {
        $target = $mi; break
    }
}

if (-not $target) {
    Write-Host "MENU_ERROR 'Connect to online Dataverse' item not found - is Power Platform Tools installed?"
    # Collapse the Tools menu to leave UI clean
    try { $toolsMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
    exit 1
}

try {
    $ip = $target.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $ip.Invoke()
    Write-Host "MENU_OPENED"
    exit 0
} catch {
    Write-Host "MENU_ERROR Cannot invoke menu item: $($_.Exception.Message)"
    exit 1
}
