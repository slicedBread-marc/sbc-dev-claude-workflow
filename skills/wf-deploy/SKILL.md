---
name: wf-deploy
description: Promote release branch to main. Mark plans complete, close bugs, back-merge to develop. Final step before production push.
user_invocable: true
model: haiku
---

# Deploy Role

You are in **deploy mode**. Your job is to promote the validated release branch to main, mark plans complete, close bugs, and back-merge to develop. This is the final pipeline step — run only after `/wf-release` has merged PRs and E2E tests have passed on the release branch.

## State context

```
plans/REGISTRY.md → single source of truth (plans move testing → complete)
bugs/triaged/     → bugs linked to plans (move to closed/ when plan completes)
bugs/closed/      → closed bugs
```

## Pre-flight check

Before starting, confirm E2E passed on release:

1. **Confirm you are on the `release` branch:**
   ```bash
   scripts/wf-exec.sh wf-branch-check.sh release
   ```
2. **Show recent release commits** so the user can confirm what's being promoted:
   ```bash
   git log --oneline release --not main -n 20
   ```
3. **If no new commits on release vs main**: inform the user there is nothing to deploy and exit.
4. **Prompt user**: "These commits will be promoted to main. Proceed? (y/n)"
   Wait for explicit confirmation before continuing.

## What you do

5. **Switch to `main` branch**:
   ```bash
   git checkout main
   git pull origin main
   ```
6. **Merge `release` into `main`** (auto-resolve in favor of release):
   ```bash
   git merge -X theirs --no-ff release -m "release: promote to main"
   ```
   The `-X theirs` option automatically accepts release's version of any conflicting files in `plans/`.
7. **Run full test suite** (final integration check):
   ```bash
   {{build_command}}
   {{test_command}}
   ```
   If tests fail, abort the deploy — do NOT proceed to registry updates. Inform user of failures and suggest fixing on the release branch, then re-running `/wf-release`.
8. **Update REGISTRY.md** — for each plan that was on the release branch, verify state is `complete`. If not:
   ```bash
   scripts/wf-exec.sh wf-registry-update.sh PLN-NNN testing complete -
   ```
9. **Close linked bugs** — for each completed plan, check `plan.md` Goal for `**Bug:**` line:
   ```bash
   scripts/wf-exec.sh wf-bug-close.sh BUG-NNN PLN-NNN-<slug>
   ```
10. **Commit plan and bug updates**:
    ```bash
    git add plans/PLN-*/plan.md bugs/closed/
    git commit -m "release: complete [plan-names], close bugs"
    ```
11. **Back-merge `main` → `develop`** (auto-resolve in favor of main):
    ```bash
    git checkout develop
    git pull origin develop
    git merge -X ours main -m "sync: bring completed plans back to develop"
    ```
    The `-X ours` option automatically accepts main's version of any conflicting files in `plans/` (main has complete state).
12. **Push develop branch**:
    ```bash
    git push origin develop
    ```
    (This syncs the completed plans back to develop)

13. **Do NOT push main** — that's a separate, deliberate step:
    ```
    To deploy to production, run:
    git push origin main
    (This triggers the production deploy in GitHub Actions)
    ```

14. **Display success**:
    ```
    ✓ Release promoted to main
    ✓ Plans marked complete
    ✓ Bugs closed
    ✓ Back-merged to develop and pushed

    NEXT: When ready to go live, manually push main:
      git push origin main

    This will trigger the production deploy to {{production_url}}
    ```

## Conflict resolution

Merge strategy `-X theirs` (step 6) and `-X ours` (step 11) automatically resolve conflicts:

- **release → main:** Accept release's version
- **main → develop:** Accept main's version (has REGISTRY.md updates)

Plans never move folders, so the only potential conflict is REGISTRY.md — which is row-based and auto-merges in most cases. If a merge fails, abort and notify the user.

## Rules

- **Require confirmation** — always show what's being promoted and wait for user approval
- **E2E must have passed** — this skill assumes `/wf-release` already validated the release branch
- **Do NOT** force push — this is a main branch, use regular merge
- **Do NOT** skip back-merge — develop needs to stay in sync with main
- **Complete all steps** — if the user interrupts, provide a clear resumption point

## On startup

1. Confirm on `release` branch
2. Show commits on release that aren't on main
3. If new commits exist: prompt user to confirm promotion
4. If no new commits: inform user there is nothing to deploy

## Committing work

Three commits are normal:
1. Merge commit (release → main): `"release: promote to main"`
2. Plans + bugs: `"release: complete [plan-names], close bugs"`
3. Back-merge: `"sync: bring completed plans back to develop"`

If you need to resume after an interruption, tell the user which step to pick up at.

On completion, run `scripts/wf-exec.sh wf-check-reboot-flag.sh` and append any output to your completion message.

## Production deploy (separate step)

This skill does NOT push to main. After `/wf-deploy` completes:

To deploy to production, manually push main:
```bash
git push origin main
```

Pushing `main` automatically triggers `.github/workflows/deploy.yml` on the GitHub Actions runner. Check deployment status at:
- **Logs:** {{production_logs_url}}
- **Live site:** {{production_url}} (update should be live in 2–5 minutes)
- **Health:** Check `/health` endpoint for server status
