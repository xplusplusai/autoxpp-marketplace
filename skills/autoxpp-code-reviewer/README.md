# AutoXPP Code Reviewer

Post-coding review gate that validates generated X++ code and D365 metadata XML against 64 checks across three pillars: rule compliance, X++ quality, and cross-file consistency. Catches compilation blockers, pattern violations, and wiring errors before they reach the build step.

## Why This Skill Matters

A build-deploy cycle in D365 F&O takes 10-30 minutes. The #1 compilation error in AI-generated metadata -- field-EDT base type mismatch (e.g., a String field referencing a Real-based EDT) -- is invisible to the coding agent but guaranteed to fail the build. Multiply by the fix-loop iteration cost (rebuild + redeploy + retest) and a single type mismatch wastes 30-60 minutes.

This skill reads the actual generated artifacts and catches these errors in seconds. It verifies naming conventions, type consistency, XML structure, cross-file references, and operational X++ patterns -- all before the build starts. A 2-minute review saves hours of build-test-fix loops.

## What It Checks

### P1 -- Rule Compliance (26 checks)

Validates that dev-v2 followed the coding rules it was given. Each check maps to a documented rule in guard-rails.md, model-structure.md, or the metadata rules reference.

- Label format and references (`@Model:LabelId`, no bare strings, no raw references in label text)
- Compile-time validation macros (`formControlStr`, `tableNum`, etc.)
- Chain of Command contracts (`next` called unconditionally, `this.orig()` on update)
- Security artifact structure (EntryPoints, not ActionMenuItemGrants)
- Model prefix enforcement (present on custom artifacts, absent on system references)
- XML structure (filename = `<Name>` element, `<Name>` not `<n>` tags, enum values)
- Field completeness (every field has Label + EDT/EnumType, no primitive types)
- Reserved system field names, anti-pattern screening

### P2 -- X++ Quality (23 checks)

Two layers of quality analysis.

**Layer A -- Basic patterns:** Transaction pairing, select/firstOnly, RecId checks, forUpdate, nested selects, exception handling, doInsert/doUpdate justification, string concatenation in queries.

**Layer B -- Deep operational patterns:** Company and buffer identity tracing, transaction depth across standard APIs, multiplicity and state machines, alternate entry point analysis, contextual API review (bypass APIs, buffer copy, firstOnly business uniqueness).

**Layer C -- Metadata patterns:** Field-EDT base type match (#1 AI compilation error), boolean/numeric type inference, system enums as EnumType not EDT, invalid EDT names, EnumType model-prefix, staging table rules, standard EDT usage, PurchaseOrder entity name correction.

### P3 -- Cross-File Consistency (15 checks)

Verifies artifacts wire up correctly across the module.

- Reference existence (menu item -> form, privilege -> menu item, table relation -> target, form datasource -> table)
- Label resolution, descriptor moduleReferences
- EDT type vs field type cross-match
- Orphan artifact detection (entity references a table that doesn't exist)
- EDT/Enum and system object name collisions
- Extension target validation (catches hallucinated D365 object names)
- Entity field deduplication, join data source schema
- DMF entity -> staging table, form control -> field type match

## Verdicts

| Verdict | Condition | Effect |
|:--------|:----------|:-------|
| **PASS** | No critical findings, 3 or fewer warnings | Code proceeds to build |
| **FAIL** | Any critical finding, or more than 3 warnings | Fix-loop: findings written to feedback.txt, dev-v2 re-invoked |

## Evidence Discipline

Every finding requires four elements: concrete trigger, code location, consequence, and violated rule. Missing any one means it is not reported. Keyword matches, speculative risks, and style preferences are never findings.

| Evidence Level | Meaning |
|:---------------|:--------|
| **code-confirmed** | Defect visible in source; no runtime needed |
| **runtime-reproduced** | Verified by execution (when build output available) |
| **needs-verification** | Plausible from analysis, requires runtime confirmation |

## Knowledge Stack

The skill loads 10+ curated reference files covering coding rules, naming conventions, anti-patterns, operational correctness, and metadata validation:

| Reference | What it provides |
|:----------|:----------------|
| `guard-rails.md` | Coding rules and pre-build validation checks |
| `model-structure.md` | Project structure and naming conventions |
| `anti-patterns.md` | Known anti-patterns from real D365 projects |
| `xpp-correctness.md` | Deep X++ operational correctness patterns |
| `xgen-metadata-rules.md` | XML metadata validation rules |
| `tables.md`, `forms.md`, `batch.md`, `security.md` | Artifact-type-specific best practices |

## Phased Rollout

**Phase 1 (current) -- Standalone:** Manual invocation via `/autoxpp-code-reviewer`. Points at a metadata folder or workspace. Outputs `code_review.md`. No lifecycle integration. Admin-only for testing and iteration.

**Phase 2 (future) -- Lifecycle gate:** Chained between dev-v2 and build. Automatic fix-loop on FAIL verdict. Shared iteration counter with build/test fix-loops. Gate criteria for promotion: false-positive rate < 10%, catch rate > 80%.
