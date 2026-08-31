# Power Apps (play host / code apps) - Browser Automation Reference

## Site Info
- **Site key:** `powerapps`
- **URL pattern:** `https://apps.powerapps.com/play/e/{envId}/a/{appId|local}`
- **Auth type:** Microsoft Entra ID (MSAL popup + silent SSO)
- **Last updated:** 2026-08-17

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

## Lessons Learned

| Date | Context | Learning |
|:-----|:--------|:---------|
| 2026-08-17 | TC MSDS local play | Silent SSO fails with AADSTS160021 on a fresh named-session profile even after `state-load`. Warm Microsoft login in the main tab first. |
| 2026-08-17 | Preview `blob:` tab | After `tab-select 1`, screenshot/snapshot YAML is the preview; the CLI "Page URL" line may still print the opener. |
| 2026-08-17 | Native confirm | Arm nothing extra. Click the in-app button, wait for `Modal state`, then `dialog-accept`. |
