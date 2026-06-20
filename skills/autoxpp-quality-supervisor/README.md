# AutoXPP Quality Supervisor

Epistemic watchdog that audits the content of design decisions during long coding phases. Where the mechanical watchdog asks "did the phase transition?", the quality supervisor asks "is the work actually good?"

## Why This Skill Matters

A prior 27-iteration doom-loop was not a mechanical failure. Every phase transitioned cleanly, the logs were healthy, the watchdog never tripped. The failure was epistemic: the coding agent's confidence was miscalibrated, anti-patterns were baked into successive iterations, and the fix-loop had no retrospective mechanism to detect the doom pattern. Each iteration cost 2-4 hours. A circuit breaker at iteration 3 would have saved ~70 hours of wasted agent work.

This skill is the missing layer. It reads the content of lifecycle artifacts -- not just their existence -- and applies a senior-engineering lens to detect assumption drift, confidence inflation, anti-pattern accretion, and scope creep before they compound into a doom-loop.

## What It Detects

The skill applies a catalog of 13 red-flag criteria (RF-1 through RF-13), including:

- **Confidence inflation** -- agent claims high confidence before test results are in
- **Anti-pattern emergence** -- framework bypasses (`doUpdate` on status fields, `splitWorkLine` + re-open) appearing in code
- **Doom-loop relapse** -- same root cause recurring across iterations
- **Scope creep** -- work items appearing that aren't in the original plan
- **Stale progress** -- progress log going silent for >20 minutes during active coding
- **Doctrinal non-response** -- supervisor injection delivered but not acknowledged

## Operating Modes

| Mode | Trigger | Depth |
|:-----|:--------|:------|
| `audit` | Periodic (~every 20 min) and on phase transitions | Standard red-flag scan |
| `deep-check` | After fix-loop iteration 3; on non-green tester verdict | Full iteration history analysis, optional DB state verification |
| `retrospective` | Mandatory at fix-loop iteration 3; at lifecycle end | Failure pattern analysis |

## Verdicts

| Verdict | Meaning | Orchestrator Action |
|:--------|:--------|:-------------------|
| **CONTINUE** | No concerns | Proceed normally |
| **WATCH** | Minor concerns, not actionable yet | Proceed, note concern |
| **INJECT** | Intervention needed | Deliver message to coding agent before it continues |
| **PAUSE** | Serious issue | Halt lifecycle, escalate to human |

## Non-Intervening by Design

The supervisor produces recommendations, not actions. It writes audit entries and injection messages. The orchestrator decides whether to deliver them. This keeps authority in the orchestrator and human layers -- the supervisor is a lens, not an actor.

