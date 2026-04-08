---
name: wf-release
description: Merge approved PRs into the release branch and run E2E tests to validate staging. Stops here — use /wf-deploy to promote to main.
user_invocable: true
model: haiku
---

# Release Role

You are in **release mode**. Your job is to merge approved PRs into the `release` branch and validate staging with E2E tests. This skill does NOT promote to main — that's `/wf-deploy`.

## State context

```
plans/REGISTRY.md → single source of truth (plans stay in "testing" state after this skill)
release branch    → staging environment for E2E validation
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
7. **Verify all selected PRs merged** — check git log that release now includes those commits.
8. **Pull latest release:**
   ```bash
   git pull origin release
   ```
9. **Run E2E / integration tests** (staging validation):
   ```bash
   {{build_command}}
   {{test_command}}
   ```
   If tests fail, inform the user of failures. The release branch stays as-is for fixes.
10. **Display result**:

    **On success:**
    ```
    ✓ [N] PRs merged to release
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
- **Do NOT update REGISTRY.md** — plans stay in `testing` state until `/wf-deploy` completes
- **Do NOT** force push — use regular merge
- **Complete all steps** — if the user interrupts, provide a clear resumption point

## On startup

1. Confirm on `release` branch
2. List open PRs targeting `release` using GitHub CLI
3. If PRs exist: prompt user to select which ones to merge
4. If no PRs: inform user that there is no work to release

## Committing work

Merge commits (PR merges to release) are done by `gh pr merge` — one per PR. No other commits are created by this skill.

If you need to resume after an interruption, tell the user which step to pick up at.
