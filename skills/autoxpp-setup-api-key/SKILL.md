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
- **If the MCP tool is not available**: Continue to Step 2.

## Step 2: Get the API key

If the user provided a key as an argument (e.g. `/autoxpp:autoxpp-setup-api-key ak_xxxxxxxx`), use that.

Otherwise, ask the user for their key. It should start with `ak_` (e.g. `ak_ZVrTR-3R_fu8vLUjlgjHTjxiLRP9gTiaK`). If they don't have one, direct them to https://xplusplus.ai/autoxpp.html to subscribe and get a key.

## Step 3: Detect plugin scope and choose MCP placement

The plugin (skills) and MCP (server connection) are configured separately. The MCP should be added at the same scope where the plugin is installed.

### Detection logic

Read the file `~/.claude/plugins/installed_plugins.json` (platform-aware: `$HOME/.claude/plugins/installed_plugins.json` on macOS/Linux, `$env:USERPROFILE\.claude\plugins\installed_plugins.json` on Windows).

Look for the key `autoxpp@xplusplus-ai` in the `plugins` object. The entry structure is:

```json
{
  "plugins": {
    "autoxpp@xplusplus-ai": [
      {
        "scope": "user",
        "installPath": "...",
        "version": "1.4.0"
      }
    ]
  }
}
```

**Decision:**
1. If `scope` is `"user"` → use **global MCP** (Step 4a).
2. If `scope` is `"project"` → use **project MCP** (Step 4b).
3. If the file doesn't exist, the key is missing, or the scope can't be determined → **ask the user**:

> Where should I configure the AutoXPP MCP server?
>
> - **Global (recommended)** — works in every workspace, one-time setup. Adds to your user-level Claude config (`~/.claude.json`).
> - **Project** — this workspace only. Writes `.mcp.json` in the current directory.

## Step 4a: Global MCP (user scope)

Run the following command, replacing `<API_KEY>` with the actual key:

```
claude mcp add autoxpp --scope user -t http --url "https://autoxpp.xplusplus.ai/mcp" --header "Authorization: Bearer <API_KEY>"
```

After running, tell the user:
1. Restart Claude Code for the MCP server to connect.
2. Run `/autoxpp-setup-api-key` again to validate the connection.

## Step 4b: Project MCP (workspace scope)

Write (or merge into) the `.mcp.json` file in the current working directory:

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

After writing, tell the user:
1. Restart Claude Code for the MCP server to connect.
2. Run `/autoxpp-setup-api-key` again to validate the connection.
3. Add `.mcp.json` to `.gitignore` if this is a git repo (it contains the API key).

## Notes

- Free skills (browser-v2, azure-devops, sql-jit, ude-switch) work without an API key or MCP connection.
- The plugin handles skill distribution. This skill handles MCP server configuration only.
- Global MCP lands in the user's Claude config (`~/.claude.json`).
- Project MCP lands in `.mcp.json` in the workspace root.
