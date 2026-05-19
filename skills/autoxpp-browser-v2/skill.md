---
name: autoxpp-browser-v2
description: >-
  Generic browser automation wrapper over playwright-cli. Adds auth management,
  self-learning site patterns, cross-skill integration, and evidence capture on top
  of the built-in playwright-cli skill. Site-specific knowledge lives in reference/
  files.
allowed-tools: Bash(playwright-cli:*), Read, Write, Edit, Glob, Grep
---

# Browser Automation Skill v2 (playwright-cli Wrapper)

## Architecture: Two-Layer Design

```
┌─────────────────────────────────────────────────────────┐
│  autoxpp-browser-v2  (this file)                        │
│  Our wrapper: auth, site-agnostic patterns,             │
│  self-learning, evidence capture.                       │
│  Lives in project .claude/skills/.                      │
│  Distributed via git (project-specific).                │
├─────────────────────────────────────────────────────────┤
│  playwright-cli built-in skill  (official, read-only)   │
│  Command reference from @playwright/cli npm package.    │
│  Location: ~/.claude/skills/playwright-cli/             │
│  Shared across ALL projects on this machine.            │
│  Updated by: npm update + playwright-cli install-skills │
└─────────────────────────────────────────────────────────┘
```

**Key points:**
- This wrapper adds: auth management, D365 patterns, self-learning, evidence workflow
- For command syntax and examples → read `~/.claude/skills/playwright-cli/SKILL.md`
- **NEVER modify** files under `~/.claude/skills/playwright-cli/` — it is upstream-managed
- The built-in skill is **global** (one install per machine, all projects share it)
- This wrapper is **per-project** (distributed via git with other autoxpp-* skills)

## Prerequisites: New Machine Setup

**Package:** `@playwright/cli`
**Reference:** https://testcollab.com/blog/playwright-cli

```bash
# Step 1: Install the CLI globally
npm install -g @playwright/cli

# Step 2: Install browser engine (Chromium)
playwright-cli install-browser

# Step 3: Install built-in skill files GLOBALLY
#   The command creates .claude/skills/playwright-cli/ relative to cwd.
#   We want it under ~/.claude/skills/ so ALL projects can use it.
cd ~
playwright-cli install --skills
#   This creates ~/.claude/.claude/skills/playwright-cli/ (nested)
#   Move to correct location:
cp -r ~/.claude/.claude/skills/playwright-cli ~/.claude/skills/
rm -rf ~/.claude/.claude
#   → Result: ~/.claude/skills/playwright-cli/SKILL.md

# Step 4: Verify
playwright-cli --version
ls ~/.claude/skills/playwright-cli/SKILL.md
```

> **Wrong package names — do NOT use:**
> - `playwright-cli` (npm) — deprecated empty stub v0.262.0
> - `@anthropic-ai/playwright-cli` — does not exist on npm
>
> **Wrong install location — avoid:**
> - Do NOT run `playwright-cli install --skills` from a sub-repo (e.g., D365FO)
>   — it creates files inside that repo's .claude/ folder instead of globally
> - Do NOT run from a project workspace — that creates a per-project copy

## Updating After Package Upgrade

When `@playwright/cli` releases a new version:

```bash
# Step 1: Update the CLI binary
npm update -g @playwright/cli

# Step 2: Update the built-in skill docs to match
cd ~
playwright-cli install --skills
cp -r ~/.claude/.claude/skills/playwright-cli ~/.claude/skills/
rm -rf ~/.claude/.claude

# Step 3: Verify
playwright-cli --version
```

This updates `~/.claude/skills/playwright-cli/SKILL.md` with any new commands
or syntax changes. Our wrapper (this file) is unaffected — no project changes needed.

---

## CRITICAL RULES (READ FIRST)

1. **AUTH FIRST**: Before navigating to ANY URL, check for saved auth state and restore it. Do NOT ask user to log in manually until restore has been tried.

2. **SAVE AUTH AFTER LOGIN**: After ANY successful login (manual or restored), capture and save auth state before doing anything else.

3. **NEVER SKIP AUTH CHECK**: Even for a "quick check" — auth restore takes seconds, manual login takes minutes.

4. **PROPOSE LESSONS FOR APPROVAL**: When you discover a new pattern, workaround, or quirk, self-evaluate ("Would this save time in future sessions?"). If yes, present it to the user with proposed destination (skill-level or project-level per Dual Reference routing). Never auto-save — wait for user approval. At session end, auto-discover any remaining candidates per the protocol in Section 6.

