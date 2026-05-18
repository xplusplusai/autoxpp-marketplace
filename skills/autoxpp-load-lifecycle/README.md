# AutoXPP Load Lifecycle

Bootloader that crosses the boundary from research to autonomous execution. A single invocation replaces a multi-step intake recipe: resolve workspace, write requirement, initialize logs, arm the watchdog, and launch parallel analysis.

## Why This Skill Matters

Before this skill existed, starting a requirement lifecycle required the orchestrator to remember and execute a precise sequence: pick a workspace folder, write `requirement.txt`, create `lifecycle.log`, spawn the watchdog via Monitor, launch `req-analyzer` and `test-composer` in parallel, and anchor the routing table in context. Miss any step and the lifecycle drifts -- a forgotten watchdog means stalls go undetected, a missing routing table means the orchestrator stops between phases instead of auto-chaining.

This skill collapses that fragile recipe into one invocation. It also enforces the Lifecycle Boundary Rule: phase skills (`req-analyzer`, `test-composer`, `dev-v2`, `build`, `tester`) are never invoked directly. All lifecycle work starts here.

## What It Does

1. **Resolves workspace** -- from a DevOps ticket URL, free text, explicit path, or auto-detection of an in-progress lifecycle
2. **Writes `requirement.txt`** -- fetches ticket details from Azure DevOps (including comments, attachments, inline screenshots) or writes user-provided text verbatim
3. **Initializes workspace layout** -- creates the canonical folder structure (`system/`, `logs/`, `supervisor_injections/`, `artifacts/`)
4. **Arms the watchdog** -- spawns the lifecycle watchdog via Monitor to catch stalled transitions
5. **Launches parallel analysis** -- `autoxpp-req-analyzer` (foreground, produces work items) and `autoxpp-test-composer` (background, produces test cases) run simultaneously
6. **Gates on design review** -- for complex/risky requirements, invokes the design reviewer before coding can proceed
7. **Spawns test data seeder** -- optionally pre-seeds test data in the background while the coding agent works
8. **Echoes the routing table** -- prints the full phase-transition routing table into the orchestrator's context so it cannot be lost on context compression

## Input Flexibility

| Argument Shape | Behavior |
|:---------------|:---------|
| DevOps URL | Fetches ticket via `autoxpp-azure-devops`, builds requirement from description + comments |
| Free text | Writes verbatim to `requirement.txt` |
| Workspace path | Resumes an existing in-progress lifecycle |
| Empty | Auto-detects the latest active lifecycle, or asks for input |

## Routing Table

After arming the lifecycle, the skill prints a mandatory routing table that the orchestrator consults after every phase completion:

```
req-analyzer done + simple       --> dev-v2 (skip design review)
req-analyzer done + complex/risky --> design-reviewer
design-reviewer PASS             --> dev-v2
dev-v2 done                      --> build
build done                       --> tester
build fail                       --> dev-v2 (fix-loop)
tester green                     --> DONE
tester non-green (N<3)           --> dev-v2 (fix-loop)
tester non-green (N=3)           --> quality-supervisor retrospective
tester non-green (N>=5)          --> FAIL + escalate to human
```

## Fix-Loop Circuit Breaker

The skill defines the circuit breaker that prevents runaway fix-loops:
- **Iteration 3**: mandatory quality supervisor retrospective before proceeding
- **Iteration 4**: allowed only if the retrospective did not PAUSE
- **Iteration 5+**: automatic FAIL, lifecycle halts

