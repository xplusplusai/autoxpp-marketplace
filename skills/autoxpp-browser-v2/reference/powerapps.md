# Power Apps (play host / code apps) - Browser Automation Reference

## Site Info
- **Site key:** `powerapps`
- **URL pattern:** `https://apps.powerapps.com/play/e/{envId}/a/{appId|local}`
- **Auth type:** Microsoft Entra ID (MSAL popup + silent SSO)
- **Last updated:** 2026-10-17

## Navigation Patterns

| Destination | Method | Notes |
|:------------|:-------|:------|
| Published app | `https://apps.powerapps.com/play/e/{envId}/a/{appId}` | Host chrome + app iframe |
| Local play | `…/a/local?_localAppUrl=http://localhost:{port}/&_localConnectionUrl=http://localhost:{port}/__vite_powerapps_plugin__/power.config.json` | Vite must be the **same** app as `power.config.json`. Probe the HTML title / fonts if several Vite ports are up. |
| App UI | Interact with refs inside `iframe[name="fullscreen-app-host"]` | Snapshot refs look like `f2eNNN` / `f15eNNN`. CLI `click`/`fill`/`select` resolve the frame. |

## Form Interactions

- Dismiss the host MessageBar **"Your app is running in local mode"** (`button "Close"`) before clicking iframe controls — it intercepts pointer events.
- Native `window.confirm()` / `alert()` from the code app: snapshot shows `Modal state` with the message. **Then** `playwright-cli dialog-accept` (or `dialog-dismiss`). Do **not** also `run-code` a `page.once('dialog')` handler on the same dialog — the CLI already handled it (`Cannot accept dialog which is already handled`).
- App-rendered dialogs (React modal) are ordinary snapshot buttons, not `dialog-accept`.

### Canvas App Control Interactions

**ComboBox — Search and Select:**
Power Apps renders a transparent overlay that intercepts pointer events on dropdown options. Use keyboard navigation instead of clicking:
```bash
playwright-cli fill <combobox-ref> "SearchText"
playwright-cli press ArrowDown    # highlight first result
playwright-cli press Enter        # select it
```

**TextInput — FocusOut mode** (`TriggerOutput: "FocusOut"`, the default):
`fill()` sets the DOM value but Power Apps only fires `OnChange` on blur. Always follow with Tab:
```bash
playwright-cli fill <textbox-ref> "Value"
playwright-cli press Tab          # triggers OnChange
```

**TextInput — Delayed mode** (`TriggerOutput: ='TextInputCanvas.TriggerOutput'.Delayed`):
`fill` + `Tab` does NOT fire OnChange for Delayed inputs — `fill` doesn't dispatch the keystroke events the debounce listens for. Use real keystrokes + blur:
```bash
playwright-cli click <textbox-ref>          # focus
playwright-cli type "Value"                  # real keystrokes (not fill)
playwright-cli click <another-control-ref>   # blur commits the debounce
```
If `fill`+`Tab` "does nothing," check the control's `TriggerOutput` — it's almost certainly `Delayed`.

**Gallery Items:**
Gallery item refs are dynamic — they change on every DOM update. Always snapshot first. Each listitem contains child controls; target the specific child ref:
```yaml
- listitem "Item 1. Selected." [ref=f8e2001]:
  - button [ref=f8e2023]           # delete button
  - generic [ref=f8e2029]: Roll 1  # label
  - textbox [ref=f8e2034]          # input
```

**Buttons / Radio / Checkbox / DatePicker:**
```bash
playwright-cli click <button-ref>
playwright-cli fill <datepicker-ref> "05/29/2026"
playwright-cli press Tab
```

## Timing

Canvas Apps have internal async operations. After triggering an action, wait before the next snapshot/screenshot:

| Action | Wait | Reason |
|--------|------|--------|
| ComboBox select | 1-2s | Filtered data reload |
| TextInput OnChange (Dataverse lookup) | 3-5s | Server roundtrip |
| Button click (Patch/save) | 3-5s | Server write |
| Screen navigation | 3-5s | Full screen re-render |
| Gallery data load | 2-4s | Data source refresh |

## Visual Validation

| Signal | Meaning |
|--------|---------|
| Red/pink background on TextInput | Invalid value (OnChange validation failed) |
| Normal/white background | Value accepted |
| Notification banner | Success/error message (may auto-dismiss after a few seconds) |
| `[disabled]` on button | Preconditions not met |

## Element Selectors

| Element | Selector/Ref | Notes |
|:--------|:-------------|:------|
| Code app host | `iframe[name="fullscreen-app-host"]` | Only the iframe contains the React app |
| Local-mode banner | `alert "Your app is running in local mode"` | Close before interacting |
| Account chip | `button "Account manager for {name}"` | `{0}` in the name means not signed in |

## Known Quirks & Workarounds

