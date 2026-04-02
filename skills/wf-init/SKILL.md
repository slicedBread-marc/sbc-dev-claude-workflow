---
name: wf-init
description: One-time setup for a workflow session. Prompts for terminal role, sets up logging context, checks folder structure, and guides next steps. Run this once per terminal at session start.
user_invocable: true
model: haiku
---

# Init Role

You are in **init mode**. Your job is to set up a terminal for the workflow session: establish its role, configure logging, and provide next-step guidance.

## What you do

### 1. Show the strategy (briefly)

Display the 4-terminal pipeline:
```
T1: Intake              T2: Planner             T3: Builder              T4: Validator
(/wf-status,            (/wf-spec)              (/wf-implement)          (/wf-verify)
/wf-brainstorm,                │                      │                        │
/wf-bug)                       └─→ [ready/] ←────────┘                        │
                                      │                                        │
                                      └──────→ [verify/] ←────────────────────┘
```

Then say: "Run `/wf-help` anytime to see the full strategy."

### 2. Prompt for terminal role

```
Which terminal are you?
1) T1 — Intake (/wf-status, /wf-brainstorm, /wf-bug) [Sonnet]
2) T2 — Planner (/wf-spec) [Opus]
3) T3 — Builder (/wf-implement loop) [Opus]
4) T4 — Validator (/wf-verify loop) [Sonnet]
```

Wait for user input (1–4).

### 3. Confirm role and model

Based on selection, show:
```
✓ You are T2 (Builder)
✓ Model: Opus 4.6
✓ Command: /model opus

What you'll do:
  • /loop 2m /wf-implement
  • Auto-picks plans from plans/ready/
  • Executes steps, writes tests, commits
  • Moves completed plans to verify/
```

### 4. Set up logging context

Create/read session files:
```bash
mkdir -p .logs
if [ ! -f ".logs/SESSION_TIMESTAMP" ]; then
  date +%Y-%m-%d-%s > .logs/SESSION_TIMESTAMP
  echo "📝 New session: $(cat .logs/SESSION_TIMESTAMP)"
else
  echo "📝 Joining session: $(cat .logs/SESSION_TIMESTAMP)"
fi

# Derive terminal ID from TERM_SESSION_ID
export SESSION_ID="$(cat .logs/SESSION_TIMESTAMP)-T${ROLE_NUM}"
echo "📝 Your ID: $SESSION_ID"
```

Then show:
```
✓ Logging enabled to .logs/workflow.log
✓ SESSION_ID: 2026-04-02-1743868195-T2
✓ Queue metrics tracked automatically
```

### 5. Check folder structure

Verify these exist (create if missing):
```
✓ plans/ready/
✓ plans/active/
✓ plans/verify/
✓ plans/complete/
✓ plans/rolled-back/
✓ bugs/open/
✓ bugs/triaged/
✓ bugs/closed/
```

Show:
```
✓ Folder structure: ready
```

### 6. Suggest next steps

Based on role:

**T1 (Intake):**
```
NEXT STEPS:
1. /model sonnet
2. /loop 10m /wf-status
3. /wf-brainstorm to capture new ideas
4. /wf-bug to file discovered issues
5. Keep T2 fed with decided briefs

Run /wf-help to understand the flow.
```

**T2 (Planner):**
```
NEXT STEPS:
1. /model opus
2. /wf-spec BRF-001 (or pick a brief)
3. Convert briefs to plans, move to ready/
4. Keep ready/ queue at 2–3 plans for T3

Run /wf-help to understand the flow.
```

**T3 (Builder):**
```
NEXT STEPS:
1. /model opus
2. /loop 2m /wf-implement
3. Wait for T2 to create ready plans
4. Auto-picks and executes them

If idle, alert T2 (plans/ready/ is empty).
Run /wf-help to understand the flow.
```

**T4 (Validator):**
```
NEXT STEPS:
1. /model sonnet
2. /loop 3m /wf-verify
3. Auto-validates plans from plans/verify/
4. Can manually /wf-debug if needed

Run /wf-help to understand the flow.
```

### 7. Final summary

```
═══════════════════════════════════════════════════════════════════════════
Session: 2026-04-02-1743868195
Terminal: T2 (Builder)
Model: Opus 4.6
Logging: Enabled → .logs/workflow.log

Ready to go! Follow the NEXT STEPS above.
═══════════════════════════════════════════════════════════════════════════
```

## Rules

- **Idempotent:** Running init multiple times in same terminal is safe (just re-shows info)
- **Session file:** `.logs/SESSION_TIMESTAMP` is created by first terminal, read by others
- **No errors:** If .logs/ can't be created, warn but continue (logging just won't work)
- **Always helpful:** Show `/wf-help` reference in output

## Logging gate

Other skills check:
```bash
if [ -n "$SESSION_ID" ] && [ -d ".logs" ]; then
  log_start "skill_name" "metric"
  # ... do work ...
  log_done "skill_name" "outcome"
else
  # Logging disabled, skill still runs
  # ... do work ...
fi
```

If user runs a skill without `/wf-init`, it works but doesn't log. No friction.

---

## One-time setup checklist

Users will see this after init completes:

- [ ] Run `/model [opus|sonnet]` (shown in NEXT STEPS)
- [ ] Run your assigned skill(s)
- [ ] Open other terminals and run `/wf-init` in each
- [ ] Verify `/wf-status` shows healthy queues
- [ ] Run `/wf-help` to review strategy anytime
