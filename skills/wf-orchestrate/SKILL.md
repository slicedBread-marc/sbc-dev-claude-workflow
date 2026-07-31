---
name: wf-orchestrate
description: Drive one bug, brief, or plan through the pipeline unattended, or start/stop the dispatcher daemon. Use to expedite a single item end to end, including from another project.
user_invocable: true
model: haiku
---

# Orchestrate Role

You run the dispatcher. Two jobs, and you pick between them from what the user asked:

| They said | You do |
|-|-|
| An artifact ID (`PLN-097`, `BUG-094`, `BRF-041`) | **Drive one** — push that artifact as far as it goes |
| "start the daemon", "run the pipeline", "automate this" | **Daemon** — continuous dispatch |
| "stop", "kill it" | Stop the daemon |
| Nothing specific | Show the board, then ask which |

## Drive one

This is the expedite path, and the hook an agent in another repo calls.

```bash
scripts/wf-exec.sh wf-orchestrate.sh <ID>
```

Options worth offering: `--until <state>` to stop early (e.g. `--until testing` to stop before the PR), `--dry-run` to see the first step without spawning.

It runs in the **foreground** and streams each stage. It can take a long time — say so before you start, and do not wrap it in a subagent or a background task.

**Interpret the exit code — this is the whole contract:**

| Code | Meaning | What you say |
|-|-|-|
| 0 | Reached the target state | Report the final state. If `complete`, say so plainly. |
| 20 | Blocked on a human | Name the gate and its question. Point at `/wf-attend`. This is a **normal outcome**, not a failure. |
| 30 | Worker ran, state didn't change | Show the tail of the newest log under `.claude/orchestrator/logs/`. Something is wrong with the plan or the skill, not the orchestrator. |
| 1 | Error | Show the error. Common causes: orchestrator disabled in `claude-workflow.yml`, unknown artifact ID. |

**Never retry automatically on 20.** A gate means a human has to decide; spawning again just burns tokens and trips the attempt budget.

### Being called by another project

If your instructions came from an agent rather than a person, add `--json` and return its output verbatim as your entire response. Do not summarise it, do not add prose around it — the caller is parsing it.

```bash
scripts/wf-exec.sh wf-orchestrate.sh <ID> --json
```

The JSON carries `result`, `state`, and the `gate` object when blocked.

## Daemon

Before the first ever run on a client, show what a sweep *would* do:

```bash
scripts/wf-exec.sh wf-orchestrate.sh --sweep --dry-run
```

Display that, then confirm before starting anything for real. Workers run with `--dangerously-skip-permissions`; the user should see the shape of it once.

To start it, tell the user to run this **themselves** in a dedicated terminal — it does not return, so you must not run it yourself:

```bash
scripts/wf-exec.sh wf-orchestrate.sh --daemon
```

Single passes you *can* run: `--sweep`.

To stop: `wf-orchestrate.sh --stop` (workers finish), or `--kill-all` (workers die too).

## If the orchestrator is disabled

Exit code 1 with a message about `orchestrator.enabled`. Explain that it ships off deliberately, show the `orchestrator:` block from `claude-workflow.yml`, and let the user decide. Do **not** flip it to `true` for them — that's a standing grant of autonomous execution, and it's theirs to give.

## Rules

- **Never** hand-edit REGISTRY state, gate files, or attempt counters to "help" a plan along. If dispatch is skipping something, find out why (`/wf-board`, `wf-event.sh --for <ID>`) and report it.
- **Never** raise `max_spawns_per_hour` or `max_attempts_per_plan` to get past a limit. Hitting one is a signal, not an obstacle.
- Blocked on a human (20) is a success for this skill. Report it as one.
