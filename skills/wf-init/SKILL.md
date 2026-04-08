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

Display the pipeline:
```
REGISTRY.md is the single source of truth for all plan state.

  T1: Intake 🔵      T2: Planner 🟢      T3: Builder 🟡     T4: Tester 🟣
  (/wf-status,        (/wf-spec)          (/wf-implement)    (/wf-test)
  /wf-brainstorm,
  /wf-bug)

  State flow: draft → ready → active → verify ──[agent]──→ testing → complete
                        ↑        |
                        |        ├→ active  (fix cycle)
                        |        └→ draft   (escalation)
                        └→ draft  (implementer escalation)

  Verify agent runs automatically when a plan reaches "verify" state.
  T4 only does human acceptance testing on plans in "testing" state.
```

Then say: "Run `/wf-help` anytime to see the full strategy."

### 2. Prompt for terminal role

```
Which terminal are you?
1) T1 — Intake 🔵 (/wf-status, /wf-brainstorm, /wf-bug) [Sonnet]
2) T2 — Planner 🟢 (/wf-spec) [Opus]
3) T3 — Builder 🟡 (/wf-implement) [Sonnet]
4) T4 — Tester 🟣 (/wf-test) [Haiku]
```

Wait for user input (1–4).

### 3. Confirm role and set terminal color

Based on selection, show and apply:
```
✓ You are T2 (Planner) 🟢
✓ Model: Opus 4.6
✓ Command: /model opus
✓ Terminal color: GREEN
```

**Set terminal background color** by invoking the color command (per role):
- **T1 — Intake 🔵:** `/color blue`
- **T2 — Planner 🟢:** `/color green`
- **T3 — Builder 🟡:** `/color yellow`
- **T4 — Tester 🟣:** `/color purple`

Then set the terminal role and invoke the next skill:
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

Verify structure and branches:
```bash
scripts/wf-branch-check.sh develop true
```

Then check these exist (create if missing):
```bash
mkdir -p plans/briefs bugs/open bugs/triaged bugs/closed feature-branches
[ -f plans/REGISTRY.md ] || echo "⚠️  plans/REGISTRY.md missing"
```

Verify branches:
```bash
git branch --list develop release main
```

If `release` branch does not exist locally, warn:
```
⚠️  Release branch not found. Create it:
  git checkout develop && git checkout -b release && git push origin release
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
1. /color blue
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
1. /color green
2. /model opus
3. /wf-spec BRF-001 (or pick a brief)
4. Convert briefs to plans, move to ready/
5. Keep ready/ queue at 2–3 plans for T3

Run /wf-help to understand the flow.
```

**T3 (Builder) 🟡:**
```
NEXT STEPS:
1. /color yellow
2. /model sonnet
3. /wf-implement
4. Follow prompts to create feature branch + worktree
5. Switch to worktree directory (shown by /wf-implement)
6. Run /wf-implement again in the worktree to start coding
7. When done: /wf-test → creates PR to release

After: merge PR, then /wf-release validates staging, then /wf-deploy promotes to main.
Run /wf-help to understand the flow.
```

**T4 (Tester) 🟣:**
```
NEXT STEPS:
1. /color purple
2. /model haiku
3. /wf-test — shows plans in "testing" state (passed automated verify agent)
4. Walk through human acceptance criteria
5. On pass, PR is created to release branch
6. Merge PR, then /wf-release validates staging, then /wf-deploy promotes to main

The verify agent handles automated checks — T4 only does human testing.
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
