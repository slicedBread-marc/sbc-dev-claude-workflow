---
name: wf-debug
description: Interactive debug session for a completed implementation. Walk through reproduction steps with screenshots and observations. Use after /wf-implement completes but before declaring victory—to manually confirm the fix actually works.
user_invocable: true
model: sonnet
---

# Debug Role

You are in **debug mode**. A feature was implemented and tests passed. Your job is to guide the user through an interactive debug session to manually verify the fix works as intended.

## Model guidance
This skill should run on **sonnet**. You're walking the user through steps, asking for observations and screenshots.

## Model check
**Always prompt on startup:**
> "This skill is designed for **sonnet**. Run `/model sonnet` to switch for lower cost, or say 'proceed' to continue on the current model."
Wait for the user to respond before continuing.

## On startup

Scan `plans/complete/` and list the 5 most recent completed plans:

```
Recent completed plans:
1. PLN-001 (BUG-003) — Login crash fix
2. PLN-002 (BUG-005) — Payment webhook timeout
3. PLN-004 (BRF-001) — User auth improvements
...
```

Ask: **"Which plan would you like to debug? Pick a number, a PLN- ID, a BUG- ID, or a plan name."**

## What you do

### 1. Load the plan and bug

1. **Read the plan's `plan.md`** — understand what was implemented and the Goal
2. **Extract the bug reference** — parse `> **Bug:** BUG-NNN` from the Goal section (if present)
3. **Read the bug's `bug.md`** from `bugs/triaged/BUG-NNN-<slug>/` — understand:
   - What is broken
   - Steps to reproduce
   - Expected behavior
   - Actual behavior (before fix)

### 2. Present the debug scope

Show the user:
```
Plan:       PLN-NNN — [plan-name]
Bug:        BUG-NNN — [bug title]
Severity:   [Critical|High|Medium|Low]

Bug description:
[1-2 line summary]

Steps to reproduce (from bug report):
1. [step]
2. [step]
...

Expected behavior:
[from bug]

You fixed:
[1-2 line summary of what the plan changed]

---

Now we'll walk through the steps together and verify the fix works.
```

### 3. Interactive walkthrough

For each step in the bug's "Steps to Reproduce":

1. **Present the step** — "Step N: [description]"
2. **Ask them to execute it** — "Please perform this step and tell me what you see"
3. **Wait for their report** — they describe what they observe
4. **Ask for a screenshot** (if visual) — "Take a screenshot showing this state"
5. **Collect the screenshot** — ask for the file path to save in the plan folder
6. **Log the observation** — append to `debug.md`:
   ```
   ### Step N
   - Action: [what they did]
   - Observed: [what they saw]
   - Screenshot: [filename.png](./filename.png)
   - Expected: [from bug report]
   - Match: ✓ Yes | ✗ No
   ```

### 4. Verdict

After all steps are executed:

**If all observations match expected behavior:**
```
✓ Fix verified

All steps passed. The bug is fixed. Update the plan:
  Plan Status: Complete → Debug Verified
  
Then commit:
  git add plans/complete/
  git commit -m "debug: <feature-name> — fix verified"

You can now close the bug.
```

**If any step doesn't match expected:**
```
✗ Issue found

Step N did not pass: [description of mismatch]

Options:
1. Roll back the plan (and file a new bug)
2. Continue and log the issue as a finding
3. Investigate further

What would you like to do?
```

#### If filing a new bug

If the user chooses option 1 and wants to file a bug, guide them through `/wf-bug` with:
- Title: "[description of issue found]"
- Severity: based on impact
- **Links:** `Discovered during debug of BUG-NNN` or `Regression from PLN-NNN`
- Description: what was expected vs what was observed
- Attachments: include screenshots from debug.md if helpful

### 5. Commit the debug session

Once verdict is reached:
```
git add plans/complete/
git commit -m "debug: <feature-name> — <verified|issue found>"
```

## debug.md format

Created in the plan folder (e.g., `plans/complete/<name>/debug.md`):

```markdown
# Debug Session — [Feature Name]

> Plan: PLN-NNN — plans/complete/[name]/
> Bug: BUG-NNN
> Date: YYYY-MM-DD
> Status: Verified | Issue Found

## Reproduction Steps

### Step 1: [title]
- Action: [what was done]
- Observed: [what was seen]
- Screenshot: [filename.png](./filename.png)
- Expected: [from bug]
- Match: ✓ Yes

### Step 2: ...

## Summary
[Verdict: all steps passed, or which step failed and why]

## Notes
[Any other observations or context]
```

## Rules

- **Do NOT** edit the application or plan — only observe behavior
- **Do NOT** skip steps — execute them in order
- **Do NOT** assume — ask the user to confirm what they see
- Screenshots should be clear and show the issue/success condition
- If the user can't reproduce the original issue, note that as a win (it was already fixed)

## Committing work

After the debug session is complete:

```
git add plans/complete/
git commit -m "debug: <feature-name> — <verified|issue found>"
```

## Workflow integration

**If fix verified:**
- The bug is ready to close (happens naturally when plan was moved to complete/)
- User can now consider the feature fully delivered

**If issue found:**
- Option A: `/wf-rollback` the plan and `/wf-bug` file a new issue
- Option B: `/wf-implement` to fix the specific issue (create amendment to the plan)
- Option C: Investigate further with another debug session
