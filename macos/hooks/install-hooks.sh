#!/bin/bash
# Install Ghostty Claude Status hooks into ~/.claude/settings.json
# Adds hook commands alongside any existing hooks.
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

HOOK_CMD="$HOOK_SCRIPT"

# For each event type, add a hook entry if not already present
for EVENT in UserPromptSubmit Stop PermissionRequest; do
    # Check if our hook is already installed
    if jq -e ".hooks.${EVENT}[]?.hooks[]? | select(.command == \"$HOOK_CMD\")" "$SETTINGS" >/dev/null 2>&1; then
        echo "Hook for $EVENT already installed, skipping"
        continue
    fi

    # Add our hook to the event's array
    ENTRY="{\"hooks\":[{\"type\":\"command\",\"command\":\"$HOOK_CMD\"}]}"
    if [ "$EVENT" = "PermissionRequest" ]; then
        ENTRY="{\"matcher\":\"*\",\"hooks\":[{\"type\":\"command\",\"command\":\"$HOOK_CMD\"}]}"
    fi

    jq ".hooks.${EVENT} = (.hooks.${EVENT} // []) + [$ENTRY]" "$SETTINGS" > "${SETTINGS}.tmp"
    mv "${SETTINGS}.tmp" "$SETTINGS"
    echo "Installed hook for $EVENT"
done

echo "Done! Restart Claude Code for hooks to take effect."
