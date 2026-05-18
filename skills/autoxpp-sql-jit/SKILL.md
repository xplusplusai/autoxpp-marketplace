---
name: autoxpp-sql-jit
description: >-
  Acquire Just-In-Time read-only SQL credentials from VS2022's 'SQL Credentials
  for Dynamics 365 FinOps' dialog for the active online UDE environment. Auto-
  launches VS2022 if not running (reuses autoxpp-build launcher scripts, same
  3-attempt retry loop), drives the JIT dialog via PowerShell UIA,
  captures the connection string from clipboard, writes it to
  ~/.autoxpp/ude-configs.json → udeConfigs[].sqlCache. Credentials last
  ~24h. Companion to scripts/sql.py which reads the cache and
  runs queries via pyodbc. Use when a test case or investigation needs SQL
  access to internal tables / aggregates / joins that OData cannot express.
---

# AutoXPP SQL JIT

Automate the D365 F&O Just-In-Time SQL credential flow from VS2022. Saves the connection string to a per-machine cache so downstream scripts (`sql.py`) and skills don't re-drive the dialog on every query.

## Top rules (read before use)

1. **READ-ONLY.** The JIT credentials grant the `Reader` SQL role only. `scripts/sql.py` additionally rejects any statement starting with `INSERT / UPDATE / DELETE / DROP / ALTER / CREATE / TRUNCATE / EXEC / MERGE` before issuing the query. Both layers must see `SELECT` / schema queries only. If a caller needs write access, the answer is OData (`odata.py`) or the UI — never this skill.

2. **TEST OR ANALYSIS ONLY.** Valid uses: test-case layer-3 assertions, investigation of bugs / behavior / data shape, schema exploration. NOT for: triggering dev-time side effects, ad-hoc data fixes, or anything a user could reasonably call a "change." Never invoke on production environments — JIT is dev/sandbox only.

3. **CACHE LOCATION.** Connection strings land in `~/.autoxpp/ude-configs.json` → `udeConfigs[].sqlCache` — user-home, per-machine, ~24h expiry. Never checked into any repo. Never echoed to stdout / logs. `sql.py status --env <env>` shows non-secret fields (server, database, expiry) only.

## Why this skill exists

D365 F&O cloud environments issue temporary read-only SQL credentials (JIT, ~24h expiry) via VS2022's UDE. These credentials are the only practical path to internal tables (`InventTrans`, `WHSWorkLine`, `GeneralJournalEntry`) and to aggregate / cross-table queries that OData cannot express. The dialog is UI-only — there is no API. This skill drives the dialog via UIA so the tester and investigations can obtain credentials without hand-driving the flow.

## When to use

**Consumer contract (IMPORTANT): lazy-acquire only.** Other skills that need SQL must call `scripts/sql.py query ...` directly, NOT pre-invoke this skill as a pre-flight. This skill is invoked only when `sql.py` signals it needs fresh credentials:

- `sql.py` exits 1 with error code `cache-missing` → invoke this skill.
- `sql.py` exits 1 with error code `env-not-cached` → invoke this skill.
- `sql.py` exits 1 with error code `credentials-expired` → invoke this skill.
- `sql.py status --env <env>` reports missing/expired (only if a caller has a specific reason to precheck — one-off queries should just call `query`).

After this skill completes, the consumer retries the original `sql.py` call and proceeds.

Invoke also when:

- A test case needs a layer-3 assertion on a table with no OData entity (`InventTrans`, `WHSWorkLine`, `WHSWorkTable`, posted-journal tables, audit tables) AND the creds are stale.
- An investigation needs aggregate / `GROUP BY` / `COUNT` / `SUM` queries AND the creds are stale.
- A check requires a cross-table `JOIN` that OData can't express cleanly AND the creds are stale.

Do NOT invoke:

