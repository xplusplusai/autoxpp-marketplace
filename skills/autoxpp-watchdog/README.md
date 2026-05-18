# AutoXPP Watchdog

External safety net that monitors `lifecycle.log` for stalled phase transitions. Pure file-based detection -- zero LLM cost per tick.

## Why This Skill Matters

The autonomous execution rule says "never stop between phases -- immediately invoke the next skill." That rule is a norm. Norms can be missed. The orchestrator might draft a "Next: hand off to build" message and end the turn without actually invoking the build. The coding agent might exit silently after a context compression. A sub-agent might crash without writing a terminal log line.

None of these failures produce an error. They produce silence. The watchdog detects that silence: if a phase completion line appears in the log and the expected successor doesn't follow within a time threshold, it emits a STALL event. The orchestrator sees the STALL as a notification and resumes the chain.

Without this skill, a stalled lifecycle sits undetected until a human checks. With it, stalls are caught within 2 minutes.

## What It Detects

The watchdog enforces transition timing between every phase pair in the lifecycle:

| After | Expects | Max Gap |
|:------|:--------|:--------|
| Req-analyzer complete | Design reviewer or dev-v2 start | 120s |
| Design reviewer PASS | Dev-v2 start | 300s |
| Dev-v2 coding-complete | Build triggered | 120s |
| Build triggered | Build done or failed | 25 min |
| Build complete | Tester start | 120s |
| Tester non-green | Dev-v2 fix-loop start | 180s |
| Tester all-green | Lifecycle DONE | 120s |

It also monitors the fix-loop counter and emits circuit-breaker notifications:
- **Iteration 3** without a supervisor retrospective: `NOTICE` (orchestrator must invoke quality supervisor)
- **Iteration 4+**: `ESCALATE` (orchestrator must halt and contact human)

## How It Works

- Spawned once at lifecycle start via the Monitor tool
- Runs a poll script that tails `lifecycle.log`
- Pattern-matches the last log line against expected successors
- Emits STALL events as Monitor notifications when thresholds are exceeded
- Self-terminates when the lifecycle reaches a terminal state (`DONE` or `FAIL`)
- Idempotent on re-spawn (safe to re-arm after session resume)

## Design Choices

- **Not an LLM agent.** Detection is pattern matching over a text file -- bash + grep is enough. Zero token cost per tick.
- **Detection only, no correction.** The watchdog emits events. All corrective intelligence lives in the orchestrator. This keeps the watchdog deterministic and cheap.
- **File-based signaling.** Reads `lifecycle.log`, the same file all skills already write to. No new plumbing needed.

