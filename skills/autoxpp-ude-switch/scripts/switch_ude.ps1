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
    [switch]$CloseExisting,
    [ValidateSet('','always','ask','skip','skip-if-cached')]
    [string]$DownloadPolicy = ''
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\config_helpers.ps1"
. "$PSScriptRoot\uia_helpers.ps1"   # Show-Vs / Bring-SelfToFront (Minimize-Vs alias) are called directly below

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

    # Ensure the metadata folder from ude-configs.json exists (create if missing).
    # This is the ModelStoreFolder we retarget the active config to in Phase C.
    if (-not (Test-Path $ude.customMetadataFolder)) {
        New-Item -ItemType Directory -Path $ude.customMetadataFolder -Force | Out-Null
        Write-UdeLog -LogFile $logFile -Step "metadata-create" -Status "OK" -Detail "created: $($ude.customMetadataFolder)"
        Write-Host "Created customMetadataFolder: $($ude.customMetadataFolder)"
        Write-Host "  (empty - clone the repo here before building)"
    }

    # Snapshot XPPConfig
    $baselineFile = Join-Path (Split-Path -Parent $logFile) "xpp-baseline-$Name.txt"
    & "$PSScriptRoot\snapshot_xppconfig.ps1" | Set-Content -Path $baselineFile -Encoding UTF8
    Write-UdeLog -LogFile $logFile -Step "snapshot" -Status "OK" -Detail "baseline=$baselineFile"

    # --- Phase B: VS interaction ---
    Write-UdeLog -LogFile $logFile -Step "phase-b" -Status "INFO" -Detail "VS interaction"

    # Never operate on a PRE-EXISTING VS session: if VS already has a Dataverse
    # connection it auto-reconnects and SKIPS the "Enter environment instance url"
    # popup, so the switch would silently keep the old environment. We must start
    # from a fresh VS session. Closing VS can lose unsaved work, so closing a
    # pre-existing instance requires explicit user approval via -CloseExisting.
    #
    # Idempotent (P-8): if the VS already running is the fresh one WE launched
    # earlier in this same operation (tracked by a recent PID sentinel), reuse it
    # instead of closing+relaunching again. This avoids needless restarts and the
    # skipped re-approval seen when the script is retried after a partial failure.
    $freshPidFile = Join-Path (Get-UdeLogDir) "fresh-vs.pid"
    $ourFreshPid  = ""
    if (Test-Path $freshPidFile) {
        $ageMin = ((Get-Date) - (Get-Item $freshPidFile).LastWriteTime).TotalMinutes
        if ($ageMin -lt 20) { $ourFreshPid = (Get-Content -Raw $freshPidFile).Trim() }
    }

    $existingVs = @(Get-Process devenv -ErrorAction SilentlyContinue)
    $reuseFresh = ($existingVs.Count -gt 0 -and $ourFreshPid -and
                   ($existingVs | Where-Object { "$($_.Id)" -eq $ourFreshPid }))

    if ($reuseFresh) {
        Write-Host "Reusing the fresh VS we launched earlier (pid=$ourFreshPid) - no restart needed."
        Write-UdeLog -LogFile $logFile -Step "vs-reuse" -Status "OK" -Detail "reuse fresh pid=$ourFreshPid"
    }
    elseif ($existingVs.Count -gt 0) {
        if (-not $CloseExisting) {
            Write-Host "VS_ALREADY_OPEN: Visual Studio 2022 is already running ($($existingVs.Count) process(es))."
            Write-Host "  A live Dataverse connection makes VS skip the instance-URL step, so the"
            Write-Host "  switch must start from a fresh VS session. Closing VS may lose unsaved work."
            Write-Host "  Get the user's approval, then re-run with -CloseExisting."
            Write-UdeLog -LogFile $logFile -Step "vs-open" -Status "WAIT" -Detail "approval needed to close existing VS ($($existingVs.Count))"
            exit 2
        }
        Write-Host "Closing existing VS2022 session(s) (user-approved)..."
        Remove-Item $freshPidFile -ErrorAction SilentlyContinue
        foreach ($p in $existingVs) { try { $p.CloseMainWindow() | Out-Null } catch {} }
        Start-Sleep -Seconds 5
        $still = @(Get-Process devenv -ErrorAction SilentlyContinue)
        if ($still.Count -gt 0) {
            Write-Host "  Graceful close timed out; forcing $($still.Count) process(es)..."
            $still | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
        Write-UdeLog -LogFile $logFile -Step "vs-close" -Status "OK" -Detail "closed existing VS; starting fresh"
    }

    # Launch a fresh VS session (no-op if we are reusing one already running)
    $vsPath = if ($ude.ContainsKey('vsPath')) { $ude.vsPath } else { "" }
    $launchTimeout = if ($ude.timeouts) { [int]$ude.timeouts.vsRestartSeconds } else { 120 }

    $launchResult = & "$PSScriptRoot\launch_vs.ps1" -VsPath $vsPath -TimeoutSeconds $launchTimeout
    Write-UdeLog -LogFile $logFile -Step "launch-vs" -Status "OK" -Detail "$launchResult"
    if ($LASTEXITCODE -ne 0) { throw "Failed to launch VS" }

    # Record the fresh VS PID so a retry reuses it instead of restarting (P-8).
    $freshVs = Get-Process devenv -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if ($freshVs) { Set-Content -Path $freshPidFile -Value $freshVs.Id -Encoding ASCII }

    # Get a freshly-launched VS past its Start Window / startup dialogs so the menu
    # bar exists for the steps below (P-4). No-op if VS is already at the main IDE.
    $swOut = & "$PSScriptRoot\dismiss_start_window.ps1" -TimeoutSeconds 60
    $swOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "start-window" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "VS Start Window could not be dismissed (no menu bar available)" }

    # Ensure "Skip Discovery" is ON - required for the "Enter environment instance url"
    # popup to appear during connect (Tools > Options > Power Platform Tools > General).
    Write-Host "Showing VS to verify 'Skip Discovery' option..."
    $sdOut = & "$PSScriptRoot\ensure_skip_discovery.ps1" -TimeoutSeconds 30
    $sdOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "skip-discovery" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Failed to ensure 'Skip Discovery' is enabled" }

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
    if ($LASTEXITCODE -ne 0) { throw "Validation timed out - Dataverse not responding" }

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

    # Download prompt (may or may not appear) — non-fatal: VS may not show it at all,
    # or it may time out. Either way Phase C should still run since connect succeeded.
    Write-Host "Waiting for Client assets download prompt (policy=$policy)..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $dlOut = & "$PSScriptRoot\handle_download_prompt.ps1" -Policy $policy -TimeoutSeconds 90 2>&1
    $dlExitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    $dlOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "dl-prompt" -Status "INFO" -Detail $_ }
    if ($dlExitCode -ne 0) {
        Write-Host "  Download prompt: exited $dlExitCode (non-fatal, proceeding to Phase C)"
        Write-UdeLog -LogFile $logFile -Step "dl-prompt" -Status "WARN" -Detail "non-fatal exit $dlExitCode"
    }

    $downloadTriggered = ($dlOut -join "`n") -match 'choice=Yes'
    if ($downloadTriggered) {
        Write-Host "Download started. This typically takes ~20 minutes for a new platform version."
        Write-Host "VS may auto-exit after completion - skill will relaunch it."

        $vs = Get-Process devenv -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
        $dlTimeout = if ($ude.timeouts) { [int]$ude.timeouts.metadataDownloadSeconds } else { 3600 }

        $exitOut = & "$PSScriptRoot\wait_for_vs_exit.ps1" -VsPid $vs.Id -TimeoutSeconds $dlTimeout
        $exitOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "dl-wait" -Status "INFO" -Detail $_ }

        if ($exitOut -match 'VS_EXITED') {
            Write-Host "VS exited - waiting 15s for extension registration, then relaunching..."
            Start-Sleep -Seconds 15
            $relaunch = & "$PSScriptRoot\launch_vs.ps1" -VsPath $vsPath -TimeoutSeconds $launchTimeout
            $relaunch | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "vs-relaunch" -Status "INFO" -Detail $_ }
        }
    }

    # --- Phase C: post-switch disk edits ---
    Write-UdeLog -LogFile $logFile -Step "phase-c" -Status "INFO" -Detail "resolving XPP config"

    # Identify the config VS just created/updated by diffing the XPPConfig folder
    # against the Phase A baseline - name-agnostic (VS may name it by org ID or by
    # display name; we don't care which). This is the source with the correct
    # FrameworkDirectory / RuntimePackagesDirectory for this environment.
    $lkv = if ($ude.ContainsKey('lastKnownVersion')) { $ude.lastKnownVersion } else { "" }
    $diffOut = & "$PSScriptRoot\diff_xppconfig.ps1" -BaselineFile $baselineFile -LastKnownVersion $lkv
    $diffOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "diff" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Could not identify the XPP config VS created" }

    $srcXpp = ($diffOut | Where-Object { $_ -match '^XPP_JSON: ' }) -replace '^XPP_JSON: ', ''
    if (-not $srcXpp) { throw "diff_xppconfig did not emit XPP_JSON line" }

    # Version comes from the file VS created.
    $ver = ""
    $m = [regex]::Match([System.IO.Path]::GetFileNameWithoutExtension($srcXpp), '___([\d\.]+)$')
    if ($m.Success) { $ver = $m.Groups[1].Value }

    # We own ONLY {UDE}___{ver}.json. Never rename or delete files VS made.
    # If our file doesn't exist yet, create it by copying the VS-created one.
    $xppDir  = Split-Path -Parent $srcXpp
    $ourName = if ($ver) { "${Name}___${ver}.json" } else { "${Name}.json" }
    $xppLine = Join-Path $xppDir $ourName

    if ($srcXpp -ieq $xppLine) {
        Write-Host "  VS used our name already: $ourName"
        Write-UdeLog -LogFile $logFile -Step "own-config" -Status "OK" -Detail "vs-named $ourName"
    } elseif (Test-Path $xppLine) {
        Write-Host "  Using existing owned config: $ourName"
        Write-UdeLog -LogFile $logFile -Step "own-config" -Status "OK" -Detail "exists $ourName"
    } else {
        Copy-Item -Path $srcXpp -Destination $xppLine -Force
        Write-Host "  Created owned config: $ourName (copied from $(Split-Path -Leaf $srcXpp))"
        # Cosmetic: point the Description at the friendly name for the dialog.
        $srcLeaf = ([System.IO.Path]::GetFileNameWithoutExtension($srcXpp) -split '___')[0]
        try {
            $raw = [System.IO.File]::ReadAllText($xppLine, (New-Object System.Text.UTF8Encoding $false))
            $jr  = $raw | ConvertFrom-Json
            if (($jr.PSObject.Properties.Name -contains 'Description') -and $jr.Description) {
                $jr.Description = $jr.Description -replace [regex]::Escape($srcLeaf), $Name
                $out = ($jr | ConvertTo-Json -Depth 20) -replace ':  ', ': '
                [System.IO.File]::WriteAllText($xppLine, $out, (New-Object System.Text.UTF8Encoding $false))
            }
        } catch { }
        Write-UdeLog -LogFile $logFile -Step "own-config" -Status "OK" -Detail "created $ourName from $(Split-Path -Leaf $srcXpp)"
    }

    # Retarget ModelStoreFolder/DebugSourceFolder (+DefaultCompany) in OUR config to
    # the customMetadataFolder from ude-configs.json.
    $company = if ($ude.ContainsKey('defaultCompany')) { $ude.defaultCompany } else { "" }
    $rtOut = & "$PSScriptRoot\retarget_xpp_config.ps1" `
        -XppJsonPath $xppLine `
        -MetadataFolder $ude.customMetadataFolder `
        -DefaultCompany $company
    $rtOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "retarget" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Retarget failed" }

    # Make OUR config the active/Current one via VS's own UI (Extensions > Dynamics 365 >
    # Configure Metadata...). No direct registry writes - VS owns that state.
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
    Remove-Item (Join-Path (Get-UdeLogDir) "fresh-vs.pid") -ErrorAction SilentlyContinue  # clear fresh-VS sentinel on success (P-8)
    exit 0

} catch {
    $msg = $_.Exception.Message
    Write-UdeLog -LogFile $logFile -Step "fail" -Status "FAIL" -Detail $msg
    Write-Host ""
    Write-Host "UDE_SWITCH_FAIL $msg"
    Write-Host "Log: $logFile"
    exit 1
}
