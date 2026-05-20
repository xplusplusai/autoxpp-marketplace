---
name: autoxpp-setup-api-key
description: Configure your AutoXPP API key and MCP connection for premium skill access.
---

# AutoXPP API Key Setup

## Step 1: Check if MCP is already connected

First, try to call the `autoxpp` MCP tool `validate_license`.

- **If the call succeeds**: Display the following banner, then report the user's tier and available skills. Done — no further setup needed.

```
  >_  AutoXPP™  · D365 F&O AI Dev Engine · by xplusplus.ai
```
- **If the MCP tool is not available**: Check if `.mcp.json` exists in the current working directory with an `autoxpp` server entry.
  - **If `.mcp.json` exists with autoxpp config**: Tell the user to restart Claude Code so the MCP server connects, then run this skill again.
  - **If no `.mcp.json` or no autoxpp entry**: Continue to Step 2.

## Step 2: Get the API key

If the user provided a key as an argument (e.g. `/autoxpp:autoxpp-setup-api-key ak_xxxxxxxx`), use that.

Otherwise, ask the user for their key. It should start with `ak_` (e.g. `ak_ZVrTR-3R_fu8vLUjlgjHTjxiLRP9gTiaK`). If they don't have one, direct them to https://xplusplus.ai/autoxpp.html to subscribe and get a key.

## Step 3: Write .mcp.json

Write (or merge into) the `.mcp.json` file in the user's current working directory:

```json
{
  "mcpServers": {
    "autoxpp": {
      "type": "http",
      "url": "https://autoxpp.xplusplus.ai/mcp",
      "headers": {
        "Authorization": "Bearer <API_KEY>"
      }
    }
  }
}
```

Replace `<API_KEY>` with the actual key.

**If `.mcp.json` already exists**, read it first and merge the `autoxpp` entry into the existing `mcpServers` object. Do NOT overwrite other MCP server configurations.

## Step 4: Next steps

Tell the user:
1. Restart Claude Code for the MCP server to connect
2. Run `/autoxpp:autoxpp-setup-api-key` again to validate the connection
3. Remind them to add `.mcp.json` to `.gitignore` if this is a git repo

## Notes

- Free skills (browser-v2, azure-devops, sql-jit, ude-switch) work without an API key or MCP connection.
- This writes to the PROJECT-LEVEL `.mcp.json`. Run once per workspace where premium skills are needed.
