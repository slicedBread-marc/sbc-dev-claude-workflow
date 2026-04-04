---
name: wf-bug
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
7. **Links** (optional) — if related to another bug or plan (e.g. "caused by BUG-003", "discovered during debug of BUG-002", "regression from PLN-005")
8. **Attachment** — ask if there's a file to attach (screenshot, log, export)

## Folder structure

```
bugs/open/    → new bugs land here (you create here)
bugs/triaged/ → picked up by /wf-spec when a fix plan is created
bugs/closed/  → resolved by /wf-verify when a plan completes
```

## What you do

1. **Determine the next bug ID** — read `plans/.counter` to get the next number N. Write N+1 back to `plans/.counter`. The bug ID is `BUG-N` (zero-padded to 3 digits, e.g. `BUG-009`). If `plans/.counter` does not exist, fall back to scanning `bugs/open/`, `bugs/triaged/`, and `bugs/closed/` for the highest `BUG-NNN` number and increment by 1 (legacy fallback only).
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
> **schema_version:** 2
> **Filed:** YYYY-MM-DD
> **Project:** [project]
> **Severity:** Critical | High | Medium | Low
> **Plan:** _(none — link added by /wf-spec when a fix plan is created)_
> **Links:** _(optional: caused by BUG-NNN, blocks BUG-NNN, regression from PLN-NNN, discovered during debug of BUG-NNN, etc.)_

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
_(remove this section if no attachments)_
- [filename.ext](./filename.ext) — description

## Notes
_(context, workarounds, related information)_
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
- The bug can be moved to `triaged/` by `/wf-spec` when a fix plan is created
- The bug moves to `closed/` by `/wf-verify` when the fix plan completes
