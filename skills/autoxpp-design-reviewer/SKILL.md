---
name: autoxpp-design-reviewer
description: >-
  Pre-coding design review gate between req-analyzer and dev-v2. Runs for
  requirements classified as complex or risky. Loads design-reviewer +
  senior-fo-developer roles, reads requirement.txt / work_items.md /
  test_cases.md and relevant dev-reference sections, and writes
  design_review.md with PASS / NEEDS-WORK / BLOCKED verdict. Dev-v2 cannot
  proceed until PASS.
---

# AutoXPP Design Reviewer

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=design-reviewer`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