5. **SESSION WRAP-UP**: Before ending any browser session:
   - **Do NOT close the browser.** Leave it running — the next session reuses it via `tab-new` (Section 1, step 0). Closing destroys the persistent profile's in-memory state and forces a cold restart + re-auth next time.
   - **NEVER close, kill, or stop pre-existing Chrome/browser processes.** Not `Stop-Process chrome`, not `playwright-cli close`, not `playwright-cli kill-all`, not `taskkill /IM chrome.exe`. The user may have their own Chrome session open. Another CLI session may have its own playwright browser. Only YOUR session's browser tab is yours to manage.
   - **Close only YOUR tabs.** At session end, close the tab(s) you opened during this invocation via `playwright-cli tab-close`. This prevents tab accumulation across invocations. If you opened multiple tabs, close all of them. The browser itself (and the daemon keeping the persistent profile alive) stays running.
   - Review what was learned
   - Confirm all learnings were saved to user-local file
   - Report summary to user
   - Even if nothing new: "No new patterns discovered — reference file is up to date."

6. **NEVER MODIFY BUILT-IN**: `.claude/skills/playwright-cli/` is read-only. Our wrapper adds layers, never touches the dependency.

7. **SNAPSHOT DIRECTORY**: `playwright-cli` writes `.playwright-cli/` relative to the shell's CWD. If CWD changes during a session, snapshots scatter across directories and you read stale files with wrong element refs. **Fix:** At session start, set `SNAPDIR` to an absolute path and use it consistently:
   ```bash
   SNAPDIR="{WorkspaceRoot}/.playwright-cli"
   # Then always: SNAP=$(ls -t $SNAPDIR/page-*.yml | head -1)
   ```

8. **USE `--persistent` FOR LONG SESSIONS**: D365 deployments invalidate all sessions. Use `playwright-cli open --browser chrome --headed --persistent` to maintain a browser profile that survives restarts. Re-auth once instead of after every deploy.

9. **USE `--persistent` AS PRIMARY AUTH**: The `--persistent` flag gives playwright-cli a real Chrome user-data-dir that accumulates cookies and saved credentials across sessions. This is the simplest and most reliable auth path — no profile copying needed. The persistent profile lives at `$LOCALAPPDATA/ms-playwright/daemon/*/ud-default-chrome/` and survives browser restarts. Google OAuth blocks playwright-launched browsers regardless of profile strategy, so use Microsoft login when manual auth is needed.

10. **SAVE AUTH STATE AS BACKUP**: After any successful login, run `playwright-cli state-save` and copy the result to `~/.autoxpp/cache/auth-state/{domain-key}.json`. This serves as a fallback if the persistent profile is lost (daemon cleanup, machine switch). On session start, if `--persistent` doesn't have valid auth, try `state-load` before asking the user to log in manually. Do NOT save auth state to `{ProjectMemoryDir}` — cookie dumps are ~270KB and waste context when loaded as project memory.

11. **ORPHAN-SAFE POLLING LOOPS**: Every `until`/`while` loop that polls `playwright-cli snapshot` (or any other blocking wait) MUST include both guards below. Loops without these guards become orphans when the Claude Code session dies — they keep the playwright daemon alive indefinitely, respawning Chrome on close.

    **Mandatory pattern:**
    ```bash
    _POLL_PARENT=$PPID
    _POLL_START=$(date +%s)
    _POLL_MAX=300  # seconds — adjust per use case, NEVER exceed 600

    until <your-condition>; do
      kill -0 $_POLL_PARENT 2>/dev/null || { echo "POLL_ORPHAN: parent gone, exiting"; exit 1; }
      [ $(( $(date +%s) - _POLL_START )) -ge $_POLL_MAX ] && { echo "POLL_TIMEOUT: ${_POLL_MAX}s exceeded"; exit 2; }
      sleep 5
    done
    ```

    **Rules:**
    - `_POLL_PARENT=$PPID` — captures the parent PID at loop start. If the Claude Code session crashes, this PID dies, and the guard exits the loop on the next tick.
    - `_POLL_MAX` — hard ceiling. Login polls: 300s. Page-load polls: 120s. Processing waits: 600s max. NEVER omit this.
    - This applies to ALL polling — login detection, page-load waits, batch processing checks, navigation confirmation, anything with `sleep` in a loop.
    - The Monitor tool has its own timeout (`timeout_ms`) — still add both guards inside the command string for defense-in-depth.

