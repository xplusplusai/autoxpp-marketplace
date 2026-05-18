# AutoXPP Test Composer

Generates structured, executable test cases from a requirement -- in parallel with analysis, before any code exists. Tests the requirement, not the implementation.

## Why This Skill Matters

Test cases written after code exists are biased toward what was built, not what was asked for. They confirm the implementation works as coded, but miss gaps between the requirement and the code. This skill writes test cases from the raw requirement text, independently of the work item decomposition, so they serve as an unbiased validator of whether the delivered code actually satisfies the original ask.

Running in parallel with `autoxpp-req-analyzer` means test cases are ready the moment coding finishes -- no waiting for a separate test planning phase. The tester agent can execute immediately after the build deploys.

## How It Works

1. **Reads `requirement.txt` directly** -- does NOT depend on `work_items.md` (independence is the point)
2. **Loads domain-specific test templates** -- D365 F&O form tests, posting tests, batch job tests, or integration pipeline tests
3. **Infers the test environment** -- derives the target D365 environment, company, and URLs from project memory, screenshots, or domain heuristics
4. **Writes structured test cases** -- each with setup data, step-by-step instructions, and specific pass conditions
5. **Includes verification queries** -- SQL or OData queries that the tester can run to verify data-layer outcomes without relying solely on the UI

## Key Design Decisions

- **Tests the requirement, not the code.** Written before code exists, so they cannot be biased toward the implementation.
- **Append-only on feedback iterations.** When a bug report arrives, new test cases are added targeting the reported issue. Existing cases are never removed -- they become regression tests.
- **Multi-X layer-3 assertions are mandatory.** For requirements that involve "multiple X per Y", at least one test case must assert the per-X output (e.g., "one `InventTrans` per batch"), not just the aggregate ("posting completed"). This catches the class of bugs that aggregate-level assertions miss.
- **Environment inference before composing.** Test cases that target the wrong environment produce 100% false negatives. The skill resolves the target environment from project memory, requirement screenshots, or domain heuristics before writing any test.

## Output Format

Each test case includes:

- **Setup** -- what records and data must exist before the test runs
- **Steps** -- navigation paths using stable identifiers (form names, menu items), not coordinates
- **Pass condition** -- specific, verifiable outcome (field value, record count, SQL query result)
- **Work item reference** -- links back to the WI it validates (when `work_items.md` is available)

