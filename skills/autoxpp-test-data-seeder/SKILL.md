---
name: autoxpp-test-data-seeder
description: >-
  Background agent that pre-seeds test data in the D365 environment while
  dev-v2 analyzes standard code. Reads test_cases.md as a shopping list,
  finds or creates required records via OData/SQL/browser, and writes
  test_data_manifest.md for the tester to consume.
---

# AutoXPP Test Data Seeder

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=test-data-seeder`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
