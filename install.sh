#!/bin/bash
set -euo pipefail

# claude-workflow installer
# Installs the workflow skills, templates, and folder structure into a project.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-.}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "claude-workflow installer"
echo "========================"
echo ""

# Check for config
CONFIG_FILE="$TARGET_DIR/claude-workflow.yml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}No claude-workflow.yml found in $TARGET_DIR${NC}"
    echo "Creating from template..."
    cp "$SCRIPT_DIR/config.example.yml" "$CONFIG_FILE"
    echo -e "${GREEN}Created $CONFIG_FILE — edit it with your project settings, then re-run.${NC}"
    exit 0
fi

# Parse config (simple grep-based, no yq dependency)
get_config() {
    grep "^$1:" "$CONFIG_FILE" 2>/dev/null | sed "s/^$1:[[:space:]]*//" | sed 's/^"//' | sed 's/"$//' || true
}

BUILD_CMD=$(get_config "build_command")
TEST_CMD=$(get_config "test_command")
TEST_FILTER=$(get_config "test_filter_flag")
TEST_EXCLUDE_E2E=$(get_config "test_exclude_e2e")
TEST_ONLY_E2E=$(get_config "test_only_e2e")
NAMESPACE_CONV=$(get_config "namespace_convention")
CONVENTIONS_NOTE=$(get_config "conventions_note")
LOCAL_START=$(get_config "local_start_command")
LOCAL_DEPLOY=$(get_config "local_deploy_command")
LOCAL_STOP=$(get_config "local_stop_command")
PROJECT_SLUG=$(get_config "project_slug")
PRODUCTION_LOGS_URL=$(get_config "production_logs_url")
PRODUCTION_URL=$(get_config "production_url")

# project_slug is required as of workflow v1.33.0 — it namespaces Docker
# compose projects so multiple clients can coexist on one Docker daemon.
if [ -z "$PROJECT_SLUG" ]; then
    RED='\033[0;31m'
    echo -e "${RED}ERROR: project_slug is required (introduced in workflow v1.33.0).${NC}"
    echo ""
    echo "Edit $CONFIG_FILE and set project_slug to a short identifier"
    echo "unique to this project (e.g., the repo directory name):"
    echo ""
    echo "    project_slug: \"$(basename "$(cd "$TARGET_DIR" && pwd)")\""
    echo ""
    echo "This namespaces Docker compose projects (e.g., <slug>-pln004) so"
    echo "multiple clients on one machine don't collide on container names."
    exit 1
fi

# Read source_dirs as comma-separated string
SOURCE_DIRS=$(grep -A 10 "^source_dirs:" "$CONFIG_FILE" | grep "^  - " | sed 's/^  - //' | sed 's/"//g' | tr '\n' ', ' | sed 's/,$//')

echo "Configuration:"
echo "  Build:       $BUILD_CMD"
echo "  Test:        $TEST_CMD"
echo "  Source dirs: $SOURCE_DIRS"
echo ""

# Create folder structure
echo "Creating folder structure..."
mkdir -p "$TARGET_DIR/plans/briefs"
mkdir -p "$TARGET_DIR/plans/drafts"
mkdir -p "$TARGET_DIR/plans/ready"
mkdir -p "$TARGET_DIR/plans/active"
mkdir -p "$TARGET_DIR/plans/verify"
mkdir -p "$TARGET_DIR/plans/replanning"
mkdir -p "$TARGET_DIR/plans/complete"
mkdir -p "$TARGET_DIR/plans/rolled-back"
echo -e "${GREEN}  plans/ folder structure created${NC}"

# Seed REGISTRY.md if it doesn't exist (gitignored — never overwrite live state)
REGISTRY_TEMPLATE="$SCRIPT_DIR/templates/plans/REGISTRY.md"
REGISTRY_DEST="$TARGET_DIR/plans/REGISTRY.md"
if [ -f "$REGISTRY_TEMPLATE" ] && [ ! -f "$REGISTRY_DEST" ]; then
    mkdir -p "$TARGET_DIR/plans"
    cp "$REGISTRY_TEMPLATE" "$REGISTRY_DEST"
    echo -e "${GREEN}  Seeded plans/REGISTRY.md from template${NC}"
