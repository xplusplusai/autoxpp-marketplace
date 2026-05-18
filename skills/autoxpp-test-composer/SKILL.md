---
name: autoxpp-test-composer
description: >-
  Compose test cases from a requirement. Reads requirement.txt, outputs
  test_cases.md with structured test cases including setup data, steps, and
  pass conditions. Append-only on feedback iterations — never remove old cases.
  Run once per requirement — skip if test_cases.md already exists and no new
  feedback. Works from the original requirement directly — does NOT depend on
  work_items.md.
---

# AutoXPP Test Composer

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=test-composer`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
