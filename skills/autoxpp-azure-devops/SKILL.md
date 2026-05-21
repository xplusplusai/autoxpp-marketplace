---
name: autoxpp-azure-devops
description: Use when the user asks to read, query, or interact with Azure DevOps work items, tickets, comments, attachments, or boards. Triggers on phrases like "read ticket", "check devops", "work item", "devops comments", "ticket 1069", or any Azure DevOps URL (dev.azure.com).
version: 2.0.0
---

# Azure DevOps Skill

Read and query Azure DevOps work items, comments, and attachments using the REST API.

## Required Configuration

Before making any API calls, the following values must be known. Check these sources in order:

1. **CLAUDE.md** or **memory files** in the current project
2. **User-provided DevOps URL** (parse org, project, and work item ID from it)
3. **Ask the user** if not found

| Parameter | Description | Example |
|-----------|-------------|---------|
| **Org** | Azure DevOps organization name | `MyOrg` |
| **Project** | DevOps project name | `My Project` |
| **User email** | The user's DevOps login (for context, not used in API auth) | `user@company.com` |

If org/project are missing, **ask the user** before proceeding.

### URL Parsing

If the user provides a URL like `https://dev.azure.com/{Org}/{Project}/_workitems/edit/{ID}`, extract org, project, and work item ID directly — no need to ask.

## Authentication — Dual-Method with Auto-Fallback

This skill supports two auth methods, tried in priority order. The first success wins.

### Priority 1: GCM Credential Fill (Bearer token)

Git Credential Manager (GCM) caches an Azure AD OAuth access token after the user's first interactive login (VS, `az login`, browser popup). This token is full-scope, auto-refreshed, and doesn't expire like PATs.

**How it works:** pipe the DevOps host info to `git credential fill`, extract the `password=` line — that's the OAuth token. Use it as a Bearer header.

**When it works:** any machine where the user has previously authenticated to this DevOps org via git, VS, or Azure CLI. Covers most dev machines.

**When it fails:** fresh machine with no cached auth, CI/CD containers, or if GCM is not installed.

### Priority 2: PAT from File (Basic auth)

Personal Access Token stored in a JSON file on disk. Scope-limited and expires (90 days typical, 1 year max).

**File locations (checked in order):**

1. **Project-level PAT file** — path specified in CLAUDE.md or memory (e.g. `Docs/DevOps/PAT.txt`). Plain text, token only.
2. **Global PAT file** — `~/.claude/.devops_pat.json`. JSON with per-org entries:

```json
{
  "default": {
    "pat": "<token>",
    "email": "user@company.com"
  },
  "other-org": {
    "pat": "<different-token>",
    "email": "user@other.com"
  }
}
```

Lookup: match by org name (lowercase). If no org-specific entry, use `"default"`.

### Priority 3: Both Failed — Prompt User

If neither method produces a working token, print a clear diagnostic and ask the user to fix one:

```
Both Azure DevOps auth methods failed for org "{Org}".

Option A — Fix GCM (recommended, no expiry):
  Run in terminal:  ! git credential fill <<< "protocol=https\nhost=dev.azure.com"
  If that errors, run:  ! az login   (or any git operation against this org to trigger browser login)

Option B — Create/update a PAT:
  1. Go to: https://dev.azure.com/{Org}/_usersSettings/tokens
  2. Create token with scope: Work Items (Read, Write, & Manage)
  3. Save to: ~/.claude/.devops_pat.json  under key "{org_lower}"
```

## Access Pattern — Python Implementation

**Always use Python + REST API.** Do NOT use `az devops` CLI — it has persistent auth issues with external orgs.

### Authentication Module

