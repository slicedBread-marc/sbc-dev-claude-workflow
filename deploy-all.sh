#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENTS_FILE="$SCRIPT_DIR/deployments.txt"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "claude-workflow deploy-all"
echo "=========================="
echo ""

# ── Local deployments ────────────────────────────────────────────────────────

if [ ! -f "$DEPLOYMENTS_FILE" ]; then
    echo -e "${YELLOW}No deployments.txt found.${NC}"
    echo "Create it with one project path per line:"
    echo "  echo \"/path/to/your/project\" >> deployments.txt"
    echo ""
else
    LOCAL_COUNT=0
    LOCAL_ERRORS=0

    while IFS= read -r project_path || [ -n "$project_path" ]; do
        # Skip blank lines and comments
        [[ -z "$project_path" || "$project_path" == \#* ]] && continue

        echo "→ $project_path"

        if [ ! -d "$project_path" ]; then
            echo -e "  ${RED}Directory not found — skipping${NC}"
            ((LOCAL_ERRORS++)) || true
            continue
        fi

        if bash "$SCRIPT_DIR/install.sh" "$project_path"; then
            echo -e "  ${GREEN}Updated${NC}"
            ((LOCAL_COUNT++)) || true
        else
            echo -e "  ${RED}Failed${NC}"
            ((LOCAL_ERRORS++)) || true
        fi

        echo ""
    done < "$DEPLOYMENTS_FILE"

    echo -e "${GREEN}Local: $LOCAL_COUNT updated${NC}"
    [ "$LOCAL_ERRORS" -gt 0 ] && echo -e "${RED}       $LOCAL_ERRORS failed${NC}"
    echo ""
fi

# ── GitHub deployment ─────────────────────────────────────────────────────────
# TODO: not yet implemented
# Intended to push updated skills to a GitHub repo or release so that
# projects cloning the workflow can pull updates via git.
#
# echo "→ GitHub"
# echo -e "  ${YELLOW}GitHub deployment not yet implemented — skipping${NC}"
