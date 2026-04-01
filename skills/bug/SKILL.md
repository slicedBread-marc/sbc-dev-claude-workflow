---
name: bug
description: File a new bug report. Creates a bug folder in bugs/open/ with a structured report and optional file attachment. Use when the user wants to report a bug, quick-fire a known issue, or import a flag from SBC.
user_invocable: true
model: sonnet
---

# Bug Filer Role

You are in **bug filing mode**. Your job is to capture a bug clearly and completely so it can be triaged, planned, and fixed.

## Two modes

### Quick-fire mode
If the user provides a one-liner or brief description, extract what you can and fill in the rest as `TBD`. Create the bug immediately — don't interrogate them for every field.

### Structured mode
If the user says "new bug" or provides no description, prompt for:
1. **Title** — short, specific (e.g. "Login crashes on empty password")
2. **Project** — which repo or app
3. **Severity** — Critical / High / Medium / Low
4. **Description** — what's broken and the impact
5. **Steps to reproduce** — numbered list
6. **Expected vs actual** — what should happen, what does happen
7. **Attachment** — ask if there's a file to attach (screenshot, log, export)

## Folder structure

```
bugs/open/    → new bugs land here (you create here)
bugs/triaged/ → picked up by /spec when a fix plan is created
bugs/closed/  → resolved by /verify when a plan completes
```

## What you do

1. **Determine the next bug ID** — list `bugs/open/`, `bugs/triaged/`, and `bugs/closed/` to find the highest existing `BUG-NNN` number. Increment by 1. Start at `BUG-001` if none exist.
2. **Choose a slug** — kebab-case title (e.g. `login-crash-empty-password`). The folder will be `BUG-NNN-<slug>`.
3. **Create the bug folder** — `bugs/open/BUG-NNN-<slug>/`
4. **Write `bug.md`** — fill in all known fields from the template at `bugs/_template/bug.md`
5. **Handle attachments** — if the user provides a file path, copy or note it:
   - If the file exists locally, note its path in `bug.md` under `## Attachments` with a relative reference
   - If the user describes a file they'll add later, add a placeholder: `- [ ] Attach: <description>`
6. **Commit immediately**:
   ```
   git add bugs/open/BUG-NNN-<slug>/
   git commit -m "bug: BUG-NNN — <short title>"
   ```
7. **Confirm** — show the user the bug ID, folder path, and commit hash

## bug.md format

```markdown
# [Bug Title]

> **Status:** Open
> **ID:** BUG-NNN
> **Filed:** YYYY-MM-DD
> **Project:** [project]
> **Severity:** Critical | High | Medium | Low
> **Plan:** _(none)_

## Description
...

## Steps to Reproduce
1. 
2. 

## Expected
...

## Actual
...

## Attachments
- [filename.ext](./filename.ext) — description

## Notes
...
```

## Attachment handling

When an attachment is provided:
- Place it (or a symlink note) in the bug folder alongside `bug.md`
- Reference it with a relative path: `[filename.ext](./filename.ext)`
- If it's a path outside the repo, note the full path as a non-relative reference with a warning that it may not be portable

## Rules

- Never invent reproduction steps — leave as `TBD` if unknown
- Severity is the user's call; suggest based on description but don't override
- Keep descriptions factual, not prescriptive (describe the problem, not the fix)
- One bug per folder — do not combine multiple issues

## Notes

- Bugs are committed immediately upon creation — no manual commit step needed
- Attachments are co-located with `bug.md` in the bug folder
- The bug can be moved to `triaged/` by `/spec` when a fix plan is created
- The bug moves to `closed/` by `/verify` when the fix plan completes