- **Eagerly before every SQL use.** The `scripts/sql.py` cache is checked per-query; letting it fail-then-refresh is cheaper than driving VS UI on every run.
- For CRUD operations that OData supports — use `odata.py` per the OData-first rule (`autoxpp-tester/reference/domain-fo.md`).
- On production environments — JIT is dev/sandbox only.
- Repeatedly inside a single test run — credentials are cached and live ~24h.

## Trigger phrases

"get sql credentials", "get sql access", "sql jit", "connect to sql", "need sql connection", "refresh sql jit"

## Prerequisites

- Terminal / Claude runs as Administrator (UIPI blocks UIA actions otherwise)
- VS2022 is connected to an online UDE at some point prior (so the `Tools → SQL Credentials…` menu item is registered) — the skill can START VS on its own, but it cannot establish the Dataverse connection. If VS has never connected, run `/autoxpp-ude-switch <env-name>` first.
- PowerShell UIA assemblies available (built-in on Windows)
- `~/.autoxpp/` directory exists (created on first use if missing)

## Show / Hide VS convention

Per global CLAUDE.md's Show/Hide rule for VS2022: show → act → hide. Do not leave VS in the foreground after the skill completes.

## Preflight (MANDATORY — runs before the UIA sequence)

### P0. Administrator privilege check (BLOCKING)

D365 F&O development requires VS2022 to run as Administrator, and the AI's terminal must also be elevated — otherwise Windows UIPI silently swallows every mouse click and keystroke directed at VS.

```bash
powershell.exe -Command '([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)'
```

| Output | Action |
|--------|--------|
| `True` | Proceed to P1. |
| `False` | **STOP.** Tell user to restart Claude / terminal as Administrator. Do NOT attempt UIA. |

### P1. Is VS2022 already running?

```powershell
Get-Process devenv -ErrorAction SilentlyContinue | Select-Object Id, MainWindowHandle, Responding | Format-List
```

> **PS7 compatibility:** `Select-Object` without an explicit formatter produces no visible output in PowerShell 7's non-interactive mode. Always pipe through `Format-List` (or `Out-String`) when the agent needs to read the result.

- Process exists AND `MainWindowHandle -ne 0` AND `Responding = True` → skip to UIA sequence step 1 (Show VS2022).
- Process missing, hung, or windowless → continue to P2 (Launch VS).

### P2. Launch VS2022 (retry loop, max 3 attempts)

**Reuse the build skill's launcher scripts** — do not duplicate logic. Build skill owns canonical VS launch and dialog dismissal.

```
for attempt in 1..3:
  1. If a broken devenv process exists → Stop-Process -Name devenv -Force; sleep 5s
  2. Start-Process devenv -Verb RunAs   (MUST use -Verb RunAs; plain launch fails silently under UIPI)
  3. Poll up to 120s for VS readiness: MainWindowHandle ≠ 0 AND Responding = True
  4. Click "Continue without code" via UIA:
       powershell.exe -ExecutionPolicy Bypass -File "{skills-root}/autoxpp-build/scripts/continue_without_code.ps1"
  5. Dismiss SDK dialog (cold-start only, benign if absent):
       powershell.exe -ExecutionPolicy Bypass -File "{skills-root}/autoxpp-build/scripts/dismiss_sdk_dialog.ps1"
  6. Verify menu bar is reachable via UIA (find a top-level MenuItem with Name="Tools").
     - If found → break loop, proceed to UIA sequence.
     - If not found within attempt's 120s window → kill VS, increment attempt.

If all 3 attempts fail → FAIL with "VS2022 failed to launch after 3 attempts. Manual intervention required."
```

**Why "Continue without code" (no solution):** Loading a `.sln` triggers project-load validation which often blocks on a modal "projects not loaded" dialog. The `Tools → SQL Credentials…` menu item is registered by the Power Platform Tools extension once VS has previously connected to an online Dataverse — it is independent of any loaded solution. Running bare is faster and has fewer failure modes.

### P3. UDE-connection sanity check

