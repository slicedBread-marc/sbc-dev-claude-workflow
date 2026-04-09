---
name: wf-info
description: Display the full history and current status of any plan, bug, or brief by ID (PLN-NNN, BUG-NNN, BRF-NNN).
user_invocable: true
model: haiku
---

# Info Mode

You are in **info mode**. Your job is to look up a plan, bug, or brief by ID and present its full history in one consolidated view.

## On startup

The user may provide an ID as an argument (e.g. `/wf-info PLN-022`). If no ID was given, ask: **"Which item? (PLN-NNN, BUG-NNN, or BRF-NNN)"** and wait.

## Data gathering

Determine the type from the ID prefix, then run all applicable commands in parallel.

### PLN-NNN

```bash
grep "| PLN-NNN |" plans/REGISTRY.md
ls plans/PLN-NNN-*/
cat plans/PLN-NNN-*/plan.md
cat plans/PLN-NNN-*/progress.md 2>/dev/null || true
cat plans/PLN-NNN-*/findings.md 2>/dev/null || true
git log --oneline --all --grep="PLN-NNN"
```

### BUG-NNN

```bash
find bugs/ -maxdepth 2 -name "BUG-NNN-*" -type d
cat bugs/open/BUG-NNN-*/bug.md 2>/dev/null || cat bugs/triaged/BUG-NNN-*/bug.md 2>/dev/null || cat bugs/closed/BUG-NNN-*/bug.md 2>/dev/null || true
git log --oneline --all --grep="BUG-NNN"
```

Also check if a plan exists for this bug:
```bash
grep -r "BUG-NNN" plans/*/plan.md 2>/dev/null | grep -i "Bug:" | head -3 || true
```

### BRF-NNN

```bash
find plans/briefs/ -name "BRF-NNN-*.md"
cat plans/briefs/BRF-NNN-*.md
git log --oneline --all --grep="BRF-NNN"
```

Also check if a plan was created from this brief:
```bash
grep -r "BRF-NNN" plans/*/plan.md 2>/dev/null | grep -i "Brief:" | head -3 || true
```

## Output format

```
## {TYPE}-NNN — {Title}
State: {state}  Priority: {priority}  Branch: {branch or n/a}

### Goal
{1–3 line summary from plan/bug/brief}

### Progress       ← PLN only, omit if no progress.md
{done_count}/{total} steps complete
[✓] Step 1: ...
[✓] Step 2: ...
[ ] Step 3: ...

### Activity log   ← PLN only, from progress.md ## Log section
{date} — {entry}
{date} — {entry}

### Findings       ← PLN only, omit if no findings.md
[open]   {finding text}
[closed] {finding text}

### Git history
{hash} — {subject}
{hash} — {subject}

### Cross-references
Brief: BRF-NNN — {title}     ← if present in plan frontmatter
Bug:   BUG-NNN — {title}     ← if present in plan frontmatter
Plan:  PLN-NNN — {title}     ← for BUG or BRF lookups, if a plan exists
```

## Rules

- **Do NOT** edit any files — read-only
- Omit sections that have no data (e.g. no findings.md → omit Findings)
- Findings: prefix `[open]` for `- [ ]` lines, `[closed]` for `- [x]` lines; strip markdown bold markers
- Activity log: show entries from the `## Log` section of progress.md in chronological order
- Git history: show most recent 10 commits, newest first
- If the ID is not found in any expected location, say so clearly and stop
