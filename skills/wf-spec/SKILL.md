---
name: wf-spec
description: Convert a decided brief or open bug into a step-by-step implementation plan. Creates immovable plan folders in plans/. Use when the user wants to create or amend an implementation plan.
user_invocable: true
model: haiku
---

# Spec Role

You are in **spec mode**. Your job is to convert decided briefs into precise, step-by-step implementation plans that another Claude session can execute without judgment calls.

## Unattended mode

If `WF_UNATTENDED=1` is set in your environment, you were launched by the orchestrator and **there is no human reading your output**. A question asked here hangs the pipeline.

Rules, in force for the whole session:

1. If your instructions name an artifact (`PLN-NNN`, `BUG-NNN`, `BRF-NNN`), skip the selection menu entirely and work that artifact.
2. Prompts marked **[AUTO]** below resolve to their stated default. Take it and move on.
3. Prompts marked **[GATE]** below must never be guessed. Park the work instead:
   ```bash
   scripts/wf-exec.sh wf-gate-open.sh <ID> <gate-name> "<question>" --context <path> --skill wf-spec
   ```
   Then **exit cleanly** without changing REGISTRY state. The dispatcher skips gated artifacts; `/wf-attend` will bring a human to it.
4. **Never guess.** If you are about to ask something that isn't in the table, treat it as a [GATE] — use gate name `needs-input`.

| Step | Prompt | Mode | Unattended behavior |
|-|-|-|-|
| Entry | Work selection menu | [AUTO] | Use the artifact named in your instructions |
| 1 | Deferred criteria to include | [AUTO] | Include none — do not widen scope unattended |
| 4b | Goal confirmation | [AUTO] | Accept your own draft if it is concrete and specific. If you cannot write a concrete goal from the source artifact, [GATE] `goal-missing` |
| 4c | Tag assignment | [AUTO] | Assign from the allowlist based on slug, goal, and touched paths |
| 7c | Auto-test promotion (y/n) | [AUTO] | **Yes** — promote. Maximizing automation is the standing direction; this overrides "never auto-promote" in step 7c |
| Review gate | Plan approval | **[GATE]** | `spec-approval` — a human decides what gets built. Question: the goal plus step/test counts. Context: the plan.md path |

The review gate is the hard stop. A spec may be written unattended; it may not be **approved** unattended.

## IMMEDIATE STARTUP — run in parallel before reading further

1. Run branch check (do not prompt the user):
   ```bash
   scripts/wf-exec.sh wf-branch-check.sh develop true
   ```

2. Spawn a **haiku subagent** to fetch and format the worklist:

```
Agent(model: haiku, prompt: "Run `scripts/wf-exec.sh wf-list-specable.sh` in the current directory.
Parse the tab-separated output (sections: # replanning, # bugs, # briefs).

Format as TWO markdown tables:

**Table 1 — Available work** (actionable items with sequential numbering):
| # | Priority | Type | ID | Name | Detail |
|-|-|-|-|-|-|
- Replans: the third tab field is priority (show it). Type = Replan.
- Bugs: priority = '—', second field = severity, third = title. Type = Bug.
- Briefs: priority = '—', second field = name, third = description. Type = Brief.
  If a brief's detail says 'Already has plan PLN-NNN', put it in Table 2 instead.

**Table 2 — Already planned** (informational, no numbering):
| Type | ID | Name | Plan |
|-|-|-|-|
Only briefs that already have a plan go here. Omit this table if empty.

After the tables add: Mark a plan urgent: \`u <number>\` (replans only)

If no actionable items, say 'No specable work found.'

Final response: ONLY the formatted tables and footer line. No commentary.")
```

Display the subagent's output verbatim, then tell the user: "Run `/model opus`, then pick a number or describe new work."

**Handling `u <N>` commands:**
If the user types `u <N>` for a replan: run `scripts/wf-exec.sh wf-set-priority.sh <plan-id> urgent`, then re-run the haiku subagent above to re-display the updated menu.
If the user types `u <N>` for an already-urgent replan: run `scripts/wf-exec.sh wf-set-priority.sh <plan-id> —` to clear it, then re-run the subagent.

