---
name: wf-release
description: Promote release branch to main. Move tested plans to complete, close bugs, back-merge to develop. Separate skill pushes main to trigger production.
user_invocable: true
model: haiku
---

# Release Role

You are in **release mode**. Your job is to promote tested work from the release branch to main, mark plans complete, close bugs, and back-merge to develop. Pushing to main (which triggers production deploy) is a separate, deliberate step.

## Model guidance
This skill runs on **haiku**. Release is orchestration and git operations — straightforward procedural work.

## Model check
**On startup, only if NOT on haiku:**
> "This skill is designed for **haiku**. Run `/model haiku` to switch, or say 'proceed' to continue on the current model."
Wait for the user to respond before continuing. If they proceed without switching, note it once and continue.

If already on haiku, skip the prompt and continue directly.

## Folder structure

```
release/          → staging integration (merge PRs here, then promote to main)
main/             → ready for production (git push origin main triggers deploy in GitHub Actions)
plans/verify/     → plans with Status Tested (PR created, awaiting merge in wf-release)
plans/complete/   → plans promoted to main (ready or live)
bugs/triaged/     → bugs linked to verified plans (move to closed when plan completes)
bugs/closed/      → closed bugs
```

## What you do

1. **Confirm you are on the `release` branch** — run `git branch --show-current`. Must be `release`.
2. **List open PRs targeting `release`**:
   ```bash
   gh pr list --base release --state open --json number,title,headRefName
   ```
3. **If no PRs exist**: inform the user and exit. Next step: work on a plan with `/wf-implement`, test it with `/wf-test`, then return here.
4. **If PRs exist**: display them as a numbered list with PR number, title, and source branch.
5. **Prompt user**: "Which PRs should I merge? (enter numbers separated by spaces, or 'all')"
6. **Merge selected PRs**:
   ```bash
   gh pr merge <PR-number> --squash --auto
   # or
   gh pr merge <PR-number> --merge --auto
   ```
   For each PR merged, extract the plan name from the PR title (format: `feat: <plan-name>`) and note it.
7. **Verify all selected PRs merged** — check git log that release now includes those commits
8. **Switch to `main` branch**:
   ```bash
   git checkout main
   git pull origin main
   ```
9. **Merge `release` into `main`**:
   ```bash
   git merge --no-ff release -m "release: promote to main"
   ```
   If there are merge conflicts in `plans/`, resolve in favor of release:
   ```bash
   git diff --name-only --diff-filter=U | grep '^plans/' | xargs -r git checkout --theirs
   git add plans/
   git commit --no-edit
   ```
10. **Move plans from `verify/` → `complete/`** (on the main branch):
    For each merged PR's plan name:
    ```bash
    git mv plans/verify/<plan-name> plans/complete/<plan-name>
    ```
    Update `plan.md`: set Status to `Complete` and add a note:
    ```
    Completed: YYYY-MM-DD — deployed to production
    ```
11. **Close linked bugs**:
    - For each plan in `plans/complete/`, read `plan.md` Goal to find the `**Bug:**` line (if present)
    - Extract BUG-NNN identifier
    - Move `bugs/triaged/BUG-NNN-<slug>/` → `bugs/closed/BUG-NNN-<slug>/`
    - Update `bug.md` in that folder:
      ```
      Status: Closed
      Closed: YYYY-MM-DD
      Notes: Fixed by plan: plans/complete/<plan-folder>/
      ```
12. **Commit all plan moves and bug closures**:
    ```bash
    git add plans/complete/ bugs/closed/
    git commit -m "release: complete [plan-names], close bugs"
    ```
13. **Back-merge `main` → `develop`**:
    ```bash
    git checkout develop
    git pull origin develop
    git merge main -m "sync: bring completed plans back to develop"
    ```
    If there are merge conflicts in `plans/`, resolve in favor of main (--ours, since main has complete/):
    ```bash
    git diff --name-only --diff-filter=U | grep '^plans/' | xargs -r git checkout --ours
    git add plans/
    git commit --no-edit
    ```
14. **Push develop branch**:
    ```bash
    git push origin develop
    ```
    (This syncs the completed plans back to develop)

15. **Do NOT push main** — that's a separate step:
    ```
    To deploy to production, run:
    git push origin main
    (This triggers the production deploy in GitHub Actions)
    ```

16. **Display success**:
    ```
    ✓ [N] PRs merged to release
    ✓ Plans marked complete on main
    ✓ Bugs closed
    ✓ Back-merged to develop and pushed
    
    NEXT: When ready to go live, manually push main:
      git push origin main
    
    This will trigger the production deploy to https://slicedbread.ca
    ```

## Plan conflict resolution

**During release → main merge:** Use release's version (--theirs) because release has tested/staged plans

**During main → develop back-merge:** Use main's version (--ours) because main now has complete/ plans

Both merges auto-resolve plan conflicts inline (steps 6 and 10). If conflicts are complex and can't auto-resolve, abort and notify the user.

## Rules

- **Confirm branch** — always check you're on `release` before starting
- **Verify staging** — confirm human testing before proceeding to main
- **Do NOT** force push — this is a main branch, use regular merge
- **Do NOT** skip back-merge — develop needs to stay in sync with main
- **Complete all steps** — if the user interrupts, provide a clear resumption point

## Bug closing

When a plan reaches `Complete`, check if `plan.md` contains a `**Bug:**` line in the Goal section.

Format:
```
## Goal
Fix the [description]. (**Bug:** BUG-NNN-<slug>)
```

Extract BUG-NNN and slug, then:
1. Read `bugs/triaged/BUG-NNN-<slug>/bug.md`
2. Update `bug.md`:
   ```
   Status: Closed
   Closed: YYYY-MM-DD
   Notes: Fixed by plan: plans/complete/<plan-folder>/
   ```
3. Move folder: `git mv bugs/triaged/BUG-NNN-<slug> bugs/closed/BUG-NNN-<slug>`

## On startup

1. Confirm on `release` branch
2. List open PRs targeting `release` using GitHub CLI
3. If PRs exist: prompt user to select which ones to merge
4. If no PRs: inform user that there is no work to release

## Committing work

Four commits are normal:
1. Merge commits (PR merges to release): done by `gh pr merge` — one per PR
2. Merge commit (release → main): `"release: promote to main"`
3. Plans + bugs: `"release: complete [plan-names], close bugs"`
4. Back-merge: `"sync: bring completed plans back to develop"`

If you need to resume after an interruption, tell the user which step to pick up at.

## Production deploy (separate step)

This skill does NOT push to main. After `/wf-release` completes:

To deploy to production, manually push main:
```bash
git push origin main
```

Pushing `main` automatically triggers `.github/workflows/deploy.yml` on the GitHub Actions runner. Check deployment status at:
- **Logs:** https://github.com/marcblais/sbc/actions
- **Live site:** https://slicedbread.ca (update should be live in 2–5 minutes)
- **Health:** Check `/health` endpoint for server status
