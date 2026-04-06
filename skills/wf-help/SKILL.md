---
name: wf-help
description: Display the overall workflow strategy, architecture, and reference guide. Shows how the terminal setup works and explains the full pipeline.
user_invocable: true
model: haiku
---

# Help & Strategy

You are in **help mode**. Your job is to display the overall workflow architecture so users understand the system, how it works, and how to use it.

## What to show

Display the full strategy with ASCII diagrams and clear explanations:

```
╔════════════════════════════════════════════════════════════════════════════╗
║                    Workflow Strategy: Terminal Pipeline                    ║
╚════════════════════════════════════════════════════════════════════════════╝

T1: Intake                T2: Planner              T3: Builder              T4: Tester
(/wf-status,              (/wf-spec)               (/wf-implement)          (/wf-test)
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
4. T3 runs /wf-implement → auto-picks plans from ready/
5. T3 executes steps, writes tests, runs code/architecture review, E2E tests, moves to verify/
6. T4 runs /wf-test → human acceptance testing against plan criteria
7. T4 creates PR to release on pass
8. Merge PR to release, validate staging
9. /wf-release: merge release → main, plans move to complete/, bugs closed, back-merge to develop
10. Loop continues: intake → plan → build → test → release → production → back to intake

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

T3: Sonnet Builder
  • /wf-implement: Execute plans step-by-step
  • Runs in loop: /loop 2m /wf-implement
  • Auto-picks plans from ready/ when available
  • BOTTLENECK: If idle, means T2 is too slow

T4: Haiku Tester
  • /wf-test: Human acceptance testing against plan criteria
  • Deploys to local container, walks through checklist
  • Creates PR to release on pass
  • /wf-rollback: Revert plans if issues found
  • Tests in parallel with T3's next build

Release (any terminal on release/main branch):
  • /wf-release: Promote release → main, mark plans complete, close bugs
  • Merges release to main, moves plans to complete/, back-merges to develop
  • Run after PRs are merged to release and staging is validated

═══════════════════════════════════════════════════════════════════════════

QUEUE STATES:

plans/ready/     → Plans waiting for T3 to implement
plans/active/    → Plan being worked on by T3
plans/verify/    → Plan waiting for T4 to test (human acceptance)
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

Rule 3: T4 tests in parallel
  → While T3 builds the next feature, T4 tests the previous one

Rule 4: T1 keeps the intake flowing
  → If < 3 Decided briefs, run /wf-brainstorm more

═══════════════════════════════════════════════════════════════════════════

GETTING STARTED:

1. Terminal 1: /wf-init → select T1 (Intake), follow prompts
2. Terminal 2: /wf-init → select T2 (Planner), follow prompts
3. Terminal 3: /wf-init → select T3 (Builder), follow prompts
4. Terminal 4: /wf-init → select T4 (Tester), follow prompts

Then:
  T1: /loop 10m /wf-status (monitor queue) + /wf-brainstorm (feed work)
  T2: /wf-spec BRF-001 (convert briefs to plans)
  T3: /wf-implement (auto-picks ready plans, includes code/arch review + E2E tests)
  T4: /wf-test (human acceptance testing in worktree)

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
