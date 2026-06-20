<p align="center">
  <img src=".github/autoxpp-logo.svg" alt="AutoXPP" width="80" height="80">
</p>

<h1 align="center">AutoXPP</h1>

<p align="center">
  <strong>Multi-Agent AI Development System for D365 Finance & Operations</strong><br>
  A team of specialized AI agents that collaborate to turn a plain-English requirement into working, tested X++ code — autonomously.
</p>

<p align="center">
  Built for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a> by <a href="https://www.xplusplus.ai">XPLUSPLUS.AI</a>
</p>

---

## What It Does

AutoXPP is a multi-agent system of 20 specialized AI skills that together form a complete D365 F&O development pipeline. Each agent handles one phase — analysis, coding, building, testing — and hands off to the next automatically. Feed it a requirement and walk away:

1. **Analyst agent** decomposes the requirement into structured work items
2. **QA agent** writes test cases in parallel
3. **Design reviewer** validates the approach against D365 patterns
4. **Developer agent** writes X++ metadata artifacts
5. **Build agent** compiles and deploys via Visual Studio 2022 (zero human clicks)
6. **Tester agent** verifies end-to-end in the live D365 environment
7. **On failure:** the developer agent reads the test report, fixes the code, rebuilds, and retests — automatically, with a mandatory quality review at iteration 3 and a hard limit of 5

The developer can step away from the computer. The agents run the full code → build → test → fix loop unattended for hours until the task is complete or the iteration limit is reached. No human in the loop between phases.

Each agent is a standalone skill. Use the full lifecycle or invoke individual skills for targeted tasks like "build and deploy this model" or "run a SQL query against the dev database."

---

## The Lifecycle — Main Use Case

```
  Requirement
  (DevOps ticket, free text, or conversation)
       │
       ▼
  ┌─────────────────────────────────┐
  │  /autoxpp-load-lifecycle        │  Bootloader — creates workspace,
  │                                 │  arms watchdog, launches parallel
  │                                 │  analysis
  └────────┬────────────────────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
  Req Analyzer  Test Composer        Parallel: decompose requirement
  (work items)  (test cases)         into work items + test cases
     │           │
     ▼           │
  Design Review  │                   Quality gate for complex/risky
  (if needed)    │                   requirements
     │           │
     ▼           ▼
  ┌─────────────────────────────────┐
  │  Dev-v2 (X++ Coding Agent)      │  Writes metadata artifacts in
  │                                 │  dependency order, guided by
  │                                 │  D365 reference patterns
  └────────┬────────────────────────┘
           │
           ▼
  ┌─────────────────────────────────┐
  │  Build (VS 2022 Automation)     │  Compile → sync DB → deploy
  │                                 │  to online environment
  └────────┬────────────────────────┘
           │
           ▼
  ┌─────────────────────────────────┐
  │  Tester (Browser + SQL)         │  Execute test cases, capture
  │                                 │  evidence, produce report
  └────────┬────────────────────────┘
           │
      ┌────┴────┐
      ▼         ▼
   All pass   Failures
      │         │
      ▼         ▼
   DONE      Fix loop ──► Dev-v2 ──► Build ──► Tester
             (auto, up to 3 iterations)
```

The watchdog monitors the entire lifecycle and alerts on stalled transitions. A quality supervisor audits design decisions and flags epistemic drift on complex requirements.

---

## Skill Catalog

### Core Development

| Skill | Tier | Purpose |
|:------|:-----|:--------|
| **autoxpp-dev-v2** | Pro | X++ coding agent. Reads work items, loads D365 reference patterns, writes metadata artifacts (classes, tables, forms, extensions, security). Follows dependency order and logs every design decision. |
| **autoxpp-build** | Pro | Drives Visual Studio 2022's full build-deploy cycle via PowerShell UI Automation. Zero human clicks — compile, sync database, deploy to online environment, all automated. |
| **autoxpp-browser-v2** | Free | Browser automation via Playwright CLI. Self-learning site patterns, persistent auth state, evidence capture. Handles D365's complex SPA forms and multi-step business processes. |

### Analysis & Quality Gates

| Skill | Tier | Purpose |
|:------|:-----|:--------|
| **autoxpp-req-analyzer** | Pro | Decomposes a requirement into structured work items with dependency order, artifact types, and complexity classification. |
| **autoxpp-test-composer** | Pro | Generates structured test cases from the requirement, including setup steps, expected outcomes, and verification queries. |
| **autoxpp-design-reviewer** | Pro | Pre-coding design review gate. Validates the proposed solution against D365 patterns and flags risks before a single line of code is written. |
| **autoxpp-quality-supervisor** | Pro | Epistemic watchdog. Audits design decisions, detects assumption drift, and injects corrections during long coding phases. |

### Testing & Verification

| Skill | Tier | Purpose |
|:------|:-----|:--------|
| **autoxpp-tester** | Pro | Executes test cases via browser automation and SQL queries. Produces structured pass/fail reports with evidence. |
| **autoxpp-test-data-seeder** | Pro | Background agent that pre-seeds test data while the developer agent is still analyzing code — uses idle environment time. |
| **autoxpp-sql-jit** | Free | Acquires temporary read-only SQL credentials from VS 2022's JIT dialog via UI Automation. Enables direct database queries for test verification and investigation without browser overhead — dramatically faster and cheaper than navigating D365 forms to check data. |

### Environment & Infrastructure

