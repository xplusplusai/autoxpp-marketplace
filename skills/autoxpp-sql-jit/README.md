# AutoXPP SQL JIT

Acquires temporary **read-only** SQL credentials for D365 F&O environments by automating the VS 2022 Just-In-Time credential dialog.

## Why This Skill Matters

D365 F&O internal tables — `InventTrans`, `WHSWorkLine`, `GeneralJournalEntry`, `CustTrans`, `VendTrans` — have no OData entity. The only way to query them is direct SQL. Without this skill, verifying an inventory transaction or warehouse work status requires navigating 5-10 browser screens per check — 30-60 seconds of browser interaction and 10-20x more AI tokens per data point.

With SQL JIT, the same verification is a single query that returns in ~2 seconds. This saves significant AI token cost and wall-clock time during testing and investigation. When the tester agent needs to validate 20+ data points across a test run, the difference is minutes vs. hours — and hundreds of tokens vs. thousands.

## Read-Only by Design

This skill is built for **data validation and investigation only** — never for writes.

Two layers enforce read-only:

1. **Database role** — the JIT credentials use the SQL `Reader` role. The database itself rejects write operations.
2. **Script-level guard** — the query script rejects any statement starting with `INSERT`, `UPDATE`, `DELETE`, `DROP`, `ALTER`, `CREATE`, `TRUNCATE`, `EXEC`, or `MERGE` before it reaches the database. It also injects `TOP 1000` on unbounded `SELECT` queries to prevent runaway result sets.

For write operations, use OData or the D365 UI — never SQL.

## How It Fits in the Testing Strategy

The tester agent uses a three-layer verification approach:

| Layer | Tool | When to use |
|:------|:-----|:------------|
| 1. OData | OData queries | Entities with OData endpoints — CRUD, filtered queries, cross-company |
| 2. SQL | SQL queries (this skill's output) | Internal tables, aggregates (`SUM`/`COUNT`/`GROUP BY`), cross-table joins |
| 3. Browser | `autoxpp-browser-v2` | UI behavior, form workflows, visual verification |

SQL and OData together handle the majority of data validation, reserving browser automation for cases that genuinely require UI interaction. This keeps the testing loop fast and token-efficient.

## How It Works

1. Opens VS 2022's `Tools → SQL Credentials for Dynamics 365 FinOps` menu
2. Handles reconnect/login dialogs automatically (reuses cached Windows auth tokens — no password prompt)
3. Fills the JIT request form and clicks Request Access
4. Reads the connection string from the clipboard after VS copies it
5. Parses and caches credentials per-environment in `~/.autoxpp/ude-configs.json`

Credentials expire after ~24 hours. Skills don't call SQL JIT directly — the query tool auto-signals when a refresh is needed. SQL JIT is invoked only on that signal (lazy acquisition).

## Prerequisites

| Dependency | Purpose |
|:-----------|:--------|
| VS 2022 with D365 UDE | Hosts the JIT credential dialog |
| Administrator elevation | Required for UI Automation to interact with VS |
| `pyodbc` + ODBC Driver 17/18 | For SQL queries to connect to SQL Server |
| Prior UDE connection | VS must have connected to an online environment at least once |

The skill auto-detects missing prerequisites and provides clear guidance on first use.

## Usage

```
/autoxpp-sql-jit
```

Typically invoked automatically when SQL credential refresh is needed. Can also be invoked manually to pre-acquire credentials before a testing session.
