---
name: autoxpp-load-lifecycle
description: >-
  Bootloader for the autoxpp D365 F&O lifecycle. Call ONCE at the start of a
  requirement to mark the boundary between research/refine (pre-lifecycle) and
  autonomous execution (req-analyzer -> test-composer -> dev-v2 -> build ->
  tester -> DONE or fix-loop). The skill resolves workspace, writes
  requirement.txt from the arg, initializes lifecycle.log, spawns the watchdog,
  and auto-chains into req-analyzer + test-composer.
---

# AutoXPP Load Lifecycle

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=load-lifecycle`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
