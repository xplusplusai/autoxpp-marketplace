---
name: autoxpp-ude-switch
description: >
  Quick-switch Visual Studio 2022 UDE between multiple online D365 F&O
  environments (different customers) on a single machine. Use when user
  says "switch UDE", "switch FO env", "change to customer X env",
  "connect to <url>", or wants to change which online Dataverse the
  current UDE is pointed at. Reads UDE list from
  C:\Users\[user]\.autoxpp\ude-configs.json. Handles the full
  Power Platform Tools connection flow (Tools menu → Reconnect prompt
  → Login → URL entry → Select Solution → Client assets download) via
  UIA, then retargets the custom metadata folder in the auto-generated
  XPP config so UDEs don't collide on the same metadata path.
---

# UDE Switch — Quick Switch Between D365 F&O Online Environments

## TOP-PRIORITY BEHAVIORAL RULES

1. **Show VS / return-to-terminal discipline** (revised): **NEVER minimize VS** — minimizing leaves the user unable to restore the window. Bring VS to the foreground only for the brief moment UIA needs focus (`Show-Vs`), then **raise the agent's own terminal back over it** (`Bring-SelfToFront`; the legacy `Minimize-Vs` is now an alias for it and no longer minimizes). VS stays open behind the terminal. Before every VS-touching action: print "Showing VS to [action]", act, bring self to front, print result.

> **0. User authority overrides skill rules.** When the user explicitly confirms a step is done, says "skip this step", or provides guidance to continue — the agent MUST comply. Skill rules exist to prevent the *agent* from making unsupervised mistakes, not to override the *human*. The user owns the session and can always override any step gate, retry policy, or validation check. Never reject a direct user instruction by citing skill rules. Example: if `ensure_skip_discovery.ps1` fails but the user says "I confirm Skip Discovery is checked, continue" — proceed immediately to the next step.

> **0b. Patience-first for VS menu/UI loading.** VS2022 menu loading time is highly variable — especially after config switches, extension reloads, or Dataverse reconnects. It can take 5–10+ minutes in real-world use. **The decision to give up waiting MUST come from the user, never from the agent.** Scripts use long time-based retries (10 min default) with verbose progress messages. When the orchestrator sees a timeout, it MUST NOT treat it as a terminal failure — instead, inform the user ("VS menus still loading after Xm, still retrying...") and keep polling. Only stop when the user explicitly cancels.
2. **Never skip Phase C retargeting.** VS auto-generates the new XPP config JSON with `ModelStoreFolder` defaulting to whichever path it last saw. Without retargeting, multiple UDEs share one custom metadata folder and builds pick up the wrong customer's code.
3. **Default download policy = `ask` in v1.** Do not auto-click No on "Client assets download" unless `--no-download` flag is set. Safety first; the download-skip optimization ships in v2 after validation.