else
    echo -e "${YELLOW}  plans/REGISTRY.md already exists — skipping${NC}"
    # v2.00 migration: ensure REGISTRY has the WF column. Row layout is
    # "| ID | Slug | State | Priority | Branch | Updated | WF |" — 7 data
    # columns means 8 pipes. Rows with 7 pipes lack WF; append an empty
    # WF cell so the dispatcher routes them to v1.x (legacy baseline).
    header_line=$(grep -nE '^\| ID \|' "$REGISTRY_DEST" | head -1 | cut -d: -f1 || true)
    if [ -n "$header_line" ] && ! grep -qE '^\| ID \|.*\| WF \|' "$REGISTRY_DEST"; then
        echo "  Migrating REGISTRY.md → adding WF column (legacy rows → v1.x)"
        # Header + separator lines get " WF |" appended
        awk 'BEGIN{OFS=""}
             NR==FNR{if(/^\| ID \|/){hdr=NR}; if(hdr && NR==hdr+1){sep=NR}; next}
             {
               if(FNR==hdr){sub(/\|[[:space:]]*$/, "| WF |"); print; next}
               if(FNR==sep){sub(/\|[[:space:]]*$/, "|-|"); print; next}
               # Data rows start with "| PLN-" and end with " |"
               if(/^\| PLN-/){sub(/\|[[:space:]]*$/, "|  |"); print; next}
               print
             }' "$REGISTRY_DEST" "$REGISTRY_DEST" > "$REGISTRY_DEST.tmp" && mv "$REGISTRY_DEST.tmp" "$REGISTRY_DEST"
        echo -e "${GREEN}  REGISTRY.md migrated (WF column added)${NC}"
    fi
fi

# Copy and templatize plan templates
echo "Installing templates..."
for f in "$SCRIPT_DIR/templates/plans/TEMPLATE.md" "$SCRIPT_DIR/templates/plans/briefs/TEMPLATE.md" "$SCRIPT_DIR/templates/plans/briefs/INDEX.md"; do
    DEST="$TARGET_DIR/plans/${f#$SCRIPT_DIR/templates/plans/}"
    if [ -f "$DEST" ]; then
        echo -e "  ${YELLOW}Skipping $DEST (already exists)${NC}"
    else
        mkdir -p "$(dirname "$DEST")"
        sed -e "s|{{build_command}}|$BUILD_CMD|g" \
            -e "s|{{test_command}}|$TEST_CMD|g" \
            -e "s|{{test_filter_flag}}|$TEST_FILTER|g" \
            -e "s|{{test_exclude_e2e}}|$TEST_EXCLUDE_E2E|g" \
            -e "s|{{test_only_e2e}}|$TEST_ONLY_E2E|g" \
            -e "s|{{namespace_convention}}|$NAMESPACE_CONV|g" \
            -e "s|{{conventions_note}}|$CONVENTIONS_NOTE|g" \
            -e "s|{{source_dirs}}|$SOURCE_DIRS|g" \
            -e "s|{{project_slug}}|$PROJECT_SLUG|g" \
            -e "s|{{production_logs_url}}|$PRODUCTION_LOGS_URL|g" \
            -e "s|{{production_url}}|$PRODUCTION_URL|g" \
            "$f" > "$DEST"
        echo -e "${GREEN}  Installed $DEST${NC}"
    fi
done

