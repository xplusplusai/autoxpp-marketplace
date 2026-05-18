---
name: autoxpp-req-analyzer
description: >-
  Analyze a requirement and produce structured work items with dependencies.
  Reads requirement.txt (and optionally Stage 1 output, feedback). Outputs
  work_items.md with developer-level task descriptions and a complexity flag
  (simple/complex/risky). Domain-specific artifact tags, grep patterns, and
  worked examples live in reference/domain-*.md. Run once per requirement —
  skip if work_items.md already exists and requirement unchanged.
---

# AutoXPP Req Analyzer

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=req-analyzer`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
