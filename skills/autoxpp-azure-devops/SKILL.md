---
name: autoxpp-azure-devops
description: Use when the user asks to read, query, or interact with Azure DevOps work items, tickets, comments, attachments, or boards. Triggers on phrases like "read ticket", "check devops", "work item", "devops comments", "ticket 1069", or any Azure DevOps URL (dev.azure.com).
version: 1.3.0
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
| **PAT** | Personal Access Token (resolved automatically, see below) | — |
| **User email** | The user's DevOps login (for context, not used in API auth) | `user@company.com` |

If org/project are missing, **ask the user** before proceeding.

### PAT Resolution (priority order)

1. **Project-level PAT file** — path specified in CLAUDE.md or memory (e.g. `Docs/DevOps/PAT.txt`). Plain text file containing only the token.
2. **Global PAT file** — `~/.claude/.devops_pat.json`. JSON format, supports multiple orgs:

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

Lookup: match by org name (lowercase). If no org-specific entry, use `"default"`. If neither file exists, ask the user.

### URL Parsing

If the user provides a URL like `https://dev.azure.com/{Org}/{Project}/_workitems/edit/{ID}`, extract org, project, and work item ID directly — no need to ask.

## Access Pattern

**Always use Python + REST API with PAT token.** Do NOT use `az devops` CLI — it has persistent auth issues with external orgs.

### HTTP 401 Handling (PAT expiry)

ADO PATs expire (max 1 year, typically 90 days). A 401 on ANY request almost always means expired or insufficient-scope PAT. On 401:

1. Do NOT silently retry with the same token.
2. Print a clear block to the user with:
   - The exact regeneration URL for THIS org: `https://dev.azure.com/{Org}/_usersSettings/tokens`
   - Minimum required scopes: `Work Items (Read, Write, & Manage)`; add `Code (Read)` if reading repo files is needed.
   - Which PAT file needs updating (project file path OR `~/.claude/.devops_pat.json` entry key).
3. Exit cleanly — do not raise a raw stack trace.

Reference template to print on 401:

```
HTTP 401 Unauthorized — PAT is expired or lacks required scope.
Regenerate at: https://dev.azure.com/{Org}/_usersSettings/tokens
Required scopes: Work Items (Read, Write, & Manage)
Update one of:
  - Project PAT: {project_pat_path}  (if configured)
  - Global PAT: ~/.claude/.devops_pat.json  entry "{org_lower}" or "default"
```

Wrap every `devops_request` call in try/except that catches `urllib.error.HTTPError` with `.code == 401` and prints this block before exiting.

### Authentication

```python
import urllib.request, json, base64, re, os

def resolve_pat(org=None, project_pat_path=None):
    """Resolve PAT: project file first, then global ~/.claude/.devops_pat.json"""
    # 1. Project-level PAT file
    if project_pat_path and os.path.isfile(project_pat_path):
        with open(project_pat_path) as f:
            return f.read().strip()

    # 2. Global PAT file
    global_path = os.path.expanduser('~/.claude/.devops_pat.json')
    if os.path.isfile(global_path):
        with open(global_path) as f:
            data = json.load(f)
        # Try org-specific key first, then "default"
        key = (org or '').lower()
        entry = data.get(key) or data.get('default')
        if entry:
            return entry['pat']

    raise FileNotFoundError('No PAT found. Set project PAT path or create ~/.claude/.devops_pat.json')

def devops_request(url, pat, org=None, project_pat_path=None):
    creds = base64.b64encode((':' + pat).encode()).decode()
    req = urllib.request.Request(url, headers={'Authorization': 'Basic ' + creds})
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 401:
            org_display = org or '{Org}'
            org_lower = (org or '').lower()
            print("=" * 64)
            print("HTTP 401 Unauthorized — PAT is expired or lacks required scope.")
            print(f"Regenerate at: https://dev.azure.com/{org_display}/_usersSettings/tokens")
            print("Required scopes: Work Items (Read, Write, & Manage)")
            print("Update one of:")
            if project_pat_path:
                print(f"  - Project PAT: {project_pat_path}")
            print(f"  - Global PAT: ~/.claude/.devops_pat.json  entry \"{org_lower}\" or \"default\"")
            print("=" * 64)
            raise SystemExit(1)
        raise
```

