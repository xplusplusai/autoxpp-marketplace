# AutoXPP Browser v2

Browser automation for D365 Finance & Operations via Playwright CLI — persistent authentication, self-learning site patterns, and structured evidence capture.

## Why This Skill Matters

Browser automation is the other half of the autonomous development loop. After the build agent deploys code, the tester agent uses this skill to open D365 in a real browser, execute test cases against the live UI, and capture screenshot evidence of every step. When a test fails, the failure report feeds back to the coding agent — which fixes the code, triggers a rebuild, and retests automatically. No human in the loop. The developer can step away from the computer while agents run the full code → build → test → fix cycle for hours unattended.

D365 F&O is a browser-based ERP with deeply nested forms, multi-step workflows, async loading, and session-dependent state. Standard browser automation breaks constantly against it — Google OAuth blocks Playwright's default browser, sessions expire mid-test, and form elements load asynchronously. This skill solves all of that so the tester agent can focus on test execution, not browser mechanics.

## How It Fits in the Testing Strategy

The tester agent uses a three-layer verification approach, choosing the cheapest method that can express each check:

| Layer | Tool | Best for | Cost |
|:------|:-----|:---------|:-----|
| 1. OData | OData queries | CRUD on exposed entities, filtered queries | Lowest — no credentials needed, ~1s per call |
| 2. SQL | SQL queries | Internal tables, aggregates, cross-table joins | Low — ~2s per query, requires JIT credentials |
| 3. Browser | This skill | UI behavior, form workflows, visual verification | Highest — 30-60s per interaction, screenshots |

SQL and OData handle the bulk of data validation. Browser automation is reserved for what genuinely requires the UI: button clicks that trigger business logic (posting, reservation dialogs), form workflows with validation, and visual evidence capture. This mix keeps AI token costs low — a SQL query that replaces 5-10 browser navigations saves 10-20x in tokens.

## Key Capabilities

- **Per-session Chrome profile isolation** — copies the user's Chrome profile to a session-scoped temp directory. Multiple CLI sessions never share or corrupt each other's browser state.
- **Authentication priority chain** — Chrome profile (bypasses OAuth blocks) → Playwright state-load → manual login. Auth is always restored before navigating anywhere.
- **Self-learning site patterns** — discovered navigation paths, form quirks, and workarounds are saved to reference files and reused across sessions.
- **Persistent sessions** — `--headed --persistent` mode survives D365 deployments that invalidate sessions. Re-auth once instead of after every deploy.
- **Evidence capture** — structured screenshot capture at each test step, stored alongside the test report.

## Prerequisites

| Dependency | Install |
|:-----------|:--------|
| Node.js | Required for npm |
| `@playwright/cli` | `npm install -g @playwright/cli` |
| Chromium browser | `playwright-cli install-browser` |
| Built-in skill docs | `cd ~ && playwright-cli install --skills` (one-time) |

The skill auto-detects missing dependencies on first use and guides installation — no manual setup needed.

