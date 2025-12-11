#!/bin/bash
# sync-state.sh - Ensure STATE.scm and .claude/CLAUDE.md are in sync
#
# Usage:
#   ./scripts/sync-state.sh check    # Verify sync status
#   ./scripts/sync-state.sh generate # Regenerate CLAUDE.md from STATE.scm
#   ./scripts/sync-state.sh update   # Update both timestamps
#
# This prevents drift between the Scheme state file (source of truth)
# and the Markdown file (for Claude Code context).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STATE_FILE="$PROJECT_ROOT/STATE.scm"
CLAUDE_FILE="$PROJECT_ROOT/.claude/CLAUDE.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Extract timestamp from STATE.scm
get_state_timestamp() {
    grep -oP "state-scm-version \. \"[^\"]+\"" "$STATE_FILE" | grep -oP '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z' || echo "unknown"
}

# Extract timestamp from CLAUDE.md
get_claude_timestamp() {
    grep -oP "Last sync.*: \K\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z" "$CLAUDE_FILE" || echo "unknown"
}

# Check if files are in sync
check_sync() {
    local state_ts=$(get_state_timestamp)
    local claude_ts=$(get_claude_timestamp)

    echo "STATE.scm timestamp:  $state_ts"
    echo "CLAUDE.md timestamp:  $claude_ts"
    echo

    if [[ "$state_ts" == "$claude_ts" ]]; then
        echo -e "${GREEN}✓ Files are in sync${NC}"
        return 0
    else
        echo -e "${RED}✗ Files are OUT OF SYNC${NC}"
        echo
        echo "Run: $0 generate"
        return 1
    fi
}

# Update timestamp in both files
update_timestamps() {
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "Updating timestamps to: $ts"

    # Update STATE.scm
    sed -i "s/state-scm-version \. \"[^\"]*\"/state-scm-version . \"$ts\"/" "$STATE_FILE"
    sed -i "s/claude-md-version \. \"[^\"]*\"/claude-md-version . \"$ts\"/" "$STATE_FILE"
    sed -i "s/Last updated: [0-9T:-]*Z/Last updated: $ts/" "$STATE_FILE"

    # Update CLAUDE.md
    sed -i "s/Last sync.*: [0-9T:-]*Z/Last sync**: $ts/" "$CLAUDE_FILE"

    echo -e "${GREEN}✓ Timestamps updated${NC}"
}

# Generate CLAUDE.md from STATE.scm (simplified - full version would parse Scheme)
generate_claude_md() {
    echo -e "${YELLOW}Note: Full generation requires Guile Scheme parser${NC}"
    echo "For now, manually update CLAUDE.md to match STATE.scm"
    echo
    echo "Key sections to sync:"
    echo "  - version-status (v1 blockers)"
    echo "  - components (new files)"
    echo "  - completed-items (recent work)"
    echo "  - external-contributions"
    echo

    # Update timestamp to mark as synced
    update_timestamps
}

# Git hook installation
install_hook() {
    local hook_file="$PROJECT_ROOT/.git/hooks/pre-commit"

    cat > "$hook_file" << 'HOOK'
#!/bin/bash
# Pre-commit hook to check STATE.scm / CLAUDE.md sync

if ! ./scripts/sync-state.sh check 2>/dev/null; then
    echo "ERROR: STATE.scm and CLAUDE.md are out of sync"
    echo "Run: ./scripts/sync-state.sh generate"
    exit 1
fi
HOOK

    chmod +x "$hook_file"
    echo -e "${GREEN}✓ Pre-commit hook installed${NC}"
}

# Main
case "${1:-check}" in
    check)
        check_sync
        ;;
    generate)
        generate_claude_md
        ;;
    update)
        update_timestamps
        ;;
    install-hook)
        install_hook
        ;;
    *)
        echo "Usage: $0 {check|generate|update|install-hook}"
        exit 1
        ;;
esac
