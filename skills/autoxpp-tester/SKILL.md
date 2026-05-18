---
name: autoxpp-tester
description: >-
  Execute test cases and produce a structured test report. Reads test_cases.md,
  orchestrates test execution via domain-appropriate tools (autoxpp-browser-v2
  for UI paths, direct HTTP/SQL/Service Bus for integration paths), handles test
  data setup, captures evidence, and outputs test_report.md with pass/fail per
  case.
---

# AutoXPP Tester

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=tester`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