## API Reference

### Base URL Pattern
```
https://dev.azure.com/{Org}/{Project}/_apis/wit/workItems/{ID}
```

### Read Work Item Fields
```python
url = f'https://dev.azure.com/{org}/{project}/_apis/wit/workItems/{id}?api-version=7.1'
data = devops_request(url, pat)
# Fields: data['fields']['System.Title'], System.State, System.AssignedTo, System.Description, etc.
```

### Read Comments / Discussion
```python
url = f'https://dev.azure.com/{org}/{project}/_apis/wit/workItems/{id}/comments?api-version=7.1-preview.4'
data = devops_request(url, pat)
for c in data.get('comments', []):
    date = c['createdDate']
    by = c['createdBy']['displayName']
    text = re.sub('<[^<]+?>', ' ', c.get('text', ''))  # strip HTML
    text = re.sub(r'\s+', ' ', text).strip()
```

### Read Work Item with Relations (attachments, links)
```python
url = f'https://dev.azure.com/{org}/{project}/_apis/wit/workItems/{id}?$expand=relations&api-version=7.1'
data = devops_request(url, pat)
for rel in data.get('relations', []):
    if rel['rel'] == 'AttachedFile':
        print(rel['url'])  # download URL
        print(rel['attributes']['name'])  # filename
```

### Download Attachment
```python
# Use the attachment URL from relations with same auth header
attachment_data = devops_request(attachment_url, pat)
```

### Query Work Items (WIQL)
```python
def devops_query(org, project, pat, wiql):
    url = f'https://dev.azure.com/{org}/{project}/_apis/wit/wiql?api-version=7.1'
    creds = base64.b64encode((':' + pat).encode()).decode()
    body = json.dumps({'query': wiql}).encode()
    req = urllib.request.Request(url, data=body, headers={
        'Authorization': 'Basic ' + creds,
        'Content-Type': 'application/json'
    })
    resp = urllib.request.urlopen(req)
    return json.loads(resp.read())

# Example WIQL query
wiql = "SELECT [System.Id], [System.Title] FROM WorkItems WHERE [System.AreaPath] UNDER '{Project}' AND [System.WorkItemType] = 'Requirement'"
```

## CRITICAL: Always Read Images and Attachments

When reading a work item, you MUST extract and view all visual content. Screenshots often contain the most important information (error messages, field values, before/after states). Skipping them means missing critical context.

### Step 1: Read work item with `$expand=relations` (for file attachments)

```python
data = devops_request(
    f'https://dev.azure.com/{org}/{project_encoded}/_apis/wit/workItems/{id}?$expand=relations&api-version=7.1', pat)
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

def download_file(url, path, pat):
    creds = base64.b64encode((':' + pat).encode()).decode()
    req = urllib.request.Request(url, headers={'Authorization': 'Basic ' + creds})
    resp = urllib.request.urlopen(req)
    with open(path, 'wb') as f:
        f.write(resp.read())

# Download inline images
for i, img_url in enumerate(inline_imgs):
    path = f'{download_dir}/inline-{i+1}.png'
    download_file(img_url, path, pat)

# Download file attachments
for att in attachments:
    path = f'{download_dir}/{att["name"]}'
    download_file(att['url'], path, pat)
```

After downloading, use the **Read tool** to view each image file. Present findings to the user with context from the surrounding HTML text.

### Step 5: Also check comments for images

Comments may also contain inline screenshots:

```python
comments_data = devops_request(
    f'https://dev.azure.com/{org}/{project_encoded}/_apis/wit/workItems/{id}/comments?api-version=7.1-preview.4', pat)
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
