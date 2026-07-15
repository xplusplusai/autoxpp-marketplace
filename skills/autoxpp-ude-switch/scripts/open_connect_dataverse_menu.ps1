# open_connect_dataverse_menu.ps1 - drive VS menu: Tools -> Connect to online Dataverse
#
# Uses UIA ExpandCollapsePattern on the Tools menu, then searches for the
# "Connect to online Dataverse" menu item. Falls back to DTE COM via separate
# process when VS lacks foreground focus. Uses time-based retry (default 10 min)
# with verbose progress -- VS extensions can take a very long time to load after
# config switches. The decision to abort belongs to the caller/user, not this script.
#
# Emits:
#   MENU_OPENED
#   MENU_ERROR <reason>

param([int]$TimeoutSeconds = 600)

. "$PSScriptRoot\uia_helpers.ps1"

# --- DTE helper script content (written to temp and run via Start-Process) ---
# Tries to execute "Connect to online Dataverse" via DTE COM, bypassing UIA menus.
# Uses CommandBars first (caption search), then known command names as fallback.
# May block if the command opens a modal dialog (Reconnect prompt, Login, etc.).
$script:DteConnectScript = @'
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

# Strategy 1: CommandBars -- search by caption (works without foreground)
try {
    $menuBar = $dte.CommandBars.Item("MenuBar")
    $toolsCtrl = $null
    foreach ($ctrl in $menuBar.Controls) {
        if ($ctrl.Caption -match '^&?Tools$') { $toolsCtrl = $ctrl; break }
    }
    if ($toolsCtrl) {
        $popup = $toolsCtrl.CommandBar
        $connectItem = $null
        foreach ($ctrl in $popup.Controls) {
            if ($ctrl.Caption -match 'Connect.*Dataverse') { $connectItem = $ctrl; break }
        }
        if ($connectItem) {
            # Signal that we found the command before executing (may block on modal)
            [System.IO.File]::WriteAllText(
                [System.IO.Path]::Combine($env:TEMP, "ude_dte_connect_signal.txt"),
                "FOUND")
            $connectItem.Execute()
            exit 0
        }
    }
} catch {}

# Strategy 2: try known DTE command names
$candidates = @(
    "Tools.ConnecttoonlineDataverse",
    "Tools.ConnectToOnlineDataverse",
    "Tools.ConnecttoOnlineDataverse",
    "PowerPlatformTools.ConnectToOnlineDataverse",
    "PowerPlatformTools.ConnecttoonlineDataverse"
)
foreach ($name in $candidates) {
    try {
        [System.IO.File]::WriteAllText(
            [System.IO.Path]::Combine($env:TEMP, "ude_dte_connect_signal.txt"),
            "FOUND")
        $dte.ExecuteCommand($name)
        exit 0
    } catch {}
}

exit 1
'@

$vs = Get-VsProcess
if (-not $vs) { Write-Host "MENU_ERROR VS not running"; exit 1 }

Show-Vs
Start-Sleep -Milliseconds 500

$TS = [System.Windows.Automation.TreeScope]
$AE = [System.Windows.Automation.AutomationElement]
$CT = [System.Windows.Automation.ControlType]

$menuItemCond = New-Object System.Windows.Automation.PropertyCondition(
    $AE::ControlTypeProperty, $CT::MenuItem)
$winCond = New-Object System.Windows.Automation.PropertyCondition(
    $AE::ControlTypeProperty, $CT::Window)

$lastErr = ""
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$attempt = 0
$dteProc = $null
$signalPath = Join-Path $env:TEMP "ude_dte_connect_signal.txt"

