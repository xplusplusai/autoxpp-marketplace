# open_connect_dataverse_menu.ps1 - drive VS menu: Tools -> Connect to online Dataverse
#
# Uses UIA ExpandCollapsePattern on the Tools menu, then searches for the
# "Connect to online Dataverse" menu item. Retries up to 3 times with 5s wait
# between attempts (VS extensions may still be loading on first try).
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

$menuItemCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::MenuItem)

$lastErr = ""

for ($attempt = 1; $attempt -le 3; $attempt++) {
    if ($attempt -gt 1) {
        Write-Host "  Retry $attempt in 5s (extensions may still be loading)..."
        Start-Sleep -Seconds 5
        Show-Vs
        Start-Sleep -Milliseconds 500
        # Re-acquire automation element (VS tree may have changed)
        $vsElem = Get-VsAutomationElement -VsPid $vs.Id
        if (-not $vsElem) { $lastErr = "Cannot get automation element on retry"; continue }
    }

    # Find Tools menu (MenuItem) by name
    $items = $vsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuItemCond)
    $toolsMenu = $null
    foreach ($mi in $items) {
        if ($mi.Current.Name -eq 'Tools') { $toolsMenu = $mi; break }
    }

    if (-not $toolsMenu) {
        $lastErr = "Tools menu not found via UIA"
        Write-Host "  Attempt $attempt`: $lastErr"
        continue
    }

    # Expand Tools menu
    try {
        $ep = $toolsMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        $ep.Expand()
        Start-Sleep -Milliseconds 800
    } catch {
        $lastErr = "Cannot expand Tools menu: $($_.Exception.Message)"
        Write-Host "  Attempt $attempt`: $lastErr"
        continue
    }

    # Walk menu items looking for "Connect to online Dataverse"
    $items2 = $vsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuItemCond)
    $target = $null
    foreach ($mi in $items2) {
        $n = $mi.Current.Name
        if ($n -match 'Connect to online Dataverse' -or $n -match 'Connect.*Dataverse') {
            $target = $mi; break
        }
    }

    if (-not $target) {
        # Collapse the menu to leave UI clean before retry
        try { $toolsMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
        $lastErr = "'Connect to online Dataverse' item not found - Power Platform Tools may still be loading"
        Write-Host "  Attempt $attempt`: $lastErr"
        continue
    }

    try {
        $ip = $target.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $ip.Invoke()
        Write-Host "MENU_OPENED"
        exit 0
    } catch {
        $lastErr = "Cannot invoke menu item: $($_.Exception.Message)"
        Write-Host "  Attempt $attempt`: $lastErr"
        continue
    }
}

Write-Host "MENU_ERROR $lastErr (after 3 attempts)"
exit 1
