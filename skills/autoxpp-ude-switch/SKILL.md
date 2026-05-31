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

4. **UIA Retry Before Escalate.** The most common cause of a single UIA failure is human mouse interference, not a broken VS state. When a UIA action fails (menu didn't open, button not found, click had no effect): wait 3 seconds, retry the same action (up to 3 attempts total). Only on 3rd consecutive failure: take a screenshot, diagnose, consider recovery. NEVER restart VS, kill processes, or reconnect on first UIA failure.

5. **"Skip Discovery" must be ON — the whole flow depends on it.** `Tools → Options → Power Platform Tools → General → ☑ Skip Discovery when connecting to Dataverse`. With it ON, VS shows the **"Enter environment instance url"** popup that `handle_url_popup.ps1` fills. With it OFF, that popup never appears and the switch cannot target a specific environment. Verify it is checked before connecting (the `ensure_skip_discovery.ps1` pre-flight enforces this).

6. **Always start from a fresh VS session — never reuse an open VS.** If VS already has a Dataverse connection it auto-reconnects and **skips** the instance-URL popup, silently keeping the old environment. So if `devenv` is already running, `switch_ude.ps1` exits **2**; the orchestrator must get the user's **explicit approval** (this skill is interactive, not autonomous, and unsaved VS work can be lost), then re-run with **`-CloseExisting`**, which closes VS and launches fresh.

---

## Overview

Switches Visual Studio 2022 UDE from one online D365 F&O environment to another, using a JSON config file to track known UDEs. Main flow is three phases:

- **Phase A (pre-flight)**: Load config, snapshot XPPConfig folder state, decide download policy.
- **Phase B (UIA)**: Drive VS through Tools → Connect to online Dataverse → Reconnect-No → Login → URL → Select Solution → Download-prompt.
- **Phase C (post-switch)**: Retarget `ModelStoreFolder` in new XPP config JSON, update `lastUsed`/`lastKnownVersion`.

See `DESIGN.md` in this folder for the full design rationale.

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

1. Visual Studio 2022 installed (Professional or Enterprise)
2. Power Platform Tools for VS 2022 extension installed
3. `Tools → Options → Power Platform Tools → Skip Discovery when connecting to Dataverse` checked
4. At least one UDE reachable and user has access
5. Windows account signed into the tenant (WAM caches MFA tokens)

If prerequisites are missing, skill surfaces an error with install guidance.

## Config file

**Path:** `C:\Users\[user]\.autoxpp\ude-configs.json`

See `reference/config-schema.md` for the schema and field semantics.

Minimum required per UDE: `name`, `dataverseUrl`, `customMetadataFolder`. Everything else is optional — connection settings (`solutionName`, `msAccount`, `downloadPolicy`) are per-UDE and fall back to code defaults; other fields (`foUrl`, `moduleName`, `oauth`, `login`, `sqlCache`) are owned by other skills and preserved untouched.

## Scripts

All scripts live in `scripts/` and follow the established autoxpp-* pattern:
- PowerShell (`.ps1`) for UIA and filesystem work on Windows
- UTF-8 output
- Structured logging via `log_step.ps1` (shared pattern)
- Emit tagged status lines (`UDE_SWITCH_OK`, `UDE_SWITCH_FAIL`, etc.) for the main channel

**Use existing scripts only.** The agent MUST invoke the scripts listed below by their file path — never generate new PowerShell scripts inline or write ad-hoc `.ps1` files to disk. Every UDE operation is already covered by the script inventory. If a script doesn't exist for the operation, that operation is out of scope for this skill.

### Entry point

```powershell
pwsh "scripts/switch_ude.ps1" -Name "<env-name>"
pwsh "scripts/switch_ude.ps1" -Name "<env-name>" -CloseExisting   # caller-approved: close an already-open VS, then switch
pwsh "scripts/switch_ude.ps1" -Current
pwsh "scripts/switch_ude.ps1" -List
pwsh "scripts/switch_ude.ps1" -Add
```

**`-CloseExisting` (skill option `--close-existing`):** by default, if VS2022 is already open the switch stops with **exit 2** so the orchestrator can get the user's approval (closing VS can lose unsaved work). Pass `-CloseExisting` when closing has already been approved — it closes the open session and starts fresh without the exit-2 round-trip. Use it for automation; omit it for interactive safety.

### Script inventory

| Script | Purpose |
|---|---|
| `switch_ude.ps1` | Main orchestrator (Phase A/B/C) |
| `config_helpers.ps1` | Load/save shared `ude-configs.json` (stamps schemaVersion 3, BOM-less) + resolve a UDE entry (dot-sourced) |
| `list_udes.ps1` | Print configured UDE list with last-used info |
| `show_current_ude.ps1` | Detect active UDE from XPPConfig folder + `lastUsed` |
| `add_ude.ps1` | Interactive add flow (prompts, writes JSON) |
| `launch_vs.ps1` | Start VS 2022 if not running; wait for main window |
| `close_open_solution.ps1` | UIA: File → Close Solution (if any open) |
| `open_connect_dataverse_menu.ps1` | UIA: Tools → Connect to online Dataverse |
| `handle_reconnect_dialog.ps1` | UIA: click No on "Reconnect to Dataverse" |
| `handle_login_dialog.ps1` | UIA: click Login on Power Platform Tools Login |
| `handle_url_popup.ps1` | UIA: type `dataverseUrl` + click OK |
| `wait_for_validation.ps1` | UIA: poll for Validating / Loading states |
| `handle_select_solution.ps1` | UIA: pick `solutionName` + click Done |
| `handle_download_prompt.ps1` | UIA: read version, decide Yes/No, click |
| `wait_for_download_complete.ps1` | Monitor download; detect VS exit |
| `relaunch_vs_if_exited.ps1` | Relaunch VS after assets install if it auto-closed |
| `retarget_xpp_config.ps1` | Overwrite `ModelStoreFolder`/`DebugSourceFolder` in new XPP JSON |
| `snapshot_xppconfig.ps1` | Baseline snapshot of `XPPConfig\` folder |
| `diff_xppconfig.ps1` | Identify newly created JSON file after switch |

## Flow summary (happy path)

```
1. Load ude-configs.json → resolve {name} entry
2. Verify VS 2022 + Power Platform Tools extension present
3. Snapshot XPPConfig baseline
4. Ensure VS running, close any open solution
5. Tools → Connect to online Dataverse
6. Click No on Reconnect dialog (force reconnect)
7. Click Login on Power Platform Tools Login dialog
8. Type dataverseUrl + OK on popup
9. Wait for "Loading Workflows / Plugin / Steps..."
10. Select solutionName on "Select Solution" dialog, click Done
11. On "Client assets download" prompt:
    - if version cached AND policy != "always" → click No
    - else → click Yes, monitor progress
12. If VS auto-exits post-download → wait + relaunch
13. Identify new {name}___{version}.json in XPPConfig → retarget ModelStoreFolder
14. Update lastUsed + lastKnownVersion in ude-configs.json
15. Report summary
```

## Error handling

See `DESIGN.md` section 7 for the full matrix. Common failures:
- Config name not found → list known names
- VS not installed → fail with guidance
- MFA prompt → surface to user, wait up to 5 min
- Account picker (cross-tenant) → surface to user
- Download stall (no output for 2 min) → warn, offer cancel

## Logging

All steps append to `C:\Users\[user]\.autoxpp\logs\ude-switch-{timestamp}.log` via shared `log_step.ps1` pattern. Line format:
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

- `DESIGN.md` — full design rationale and phase detail
- `reference/config-schema.md` — ude-configs.json schema reference
- `reference/dialogs.md` — UIA selector reference per dialog
- `autoxpp-build` — shared UIA patterns and Show/Hide VS discipline