12. **PREFER SYSTEM CHROME (`--browser chrome`)**: Always include `--browser chrome` in the launch command. System Chrome has the user's saved passwords, extensions, and trusted session cookies — Playwright's bundled Chromium starts with an empty credential store and may be blocked by SSO providers that fingerprint browser binaries. Only omit `--browser chrome` (falling back to bundled Chromium) if the launch fails because Chrome is not installed.

13. **MAXIMIZE VIEWPORT ON LAUNCH**: After opening a browser session, immediately resize to full HD: `playwright-cli resize 1920 1080`. D365 forms hide toolbar buttons, collapse action panes, and truncate grids at smaller viewports. If you can't find an expected element (button, link, menu item), the first fix is maximizing — not re-navigating or assuming the element doesn't exist.

---

## Section 1: Environment Check

```
┌──────────────────────────────────────────────────────────────┐
│  ON INVOCATION:                                               │
│                                                               │
│  ** HARD RULE: NEVER kill, close, or stop any pre-existing ** │
│  ** Chrome or browser processes. Not playwright-cli close,  ** │
│  ** not kill-all, not Stop-Process, not taskkill. The user  ** │
│  ** has their own Chrome open. Only open new tabs.          ** │
│                                                               │
│  ** HARD RULE: ALWAYS REUSE. The persistent daemon is a    ** │
│  ** shared resource. If it's running, connect to it. Never ** │
│  ** kill-and-relaunch as a shortcut.                        ** │
│                                                               │
│  ** HARD RULE: MULTI-SESSION ISOLATION. If the default     ** │
│  ** daemon is actively used by ANOTHER Claude Code session ** │
│  ** (e.g., snapshot shows another session's page, or       ** │
│  ** tab-select/click targets the wrong page), DO NOT fight ** │
│  ** over tabs. Instead, use a NAMED SESSION:               ** │
│  **                                                        ** │
│  **   playwright-cli -s=my-task open --headed --persistent ** │
│  **   playwright-cli -s=my-task goto <url>                 ** │
│  **   playwright-cli -s=my-task snapshot                   ** │
│  **   playwright-cli -s=my-task click e123                 ** │
│  **                                                        ** │
│  ** This creates a separate Chrome instance with its own   ** │
│  ** user-data-dir (ud-<name>-chrome). No conflicts with    ** │
│  ** the default session. All commands must include -s=name. ** │
│  ** At session end, close your tab(s) in your session only.** │
│                                                               │
│  0. CHECK IF BROWSER IS ALREADY OPEN:                         │
│     playwright-cli snapshot 2>/dev/null                        │
│                                                               │
│     IF snapshot succeeds (browser already running):            │
│       → DO NOT close it. Reuse the existing browser.          │
│       → Open a new tab for the target URL:                    │
│         playwright-cli tab-new {target-url}                   │
│       → Auth is already valid (persistent profile).           │
│       → Skip to step 4 (load knowledge).                      │
│                                                               │
│     IF snapshot fails (no browser running):                    │
│       → Check for ORPHANED daemon (step 0b) before launching. │
│                                                               │
│  0b. ORPHAN DETECTION (only when snapshot fails):             │
│     Check if Chrome processes exist with the persistent       │
│     profile but the daemon pipe is broken:                    │
│                                                               │
│     PowerShell:                                               │
│       $orphans = Get-Process chrome -EA SilentlyContinue |    │
│         Where-Object { $_.CommandLine -match                  │
│           'chrome-profile-fresh|ms-playwright\\daemon' }      │
│                                                               │
│     IF orphans exist (Chrome running but snapshot failed):    │
│       → The daemon died but Chrome children survived.         │
│       → Safe to clean up ONLY these specific processes:       │
│         taskkill /F /PID <main-chrome-pid> /T                 │
│       → Delete stale session file:                            │
│         Remove-Item "$env:LOCALAPPDATA\ms-playwright\         │
│           daemon\*\default.session" -Force                    │
│       → Now proceed to step 1 (launch fresh).                 │
│                                                               │
│     IF no orphans (clean state):                              │
│       → Proceed to step 1 (launch fresh).                     │
│                                                               │
│  1. Verify playwright-cli works:                              │
│     playwright-cli --version                                  │
│                                                               │
│     IF not found:                                             │
│       Ask user: "playwright-cli not found. Install?"          │
│       → npm install -g @playwright/cli                        │
│       → playwright-cli install-browser                        │
│       (ref: testcollab.com/blog/playwright-cli)               │
│       IF user declines or install fails:                      │
│         → Report: "Browser testing unavailable"               │
│         → Return control to caller with BROWSER_UNAVAILABLE   │
│                                                               │
│  2. Verify built-in skill exists:                             │
│     Check: ~/.claude/skills/playwright-cli/SKILL.md           │
│                                                               │
│     IF not found:                                             │
│       → Tell user: "playwright-cli skill not installed        │
│         globally. Run these commands:"                        │
│         cd ~                                                  │
│         playwright-cli install --skills                       │
│         cp -r ~/.claude/.claude/skills/playwright-cli \       │
│                ~/.claude/skills/                              │
│         rm -rf ~/.claude/.claude                              │
│       → Verify file now exists                                │
│                                                               │
│  3. Launch browser (system Chrome + persistent profile):      │
│     playwright-cli open --browser chrome --headed             │
│       --persistent {target-url}                               │
│                                                               │
│     IF launch fails (Chrome not installed):                   │
│       → Retry without --browser chrome (bundled Chromium):    │
│       playwright-cli open --headed --persistent {target-url}  │
│                                                               │
│     The persistent profile accumulates cookies and saved      │
│     credentials across sessions. No profile copying needed.   │
│     System Chrome is preferred — it has saved passwords and   │
│     is trusted by SSO providers.                              │
│                                                               │
│  4. Load knowledge (Section 6):                               │
│     → Read shared reference files from reference/             │
│     → Read user-local browser-ref files                       │
│                                                               │
│  5. Ensure .playwright-cli/ is gitignored                     │
│     (runtime snapshots/screenshots go here — transient)       │
└──────────────────────────────────────────────────────────────┘
```

