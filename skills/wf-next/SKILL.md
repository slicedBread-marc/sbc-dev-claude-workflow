---
name: wf-next
description: Run the next appropriate skill for your terminal role. Auto-invokes /wf-spec, /wf-implement, /wf-verify, or /wf-status based on your TERMINAL_ROLE from /wf-init.
user_invocable: true
model: haiku
---

# Next Skill

You are in **next mode**. Your job is to invoke the right skill for your terminal's assigned role, as set by `/wf-init`.

## What you do

1. **Check the `TERMINAL_ROLE` environment variable** — this was exported by `/wf-init`
2. **Parse the role** — extract T1, T2, T3, or T4
3. **Run the appropriate skill (no auto-looping):**
   - **T1 (Intake):** `/wf-status`
   - **T2 (Planner):** `/wf-spec` (prompt for brief selection if needed)
   - **T3 (Builder):** `/wf-implement`
   - **T4 (Validator):** `/wf-verify`

(Users can add `/loop` themselves if they want: `export TERMINAL_ROLE="T3 — Builder" && /loop 2m /wf-next`)

## Special handling for T2 (Planner)

Since `/wf-spec` requires choosing a brief, before invoking it:
1. List available Decided briefs from `plans/briefs/INDEX.md`
2. Ask the user which one to plan (or show a quick menu)
3. Invoke `/wf-spec BRF-NNN`

If no Decided briefs exist, prompt the user to run `/wf-brainstorm` first.

## Error handling

**If `TERMINAL_ROLE` is not set:**
```
ℹ️  TERMINAL_ROLE not found in this session.

Run /wf-init first to see your role, then set it:
  export TERMINAL_ROLE="T1 — Intake"
  /wf-next

(Or run /wf-init again and remember to export after.)
```

**If role is unrecognized:**
```
✗ TERMINAL_ROLE="T5 — Unknown" not recognized.
  Expected one of:
    T1 — Intake
    T2 — Planner
    T3 — Builder
    T4 — Validator

Run /wf-init again or fix the export.
```

## Rules

- **One job:** Just invoke the right skill, don't explain the flow (user knows it from /wf-init)
- **Idempotent:** Running /wf-next multiple times just re-runs the same skill
- **Graceful:** If TERMINAL_ROLE is missing, guide user back to /wf-init
