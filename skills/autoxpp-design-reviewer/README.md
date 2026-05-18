# AutoXPP Design Reviewer

Pre-coding design gate that validates the implementation approach against D365 platform patterns before a line of code is written. Catches wrong extension patterns, incorrect API choices, and missing multi-X layers before they cost a full build-deploy cycle.

## Why This Skill Matters

A build-deploy cycle in D365 F&O takes 15-30 minutes. A wrong API choice discovered at test time means fixing the code, rebuilding, redeploying, and retesting -- easily 1-2 hours lost per mistake. Multiply by 3-4 iterations on a complex requirement and the cost is a full day of wasted cycles.

This skill catches those mistakes before coding starts. It reads the work items, cross-references them against verified patterns and known anti-patterns, audits data assumptions, and produces a PASS/NEEDS-WORK/BLOCKED verdict. The coding agent cannot proceed until the design clears the gate. A 10-minute review saves hours of build-test-fix loops.

## When It Runs

The lifecycle bootloader invokes this skill automatically based on the requirement's complexity classification:

| Complexity | Design Review |
|:-----------|:-------------|
| `simple` | Skipped |
| `complex` | Recommended (auto-invoked) |
| `risky` | Mandatory (blocks coding until PASS) |

## What It Checks

1. **Requirement-to-plan traceability** -- every acceptance criterion maps to at least one work item
2. **Multi-X three-layer screening** -- for multi-X requirements, all three layers (accept, process, verify-output) are covered
3. **API choice validation** -- each WI that calls a standard API has a citation from standard code, not a guess
4. **Framework-native flow check** -- the design uses the platform's own mechanisms, not workarounds
5. **Anti-pattern screen** -- cross-references against known anti-patterns from the lessons library
6. **Data-assumption audit** -- HIGH/MED/LOW risk ranking for every assumption, with verification plans for HIGH
7. **Risk register** -- top 3-5 risks with mitigations
8. **Dependency-order sanity** -- work items are sorted correctly
9. **Test-coverage pre-check** -- test cases cover the work item set

## Verdicts

| Verdict | Meaning | Effect |
|:--------|:--------|:-------|
| **PASS** | Design is sound | Coding proceeds |
| **NEEDS-WORK** | Minor issues (1-2 missing details) | Auto-fix and re-review (max 2 rounds) |
| **BLOCKED** | Fundamental design flaw | Lifecycle halts, human must intervene |

## Supervisor Hook

The review output includes a "Supervisor Hook" section listing what the quality supervisor should watch for during the coding phase. For example: "If `doUpdate()` appears on a framework-owned status field, this is the anti-pattern flagged in WI-3 -- intervene immediately." The review's insights carry forward into active monitoring, not just a one-shot document.