If VS was just launched (P2 ran), the Tools menu still needs the Power Platform Tools extension to be present. Quick UIA probe:

```
1. Click Tools in the menu bar (via PowerShell UIA).
2. Look for a MenuItem whose Name starts with "SQL Credentials for Dynamics 365 FinOps".
3. Close the menu (press Escape).
```

- Menu item present → proceed to UIA sequence step 2 (Open the Tools menu).
- Menu item absent → FAIL with: `VS2022 not connected to an online FO environment. Run /autoxpp-ude-switch <env-name> first to connect, then re-invoke this skill.`

Do NOT attempt to drive the UDE-connection flow from this skill — that is `autoxpp-ude-switch`'s responsibility (and involves a 5–15 min metadata download). Surface the clear pointer and exit.

### Show/Hide during preflight

Keep VS minimized for P0 and P1 (pure process / UIA probes — no focus needed). P2 must show VS briefly to click "Continue without code" via UIA; hide immediately after. P3 shows VS briefly for the Tools-menu probe; hide immediately after.

## UIA sequence

Drive all GUI interactions through PowerShell UIA. Each step below is a single desktop action. Preflight (above) has already guaranteed VS is running, Dataverse-registered, and reachable via UIA.

### 1. Show VS2022

Restore / focus the VS2022 window. Store the original window state so HIDE can restore it.

### 2. Open the Tools menu

Click `Tools` in the VS2022 menu bar.

### 3. Click "SQL Credentials for Dynamics 365 FinOps..."

The menu item text starts with `SQL Credentials for Dynamics 365 FinOps` and often includes the env name in a trailing ellipsis form.

- Menu item missing → Fail: "VS2022 not connected to an online FO environment. Run /autoxpp-ude-switch first."

Clicking the item can produce any of these dialogs, in sequence — handle each as it appears. The skill's job is to click through them silently; none of these steps require a fresh password prompt when the Windows user has a live WAM token to the tenant.

