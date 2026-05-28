# AutoXPP Azure DevOps

Fetches work items, comments, attachments, and inline screenshots from Azure DevOps using the REST API. Provides the requirement intake layer for the lifecycle bootloader.

## Why This Skill Matters

Requirements in D365 F&O projects live in Azure DevOps tickets -- often with critical context buried in comment threads, inline screenshots showing error states, and file attachments with specifications. An agent that reads only the ticket title and description misses the most important information: the screenshot showing exactly which field is wrong, the comment thread where the business analyst clarified the expected behavior, the attached spreadsheet with test data.

This skill extracts all of it: structured fields, HTML-stripped comments, inline images parsed from HTML `<img>` tags, and file attachments downloaded to the workspace. The lifecycle bootloader (`autoxpp-load-lifecycle`) uses this output to build a complete `requirement.txt` that downstream skills can work from without going back to DevOps.

## Key Capabilities

- **URL parsing** -- extracts organization, project, and work item ID directly from DevOps URLs
- **PAT resolution** -- project-level PAT file, global `~/.devops_pat.json` with per-org entries, or user prompt
- **Full content extraction** -- title, description, repro steps, state, assignment, plus all rich-text fields
- **Comment thread** -- newest-first, HTML-stripped, with author and date
- **Inline image extraction** -- parses `<img src="...">` from HTML fields (description, repro steps, comments) and downloads them
- **File attachments** -- downloads from the relations API
- **WIQL queries** -- arbitrary work item queries for bulk operations
- **401 handling** -- clear error messages with the exact PAT regeneration URL and required scopes when authentication fails

## Usage

Typically invoked by `autoxpp-load-lifecycle` when the user provides a DevOps ticket URL. Can also be invoked directly:

```
/autoxpp-azure-devops https://dev.azure.com/{Org}/{Project}/_workitems/edit/{ID}
```

Or by ticket number when the organization and project are known from project configuration.

