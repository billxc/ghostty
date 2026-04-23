#!/bin/bash
# Test Ghostty Claude Status integration.
# Run this INSIDE a Claude tab launched from Ghostty's QuickLaunchBar.
set -e

if [ -z "$GHOSTTY_SOCKET" ] || [ -z "$GHOSTTY_TAB_ID" ]; then
    echo "ERROR: Not in a Ghostty Claude tab."
    echo "  GHOSTTY_SOCKET=$GHOSTTY_SOCKET"
    echo "  GHOSTTY_TAB_ID=$GHOSTTY_TAB_ID"
    echo ""
    echo "Launch a tab from QuickLaunchBar first, then run this script there."
    exit 1
fi

echo "Socket: $GHOSTTY_SOCKET"
echo "Tab ID: $GHOSTTY_TAB_ID"
echo ""

send() {
    printf '{"event":"%s","tabId":"%s"}' "$1" "$GHOSTTY_TAB_ID" \
        | nc -U -w1 "$GHOSTTY_SOCKET" 2>/dev/null
    echo "Sent: $1"
}

echo "==> Sending Start (should show orange pulsing dot)"
send "Start"
sleep 3

echo "==> Sending Stop (should show green dot + beep)"
send "Stop"
sleep 3

echo "==> Sending Start again"
send "Start"
sleep 2

echo "==> Sending PermissionRequest (should show red dot + beep)"
send "PermissionRequest"
sleep 3

echo "==> Sending SessionEnd (should clear)"
send "SessionEnd"

echo ""
echo "Done! Check sidebar and tab bar for status changes."
