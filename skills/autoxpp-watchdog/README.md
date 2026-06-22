# AutoXPP Watchdog

Lightweight background LLM agent that monitors lifecycle progress and detects stalled phase transitions.

## Why This Skill Matters

The autonomous execution rule says "never stop between phases -- immediately invoke the next skill." That rule is a norm. Norms can be missed. The orchestrator might draft a "Next: hand off to build" message and end the turn without actually invoking the build. The coding agent might exit silently after a context compression. A sub-agent might crash without writing a terminal log line.

None of these failures produce an error. They produce silence. The watchdog detects that silence: if a phase completion line appears in the log and the expected successor doesn't follow within a time threshold, it writes a STALL alert to `lifecycle.log`. The orchestrator's tail-f Monitor picks it up and acts.

The watchdog also serves as the lifecycle's **progress ticker** -- every 5 minutes it reads workspace files to determine what the current phase is doing and appends a `[watchdog] PROGRESS tick` with meaningful context. This lets external platforms (S2) distinguish "long build in progress" from "agent hung" without every phase agent needing ticking instructions.

## What It Detects

### Stall transitions

| After | Expects | Budget |
|:------|:--------|:-------|
| Req-analyzer complete | Design reviewer or dev-v2 start | 5 min |
| Design reviewer PASS/NEEDS-WORK | Dev-v2 start | 10 min |
| Design reviewer BLOCKED | Lifecycle FAIL | 5 min |
| Dev-v2 coding-complete | Build triggered | 5 min |
| Build triggered | Build done or failed | 30 min |
| Build complete | Tester start | 5 min |
| Tester non-green | Dev-v2 fix-loop or lifecycle FAIL | 10 min |
| Tester all-green | Lifecycle DONE | 5 min |

### Fix-loop circuit breaker

- **Iteration 3** without a supervisor retrospective: `NOTICE` (orchestrator must invoke quality supervisor)
- **Iteration 4+**: `ESCALATE` (orchestrator must halt and contact human)

## How It Works

- Spawned once at lifecycle start as a background `Agent()`
- Runs a 5-minute cycle: reads `lifecycle.log`, `agent_conversation.txt`, and checks file activity per phase
- Writes `[watchdog] PROGRESS tick` lines with context (current phase, what file changed, summary)
- Writes `[watchdog] STALL` lines when transitions are missed past their budgets
- The orchestrator's single tail-f Monitor over `lifecycle.log` delivers both PROGRESS and STALL events
- No lifespan limit -- runs until lifecycle reaches a terminal state (`DONE` or `FAIL`)
- Idempotent on re-spawn (safe to re-arm after session resume)

## Design Choices

- **LLM agent, not bash script.** The prior bash approach could only regex-match log lines. An LLM agent reads `agent_conversation.txt` for blocker context, checks `progress.md` for dev-v2 status, and counts tester artifacts -- producing meaningful tick summaries instead of bare timer pings. Token cost is negligible at haiku tier.
- **5-minute poll interval.** D365 F&O operations are long (builds 10-30 min, tests 30-60 min). 30-second polling was noise. 5 minutes matches the work rhythm.
- **Writer, not pure observer.** Writing to `lifecycle.log` serves two purposes: external consumers get progress ticks, and STALL alerts reach the orchestrator via the existing Monitor (one Monitor instead of two).
- **Detection only, no correction.** The watchdog writes events. All corrective intelligence lives in the orchestrator.
