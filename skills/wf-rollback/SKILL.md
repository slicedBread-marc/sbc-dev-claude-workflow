---
name: wf-rollback
description: Execute a rollback for a completed or active plan. Reads the plan's rollback section, walks through steps interactively, moves the plan to rolled-back/, and optionally files a bug. Use when a deployed feature needs to be reverted.
user_invocable: true
model: sonnet
---

# Rollback Role

You are in **rollback mode**. A feature needs to be reverted. Your job is to guide the user through the rollback steps defined in the plan, confirm each step, and record the outcome.

## Model guidance
This skill should run on **sonnet**. Rollback requires careful reasoning — do not use haiku.

## Model check
**On startup, only if NOT on sonnet:**
> "This skill is designed for **sonnet**. Run `/model sonnet` to switch for lower cost, or say 'proceed' to continue on the current model."
Wait for the user to respond before continuing. If they proceed without switching, note it once and continue.

If already on sonnet, skip the prompt and continue directly.

## Folder structure

```
plans/complete/      → most rollbacks originate here (plan was deployed)
plans/active/        → rollback may also be needed for an in-progress plan
plans/rolled-back/   → where plan folders go after rollback
```

## What you do

### 1. Identify the plan

Ask the user which feature to roll back. List candidates from `plans/complete/PLN-NNN-*/` and `plans/active/PLN-NNN-*/`. Read each `plan.md` Status and Goal to help the user identify the right one.

### 2. Read the rollback section

Read `## Rollback` from `plan.md`. Present the following to the user before proceeding:

```
Feature:    [plan name]
Status:     [plan status]

--- Rollback Assessment ---
Trigger conditions:   [list]
Data migrations:      Reversible | Irreversible | N/A
Breaking changes:     Yes / No
Downstream impact:    [description]

--- Steps ---
1. [step]
2. [step]
...
```

**If data migrations are Irreversible:** stop and warn the user explicitly before proceeding:
> "⚠️ This plan has irreversible data migrations. Rolling back the code will NOT revert the data. Confirm you understand and want to proceed."

Wait for explicit confirmation before continuing.

### 3. Execute steps interactively

Walk through each rollback step one at a time:
- Present the step
- Ask the user to execute it (you cannot run deployment commands or push to remotes directly)
- Wait for confirmation that it's done before moving to the next step
- If a step fails or the user encounters an issue, stop and help diagnose before continuing

### 4. Verify the rollback

Once all steps are complete, work through the rollback verification checklist from `plan.md`:
- For each verification check, ask the user to confirm or observe the result
- If any check fails, note it and ask how the user wants to proceed

### 5. Record the rollback

Update `plan.md`:
- Set `Status` to `Rolled Back`
- Append to `## Amendments`:
  ```
  [date] — Rolled back. Reason: [user-provided reason]. Data migrations: [Reversible/Irreversible/N/A]. Verification: [passed/partial — notes].
  ```

Move the plan folder from its current location → `plans/rolled-back/PLN-NNN-<name>/` and commit:
```
git mv plans/complete/PLN-NNN-<name> plans/rolled-back/PLN-NNN-<name>
git commit -m "rollback(PLN-NNN-<name>): <reason>"
```

(If rolling back from `plans/active/`, use `git mv plans/active/PLN-NNN-<name> plans/rolled-back/PLN-NNN-<name>`)

### 6. File a bug (optional)

Ask the user:
> "Do you want to file a bug for the issue that triggered this rollback?"

If yes, guide them through the `/wf-bug` filing process with the rollback context pre-filled:
- Title: "Rollback: [feature name] — [brief reason]"
- Severity: based on user input
- Description: what went wrong that triggered the rollback
- Notes: link to the rolled-back plan folder

### 7. Recommend next action

After the rollback is recorded:
- If a bug was filed: "Run `/wf-spec` when ready to plan a fix — link it to [BUG-NNN]"
- If no bug was filed: "Run `/wf-status` to see the current pipeline state"

## Rules

- **Do NOT** execute deployment commands, git pushes, or database migrations yourself — guide the user to run them
- **Do NOT** skip the safety assessment for irreversible migrations — always surface this explicitly
- **Do NOT** move the plan folder until all steps are confirmed complete and verification is done
- Steps must be walked through in order — do not skip ahead
- If the user aborts mid-rollback, note the partial state in `plan.md` Amendments before exiting

## Partial rollback

If the user stops partway through:
1. Note which steps were completed in `plan.md` Amendments: `[date] — Partial rollback. Completed steps 1-N. Stopped at step N+1 due to: [reason].`
2. Leave the plan folder in its current location (do NOT move to `rolled-back/`)
3. Set Status to `Rollback Partial`
4. Commit the partial state:
   ```
   git add plans/
   git commit -m "rollback: <feature-name> — partial, stopped at step N"
   ```
   (The plan folder stays in its current location; do NOT use `git mv`)
5. Recommend filing a bug and getting help before continuing

## Rolling back

When a plan is rolled back:
1. Assign it a `RBK-NNN` ID (next available in `plans/rolled-back/`)
2. Optionally record the rollback in the plan's Amendments with a note like:
   ```
   [date] — Rolled back as RBK-001. Reason: [reason]. Verified: [passed/partial — notes].
   ```

## Committing work

The commit is done immediately after `git mv` during step 5 (Record the rollback). Use `git mv` to track the plan folder move explicitly.
