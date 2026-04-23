#!/bin/bash
# Uninstall Ghostty Claude Status hooks from ~/.claude/settings.json
set -e

HOOK_SCRIPT="$(cd "$(dirname "$0")" && pwd)/ghostty-claude-status.sh"
SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
    echo "ERROR: $SETTINGS not found"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required. Install with: brew install jq"
    exit 1
fi

for EVENT in UserPromptSubmit Stop PermissionRequest; do
    jq --arg cmd "$HOOK_SCRIPT" \
        "if .hooks.${EVENT} then .hooks.${EVENT} |= map(select((.hooks // []) | all(.command != \$cmd))) else . end" \
        "$SETTINGS" > "${SETTINGS}.tmp"
    mv "${SETTINGS}.tmp" "$SETTINGS"
    echo "Removed hook for $EVENT"
done

echo "Done! Restart Claude Code for changes to take effect."
