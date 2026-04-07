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

## State context

```
plans/REGISTRY.md → single source of truth (plans in "complete" state after this skill runs)
bugs/triaged/     → bugs linked to plans (move to closed/ when plan completes)
bugs/closed/      → closed bugs
```

## What you do

1. **Confirm you are on the `release` branch:**
   ```bash
   scripts/wf-branch-check.sh release
   ```
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
9. **Merge `release` into `main`** (auto-resolve in favor of release):
   ```bash
   git merge -X theirs --no-ff release -m "release: promote to main"
   ```
   The `-X theirs` option automatically accepts release's version of any conflicting files in `plans/`.
10. **Update REGISTRY.md** — for each merged PR's plan, verify state is `complete`. If not:
    ```bash
    scripts/wf-registry-update.sh PLN-NNN testing complete -
    ```
11. **Close linked bugs** — for each completed plan, check `plan.md` Goal for `**Bug:**` line:
    ```bash
    scripts/wf-bug-close.sh BUG-NNN PLN-NNN-<slug>
    ```
12. **Commit plan and bug updates**:
    ```bash
    git add plans/REGISTRY.md plans/PLN-*/plan.md bugs/closed/
    git commit -m "release: complete [plan-names], close bugs"
    ```
13. **Back-merge `main` → `develop`** (auto-resolve in favor of main):
    ```bash
    git checkout develop
    git pull origin develop
    git merge -X ours main -m "sync: bring completed plans back to develop"
    ```
    The `-X ours` option automatically accepts main's version of any conflicting files in `plans/` (main has complete/).
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

## Conflict resolution

Merge strategy `-X theirs` (step 9) and `-X ours` (step 13) automatically resolve conflicts:

- **release → main:** Accept release's version
- **main → develop:** Accept main's version (has REGISTRY.md updates)

Plans never move folders, so the only potential conflict is REGISTRY.md — which is row-based and auto-merges in most cases. If a merge fails, abort and notify the user.

## Rules

- **Confirm branch** — always check you're on `release` before starting
- **Verify staging** — confirm human testing before proceeding to main
- **Do NOT** force push — this is a main branch, use regular merge
- **Do NOT** skip back-merge — develop needs to stay in sync with main
- **Complete all steps** — if the user interrupts, provide a clear resumption point

## Bug closing

When a plan reaches `complete` state in REGISTRY.md, check if `plan.md` contains a `**Bug:**` line in the Goal section. Extract BUG-NNN, then:
```bash
scripts/wf-bug-close.sh BUG-NNN PLN-NNN-<slug>
```

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
