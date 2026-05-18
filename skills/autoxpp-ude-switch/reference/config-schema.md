# ude-configs.json — schema reference

Path: `C:\Users\[user]\.autoxpp\ude-configs.json`

## Full example

```json
{
  "schemaVersion": 1,
  "activeEnv": "<env-1>",
  "defaults": {
    "solutionName": "Default",
    "msAccount": "<user>@<tenant>.com",
    "signInAsCurrentUser": true,
    "deploymentType": "Office365",
    "downloadPolicy": "ask",
    "closeOpenSolutionBeforeSwitch": true,
    "vsPath": "C:\\Program Files\\Microsoft Visual Studio\\2022\\Professional\\Common7\\IDE\\devenv.exe",
    "timeouts": {
      "dataverseConnectSeconds": 180,
      "metadataDownloadSeconds": 3600,
      "dialogTransitionSeconds": 30,
      "vsRestartSeconds": 120
    },
    "defaultCustomMetadataRoot": "C:\\D365Metadata"
  },
  "udeConfigs": [
    {
      "name": "<env-1>",
      "description": "Customer A DEV",
      "dataverseUrl": "https://<env-1>.crm.dynamics.com",
      "foUrl": "https://<env-1>.sandbox.operations.dynamics.com",
      "customMetadataFolder": "C:\\D365Metadata\\<ModelRoot-A>\\Metadata",
      "defaultCompany": "USMF",
      "lastUsed": "2026-04-18T01:40:00Z",
      "lastKnownVersion": "10.0.2428.95"
    }
  ]
}
```

## Top-level fields

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | int | Schema version. Current: 1. |
| `activeEnv` | string | Name of the currently active UDE. Set automatically on successful switch. All skills read this field to determine which env entry to use — no `lastUsed` timestamp sorting needed. |
| `defaults` | object | Default values inherited by all UDE entries (see below). |
| `udeConfigs` | array | Per-environment entries (see below). |

## Resolution

When the skill processes a UDE entry, it **merges** `defaults` with the per-UDE fields. Per-UDE fields override defaults.

Example: `<env-1>` inherits `solutionName: "Default"` from defaults because the entry doesn't specify it. If `<env-2>` had `"solutionName": "Custom"`, that would override.

## `defaults` fields

| Field | Type | Notes |
|---|---|---|
| `solutionName` | string | Passed to the "Select Solution" combo. "Default" fits most UDEs. |
| `msAccount` | string | Informational; Windows WAM picks the account. Useful when `--add` prompts. |
| `signInAsCurrentUser` | bool | Expected state of the Login dialog checkbox. |
| `deploymentType` | string | "Office365" or "OnPremises". Skill verifies; does not force-change. |
| `downloadPolicy` | string | `always` \| `ask` \| `skip` \| `skip-if-cached`. v1 uses `ask` = Yes. |
| `closeOpenSolutionBeforeSwitch` | bool | True = `File → Close Solution` before switching. |
| `vsPath` | string | Full path to `devenv.exe` — used if VS isn't running. Auto-detected if missing. |
| `timeouts.dataverseConnectSeconds` | int | How long to wait on "Validating / Loading Workflows..." before giving up. |
| `timeouts.metadataDownloadSeconds` | int | How long to wait on "Client assets download" (~20 min typical, 1hr guardrail). |
| `timeouts.dialogTransitionSeconds` | int | Short waits for dialog pop-ups between steps. |
| `timeouts.vsRestartSeconds` | int | How long to wait for `devenv.exe` to show a main window. |
| `defaultCustomMetadataRoot` | string | Parent path suggested by `--add` flow when asking for metadata folder. |

## Per-UDE fields

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Unique key. Matches `XPPConfig\{name}___{version}.json`. |
| `dataverseUrl` | yes | Typed into the "Enter environment instance url" popup. |
| `customMetadataFolder` | yes | Full path (any structure). Skill auto-discovers git state. |
| `description` | no | Shown in picker. |
| `foUrl` | no | For other autoxpp-* skills needing the FO front-end URL. |
| `defaultCompany` | no | Written into XPP config JSON's `DefaultCompany` field during retargeting. |
| `msAccount` | no | Overrides `defaults.msAccount` for cross-tenant UDEs. |
| `solutionName` | no | Overrides `defaults.solutionName`. |
| `downloadPolicy` | no | Overrides `defaults.downloadPolicy`. |
| `lastUsed` | auto | Updated by skill on successful switch. |
| `lastKnownVersion` | auto | Updated by skill with the platform version detected on switch. |

## Minimum valid entry

```json
{
  "name": "<env-2>",
  "dataverseUrl": "https://<env-2>.crm.dynamics.com",
  "customMetadataFolder": "C:\\D365Metadata\\<ModelRoot-B>\\Metadata"
}
```

Everything else falls back to defaults.

## Editing manually vs. `--add` flow

- Use `--add` to create new entries via guided prompts.
- Edit the JSON directly to change existing entries, tweak defaults, or rearrange.
- The skill does not watch the file — it reads fresh on each invocation.

## Version control (optional)

The file is personal and lives outside any repo. To version-control it via the user's personal `claude-config` repo, symlink it:

```powershell
# One-time setup
$src = "C:\Temp\claude-config\ude-configs.json"
$dst = "$env:USERPROFILE\.autoxpp\ude-configs.json"
Move-Item $dst $src
New-Item -ItemType SymbolicLink -Path $dst -Target $src
```

Then commit `ude-configs.json` from the `claude-config` repo as you do with `CLAUDE.md`.