---

## Section 2: Authentication State Management

```
IMPORTANT: Google OAuth blocks ALL playwright-launched browsers due to
automation flags. Use Microsoft login when manual auth is needed.

┌──────────────────────────────────────────────────────────────┐
│  AUTH STRATEGY PRIORITY (try in order):                       │
│                                                               │
│  1. PERSISTENT PROFILE (preferred — cookies survive restarts) │
│  2. Playwright state-load (fallback for lost profiles)       │
│  3. Manual login (last resort)                               │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  ON SESSION START (after Section 1):                          │
│                                                               │
│  The browser is now open (either reused or freshly launched   │
│  with --persistent). Take a snapshot to check auth state.     │
│                                                               │
│  1. CHECK CURRENT PAGE:                                       │
│     playwright-cli snapshot                                   │
│     → IF app content visible (not login page) → DONE          │
│       Auth is valid from persistent profile. Proceed to task. │
│     → IF login page → persistent cookies expired.             │
│       Fall through to step 2.                                 │
│                                                               │
│  2. FALLBACK — PLAYWRIGHT STATE-LOAD:                         │
│     Derive domain key from target URL                         │
│     e.g., <env>.operations.dynamics.com → d365-<env>          │
│     Check: ~/.autoxpp/cache/auth-state/{domain-key}.json      │
│                                                               │
│     IF state file exists:                                     │
│       playwright-cli state-load "{path-to-state-file}"        │
│       playwright-cli goto {target-url}                        │
│       playwright-cli snapshot                                 │
│       → IF logged in → proceed to task                        │
│       → IF login page → state expired, fall through           │
│                                                               │
│  3. LAST RESORT — MANUAL LOGIN:                               │
│     playwright-cli goto {target-url}                          │
│     → Use MICROSOFT login (not Google — Google blocks         │
│       playwright). Bring browser to foreground, tell user.    │
│     → Poll: playwright-cli snapshot every ~5s                 │
│       Check for app content (not login page)                  │
│     → When login detected, proceed to step 4                  │
│                                                               │
│  4. SAVE AUTH STATE (immediately after login):                │
│     playwright-cli state-save                                 │
│     → Output lands in .playwright-cli/ by default             │
│     → Copy/move to ~/.autoxpp/cache/auth-state/{domain-key}   │
│     mkdir -p ~/.autoxpp/cache/auth-state                      │
│     cp .playwright-cli/state-*.json \                         │
│        ~/.autoxpp/cache/auth-state/{domain-key}.json          │
└──────────────────────────────────────────────────────────────┘
```

### CRITICAL: Always Use `--headed --persistent` and Show Browser for Manual Login

