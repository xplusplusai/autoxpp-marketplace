---
name: autoxpp-watchdog
description: >-
  Lifecycle progress monitor and stall detector. Spawned ONCE at lifecycle start
  as a lightweight background LLM agent. Runs a 5-minute cycle: reads
  lifecycle.log + agent_conversation.txt + workspace file activity to determine
  current phase status, then appends [watchdog] PROGRESS ticks (with context)
  or STALL alerts to lifecycle.log. The orchestrator's tail-f Monitor picks up
  STALL lines and acts. Also reports the fix-loop circuit breaker thresholds
  (read from the configured fix-loop limit). Writes only [watchdog] lines.
  Replaces the prior pure-bash poll_lifecycle.sh approach — an LLM agent can
  read text files intelligently and produce meaningful tick summaries that
  external platforms consume for progress reporting and kill decisions.
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
