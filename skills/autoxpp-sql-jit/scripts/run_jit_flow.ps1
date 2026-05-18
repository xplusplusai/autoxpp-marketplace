param(
    # JIT dialog can take 60-150s to appear after Solution-Done on a freshly
    # launched VS (Power Platform Explorer init + JIT backend warmup).
    [int]$JitTimeoutSec = 180,
    [int]$CredPopulateTimeoutSec = 60
)

# End-to-end JIT flow: Tools menu → Reconnect Yes → Solution dialog → JIT dialog →
# fill Reason → Request Access → poll for creds → copy Connection string → return
# raw connection string + expiry to caller on stdout as a single JSON line.
#
# Caller (skill orchestrator) is responsible for parsing + cache write.

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
$ErrorActionPreference = 'Continue'

function Get-VSWindow {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $p = Get-Process devenv -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if (-not $p) { return $null }
    $pidCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $pidCond)
}

function Get-ChildWindows($vs) {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Window)
    return $vs.FindAll([System.Windows.Automation.TreeScope]::Children, $c)
}

function Find-Button($root, $nameTrim) {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
    return $btns | Where-Object { $_.Current.Name.Trim() -eq $nameTrim } | Select-Object -First 1
}

function Invoke-Btn($btn) {
    $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Find-Edit-ByName($root, $like) {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    $edits = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
    return $edits | Where-Object { $_.Current.Name -like $like } | Select-Object -First 1
}

function Find-JIT-Dialog($vs) {
    $cw = Get-ChildWindows $vs
    foreach ($w in $cw) {
        $marker = $w.FindFirst(
            [System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty,
                'Dynamics 365 FinOps: Just In Time Credentials')))
        if ($marker) { return $w }
    }
    return $null
}

# --- Step 1: open Tools menu and invoke SQL Credentials item ---
$menuCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::MenuItem)

# Wait up to 60s for Tools menu to populate (menu bar lags VS window-ready signal)
$toolsDeadline = (Get-Date).AddSeconds(60)
$vs = $null
$tools = $null
while ((Get-Date) -lt $toolsDeadline) {
    try {
        $vs = Get-VSWindow
        if ($vs) {
            $items = $vs.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuCond)
            $tools = $items | Where-Object { $_.Current.Name -eq 'Tools' } | Select-Object -First 1
            if ($tools) { break }
        }
    } catch {}
    Start-Sleep -Seconds 2
}
if (-not $vs) { Write-Host '{"status":"FAIL","reason":"VS_NOT_RUNNING"}'; exit 1 }
if (-not $tools) { Write-Host '{"status":"FAIL","reason":"TOOLS_MENU_NOT_FOUND"}'; exit 1 }
Write-Host "STEP: Tools menu found"

