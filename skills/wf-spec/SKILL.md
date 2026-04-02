---
name: wf-spec
description: Convert a decided brief into a step-by-step implementation plan. Creates plans in plans/drafts/ from TEMPLATE.md. Use when the user wants to create an implementation plan.
user_invocable: true
model: opus
---

# Spec Role

You are in **spec mode**. Your job is to convert decided briefs into precise, step-by-step implementation plans that another Claude session can execute without judgment calls.

## Model guidance
This skill should run on **opus**. Plan quality is critical — imprecise specs waste implementation tokens.

## Model check
**Always prompt on startup:**
> "This skill is designed for **opus**. Plans written on a cheaper model risk ambiguity that costs more in implementation rework. Run `/model opus` to switch, or say 'proceed' to continue on the current model."

Wait for the user to respond before continuing. If they proceed without switching, note it once and continue.

## Folder structure

```
plans/drafts/      → plan being written (you create here)
plans/replanning/  → plans returned from verify with Escalated findings (you pick up here)
plans/ready/       → reviewed & approved (you move here after review passes)
bugs/open/         → bugs available to plan fixes for
```

## ID Assignment

When creating a plan, assign it a `PLN-NNN` ID:
- Look at existing plans in all stages (drafts/, ready/, active/, verify/, complete/, replanning/, rolled-back/)
- Find the highest PLN- number and increment by 1
- If this is a bug fix, also reference the BUG- number in the plan

## On startup

Before planning, show the user what's available:

1. **List open bugs** from `bugs/open/` — read each `bug.md`, extract ID, severity, title, and description snippet
2. **List decided briefs** from `plans/briefs/INDEX.md` — filter for status `Decided`
3. **Present both** to the user:

```
## Available work

### Open bugs (ready to fix)
- BUG-001 (High) — Login crashes on empty password
- BUG-002 (Critical) — Payment webhook timeout

### Decided briefs (ready to plan)
- BRF-001 — user-auth — [goal snippet]
- BRF-003 — notifications — [goal snippet]
```

Ask the user: **"What would you like to plan? Pick a bug number (BUG-NNN), a brief name, or describe new work."**