# Copy and templatize skills
echo "Installing skills..."
mkdir -p "$TARGET_DIR/.claude/skills"
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
    SKILL_NAME=$(basename "$skill_dir")
    DEST_DIR="$TARGET_DIR/.claude/skills/$SKILL_NAME"
    mkdir -p "$DEST_DIR"

    sed -e "s|{{build_command}}|$BUILD_CMD|g" \
        -e "s|{{test_command}}|$TEST_CMD|g" \
        -e "s|{{test_filter_flag}}|$TEST_FILTER|g" \
        -e "s|{{test_exclude_e2e}}|$TEST_EXCLUDE_E2E|g" \
        -e "s|{{test_only_e2e}}|$TEST_ONLY_E2E|g" \
        -e "s|{{namespace_convention}}|$NAMESPACE_CONV|g" \
        -e "s|{{conventions_note}}|$CONVENTIONS_NOTE|g" \
        -e "s|{{source_dirs}}|$SOURCE_DIRS|g" \
        -e "s|{{project_slug}}|$PROJECT_SLUG|g" \
        -e "s|{{production_logs_url}}|$PRODUCTION_LOGS_URL|g" \
        -e "s|{{production_url}}|$PRODUCTION_URL|g" \
        "$skill_dir/SKILL.md" > "$DEST_DIR/SKILL.md"

    echo -e "${GREEN}  Installed /$(basename "$skill_dir")${NC}"
done

# Install local env script (only if local_deploy_command is set)
if [ -n "$LOCAL_DEPLOY" ]; then
    sed -e "s|{{local_start_command}}|$LOCAL_START|g" \
        -e "s|{{local_deploy_command}}|$LOCAL_DEPLOY|g" \
        -e "s|{{local_stop_command}}|$LOCAL_STOP|g" \
        "$SCRIPT_DIR/templates/on-implement-commit.sh" > "$TARGET_DIR/.claude/on-implement-commit.sh"
    chmod +x "$TARGET_DIR/.claude/on-implement-commit.sh"
    echo -e "${GREEN}  Installed .claude/on-implement-commit.sh${NC}"

    # Gitignore local-env runtime files
    GITIGNORE="$TARGET_DIR/.gitignore"
    for pattern in ".claude/local-env.timestamp" ".claude/local-env.pid" ".claude/local-env.log"; do
        if ! grep -qF "$pattern" "$GITIGNORE" 2>/dev/null; then
            echo "$pattern" >> "$GITIGNORE"
        fi
    done
    echo -e "${GREEN}  Updated .gitignore with local-env runtime files${NC}"
else
    echo -e "${YELLOW}  local_deploy_command not set — skipping local env install${NC}"
fi

# Install verify trigger script (always — verify agent is core to the pipeline)
cp "$SCRIPT_DIR/templates/on-verify-trigger.sh" "$TARGET_DIR/.claude/on-verify-trigger.sh"
chmod +x "$TARGET_DIR/.claude/on-verify-trigger.sh"
echo -e "${GREEN}  Installed .claude/on-verify-trigger.sh${NC}"

# Gitignore verify runtime files
GITIGNORE="$TARGET_DIR/.gitignore"
for pattern in ".claude/verify-*.log" ".claude/verify-*.pid"; do
    if ! grep -qF "$pattern" "$GITIGNORE" 2>/dev/null; then
        echo "$pattern" >> "$GITIGNORE"
    fi
done

# Orchestrator runtime dirs — gates, worker logs, events.log, locks.
# All runtime state, none of it belongs in git.
mkdir -p "$TARGET_DIR/.claude/orchestrator/gates" \
         "$TARGET_DIR/.claude/orchestrator/logs" \
         "$TARGET_DIR/.claude/orchestrator/attempts"
if ! grep -qF ".claude/orchestrator/" "$GITIGNORE" 2>/dev/null; then
    echo ".claude/orchestrator/" >> "$GITIGNORE"
fi
echo -e "${GREEN}  Created .claude/orchestrator/ (gitignored)${NC}"

# Install post-commit hook
HOOK="$TARGET_DIR/.git/hooks/post-commit"
if [ ! -f "$HOOK" ]; then
    cp "$SCRIPT_DIR/templates/hooks/post-commit" "$HOOK"
    chmod +x "$HOOK"
    echo -e "${GREEN}  Installed .git/hooks/post-commit${NC}"