| Skill | Tier | Purpose |
|:------|:-----|:--------|
| **autoxpp-ude-switch** | Free | Switches VS 2022's Unified Developer Experience between multiple D365 environments on a single machine. One dev VM serves multiple customers. |
| **autoxpp-azure-devops** | Free | Azure DevOps REST API client. Reads and queries work items, comments, attachments, and boards directly from Claude Code. |
| **autoxpp-load-lifecycle** | Pro | Bootloader that transitions from research to autonomous execution. Creates the workspace, arms the watchdog, and launches the first phases. |
| **autoxpp-watchdog** | Pro | External safety net. Monitors lifecycle.log for stalled phase transitions and emits alerts when expected successor events are missing. |

### Role Loaders

Skills that load a specialized persona before pre-lifecycle work (investigation, debugging, planning):

| Skill | Tier | Role |
|:------|:-----|:-----|
| **autoxpp-load-senior-fo-dev** | Pro | Senior D365 F&O Developer — for code research, debugging, solution design |
| **autoxpp-load-integration-dev** | Pro | Integration Developer — for Azure Functions, Service Bus, Dataverse plugins |
| **autoxpp-load-qa-engineer** | Pro | QA Engineer — for test planning, data strategy, coverage analysis |

---

## Why Each Layer Matters

### Why SQL JIT?

SQL JIT is designed for **read-only data access** — it acquires temporary credentials with the SQL `Reader` role, and `sql.py` additionally rejects any write statement before it reaches the database. Both layers enforce read-only by design.

D365 F&O internal tables (`InventTrans`, `WHSWorkLine`, `GeneralJournalEntry`) have no OData entity — the only way to query them is direct SQL. The JIT skill auto-acquires temporary read-only credentials by driving the VS 2022 dialog via UI Automation. This lets the AI agent verify test results with a single SQL query instead of navigating 5-10 browser screens — dramatically faster and cheaper. A SQL query returns in ~2 seconds; the equivalent browser verification takes 30-60 seconds and 10-20x more AI tokens navigating forms, waiting for page loads, and parsing screenshots.

The tester agent uses a three-layer verification strategy: OData for entities that have endpoints, SQL for internal tables and aggregate queries, and browser for UI-specific checks. SQL and OData handle the bulk of data validation, reserving browser automation for cases that genuinely require UI interaction. This mix keeps token costs low while maintaining thorough test coverage.

### Why Build Automation?

Build automation is the keystone that makes unattended multi-agent development possible. Without it, every code → build → test → fix iteration requires a human to click through VS 2022 dialogs, wait for compilation, and trigger deployment. With it, the coding agent writes X++ code, the build agent compiles and deploys it autonomously, and the tester agent verifies the result — all without human intervention. This is what enables a developer to walk away from the computer while agents iterate for hours until the task is complete.

D365 builds take 1-15 minutes and involve navigating modal dialogs, setting checkboxes, monitoring progress bars, and waiting for online deployment. The build skill handles all of this via PowerShell UI Automation — triggering builds, polling status without bringing VS to foreground, dismissing post-build dialogs, and monitoring deployment to the online environment. Combined with browser automation, it closes the full autonomous development loop.

### Why Browser Automation?

Browser automation is the other half of the autonomous development loop. After the build agent deploys code, the tester agent opens D365 in a browser, executes test cases against the live UI, and captures screenshot evidence. If a test fails, the failure feeds back to the coding agent automatically — triggering a fix, rebuild, and retest without human involvement. Like the build skill, this is what lets the developer step away while agents iterate.

D365 F&O is a browser-based ERP with deeply nested forms, multi-step workflows, and session-dependent state. The browser skill handles authentication (persistent Chrome profiles bypass OAuth blocks), learns site-specific patterns, and captures screenshot evidence of test results. While SQL and OData handle the majority of data validation (faster and cheaper), browser automation is essential for testing UI behavior — button clicks that trigger business logic, form workflows like posting and reservation, and visual verification of form state.

### Why a Design Review Gate?

D365 customization is expensive to fix post-build. A wrong extension pattern or incorrect API choice costs a full build-deploy cycle (15-30 minutes). The design reviewer catches these before coding starts, validating the approach against D365 platform patterns.

### Why a Watchdog?

Autonomous multi-phase execution can stall silently — a sub-agent exits, a phase forgets to chain the next one, or context compression loses the routing table. The watchdog monitors the lifecycle log and emits alerts when expected transitions don't happen within a time window.

---

## Demo

Watch the [full lifecycle demo](https://www.youtube.com/watch?v=EaxUN7lpuX0) — from requirement to tested code, unattended.

---

## Installation

See [xplusplus.ai/install.html](https://xplusplus.ai/install.html) for setup instructions.

---

## Quick Start

### Full Lifecycle (requirement to tested code)

```
/autoxpp-load-lifecycle

Implement a batch job that processes staging records and posts inventory journals.
```

### Individual Skills

```
/autoxpp-build                    # Compile and deploy the current model
/autoxpp-sql-jit                  # Acquire SQL credentials for the active environment
/autoxpp-browser-v2               # Open a browser session for testing
/autoxpp-ude-switch my-dev1       # Switch VS to a different environment
/autoxpp-load-senior-fo-dev       # Load the senior developer persona for investigation
```

### Direct SQL Query (after credentials are cached)

```bash
python ~/.autoxpp/cache/scripts/sql.py query \
  --env <env-name> \
  --sql "SELECT TOP 10 * FROM InventTrans WHERE DataAreaId = '1000'" \
  --format table
```

---

## License

See [AutoXPP License](https://xplusplus.ai/legal/autoxpp-license.html) for terms. You own all generated artifacts; the skill definitions and reference materials remain the property of the licensor.

---

[XPLUSPLUS.AI](https://www.xplusplus.ai) | [contact@xplusplus.ai](mailto:contact@xplusplus.ai)