```python
import urllib.request, json, base64, re, os, subprocess

def _try_gcm_credential(org):
    """Priority 1: Extract Bearer token from GCM's cached credentials."""
    try:
        input_text = f"protocol=https\nhost=dev.azure.com\npath={org}\n\n"
        result = subprocess.run(
            ['git', 'credential', 'fill'],
            input=input_text, capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return None
        for line in result.stdout.splitlines():
            if line.startswith('password='):
                return line[len('password='):]
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception):
        pass
    return None

def _try_pat(org, project_pat_path=None):
    """Priority 2: Read PAT from project file or global JSON."""
    # Project-level PAT file
    if project_pat_path and os.path.isfile(project_pat_path):
        with open(project_pat_path) as f:
            return f.read().strip()
    # Global PAT file
    global_path = os.path.expanduser('~/.claude/.devops_pat.json')
    if os.path.isfile(global_path):
        with open(global_path) as f:
            data = json.load(f)
        key = (org or '').lower()
        entry = data.get(key) or data.get('default')
        if entry:
            return entry['pat']
    return None

def resolve_auth(org, project_pat_path=None):
    """
    Returns (auth_header_value, method_name).
    Tries GCM first, then PAT. Raises if both fail.
    """
    # Priority 1: GCM
    gcm_token = _try_gcm_credential(org)
    if gcm_token:
        return f'Bearer {gcm_token}', 'gcm'

    # Priority 2: PAT
    pat = _try_pat(org, project_pat_path)
    if pat:
        basic = base64.b64encode(f':{pat}'.encode()).decode()
        return f'Basic {basic}', 'pat'

    # Priority 3: Both failed
    org_lower = (org or '').lower()
    raise AuthError(org, org_lower, project_pat_path)

class AuthError(Exception):
    def __init__(self, org, org_lower, project_pat_path):
        self.org = org
        self.org_lower = org_lower
        self.project_pat_path = project_pat_path
    def __str__(self):
        lines = [
            f'Both Azure DevOps auth methods failed for org "{self.org}".',
            '',
            'Option A - Fix GCM (recommended, no expiry):',
            '  Run in terminal:  ! git fetch  (against any repo in this org to trigger browser login)',
            '  Or:  ! az login',
            '',
            'Option B - Create/update a PAT:',
            f'  1. Go to: https://dev.azure.com/{self.org}/_usersSettings/tokens',
            '  2. Create token with scope: Work Items (Read, Write, & Manage)',
            f'  3. Save to: ~/.claude/.devops_pat.json  under key "{self.org_lower}"',
        ]
        if self.project_pat_path:
            lines.append(f'  Or save to project PAT: {self.project_pat_path}')
        return '\n'.join(lines)
```

### HTTP Request Helper

```python
def devops_request(url, org, project_pat_path=None, method='GET', body=None):
    """Make an authenticated DevOps REST API request with auto-fallback."""
    auth_header, auth_method = resolve_auth(org, project_pat_path)
    headers = {'Authorization': auth_header}
    if body is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(body).encode() if isinstance(body, dict) else body
    else:
        data = None

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 401 and auth_method == 'gcm':
            # GCM token might be stale — retry with PAT
            pat = _try_pat(org, project_pat_path)
            if pat:
                basic = base64.b64encode(f':{pat}'.encode()).decode()
                req2 = urllib.request.Request(url, data=data, method=method,
                    headers={**headers, 'Authorization': f'Basic {basic}'})
                if body is not None:
                    req2.add_header('Content-Type', 'application/json')
                try:
                    resp2 = urllib.request.urlopen(req2)
                    return json.loads(resp2.read())
                except urllib.error.HTTPError as e2:
                    if e2.code == 401:
                        _print_401(org, project_pat_path)
                        raise SystemExit(1)
                    raise
            _print_401(org, project_pat_path)
            raise SystemExit(1)
        if e.code == 401:
            _print_401(org, project_pat_path)
            raise SystemExit(1)
        raise

def _print_401(org, project_pat_path):
    org_lower = (org or '').lower()
    print("=" * 64)
    print("HTTP 401 — Both auth methods failed or lack required scope.")
    print()
    print("Option A - Refresh GCM token:")
    print("  Run:  ! git fetch  (against any repo in this org)")
    print()
    print("Option B - Regenerate PAT:")
    print(f"  URL: https://dev.azure.com/{org}/_usersSettings/tokens")
    print("  Scopes: Work Items (Read, Write, & Manage)")
    if project_pat_path:
        print(f"  Save to: {project_pat_path}")
    print(f"  Or: ~/.claude/.devops_pat.json  entry \"{org_lower}\"")
    print("=" * 64)
```

### Bash Alternative (When Python Is Overhead)

For simple one-off reads where a full Python script isn't needed, the same dual-method works from bash/PowerShell:

```bash
# Try GCM first
TOKEN=$(printf 'protocol=https\nhost=dev.azure.com\npath={Org}\n\n' \
  | git credential fill 2>/dev/null | grep '^password=' | sed 's/^password=//')

if [ -n "$TOKEN" ]; then
  AUTH_HEADER="Authorization: Bearer $TOKEN"
else
  # Fall back to PAT
  PAT=$(python3 -c "import json,os; print(json.load(open(os.path.expanduser('~/.claude/.devops_pat.json'))).get('{org_lower}',{}).get('pat',''))" 2>/dev/null)
  AUTH_HEADER="Authorization: Basic $(printf ':%s' "$PAT" | base64 -w0)"
fi

curl -s -H "$AUTH_HEADER" "https://dev.azure.com/{Org}/{Project}/_apis/wit/workItems/{ID}?api-version=7.1"
```

## API Reference

