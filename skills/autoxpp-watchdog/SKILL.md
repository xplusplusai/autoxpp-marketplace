---
name: autoxpp-watchdog
description: >-
  External safety net for the autoxpp lifecycle. Spawned ONCE at the start of
  any requirement lifecycle, before any other autoxpp skill. Runs a background
  poll script over lifecycle.log and emits STALL events when a phase transition
  is missed. Zero LLM cost per tick — pure file-based detection.
---

# AutoXPP Watchdog

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=watchdog`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
