# AutoXPP Req Analyzer

Decomposes a D365 F&O requirement into structured, dependency-ordered work items with artifact type tags and a complexity classification. Forces structured thinking before any code is written.

## Why This Skill Matters

The most expensive mistake in an autonomous coding loop is starting to code before understanding what to build. A vague requirement like "support multiple batches per sales line" can mean 2 work items or 12, depending on how many framework layers the change touches. Without structured decomposition, the coding agent discovers missing pieces mid-implementation -- each discovery triggers another build-deploy cycle (15-30 minutes) and often invalidates earlier work.

This skill front-loads that analysis. It reads the raw requirement, identifies every entity, action, and dependency, and produces a sorted work item list that the coding agent can implement sequentially without backtracking. The decomposition runs once and costs minutes; skipping it costs hours.

## How It Works

1. **Reads `requirement.txt`** -- the raw requirement from a ticket, user input, or DevOps work item
2. **Loads domain-specific references** -- D365 F&O artifact tags, integration patterns, or both for cross-system requirements
3. **Scans the lessons library** -- checks `autoxpp-dev-reference/lessons/` for prior failures on the same framework area
4. **Decomposes into work items** -- each WI names the artifact to create/extend, its dependencies, and enough detail for a developer to implement
5. **Classifies complexity** -- `simple` (1-2 WIs, skip design review), `complex` (3+ WIs, design review recommended), or `risky` (touches framework invariants, design review mandatory)
6. **Writes `work_items.md`** -- the structured output that drives every downstream skill

## Multi-X Three-Layer Rule

When a requirement implies "support multiple X per Y" (multiple batches per work line, multiple sites per order, multiple serial numbers per shipment), the analyzer enforces a mandatory three-layer decomposition:

| Layer | Purpose | Example |
|:------|:--------|:--------|
| **Accept** | Let multiple X rows enter the system | Staging table key, validation, unique index |
| **Process** | Iterate X rows and produce per-X effects | Methods that fan-out per X instead of aggregating |
| **Verify-output** | A queryable artifact the tester can assert on per X | "One `InventTrans` per batch", not "posting completed" |

A plan that only touches the Accept layer ships a bug. The analyzer rejects under-decomposed plans and flags layer-2 candidates by grepping the codebase for iteration patterns that collapse multi-X scenarios.

## Complexity Classification

| Flag | Triggers | Downstream Effect |
|:-----|:---------|:------------------|
| `simple` | 1-2 work items, no framework invariants | Design review skipped |
| `complex` | 3+ work items, posting/batch/multi-form | Design review recommended |
| `risky` | WHS/inventory/posting invariants, framework bypasses, prior multi-iteration failures | Design review mandatory, quality supervisor active |