### Base URL Pattern
```
https://dev.azure.com/{Org}/{Project}/_apis/wit/workItems/{ID}
```

### Read Work Item Fields
```python
url = f'https://dev.azure.com/{org}/{project}/_apis/wit/workItems/{id}?api-version=7.1'
data = devops_request(url, org)
# Fields: data['fields']['System.Title'], System.State, System.AssignedTo, System.Description, etc.
```

### Read Comments / Discussion
```python
url = f'https://dev.azure.com/{org}/{project}/_apis/wit/workItems/{id}/comments?api-version=7.1-preview.4'
data = devops_request(url, org)
for c in data.get('comments', []):
    date = c['createdDate']
    by = c['createdBy']['displayName']
    text = re.sub('<[^<]+?>', ' ', c.get('text', ''))  # strip HTML
    text = re.sub(r'\s+', ' ', text).strip()
```

### Read Work Item with Relations (attachments, links)
```python
url = f'https://dev.azure.com/{org}/{project}/_apis/wit/workItems/{id}?$expand=relations&api-version=7.1'
data = devops_request(url, org)
for rel in data.get('relations', []):
    if rel['rel'] == 'AttachedFile':
        print(rel['url'])  # download URL
        print(rel['attributes']['name'])  # filename
```

### Download Attachment
```python
# Use the attachment URL from relations with same auth
attachment_data = devops_request(attachment_url, org)
```

### Query Work Items (WIQL)
```python
url = f'https://dev.azure.com/{org}/{project}/_apis/wit/wiql?api-version=7.1'
data = devops_request(url, org, body={'query': wiql})

# Example WIQL
wiql = "SELECT [System.Id], [System.Title] FROM WorkItems WHERE [System.AreaPath] UNDER '{Project}' AND [System.WorkItemType] = 'Requirement'"
```

## CRITICAL: Always Read Images and Attachments

When reading a work item, you MUST extract and view all visual content. Screenshots often contain the most important information (error messages, field values, before/after states). Skipping them means missing critical context.

### Step 1: Read work item with `$expand=relations` (for file attachments)

```python
data = devops_request(
    f'https://dev.azure.com/{org}/{project_encoded}/_apis/wit/workItems/{id}?$expand=relations&api-version=7.1', org)
```

### Step 2: Extract inline images from HTML fields

DevOps embeds screenshots as `<img src="...">` tags inside Description, Repro Steps, and comments. These are NOT listed in relations — you must parse the HTML.

```python
import re

# Check ALL rich-text fields for inline images
html_fields = [
    data['fields'].get('System.Description', ''),
    data['fields'].get('Microsoft.VSTS.TCM.ReproSteps', ''),
    data['fields'].get('System.History', ''),
]
inline_imgs = []
for html in html_fields:
    inline_imgs += re.findall(r'<img[^>]+src="([^"]+)"', html or '')
```

### Step 3: Extract file attachments from relations

```python
attachments = []
for rel in data.get('relations', []):
    if rel['rel'] == 'AttachedFile':
        attachments.append({
            'name': rel['attributes']['name'],
            'url': rel['url']
        })
```

### Step 4: Download and view ALL images

```python
import os

download_dir = f'{workspace_root}/screenshots/devops-{id}'
os.makedirs(download_dir, exist_ok=True)

def download_file(url, path, org):
    auth_header, _ = resolve_auth(org)
    req = urllib.request.Request(url, headers={'Authorization': auth_header})
    resp = urllib.request.urlopen(req)
    with open(path, 'wb') as f:
        f.write(resp.read())

# Download inline images
for i, img_url in enumerate(inline_imgs):
    path = f'{download_dir}/inline-{i+1}.png'
    download_file(img_url, path, org)

# Download file attachments
for att in attachments:
    path = f'{download_dir}/{att["name"]}'
    download_file(att['url'], path, org)
```

After downloading, use the **Read tool** to view each image file. Present findings to the user with context from the surrounding HTML text.

### Step 5: Also check comments for images

Comments may also contain inline screenshots:

```python
comments_data = devops_request(
    f'https://dev.azure.com/{org}/{project_encoded}/_apis/wit/workItems/{id}/comments?api-version=7.1-preview.4', org)
for c in comments_data.get('comments', []):
    comment_imgs = re.findall(r'<img[^>]+src="([^"]+)"', c.get('text', ''))
    # Download and view these too
```

## Output Guidelines

- Strip HTML tags from comment text before displaying
- Show comments in reverse chronological order (newest first) unless user asks otherwise
- For large comment threads, summarize key points rather than dumping all text
- When reading a ticket, always show: ID, Title, State, Assigned To, then Description/Repro Steps with images
- **ALWAYS download and view inline screenshots and attachments** — never skip them