while ((Get-Date) -lt $deadline) {
    $attempt++
    if ($attempt -gt 1) {
        $remaining = [math]::Round(($deadline - (Get-Date)).TotalSeconds)
        $elapsed = [math]::Round($TimeoutSeconds - $remaining)
        Write-Host "  Retry $attempt in 15s -- extensions may still be loading (${elapsed}s elapsed, ${remaining}s remaining)..."
        Start-Sleep -Seconds 15
        Show-Vs
        Start-Sleep -Milliseconds 500
    }

    # Re-acquire automation element every attempt -- the UIA tree is stale if
    # acquired during VS startup and won't reflect newly loaded extensions.
    $vsElem = Get-VsAutomationElement -VsPid $vs.Id
    if (-not $vsElem) { $lastErr = "Cannot get automation element"; continue }

    # --- Strategy A: UIA menu expansion ---
    $items = $vsElem.FindAll($TS::Descendants, $menuItemCond)
    $toolsMenu = $null
    foreach ($mi in $items) {
        if ($mi.Current.Name -eq 'Tools') { $toolsMenu = $mi; break }
    }

    if ($toolsMenu) {
        try {
            $ep = $toolsMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
            $ep.Expand()
            Start-Sleep -Milliseconds 800

            # Search the Tools menu element's own descendants (NOT vsElem --
            # WPF menu popups are linked to the menu item, not the main window).
            $items2 = $toolsMenu.FindAll($TS::Descendants, $menuItemCond)
            $target = $null
            foreach ($mi in $items2) {
                $n = $mi.Current.Name
                if ($n -match 'Connect to online Dataverse' -or $n -match 'Connect.*Dataverse') {
                    $target = $mi; break
                }
            }

            if ($target) {
                try {
                    $ip = $target.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                    $ip.Invoke()
                    Write-Host "MENU_OPENED"
                    exit 0
                } catch {
                    $lastErr = "Cannot invoke menu item: $($_.Exception.Message)"
                    Write-Host "  Attempt ${attempt}: $lastErr"
                }
            } else {
                try { $toolsMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
                $lastErr = "'Connect to online Dataverse' not found in expanded menu (no foreground?)"
                Write-Host "  Attempt ${attempt}: $lastErr"
            }
        } catch {
            $lastErr = "Cannot expand Tools menu: $($_.Exception.Message)"
            Write-Host "  Attempt ${attempt}: $lastErr"
        }
    } else {
        $lastErr = "Tools menu not found via UIA"
        Write-Host "  Attempt ${attempt}: $lastErr"
    }

    # --- Strategy B: DTE COM via separate process (works without foreground) ---
    # Clean up any previous DTE helper
    if ($dteProc -and -not $dteProc.HasExited) {
        Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue
        $dteProc = $null
    }

    Write-Host "  Trying DTE COM fallback..."
    Remove-Item $signalPath -Force -ErrorAction SilentlyContinue

    $helperPath = Join-Path $env:TEMP "ude_dte_connect_dataverse.ps1"
    Set-Content -Path $helperPath -Value $script:DteConnectScript -Encoding UTF8

    $dteProc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$helperPath`"" `
        -PassThru -WindowStyle Hidden

    # Wait for helper: it may exit quickly (non-blocking command) or block on modal
    $null = $dteProc.WaitForExit(15000)

    if ($dteProc.HasExited -and $dteProc.ExitCode -eq 0) {
        # Command executed and returned -- menu action triggered
        Write-Host "MENU_OPENED"
        exit 0
    }

    # Helper still running? Check if it signaled that it found the command
    # (meaning it is now blocked on a modal dialog the command opened)
    if (-not $dteProc.HasExited -and (Test-Path $signalPath)) {
        Write-Host "  DTE COM command found and executing (blocked on modal dialog)"
        # The command opened a dialog (Reconnect, Login, etc.) -- that is success.
        # Leave the helper running; it will unblock when subsequent scripts
        # handle the dialog.
        Write-Host "MENU_OPENED"
        exit 0
    }

    # DTE failed this attempt -- clean up and retry with UIA
    if (-not $dteProc.HasExited) {
        Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue
    }
    $dteProc = $null
    Write-Host "  DTE COM fallback did not succeed this attempt"
}

# Final cleanup
if ($dteProc -and -not $dteProc.HasExited) {
    Stop-Process -Id $dteProc.Id -Force -ErrorAction SilentlyContinue
}

Write-Host "MENU_ERROR $lastErr (after $attempt attempts over ${TimeoutSeconds}s)"
exit 1