elif ! grep -q "claude-workflow: verify agent trigger" "$HOOK"; then
    # Overwrite with latest hook (includes both local-env and verify triggers)
    cp "$SCRIPT_DIR/templates/hooks/post-commit" "$HOOK"
    chmod +x "$HOOK"
    echo -e "${GREEN}  Updated .git/hooks/post-commit (added verify trigger)${NC}"
else
    echo -e "${YELLOW}  post-commit hook already up to date — skipping${NC}"
fi

# Gitignore REGISTRY.md (operational state, not source code)
GITIGNORE="$TARGET_DIR/.gitignore"
if ! grep -qF "plans/REGISTRY.md" "$GITIGNORE" 2>/dev/null; then
    echo "plans/REGISTRY.md" >> "$GITIGNORE"
    echo -e "${GREEN}  Added plans/REGISTRY.md to .gitignore${NC}"
fi

# Install workflow scripts — versioned layout (v2.0+).
# Each scripts/v*/ in the library is a complete, frozen snapshot. The
# unversioned dispatcher (scripts/wf-exec.sh) routes plans to the right
# snapshot via scripts/version-map.txt.
echo "Installing scripts..."
mkdir -p "$TARGET_DIR/scripts"

# Template each versioned snapshot.
for version_dir in "$SCRIPT_DIR/scripts"/v*/; do
    [ -d "$version_dir" ] || continue
    folder_name=$(basename "$version_dir")
    DEST_VDIR="$TARGET_DIR/scripts/$folder_name"
    mkdir -p "$DEST_VDIR"
    for script in "$version_dir"/wf-*.sh; do
        [ -f "$script" ] || continue
        DEST="$DEST_VDIR/$(basename "$script")"
        sed -e "s|{{project_slug}}|$PROJECT_SLUG|g" \
            -e "s|{{production_logs_url}}|$PRODUCTION_LOGS_URL|g" \
            -e "s|{{production_url}}|$PRODUCTION_URL|g" \
            "$script" > "$DEST"
        chmod +x "$DEST"
    done
    echo -e "${GREEN}  Installed scripts/$folder_name/ ($(ls "$DEST_VDIR" | wc -l | tr -d ' ') scripts)${NC}"
done

# Dispatcher + pruning tool + version map — unversioned, copied verbatim.
for f in wf-exec.sh wf-prune-versions.sh; do
    cp "$SCRIPT_DIR/scripts/$f" "$TARGET_DIR/scripts/$f"
    chmod +x "$TARGET_DIR/scripts/$f"
    echo -e "${GREEN}  Installed scripts/$f${NC}"
done
cp "$SCRIPT_DIR/scripts/version-map.txt" "$TARGET_DIR/scripts/version-map.txt"
echo -e "${GREEN}  Installed scripts/version-map.txt${NC}"

# Gitignore workflow runtime files
GITIGNORE="$TARGET_DIR/.gitignore"
for pattern in ".wf-claim"; do
    if ! grep -qF "$pattern" "$GITIGNORE" 2>/dev/null; then
        echo "$pattern" >> "$GITIGNORE"
    fi
done

# Stamp workflow version into the target project
WORKFLOW_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
echo "$WORKFLOW_VERSION" > "$TARGET_DIR/.claude/workflow-version"
echo -e "${GREEN}  Stamped workflow version $WORKFLOW_VERSION → .claude/workflow-version${NC}"

# WORKFLOW.md at the project root — the entry-point contract for anyone (or
# anything) that lands in this repo without prior context: how work enters the
# pipeline, which hooks fire automatically, and the wf-orchestrate.sh exit codes
# an external process needs in order to drive a plan.
# Regenerated on every install so it can't drift from the installed version.
sed -e "s|{{project_slug}}|$PROJECT_SLUG|g" \
    -e "s|{{workflow_version}}|$WORKFLOW_VERSION|g" \
    "$SCRIPT_DIR/templates/WORKFLOW.md" > "$TARGET_DIR/WORKFLOW.md"