**playwright-cli defaults to headless with in-memory profile.** The user CANNOT see or interact with a
headless browser, and in-memory profiles lose auth state when closed. Additionally, some SSO providers
(e.g., Google) block non-standard browsers — `--persistent` uses a real Chrome user-data-dir that
SSO providers trust.

**Rules:**
1. **ALWAYS** open the browser with `playwright-cli open --browser chrome --headed --persistent`
   - `--browser chrome`: uses system-installed Chrome (saved passwords, SSO-trusted)
   - `--headed`: user can see and interact with the browser
   - `--persistent`: uses a real Chrome profile (survives restarts, SSO-compatible)
   - If Chrome is not installed, fall back to: `playwright-cli open --headed --persistent` (bundled Chromium)
   - **NEVER** use `playwright-cli open` without `--headed --persistent` when human login is needed
   - **NEVER** use `playwright-cli show` as a substitute — it only makes a headless browser visible but SSO providers may still block it
2. **BEFORE** telling the user to log in, bring the browser window to foreground:

```powershell
# Bring playwright Chromium to foreground
powershell.exe -Command "
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class BrowserFocus {
    [DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport(\"user32.dll\")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
'@
# playwright-cli uses Chromium — find by window title (login page or app title)
\$browsers = Get-Process | Where-Object {
    \$_.MainWindowHandle -ne [IntPtr]::Zero -and
    \$_.ProcessName -match 'chrom' -and
    \$_.MainWindowTitle -match 'Sign in|Playwright|Chromium|dynamics|D365'
}
if (-not \$browsers) {
    # Fallback: find the playwright-cli child process (Chromium without 'Google Chrome' in title)
    \$browsers = Get-Process | Where-Object {
        \$_.MainWindowHandle -ne [IntPtr]::Zero -and
        \$_.ProcessName -match 'chrom' -and
        \$_.MainWindowTitle -notmatch 'Google Chrome'
    }
}
if (\$browsers) {
    \$b = \$browsers | Select-Object -First 1
    [BrowserFocus]::ShowWindow(\$b.MainWindowHandle, 3)
    [BrowserFocus]::keybd_event(0xA4, 0, 0, [UIntPtr]::Zero)
    [BrowserFocus]::SetForegroundWindow(\$b.MainWindowHandle)
    [BrowserFocus]::keybd_event(0xA4, 0, 2, [UIntPtr]::Zero)
    Write-Host 'BROWSER_FOCUSED'
} else {
    Write-Host 'PLAYWRIGHT_BROWSER_NOT_FOUND'
}
"
```

3. **THEN** tell the user: "Browser is open — please log in."
4. **NEVER** tell the user to log in without first showing them the browser.

### Auto-Login with Browser Saved Credentials

When using `--persistent` profile, the browser accumulates saved credentials across sessions.
The browser may auto-populate email and password fields on login pages.

**Auto-login is allowed when BOTH conditions are met:**

1. **Known test account**: The user email is found in `ude-configs.json`
   (lookup order: environment-specific `login.adminUser` or `login.testUser`,
   then `defaults.msAccount`)
2. **Credentials auto-filled**: The `--persistent` browser profile has auto-populated
   the email and/or password fields (visible as non-empty fields in the snapshot)

If both conditions are met → **click Sign In immediately, do NOT ask the user.**
If either condition is NOT met → bring browser to foreground and ask user to log in manually.

**Generic auto-login flow (works for any site):**

