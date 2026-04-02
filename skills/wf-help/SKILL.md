---
name: wf-help
description: Display the overall workflow strategy, architecture, and reference guide. Shows how the 4-terminal setup works and explains the full pipeline.
user_invocable: true
model: haiku
---

# Help & Strategy

You are in **help mode**. Your job is to display the overall workflow architecture so users understand the system, how it works, and how to use it.

## What to show

Display the full strategy with ASCII diagrams and clear explanations:

```
╔════════════════════════════════════════════════════════════════════════════╗
║                    Workflow Strategy: 4-Terminal Pipeline                  ║
╚════════════════════════════════════════════════════════════════════════════╝

┌──────────────┬──────────────┐
│  T1: Planner │  T2: Builder │
│  (/wf-spec)  │(/wf-implement)
│   [Opus]     │   [Opus]     │
└──────────────┴──────────────┘
       │              │
       └──→ [ready/] ←┘
               │
               ↓
       [active/] (T2 works)
               │
               ↓
        [verify/] ←─ T3: Validator (/wf-verify) [Sonnet]
               │
               ↓
    [complete/] ←─ T3: Debug (/wf-debug) [Sonnet]
               │
               ↓
      T4: Intake (/wf-status, /wf-brainstorm, /wf-bug) [Sonnet]
          (feeds new work back to T1)


═══════════════════════════════════════════════════════════════════════════

THE FLOW:

1. T1 reads Decided briefs + open bugs
2. T1 runs /wf-spec → creates plan → moves to ready/
3. T2 runs /wf-implement in a loop → auto-picks plans from ready/
4. T2 executes steps, commits, moves to verify/
5. T3 runs /wf-verify in a loop → tests + checks against plan
6. T3 can run /wf-debug for manual verification
7. T4 runs /wf-status to monitor queue health
8. T4 runs /wf-brainstorm to feed new briefs to T1
9. Loop continues: spec → implement → verify → debug → brainstorm

═══════════════════════════════════════════════════════════════════════════

TERMINAL ROLES:

T1: Opus Planner
  • /wf-spec: Convert briefs/bugs → implementation plans
  • Keeps ready/ queue filled (2–3 plans ahead)
  • Manual (not looped)

T2: Opus Builder
  • /wf-implement: Execute plans step-by-step
  • Runs in loop: /loop 2m /wf-implement
  • Auto-picks plans from ready/ when available
  • BOTTLENECK: If idle, means T1 is too slow

T3: Sonnet Validator
  • /wf-verify: Run tests, check against plan
  • Runs in loop: /loop 3m /wf-verify
  • /wf-debug: Manual verification with screenshots
  • /wf-rollback: Revert plans if issues found
  • Validates in parallel with T2's building

T4: Sonnet Intake
  • /wf-status: Monitor pipeline health
  • /wf-brainstorm: Capture new ideas → briefs
  • /wf-bug: File bugs discovered during debug
  • /wf-init: One-time setup (logging, session)

═══════════════════════════════════════════════════════════════════════════

QUEUE STATES:

plans/ready/     → Plans waiting for T2 to implement
plans/active/    → Plan being worked on by T2
plans/verify/    → Plan waiting for T3 to verify
plans/complete/  → Plan finished and verified
plans/rolled-back/ → Plan reverted due to issues

bugs/open/       → Bugs waiting for T1 to plan fixes
bugs/triaged/    → Bugs linked to plans in progress
bugs/closed/     → Bugs fixed and verified

═══════════════════════════════════════════════════════════════════════════

LOGGING & METRICS:

• All terminals share one SESSION_ID (e.g., 2026-04-02-1743868195)
• Each terminal gets unique ID (T1–T4): 2026-04-02-1743868195-T1
• Logs to .logs/workflow.log with queue state on every action
• Format: [HH:MM:SS] SESSION_ID | SKILL | ACTION | METRIC | Q: ready=N verify=N...
• Use /wf-metrics (TODO) to analyze logs and detect bottlenecks

═══════════════════════════════════════════════════════════════════════════

BOTTLENECK PREVENTION:

Rule 1: T2 should never be idle
  → If no plans in ready/, T1 is too slow → help T1 spec faster

Rule 2: T1 should stay 2–3 plans ahead
  → Check ready/ before T1 finishes each spec

Rule 3: T3 validates in parallel
  → Don't wait for T2 to finish before T3 validates

Rule 4: T4 keeps intake flowing
  → If < 3 Decided briefs, brainstorm more

═══════════════════════════════════════════════════════════════════════════

GETTING STARTED:

1. Terminal 1: /wf-init → select T1, follow prompts
2. Terminal 2: /wf-init → select T2, follow prompts
3. Terminal 3: /wf-init → select T3, follow prompts
4. Terminal 4: /wf-init → select T4, follow prompts

Then:
  T1: /wf-spec BRF-001 (or pick a brief)
  T2: (auto-loops, waits for ready plans)
  T3: (auto-loops, waits for plans to verify)
  T4: /wf-status (check queue, capture new ideas)

═══════════════════════════════════════════════════════════════════════════
```

## When to show this

- `/wf-help` — show full strategy (above)
- `/wf-help status` — show queue state explanation
- `/wf-help bottleneck` — show how to detect and fix bottlenecks
- `/wf-help logging` — show logging format and metrics

## Rules

- **Keep it visual** — ASCII diagrams help
- **Be concise** — reference, not tutorial
- **Link to detailed docs** — point to MANUAL_SETUP.md for deep dives
- **Always** — never refuse to show help
