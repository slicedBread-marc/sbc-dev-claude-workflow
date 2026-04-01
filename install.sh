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
    grep "^$1:" "$CONFIG_FILE" | sed "s/^$1:[[:space:]]*//" | sed 's/^"//' | sed 's/"$//'
}

BUILD_CMD=$(get_config "build_command")
TEST_CMD=$(get_config "test_command")
TEST_FILTER=$(get_config "test_filter_flag")
NAMESPACE_CONV=$(get_config "namespace_convention")
CONVENTIONS_NOTE=$(get_config "conventions_note")

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
mkdir -p "$TARGET_DIR/plans/complete"
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
        -e "s|{{namespace_convention}}|$NAMESPACE_CONV|g" \
        -e "s|{{conventions_note}}|$CONVENTIONS_NOTE|g" \
        -e "s|{{source_dirs}}|$SOURCE_DIRS|g" \
        "$skill_dir/SKILL.md" > "$DEST_DIR/SKILL.md"

    echo -e "${GREEN}  Installed /$(basename "$skill_dir")${NC}"
done

# Append workflow snippet to CLAUDE.md if not already present
CLAUDE_MD="$TARGET_DIR/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
    if grep -q "Multi-Session Workflow" "$CLAUDE_MD"; then
        echo -e "${YELLOW}  CLAUDE.md already contains workflow section — skipping${NC}"
    else
        echo "" >> "$CLAUDE_MD"
        sed -e "s|{{build_command}}|$BUILD_CMD|g" \
            -e "s|{{test_command}}|$TEST_CMD|g" \
            -e "s|{{source_dirs}}|$SOURCE_DIRS|g" \
            "$SCRIPT_DIR/claude-md/workflow-snippet.md" >> "$CLAUDE_MD"
        echo -e "${GREEN}  Appended workflow section to CLAUDE.md${NC}"
    fi
else
    sed -e "s|{{build_command}}|$BUILD_CMD|g" \
        -e "s|{{test_command}}|$TEST_CMD|g" \
        -e "s|{{source_dirs}}|$SOURCE_DIRS|g" \
        "$SCRIPT_DIR/claude-md/workflow-snippet.md" > "$CLAUDE_MD"
    echo -e "${GREEN}  Created CLAUDE.md with workflow section${NC}"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Available skills:"
echo "  /status      — see pipeline status and next action"
echo "  /brainstorm  — capture and explore ideas"
echo "  /plan        — create implementation plan from a brief"
echo "  /review      — architecture and security review"
echo "  /implement   — build from a plan"
echo "  /verify      — check implementation against plan"
echo ""
echo "Start with: /status"
