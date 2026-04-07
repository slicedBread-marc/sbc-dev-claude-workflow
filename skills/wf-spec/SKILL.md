---
name: wf-spec
description: Convert a decided brief or open bug into a step-by-step implementation plan. Creates immovable plan folders in plans/. Use when the user wants to create or amend an implementation plan.
user_invocable: true
model: opus
---

# Spec Role

You are in **spec mode**. Your job is to convert decided briefs into precise, step-by-step implementation plans that another Claude session can execute without judgment calls.

## Model guidance
This skill should run on **opus**. Plan quality is critical — imprecise specs waste implementation tokens.

## Model check
**On startup, only if NOT on opus:**
> "This skill is designed for **opus**. Plans written on a cheaper model risk ambiguity that costs more in implementation rework. Run `/model opus` to switch, or say 'proceed' to continue on the current model."

Wait for the user to respond before continuing. If they proceed without switching, note it once and continue.

If already on opus, skip the prompt and continue directly.

## Branch check

```bash
scripts/wf-branch-check.sh develop true
```
Switches to develop automatically if needed. Do not prompt the user.

---

## Entry (simple)

Run `scripts/wf-list-specable.sh` to find all available work. Output is grouped by section headers (`# replanning`, `# bugs`, `# briefs`) with tab-separated entries.

Present the results from the script output:

```
## Available work

### Escalated plans (highest priority)
- PLN-NNN — <slug> (N escalated findings)

### Open bugs (ready to fix)
- BUG-001 (High) — Login crashes on empty password

### Decided briefs (ready to plan)
- BRF-001 — user-auth — [goal snippet]
```

Ask the user: **"What would you like to plan? Pick a plan to amend, a bug number, a brief name, or describe new work."**

- If they pick an escalated plan: go to [Replanning](#replanning)
- If they pick a bug: go to [Plan from bug](#plan-from-bug)
- If they pick a brief: go to step 1 below (Read the brief)
- If they describe new work: ask if it should become a brief first (route to `/wf-brainstorm`)

---

## ID Assignment

```bash
new_id=$(scripts/wf-counter-next.sh PLN)
```
This reads the counter, prints the prefixed ID (e.g., `PLN-021`), and increments the counter in REGISTRY.md.

## Plan from bug

If the user picks a bug BUG-NNN:

1. **Read the bug** — read `bugs/open/BUG-NNN-<slug>/bug.md`
2. **Extract the bug ID** — save BUG-NNN for use in the plan folder name
3. **Use it as context** — the bug's description, steps, and expected behavior become the plan's Goal and acceptance criteria
4. **Choose a feature name** — a short kebab-case slug describing the fix (e.g. `login-crash`, `webhook-timeout`)
5. **Assign a plan ID** — next available `PLN-NNN` from REGISTRY.md counter
6. **Construct the plan folder name** — use `PLN-NNN-bug-BUG-NNN-<slug>` (e.g. `PLN-003-bug-BUG-003-login-crash`)
7. **Treat it like a brief** — proceed as normal, but the scope is defined by fixing the bug
8. The bug consumption happens in the [Bug consumption](#bug-consumption) section below

## What you do

1. **Read the input** — if from a brief: read the relevant brief in `plans/briefs/`; if from a bug: the bug's `bug.md` becomes the scope definition
2. **Choose a feature name** — a short kebab-case slug describing the work (e.g. `user-auth`, `payment-webhook`, `login-crash`)
3. **Assign a plan ID** — next available `PLN-NNN` from REGISTRY.md counter
4. **Explore the codebase** — spawn **haiku agents** to find existing patterns, file structures, and signatures you need to reference in the plan. Keep agents focused: one per question, output under 2000 characters.
5. **Create the plan folder** — `plans/PLN-NNN-<slug>/` with three files following `templates/plans/TEMPLATE.md`:
   - For briefs: `plans/PLN-NNN-<slug>/` (e.g. `plans/PLN-001-user-auth/`)
   - For bugs: `plans/PLN-NNN-bug-BUG-NNN-<slug>/` (e.g. `plans/PLN-003-bug-003-login-crash/`)
   - In `plan.md`, fill in `> **ID:** PLN-NNN` and `> **schema_version:** 4`
   - `plan.md` — goal, steps, tests, checklist, design decisions, out of scope
   - `findings.md` — empty (no table header needed — findings are appended as flat checklists)
   - `progress.md` — step list (copied from plan steps), empty log
6. **Specify everything** — every step must include:
   - Exact file paths to create or modify
   - Class/method/component names and signatures
   - Acceptance criteria (test command, observable behavior)
7. **Define tests** — fill in the Tests table with specific test IDs, types, descriptions, and commands
8. **Fill verification checklist** — the verify agent needs to know exactly what to check
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

When the user approves the plan (says "looks good", "approved", "ready", etc.):

1. **Spawn a sonnet agent** to run the architectural and security review:

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

2. **Process the review result:**
   - **Critical findings:** do NOT move to `ready`. Present findings to the user, revise the plan, and re-review.
   - **Warnings only:** present to the user for acknowledgement.
   - **Clean or Notes only:** proceed to state transition.
3. **Write the review result** to `plan.md`'s `## Review` section

4. **State transition — update REGISTRY.md:**
   ```bash
   scripts/wf-registry-update.sh PLN-NNN draft ready
   ```

5. **Commit:**
   ```
   git add plans/PLN-NNN-<slug>/ plans/REGISTRY.md plans/briefs/ bugs/
   git commit -m "spec: PLN-NNN-<slug> — plan ready"
   ```

For new plans, also add the REGISTRY.md row in the same commit:
```
| PLN-NNN | <slug> | draft | — | YYYY-MM-DD |
```
Then after review passes, update to `ready`.

---

## Replanning

When a plan in REGISTRY.md has state `draft` AND has `ESCALATED` items in its `findings.md`, it's a plan returned from verify or test that needs design amendments.

1. **Read `plan.md` and `findings.md`** from `plans/PLN-NNN-<slug>/` — understand the full plan and all `ESCALATED` findings
2. **Discuss with the user** — present the escalated findings and ask how to resolve them. Do not make design decisions unilaterally.
3. **Write an Amendment** — append to `plan.md`'s **Amendments** section. Never rewrite Steps, Tests, or Design Decisions already there.
4. **Update Design Decisions** — add any new decisions to `plan.md`
5. **Address findings** — for each `ESCALATED` item in `findings.md`, check it off if resolved by the amendment. If the fix requires code changes, leave it unchecked (T3 will handle it).
6. **Run the review gate** — same as above
7. **Update REGISTRY.md:**
   ```bash
   scripts/wf-registry-update.sh PLN-NNN draft ready
   ```
8. **Commit:**
   ```
   git add plans/PLN-NNN-<slug>/ plans/REGISTRY.md
   git commit -m "spec: PLN-NNN-<slug> — amendment, back to ready"
   ```

## Bug consumption

When the plan being created is a fix for a tracked bug:

1. **Consume the bug:**
   ```bash
   scripts/wf-bug-consume.sh BUG-NNN PLN-NNN-<slug>
   ```
   This updates bug.md (Status→Triaged, Plan→linked) and moves open→triaged.
2. **Link back in `plan.md`** — add to the Goal section: `> **Bug:** BUG-NNN — <title>`

## Rules

- **Do NOT** edit source code files (src/,tests/)
- **Do NOT** leave ambiguous steps — if you're unsure, spawn a haiku agent to investigate
- If a plan is already in `active` or beyond, only append to **Amendments**
- Plans become static decision records — they document what was decided and why
