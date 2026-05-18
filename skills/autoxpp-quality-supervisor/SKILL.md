---
name: autoxpp-quality-supervisor
description: >-
  Epistemic watchdog for the autoxpp lifecycle. Distinct from autoxpp-watchdog
  (which catches mechanical stalls — absence of motion). This skill catches
  wrongness of motion: confidence inflation, anti-pattern emergence, scope
  creep, doom-loop relapse. Invoked periodically on phase transitions and
  on-demand after non-green tester verdicts.
---

# AutoXPP Quality Supervisor

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=quality-supervisor`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
