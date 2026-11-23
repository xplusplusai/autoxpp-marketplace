---
name: autoxpp-build
description: >
  Build and deploy D365 F&O X++ models in Visual Studio 2022 (UDE).
  Use when: user says "build", "compile", "deploy", "sync database",
  "refresh models", or after completing X++ code changes that need
  compilation. Also use when autoxpp-browser testing reveals code
  changes are needed and a rebuild is required. Even if the user doesn't
  explicitly mention "build", trigger this skill when the task clearly
  requires compiling and deploying X++ code.
---

# AutoXPP Build

AI-powered D365 F&O skill by XPLUSPLUS.AI. Requires AutoXPP Pro.

## How to activate

1. Call the `autoxpp` MCP tool `get_skill_content` with `skill_name=build`
2. If the response contains skill instructions, follow all returned instructions exactly.
   For skills that reference additional documents (guard-rails, tables, forms, etc.),
   call `get_reference` with the appropriate `reference_name` as instructed.
3. If the response says the skill is locked or requires an upgrade, relay that
   message to the user. Suggest running `/autoxpp:autoxpp-setup-api-key` if no API key
   is configured, or visit https://xplusplus.ai/autoxpp.html to subscribe.

Do NOT attempt to perform this skill's task without successfully loading the skill content first.
