# Manual Multi-Terminal Setup

## Overview

This is the ideal setup for running the workflow with maximum throughput. It enables **parallel planning and implementation** without bottlenecks by using 4 dedicated terminals, each with a fixed model and assigned skills.

## Terminal Layout

```
┌─────────────────────┬─────────────────────┐
│  T1: Opus Planner   │  T2: Opus Builder   │
│  /wf-spec           │  /wf-implement      │
├─────────────────────┼─────────────────────┤
│  T3: Sonnet         │  T4: Sonnet Intake  │
│  Validator          │  /wf-status         │
│  /wf-verify         │  /wf-brainstorm     │
│  /wf-debug          │  /wf-bug            │
│  /wf-rollback       │                     │
└─────────────────────┴─────────────────────┘
```

## Logging & Session Tracking

All terminals append to a single unified log file: `.logs/workflow.log`

### Setup (one time)
```bash
source .logs-utils.sh
init_session "2026-04-02-A"  # or let it auto-generate
```

### Session ID format
`YYYY-MM-DD-TERMINAL-ID` (e.g., `2026-04-02-T1`, `2026-04-02-A`)

### Each skill logs on start and completion
```bash
log_start "wf-spec" "BRF-001"
# ... do work ...
log_done "wf-spec" "PLN-001→ready"
```

### Log format
```
[HH:MM:SS] SESSION_ID | SKILL | ACTION | METRIC | Q: ready=N verify=N active=N open=N triaged=N
```

### Useful commands
```bash
source .logs-utils.sh
log_tail 20              # show last 20 lines
log_watch                # stream log in real-time (tail -f)
log_summary 2026-04-02   # show all lines from a session
```

### File locking (automatic)
- Uses `flock` to serialize writes
- Prevents line interleaving if multiple terminals log simultaneously
- Blocking: processes wait their turn (~1ms overhead per write)

---

## Terminal Setup

### T1: Opus Planner
**Purpose:** Convert decided briefs and bugs into implementation plans.

- **Model:** Opus 4.6
- **Skills:** `/wf-spec` (primary)
- **Startup sequence:**
  ```bash
  source .logs-utils.sh
  init_session "2026-04-02-T1"  # or auto-generate
  /model opus
  ```
- **Responsibilities:**
  - Read `plans/briefs/INDEX.md` for Decided briefs
  - List open bugs in `bugs/open/`
  - Create plans in `plans/drafts/`
  - Move approved plans to `plans/ready/`
  - Always keep 2-3 ready plans ahead of T2's pace

### T2: Opus Builder
**Purpose:** Implement ready plans and produce working code.

- **Model:** Opus 4.6
- **Skills:** `/wf-implement` (primary)
- **Startup sequence:**
  ```bash
  source .logs-utils.sh
  init_session "2026-04-02-T2"  # or match T1's date for same session
  /model opus
  /loop 2m /wf-implement
  ```
- **Responsibilities:**
  - Pick plans from `plans/ready/`
  - Execute steps and write tests
  - Move completed plans to `plans/verify/`
  - If idle waiting for a ready plan, signal T1 to spec faster

### T3: Sonnet Validator
**Purpose:** Test implementations, debug issues, handle rollbacks.

- **Model:** Sonnet 4.6
- **Skills:** `/wf-verify`, `/wf-debug`, `/wf-rollback`
- **Startup sequence:**
  ```bash
  source .logs-utils.sh
  init_session "2026-04-02-T3"
  /model sonnet
  /loop 3m /wf-verify
  ```
- **Responsibilities:**
  - Run `/wf-verify` on plans in `plans/verify/`
  - Run `/wf-debug` on completed plans if manual testing needed
  - Run `/wf-rollback` if issues found
  - Can run in parallel with T2's implementation
  - Monitor for completed plans and pull them proactively

### T4: Sonnet Intake
**Purpose:** Feed work into the pipeline, maintain visibility.

- **Model:** Sonnet 4.6
- **Skills:** `/wf-status`, `/wf-brainstorm`, `/wf-bug`
- **Startup sequence:**
  ```bash
  source .logs-utils.sh
  init_session "2026-04-02-T4"
  /model sonnet
  /loop 10m /wf-status
  ```
