---
name: autoxpp-dev-v2
description: >-
  Focused D365 F&O coding skill. Reads work_items.md and implements X++ artifacts
  sequentially in dependency order. Uses autoxpp-dev-reference for D365 patterns.
  No planning (req-analyzer does that), no test design (test-composer does that).
  Autonomous-ready — never prompts for input. For fix loops, reads test_report.md.
---

# AutoXPP Dev V2

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=dev-v2`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
