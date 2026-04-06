#!/usr/bin/env bash
# migrate-to-dotplan.sh
# One-time migration: adds .plan/ to feature branch worktrees
# and corrects develop's plans/ stages to reflect actual state.
#
# Run from the project root (e.g., /Users/marcblais/dev/sbc)
#
# Safe: does NOT untrack plans/ on feature branches (that would
# cause merge deletions on develop). Just adds .plan/ alongside.
# Skills will prefer .plan/ going forward; stale plans/ is inert.

set -euo pipefail

PROJECT_ROOT=$(pwd)

echo "Plan Migration: plans/ → .plan/"
echo "================================"
echo ""

# ── Phase 1: Add .plan/ to each feature branch worktree ─────────────────

echo "Phase 1: Add .plan/ to feature branch worktrees"
echo ""

for worktree in feature-branches/PLN-*/; do
  [ -d "$worktree" ] || continue
  wt_name=$(basename "$worktree")
  wt_prefix=$(echo "$wt_name" | grep -o '^PLN-[0-9]*' || true)
  [ -n "$wt_prefix" ] || continue

  # Find this worktree's own plan (try verify/, active/, replanning/)
  rel_plan=""
  for stage in verify active replanning; do
    # PLN-prefixed match
    for candidate in "${worktree}plans/${stage}/"*/; do
      [ -d "$candidate" ] || continue
      cand_name=$(basename "$candidate")
      cand_prefix=$(echo "$cand_name" | grep -o '^PLN-[0-9]*' || true)
      if [ "$cand_prefix" = "$wt_prefix" ]; then
        rel_plan="plans/${stage}/${cand_name}"
        break 2
      fi
    done
    # Legacy name match (e.g., PLN-004-deployment-date-footer → deployment-date-footer)
    legacy_name=$(echo "$wt_name" | sed "s/^${wt_prefix}-//")
    if [ -d "${worktree}plans/${stage}/${legacy_name}" ]; then
      rel_plan="plans/${stage}/${legacy_name}"
      break
    fi
  done

  if [ -z "$rel_plan" ]; then
    echo "  ⚠ $wt_name — no matching plan found, skipping"
    continue
  fi

  echo "→ $wt_name"
  echo "  Source: $rel_plan/"

  cd "$PROJECT_ROOT/$worktree"

  if [ -d ".plan" ]; then
    echo "  .plan/ already exists — skipping"
    cd "$PROJECT_ROOT"
    continue
  fi

  mkdir -p .plan
  for f in plan.md findings.md progress.md; do
    [ -f "${rel_plan}/${f}" ] && cp "${rel_plan}/${f}" .plan/
  done

  file_count=$(ls .plan/ 2>/dev/null | wc -l | tr -d ' ')
  git add .plan/
  git commit -m "chore(${wt_prefix}): add .plan/ for plan migration"
  echo "  ✓ Committed .plan/ (${file_count} files)"

  cd "$PROJECT_ROOT"
done

# Handle site-version-indicator legacy worktree
if [ -d "feature-branches/site-version-indicator" ]; then
  echo ""
  echo "→ site-version-indicator (legacy)"
  cd "$PROJECT_ROOT/feature-branches/site-version-indicator"

  if [ -d ".plan" ]; then
    echo "  .plan/ already exists — skipping"
  elif [ -d "plans/staging/site-version-indicator" ]; then
    mkdir -p .plan
    for f in plan.md findings.md progress.md; do
      [ -f "plans/staging/site-version-indicator/${f}" ] && cp "plans/staging/site-version-indicator/${f}" .plan/
    done
    git add .plan/
    git commit -m "chore(site-version-indicator): add .plan/ for plan migration"
    echo "  ✓ Committed"
  else
    echo "  ⚠ No plan found — skipping"
  fi

  cd "$PROJECT_ROOT"
fi

# ── Phase 2: Correct develop's plans/ stages ─────────────────────────────

echo ""
echo "Phase 2: Correct develop plan stages"
echo ""

moved=0

for plan_dir in plans/active/PLN-*/; do
  [ -d "$plan_dir" ] || continue
  plan_name=$(basename "$plan_dir")
  wt_prefix=$(echo "$plan_name" | grep -o '^PLN-[0-9]*' || true)

  # Check if worktree exists
  wt_match=$(ls -d "feature-branches/${wt_prefix}-"* 2>/dev/null | head -1 || true)
  if [ -z "$wt_match" ]; then
    echo "  $plan_name — no worktree, leaving in active/"
    continue
  fi

  # Determine status hint from findings
  status="Verified"
  findings="${wt_match}/.plan/findings.md"
  [ -f "$findings" ] || findings="${wt_match}/plans/verify/${plan_name}/findings.md"

  if [ -f "$findings" ] && grep -q "| Open |" "$findings" 2>/dev/null; then
    status="Verified-with-findings"
  fi

  mkdir -p plans/verify/
  git mv "$plan_dir" "plans/verify/$plan_name"

  # Update status in plan.md
  plan_md="plans/verify/$plan_name/plan.md"
  if [ -f "$plan_md" ]; then
    sed -i '' "s/^Status:.*/Status: $status/" "$plan_md" 2>/dev/null || true
    git add "$plan_md"
  fi

  echo "  $plan_name → verify/ ($status)"
  ((moved++)) || true
done

# Handle legacy deployment-date-footer
if [ -d "plans/active/deployment-date-footer" ]; then
  mkdir -p plans/verify/
  git mv "plans/active/deployment-date-footer" "plans/verify/deployment-date-footer"
  echo "  deployment-date-footer → verify/"
  ((moved++)) || true
fi

if [ "$moved" -gt 0 ]; then
  git add plans/
  git commit -m "chore: correct plan stages — move $moved plans from active/ to verify/"
  echo "  ✓ Committed on develop"
else
  echo "  No plans to move"
fi

# ── Phase 3: Safety net — add .plan/ to develop's .gitignore ─────────────

if ! grep -q '^\.plan/' .gitignore 2>/dev/null; then
  echo "" >> .gitignore
  echo "# Feature branch plan files (should not land on develop)" >> .gitignore
  echo ".plan/" >> .gitignore
  git add .gitignore
  git commit -m "chore: add .plan/ to .gitignore on develop"
  echo ""
  echo "✓ Added .plan/ to develop's .gitignore"
fi

echo ""
echo "=== Migration complete ==="
echo ""
echo "Next steps:"
echo "  1. Update skills (wf-implement, wf-verify, wf-test) to use .plan/"
echo "  2. Update wf-list-*.sh scripts to scan develop's plans/ only"
echo "  3. Existing worktrees work with both paths during transition"
