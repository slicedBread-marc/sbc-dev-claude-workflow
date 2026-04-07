---
name: wf-next
description: Run the next appropriate skill for your terminal role. Auto-invokes /wf-status, /wf-spec, /wf-implement, or /wf-test based on your TERMINAL_ROLE from /wf-init.
user_invocable: true
model: haiku
---

# Next Skill

You are in **next mode**. Your job is to invoke the right skill for your terminal's assigned role, as set by `/wf-init`.

**Role → Skill mapping:**
- T1 (Intake) → `/wf-status`
- T2 (Planner) → `/wf-spec` (no parameters)
- T3 (Builder) → `/wf-implement`
- T4 (Tester) → `/wf-test` (human acceptance testing — verify agent handles automated checks)

## What you do

1. **Check the `TERMINAL_ROLE` environment variable** — this was exported by `/wf-init`
2. **Display your role and what will run** — confirm which skill is about to be invoked
3. **Parse the role** — extract T1, T2, T3, or T4
4. **Run the appropriate skill (no auto-looping):**
   - **T1 (Intake) 🔵:** → `/wf-status`
   - **T2 (Planner) 🟢:** → `/wf-spec` (no parameters — shows all available work)
   - **T3 (Builder) 🟡:** → `/wf-implement`
   - **T4 (Tester) 🟣:** → `/wf-test` (human acceptance testing in the worktree)

**Display before running:**
```
Terminal role: T2 — Planner 🟢
Running: /wf-spec
```

(Users can add `/loop` themselves if they want: `export TERMINAL_ROLE="T3 — Builder" && /loop 2m /wf-next`)

## How it works per role

**T2 (Planner) 🟢:**
- Simply invoke `/wf-spec` with no parameters
- `/wf-spec` will list all available work (Decided briefs and open bugs)
- User picks which one to plan
- No pre-selection needed

## Error handling

**If `TERMINAL_ROLE` is not set:**
```
ℹ️  TERMINAL_ROLE not found in this session.

Run /wf-init first to establish your role:
  /wf-init

Then set your role and run /wf-next:
  export TERMINAL_ROLE="T2 — Planner"
  /wf-next

Available roles:
  T1 — Intake 🔵 (/wf-status, /wf-brainstorm, /wf-bug)
  T2 — Planner 🟢 (/wf-spec)
  T3 — Builder 🟡 (/wf-implement)
  T4 — Tester 🟣 (/wf-test — human acceptance testing)
```

**If role is unrecognized:**
```
✗ TERMINAL_ROLE="T5 — Unknown" not recognized.

Expected one of:
  T1 — Intake 🔵 → runs /wf-status
  T2 — Planner 🟢 → runs /wf-spec
  T3 — Builder 🟡 → runs /wf-implement
  T4 — Tester 🟣 → runs /wf-test

Run /wf-init again or fix the export:
  export TERMINAL_ROLE="T2 — Planner"
  /wf-next
```

## Rules

- **Be verbose:** Display role and skill name before running (so user knows what happened)
- **Idempotent:** Running /wf-next multiple times just re-runs the same skill
- **Graceful:** If TERMINAL_ROLE is missing, guide user back to /wf-init with options
