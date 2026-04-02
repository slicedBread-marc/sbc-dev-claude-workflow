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
develop (T1, T2)                           feature/ (T3, T4)               release, main
  - Plans only                             - Code only                     - Ship it
  
  T1: Intake 🔵      T2: Planner 🟢             T3/T4: Worktree
  (/wf-status,        (/wf-spec)                 (/wf-implement, /wf-verify, /wf-test)
  /wf-brainstorm,           │                            │
  /wf-bug)                  └─→ [ready/] ←──────────────┤
                                   │                      │
                                   └──→ [active/] ←──────┘
                                           │
                                           └──→ [verify/] ──→ [human test] ──→ [release PR]
                                           
  T3: Builder 🟡     T4: Validator 🟣
  (/wf-implement)    (/wf-verify, /wf-test)
                                                                                    │
                                                                           (staging validation)
                                                                                    │
                                                                           /wf-release: main → complete
```

Then say: "Run `/wf-help` anytime to see the full strategy."

### 2. Prompt for terminal role

```
Which terminal are you?
1) T1 — Intake 🔵 (/wf-status, /wf-brainstorm, /wf-bug) [Sonnet]
2) T2 — Planner 🟢 (/wf-spec) [Opus]
3) T3 — Builder 🟡 (/wf-implement loop) [Opus]
4) T4 — Validator 🟣 (/wf-verify loop) [Sonnet]
```

Wait for user input (1–4).

### 3. Confirm role and set terminal color

Based on selection, show and apply:
```
✓ You are T2 (Planner) 🟢
✓ Model: Opus 4.6
✓ Command: /model opus
✓ Terminal color: GREEN

What you'll do:
  • /wf-spec to convert briefs to plans
  • Review and approve implementation
  • Move plans to ready/ queue
  • Keep T3 fed with work
```

**Set terminal background color** (per role):
```bash
# T1 — Intake (blue)
printf "\033]11;rgb:0066FF\033\\"

# T2 — Planner (green)
printf "\033]11;rgb:00CC00\033\\"

# T3 — Builder (yellow)
printf "\033]11;rgb:FFCC00\033\\"

# T4 — Validator (purple)
printf "\033]11;rgb:9933FF\033\\"
```

Then set the terminal role for `/wf-next`:
```bash
export TERMINAL_ROLE="T2 — Planner"
/wf-next
```

This will automatically invoke the right skill for your role and the terminal background will remain colored.

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

### 5. Check folder structure and branches

Verify these folders exist (create if missing):
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

Verify these branches exist (warn if missing):
```
✓ develop (current)
✓ release
✓ main
```

If `release` branch does not exist locally:
```
⚠️  Release branch not found. Create it:
  git checkout develop
  git checkout -b release
  git push origin release
```

Show:
```
✓ Folder structure: ready
✓ Branches: develop, release, main
```

### 6. Suggest next steps

Based on role:

**T1 (Intake) 🔵:**
```
NEXT STEPS:
1. Set terminal color: printf "\033]11;rgb:0066FF\033\\"
2. /model sonnet
3. /loop 10m /wf-status
4. /wf-brainstorm to capture new ideas
5. /wf-bug to file discovered issues
6. Keep T2 fed with decided briefs

Run /wf-help to understand the flow.
```

**T2 (Planner) 🟢:**
```
NEXT STEPS:
1. Set terminal color: printf "\033]11;rgb:00CC00\033\\"
2. /model opus
3. /wf-spec BRF-001 (or pick a brief)
4. Convert briefs to plans, move to ready/
5. Keep ready/ queue at 2–3 plans for T3

Run /wf-help to understand the flow.
```

**T3 (Builder) 🟡:**
```
NEXT STEPS:
1. Set terminal color: printf "\033]11;rgb:FFCC00\033\\"
2. /model opus
3. /wf-implement
4. Follow prompts to create feature branch + worktree
5. Switch to worktree directory (shown by /wf-implement)
6. Run /wf-implement again in the worktree to start coding
7. When done: /wf-verify → /wf-test → creates PR to release

After: wait for staging validation, then /wf-release moves to production.
Run /wf-help to understand the flow.
```

**T4 (Validator) 🟣:**
```
NEXT STEPS:
1. Set terminal color: printf "\033]11;rgb:9933FF\033\\"
2. /model sonnet
3. Join T3 in the worktree directory (same feature branch)
4. After /wf-implement finishes, run /wf-verify
5. If all tests pass, /wf-test walks through acceptance criteria
6. On pass, PR is created to release branch

Wait for staging validation, then /wf-release handles production.
Run /wf-help to understand the flow.
```

### 7. Final summary

```
═══════════════════════════════════════════════════════════════════════════
Session: 2026-04-02-1743868195
Terminal: T2 (Planner) 🟢
Background: GREEN
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
- **Terminal title:** To make the title persist across all sessions, add the `precmd` hook to `~/.zshrc` (see step 3)

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
