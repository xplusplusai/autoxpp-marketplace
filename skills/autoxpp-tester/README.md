# AutoXPP Tester

Executes structured test cases against a live D365 F&O environment using a three-layer verification strategy — OData, SQL, and browser — to maximize coverage while minimizing AI token cost.

## Why This Skill Matters

The tester agent closes the autonomous development loop. After the build agent deploys code, the tester executes every test case from `test_cases.md`, captures evidence, and produces a structured pass/fail report. If any test fails, the report feeds directly to the coding agent for automatic fix — no human review needed between iterations. This is what enables the full unattended code → build → test → fix cycle.

## Three-Layer Verification Strategy

For every data check, the tester picks the cheapest method that can express the assertion:

| Layer | Tool | Best for | Token cost | Speed |
|:------|:-----|:---------|:-----------|:------|
| 1. OData | OData queries | Entities with endpoints — CRUD, filtered queries | Lowest | ~1s |
| 2. SQL | SQL queries | Internal tables, aggregates, joins | Low | ~2s |
| 3. Browser | `autoxpp-browser-v2` | UI behavior, form workflows, visual evidence | Highest | 30-60s |

**OData first** — no credential acquisition step, works for any entity Microsoft ships. **SQL second** — handles internal tables (`InventTrans`, `WHSWorkLine`, `GeneralJournalEntry`) and aggregate queries that OData cannot express. **Browser last** — reserved for testing UI-specific behavior: button clicks that trigger business logic, form workflows with validation, posting dialogs, and screenshot evidence.

For D365 F&O, the primary testing surface is the UI — business processes like sales order posting, warehouse execution, and inventory journals are driven through forms. But data validation behind those processes (did the correct `InventTrans` rows get created? Is the warehouse work status correct?) is far cheaper via SQL and OData. The tester uses browser automation for the business process execution, then SQL/OData for the data assertions — the best of both approaches.

## Test Report

The tester produces `test_report.md` with per-test-case status:

| Status | Meaning |
|:-------|:--------|
| **PASS** | All assertions met, evidence captured |
| **FAIL** | One or more assertions failed — triggers fix loop |
| **PARTIAL** | Some assertions passed, others inconclusive — triggers fix loop |
| **BLOCKED** | Cannot execute (missing data, environment issue) — triggers fix loop |

Any non-green result (`fail > 0` or `partial > 0` or `blocked > 0`) automatically triggers the fix loop: the coding agent reads the failure details, fixes the code, the build agent recompiles, and the tester retests. Up to 3 iterations before escalation.