$tools.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
Start-Sleep -Milliseconds 1500
$items2 = $vs.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuCond)
$sqlCred = $items2 | Where-Object { $_.Current.Name -like 'SQL Credentials*' } | Select-Object -First 1
if (-not $sqlCred) {
    try { $tools.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
    Write-Host '{"status":"FAIL","reason":"SQL_CRED_MENU_NOT_FOUND"}'; exit 1
}
$sqlCred.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-Host "STEP: menu invoked"

# --- Step 2: handle dialog cascade until JIT dialog appears ---
$deadline = (Get-Date).AddSeconds($JitTimeoutSec)
$jit = $null
$handledReconnect = $false
$handledLoginPhase = $false
$handledSolutionPhase = $false

while ((Get-Date) -lt $deadline -and -not $jit) {
    Start-Sleep -Milliseconds 1500
    try {
        $vs = Get-VSWindow
        $jit = Find-JIT-Dialog $vs
        if ($jit) { break }

        $cw = Get-ChildWindows $vs
        foreach ($w in $cw) {
            $name = $w.Current.Name

            # Reconnect to Dataverse → click Yes
            if ($name -eq 'Reconnect to Dataverse' -and -not $handledReconnect) {
                $yes = Find-Button $w 'Yes'
                if ($yes) {
                    Invoke-Btn $yes
                    $handledReconnect = $true
                    Write-Host "STEP: Reconnect Yes clicked"
                }
                continue
            }

            # Configure Power Platform Solution — two phases
            if ($name -like '*Power Platform Solution*') {
                $doneBtn = Find-Button $w 'Done'
                $loginBtn = Find-Button $w 'Login'

                $cbCond = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::ComboBox)
                $combos = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cbCond)
                $selSol = $combos | Where-Object { $_.Current.Name -eq 'Select Solution:' } | Select-Object -First 1

                if ($selSol -and $doneBtn -and -not $handledSolutionPhase) {
                    # Phase 2: delegate to build skill's handler (BoundingRectangle + mouse_event
                    # is more reliable than InvokePattern on this WPF Done button).
                    $skillsRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
                    $handler = Join-Path $skillsRoot 'autoxpp-build\scripts\handle_solution_dialog.ps1'
                    $focus = Join-Path $skillsRoot 'autoxpp-build\scripts\focus_maximize_vs.ps1'
                    & powershell.exe -ExecutionPolicy Bypass -File $focus | Out-Null
                    $out = & powershell.exe -ExecutionPolicy Bypass -File $handler 2>&1
                    Write-Host "STEP: delegated to handle_solution_dialog: $($out -join ' | ')"
                    Start-Sleep -Seconds 2
                    # Check if the dialog still exists — if so, the mouse_event click
                    # got consumed as a focus event; double-click the button coord.
                    $vsCheck = Get-VSWindow
                    if ($vsCheck) {
                        $cwCheck = Get-ChildWindows $vsCheck
                        $stillOpen = $cwCheck | Where-Object { $_.Current.Name -like '*Power Platform Solution*' } | Select-Object -First 1
                        if ($stillOpen) {
                            $doneBtn2 = Find-Button $stillOpen 'Done'
                            if ($doneBtn2) {
                                $rect = $doneBtn2.Current.BoundingRectangle
                                $cx = [int]($rect.X + $rect.Width / 2)
                                $cy = [int]($rect.Y + $rect.Height / 2)
                                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinMouse {
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
}
"@ -ErrorAction SilentlyContinue
                                [WinMouse]::SetCursorPos($cx, $cy) | Out-Null
                                Start-Sleep -Milliseconds 200
                                [WinMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
                                [WinMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
                                Start-Sleep -Milliseconds 400
                                [WinMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
                                [WinMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
                                Write-Host "STEP: Done double-clicked at ($cx,$cy)"
                            }
                        }
                    }
                    $handledSolutionPhase = $true
                } elseif ($loginBtn -and -not $handledLoginPhase) {
                    # Phase 1: click Login (Sign in as current user pre-checked)
                    Invoke-Btn $loginBtn
                    $handledLoginPhase = $true
                    Write-Host "STEP: Login clicked"
                }
                continue
            }

            # Login Failure → fail fast
            if ($name -eq 'Login Failure') {
                Write-Host '{"status":"FAIL","reason":"LOGIN_FAILURE_DIALOG"}'
                exit 1
            }
        }
    } catch {
        # HRESULT 0x80131505 during auth handshake — benign, retry
        Write-Host "WARN: UIA transient error: $($_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}

if (-not $jit) {
    Write-Host '{"status":"FAIL","reason":"JIT_DIALOG_TIMEOUT"}'
    exit 1
}
Write-Host "STEP: JIT dialog open"

# --- Step 3: fill Reason, click Request Access ---
$reason = Find-Edit-ByName $jit 'Reason*'
if (-not $reason) { Write-Host '{"status":"FAIL","reason":"REASON_FIELD_NOT_FOUND"}'; exit 1 }
$reason.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Testing')

$reqBtn = Find-Button $jit 'Request Access'
if (-not $reqBtn) { Write-Host '{"status":"FAIL","reason":"REQUEST_BUTTON_NOT_FOUND"}'; exit 1 }
Invoke-Btn $reqBtn
Write-Host "STEP: Request Access clicked"

# --- Step 4: poll for creds ---
$deadline2 = (Get-Date).AddSeconds($CredPopulateTimeoutSec)
$expiryVal = $null
$serverVal = $null
while ((Get-Date) -lt $deadline2) {
    Start-Sleep -Seconds 2
    try {
        $vs = Get-VSWindow
        $jit = Find-JIT-Dialog $vs
        if (-not $jit) { continue }
        $expiryE = Find-Edit-ByName $jit 'Credential Expires On*'
        $serverE = Find-Edit-ByName $jit 'SQL Server Name*'
        $expiryVal = $expiryE.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        $serverVal = $serverE.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if ($expiryVal -and $serverVal) { break }
    } catch {}
}

if (-not $expiryVal -or -not $serverVal) {
    Write-Host '{"status":"FAIL","reason":"CREDS_POPULATE_TIMEOUT"}'
    exit 1
}
Write-Host "STEP: creds populated"

# --- Step 5: clear clipboard, click Connection string ---
[System.Windows.Forms.Clipboard]::Clear()
$connBtn = Find-Button $jit 'Connection string'
if (-not $connBtn) { Write-Host '{"status":"FAIL","reason":"CONNSTR_BUTTON_NOT_FOUND"}'; exit 1 }
Invoke-Btn $connBtn
Start-Sleep -Milliseconds 1200
Write-Host "STEP: Connection string clicked"

# --- Step 6: close the dialog via WindowPattern ---
try {
    $jit.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
} catch {}

# Emit result as a final JSON line
# Note: we do NOT include the connection string here — caller reads clipboard in STA mode
$expiryIso = ''
try {
    $dt = [DateTime]::Parse($expiryVal)
    $expiryIso = $dt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
} catch { $expiryIso = $expiryVal }

$result = [pscustomobject]@{
    status = 'OK'
    server = $serverVal
    expiresOn = $expiryIso
    expiresOnLocal = $expiryVal
}
Write-Host ('RESULT: ' + ($result | ConvertTo-Json -Compress))
