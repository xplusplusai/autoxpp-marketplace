# autoxpp-ude-switch

Quick-switch Visual Studio 2022 UDE between multiple online D365 F&O environments (different customers) on a single developer machine.

## Why

One UDE VM for multiple customers is more efficient than maintaining several VMs (each VM needs its own VS install, extensions, skills, MFA enrollment, Windows updates). But manual switch steps — close solution, Tools menu, Reconnect dialog, Login, URL, Select Solution, Client assets download — take ~5 min of clicking per switch. This skill automates that.

## Usage

```
/autoxpp-ude-switch                          # interactive picker (arrow select)
/autoxpp-ude-switch <name>                   # switch to named UDE
/autoxpp-ude-switch <name> --close-existing  # close open VS first, then switch (fresh session)
/autoxpp-ude-switch <name> --no-download     # skip metadata download (warn)
/autoxpp-ude-switch --current                # show current active UDE
/autoxpp-ude-switch --list                   # list configured UDEs
/autoxpp-ude-switch --add                    # interactive add flow
```

## What the skill does

| Phase | Actions |
|---|---|
| **A — Pre-flight** | Load `ude-configs.json`, validate target, snapshot `XPPConfig\` folder. |
| **B — VS UIA** | Launch fresh VS (close existing if approved via `--close-existing`) → verify "Skip Discovery" is ON in Tools > Options → close any open solution → Tools → Connect to online Dataverse → Reconnect dialog (click No) → Login → URL → wait for validation → Select Solution → Client assets download prompt. |
| **C — Post-switch** | Retarget `ModelStoreFolder`/`DebugSourceFolder` in the auto-generated XPP config JSON to the customer-specific path (critical — without this, all UDEs collide on one metadata folder). Update `lastUsed`/`lastKnownVersion`. |

## Key behavioral rules

- **Fresh VS session required.** If VS is already open with a Dataverse connection, it auto-reconnects and skips the instance-URL popup — silently keeping the old environment. The skill exits with code 2 so the orchestrator can get user approval before closing VS. Pass `--close-existing` when approval is already given.
- **Skip Discovery auto-verified.** The pre-flight step opens Tools > Options and confirms "Skip Discovery when connecting to Dataverse" is checked. Without it, VS shows a discovery flow instead of the URL popup and the switch cannot target a specific environment.

## What the skill does NOT do

- Install Power Platform Tools extension (one-time manual setup)
- Avoid MS's monthly platform version bumps (they trigger re-downloads; not avoidable for online envs)
- Handle MFA prompts (Windows WAM does; user completes with Windows Hello)
- Clone custom metadata repos (surface a warning if folder is missing)

> **Do not move the mouse or interact with the screen** while this skill is running. The AI controls Visual Studio via mouse and keyboard automation (UI Automation). Any human mouse movement or clicks during UIA operations will interfere — menus open in the wrong place, clicks miss their targets, dialogs lose focus. This can cause the AI to misdiagnose the situation and restart Visual Studio unnecessarily, adding 5-10 minutes of recovery time.

## Known limitations (v1)

- English VS only (control names are hardcoded).
- Download policy `ask` = always Yes. Auto-skip when cached needs validation against a live "re-enter same UDE" flow before enabling.
- Cross-tenant account picker is surfaced to the user (MFA) — no auto-selection. Intentional: WAM handles this securely.
- VS2022 may freeze (Responding=False) after a switch attempt. Root cause under investigation — happens with both empty and non-empty metadata folders. If VS freezes, kill it manually and relaunch.
