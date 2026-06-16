# open_connect_dataverse_menu.ps1 - drive VS menu: Tools -> Connect to online Dataverse
#
# Uses UIA ExpandCollapsePattern on the Tools menu, then searches for the
# "Connect to online Dataverse" menu item. Uses time-based retry (default 10 min)
# with verbose progress — VS extensions can take a very long time to load after
# config switches. The decision to abort belongs to the caller/user, not this script.
#
# Emits:
#   MENU_OPENED
#   MENU_ERROR <reason>

param([int]$TimeoutSeconds = 600)

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Host "MENU_ERROR VS not running"; exit 1 }

Show-Vs
Start-Sleep -Milliseconds 500

$menuItemCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::MenuItem)

$lastErr = ""
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$attempt = 0

while ((Get-Date) -lt $deadline) {
    $attempt++
    if ($attempt -gt 1) {
        $remaining = [math]::Round(($deadline - (Get-Date)).TotalSeconds)
        $elapsed = [math]::Round($TimeoutSeconds - $remaining)
        Write-Host "  Retry $attempt in 15s — extensions may still be loading (${elapsed}s elapsed, ${remaining}s remaining)..."
        Start-Sleep -Seconds 15
        Show-Vs
        Start-Sleep -Milliseconds 500
    }

    # Re-acquire automation element every attempt — the UIA tree is stale if
    # acquired during VS startup and won't reflect newly loaded extensions.
    $vsElem = Get-VsAutomationElement -VsPid $vs.Id
    if (-not $vsElem) { $lastErr = "Cannot get automation element"; continue }

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

Write-Host "MENU_ERROR $lastErr (after $attempt attempts over ${TimeoutSeconds}s)"
exit 1
