# autoxpp-ude-switch

Quick-switch Visual Studio 2022 UDE between multiple online D365 F&O environments (different customers) on a single developer machine.

## Why

One UDE VM for multiple customers is more efficient than maintaining several VMs (each VM needs its own VS install, extensions, skills, MFA enrollment, Windows updates). But manual switch steps — close solution, Tools menu, Reconnect dialog, Login, URL, Select Solution, Client assets download — take ~5 min of clicking per switch. This skill automates that.

## What the skill does

| Phase | Actions |
|---|---|
| **A — Pre-flight** | Load `ude-configs.json`, validate target, snapshot `XPPConfig\` folder. |
| **B — VS UIA** | Launch/show VS → close any open solution → Tools → Connect to online Dataverse → Reconnect dialog (click No) → Login → URL → wait for validation → Select Solution → Client assets download prompt. |
| **C — Post-switch** | Retarget `ModelStoreFolder`/`DebugSourceFolder` in the auto-generated XPP config JSON to the customer-specific path (critical — without this, all UDEs collide on one metadata folder). Update `lastUsed`/`lastKnownVersion`. |

## What the skill does NOT do

- Install Power Platform Tools extension (one-time manual setup)
- Toggle "Skip Discovery when connecting to Dataverse" (one-time manual setup)
- Avoid MS's monthly platform version bumps (they trigger re-downloads; not avoidable for online envs)
- Handle MFA prompts (Windows WAM does; user completes with Windows Hello)
- Clone custom metadata repos (surface a warning if folder is missing)

> **Do not move the mouse or interact with the screen** while this skill is running. The AI controls Visual Studio via mouse and keyboard automation (UI Automation). Any human mouse movement or clicks during UIA operations will interfere — menus open in the wrong place, clicks miss their targets, dialogs lose focus. This can cause the AI to misdiagnose the situation and restart Visual Studio unnecessarily, adding 5-10 minutes of recovery time.

## Known limitations (v1)

- English VS only (control names are hardcoded).
- Download policy `ask` = always Yes. Auto-skip when cached needs validation against a live "re-enter same UDE" flow before enabling.
- Cross-tenant account picker is surfaced to the user (MFA) — no auto-selection. Intentional: WAM handles this securely.