- If they pick an escalated plan: **claim it** (`scripts/wf-exec.sh wf-claim.sh PLN-NNN-<slug>`), then go to [Replanning](#replanning)
- If they pick a bug: go to [Plan from bug](#plan-from-bug)
- If they pick a brief: go to step 1 below (Read the brief)
- If they describe new work: ask if it should become a brief first (route to `/wf-brainstorm`)

---

## ID Inheritance

Plans inherit their number from the source artifact — no new counter allocation.

- **From brief BRF-041** → plan becomes **PLN-041**
- **From bug BUG-043** → plan becomes **PLN-043**

Extract the number from the source ID:
```bash
# Example: source_id="BRF-041" or "BUG-043"
plan_num="${source_id##*-}"          # "041"
new_id="PLN-${plan_num}"            # "PLN-041"
```

Do **not** call `wf-counter-next.sh` — the number was already allocated when the brief or bug was created.

## Plan from bug

If the user picks a bug BUG-NNN:

1. **Read the bug** — read `bugs/open/BUG-NNN-<slug>/bug.md`
2. **Inherit the plan ID** — BUG-NNN becomes PLN-NNN (same number, see [ID Inheritance](#id-inheritance))
3. **Use it as context** — the bug's description, steps, and expected behavior become the plan's Goal and acceptance criteria
4. **Choose a feature name** — a short kebab-case slug describing the fix (e.g. `login-crash`, `webhook-timeout`)
5. **Construct the plan folder name** — `PLN-NNN-<slug>` (e.g. `PLN-003-login-crash`)
6. **Treat it like a brief** — proceed as normal, but the scope is defined by fixing the bug
7. The bug consumption happens in the [Bug consumption](#bug-consumption) section below

## What you do

1. **Read the input** — if from a brief: read the relevant brief in `plans/briefs/`; if from a bug: the bug's `bug.md` becomes the scope definition
1a. **Check deferred criteria** — if `plans/deferred-criteria.md` exists, read it and scan for entries where `Prereq Plan` matches the current plan ID, or where the criterion text or prerequisite description overlaps with the feature being planned. If any match, show them to the user before writing the plan:
    ```
    Found N deferred criterion/criteria that may apply to this plan:
    | # | Criterion | From |
    |-|-|-|
    | DC-001 | <text> | PLN-009 |
    ```
    Ask: "Include any of these in the acceptance criteria? (Enter numbers, or press enter to skip.)"
    For each included: add it to the plan's Human Test Criteria and remove its row from `deferred-criteria.md`.
2. **Choose a feature name** — a short kebab-case slug describing the work (e.g. `user-auth`, `payment-webhook`, `login-crash`)
3. **Inherit the plan ID** — reuse the source artifact's number (see [ID Inheritance](#id-inheritance)). Do not call `wf-counter-next.sh`.
4. **Explore the codebase** — spawn **haiku agents** to find existing patterns, file structures, and signatures you need to reference in the plan. Keep agents focused: one per question, output under 2000 characters.
4b. **Draft the one-liner goal** — before creating any files, write a single sentence describing what this plan achieves and show it to the user:
    ```
    Goal: <one-line summary>
    Confirm or edit?
    ```
    Do not proceed to step 4c until the user confirms or provides a revised goal. This line will be extracted by scripts (`wf-plan-info.sh`) and displayed in `wf-implement`, `wf-test`, and PR descriptions — it must be concrete, not a placeholder.
4c. **Assign tags** — after the goal is confirmed, prompt the user for category tags:
    ```
    Tags (comma-separated): security, arcade, admin, lessons, ux, infra, e2e, bugfix
    Current: <suggested based on slug/goal>
    Confirm or edit?
    ```
    Suggest tags based on the plan content (e.g., a plan fixing auth → `security`, a plan for arcade games → `arcade`). Multiple tags allowed. Store for use when writing the registry row.
5. **Create the plan folder** — `plans/PLN-NNN-<slug>/` with three files following `templates/plans/TEMPLATE.md`:
   - Folder is always `plans/PLN-NNN-<slug>/` (e.g. `plans/PLN-041-user-auth/`)
   - In `plan.md`, fill in `> **ID:** PLN-NNN` and `> **schema_version:** 5`
   - **Goal** — use the confirmed one-liner from step 4b as the first line under `## Goal`. Follow with an optional context paragraph.
   - `plan.md` — goal, steps, tests, checklist, design decisions, out of scope
   - `findings.md` — empty (no table header needed — findings are appended as flat checklists)
   - `progress.md` — step list (copied from plan steps), empty log
6. **Specify everything** — every step must include:
   - Exact file paths to create or modify
   - Class/method/component names and signatures
   - Acceptance criteria (test command, observable behavior)
7. **Define tests** — fill in the Tests table with specific test IDs, types, descriptions, and commands. **Maximize automation:** API responses, data correctness, markup structure, auth gates, redirects, and status codes are all automatable (unit tests, integration tests, curl commands, scripts). Only use `Manual` type for things that genuinely require human eyes — visual rendering, subjective UX, complex multi-step physical interactions.

   **Default-automated patterns** — past plans have repeatedly shipped these classes of criteria as automated tests (see `plans/auto-test-log.md` Realized section for proofs). If a criterion you're drafting fits one of these shapes, put it in the Tests table (not Human Test Criteria) from the start:

   | Pattern | Example criterion | Test shape |
   |-|-|-|
   | Cookie attributes on a response | "PwdResetHandoff cookie is HttpOnly, Secure, SameSite=Lax, ~15m expiry" | Unit test asserting `Set-Cookie` header flags |
   | HTML meta tag presence/absence | "No Referer meta tag on /account/reset-password" | Response inspection / static HTML assertion |
   | "No console errors" / "no X log entries" | "No Authorization failed entries on /apps/lessons load" | Auth layout absence test, or log capture assertion |
   | Form validation → specific status code | "POST invalid LessonLength returns 400" | Integration test on the endpoint |
   | Route redirect by auth state | "Unauthenticated /apps/lessons → /login" | Integration test asserting 302 + Location |
   | Dialog open / close / field presence | "Clicking CREATE USER opens dialog with Roles field visible" | E2E / component test |
   | Admin table filter / pagination / layout | "Filter by GameType shows only matching rows" | Service test + DOM/E2E assertion |
   | Element presence on direct URL vs client nav | "Footer shows build date on direct load AND after client-side nav" | Two E2E tests, one per entry mode |

   Only escape to Human Test Criteria when the check genuinely requires human judgment (subjective animation feel, visual polish, cross-device ergonomics).
7a. **Fill `## E2E Scope`** — list the e2e test file paths or glob patterns that cover this plan's changes (one per line, no backticks). If the project has a single flat e2e directory and there are no dedicated per-feature files yet, leave the section blank — wf-test will fall back to the full suite. Only populate this if you can identify specific test files that exercise the affected routes or behaviors.
7b. **Fill `## Test Scope`** — list category names (one per bullet) the planner knows are relevant. Leave blank only if the change truly affects nothing testable (e.g., doc-only). Prefer declaring generously; auto-detect unions in more categories at verify time. Valid category names live in `claude-workflow.yml → testScopes`.
7c. **Consult the auto-test log** — if `plans/auto-test-log.md` exists, read its `### Realized` section. Those rows prove what shape of criterion past plans successfully converted to automated tests at `/wf-test` time. **Before citing a row, verify the referenced test file still exists** (`test -f <File column>`) — rolled-back plans may leave stale rows. For each criterion you're drafting, ask: *does any live Realized row describe a similar intent* (e.g., "redirects after valid login", "button disables while submitting", "validation error shows on empty field")? If yes, flag it to the user before proceeding to step 8:
    ```
    Automation opportunity: criterion "<text>" resembles past realized auto-tests:
      - PLN-NNN "<prior criterion>" → <test name> (<file>)
    Consider classifying this as automated (Tests table + Build & Tests checklist)
    instead of Human Test Criteria. Promote? (y/n)
    ```
    If yes, add the test to the Tests table (step 7) and skip adding it under Human Test Criteria. If no, proceed normally. **Never auto-promote — always ask** (except under `WF_UNATTENDED=1`, where this is an [AUTO] yes — see [Unattended mode](#unattended-mode)). If the log doesn't exist or has no relevant matches, skip this step silently.
8. **Fill verification checklist** — the verify agent needs to know exactly what to check. For `### Human Test Criteria`, split into two subsections:
   - `#### Chrome-Assisted` — objectively verifiable behavior (navigations, clicks, form submissions, error states, persistence). Each criterion starts with a route: `- [ ] /login — redirects to /dashboard after valid credentials`
   - `#### Manual` — subjective or visual checks that need human eyes (layout, animation, UX feel). Each criterion starts with a route: `- [ ] /play — animation feels smooth and natural`
   Only use `#### Manual` for things that genuinely require human judgment. If Chrome can navigate and check the result, it's Chrome-Assisted.
9. **Make all design decisions** — the implementer should not need to make judgment calls
10. **Write the rollback plan** — fill in `## Rollback` in `plan.md`:
    - List specific trigger conditions (don't leave as TBD)
    - Assess data migration reversibility honestly — if irreversible, say so explicitly
    - Write exact rollback commands, not general descriptions
    - Add verification steps to confirm the rollback succeeded
11. **Update the brief (if from brief)** — set status to `Planned`, add the plan folder link; update `plans/briefs/INDEX.md`
12. **Consume the bug (if from bug)** — see [Bug consumption](#bug-consumption) below

## Codebase exploration via agents

When you need to understand existing code, spawn haiku agents rather than reading everything yourself:

```
Agent(model: haiku, prompt: "Find all [component type] in [directory]. 
List each file, its purpose, and public interface. 
Final response under 1000 characters.")
```

Good agent tasks:
- "List all files in [directory] with their purpose"
- "Find where [class/interface] is defined and list its public members"
- "What patterns are used in [file]?"

Bad agent tasks (do these yourself):
- Design decisions
- Writing plan steps
- Anything requiring the full brief context

---

## Exit (complex) — Review Gate

**[GATE] under `WF_UNATTENDED=1`.** Commit the drafted plan (state stays `draft`), then park and exit:

```bash
git add plans/PLN-NNN-<slug>/ && git commit -m "spec(PLN-NNN-<slug>): draft plan — awaiting approval"
scripts/wf-exec.sh wf-gate-open.sh PLN-NNN spec-approval \
  "<goal> — N steps, N automated tests, N manual criteria. Approve?" \
  --context plans/PLN-NNN-<slug>/plan.md --skill wf-spec
```

Do **not** run the review agent, do **not** write the registry row's state as `ready`, and do **not** proceed past this point. `/wf-attend` runs the review with a human present.

When the user approves the plan (says "looks good", "approved", "ready", etc.):

1. **Goal gate** — verify that the first line under `## Goal` in `plan.md` is a concrete one-line summary (not empty, not template placeholder text). If missing or placeholder, ask the user for a one-line goal, write it as the first line under `## Goal` (before any paragraph), and stage the file.

2. **Spawn a sonnet agent** to run the architectural and security review:

```
Agent(model: sonnet, prompt: "You are a code reviewer. Read plans/PLN-NNN-[name]/plan.md 
and evaluate against: architecture (project patterns, dependency direction), 
security (auth on endpoints, input sanitization, no hardcoded secrets), 
performance (no unbounded queries, N+1 patterns), 
maintainability (scope matches goal, test coverage),
rollback (trigger conditions defined, safety assessment complete, steps are specific commands not descriptions, irreversible migrations called out explicitly).

Write your findings in this format:
Result: Approved | Approved with notes | Blocked
Then a table: | # | Severity | Category | Finding | Recommendation |
Severity: Critical (blocks), Warning (should fix), Note (informational).
Final response under 2000 characters.")
```

3. **Process the review result:**
   - **Critical findings:** do NOT move to `ready`. Present findings to the user, revise the plan, and re-review.
   - **Warnings only:** present to the user for acknowledgement.
   - **Clean or Notes only:** proceed to state transition.
4. **Write the review result** to `plan.md`'s `## Review` section

5. **State transition — update REGISTRY.md:**
   ```bash
   scripts/wf-exec.sh wf-registry-update.sh PLN-NNN draft ready
   ```

6. **Release claim and commit:**
   ```bash
   scripts/wf-exec.sh wf-unclaim.sh PLN-NNN-<slug>
   git add plans/PLN-NNN-<slug>/ plans/briefs/ bugs/
   # If any deferred criteria were consumed (rows removed from deferred-criteria.md):
   git add plans/deferred-criteria.md
   git commit -m "spec: PLN-NNN-<slug> — plan ready"
   ```
   Then run `scripts/wf-exec.sh wf-check-reboot-flag.sh` and append any output after your completion message.

For new plans, also add the REGISTRY.md row in the same commit. Stamp the WF column with the current workflow version so the dispatcher routes this plan to the matching script snapshot (see `scripts/version-map.txt`):
```bash
WF=$(cat .claude/workflow-version 2>/dev/null | tr -d '[:space:]')
```
Then append (replacing WF with the stamped value):
```
| PLN-NNN | <slug> | draft | — | — | YYYY-MM-DD | $WF | <tags> | — |
```
Columns: `ID | Slug | State | Priority | Branch | Updated | WF | Tags | Deps`. Use the tags confirmed in step 4c. Deps defaults to `—`. Then after review passes, update state to `ready`.

---

## Replanning

When a plan in REGISTRY.md has state `draft` AND has unchecked items in its `findings.md`, it's a plan returned from verify or test that needs review. Findings come in two categories:

- **ESCALATED** (design) — require plan amendments and design decisions
- **Behavior** (code fix) — bugs found during human testing, routed here for Opus review before sending to builder

1. **Read `plan.md` and `findings.md`** from `plans/PLN-NNN-<slug>/` — understand the full plan and all findings
1b. **Push a sub-goal** — summarize the pending findings as the active goal. If any finding is a show-stopper (critical/ESCALATED), make it the focus of the goal. Run:
    ```bash
    scripts/wf-exec.sh wf-goal-push.sh PLN-NNN "<findings summary goal>" "<trigger description>"
    ```
    Example goal: "Fix show-stopper: auth bypass on /api/settings (+ 2 behavior findings)"
    Example trigger: "Verify: 3 findings (1 ESCALATED)"
2. **Triage findings:**
   - **ESCALATED findings** — present to the user and discuss how to resolve. Write amendments as needed.
   - **Behavior findings** — review each finding. Add implementation guidance to `findings.md` (append a line under the finding with context, root cause hints, or file pointers). If a behavior finding reveals a spec gap, write an amendment.
3. **Write an Amendment** (if needed) — append to `plan.md`'s **Amendments** section. Never rewrite Steps, Tests, or Design Decisions already there.
4. **Update Design Decisions** — add any new decisions to `plan.md`
5. **Address findings** — for each `ESCALATED` item in `findings.md`, check it off if resolved by the amendment. Leave behavior findings unchecked (T3 will handle them).
6. **Run the review gate** — same as above
6b. **Pop the sub-goal** — restore the original goal now that findings are addressed:
    ```bash
    scripts/wf-exec.sh wf-goal-pop.sh PLN-NNN
    ```
7. **Update REGISTRY.md:**
   ```bash
   scripts/wf-exec.sh wf-registry-update.sh PLN-NNN draft ready
   ```
8. **Commit:**
   ```
   git add plans/PLN-NNN-<slug>/
   # If any deferred criteria were consumed:
   git add plans/deferred-criteria.md
   git commit -m "spec: PLN-NNN-<slug> — amendment, back to ready"
   ```

## Bug consumption

When the plan being created is a fix for a tracked bug:

1. **Consume the bug:**
   ```bash
   scripts/wf-exec.sh wf-bug-consume.sh BUG-NNN PLN-NNN-<slug>
   ```
   This updates bug.md (Status→Triaged, Plan→linked) and moves open→triaged.
2. **Link back in `plan.md`** — add to the Goal section: `> **Bug:** BUG-NNN — <title>`

## Rules

- **Do NOT** edit source code files (src/,tests/)
- **Do NOT** leave ambiguous steps — if you're unsure, spawn a haiku agent to investigate
- If a plan is already in `active` or beyond, only append to **Amendments**
- Plans become static decision records — they document what was decided and why

## When the workflow misbehaves

If the harness does something its own documentation does not describe — a `wf-*` script erroring unexpectedly, an instruction here referencing something that does not exist, the registry contradicting the worktree — record it, then carry on:

```bash
scripts/wf-exec.sh wf-issue.sh --source wf-spec \
  --expected "<what should have happened>" \
  --actual   "<what happened, verbatim>" \
  --context  "<plan id, branch, state>"
```

These are swept into the claude-workflow library and fixed upstream, so one report fixes it for every project. **Not** for application build/test failures or plan findings — those are normal work, not harness faults. Filing never justifies abandoning the run; work around it if you can and say so in `--notes`.

