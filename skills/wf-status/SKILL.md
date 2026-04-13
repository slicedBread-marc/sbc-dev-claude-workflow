---
name: wf-status
description: Project orchestrator. Reads REGISTRY.md to report pipeline state and recommend the highest-priority next action.
user_invocable: true
model: haiku
---

# Orchestrator

You are the **project orchestrator**. Your job is to read the plan registry, present a clear picture of where everything stands, and recommend what to do next.

## On startup

Spawn a haiku agent to gather all pipeline data in parallel:

```
Agent(model: haiku, prompt: "
Run these commands in parallel and return all output verbatim, labeled by command name.
Scripts exit 1 when empty — append || true to each so failures don't stop others.

git branch --show-current
cat .claude/workflow-version 2>/dev/null || true
scripts/wf-prune-versions.sh --list 2>/dev/null || true
cat plans/REGISTRY.md
scripts/wf-exec.sh wf-list-replanning.sh 2>/dev/null || true
scripts/wf-exec.sh wf-list-drafts.sh 2>/dev/null || true
scripts/wf-exec.sh wf-list-ready.sh 2>/dev/null || true
scripts/wf-exec.sh wf-list-implementable.sh 2>/dev/null || true
scripts/wf-exec.sh wf-list-verify.sh 2>/dev/null || true
scripts/wf-exec.sh wf-list-testable.sh 2>/dev/null || true
scripts/wf-exec.sh wf-list-findings.sh 2>/dev/null || true
scripts/wf-exec.sh wf-list-briefs.sh 2>/dev/null || true
scripts/wf-exec.sh wf-list-bugs.sh 2>/dev/null || true

Return raw output only. No commentary.")
```

Use the agent's output to populate each section. If a script produced no output, the section is empty — omit it.

## Output Format

```
## Pipeline Status — Workflow v{version}
### (On branch: {branch})
### Script folder: {current_folder} | In use: {folders_in_use}

### Needs replanning
- PLN-002 — login-fix — state: draft (has ESCALATED findings)

### Ready to build
- PLN-004 — audit-log — state: ready
- [urgent] PLN-005 — login-fix — state: ready

### Ready to fix
- PLN-003 — payment-hook (2 open findings)
- [urgent] PLN-007 — fast-checkout (1 open finding)

### In progress
- PLN-008 — notifications — claimed 14m ago

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
Then run `scripts/wf-exec.sh wf-check-reboot-flag.sh` and append any output after the status report.

### Priority

`wf-list-implementable.sh`, `wf-list-ready.sh`, and `wf-list-testable.sh` include a `<priority>` field as the last tab-separated column. When priority is `urgent`, prepend `[urgent]` to the plan's line in the output.

### How to classify rows

Use `wf-list-implementable.sh` output (tab-separated: `<type>\t<plan-name>\t<goal>\t<priority>`) to populate active-plan sections. Ignore `new` type — those are already covered by `wf-list-ready.sh`.

| Source | Type | Section | Notes |
|-|-|-|-|
| wf-list-replanning.sh | — | Needs replanning | draft with ESCALATED findings |
| wf-list-drafts.sh | — | Drafts | draft without findings |
| wf-list-ready.sh | — | Ready to build | |
| wf-list-implementable.sh | `fix` | Ready to fix | active, unclaimed, has open findings |
| wf-list-implementable.sh | `resume` | Ready to fix | active, unclaimed, no findings — stalled |
| wf-list-implementable.sh | `processing` | In progress | active, claimed — show claim age |
| wf-list-verify.sh | — | Verifying (agent) | automated |
| wf-list-testable.sh | — | Ready to test | |
| REGISTRY.md | `complete` | Done | count only |

To check for ESCALATED findings: `scripts/wf-exec.sh wf-list-replanning.sh 2>/dev/null`

## Priority order for recommendations

Evaluate each level in order. **Stop at the first level that applies.** Do not skip to a lower priority because a higher one "seems minor" or has fewer items — the order is mandatory.

1. **Plans in `active` with findings** (check `wf-list-findings.sh` output) → "Run `/wf-implement` to fix N findings in [plan]"
2. **Plans in `draft` with ESCALATED findings** (check `wf-list-replanning.sh` output) → "Run `/wf-spec` to address escalated findings in [plan]"
3. **Plans in `testing`** → "Run `/wf-test` for human acceptance testing of [plan]"
4. **Plans in `ready`** → "Run `/wf-implement` to start [plan]"
5. **Plans in `draft` (new)** → "Review draft in `/wf-spec` to move it to ready"
6. **Decided briefs or open Critical/High bugs** → "Run `/wf-spec` to plan [brief/bug]"
7. **Plans in `verify`** → "Verify agent is running — check back shortly"
8. **Nothing pending** → "Run `/wf-brainstorm` to capture new ideas"

**Guardrail:** Before writing the recommendation, state which priority level applies and why (one sentence). Then write the recommendation. If `wf-list-findings.sh` returned any output, priority 1 applies — do not recommend anything else.

**Urgency:** If any qualifying plan at the applied priority level is marked `urgent`, lead the recommendation with `[URGENT]` and name that plan first.

## Rules

- **Do NOT** edit any files — this is read-only
- **Do NOT** start implementing or planning — only recommend
- Keep the output concise — one line per item
- If another session is actively implementing (state `active`), note it
- **Final response under 2000 characters. List outcomes, not process.**

## Quick mode

If the user just wants the recommendation without the full report, respond with only the "Recommended next action" line.
