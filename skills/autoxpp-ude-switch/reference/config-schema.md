# UDE Config Schema

Path: `C:\Users\[user]\.autoxpp\ude-configs.json`

This is the **shared, single source of truth** for environment config across all autoxpp skills (schemaVersion ≥ 4). ude-switch reads the UDE list, switches Visual Studio to the target Dataverse, and writes back `lastUsed` / `lastKnownVersion` / `activeEnv` plus tracked artifact fields after a successful switch.

> **Shared-file rule:** Other skills (build, sql-jit, tester, lifecycle) read and write this same file. ude-switch MUST preserve fields it does not own — load the whole object, mutate only its owned fields, and save it back. Never drop unknown top-level keys or unknown per-entry keys (`moduleName`, `standardCodebasePath`, `oauth`, `login`, `sqlCache`, `defaults.maxFixLoopIterations`, etc.). `Save-UdeConfigs` stamps `schemaVersion = 4` on every write, so a switch/add operation upgrades a stale config in place.

> **Schema v4 migration:** When `schemaVersion < 4`, `Invoke-SchemaV4Migration` auto-populates the new tracked fields (`xppConfigFile`, `xppConfigSubfolder`, `runtimeSymLinkFolder`, `xrefDbName`, `vsOrgName`) by scanning existing XPPConfig state. This runs once on first use after upgrade.

## Full example

```json
{
  "schemaVersion": 4,
  "activeEnv": "<env-1>",
  "defaults": {
    "maxFixLoopIterations": 3
  },
  "udeConfigs": [
    {
      "name": "<env-1>",
      "description": "Customer A DEV",
      "dataverseUrl": "https://<env-1>.crm.dynamics.com",
      "foUrl": "https://<env-1>.sandbox.operations.dynamics.com",
      "customMetadataFolder": "C:\\D365Metadata\\<ModelRoot-A>\\Metadata",
      "moduleName": "<ModelRoot-A>",
      "standardCodebasePath": "C:\\AosService\\PackagesLocalDirectory",
      "defaultCompany": "USMF",
      "solutionName": "Default",
      "msAccount": "<user>@<tenant>.com",
      "downloadPolicy": "ask",
      "lastUsed": "2026-04-18T01:40:00Z",
      "lastKnownVersion": "10.0.2428.95",
      "xppConfigFile": "<env-1>___10.0.2428.95.json",
      "xppConfigSubfolder": "org1234abcd___10.0.2428.95",
      "runtimeSymLinkFolder": "<env-1>1",
      "xrefDbName": "XRef_org1234abcd100242895",
      "vsOrgName": "org1234abcd",
      "oauth": { "tenantId": "", "clientId": "", "clientSecret": "", "grantType": "client_credentials" },
      "login": { "adminUser": "", "adminPassword": "", "testUser": "", "testPassword": "" },
      "sqlCache": { }
    }
  ]
}
```

## Top-level fields

| Field | Type | Notes |
|-------|------|-------|
| `schemaVersion` | int | Shared schema version. **Current: 4.** ude-switch stamps `4` on every save (upgrades stale v1/v2/v3 files in place). |
| `activeEnv` | string | Name of the currently-active UDE. Set automatically on a successful switch. All skills read this to pick the env entry. If unset, the first `udeConfigs` entry is used. |
| `defaults` | object | Shared lifecycle defaults. The only key here is `maxFixLoopIterations` (owned by the lifecycle skills). ude-switch never reads or writes it — it just preserves whatever is present. |
| `udeConfigs` | array | List of UDE environment definitions. |

> ude-switch does **not** define its own `defaults` namespace. Connection settings (solution name, sign-in account, download policy) are per-UDE fields, not shared defaults.

## Per-UDE fields

"Required" = ude-switch needs it to perform a switch. Other skills consume additional fields (`foUrl`, `moduleName`, `standardCodebasePath`, `oauth`, `login`, `sqlCache`, …) — ude-switch leaves those untouched.

| Field | Required | Owner | Notes |
|-------|----------|-------|-------|
| `name` | yes | shared | Unique key / friendly name. Match key for the target arg and `activeEnv`. Matches `XPPConfig\{name}___{version}.json`. |
| `dataverseUrl` | yes | ude-switch | Typed into the "Enter environment instance url" popup. |
| `customMetadataFolder` | yes | shared | Per-UDE metadata folder, retargeted into the XPP config on switch. Must be unique per UDE. |
| `description` | no | ude-switch | Shown in the picker. |
| `foUrl` | no | shared | F&O front-end URL. Used by tester/build; ude-switch only displays it. |
| `moduleName` | no | shared | Owned by dev/build skills. Preserve. |
| `standardCodebasePath` | no | shared | Owned by dev/build skills. Preserve. |
| `defaultCompany` | no | shared | Written into the XPP config JSON's `DefaultCompany` during retargeting; **also** the canonical company other skills read from this file. |
| `solutionName` | no | ude-switch | Dataverse solution to select. Defaults to `Default` if absent. |
| `msAccount` | no | ude-switch | Microsoft account for sign-in. |
| `downloadPolicy` | no | ude-switch | `always` \| `ask` \| `skip` \| `skip-if-cached` for the client-assets download. Defaults to `ask`. |
| `lastUsed` | auto | ude-switch | ISO timestamp, updated on switch. |
| `lastKnownVersion` | auto | ude-switch | PackagesLocalDirectory version, updated on switch. |
| `xppConfigFile` | auto | ude-switch | Owned config JSON filename in XPPConfig (e.g., `UDE001___10.0.2527.78.json`). Set on first switch. |
| `xppConfigSubfolder` | auto | ude-switch | VS-generated subfolder in XPPConfig holding XRef `.mdf` files. Immutable name (cannot be renamed). |
| `runtimeSymLinkFolder` | auto | ude-switch | Tracked RuntimeSymLinks folder for this UDE. One folder per UDE, reused across reconnects. |
| `xrefDbName` | auto | ude-switch | LocalDB database name for XRef (e.g., `XRef_org1234abcd100252778_1`). |
| `vsOrgName` | auto | ude-switch | Dataverse org identifier VS uses in auto-generated names (e.g., `org1234abcd`). |
| `oauth` / `login` / `sqlCache` | no | other skills | Owned by build / sql-jit / tester. ude-switch preserves them verbatim. |

## Minimum valid entry

```json
{
  "name": "<env-2>",
  "dataverseUrl": "https://<env-2>.crm.dynamics.com",
  "customMetadataFolder": "C:\\D365Metadata\\<ModelRoot-B>\\Metadata"
}
```

Everything else falls back to code defaults.

## Notes

- The active UDE is whichever entry matches `activeEnv`, or — if `activeEnv` is absent — the first `udeConfigs` entry.
- `customMetadataFolder` must be unique per UDE so environments don't collide on the same metadata path.
- ude-switch writes the file as **UTF-8 without BOM** — a BOM breaks the Python consumers (`sql.py`, `odata.py`).

## Editing manually vs. `--add` flow

- Use `--add` to create new entries via guided prompts.
- Edit the JSON directly to change existing entries or rearrange.
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
