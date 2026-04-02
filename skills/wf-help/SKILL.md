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

T1: Intake                T2: Planner              T3: Builder              T4: Validator
(/wf-status,              (/wf-spec)               (/wf-implement)          (/wf-verify)
/wf-brainstorm,                  │                        │                        │
/wf-bug)                         └──→ [ready/] ←─────────┘                        │
[Sonnet]                               │                                          │
    ▲                                  └────→ [verify/] ←──────────────────────────┘
    └─────────────────────────────────────────────────────────────┐
                                                                   │
                     (feeds new briefs & bug fixes back to intake)
                                                                   │
                                                      [complete/]◄─┘


═══════════════════════════════════════════════════════════════════════════

THE FLOW:

1. T1 monitors pipeline with /wf-status, captures ideas with /wf-brainstorm, files bugs
2. T1 feeds Decided briefs to T2
3. T2 runs /wf-spec → converts briefs to plans → moves to ready/
4. T3 runs /wf-implement in a loop → auto-picks plans from ready/
5. T3 executes steps, writes tests, commits, moves to verify/
6. T4 runs /wf-verify in a loop → tests + checks against plan
7. T4 can run /wf-debug for manual verification
8. T4 moves verified plans to complete/
9. Loop continues: intake → plan → build → verify → back to intake for next work

═══════════════════════════════════════════════════════════════════════════

TERMINAL ROLES:

T1: Sonnet Intake
  • /wf-status: Monitor pipeline health (queue depth, bottlenecks)
  • /wf-brainstorm: Capture new ideas → Decided briefs
  • /wf-bug: File bugs discovered during verification
  • Feeds work to T2 (keeps briefs flowing)

T2: Opus Planner
  • /wf-spec: Convert briefs/bugs → implementation plans
  • Keeps ready/ queue filled (2–3 plans ahead)
  • Manual (not looped)
  • BOTTLENECK: If idle, means T1 is starving (no briefs)

T3: Opus Builder
  • /wf-implement: Execute plans step-by-step
  • Runs in loop: /loop 2m /wf-implement
  • Auto-picks plans from ready/ when available
  • BOTTLENECK: If idle, means T2 is too slow

T4: Sonnet Validator
  • /wf-verify: Run tests, check against plan
  • Runs in loop: /loop 3m /wf-verify
  • /wf-debug: Manual verification with screenshots
  • /wf-rollback: Revert plans if issues found
  • Validates in parallel with T3's building

═══════════════════════════════════════════════════════════════════════════

QUEUE STATES:

plans/ready/     → Plans waiting for T3 to implement
plans/active/    → Plan being worked on by T3
plans/verify/    → Plan waiting for T4 to verify
plans/complete/  → Plan finished and verified
plans/rolled-back/ → Plan reverted due to issues

bugs/open/       → Bugs waiting for T2 to plan fixes (fed by T1)
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

Rule 1: T3 (Builder) should never be idle
  → If no plans in ready/, T2 is too slow → help T2 spec faster

Rule 2: T2 should keep 2–3 plans ready ahead of T3
  → Check ready/ before T2 finishes each spec

Rule 3: T4 validates in parallel
  → Don't wait for T3 to finish before T4 validates

Rule 4: T1 keeps the intake flowing
  → If < 3 Decided briefs, run /wf-brainstorm more

═══════════════════════════════════════════════════════════════════════════

GETTING STARTED:

1. Terminal 1: /wf-init → select T1 (Intake), follow prompts
2. Terminal 2: /wf-init → select T2 (Planner), follow prompts
3. Terminal 3: /wf-init → select T3 (Builder), follow prompts
4. Terminal 4: /wf-init → select T4 (Validator), follow prompts

Then:
  T1: /loop 10m /wf-status (monitor queue) + /wf-brainstorm (feed work)
  T2: /wf-spec BRF-001 (convert briefs to plans)
  T3: /loop 2m /wf-implement (auto-picks ready plans)
  T4: /loop 3m /wf-verify (auto-validates completed plans)

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