```
1. Detect login page:
   → URL contains "login", "signin", "auth" or similar
   → Snapshot shows login form (email/password fields, sign-in button)

2. Look up test account from ude-configs.json:
   → Read C:\Users\{username}\.autoxpp\ude-configs.json
   → Match target URL to a udeConfigs[] entry by foUrl or dataverseUrl
   → Check login.adminUser first, then login.testUser
   → If both are placeholder ("<REPLACE...>") or empty, fall back to defaults.msAccount
   → If NO email found at any level:
     ⚠ WARNING: "No test account configured in ude-configs.json for {target-url}.
       Add login.adminUser or login.testUser to the environment entry,
       or set defaults.msAccount."
     → Skip auto-login, bring browser to foreground, ask user manually

3. Check if credentials are auto-filled by browser:
   → Take snapshot of login page
   → Check email field: does it have a value? (may match saved test email)
   → Check password field: is it non-empty? (shown as dots/masked in UI)
   → Password textbox will NOT show the value in snapshot (security)
   → DO NOT attempt to read or fill passwords

4. If BOTH conditions met (known email + auto-filled credentials):
   → Click "Sign In" / "Log In" / "Submit" button
   → Wait 5-10s, take snapshot
   → If URL changed away from login page → success
   → If still on login page → auto-login failed, fall back to manual

5. If only email is known but password NOT auto-filled:
   → Click/focus the password field (textbox "Password" or similar)
   → Wait 1-2 seconds for Chrome's credential manager dropdown to appear
   → The dropdown is NATIVE BROWSER UI — it will NOT appear in playwright
     snapshots. You cannot see or click it via DOM interaction.
   → Send keyboard: ArrowDown then Enter to select the first saved credential
     (this works even though the dropdown is invisible in snapshots)
   → Wait 1 second, take snapshot to check if password field now shows dots
   → If password field is filled → click "Sign in" button
   → If password field is STILL empty after keyboard attempt:
     a. Fill email field with saved test email (if empty)
     b. Bring browser to foreground
     c. Ask user: "Email pre-filled. Please enter password and click Sign In."

6. Handle post-login prompts ("Stay signed in?", "Remember device?"):
   → Click "Yes" / accept

7. After successful login → save auth state immediately
```

**Microsoft/Azure AD specific flow:**

```
1. URL contains "login.microsoftonline.com"
2. Email page → fill/verify email → click "Next"
3. Password page:
   a. Check if password field already shows dots (auto-filled) → click "Sign in"
   b. If password field is empty → click the password field to focus it
   c. Wait 1-2s, then send ArrowDown + Enter (selects first saved credential
      from Chrome's native dropdown — invisible in snapshots)
   d. Wait 1s, check if password field now has dots → click "Sign in"
   e. If still empty → bring browser to foreground, ask user for password
4. "Stay signed in?" → click "Yes"
```

**Key rules:**
- **NEVER store, log, or attempt to read passwords** — only the browser's
  credential manager handles passwords
- Always use `--persistent` to enable browser credential saving
- Auto-login requires BOTH known account (from ude-configs.json) AND auto-filled credentials
- If auto-login fails (wrong password, MFA required, no saved credentials),
  bring browser to foreground and ask user to log in manually
- Test account email is read from `ude-configs.json` (single source of truth) — do NOT
  duplicate it in browser-ref files or project memory

---

## Section 3: Core Interaction Loop

The main automation methodology. For command syntax, refer to the built-in skill.

```
┌──────────────────────────────────────────────────────────────┐
│  NAVIGATE                                                     │
│    playwright-cli goto {url}                                  │
│    → Command auto-returns a snapshot                          │
│    → Read the snapshot YAML for page structure + element refs │
│                                                               │
│  OBSERVE                                                      │
│    Read snapshot for element refs and page state               │
│    playwright-cli screenshot (when visual context needed)     │
│    playwright-cli console (check for JS errors/warnings)      │
│    → Check D365 reference (Section 5) for known page patterns │
│                                                               │
│  ACT                                                          │
│    Use commands per built-in SKILL.md:                        │
│      click, fill, select, press, type, hover, drag, etc.     │
│    → For D365 patterns, check Section 5 FIRST                │
│    → Each command returns updated snapshot automatically       │
│                                                               │
│  VERIFY                                                       │
│    Read returned snapshot → compare expected vs actual         │
│    playwright-cli screenshot --filename={evidence-name}.png   │
│    → Check for error messages, infolog, unexpected state      │
│                                                               │
│  RECORD                                                       │
│    Log step result (PASS/FAIL)                                │
│    If new pattern discovered → save to browser-ref (Section 6)│
│    Screenshot with meaningful --filename for evidence          │
└──────────────────────────────────────────────────────────────┘
```

---

## Section 4: Site-Specific Patterns (Generic Rules)

Site-specific details live in `reference/{site-key}.md` files. These generic rules apply to ALL web apps:

### Blocking Overlays
Many web apps show loading overlays during server calls that block interaction.
- **Check the site reference** for overlay selectors and removal techniques
- **Generic approach:** Poll snapshot until the target element is interactable again
- **Proactive approach:** If the site reference provides overlay selectors, inject a MutationObserver to auto-remove them

