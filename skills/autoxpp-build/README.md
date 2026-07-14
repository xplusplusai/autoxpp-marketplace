# AutoXPP Build

Automates the full D365 F&O model build and deployment workflow in Visual Studio 2022 (Unified Developer Experience) via PowerShell UI Automation — zero human clicks from code change to deployed environment.

## Why This Skill Matters

Build automation is the keystone of the autonomous development loop. The coding agent writes X++ code, the build agent compiles and deploys it, and the tester agent verifies the result — all without human intervention. When a test fails, the coding agent reads the failure, fixes the code, and the build agent recompiles automatically. This loop runs unattended for hours until the task is complete or the iteration limit is reached. The developer can walk away from the computer.

Without this skill, every iteration of the code → build → test → fix cycle requires a human to navigate VS 2022 dialogs, set checkboxes, click Build, wait 1-15 minutes for compilation, dismiss post-build dialogs, and monitor deployment progress. That human dependency breaks the autonomous loop and limits AI-assisted development to one change at a time with manual handoffs.

> **Important:** Your AI tool, IDE, or CLI (e.g. Claude Code, Cursor) must be **run as Administrator** for this skill to work. It needs elevated permissions to interact with Visual Studio 2022 windows via GUI automation.

> **Do not move the mouse or interact with the screen** while this skill is running. The AI controls Visual Studio via mouse and keyboard automation (UI Automation). Any human mouse movement or clicks during UIA operations will interfere — menus open in the wrong place, clicks miss their targets, dialogs lose focus. This can cause the AI to misdiagnose the situation and restart Visual Studio unnecessarily, adding 5-10 minutes of recovery time.

## What It Automates

- **Model refresh** — triggers Extensions > Dynamics 365 > Model management > Refresh models
- **Build configuration** — opens the Full Build dialog, selects the target model, sets Sync Database and Deploy Online options
- **Compilation monitoring** — polls build status via UI Automation without bringing VS to foreground (terminal stays visible for user feedback)
- **Post-build dialog handling** — dismisses reconnect prompts, solution selection dialogs, and SDK popups automatically
- **Deployment monitoring** — reads the VS Output window via clipboard to track upload and deployment progress
- **Two-phase completion (UDE)** — distinguishes `BUILD_STATUS:SUCCEEDED` (compilation done) from `DEPLOY_STATUS:DEPLOYED` (code live on target environment). Never reports "done" after compilation alone. On a **OneBox** there is only one phase: the compile writes straight into the local runtime, so `BUILD_STATUS:SUCCEEDED` is completion.

## Prerequisites

- **PowerShell** with UI Automation assemblies (built-in on Windows)
- **Visual Studio 2022** with D365 F&O development tools (UDE **or** OneBox / Tier-1 VM)
- **Connected online environment** configured in VS for deployment — **UDE only**. On a OneBox the build compiles directly into the local `PackagesLocalDirectory`; there is no online deploy step.

## Supported Scenarios

| Trigger | How |
|---------|-----|
| Manual | `/autoxpp-build` or "build my model" |
| After code changes | AI triggers automatically after writing X++ code |
| Fix loop | Coding agent fixes a test failure, build agent recompiles and redeploys |

## Tips for Faster Builds

1. **Don't touch the mouse during UIA.** The skill drives VS 2022 via mouse and keyboard automation. Moving the mouse, clicking, or switching windows mid-build will derail it — menus miss targets, dialogs lose focus, and the skill may restart VS as recovery, costing 5-10 minutes.

2. **First build of the day is slower.** Expect 2+ minutes of overhead on the first build as VS loads extensions, updates scripts, and warms caches. Subsequent builds in the same session are significantly faster.

3. **Pre-warm VS 2022 before starting.** Launch VS as Administrator, connect to your online Dataverse environment, and let it finish loading before invoking the skill. A cold VS start adds minutes to the first build; a warm, connected VS lets the skill jump straight to compilation.

## Parameters

| Parameter | Resolution | Description |
|-----------|-----------|-------------|
| `{ModelName}` | Caller param → git auto-detect → ask user | Which model to build |
| `{SyncDatabase}` | Auto-detect from changed artifact types → ask user | Schema changes (AxTable, AxEdt, AxView, etc.) need sync; code-only (AxClass, AxForm) does not |
| `{DeployOnline}` | Auto-resolved from env type: **UDE → true**, **OneBox → false** (see SKILL.md "OneBox vs UDE Detection") | Deploy to connected online environment. OneBox has none, so this is off and Phase B (deploy monitoring) is skipped. |

