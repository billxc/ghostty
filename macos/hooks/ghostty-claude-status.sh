#!/bin/bash
# Ghostty Claude Status Hook
# Sends Claude Code lifecycle events to the Ghostty instance that
# launched this terminal, identified by GHOSTTY_SOCKET and GHOSTTY_TAB_ID
# environment variables injected at tab creation time.
#
# Called by Claude Code with JSON on stdin containing hook_event_name.

# Skip if not launched from Ghostty (no env vars)
[ -z "$GHOSTTY_SOCKET" ] || [ -z "$GHOSTTY_TAB_ID" ] && exit 0

# Skip if socket doesn't exist (Ghostty closed)
[ -S "$GHOSTTY_SOCKET" ] || exit 0

# Read JSON input from stdin
INPUT=$(cat)

# Extract event type
EVENT_TYPE=$(echo "$INPUT" | grep -oE '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"$' | tr -d '"')
[ -z "$EVENT_TYPE" ] && exit 0

# Map Claude Code events to Ghostty status events
case "$EVENT_TYPE" in
    UserPromptSubmit)
        GHOSTTY_EVENT="Start"
        ;;
    Stop|SubagentStop)
        GHOSTTY_EVENT="Stop"
        ;;
    PermissionRequest)
        GHOSTTY_EVENT="PermissionRequest"
        ;;
    *)
        exit 0
        ;;
esac

# Send to the specific Ghostty socket (non-blocking, ignore errors)
printf '{"event":"%s","tabId":"%s"}' "$GHOSTTY_EVENT" "$GHOSTTY_TAB_ID" \
    | nc -U -w1 "$GHOSTTY_SOCKET" 2>/dev/null

exit 0