echo -e "${GREEN}  Installed WORKFLOW.md (project-root entry point)${NC}"

# ── Propagate to feature worktrees ───────────────────────────────────────────
# Resolve a worktree's plan WF stamp → script_folder using the same algorithm
# as wf-exec.sh. Only that folder (plus the unversioned dispatcher + map) gets
# copied into the worktree — so an in-flight plan keeps running the scripts it
# was built against, even after we publish newer generations.
resolve_script_folder() {
    local wf="$1"
    local map="$TARGET_ABS/scripts/version-map.txt"
    [ -z "$wf" ] && wf="0.00"
    [ -f "$map" ] || { echo ""; return; }
    local folder=""
    while IFS= read -r line; do
        line="${line%%#*}"
        [ -z "${line// }" ] && continue
        local min_ver f
        min_ver=$(echo "$line" | awk '{print $1}')
        f=$(echo "$line" | awk '{print $2}')
        [ -z "$min_ver" ] || [ -z "$f" ] && continue
        if [ "$(printf '%s\n%s\n' "$min_ver" "$wf" | sort -V | head -1)" = "$min_ver" ]; then
            folder="$f"
        fi
    done < "$map"
    echo "$folder"
}

if git -C "$TARGET_DIR" rev-parse --git-dir &>/dev/null; then
    echo "Updating feature worktrees..."
    TARGET_ABS="$(cd "$TARGET_DIR" && pwd)"
    WT_COUNT=0

    wt_path="" wt_branch=""
    while IFS= read -r line; do
        if [[ "$line" == worktree\ * ]]; then
            wt_path="${line#worktree }"
            wt_branch=""
        elif [[ "$line" == branch\ * ]]; then
            wt_branch="${line#branch }"
        elif [[ -z "$line" ]]; then
            # End of block — process if it's a feature worktree (not the main one)
            if [[ -n "$wt_path" && "$wt_path" != "$TARGET_ABS" && "$wt_branch" == *feature/* ]]; then
                # Resolve this worktree's plan WF → script folder.
                # Branch format: refs/heads/feature/PLN-NNN[-slug]
                wt_plan_id=$(echo "$wt_branch" | grep -oE 'PLN-[0-9]+' | head -1 || true)
                wt_wf=""
                if [ -n "$wt_plan_id" ] && [ -f "$TARGET_ABS/plans/REGISTRY.md" ]; then
                    row=$(grep "^| ${wt_plan_id} " "$TARGET_ABS/plans/REGISTRY.md" | head -1 || true)
                    # WF column is field $8 in 7-column registry (ID|Slug|State|Priority|Branch|Updated|WF)
                    [ -n "$row" ] && wt_wf=$(echo "$row" | awk -F'|' '{print $8}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                fi
                wt_folder=$(resolve_script_folder "$wt_wf")

                mkdir -p "$wt_path/scripts"
                # Copy the resolved version folder.
                if [ -n "$wt_folder" ] && [ -d "$TARGET_ABS/scripts/$wt_folder" ]; then
                    mkdir -p "$wt_path/scripts/$wt_folder"
                    for script in "$TARGET_ABS/scripts/$wt_folder"/wf-*.sh; do
                        [ -f "$script" ] || continue
                        cp "$script" "$wt_path/scripts/$wt_folder/$(basename "$script")"
                        chmod +x "$wt_path/scripts/$wt_folder/$(basename "$script")"
                    done
                fi
                # Copy unversioned dispatcher + pruning tool + map.
                for f in wf-exec.sh wf-prune-versions.sh; do
                    [ -f "$TARGET_ABS/scripts/$f" ] || continue
                    cp "$TARGET_ABS/scripts/$f" "$wt_path/scripts/$f"
                    chmod +x "$wt_path/scripts/$f"
                done
                [ -f "$TARGET_ABS/scripts/version-map.txt" ] && cp "$TARGET_ABS/scripts/version-map.txt" "$wt_path/scripts/version-map.txt"

                for skill_dir in "$TARGET_ABS/.claude/skills"/*/; do
                    dest="$wt_path/.claude/skills/$(basename "$skill_dir")"
                    mkdir -p "$dest"
                    cp "$skill_dir/SKILL.md" "$dest/SKILL.md"
                done

                mkdir -p "$wt_path/.claude"
                [ -f "$TARGET_ABS/.claude/workflow.md" ] && cp "$TARGET_ABS/.claude/workflow.md" "$wt_path/.claude/workflow.md"
                # Stamp worktree's workflow-version to its PLAN's WF (or 0.00 if empty) —
                # NOT develop's version. Otherwise the dispatcher resolves to a folder
                # (e.g., v2.00) that was never propagated into the worktree.
                echo "${wt_wf:-0.00}" > "$wt_path/.claude/workflow-version"

                echo -e "  ${GREEN}Updated $(basename "$wt_path") (scripts/${wt_folder:-none}, WF=${wt_wf:-0.00})${NC}"
                ((WT_COUNT++)) || true
            fi
            wt_path="" wt_branch=""
        fi
    done < <(git -C "$TARGET_DIR" worktree list --porcelain; echo "")

    [ "$WT_COUNT" -gt 0 ] && echo -e "${GREEN}  $WT_COUNT worktree(s) updated${NC}" || echo -e "  ${YELLOW}No feature worktrees found${NC}"
    echo ""
fi

# Always overwrite .claude/workflow.md (the referenced file — keeps it current on every deploy)
WORKFLOW_MD="$TARGET_DIR/.claude/workflow.md"
sed -e "s|{{build_command}}|$BUILD_CMD|g" \
    -e "s|{{test_command}}|$TEST_CMD|g" \
    -e "s|{{source_dirs}}|$SOURCE_DIRS|g" \
    "$SCRIPT_DIR/claude-md/workflow-snippet.md" > "$WORKFLOW_MD"
echo -e "${GREEN}  Installed .claude/workflow.md${NC}"

# Add @import to CLAUDE.md once — never needs updating after that
CLAUDE_MD="$TARGET_DIR/CLAUDE.md"
IMPORT_LINE="@.claude/workflow.md"
if [ -f "$CLAUDE_MD" ]; then
    if grep -qF "$IMPORT_LINE" "$CLAUDE_MD"; then
        echo -e "${YELLOW}  CLAUDE.md already imports workflow — skipping${NC}"
    else
        echo "" >> "$CLAUDE_MD"
        echo "$IMPORT_LINE" >> "$CLAUDE_MD"
        echo -e "${GREEN}  Added workflow import to CLAUDE.md${NC}"
    fi
else
    echo "$IMPORT_LINE" > "$CLAUDE_MD"
    echo -e "${GREEN}  Created CLAUDE.md with workflow import${NC}"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Available skills:"
echo "  /wf-init        — one-time setup (logging, terminal role)"
echo "  /wf-next        — run your role's skill automatically"
echo "  /wf-help        — display workflow strategy & architecture"
echo "  /wf-status      — see pipeline status and next action"
echo "  /wf-brainstorm  — capture and explore ideas"
echo "  /wf-spec        — create implementation plan from a brief"
echo "  /wf-review      — architecture and security review"
echo "  /wf-implement   — build from a plan"
echo "  /wf-verify      — check implementation against plan"
echo "  /wf-debug       — interactive debug session"
echo "  /wf-bug         — file a bug report"
echo "  /wf-info        — full history and status for any plan, bug, or brief"
echo "  /wf-rollback    — revert a completed plan"
echo ""
echo "Start with: /wf-init (setup) → /wf-next (run your role)"