- **Responsibilities:**
  - Run `/wf-status` every 10–15 minutes to check pipeline health
  - Run `/wf-brainstorm` to capture new ideas as briefs
  - Run `/wf-bug` to file bugs discovered during `/wf-debug`
  - Ensure `plans/briefs/` has at least 3 Decided briefs ready for T1
  - Alert if bottleneck detected (T2 idle, waiting for ready plans)

## Workflow Rhythm

### Pre-Session (5 min)
1. **T4:** Run `/wf-status` — assess current state
   - Are there ready plans for T2?
   - Are there plans waiting in verify/ for T3?
   - How many briefs are Decided?
2. **T1:** If < 2 ready plans exist, start `/wf-spec`
3. **T2:** If ready plans exist, start `/wf-implement`
4. **T3:** If plans in verify/, start `/wf-verify`

### Concurrent Work (during session)
- **T1** specs PLN-003 while T2 implements PLN-001
- **T3** verifies PLN-001 (completed) while T2 is on step 5/8 of PLN-002
- **T4** captures new briefs or files bugs while others work

### Handoff Pattern
```
T1 completes /wf-spec (PLN-002 → ready/)
  ↓
T2 pulls PLN-002 from plans/ready/
  ↓
T1 starts /wf-spec on next brief
  ↓
(if no brief ready, T1 pulls from /wf-brainstorm results or waits)
```

## Bottleneck Prevention

### Rule 1: T2 should never be idle
If T2 (builder) finishes a plan and no ready plans exist:
- **Action:** Drop to T1 and run `/wf-spec` immediately
- **Reason:** T2 is the bottleneck. Empty the ready/ queue is wasteful.

### Rule 2: T1 should stay 2-3 plans ahead
Before T1 finishes a spec session:
- Check `plans/ready/` — if < 2 plans, start another spec
- **Reason:** T2 should never wait for T1's next output

### Rule 3: T3 validates in parallel
Don't wait for T2 to finish before T3 validates. As soon as a plan moves to `plans/verify/`:
- **Action:** T3 picks it up immediately
- **Reason:** Validation can happen while T2 builds the next plan

### Rule 4: T4 keeps the intake flowing
If `/wf-status` shows < 3 Decided briefs:
- **Action:** T4 runs `/wf-brainstorm` to create more briefs
- **Reason:** T1 should never run out of input

## Context-Switching Guide

### When T1 is done speccing (5–10 min per plan)
- **If plans/ready/ is full (3+):** Idle or help T4 brainstorm
- **If plans/ready/ is low (< 2):** Spec another brief immediately
- **If a brief is Decided but not spec'd:** Spec it now

### When T2 is done implementing (15–30 min per plan)
- **If plans/ready/ is empty:** Switch to T1 and help spec
- **If plans/ready/ has 2+:** Start `/wf-implement` on next plan
- **If new plans appear while implementing:** Commit current step and pick up next plan

### When T3 is done verifying (10–20 min per plan)
- **If plans/verify/ is empty:** Wait or check for completed plans
- **If plans/complete/ exists:** Run `/wf-debug` for manual verification
- **If issues found:** Run `/wf-bug` to file the issue

### When T4 is done with status (2–3 min)
- **If pipeline is healthy (3+ ready, 0 waiting):** Brainstorm new ideas
- **If pipeline is starving (< 2 ready):** Alert T1 or spec yourself
- **If new bugs discovered:** File them with `/wf-bug`

## Logging Examples

### Sample log output
```
[14:23:15] 2026-04-02-T1 | wf-spec | start | BRF-001 | Q: ready=1 verify=0 active=0 open=5 triaged=2
[14:33:42] 2026-04-02-T1 | wf-spec | done | PLN-001→ready | Q: ready=2 verify=0 active=0 open=5 triaged=2
[14:35:10] 2026-04-02-T2 | wf-implement | start | PLN-001 | Q: ready=1 verify=0 active=0 open=5 triaged=2
[14:52:30] 2026-04-02-T2 | wf-implement | done | PLN-001→verify | Q: ready=1 verify=1 active=0 open=5 triaged=2
[14:53:00] 2026-04-02-T3 | wf-verify | start | PLN-001 | Q: ready=1 verify=0 active=0 open=5 triaged=2
[15:08:45] 2026-04-02-T3 | wf-verify | done | PLN-001→complete | Q: ready=1 verify=0 active=0 open=5 triaged=2
[15:09:10] 2026-04-02-T4 | wf-bug | create | BUG-004 | Q: ready=1 verify=0 active=0 open=6 triaged=2
```

