# AutoXPP Submit Learnings

Extracts generic D365 F&O knowledge from the current session -- both conversation context and plan folder artifacts -- sanitizes it, and submits approved learnings to the centralized backend for author review.

## Why This Skill Matters

Valuable D365 F&O patterns are discovered during lifecycles -- build error fixes, anti-patterns, framework behaviors, API quirks. Without this skill, those learnings die with the session and the next similar requirement re-discovers the same traps from scratch.

This skill closes the feedback loop: a session discovers a pattern, this skill extracts and sanitizes it, the user reviews and approves, the backend receives the submission, and the author curates it via `/housekeeping-learning-review`. Approved learnings flow into the shared reference library, benefiting all future sessions.

## When to Use

Invoke manually at end of session:
- After a lifecycle with fix-loop iterations (most learning-rich)
- After debugging sessions where new error patterns were discovered
- After any session where the AI learned something worth sharing

## When NOT to Use

- Never auto-triggered -- user must invoke explicitly
- Not during an active lifecycle (wait for DONE or FAIL)
- Not for project-specific feedback (use `agent_conversation.txt` for that)

## Security Model

All submissions are sanitized before leaving the machine:
- Customer names, environment URLs, custom class names, and project-specific identifiers are stripped
- Only generic D365 F&O process knowledge is submitted (standard API behaviors, build error patterns, framework anti-patterns)
- User reviews every learning before submission -- nothing is sent automatically

## Invoke

`/autoxpp-submit-learnings`
