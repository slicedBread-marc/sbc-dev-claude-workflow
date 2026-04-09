---
name: wf-release
description: Merge develop into release, run E2E tests to validate staging. Stops here — use /wf-deploy to promote to main.
user_invocable: true
model: haiku
---

# Release Role

You are in **release mode**. Your job is to sync `develop` into `release`, validate staging with E2E tests, and confirm it's ready for production promotion. This skill does NOT promote to main — that's `/wf-deploy`.

## State context

```
plans/REGISTRY.md → single source of truth (plans stay in "complete" state after this skill)
release branch    → staging environment for E2E validation
```

## What you do

1. **Confirm you are on the `release` branch:**
   ```bash
   scripts/wf-branch-check.sh release
   ```
2. **Check if release has unreleased commits:**
   ```bash
   git log main..release --oneline | head -10
   ```
3. **If no new commits on release vs main**: inform the user ("Release is up to date with main — nothing to release.") and exit. Next step: work on a plan with `/wf-implement`, test it with `/wf-test`, then return here.
4. **Show commits to user** — display the commit list from step 2, then prompt: "These commits are staged for E2E. Proceed? (y/n)"
   Wait for explicit confirmation before continuing.
5. **Merge `develop` into `release`** to bring plan files and REGISTRY state:
   ```bash
   git pull origin release
   git merge origin/develop --no-edit
   ```
   If this fails with non-trivial conflicts, inform the user and stop — do not proceed to E2E.
6. **Push release branch:**
   ```bash
   git push origin release
   ```
7. **Run E2E / integration tests** (staging validation):
   ```bash
   {{build_command}}
   {{test_command}}
   ```
   If tests fail, inform the user of failures. The release branch stays as-is for fixes.
8. **Display result**:

   **On success:**
   ```
   ✓ develop merged to release (plan files synced)
   ✓ E2E tests passed on release branch

   NEXT: When ready to promote to production, run:
     /wf-deploy
   ```

   **On failure:**
   ```
   ✗ E2E tests failed on release branch

   Fix the issues on the feature branch, create a new PR, and re-run /wf-release.
   Do NOT proceed with /wf-deploy until E2E passes.
   ```

## Rules

- **Confirm branch** — always check you're on `release` before starting
- **Do NOT merge to main** — that's `/wf-deploy`
- **Do NOT update REGISTRY.md** — plan states are already set by `wf-test` and `wf-deploy`
- **Do NOT** force push — use regular merge
- **Complete all steps** — if the user interrupts, provide a clear resumption point

## On startup

1. Confirm on `release` branch
2. Check for commits on `release` that aren't on `main`
3. If new commits exist: show them and prompt user to confirm proceeding
4. If no new commits: inform user there is nothing to release

## Committing work

This skill creates one merge commit (`develop → release`) and one push. No other commits are created.

If you need to resume after an interruption, tell the user which step to pick up at.
