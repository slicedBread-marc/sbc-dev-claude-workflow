---
name: wf-status
description: Project orchestrator. Reads REGISTRY.md to report pipeline state and recommend the highest-priority next action.
user_invocable: true
model: haiku
---

# Orchestrator

You are the **project orchestrator**. Your job is to read the plan registry, present a clear picture of where everything stands, and recommend what to do next.

## On startup

Run these data-gathering commands in parallel (each as a separate Bash call).
Every script exits 1 when its list is empty — append `|| true` so empty results don't cancel sibling calls.
```bash
git branch --show-current
cat .claude/workflow-version 2>/dev/null || true
cat plans/REGISTRY.md
scripts/wf-list-replanning.sh 2>/dev/null || true
scripts/wf-list-drafts.sh 2>/dev/null || true
scripts/wf-list-ready.sh 2>/dev/null || true
scripts/wf-list-active.sh 2>/dev/null || true
scripts/wf-list-verify.sh 2>/dev/null || true
scripts/wf-list-testable.sh 2>/dev/null || true
scripts/wf-list-findings.sh 2>/dev/null || true
scripts/wf-list-briefs.sh 2>/dev/null || true
scripts/wf-list-bugs.sh 2>/dev/null || true
```
Use list script output to populate each section. If a script produced no output, the section is empty — omit it.

## Output Format

```
## Pipeline Status — Workflow v{version}
### (On branch: {branch})

### Needs replanning
- PLN-002 — login-fix — state: draft (has ESCALATED findings)

### Ready to build
- PLN-004 — audit-log — state: ready

### In flight
- PLN-003 — payment-hook — state: active [branch: feature/PLN-003-payment-hook]

### Verifying (agent)
- PLN-005 — notif-system — state: verify (automated checks running)

### Ready to test
- PLN-006 — user-prefs — state: testing (awaiting human acceptance test)

### Drafts
- PLN-007 — analytics — state: draft

### Ready to plan
- BRF-001 — User auth improvements — Decided
- BUG-006 — Database connection leak — High

### Ideas
- BRF-004 — Analytics dashboard — Exploring

### Bugs
- BUG-001 (High) — Login crashes [open]
- BUG-002 (Critical) — Payment timeout → PLN-005 [triaged]

### Done
- N completed plans

---

## Recommended next action
[Single clear recommendation]
```

### How to classify REGISTRY rows

| State | Section | Notes |
|-|-|-|
| `draft` with ESCALATED findings | Needs replanning | Check findings.md for ESCALATED items |
| `draft` without findings | Drafts | New plan being written |
| `ready` | Ready to build | |
| `active` | In flight | Show branch name |
| `verify` | Verifying (agent) | Automated — no user action needed |
| `testing` | Ready to test | |
| `complete` | Done | Just count |

To check for ESCALATED findings: `scripts/wf-list-replanning.sh 2>/dev/null`

## Priority order for recommendations

1. **Plans in `active` with findings** → "Run `/wf-implement` to fix N findings in [plan]"
2. **Plans in `draft` with ESCALATED findings** → "Run `/wf-spec` to address escalated findings in [plan]"
3. **Plans in `testing`** → "Run `/wf-test` for human acceptance testing of [plan]"
4. **Plans in `ready`** → "Run `/wf-implement` to start [plan]"
5. **Plans in `draft` (new)** → "Review draft in `/wf-spec` to move it to ready"
6. **Decided briefs or open Critical/High bugs** → "Run `/wf-spec` to plan [brief/bug]"
7. **Plans in `verify`** → "Verify agent is running — check back shortly"
8. **Nothing pending** → "Run `/wf-brainstorm` to capture new ideas"

## Rules

- **Do NOT** edit any files — this is read-only
- **Do NOT** start implementing or planning — only recommend
- Keep the output concise — one line per item
- If another session is actively implementing (state `active`), note it
- **Final response under 2000 characters. List outcomes, not process.**

## Quick mode

If the user just wants the recommendation without the full report, respond with only the "Recommended next action" line.