### Application Dialogs vs Native Dialogs
Web frameworks often render confirmation/info dialogs as DOM elements, not native browser dialogs (`alert()`/`confirm()`).
- `playwright-cli dialog-accept` only works for **native** browser dialogs
- For app-rendered dialogs: snapshot → find button ref → click it
- **Check site reference** for dialog patterns specific to the app

### Session Monitoring During Long Waits
When this skill is idle while another skill runs (build, deploy, data migration):
- The browser session may expire due to inactivity timeouts
- **Before resuming interaction:** take a snapshot to verify session is still active
- If session expired: check site reference for recovery steps (e.g., "Start new session" button), then fall back to auth flow (Section 2)
- External processes (deployments, service restarts) may invalidate auth server-side — check site reference for known invalidation triggers

### After-Action Verification
After any action (save, submit, process, delete), check the snapshot for:
- Success/error/warning messages (infolog, toast, banner)
- Capture messages as evidence via screenshot
- Check site reference for where the app displays status messages

---

## Section 5: Evidence Capture Workflow

### Screenshot Default Location

All screenshots MUST be saved to `{WorkspaceRoot}/screenshots/`:
```bash
mkdir -p "{WorkspaceRoot}/screenshots/{feature}"
playwright-cli screenshot --filename="{WorkspaceRoot}/screenshots/{feature}/{name}.png"
```

`{WorkspaceRoot}` = the repo workspace root (e.g., `C:\MyD365Project`).
**NEVER** save screenshots to the current working directory or `.playwright-cli/`.
Organize by feature subfolder: `screenshots/{feature}/{step}-{date}.png`
Example: `screenshots/{feature}/fullcycle-01-records-created.png`

### Per Test Case

```bash
# Before test
playwright-cli screenshot --filename="{WorkspaceRoot}/screenshots/{feature}/{TC-id}-before.png"

# ... perform test steps, screenshot at key points ...
playwright-cli screenshot --filename="{WorkspaceRoot}/screenshots/{feature}/{TC-id}-step1-{description}.png"

# After test
playwright-cli screenshot --filename="{WorkspaceRoot}/screenshots/{feature}/{TC-id}-after.png"
```

### For Complex Flows (video)

```bash
playwright-cli video-start
# ... perform multi-step flow ...
playwright-cli video-stop {TC-id}-{description}.webm
```

### For Debugging (trace)

```bash
playwright-cli tracing-start
# ... reproduce the issue ...
playwright-cli tracing-stop
# Trace files saved to .playwright-cli/
```

### Reporting

Present results in structured format:

| TC | Step | Expected | Actual | Status | Evidence |
|:---|:-----|:---------|:-------|:-------|:---------|
| TC1 | Process record | Status = Processed | Status = Processed | PASS | TC1-after.png |

---

## Section 6: Self-Learning (Dual Reference Architecture)

This skill uses the **Dual Reference Architecture** defined in the skills-repo `CLAUDE.md`.

### Skill identity

| Key | Value |
|:----|:------|
| **skill-key** | `browser-ref` |
| **Skill-level reference** | `{SkillDir}/reference/{site-key}.md` — generic D365 browser patterns (any project) |
| **Project-level reference** | `{ProjectMemoryDir}/browser-ref/{site-key}.md` — project-specific patterns (this client) |

`{ProjectMemoryDir}` = the user's Claude project memory directory (e.g., `~/.claude/projects/<hash>/memory/`)
`{SkillDir}` = `autoxpp-browser-v2/`

### On Session Start

```
1. Load skill-level reference (if exists):
   Read {SkillDir}/reference/{site-key}.md
   (May not exist in plugin mode — skip without error)

2. Load project-level reference (if exists):
   Read {ProjectMemoryDir}/browser-ref/{site-key}.md

3. Both provide context. Project-level entries take precedence on conflicts.
```

### Save routing (maintainer vs plugin mode)

```
IF {SkillDir}/reference/ exists AND is writable (maintainer mode):
  Generic learning    → {SkillDir}/reference/{site-key}.md (skill-level)
  Project-specific    → {ProjectMemoryDir}/browser-ref/{site-key}.md (project-level)

IF {SkillDir}/reference/ missing OR read-only (plugin mode):
  ALL learnings       → {ProjectMemoryDir}/browser-ref/{site-key}.md (project-level)
  NEVER create folders or files inside {SkillDir}/
```

### During Session — Propose Immediately

When you discover a new pattern, workaround, or quirk:

