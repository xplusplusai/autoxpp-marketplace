# UIA selector reference per dialog

This document captures the UIA names, control types, and automation
patterns observed on each dialog in the Connect-to-Dataverse flow. Use
this when a selector breaks (UI rename, localization, extension update).

## 1. Reconnect to Dataverse (only shown if a prior connection exists)

| Role | Control | Selector | Pattern |
|---|---|---|---|
| Window title | Window | `Reconnect to Dataverse` | — |
| Action (switch) | Button | Name = `No` | Invoke |
| Action (keep) | Button | Name = `Yes` | Invoke |

Notes: May not appear on first-ever connect or if the previous session was cleanly disconnected. Skill treats absence as "proceed to Login."

## 2. Power Platform Tools — Login

| Role | Control | Selector | Pattern |
|---|---|---|---|
| Window title | Window | contains `Power Platform Tools` and `Connect to Dataverse` | — |
| Deployment Type | RadioButton | Name = `Office 365` | SelectionItem |
| Sign in as current user | CheckBox | Name = `Sign in as current user` | Toggle |
| Show Advanced | CheckBox | Name = `Show Advanced` | Toggle |
| Display list of orgs | CheckBox | Name = `Display list of available organizations` | Toggle |
| Submit | Button | Name = `Login` | Invoke |
| Cancel | Button | Name = `Cancel` | Invoke |

## 3. Enter environment instance url (small popup after Login)

| Role | Control | Selector | Pattern |
|---|---|---|---|
| Window title | Window | contains `Enter environment instance url` | — |
| URL input | Edit | index 0 | Value.SetValue |
| Confirm | Button | Name = `Ok` (case verified on dialog) | Invoke |
| Cancel | Button | Name = `Cancel` | Invoke |

## 4. (Progress states — no buttons, just read-only text)

Power Platform Tools dialog cycles through progress messages:
- `Validating connection to Microsoft Dataverse ...`
- `Loading Workflows and Plugin Information - Loading Messages...`
- `Loading Workflows and Plugin Information - Loading Steps...`

Skill polls Text descendants under the dialog for diagnostic output but does not interact.

Transition: dialog closes or is replaced by Select Solution (step 5).

## 5. Select Solution (`2. Select Solution`)

| Role | Control | Selector | Pattern |
|---|---|---|---|
| Window title | Window | contains `Select Solution` | — |
| Solution picker | ComboBox | first combo on dialog | ExpandCollapse + Selection |
| Solution items | ListItem | Name = `Default` (or whatever was saved to the env) | SelectionItem |
| Submit | Button | Name = `Done` | Invoke |

## 6. Client assets download (only shown if platform version is not already cached)

| Role | Control | Selector | Pattern |
|---|---|---|---|
| Window title | Window | contains `Client assets download` | — |
| Prompt body | Text | matches `Proceed with downloading ... for the version X.Y.Z ?` | — |
| Yes | Button | Name = `Yes` | Invoke |
| No | Button | Name = `No` | Invoke |

Body text is parsed with regex `version\s+([\d\.]+)` to extract the platform version.

Download policy:
- `always` → Yes
- `ask` (v1 default) → Yes (safe)
- `skip` → No (warns if version not cached)
- `skip-if-cached` → No if `%LocalAppData%\Microsoft\Dynamics365\{version}` exists, else Yes

## 7. Post-download VS exit

**Observed:** On a fresh platform version download (~20 min), `devenv.exe` exits after the F&O VS extension installs. This is not an error.

**Handling:**
1. Skill polls `Get-Process devenv -Id $pid` in a loop.
2. When the process exits, wait 15s for MSI/extension registration.
3. Relaunch `devenv.exe` via `launch_vs.ps1`.

On next launch, VS may auto-reconnect to the UDE without needing the full dialog flow again (config is now cached). Skill verifies and reports.

## File → Close Solution (pre-switch)

| Role | Control | Selector | Pattern |
|---|---|---|---|
| File menu | MenuItem | Name = `File` | ExpandCollapse |
| Close Solution | MenuItem | Name = `Close Solution` | Invoke (no-op if disabled) |

Optional: if VS prompts "Save changes?", skill clicks Yes on the save dialog.

## Debugging tips

- **UIA tree inspection:** launch `accesskit` or `inspect.exe` (Windows SDK) to see live control names.
- **Focus issues:** if `Invoke` silently fails, the handler falls back to coordinate click via `UdeSwitchUiaNative::ClickAt` after `ForceForeground`.
- **Localization:** control names like `Ok`, `Yes`, `No`, `Done`, `Login` are VS/Power Platform Tools strings. If the user runs non-English VS, names will differ and each dialog handler needs string overrides.
- **Show VS only when necessary:** per the `autoxpp-build` pattern, minimize VS between steps so the user's terminal is visible.