4. **UIA Retry Before Escalate.** The most common cause of a single UIA failure is human mouse interference, not a broken VS state. When a UIA action fails (menu didn't open, button not found, click had no effect): wait 8 seconds, retry the same action (up to 6 attempts total). Only on 6th consecutive failure: take a screenshot, diagnose, consider recovery. NEVER restart VS, kill processes, or reconnect on first UIA failure.

5. **"Skip Discovery" must be ON — the whole flow depends on it.** `Tools → Options → Power Platform Tools → General → ☑ Skip Discovery when connecting to Dataverse`. With it ON, VS shows the **"Enter environment instance url"** popup that `handle_url_popup.ps1` fills. With it OFF, that popup never appears and the switch cannot target a specific environment. Verify it is checked before connecting (the `ensure_skip_discovery.ps1` pre-flight enforces this).

6. **Always start from a fresh VS session — never reuse an open VS.** If VS already has a Dataverse connection it auto-reconnects and **skips** the instance-URL popup, silently keeping the old environment. So if `devenv` is already running, `switch_ude.ps1` exits **2**; the orchestrator must get the user's **explicit approval** (this skill is interactive, not autonomous, and unsaved VS work can be lost), then re-run with **`-CloseExisting`**, which closes VS and launches fresh.

---

## Overview

Switches Visual Studio 2022 UDE from one online D365 F&O environment to another, using a JSON config file to track known UDEs. Main flow is three phases:

- **Phase A (pre-flight)**: Load config, run schema v4 migration if needed, snapshot XPPConfig + RuntimeSymLinks folder state, decide download policy.
- **Phase B (UIA)**: Handle existing VS → Launch → Dismiss Start Window → Ensure Skip Discovery → Close solution → Tools → Connect to online Dataverse → Reconnect-No → Login → URL → Wait for validation → Select Solution → Download-prompt.
- **Phase C (post-switch, v4 config lifecycle)**: Detect VS-created artifacts (config JSON, RuntimeSymLinks folder, XPPConfig subfolder, XRef DB name, org ID). Decide: first-time connect / same-version reconnect / version change. Create or update owned config `{name}___{version}.json`, retarget `ModelStoreFolder` + `DebugSourceFolder` + `RuntimePackagesDirectory`, delete VS-generated duplicates, clean up old version artifacts on version change (detach XRef DB, delete old subfolder/config/RSL folder), update tracked fields in `ude-configs.json`, set as Current via VS UI, verify single config per UDE.

## Invocation

```
/autoxpp-ude-switch                  → interactive picker (arrow select)
/autoxpp-ude-switch <name>           → switch to named UDE
/autoxpp-ude-switch --current        → show current active UDE
/autoxpp-ude-switch --list           → list configured UDEs
/autoxpp-ude-switch --add            → interactive add flow
/autoxpp-ude-switch <name> --no-download     → skip metadata download (warn)
/autoxpp-ude-switch <name> --close-existing  → if VS2022 is already open, close it first, then switch (fresh session)
/autoxpp-ude-switch <name> --manual-confirm  → user completed switch manually; just update lastUsed/activeEnv
```

## Prerequisites (one-time per machine, NOT automated)

> **PowerShell:** scripts run on **PowerShell 7 (`pwsh`, preferred) or Windows PowerShell 5.1** — they are ASCII-only with no PS7-only syntax. The entry-point invokes `pwsh`; if `pwsh` is absent the host may fall back to `powershell` 5.1, which now also works.

1. Visual Studio 2022 installed (Professional or Enterprise)
2. Power Platform Tools for VS 2022 extension installed
3. `Tools → Options → Power Platform Tools → Skip Discovery when connecting to Dataverse` checked (auto-enforced by `ensure_skip_discovery.ps1` if unchecked)
4. At least one UDE reachable and user has access
5. Windows account signed into the tenant (WAM handles auth transparently)

If prerequisites are missing, skill surfaces an error with install guidance.

## Config file

**Path:** `C:\Users\[user]\.autoxpp\ude-configs.json`

See `reference/config-schema.md` for the schema and field semantics.

Minimum required per UDE: `name`, `dataverseUrl`, `customMetadataFolder`. Everything else is optional — connection settings (`solutionName`, `msAccount`, `downloadPolicy`) are per-UDE and fall back to code defaults; other fields (`foUrl`, `moduleName`, `oauth`, `login`, `sqlCache`) are owned by other skills and preserved untouched.

## Scripts

All scripts live in `scripts/` and follow the established autoxpp-* pattern:
- PowerShell (`.ps1`) for UIA and filesystem work on Windows
- UTF-8 output
- Structured logging via `Write-UdeLog` in `config_helpers.ps1`
- Emit tagged status lines (`UDE_SWITCH_OK`, `UDE_SWITCH_FAIL`, etc.) for the main channel

**Use existing scripts only.** The agent MUST invoke the scripts listed below by their file path — never generate new PowerShell scripts inline or write ad-hoc `.ps1` files to disk. Every UDE operation is already covered by the script inventory. If a script doesn't exist for the operation, that operation is out of scope for this skill.

### Entry point

```powershell
pwsh "scripts/switch_ude.ps1" -Name "<env-name>"
pwsh "scripts/switch_ude.ps1" -Name "<env-name>" -CloseExisting   # caller-approved: close an already-open VS, then switch
pwsh "scripts/switch_ude.ps1" -Name "<env-name>" -DownloadPolicy always|ask|skip|skip-if-cached
pwsh "scripts/switch_ude.ps1" -Current
pwsh "scripts/switch_ude.ps1" -List
pwsh "scripts/switch_ude.ps1" -Add
```

**`-CloseExisting` (skill option `--close-existing`):** by default, if VS2022 is already open the switch stops with **exit 2** so the orchestrator can get the user's approval (closing VS can lose unsaved work). Pass `-CloseExisting` when closing has already been approved — it closes the open session and starts fresh without the exit-2 round-trip. Use it for automation; omit it for interactive safety.

### Script inventory

| Script | Purpose |
|---|---|
| `switch_ude.ps1` | Main orchestrator (Phase A/B/C) |
| `uia_helpers.ps1` | Shared UIA primitives (dot-sourced by all dialog handlers) |
| `config_helpers.ps1` | Load/save shared `ude-configs.json` (stamps schemaVersion 3, BOM-less) + resolve a UDE entry (dot-sourced) |
| `list_udes.ps1` | Print configured UDE list with last-used info |
| `show_current_ude.ps1` | Detect active UDE from XPPConfig folder + `lastUsed` |
| `add_ude.ps1` | Interactive add flow (prompts, writes JSON) |
| `launch_vs.ps1` | Start VS 2022 if not running; wait for main window |
| `dismiss_start_window.ps1` | Dismiss VS Start Window + undocumented modal dialogs so menu bar is usable |
| `ensure_skip_discovery.ps1` | Verify Tools → Options → Power Platform Tools → "Skip Discovery" is checked |
| `close_open_solution.ps1` | UIA: File → Close Solution (if any open) |
| `open_connect_dataverse_menu.ps1` | UIA: Tools → Connect to online Dataverse |
| `handle_reconnect_dialog.ps1` | UIA: click No on "Reconnect to Dataverse" |
| `handle_login_dialog.ps1` | UIA: click Login on Power Platform Tools Login |
| `handle_url_popup.ps1` | UIA: type `dataverseUrl` + click OK |
| `wait_for_validation.ps1` | UIA: poll for Validating / Loading states |
| `handle_select_solution.ps1` | UIA: pick `solutionName` + click Done |
| `handle_download_prompt.ps1` | UIA: read version, decide Yes/No, click |
| `wait_for_vs_exit.ps1` | Poll VS process until it exits (after client assets download) or timeout |
| `retarget_xpp_config.ps1` | Overwrite `ModelStoreFolder`/`DebugSourceFolder` in new XPP JSON |
| `select_current_xpp_config.ps1` | UIA: Extensions → Dynamics 365 → Configure Metadata, set target config as Current |
| `snapshot_xppconfig.ps1` | Baseline snapshot of `XPPConfig\` folder |
| `diff_xppconfig.ps1` | Identify newly created JSON file after switch |

## Flow summary (happy path)

```
Phase A — pre-flight (disk only)
 1. Load ude-configs.json → resolve {name} entry, decide download policy
 2. Ensure customMetadataFolder exists (create if missing)
 3. Snapshot XPPConfig baseline

Phase B — VS interaction (UIA)
 4. Handle existing VS: reuse fresh PID sentinel, or exit 2 for approval / close with -CloseExisting
 5. Launch VS (launch_vs.ps1) — wait for MainWindowHandle
 6. Dismiss Start Window + undocumented modal dialogs (dismiss_start_window.ps1)
 7. Ensure "Skip Discovery" is ON (ensure_skip_discovery.ps1 — Tools > Options)
 8. Close any open solution (close_open_solution.ps1)
 9. Tools → Connect to online Dataverse (open_connect_dataverse_menu.ps1)
10. Click No on Reconnect dialog (handle_reconnect_dialog.ps1)
11. Click Login on Power Platform Tools Login dialog (handle_login_dialog.ps1)
12. Type dataverseUrl + OK on URL popup (handle_url_popup.ps1)
13. Wait for Dataverse validation + workflow loading (wait_for_validation.ps1)
14. Select solutionName on "Select Solution" dialog, click Done (handle_select_solution.ps1)
15. On "Client assets download" prompt (handle_download_prompt.ps1):
    - if version cached AND policy != "always" → click No
    - else → click Yes, monitor progress
16. If download triggered → wait for VS exit (wait_for_vs_exit.ps1) → relaunch if exited

Phase C — post-switch config lifecycle (one config per UDE, schemaVersion 4)
17. Diff XPPConfig + RuntimeSymLinks to detect VS-created artifacts (diff_xppconfig.ps1)
    → emits: XPP_JSON, VS_ORG_NAME, XREF_DB_NAME, NEW_RSL_FOLDER, NEW_XPP_SUBFOLDER
18. Decide: first-time connect / same-version reconnect / version change
19. Create/update owned {name}___{version}.json (copy from VS-generated, cosmetic rename)
20. Retarget ModelStoreFolder + DebugSourceFolder + RuntimePackagesDirectory (retarget_xpp_config.ps1)
21. Delete VS-generated config JSON (replaced by owned copy)
22. Delete VS-generated duplicate RuntimeSymLinks folders (keep tracked one)
23. On version change: cleanup old artifacts (cleanup_old_version.ps1)
    → detach old XRef DB, delete old XPPConfig subfolder + config JSON
    → update standardCodebasePath to new platform version
24. Update tracked fields in ude-configs.json (xppConfigFile, xppConfigSubfolder,
    runtimeSymLinkFolder, xrefDbName, vsOrgName)
25. Set owned config as Current via VS UI (select_current_xpp_config.ps1)
26. Verify: exactly one config exists for this UDE name
27. Update lastUsed + lastKnownVersion in ude-configs.json
28. Report UDE_SWITCH_OK
```

## Error handling

Common failures:
- Config name not found → list known names
- VS not installed → fail with guidance
- Validation timeout → Dataverse slow or unreachable
- Download stall (no output for 2 min) → warn, offer cancel

## Failure Recovery Rules (for the AI orchestrator)

When `switch_ude.ps1` exits non-zero, the AI MUST follow these rules — NOT improvise workarounds.

### Rule F-1: NEVER go off-script

Do NOT manually invoke UIA, DTE COM, keybd_event, registry writes, or any ad-hoc PowerShell to work around a script failure. The scripts are the only authorized way to interact with VS. If a script fails after its built-in retries, report the failure to the user.

### Rule F-2: Phase C is gated on Phase B completion

If `switch_ude.ps1` exits 1, do NOT manually run Phase C scripts (`diff_xppconfig.ps1`, `retarget_xpp_config.ps1`, `select_current_xpp_config.ps1`). Phase C assumes Phase B completed successfully. Running Phase C after a partial Phase B can leave VS in a corrupt state (frozen, metadata errors).

### Rule F-3: On exit code 1, report and follow up with manual-confirm

Report the failure to the user with the log file path. Do NOT retry the entire switch unless the user explicitly asks. The user may need to:
- Kill a frozen VS manually
- Check Power Platform Tools extension installation

**User override:** If the user confirms the failed step is actually fine (e.g., "Skip Discovery is checked, I can see it") or says "continue" / "skip this step", proceed to the next step. The user's eyes on the screen outrank a script's exit code.

**MANDATORY follow-up:** After reporting the failure, ALWAYS ask the user whether they completed (or will complete) the switch manually. Then follow Rule F-6 (Manual Switch Confirmation). Never end the conversation after an exit-1 without confirming config state.

### Rule F-4: On exit code 2, get approval and re-run — or manual-confirm

Exit 2 means user input is needed (VS already open). Get the specific approval, then re-run with the appropriate flag (`-CloseExisting` for VS already open). Do NOT try alternative approaches.

**If the user declines the re-run** (e.g., "I'll do it myself", "skip it", "I already switched"), follow Rule F-6 (Manual Switch Confirmation) immediately.

### Rule F-5: VS freeze after switch

If VS becomes unresponsive (Responding=False) after a switch attempt, report it to the user. The user must kill VS manually or approve killing it. Do NOT attempt to drive a frozen VS with UIA — it will not respond and may corrupt further.

**After the freeze is resolved**, follow Rule F-6 — the switch may have partially completed, so the config still needs updating.

### Rule F-6: Manual Switch Confirmation (MANDATORY after any non-zero exit)

**This rule is the safety net that prevents `ude-configs.json` from going stale.** It fires after ANY non-zero exit from `switch_ude.ps1`, and also when the user reports a manual switch without invoking the skill at all.

**The AI orchestrator MUST follow this sequence:**

1. **Ask if the switch was completed manually.**
   > "The automated switch didn't finish. Did you complete the UDE switch manually in VS?"
   
   If the script got partway through Phase B (e.g., connected to Dataverse, but failed on metadata config selection) and the user was offered a manual fallback — the answer is likely yes. Ask regardless.

2. **If yes → present the UDE list for confirmation.** Read `ude-configs.json` and show the configured UDE names:
   ```
   Which UDE did you switch to?
   1. UDE001
   2. UDE002
   3. UDE003
   ```
   If the target UDE is obvious from context (e.g., the user originally asked to switch to UDE003 and confirms they completed it), skip the picker and confirm: "You switched to UDE003 — correct?"

3. **On confirmation → run manual-confirm** to update `lastUsed` and `activeEnv`:
   ```powershell
   pwsh "scripts/switch_ude.ps1" -Name "<confirmed-name>" -ManualConfirm
   ```

4. **Report the update.** Confirm to the user: "Updated activeEnv to `<name>` and stamped lastUsed."

5. **If no → leave config as-is.** The user didn't switch. No update needed.

**Trigger conditions** — the AI MUST enter this flow when ANY of these occur:
- `switch_ude.ps1` exits non-zero (exit 1, 2, or 3) — **always** follow up, even if the failure seems unrelated to the switch itself
- The user says they switched UDE manually (without the skill being invoked at all)
- The user says "I did it", "it's done", "already switched", "I selected it manually" after a failed or partial switch attempt
- The AI offered a manual fallback option during the switch and the user took it

**Never silently end after a failed switch.** The whole point of `lastUsed`/`activeEnv` is to keep `ude-configs.json` in sync with reality. A manual switch that doesn't update the config causes downstream skills (build, dev-v2, lifecycle) to target the wrong environment. The AI's job is to ensure the config reflects reality — even when the scripts can't do it themselves.

## Logging

All steps append to `C:\Users\[user]\.autoxpp\logs\ude-switch-{timestamp}.log` via `Write-UdeLog` in `config_helpers.ps1`. Line format:
```
<ISO-timestamp>  [ude-switch]  <STATUS>  <step>  <detail>
```

## Testing

After install, test by:
1. `/autoxpp-ude-switch --list` → should show `<env-name>`
2. `/autoxpp-ude-switch --current` → should show current (if that UDE is connected)
3. `/autoxpp-ude-switch <env-name>` → should complete full switch (cached, no download)
4. Add a second UDE, switch back and forth

## See also

- `reference/config-schema.md` — ude-configs.json schema reference
- `reference/dialogs.md` — UIA selector reference per dialog
- `autoxpp-build` — shared UIA patterns and Show/Hide VS discipline