| Issue | Workaround |
|:------|:-----------|
| **AADSTS160021 / `interaction_required`** after `state-load` | Cookie dumps do not restore an AAD session for the Power Apps host. `goto https://login.microsoftonline.com/` in the **main tab** (not the MSAL popup) until M365/Office loads, **then** `goto` the play URL. Save `storage-state-*.json` (not `state-*.json`) to `~/.autoxpp/cache/auth-state/{domain-key}.json`. |
| **MSAL "Sign in" opens a popup tab** | `page.context().pages()` often still has only the play page. Prefer establishing AAD in the main tab (row above) instead of driving the popup. |
| **CLI header URL stays on the play page after `tab-select`** | `tab-list` current tab is correct. Read the **snapshot YAML** — it is the selected tab. Blob preview URLs (`blob:http://localhost:…`) work this way. |
| **Default playwright daemon belongs to another project** | Do not fight over tabs. Use `playwright-cli -s={task} open --browser chrome --headed --persistent {url}` and pass `-s={task}` on every command. |
| **403 on `…/powerapps/apps/local/permissions`** | Normal for unpublished local-play apps. Not an app failure. |
| **Host React `createElement` / `componentWillReceiveProps` warnings** | Power Apps shell noise. Ignore unless the iframe app itself logs an error. |
| **Player serves cached app after deploy** | After import/publish, service worker caches the old build. Clear via: `playwright-cli eval "async () => { if('serviceWorker' in navigator){const rs=await navigator.serviceWorker.getRegistrations(); for(const r of rs) await r.unregister();} if(window.caches){const ks=await caches.keys(); for(const k of ks) await caches.delete(k);} return 'cleared'; }"` then `goto` the play URL. Wait ~25s for cold load; refs change — snapshot again. **A cold reload is not enough** (2026-10-17): leaving to `about:blank` and coming back still served the previous build, with no "old version" banner — three layout fixes looked "not deployed". Run the eval while the tab is on the player origin, before every post-import reload, and only then judge an import. |
| **`playwright-cli eval` syntax** | Takes a function (`async () => {...}`), NOT an invoked IIFE — `(()=>{...})()` errors with "result is not a function". |
| **Reloading the player after a `pac solution import`** | `goto <play url>` can leave the tab on `about:blank` because the app raises a `beforeunload` dialog. Sequence: `goto`, `dialog-accept` (sometimes needed twice), wait ~25 s, snapshot, ref-click the **"You're using an old version" → Refresh** banner (host chrome, refs are stable there), wait ~20 s. If `snapshot`/`screenshot` then return empty, send one more `dialog-accept`. |
| **Ref clicks inside the app iframe drift** | After the canvas app re-renders, a ref from the last snapshot can resolve to another control (a "+ New Case" ref hit the sidebar's Feedback item; a "Home" ref opened SLA). Use pointer coordinates at 1920×1080 for everything inside the app; keep ref clicks for host chrome only (Refresh banner, host dialogs). |
| **Host bar "Settings" gear vs app Settings** | A `click` on `button "Settings"` by name hits the Power Apps **host** gear, navigates the tab away and detaches the player ("Session closed", blank tab). Pick the app's Settings by coordinates or by position next to another app control; recover with `-s=<session> close` + reopen. |
| **Opening Studio from the player session** | A Studio detour in the same playwright session leaves the player session with blank tabs and lost refs. Open Studio in a **separate named session** (`-s=studio`), leave via the Apps breadcrumb + `dialog-accept` to release the edit lock. |
| **Custom nav items (label + image under a transparent rectangle)** | `click <ref>` on the item dispatches to the label and does nothing. Pointer click at the item's coordinates; verify the target screen's marker and retry per SKILL.md Section 4 "Navigation Verification and Retry" — these clicks are occasionally lost. |
| **Glass/blur popups (`htmlViewer` backdrop)** | `click`/`fill <ref>` on anything inside never passes the actionability check and hangs the daemon. Pointer clicks + `type`/`press` only, every command wrapped in `timeout 40` (full pattern in the `pp-canvas-test` skill). |
| **Classic chart data is in the accessibility tree** | `pieChart`/`barChart` expose their data as an accessible table ("Pie chart data"/"Bar chart data") with full labels — assert on that, not on the rendered (truncated) axis labels. |

## Lessons Learned

| Date | Context | Learning |
|:-----|:--------|:---------|
| 2026-08-17 | TC MSDS local play | Silent SSO fails with AADSTS160021 on a fresh named-session profile even after `state-load`. Warm Microsoft login in the main tab first. |
| 2026-08-17 | Preview `blob:` tab | After `tab-select 1`, screenshot/snapshot YAML is the preview; the CLI "Page URL" line may still print the opener. |
| 2026-08-17 | Native confirm | Arm nothing extra. Click the in-app button, wait for `Modal state`, then `dialog-accept`. |
| 2026-10-16 | CaseFusionPro regression (129 cases) | Driving a plan this size by hand is a model turn per click. Scripted it as `tests/regression/` (lib.sh + per-screen tests + results + plan updater) per SKILL.md Section 5 "Scripted Regression Harness"; a full run then costs one start command plus one results file read. |
| 2026-10-16 | Search box in assertions | A searched-for name is always "present" via the search textbox's own value; exclude that subtree before presence/absence checks. |
| 2026-10-16 | Stray `Control+a` | Selects the whole page when no textbox is focused; later mousedowns become text drags and clicks are silently lost. Neutral click on a blank band before every nav/search. |
| 2026-10-17 | Layout change broke the harness, not the app | Widening a gallery column moved the trash icon under the hardcoded row-select x (500 → trash at 497); three "failures" were a delete dialog opening. Per-screen `ROW_X`, re-discover coordinates after any layout change. |
| 2026-10-17 | `pac` import then player | Player shows the stale build until the Refresh banner is clicked; `goto` alone leaves `about:blank` behind a beforeunload dialog (row above). |
| 2026-10-17 | "My fix is not deployed" | Before re-packing or bisecting, prove the bundle: unzip the packed `.msapp` and grep `Controls/*.json` for the new formula text, then clear the player's service worker (quirk row) and cold-load. The edits were in the package all along; the player had served the cached build without a banner. A harness that reloads the player must clear the worker first (`clear_player_cache` in the CaseFusionPro `lib.sh`). |
