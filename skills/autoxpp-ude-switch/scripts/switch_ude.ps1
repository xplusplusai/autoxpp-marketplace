# switch_ude.ps1 - main orchestrator for UDE switching.
#
# Usage:
#   switch_ude.ps1 -Name <udeName>                 # switch to named UDE
#   switch_ude.ps1 -Name <udeName> -NoDownload     # warn + skip download if version not cached
#   switch_ude.ps1 -Name <udeName> -DownloadPolicy always|ask|skip|skip-if-cached
#   switch_ude.ps1 -Name <udeName> -ManualConfirm  # user switched manually; just update lastUsed/activeEnv
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
    [switch]$ManualConfirm,
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

if ($ManualConfirm) {
    # Manual confirmation mode: user completed the switch outside the skill.
    # Just update lastUsed / activeEnv in ude-configs.json -- no VS interaction.
    if (-not $Name) {
        Write-Host "ERROR: -ManualConfirm requires -Name <udeName>."
        Write-Host "       Usage: switch_ude.ps1 -Name <udeName> -ManualConfirm"
        exit 3
    }
    . "$PSScriptRoot\config_helpers.ps1"
    $mcfg = Load-UdeConfigs
    $mude = $mcfg.udeConfigs | Where-Object { $_.name -eq $Name }
    if (-not $mude) {
        $known = ($mcfg.udeConfigs | ForEach-Object { $_.name }) -join ", "
        Write-Host "ERROR: UDE '$Name' not found. Known UDEs: $known"
        exit 3
    }
    $ver = if ($mude.PSObject.Properties.Name -contains 'lastKnownVersion') { $mude.lastKnownVersion } else { "" }
    Update-UdeLastUsed -Name $Name -Version $ver
    Write-Host ""
    Write-Host "UDE_MANUAL_CONFIRM_OK name=$Name activeEnv=$Name lastUsed=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
    exit 0
}

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
    $cfg  = Invoke-SchemaV4Migration $cfg   # populate tracked fields if upgrading from v3
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

    # Poll for VS menu bar readiness instead of blind-waiting a fixed delay.
    # Extensions (especially Power Platform Tools) load asynchronously after the
    # main IDE shell appears. We poll for the Tools menu item every 10s.
    # VS menu loading is highly variable (especially after config switches) -- can
    # take 5-10+ minutes. Use generous timeout; user decides when to cancel.
    $menuTimeout = if ($reuseFresh) { 60 } else { 600 }
    # Minimum initial delay: VS needs time after Start Window dismissal for extensions
    # to begin loading. Without this, the poll can get a stale UIA tree that shows
    # a "Tools" element from the Start Window context, not the real menu bar.
    $initDelay = if ($reuseFresh) { 5 } else { 15 }
    Write-Host "Waiting ${initDelay}s initial + up to ${menuTimeout}s for VS menu bar (this can take several minutes after config switch)..."
    Start-Sleep -Seconds $initDelay
    $menuDeadline = (Get-Date).AddSeconds($menuTimeout)
    $menuReady = $false
    while ((Get-Date) -lt $menuDeadline) {
        $vsElemCheck = Get-VsAutomationElement -VsPid $freshVs.Id
        if ($vsElemCheck) {
            $miCond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::MenuItem)
            $menuItems = $vsElemCheck.FindAll([System.Windows.Automation.TreeScope]::Descendants, $miCond)
            foreach ($mi in $menuItems) {
                if ($mi.Current.Name -eq 'Tools') { $menuReady = $true; break }
            }
        }
        if ($menuReady) { break }
        $remaining = [math]::Round(($menuDeadline - (Get-Date)).TotalSeconds)
        $elapsed = [math]::Round($menuTimeout - $remaining)
        Write-Host "  Tools menu not ready yet -- extensions still loading (${elapsed}s elapsed, ${remaining}s remaining)..."
        Start-Sleep -Seconds 10
    }
    if ($menuReady) {
        Write-Host "  Tools menu detected - VS is ready."
        Write-UdeLog -LogFile $logFile -Step "menu-wait" -Status "OK" -Detail "menu ready"
    } else {
        Write-Host "  WARNING: Tools menu not detected after ${menuTimeout}s - proceeding anyway (downstream scripts will retry)"
        Write-UdeLog -LogFile $logFile -Step "menu-wait" -Status "WARN" -Detail "timeout ${menuTimeout}s"
    }

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
    $validTimeout = if ($ude.timeouts) { [int]$ude.timeouts.dataverseConnectSeconds } else { 300 }
    Write-Host "Waiting for Dataverse validation + workflow loading (up to ${validTimeout}s)..."
    $vOut = & "$PSScriptRoot\wait_for_validation.ps1" -TimeoutSeconds $validTimeout
    $vOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "validate" -Status "INFO" -Detail $_ }

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

    # Download prompt (may or may not appear) -- non-fatal: VS may not show it at all,
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

    # --- Phase C: post-switch config lifecycle (one config per UDE) ---
    Write-UdeLog -LogFile $logFile -Step "phase-c" -Status "INFO" -Detail "resolving XPP config (v4 lifecycle)"

    # 1. DETECT what VS created by diffing against the Phase A baseline.
    $lkv = if ($ude.ContainsKey('lastKnownVersion')) { $ude.lastKnownVersion } else { "" }
    $diffOut = & "$PSScriptRoot\diff_xppconfig.ps1" -BaselineFile $baselineFile -LastKnownVersion $lkv
    $diffOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "diff" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Could not identify the XPP config VS created" }

    # Parse diff output into variables
    $srcXpp     = ($diffOut | Where-Object { $_ -match '^XPP_JSON: ' })     -replace '^XPP_JSON: ', ''
    $vsOrgName  = ($diffOut | Where-Object { $_ -match '^VS_ORG_NAME: ' })  -replace '^VS_ORG_NAME: ', ''
    $xrefDbName = ($diffOut | Where-Object { $_ -match '^XREF_DB_NAME: ' }) -replace '^XREF_DB_NAME: ', ''
    $newRslFolders    = @($diffOut | Where-Object { $_ -match '^NEW_RSL_FOLDER: ' }    | ForEach-Object { $_ -replace '^NEW_RSL_FOLDER: ', '' })
    $newXppSubfolders = @($diffOut | Where-Object { $_ -match '^NEW_XPP_SUBFOLDER: ' } | ForEach-Object { $_ -replace '^NEW_XPP_SUBFOLDER: ', '' })
    if (-not $srcXpp) { throw "diff_xppconfig did not emit XPP_JSON line" }

    # Version from the VS-generated filename
    $ver = ""
    $m = [regex]::Match([System.IO.Path]::GetFileNameWithoutExtension($srcXpp), '___([\d\.]+)$')
    if ($m.Success) { $ver = $m.Groups[1].Value }

    $xppDir = Get-XppConfigDir
    $rslDir = Get-RuntimeSymLinksDir

    # Read previously tracked fields from ude-configs.json (v4 fields, may be empty on first run)
    $prevXppConfigFile  = Get-UdeTrackedField $ude 'xppConfigFile'
    $prevXppSubfolder   = Get-UdeTrackedField $ude 'xppConfigSubfolder'
    $prevRslFolder      = Get-UdeTrackedField $ude 'runtimeSymLinkFolder'
    $prevXrefDbName     = Get-UdeTrackedField $ude 'xrefDbName'
    $prevVsOrgName      = Get-UdeTrackedField $ude 'vsOrgName'
    $isFirstTime        = [string]::IsNullOrEmpty($prevXppConfigFile)

    # 2. DECIDE: same version, version change, or first-time connect
    $isVersionChange = (-not $isFirstTime) -and $ver -and $lkv -and ($ver -ne $lkv)

    if ($isFirstTime) {
        Write-Host "  First-time connect for $Name"
        Write-UdeLog -LogFile $logFile -Step "lifecycle" -Status "INFO" -Detail "first-time connect"
    } elseif ($isVersionChange) {
        Write-Host "  Version change detected: $lkv -> $ver"
        Write-UdeLog -LogFile $logFile -Step "lifecycle" -Status "INFO" -Detail "version-change old=$lkv new=$ver"
    } else {
        Write-Host "  Same version reconnect: $ver"
        Write-UdeLog -LogFile $logFile -Step "lifecycle" -Status "INFO" -Detail "same-version $ver"
    }

    # 3. Determine our owned config filename
    $ourName = if ($ver) { "${Name}___${ver}.json" } else { "${Name}.json" }
    $xppLine = Join-Path $xppDir $ourName

    # 4. Determine the RuntimeSymLinks folder to own
    # If prevRslFolder is set but the folder no longer exists on disk, clear it
    # so we fall through to scan for a real folder. This handles the case where
    # VS names folders as {orgName}{counter} (e.g. UDE0011) and the owned name
    # (UDE001) was never actually created.
    $ownedRslFolder = $prevRslFolder
    if (-not [string]::IsNullOrEmpty($ownedRslFolder)) {
        $ownedRslPath = Join-Path $rslDir $ownedRslFolder
        if (-not (Test-Path $ownedRslPath)) {
            Write-Host "  Previously tracked RSL folder '$ownedRslFolder' no longer exists on disk - re-scanning"
            $ownedRslFolder = ""
        }
    }
    if ([string]::IsNullOrEmpty($ownedRslFolder)) {
        # Adopt the newest VS-created RSL folder, or scan for existing match
        if ($newRslFolders.Count -gt 0) {
            $ownedRslFolder = $newRslFolders[0]
        } else {
            # Scan for existing folder matching org name or UDE name
            if (Test-Path $rslDir) {
                $rslCandidates = Get-ChildItem -Path $rslDir -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq $Name -or $_.Name -match "^${Name}\d+$" -or
                                   ($vsOrgName -and ($_.Name -eq $vsOrgName -or $_.Name -match "^${vsOrgName}\d+$")) } |
                    Sort-Object LastWriteTime -Descending
                if ($rslCandidates -and @($rslCandidates).Count -gt 0) {
                    $ownedRslFolder = @($rslCandidates)[0].Name
                }
            }
        }
    }
    Write-Host "  Owned RuntimeSymLinks folder: $ownedRslFolder"

    # 5. Determine the XPPConfig subfolder (holds .mdf files) - adopt from VS
    $ownedXppSubfolder = $prevXppSubfolder
    if ($isVersionChange -or $isFirstTime) {
        # On version change or first time, adopt the new subfolder VS created
        if ($newXppSubfolders.Count -gt 0) {
            $ownedXppSubfolder = $newXppSubfolders[0]
        } elseif ($vsOrgName -and $ver) {
            # Construct expected name
            $expected = "${vsOrgName}___${ver}"
            if (Test-Path (Join-Path $xppDir $expected)) {
                $ownedXppSubfolder = $expected
            }
        }
    }

    # 6. Create/update our owned config JSON
    $srcLeaf = Split-Path -Leaf $srcXpp
    if ($srcXpp -ieq $xppLine) {
        Write-Host "  VS used our owned name already: $ourName"
        Write-UdeLog -LogFile $logFile -Step "own-config" -Status "OK" -Detail "vs-named $ourName"
    } elseif (-not $isVersionChange -and (Test-Path $xppLine)) {
        # Same version reconnect: VS may have overwritten its own file; re-apply retargeting to ours
        Write-Host "  Using existing owned config: $ourName"
        Write-UdeLog -LogFile $logFile -Step "own-config" -Status "OK" -Detail "exists $ourName"
    } else {
        # First time or version change: copy VS-generated to our owned name
        Copy-Item -Path $srcXpp -Destination $xppLine -Force
        Write-Host "  Created owned config: $ourName (copied from $srcLeaf)"
        # Cosmetic: replace org ID with friendly name in Description
        $srcOrgPart = ([System.IO.Path]::GetFileNameWithoutExtension($srcXpp) -split '___')[0]
        try {
            $raw = [System.IO.File]::ReadAllText($xppLine, (New-Object System.Text.UTF8Encoding $false))
            $jr  = $raw | ConvertFrom-Json
            if (($jr.PSObject.Properties.Name -contains 'Description') -and $jr.Description) {
                $jr.Description = $jr.Description -replace [regex]::Escape($srcOrgPart), $Name
                $out = ($jr | ConvertTo-Json -Depth 20) -replace ':  ', ': '
                [System.IO.File]::WriteAllText($xppLine, $out, (New-Object System.Text.UTF8Encoding $false))
            }
        } catch { }
        Write-UdeLog -LogFile $logFile -Step "own-config" -Status "OK" -Detail "created $ourName from $srcLeaf"
    }

    # 7. Retarget ModelStoreFolder/DebugSourceFolder/RuntimePackagesDirectory/DefaultCompany
    $company = if ($ude.ContainsKey('defaultCompany')) { $ude.defaultCompany } else { "" }
    $rslFullPath = ""
    if ($ownedRslFolder) {
        $rslFullPath = Join-Path $rslDir $ownedRslFolder
    }
    $rtOut = & "$PSScriptRoot\retarget_xpp_config.ps1" `
        -XppJsonPath $xppLine `
        -MetadataFolder $ude.customMetadataFolder `
        -DefaultCompany $company `
        -RuntimeSymLinkPath $rslFullPath
    $rtOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "retarget" -Status "INFO" -Detail $_ }
    if ($LASTEXITCODE -ne 0) { throw "Retarget failed" }

    # 8. Delete VS-generated config JSON if it differs from our owned one
    if ($srcXpp -and -not ($srcXpp -ieq $xppLine) -and (Test-Path $srcXpp)) {
        Remove-Item -Path $srcXpp -Force -ErrorAction SilentlyContinue
        Write-Host "  Deleted VS-generated config: $srcLeaf (replaced by $ourName)"
        Write-UdeLog -LogFile $logFile -Step "cleanup-vs-json" -Status "OK" -Detail "deleted $srcLeaf"
    }

    # 9. Delete RuntimeSymLinks folders that aren't our owned one
    # Clean up both newly created duplicates AND orphans from previous runs.
    # VS creates {orgName}{counter} folders on each connection (e.g. UDE0011,
    # UDE0012, UDE0013 for orgName=UDE001). Only keep our owned folder.
    if ($ownedRslFolder -and (Test-Path $rslDir)) {
        $rslOrphans = Get-ChildItem -Path $rslDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $ownedRslFolder -and
                           ($_.Name -eq $Name -or $_.Name -match "^${Name}\d+$" -or
                            ($vsOrgName -and ($_.Name -eq $vsOrgName -or $_.Name -match "^${vsOrgName}\d+$"))) }
        foreach ($orphan in $rslOrphans) {
            Remove-Item -Path $orphan.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  Deleted orphaned RuntimeSymLinks folder: $($orphan.Name)"
            Write-UdeLog -LogFile $logFile -Step "cleanup-rsl" -Status "OK" -Detail "deleted $($orphan.Name)"
        }
    }

    # 10. On version change: clean up old version artifacts
    if ($isVersionChange) {
        Write-Host "  Cleaning up old version ($lkv) artifacts..."
        Write-UdeLog -LogFile $logFile -Step "cleanup-old" -Status "INFO" -Detail "cleaning old version $lkv"

        $oldConfigJson  = $prevXppConfigFile
        $oldXppSub      = $prevXppSubfolder
        $oldXrefDb      = $prevXrefDbName

        $cleanOut = & "$PSScriptRoot\cleanup_old_version.ps1" `
            -OldXrefDbName $oldXrefDb `
            -OldXppSubfolder $oldXppSub `
            -OldConfigJson $oldConfigJson `
            -OldRslFolder $prevRslFolder
        $cleanOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "cleanup-old" -Status "INFO" -Detail $_ }

        # Update standardCodebasePath to new version
        $newStdPath = Join-Path (Get-DynamicsRoot) "$ver\PackagesLocalDirectory"
        if (Test-Path $newStdPath) {
            Write-Host "  Updated standardCodebasePath to $newStdPath"
            Write-UdeLog -LogFile $logFile -Step "std-path" -Status "OK" -Detail "standardCodebasePath=$newStdPath"
            # This will be persisted via Update-UdeTrackedFields + Update-UdeLastUsed below
            $cfgForStdPath = Load-UdeConfigs
            $udeForStdPath = $cfgForStdPath.udeConfigs | Where-Object { $_.name -eq $Name }
            if ($udeForStdPath) {
                Set-UdeField $udeForStdPath 'standardCodebasePath' $newStdPath
                Save-UdeConfigs $cfgForStdPath
            }
        }
    }

    # 11. Update tracked fields in ude-configs.json (v4)
    Update-UdeTrackedFields -Name $Name `
        -XppConfigFile $ourName `
        -XppConfigSubfolder $ownedXppSubfolder `
        -RuntimeSymLinkFolder $ownedRslFolder `
        -XrefDbName $xrefDbName `
        -VsOrgName $vsOrgName
    Write-UdeLog -LogFile $logFile -Step "tracked-fields" -Status "OK" -Detail "xppConfigFile=$ourName rslFolder=$ownedRslFolder xrefDb=$xrefDbName vsOrg=$vsOrgName"

    # 12. Make OUR config the active/Current one via VS's own UI (Extensions > Dynamics 365 >
    # Configure Metadata...). No direct registry writes - VS owns that state.
    # If VS freezes on the D365 submenu (observed after Dataverse reconnect), kill it,
    # relaunch fresh, and retry once. Safe because we own the VS session and Phase B is done.
    $selOk = $false
    for ($selAttempt = 1; $selAttempt -le 2; $selAttempt++) {
        Show-Vs
        Start-Sleep -Seconds 1
        $selOut = & "$PSScriptRoot\select_current_xpp_config.ps1" -ConfigName $Name -TimeoutSeconds 60
        $selOut | ForEach-Object { Write-Host "  $_"; Write-UdeLog -LogFile $logFile -Step "select-config" -Status "INFO" -Detail $_ }
        if ($LASTEXITCODE -eq 0) { $selOk = $true; break }

        if ($selAttempt -eq 1) {
            # Check if VS froze
            $selVsProc = Get-Process devenv -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
            $selFrozen = $selVsProc -and -not $selVsProc.Responding
            Write-Host "  Select config failed (attempt 1). VS frozen=$selFrozen - killing and relaunching..."
            Write-UdeLog -LogFile $logFile -Step "select-config" -Status "WARN" -Detail "attempt 1 failed, frozen=$selFrozen, restarting VS"

            # Kill VS
            Get-Process devenv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5

            # Relaunch
            $selRelaunchOut = & "$PSScriptRoot\launch_vs.ps1" -VsPath $vsPath -TimeoutSeconds $launchTimeout
            $selRelaunchOut | ForEach-Object { Write-Host "  $_" }
            if ($LASTEXITCODE -ne 0) { throw "Failed to relaunch VS for select-config retry" }

            # Dismiss Start Window + wait for menu readiness
            $null = & "$PSScriptRoot\dismiss_start_window.ps1" -TimeoutSeconds 60
            Write-Host "  Waiting for VS menu bar after relaunch (can take several minutes)..."
            Start-Sleep -Seconds 15
            $selRetryDeadline = (Get-Date).AddSeconds(600)
            $selMenuFound = $false
            while ((Get-Date) -lt $selRetryDeadline) {
                $selVsElem = Get-VsAutomationElement
                if ($selVsElem) {
                    $selMiCond = New-Object System.Windows.Automation.PropertyCondition(
                        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                        [System.Windows.Automation.ControlType]::MenuItem)
                    $selMenuItems = $selVsElem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $selMiCond)
                    foreach ($selMi in $selMenuItems) {
                        if ($selMi.Current.Name -eq 'Tools') { $selMenuFound = $true; break }
                    }
                }
                if ($selMenuFound) { break }
                Start-Sleep -Seconds 10
            }
            Write-Host "  VS relaunched (menu ready=$selMenuFound) - retrying select config..."

            # Re-run retarget: VS overwrites the XPP config on relaunch,
            # undoing our RuntimePackagesDirectory/ModelStoreFolder changes.
            # The owned RSL folder may also have changed if VS created a new one.
            $postRestartRsl = ""
            if ($ownedRslFolder) {
                $postRestartRsl = Join-Path $rslDir $ownedRslFolder
                # VS may have created a new RSL folder on relaunch -- adopt it if ours is gone
                if (-not (Test-Path $postRestartRsl) -and (Test-Path $rslDir)) {
                    $newCandidates = Get-ChildItem -Path $rslDir -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq $Name -or $_.Name -match "^${Name}\d+$" -or
                                       ($vsOrgName -and ($_.Name -eq $vsOrgName -or $_.Name -match "^${vsOrgName}\d+$")) } |
                        Sort-Object LastWriteTime -Descending
                    if ($newCandidates -and @($newCandidates).Count -gt 0) {
                        $ownedRslFolder = @($newCandidates)[0].Name
                        $postRestartRsl = Join-Path $rslDir $ownedRslFolder
                        Write-Host "  Adopted new RSL folder after restart: $ownedRslFolder"
                    }
                }
            }
            Write-Host "  Re-applying retarget after VS restart..."
            $rtOut2 = & "$PSScriptRoot\retarget_xpp_config.ps1" `
                -XppJsonPath $xppLine `
                -MetadataFolder $ude.customMetadataFolder `
                -DefaultCompany $company `
                -RuntimeSymLinkPath $postRestartRsl
            $rtOut2 | ForEach-Object { Write-Host "    $_"; Write-UdeLog -LogFile $logFile -Step "retarget-post-restart" -Status "INFO" -Detail $_ }
            Write-UdeLog -LogFile $logFile -Step "retarget-post-restart" -Status "OK" -Detail "re-applied after VS restart"
        }
    }
    if (-not $selOk) { throw "Failed to set current XPP config via VS UI (after restart retry)" }

    # 12b. Strip UTF-8 BOM from all XPP config JSONs
    # VS adds BOM (EF BB BF) when it rewrites configs to save IsCurrent.
    # On next restart, VS fails to parse BOM'd JSON and the config dialog shows empty.
    # VS writes asynchronously -- wait for it to finish, then strip. Retry to catch
    # late writes (VS may rewrite multiple configs when toggling Current on one).
    $totalBomCount = 0
    for ($bomPass = 1; $bomPass -le 3; $bomPass++) {
        if ($bomPass -eq 1) {
            Start-Sleep -Seconds 5
        } else {
            Start-Sleep -Seconds 3
        }
        $bomCount = 0
        Get-ChildItem "$xppDir\*.json" -ErrorAction SilentlyContinue | ForEach-Object {
            $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                [System.IO.File]::WriteAllBytes($_.FullName, $bytes[3..($bytes.Length - 1)])
                Write-Host "  Stripped BOM from $($_.Name) (pass $bomPass)"
                $bomCount++
            }
        }
        $totalBomCount += $bomCount
        if ($bomCount -eq 0) { break }
    }
    if ($totalBomCount -gt 0) {
        Write-UdeLog -LogFile $logFile -Step "bom-strip" -Status "OK" -Detail "stripped BOM from $totalBomCount config(s) across $bomPass pass(es)"
    }

    # 13. Verify: confirm exactly one config exists for this UDE name
    $allConfigs = Get-ChildItem -Path $xppDir -Filter "${Name}___*.json" -ErrorAction SilentlyContinue
    if (@($allConfigs).Count -gt 1) {
        Write-Host "  WARNING: Multiple configs found for $Name -- expected exactly one:"
        $allConfigs | ForEach-Object { Write-Host "    $($_.Name)" }
        Write-UdeLog -LogFile $logFile -Step "verify" -Status "WARN" -Detail "multiple configs for ${Name}: $(@($allConfigs).Count)"
    } else {
        Write-UdeLog -LogFile $logFile -Step "verify" -Status "OK" -Detail "single config confirmed for $Name"
    }

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
