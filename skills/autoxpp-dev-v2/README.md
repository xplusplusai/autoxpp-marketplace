# AutoXPP Dev v2

The core X++ coding engine for D365 Finance & Operations. Reads structured work items, loads verified platform patterns from the shared reference library, and writes metadata artifacts in dependency order -- fully autonomous, no human prompts during execution.

## Why This Skill Matters

D365 F&O development is not general-purpose coding. The platform has strict conventions for extensions, posting frameworks, batch jobs, security privileges, and form patterns. Getting any of these wrong produces a build failure or a runtime error that costs 15-30 minutes per rebuild cycle. This skill encodes those conventions as mandatory pre-coding reference loads, so the agent writes correct X++ the first time instead of guessing and iterating.

Without this skill, an AI coding agent would write plausible-looking X++ that fails on platform-specific details: wrong extension patterns, incorrect security XML structure, missing `super()` calls, or form event handler signatures that don't match the framework. Each failure triggers a full build-deploy cycle before the error is even discovered. This skill prevents that class of failure by loading the right pattern before writing a single line.

## How It Works

1. **Reads `work_items.md`** -- structured work items produced by the requirement analyzer, already sorted by dependency
2. **Loads reference patterns** -- for each work item's artifact type (table, form, class extension, posting, batch, security, report), loads the corresponding verified pattern from `autoxpp-dev-reference`
3. **Implements in dependency order** -- base data structures before consumers, contracts before callers, source tables before extension classes
4. **Writes metadata artifacts** -- X++ class files, table XML, form XML, EDT definitions, security privileges, menu items -- all to the correct FO metadata folder structure
5. **Exits cleanly** -- writes `coding-complete` to lifecycle log and hands off to the build agent. Does not build, does not test.

## Design Review Integration

For requirements classified as `complex` or `risky`, the design reviewer produces a `design_review.md` before this skill runs. The coding agent reads the review verdict, executes any pre-coding tasks (verify assumptions, read specific standard code), and acknowledges the review in its progress log. A `NEEDS-WORK` or `BLOCKED` verdict stops coding entirely -- the design gate has teeth.

## Fix Loop

When test failures arrive via `test_report.md`, the skill re-enters in fix mode: reads the failures, traces them back to specific work items, fixes the code, and exits for another build-test cycle. Progress is logged continuously so the quality supervisor can detect drift.

## Key Principles

- **Never guess at APIs** -- load the reference pattern first, read standard code second, write custom code third
- **Never prompt for input** -- if stuck, write the question to the conversation log and continue with best judgment
- **Dependency order is non-negotiable** -- the requirement analyzer sorted the work items; implement them in that order
- **Progress logging is mandatory** -- the quality supervisor reads the progress log to catch assumption drift, so every decision, every file read, every assumption gets logged as it happens