```
1. Self-evaluate: "Would this save time or prevent mistakes in future sessions?"
   YES → proceed. NO → ignore.

2. Classify:
   - Generic (any D365 project) → skill-level if writable, else project-level
   - Project-specific (this client only) → project-level

3. Determine which section the learning belongs in:
   - Navigation correction → "Navigation Patterns"
   - Selector discovery → "Element Selectors"
   - Form behavior → "Form Interactions"
   - Quirk/workaround → "Known Quirks & Workarounds"
   - General learning → "Lessons Learned"
   - Verified form URL → browser-ref/d365-form-urls.md (D365 only)

4. Check for duplicates in BOTH files
   - If exists in skill-level → don't duplicate in project-level
   - If exists in project-level → update, don't duplicate

5. Present to user for approval (never auto-save)
6. Save approved learnings to the approved destination
```

### Knowledge Capture Triggers

| Trigger | What Gets Saved |
|:--------|:----------------|
| Navigation retry | Corrected nav path |
| User correction | User's guidance |
| Element not found + recovery | Working selector |
| Form submit pattern | Button location + confirm behavior |
| Page load quirk | Wait/refresh needed |
| Data entry pattern | How to fill a specific field |
| Error recovery | How an error was resolved |
| Verified form URL | Form URL added to d365-form-urls.md |

### On Session End

Per the "Lessons Learned — Auto-Discover" protocol in skills-repo `CLAUDE.md`:
1. Self-evaluate all session discoveries against the "worth saving" filter
2. Classify and present candidates to user with proposed destinations
3. Wait for approval — never auto-save
4. Save approved learnings
5. Report: "N learnings saved" or "No new patterns worth capturing this session."

---

## Section 7: Site Detection

When navigating to a NEW site (not previously seen), identify it:

```
1. After page loads, inspect:
   - Page title (from snapshot)
   - Framework indicators via eval:
     playwright-cli eval "(() => {
       const s = {};
       if (window.$dyn) s['d365-fo'] = true;
       if (window.Xrm) s['d365-ce'] = true;
       if (window.$A || window.sforce) s['salesforce'] = true;
       if (window.GlideAjax) s['servicenow'] = true;
       s._title = document.title;
       return JSON.stringify(s);
     })()"

2. Derive site key (lowercase kebab-case):
   "D365 Finance & Operations" → d365-fo
   "D365 CRM / Customer Engagement" → d365-ce
   "Salesforce Lightning" → salesforce
   "Custom app on myco.com" → myco-app

3. Load reference files for that site key (Section 6)
```

---

## Section 8: Cross-Skill Integration

### When Invoked by Another Skill

Other skills (e.g., a dev workflow skill) may invoke this skill for browser testing. When called from another skill:

```
1. The caller provides: test URLs, form names, steps (via plan file or direct instruction)
   → Use those URLs directly — do NOT explore/navigate manually

2. Detect browser engine availability:
   playwright-cli --version → available? → proceed
   IF not available → return BROWSER_UNAVAILABLE status to caller
```

### Return Status Codes

When called from another skill, return one of:
- `TEST_PASSED` — all test cases passed, evidence captured
- `TEST_FAILED` — one or more test cases failed, details provided
- `BROWSER_DISCONNECTED` — playwright-cli process died or unresponsive
- `BROWSER_UNAVAILABLE` — playwright-cli not installed

### Session Resilience During External Processes

When another skill is running a long operation (build, deploy, data migration, batch job):
- The browser session may expire due to inactivity or server-side invalidation
- **Before resuming browser interaction:** always verify session with a snapshot
- If session is invalid: re-run auth flow (Section 2)
- **Persistent profile** (`--persistent` flag) helps survive browser restarts and reduces re-auth
- Check site reference for known auth invalidation triggers (e.g., service restarts after deployment)

---

## Reference File Template

For creating new user-local reference files (`{ProjectMemoryDir}/browser-ref/{site-key}.md`):

```markdown
# {Site Name} - Browser Automation Reference

## Site Info
- **Site key:** {site-key}
- **URL pattern:** {url-pattern}
- **Auth type:** {SSO/password/OAuth/etc}
- **Last updated:** {date}

## Navigation Patterns

| Destination | Method | Notes |
|:------------|:-------|:------|

## Form Interactions

## Element Selectors

| Element | Selector/Ref | Notes |
|:--------|:-------------|:------|

## Known Quirks & Workarounds

| Issue | Workaround |
|:------|:-----------|

## Lessons Learned

| Date | Context | Learning |
|:-----|:--------|:---------|
```
