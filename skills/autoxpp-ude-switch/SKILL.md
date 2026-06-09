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
2. **Never skip Phase C retargeting.** VS auto-generates the new XPP config JSON with `ModelStoreFolder` defaulting to whichever path it last saw. Without retargeting, multiple UDEs share one custom metadata folder and builds pick up the wrong customer's code.
3. **Default download policy = `ask` in v1.** Do not auto-click No on "Client assets download" unless `--no-download` flag is set. Safety first; the download-skip optimization ships in v2 after validation.

4. **UIA Retry Before Escalate.** The most common cause of a single UIA failure is human mouse interference, not a broken VS state. When a UIA action fails (menu didn't open, button not found, click had no effect): wait 8 seconds, retry the same action (up to 6 attempts total). Only on 6th consecutive failure: take a screenshot, diagnose, consider recovery. NEVER restart VS, kill processes, or reconnect on first UIA failure.

5. **"Skip Discovery" must be ON — the whole flow depends on it.** `Tools → Options → Power Platform Tools → General → ☑ Skip Discovery when connecting to Dataverse`. With it ON, VS shows the **"Enter environment instance url"** popup that `handle_url_popup.ps1` fills. With it OFF, that popup never appears and the switch cannot target a specific environment. Verify it is checked before connecting (the `ensure_skip_discovery.ps1` pre-flight enforces this).

6. **Always start from a fresh VS session — never reuse an open VS.** If VS already has a Dataverse connection it auto-reconnects and **skips** the instance-URL popup, silently keeping the old environment. So if `devenv` is already running, `switch_ude.ps1` exits **2**; the orchestrator must get the user's **explicit approval** (this skill is interactive, not autonomous, and unsaved VS work can be lost), then re-run with **`-CloseExisting`**, which closes VS and launches fresh.

---

## Overview

Switches Visual Studio 2022 UDE from one online D365 F&O environment to another, using a JSON config file to track known UDEs. Main flow is three phases:

- **Phase A (pre-flight)**: Load config, snapshot XPPConfig folder state, decide download policy.
- **Phase B (UIA)**: Handle existing VS → Launch → Dismiss Start Window → Ensure Skip Discovery → Close solution → Tools → Connect to online Dataverse → Reconnect-No → Login → URL → Wait for validation → Select Solution → Download-prompt.
- **Phase C (post-switch)**: Identify new XPP config, retarget `ModelStoreFolder`, set as Current via VS UI, update `lastUsed`/`lastKnownVersion`.

## Invocation

```
/autoxpp-ude-switch                  → interactive picker (arrow select)
/autoxpp-ude-switch <name>           → switch to named UDE
/autoxpp-ude-switch --current        → show current active UDE
/autoxpp-ude-switch --list           → list configured UDEs
/autoxpp-ude-switch --add            → interactive add flow
/autoxpp-ude-switch <name> --no-download     → skip metadata download (warn)
/autoxpp-ude-switch <name> --close-existing  → if VS2022 is already open, close it first, then switch (fresh session)
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

Phase C — post-switch (disk + VS UI)
17. Diff XPPConfig to identify new config JSON (diff_xppconfig.ps1)
18. Create/reuse owned {name}___{version}.json, retarget ModelStoreFolder (retarget_xpp_config.ps1)
19. Set owned config as Current via VS UI (select_current_xpp_config.ps1)
20. Update lastUsed + lastKnownVersion in ude-configs.json
21. Report UDE_SWITCH_OK
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

### Rule F-3: On exit code 1, report and stop

Report the failure to the user with the log file path. Do NOT retry the entire switch unless the user explicitly asks. The user may need to:
- Kill a frozen VS manually
- Check Power Platform Tools extension installation

### Rule F-4: On exit code 2, get approval and re-run

Exit 2 means user input is needed (VS already open). Get the specific approval, then re-run with the appropriate flag (`-CloseExisting` for VS already open). Do NOT try alternative approaches.

### Rule F-5: VS freeze after switch

If VS becomes unresponsive (Responding=False) after a switch attempt, report it to the user. The user must kill VS manually or approve killing it. Do NOT attempt to drive a frozen VS with UIA — it will not respond and may corrupt further.

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
