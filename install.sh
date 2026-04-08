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

# Install workflow scripts
echo "Installing scripts..."
mkdir -p "$TARGET_DIR/scripts"
for script in "$SCRIPT_DIR/scripts"/wf-*.sh; do
    DEST="$TARGET_DIR/scripts/$(basename "$script")"
    cp "$script" "$DEST"
    chmod +x "$DEST"
    echo -e "${GREEN}  Installed scripts/$(basename "$script")${NC}"
done

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

# ── Propagate to feature worktrees ───────────────────────────────────────────
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
                mkdir -p "$wt_path/scripts"
                for script in "$TARGET_ABS/scripts"/wf-*.sh; do
                    cp "$script" "$wt_path/scripts/$(basename "$script")"
                    chmod +x "$wt_path/scripts/$(basename "$script")"
                done

                for skill_dir in "$TARGET_ABS/.claude/skills"/*/; do
                    dest="$wt_path/.claude/skills/$(basename "$skill_dir")"
                    mkdir -p "$dest"
                    cp "$skill_dir/SKILL.md" "$dest/SKILL.md"
                done

                mkdir -p "$wt_path/.claude"
                [ -f "$TARGET_ABS/.claude/workflow.md" ] && cp "$TARGET_ABS/.claude/workflow.md" "$wt_path/.claude/workflow.md"
                [ -f "$TARGET_ABS/.claude/workflow-version" ] && cp "$TARGET_ABS/.claude/workflow-version" "$wt_path/.claude/workflow-version"

                echo -e "  ${GREEN}Updated $(basename "$wt_path")${NC}"
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
echo "  /wf-rollback    — revert a completed plan"
echo ""
echo "Start with: /wf-init (setup) → /wf-next (run your role)"