**3a. Reconnect to Dataverse.** Yes/No prompt. **ALWAYS click Yes** — reuses the cached WAM token, silent, no reauth. Never No (that path leads to an explicit login dialog the skill won't drive).

```powershell
# Yes button's UIA Name has a trailing space ('Yes ') — use trimmed match.
$yes = $btns | Where-Object { $_.Current.Name.Trim() -eq 'Yes' } | Select-Object -First 1
$yes.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
```

**3b. Configure Microsoft Power Platform Solution.** A two-phase dialog VS opens to (re-)establish the Dataverse session context. Both phases are silent when WAM is valid — no password needed.

- *Phase "1. Connect to Dataverse"* — form with `Sign in as current user` checkbox (pre-checked), Login button. Click **Login**. WAM handles the auth silently; the dialog transitions to phase 2 after a few seconds.
- *Phase "2. Select Solution"* — combobox named exactly `Select Solution:` + `Done` button. Expand, pick **Default**, click Done. The existing build skill script handles this phase cleanly:

```bash
powershell.exe -ExecutionPolicy Bypass -File "{skills-root}/autoxpp-build/scripts/handle_solution_dialog.ps1"
```

The dialog can arrive in phase 1 OR phase 2 depending on session state; detect by probing for the combobox (phase 2) vs the Login button (phase 1). If phase 1, click Login, wait ~3s for phase transition, then run the solution script.

UIA queries during the auth handshake can briefly time out with `HRESULT 0x80131505` — this is VS's UI thread being busy, not a failure. Retry the UIA query after 2–3s.

**Done-button focus-click trap.** `InvokePattern.Invoke()` on the phase-2 Done button often fails with `"Unrecognized error"` (WPF quirk). Even `BoundingRectangle` + a single `mouse_event` click can be silently consumed as a focus event by Windows when VS doesn't have foreground focus. The reliable recipe, identical to the build skill's Done-click handling:

1. Call `autoxpp-build/scripts/focus_maximize_vs.ps1` to bring VS forward.
2. Call `autoxpp-build/scripts/handle_solution_dialog.ps1` which picks Default + `BoundingRectangle`-clicks Done.
3. If the dialog is STILL open after 5s, double-click the Done coordinate (first click activates window focus, second actually invokes the button).

**Slow Dataverse session init.** After Done is clicked, the session-establishment step (Power Platform Explorer loads, JIT backend initializes) can take **60–150s** on a freshly-launched VS. Do NOT fail at 30s or 60s. Use a **180s timeout** on the JIT-dialog wait, polling every 3–5s.

**ValuePattern staleness on populate.** When the JIT backend returns credentials, the inner edit controls (`SQL Server Name:`, `Credential Expires On:`, etc.) update visually but `ValuePattern.Current.Value` can still read empty for ~5–15s after the visual update. Signal that credentials are ready using the more reliable indicator: the `Request Access` button becomes **disabled** (`IsEnabled = false`) once the request completes. Poll `Request Access` state; when it flips to disabled, then read the edit values.

**3c. JIT dialog opens directly.** Proceed to step 4. **Important discovery: the JIT dialog's Window `Name` property is empty** (Microsoft oversight). To detect it, search the dialog's descendants for a `Text` element whose Name equals `Dynamics 365 FinOps: Just In Time Credentials`, OR probe for the unique inner controls (edit field named `Reason for accessing the database:`, button named ` Request Access `).

```powershell
# Pattern for finding the JIT dialog by content, not title:
$cw = $vs.FindAll([TreeScope]::Children, $windowCond)
foreach ($w in $cw) {
    $marker = $w.FindFirst([TreeScope]::Descendants,
        (New-Object PropertyCondition([AutomationElement]::NameProperty, 'Dynamics 365 FinOps: Just In Time Credentials')))
    if ($marker) { $jit = $w; break }
}
```

**3d. No dialog after ~30s of handling the above.** Fail: `SQL JIT dialog did not appear.`

### 4. Fill the form

- Find the edit control whose Name is `Reason for accessing the database:` (colon included) and set its value to `Testing` via `ValuePattern.SetValue`. Typing via `keybd_event` works too, but `SetValue` is focus-free.
- The `SQL User Role:` combobox defaults to `Reader` at dialog open. It does NOT support `ValuePattern` on read; trust the default and do not try to toggle. If the caller needs to confirm, read the selection via `SelectionItemPattern` or visual inspection.

### 5. Click "Request Access"

Locate and click the `Request Access` button.

### 6. Poll for credentials

Poll every 2 seconds via UIA. **The reliable completion signal is the `Request Access` button's `IsEnabled` property flipping from `True` to `False`** — the JIT dialog disables it once the backend returns credentials. Reading `ValuePattern.Current.Value` on `Credential Expires On:` / `SQL Server Name:` can lag 5–15s after the actual UI update due to UIA caching, so those are confirmatory (read them after `Request Access` is disabled), not primary.

Timeout after **60 seconds** → fail: "JIT request timed out. Check VS2022 connection status."

Expected time-to-populate on healthy env: ~15–30s.

### 7. Click "Connection string"

Locate and click the `Connection string` button. VS2022 copies the full connection string to the system clipboard and shows "Connection string copied to clipboard." in the status bar.

### 8. Read the clipboard

Clipboard access in PowerShell requires STA threading — run `powershell.exe -STA -Command "..."`. MTA (default in many hosts) returns empty for `[System.Windows.Forms.Clipboard]::GetText()`.

Before clicking the Connection string button in step 7, clear the clipboard (`[Clipboard]::Clear()`) so a stale read isn't mistaken for success. After the click, wait ~1s, then read.

Expected shape:

```
Server=<server>.database.windows.net;Database=<db>;User Id=<user>;Password=<pw>;Encrypt=True;TrustServerCertificate=False;
```

If the clipboard is empty or does not contain `Server=` and `Database=`, retry the "Connection string" button click ONCE. If still empty, fail.

### 9. Parse and cache

Parse the connection string into structured fields (server, database, user, full connection string). Extract the env slug by matching the `Database=db_d365opsprod_<slug>_ax_*` pattern against `~/.autoxpp/ude-configs.json` entries.

**Slug-to-config matching:** the database slug has no punctuation (e.g. `mydev1`) while config `name` may contain hyphens (e.g. `my-dev1`). Match by stripping hyphens and lowercasing both sides:

```powershell
foreach ($u in $config.udeConfigs) {
    if ($u.name.Replace('-','').ToLower() -eq $slug.ToLower()) { $envName = $u.name; break }
}
```

- If a match is found, key the cache entry by that env name (e.g. `my-dev1`).
- If no match, key by the `activeEnv` from `ude-configs.json` (falls back to most recent `lastUsed` if `activeEnv` is missing).
- If neither is set, key by the raw `<slug>` extracted from the database name.

**Write the cache as UTF-8 WITHOUT BOM.** PowerShell's default `Set-Content -Encoding UTF8` writes a BOM (EF BB BF) which Python's `json.load` rejects. Use:

```powershell
[System.IO.File]::WriteAllText($path, ($cache | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false))
```

Or — simpler — write the file, then strip the BOM post-hoc in the same script. The `scripts/sql.py` uses stdlib `json`, which requires clean UTF-8.

Write to `~/.autoxpp/ude-configs.json` — update the matching env's `sqlCache` field (merge, never overwrite the whole file):

```json
// In udeConfigs[] entry where name == <env-name>:
"sqlCache": {
  "connectionString": "Server=...;Database=...;User Id=...;Password=...;Encrypt=True;TrustServerCertificate=False;",
  "server": "<server>.database.windows.net",
  "database": "<db-name>",
  "user": "<jit-user>",
  "expiresOn": "<ISO-8601 from dialog>",
  "acquiredOn": "<UTC now ISO-8601>",
  "role": "Reader"
}
```

**PowerShell recipe to merge sqlCache into existing ude-configs.json:**
```powershell
$configPath = "$env:USERPROFILE\.autoxpp\ude-configs.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$env = $config.udeConfigs | Where-Object { $_.name -eq '<env-name>' }
$env.sqlCache = @{ server='...'; database='...'; user='...'; connectionString='...'; expiresOn='...'; acquiredOn='...'; role='Reader' }
$config.schemaVersion = 3
[System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false))
```

Expiry time comes from the dialog's "Credential Expires On:" field; convert to ISO-8601 UTC.

### 10. Close the dialog

Use `WindowPattern.Close()` on the JIT dialog element:

```powershell
$dlg.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
```

Escape keystrokes do NOT close the JIT dialog reliably (its Window Name is empty, so keyboard focus routing is unusual). Do not rely on Escape here. Verify closure via a follow-up UIA probe (`FindAll Children Window` on VS → count should be 0).

### 11. Hide VS2022

Restore VS2022 to its prior window state (minimize if it was minimized; otherwise leave background).

### 12. Report

Emit a short success report:

```
SQL JIT acquired.
Env:          <env-name>
Server:       <server>.database.windows.net
Database:     <db-name>
Role:         Reader
Expires:      <ISO-8601 local> (approximately 24h)
Cache:        ~/.autoxpp/ude-configs.json → sqlCache
Next:         python scripts/sql.py query --env <env-name> --sql "..."
```

The connection string, user, and password are NEVER printed to stdout or logs. Only the server + database + expiry are reported.

## Error table

| Condition | Action |
|-----------|--------|
| Terminal not elevated | Fail (P0): "Terminal is not running as Administrator. Restart Claude / terminal as Administrator and retry." |
| VS2022 fails to launch after 3 attempts | Fail (P2): "VS2022 failed to launch after 3 attempts. Check D365 extension health / licensing / disk." |
| Tools → SQL Credentials menu item not found | Fail (P3 or step 3): "VS2022 not connected to an online FO environment. Run /autoxpp-ude-switch <env-name> first." |
| `Reconnect to Dataverse` dialog appears | Click **Yes** (trimmed name match — button is `'Yes '` with trailing space). Reuses cached WAM token; no fresh login. |
| `Configure Microsoft Power Platform Solution` dialog appears (phase 1 Login) | Normal silent flow when WAM token is valid. `Sign in as current user` is pre-checked; click **Login** — WAM auths silently, dialog transitions to phase 2. |
| `Configure Microsoft Power Platform Solution` dialog appears (phase 2 Select Solution) | Normal silent flow. Run `handle_solution_dialog.ps1` (pick Default, click Done) — same as the build skill. |
| `Login Failure` dialog appears | A non-silent path failed (e.g. user clicked No on Reconnect earlier, or WAM is genuinely broken). Dismiss via Enter/Escape, FAIL: "Dataverse login failed. Re-authenticate via /autoxpp-ude-switch <env-name> or Tools → Connect to Dataverse, then re-invoke this skill." |
| UIA `FindFirst` throws `HRESULT 0x80131505` during the auth handshake | VS UI thread is briefly busy. Retry the UIA query after 2–3s. |
| JIT dialog doesn't appear within 30s of handling the above dialogs | Fail: "SQL JIT dialog did not appear. Is VS connected?" |
| JIT dialog has empty Window Name | Expected — find it by probing child windows for a descendant Text named `Dynamics 365 FinOps: Just In Time Credentials`, not by title. |
| SQL User Role dropdown is not `Reader` | Fail with observed value — do not proceed; caller must manually reset or investigate |
| Request Access returns an error inside the dialog | Screenshot the error, emit it in the failure report |
| Credentials don't appear within 30s | Fail: "JIT request timed out. Check VS2022 connection status." |
| Clipboard read fails or missing `Server=`/`Database=` | Retry "Connection string" button once, then fail |
| Unable to resolve env from database slug OR `lastUsed` | Still cache under the raw slug — warn the human that env mapping is unconfirmed |

## Files this skill owns

| File | Role |
|------|------|
| `~/.autoxpp/ude-configs.json` → `udeConfigs[].sqlCache` | Per-machine JIT credential cache, nested in env config. Merged on each successful run. |

Never written to the skills repo — credentials are per-user, per-machine, and temporary.

## Files this skill reads

- `~/.autoxpp/ude-configs.json` — to resolve env slug → env-name
- VS2022 UI state (via PowerShell UIA)
- System clipboard (via PowerShell `Get-Clipboard`)

## Relationship to other skills

- **`scripts/sql.py`** — reads the cache file this skill writes. Runs SQL queries against the cached connection. Refuses to run if credentials are missing or expired and instructs the caller to invoke this skill.
- **`autoxpp-build`** — this skill reuses three launcher scripts from `autoxpp-build/scripts/` (`focus_maximize_vs.ps1`, `continue_without_code.ps1`, `dismiss_sdk_dialog.ps1`) rather than duplicating VS-launch logic. Build skill is the canonical owner of VS startup; changes there propagate automatically.
- **`autoxpp-ude-switch`** — prerequisite if VS has never connected to the target env. This skill does NOT drive the UDE-connection flow (5–15 min metadata download is out of scope); it fails clearly when the `SQL Credentials…` menu item is absent and points the user at `/autoxpp-ude-switch`.
- **`autoxpp-tester`** — primary consumer for layer-3 assertions on internal tables. See the SQL decision tree in `autoxpp-tester/reference/domain-fo.md`.

## Notes

- JIT credentials expire after ~24h. Re-invoke this skill when `sql.py status` reports expiry.
- No automated renewal — credentials must be explicitly refreshed so the human is aware each time VS drives a live dialog.
- The Reader role is sufficient for all test / dev query needs. Elevation to Writer is out of scope; this skill will fail if the dropdown defaults to anything else.