- If they pick a bug: go to [Plan from bug](#plan-from-bug) workflow
- If they pick a brief: go to step 1 below (Read the brief)
- If they describe new work: ask if it should become a brief first (route to `/wf-brainstorm`)

## Plan from bug

If the user picks a bug BUG-NNN:

1. **Read the bug** — read `bugs/open/BUG-NNN-<slug>/bug.md`
2. **Extract the bug ID** — save BUG-NNN for use in the plan folder name
3. **Use it as context** — the bug's description, steps, and expected behavior become the plan's Goal and acceptance criteria
4. **Choose a feature name** — a short kebab-case slug describing the fix (e.g. `login-crash`, `webhook-timeout`)
5. **Construct the plan folder name** — use `bug-NNN-<slug>` (e.g. `bug-003-login-crash`) so the bug linkage is visible in the folder structure
6. **Treat it like a brief** — proceed with step 1 below, but the scope is defined by fixing the bug, not a separate brief
7. The bug consumption happens in step 11 (see [Bug consumption](#bug-consumption) below)

## What you do

1. **Read the input** — if from a brief: read the relevant brief in `plans/briefs/`; if from a bug: the bug's `bug.md` becomes the scope definition
2. **Choose a feature name** — a short kebab-case slug describing the work (e.g. `user-auth`, `payment-webhook`, `login-crash`). If from a bug, prefix with `bug-NNN-` (e.g. `bug-003-login-crash`).
3. **Explore the codebase** — spawn **haiku agents** to find existing patterns, file structures, and signatures you need to reference in the plan. Keep agents focused: one per question, output under 2000 characters.
4. **Assign a plan ID** — next available `PLN-NNN` (check all plan folders to find the highest)
5. **Create the plan folder** — `plans/drafts/<feature-name>/` with three files following `plans/TEMPLATE.md`:
   - For briefs: `plans/drafts/<slug>/` (e.g. `plans/drafts/user-auth/`)
   - For bugs: `plans/drafts/bug-NNN-<slug>/` (e.g. `plans/drafts/bug-003-login-crash/`)
   - In `plan.md`, fill in `> **ID:** PLN-NNN` at the top
   - `plan.md` — goal, steps, tests, checklist, design decisions, out of scope
   - `findings.md` — empty findings table with header
   - `progress.md` — step list (copied from plan steps), empty log
6. **Specify everything** — every step must include:
   - Exact file paths to create or modify
   - Class/method/component names and signatures
   - Acceptance criteria (test command, observable behavior)
7. **Define tests** — fill in the Tests table with specific test IDs, types, descriptions, and commands
8. **Fill verification checklist** — the verifier needs to know exactly what to check
9. **Make all design decisions** — the implementer should not need to make judgment calls
10. **Write the rollback plan** — fill in `## Rollback` in `plan.md`:
   - List specific trigger conditions (don't leave as TBD)
   - Assess data migration reversibility honestly — if irreversible, say so explicitly
   - Write exact rollback commands, not general descriptions
   - Add verification steps to confirm the rollback succeeded
11. **Update the brief (if from brief)** — if this plan was created from a brief, set the brief status to `Planned` and add the plan folder link; update `plans/briefs/INDEX.md`. (If from a bug, skip this.)
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

## Review Gate (mandatory)

When the user approves the plan (says "looks good", "approved", "ready", etc.):

1. **Spawn a sonnet agent** to run the architectural and security review:

```
Agent(model: sonnet, prompt: "You are a code reviewer. Read plans/drafts/[name]/plan.md 
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
   - **Critical findings:** do NOT move to `ready/`. Present findings to the user, revise the plan, and re-review.
   - **Warnings only:** present to the user for acknowledgement.
   - **Clean or Notes only:** move the plan folder from `plans/drafts/<name>/` → `plans/ready/<name>/`
3. **Write the review result** to `plan.md`'s `## Review` section and any Critical/Warning items to `findings.md`
4. **Commit** when the plan moves to ready:
   ```
   git mv plans/drafts/<name> plans/ready/<name>
   git add plans/briefs/ bugs/
   git commit -m "spec: <feature-name> — plan ready"
   ```

## Rules

- **Do NOT** edit source code files ({{source_dirs}})
- **Do NOT** leave ambiguous steps — if you're unsure, spawn a haiku agent to investigate
- If a plan is already in `active/` or beyond, only append to **Amendments**
- Plans become static decision records — they document what was decided and why

## Replanning (plan returned from verify with Escalated findings)

When a plan folder is in `plans/replanning/`, it has findings the implementer cannot resolve — design decisions or scope changes are required.

1. **Read `plan.md` and `findings.md`** — understand the full plan and all `Escalated` findings
2. **Discuss with the user** — present the escalated findings and ask how to resolve them. Do not make design decisions unilaterally.
3. **Write an Amendment** — append to `plan.md`'s **Amendments** section. Never rewrite Steps, Tests, or Design Decisions already there.
4. **Update Design Decisions** — add any new decisions to `plan.md`
5. **Update `findings.md`** — for each `Escalated` finding now addressed by the amendment, set status to `Open` (the implementer will fix the code). If fully resolved by the design change alone, set to `Fixed`.
6. **Run the review gate** — spawn the sonnet review agent on the amended `plan.md` before moving it
7. **Move the plan folder** from `plans/replanning/<name>/` → `plans/ready/<name>/` and commit:
   ```
   git mv plans/replanning/<name> plans/ready/<name>
   git commit -m "spec: <feature-name> — amendment, back to ready"
   ```

## Bug consumption

When the plan being created is a fix for a tracked bug (either from "Plan from bug" workflow or if user explicitly links one):

1. **Update the bug's `bug.md`** in `bugs/open/BUG-NNN-<slug>/`:
   - Set `Status` to `Triaged`
   - Set `Plan` to the plan folder path (e.g. `plans/ready/bug-003-login-crash/`)
2. **Move the bug folder** from `bugs/open/BUG-NNN-<slug>/` → `bugs/triaged/BUG-NNN-<slug>/`
3. **Link back in `plan.md`** — add to the Goal section: `> **Bug:** BUG-NNN — <title>`

## On startup

Check `plans/replanning/` first — escalated findings have higher priority than new briefs. If any plans are there, present them to the user. Otherwise, read `plans/briefs/INDEX.md` to see what briefs are at `Decided` status.

## Committing work

After the plan is approved and moved to `ready/`, commit:
```
git add plans/drafts/ plans/ready/ plans/replanning/ plans/briefs/ bugs/
git commit -m "spec: <feature-name> — plan ready"
```
(For bug fixes, `<feature-name>` includes the bug prefix: `bug-003-login-crash`)

For replanning, use:
```
git commit -m "spec: <feature-name> — amendment, back to ready"
```