### Watch log in real-time
```bash
source .logs-utils.sh
log_watch
# Streams new lines as they're appended
```

### Check recent activity
```bash
log_tail 50  # last 50 lines
log_summary 2026-04-02  # all lines from that date
```

---

## Example Session (90 minutes)

```
T4 [00:00] /wf-status
  → 2 briefs ready (BRF-001, BRF-002), 0 ready plans, 0 verifying

T1 [00:00] /wf-spec BRF-001 → PLN-001 ready [10 min]
T4 [00:05] /wf-brainstorm capture BRF-003 [5 min]

T2 [00:10] /wf-implement PLN-001 [T1 just moved it to ready/]
T1 [00:10] /wf-spec BRF-002 → PLN-002 ready [10 min]

T3 [00:15] /wf-status check (nothing to verify yet, wait)

T2 [00:20] PLN-001 step 3/7
T1 [00:20] PLN-002 ready [T1 → ready/]
T3 [00:20] Nothing to verify, idle

T2 [00:25] Step 5/7 of PLN-001
T1 [00:25] /wf-spec PLN-003 from BRF-003 [T4 just captured it]
T3 [00:25] Still idle
T4 [00:25] /wf-brainstorm — explore new feature idea

T2 [00:30] PLN-001 → verify/ [moving to T3]
  Immediately pulls PLN-002 from ready/ → starts
T3 [00:30] /wf-verify PLN-001 [15 min]
T1 [00:30] Still speccing PLN-003

T2 [00:40] Step 3/8 of PLN-002
T1 [00:35] PLN-003 ready [→ ready/]
T3 [00:35] Verifying PLN-001, step 3/4
T4 [00:40] /wf-status — pipeline healthy

T3 [00:45] PLN-001 complete → plans/complete/
T2 [00:55] PLN-002 → verify/ [moves to T3]
T3 [00:55] /wf-verify PLN-002
T1 [00:55] /wf-spec PLN-004 from remaining brief [if available]

T2 [00:55] Pulls PLN-003 from ready/ → starts /wf-implement

[Loop continues: T1 feeds, T2 builds, T3 validates, T4 monitors]
```

## Checklist: Before Each Session

**Logging setup (all terminals):**
- [ ] All: `source .logs-utils.sh`
- [ ] All: `init_session "YYYY-MM-DD-TN"` (T1, T2, T3, T4 — same date)
- [ ] One: `log_watch` (in a 5th window) to monitor log in real-time

**Terminal startup:**
- [ ] T1: `/model opus` (+ any /loop or /wf-spec)
- [ ] T2: `/model opus` + `/loop 2m /wf-implement`
- [ ] T3: `/model sonnet` + `/loop 3m /wf-verify`
- [ ] T4: `/model sonnet` + `/loop 10m /wf-status`

**Pipeline health check:**
- [ ] T4: Run `/wf-status` to see current state
- [ ] T1: Check if specs are needed (ready/ < 2)
- [ ] T2: Check if ready plans exist to implement
- [ ] T3: Check if plans in verify/ to validate

## Checklist: Monitoring Health

During a session, watch for these signs of bottlenecks:

| Symptom | Cause | Fix |
|-|-|-|
| T2 idle, no ready plans | T1 too slow | T1 spec faster or switch to T1 and help |
| T1 idle, ready plans full | T2 too slow | Normal — let T2 work; T1 waits |
| T3 always idle | No plans completing | Check if T2 is moving plans to verify |
| T4 can't brainstorm | No decided briefs | T4 should create briefs from ideas |

## Notes

- **Model switching cost:** Each terminal does `/model X` once at startup. Don't switch models mid-terminal.
- **Session length:** Typically 60–90 minutes per session. After that, review metrics and start a new session.
- **Logging:** All terminals append to `.logs/workflow.log` with file locking (flock). Safe for concurrent writes.
- **Metrics:** Parse `.logs/workflow.log` to analyze queue trends, bottlenecks, throughput. `/wf-metrics` skill (TODO) will automate this.
- **Parallel limits:** Realistically, T1 and T2 can run in true parallel only if you have 2+ physical terminals or split-screen. If sharing one screen, context-switch between them every 5–10 minutes.
- **Idle time is OK:** T1 or T3 being idle briefly is fine. T2 (builder) being idle is a sign to help T1.
- **.logs directory:** Gitignored (local only). Logs persist across sessions for historical analysis.
