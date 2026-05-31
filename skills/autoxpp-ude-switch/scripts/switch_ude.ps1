# switch_ude.ps1 - main orchestrator for UDE switching.
#
# Usage:
#   switch_ude.ps1 -Name <udeName>                 # switch to named UDE
#   switch_ude.ps1 -Name <udeName> -NoDownload     # warn + skip download if version not cached
#   switch_ude.ps1 -Name <udeName> -DownloadPolicy always|ask|skip|skip-if-cached
#   switch_ude.ps1 -Current                        # print current active UDE
#   switch_ude.ps1 -List                           # list configured UDEs
#   switch_ude.ps1 -Add                            # interactive add flow
#
# Exit codes:
#   0 - success
#   1 - switch failed (see log for detail)
#   2 - user input required (MFA / account picker / manual action)
#   3 - invalid args / config

param(
    [string]$Name,
    [switch]$Current,
    [switch]$List,
    [switch]$Add,
    [switch]$NoDownload,
    [ValidateSet('','always','ask','skip','skip-if-cached')]
    [string]$DownloadPolicy = ''
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\config_helpers.ps1"

# --- Mode dispatch ---
if ($List)    { & "$PSScriptRoot\list_udes.ps1"; exit $LASTEXITCODE }
if ($Current) { & "$PSScriptRoot\show_current_ude.ps1"; exit $LASTEXITCODE }
if ($Add)     { & "$PSScriptRoot\add_ude.ps1"; exit $LASTEXITCODE }

if (-not $Name) {
    Write-Host "ERROR: -Name is required (or use -List, -Current, -Add)."
    Write-Host "       Usage: switch_ude.ps1 -Name <udeName>"
    exit 3
}

$logFile = Get-UdeLogFile
Write-UdeLog -LogFile $logFile -Step "start" -Status "INFO" -Detail "target=$Name"

try {
    # --- Phase A: pre-flight (disk only) ---
    Write-UdeLog -LogFile $logFile -Step "phase-a" -Status "INFO" -Detail "loading config"
    $cfg  = Load-UdeConfigs
    $ude  = Resolve-Ude $cfg $Name

    # Resolve download policy (CLI > ude-configs.json default)
    $policy = if ($DownloadPolicy) { $DownloadPolicy }
              elseif ($NoDownload)  { 'skip' }
              elseif ($ude.ContainsKey('downloadPolicy')) { $ude.downloadPolicy }
              else { 'ask' }

    Write-UdeLog -LogFile $logFile -Step "resolve" -Status "OK" -Detail "url=$($ude.dataverseUrl) metadata=$($ude.customMetadataFolder) policy=$policy"

    # Warn if metadata folder missing (don't block)
    if (-not (Test-Path $ude.customMetadataFolder)) {
        Write-UdeLog -LogFile $logFile -Step "metadata-check" -Status "WARN" -Detail "folder not found: $($ude.customMetadataFolder)"
        Write-Host "WARNING: customMetadataFolder does not exist: $($ude.customMetadataFolder)"
        Write-Host "         Continuing — clone the repo before attempting a build."
    }

    # Snapshot XPPConfig
    $baselineFile = Join-Path (Split-Path -Parent $logFile) "xpp-baseline-$Name.txt"
    & "$PSScriptRoot\snapshot_xppconfig.ps1" | Set-Content -Path $baselineFile -Encoding UTF8
    Write-UdeLog -LogFile $logFile -Step "snapshot" -Status "OK" -Detail "baseline=$baselineFile"

    # --- Phase B: VS interaction ---
    Write-UdeLog -LogFile $logFile -Step "phase-b" -Status "INFO" -Detail "VS interaction"

    # Ensure VS is running
    $vsPath = if ($ude.ContainsKey('vsPath')) { $ude.vsPath } else { "" }
    $launchTimeout = if ($ude.timeouts) { [int]$ude.timeouts.vsRestartSeconds } else { 120 }

    $launchResult = & "$PSScriptRoot\launch_vs.ps1" -VsPath $vsPath -TimeoutSeconds $launchTimeout
    Write-UdeLog -LogFile $logFile -Step "launch-vs" -Status "OK" -Detail "$launchResult"
    if ($LASTEXITCODE -ne 0) { throw "Failed to launch VS" }

    # Close any open solution (Show VS briefly for menu nav)
    Write-Host "Showing VS to close open solution..."
    & "$PSScriptRoot\close_open_solution.ps1" | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "close-sln" -Status "INFO" -Detail $_ }
    Start-Sleep -Seconds 1

    # Tools -> Connect to online Dataverse
    Write-Host "Showing VS to open Connect to online Dataverse..."
    $menuOut = & "$PSScriptRoot\open_connect_dataverse_menu.ps1"
    $menuOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "menu" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Failed to open Connect to online Dataverse menu" }

    # Reconnect dialog (click No if shown)
    Write-Host "Handling Reconnect dialog..."
    & "$PSScriptRoot\handle_reconnect_dialog.ps1" -TimeoutSeconds 10 |
        ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "reconnect-dlg" -Status "INFO" -Detail $_ }

    # Login dialog (click Login)
    Write-Host "Handling Login dialog..."
    $loginOut = & "$PSScriptRoot\handle_login_dialog.ps1" -TimeoutSeconds 20
    $loginOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "login-dlg" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Login dialog handling failed" }

    # URL popup (type URL + OK)
    Write-Host "Handling URL popup..."
    $urlOut = & "$PSScriptRoot\handle_url_popup.ps1" -Url $ude.dataverseUrl -TimeoutSeconds 30
    $urlOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "url-popup" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "URL popup handling failed" }

    Minimize-Vs  # hide VS during the long wait
    Start-Sleep -Seconds 1

    # Wait for validation + loading
    $validTimeout = if ($ude.timeouts) { [int]$ude.timeouts.dataverseConnectSeconds } else { 180 }
    Write-Host "Waiting for Dataverse validation + workflow loading (up to ${validTimeout}s)..."
    $vOut = & "$PSScriptRoot\wait_for_validation.ps1" -TimeoutSeconds $validTimeout
    $vOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "validate" -Status "INFO" -Detail $_ }

    if ($LASTEXITCODE -eq 2) {
        Write-Host ""
        Write-Host "MFA / account picker detected. Please complete the sign-in in VS, then re-run this skill."
        Write-UdeLog -LogFile $logFile -Step "mfa" -Status "WAIT" -Detail "user action required"
        exit 2
    }
    if ($LASTEXITCODE -ne 0) { throw "Validation timed out — Dataverse not responding" }

    # Select Solution
    Show-Vs
    Start-Sleep -Seconds 1
    $solName = if ($ude.ContainsKey('solutionName')) { $ude.solutionName } else { "Default" }
    Write-Host "Selecting solution '$solName'..."
    $ssOut = & "$PSScriptRoot\handle_select_solution.ps1" -SolutionName $solName -TimeoutSeconds 30
    $ssOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "select-sln" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Select Solution dialog failed" }

    Minimize-Vs
    Start-Sleep -Seconds 2

    # Download prompt (may or may not appear)
    Write-Host "Waiting for Client assets download prompt (policy=$policy)..."
    $dlOut = & "$PSScriptRoot\handle_download_prompt.ps1" -Policy $policy -TimeoutSeconds 90
    $dlOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "dl-prompt" -Status "INFO" -Detail $_ }

    $downloadTriggered = ($dlOut -join "`n") -match 'choice=Yes'
    if ($downloadTriggered) {
        Write-Host "Download started. This typically takes ~20 minutes for a new platform version."
        Write-Host "VS may auto-exit after completion — skill will relaunch it."

        $vs = Get-Process devenv -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
        $dlTimeout = if ($ude.timeouts) { [int]$ude.timeouts.metadataDownloadSeconds } else { 3600 }

        $exitOut = & "$PSScriptRoot\wait_for_vs_exit.ps1" -VsPid $vs.Id -TimeoutSeconds $dlTimeout
        $exitOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "dl-wait" -Status "INFO" -Detail $_ }

        if ($exitOut -match 'VS_EXITED') {
            Write-Host "VS exited — waiting 15s for extension registration, then relaunching..."
            Start-Sleep -Seconds 15
            $relaunch = & "$PSScriptRoot\launch_vs.ps1" -VsPath $vsPath -TimeoutSeconds $launchTimeout
            $relaunch | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "vs-relaunch" -Status "INFO" -Detail $_ }
        }
    }

    # --- Phase C: post-switch disk edits ---
    Write-UdeLog -LogFile $logFile -Step "phase-c" -Status "INFO" -Detail "retargeting XPP config"

    # Find the newly created XPP config JSON.
    # VS names it by org ID (the Dataverse URL host) on first connect; on a
    # re-switch it reuses the previously renamed {name}___*.json. Try the org ID
    # first, then fall back to the friendly name.
    $orgId = ([System.Uri]$ude.dataverseUrl).Host.Split('.')[0]
    $diffOut = & "$PSScriptRoot\diff_xppconfig.ps1" -BaselineFile $baselineFile -ExpectedName $orgId
    if ($LASTEXITCODE -ne 0) {
        # Fallback: config may already be renamed to friendly name from a previous switch
        $diffOut = & "$PSScriptRoot\diff_xppconfig.ps1" -BaselineFile $baselineFile -ExpectedName $Name
    }
    $diffOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "diff" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Could not find new XPP config JSON" }

    $xppLine = ($diffOut | Where-Object { $_ -match '^XPP_JSON: ' }) -replace '^XPP_JSON: ', ''
    if (-not $xppLine) { throw "diff_xppconfig did not emit XPP_JSON line" }

    # Extract version from filename
    $ver = ""
    $m = [regex]::Match([System.IO.Path]::GetFileNameWithoutExtension($xppLine), '^.+___([\d\.]+)$')
    if ($m.Success) { $ver = $m.Groups[1].Value }

    # Retarget ModelStoreFolder/DebugSourceFolder
    $company = if ($ude.ContainsKey('defaultCompany')) { $ude.defaultCompany } else { "" }
    $rtOut = & "$PSScriptRoot\retarget_xpp_config.ps1" `
        -XppJsonPath $xppLine `
        -MetadataFolder $ude.customMetadataFolder `
        -DefaultCompany $company
    $rtOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "retarget" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Retarget failed" }

    # Rename XPP config to use the friendly name from ude-configs.json so the
    # "Manage local XPP configurations" dialog shows {name} instead of the org ID.
    # Skipped automatically on a re-switch (config already carries the friendly name).
    $xppFileName = [System.IO.Path]::GetFileNameWithoutExtension($xppLine)
    $xppOrgName = ($xppFileName -split '___')[0]
    if ($xppOrgName -ne $Name) {
        $xppVersion = ($xppFileName -split '___')[1]
        $xppDir = Split-Path -Parent $xppLine
        $newJsonName = "${Name}___${xppVersion}.json"
        $newFolderName = "${Name}___${xppVersion}"
        $newJsonPath = Join-Path $xppDir $newJsonName
        $oldFolderPath = Join-Path $xppDir "${xppOrgName}___${xppVersion}"

        # Rename JSON file
        Rename-Item -Path $xppLine -NewName $newJsonName
        Write-Host "  Renamed JSON: $xppOrgName -> $Name"

        # Rename companion folder (if exists)
        if (Test-Path $oldFolderPath) {
            Rename-Item -Path $oldFolderPath -NewName $newFolderName
            Write-Host "  Renamed folder: $xppOrgName -> $Name"
        }

        # Update Description inside JSON (replace org ID with friendly name)
        $raw = [System.IO.File]::ReadAllText($newJsonPath, [System.Text.UTF8Encoding]::new($false))
        $jr = $raw | ConvertFrom-Json
        $jr.Description = $jr.Description -replace [regex]::Escape($xppOrgName), $Name
        $output = ($jr | ConvertTo-Json -Depth 10) -replace ':  ', ': '
        [System.IO.File]::WriteAllText($newJsonPath, $output, [System.Text.UTF8Encoding]::new($false))

        $xppLine = $newJsonPath  # update for downstream use
        Write-UdeLog -LogFile $logFile -Step "rename-config" -Status "OK" -Detail "renamed $xppOrgName -> $Name"
    }

    # Make this the "Current" XPP config via VS's own UI (Extensions > Dynamics 365 >
    # Configure Metadata...). No direct registry writes — VS owns that state. The
    # config now carries the friendly name on disk, so match the row by $Name.
    $selOut = & "$PSScriptRoot\select_current_xpp_config.ps1" -ConfigName $Name -TimeoutSeconds 30
    $selOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "select-config" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Failed to set current XPP config via VS UI" }

    # Update ude-configs.json lastUsed
    Update-UdeLastUsed -Name $Name -Version $ver
    Write-UdeLog -LogFile $logFile -Step "update-cfg" -Status "OK" -Detail "lastUsed + version=$ver"

    Minimize-Vs

    Write-Host ""
    Write-Host "========================================"
    Write-Host "UDE_SWITCH_OK name=$Name version=$ver"
    Write-Host "========================================"
    Write-Host "If VS is still running, restart it to pick up the retargeted ModelStoreFolder."
    Write-UdeLog -LogFile $logFile -Step "done" -Status "OK" -Detail "name=$Name version=$ver"
    exit 0

} catch {
    $msg = $_.Exception.Message
    Write-UdeLog -LogFile $logFile -Step "fail" -Status "FAIL" -Detail $msg
    Write-Host ""
    Write-Host "UDE_SWITCH_FAIL $msg"
    Write-Host "Log: $logFile"
    exit 1
}
