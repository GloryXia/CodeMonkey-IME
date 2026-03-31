#!/bin/bash
# hybrid_cursor_move.sh — Move cursor left or right via System Events
# Usage: hybrid_cursor_move.sh <left|right> [delay_seconds]

DIRECTION="${1:-left}"
DELAY="${2:-0.1}"

sleep "$DELAY"

if [ "$DIRECTION" = "right" ]; then
    /usr/bin/osascript -e 'tell application "System Events" to key code 124'
else
    /usr/bin/osascript -e 'tell application "System Events" to key code 123'
fi
