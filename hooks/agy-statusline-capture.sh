#!/usr/bin/env bash
# flare: persist the status line payload that the Antigravity CLI (agy) pipes
# on stdin.
#
# agy keeps each model's quota in memory and hands it to the status line
# command; nothing on disk carries it. This wrapper writes that payload to the
# flare state directory and then delegates to a real status line command, if
# there is one.
#
# Constraints this script honors:
#   - no network access
#   - never writes to agy's own files
#   - a capture failure must never break or delay the status line
#   - stdout carries only what the delegate prints
#
# The delegate is, in order of precedence:
#   1. the arguments to this script, run as a command
#   2. $FLARE_AGY_STATUSLINE_DELEGATE, a file run with bash or a shell command
# With neither, the capture happens and nothing is printed; set
# "stack_with_default": true in agy's statusLine setting to keep its own line.

set -u

input=$(cat)

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/flare"
capture="$state_dir/agy-statusline.json"

if mkdir -p "$state_dir" 2>/dev/null; then
    if tmp=$(mktemp "$state_dir/.agy-statusline.XXXXXX" 2>/dev/null); then
        if printf '%s\n' "$input" >"$tmp" 2>/dev/null; then
            chmod 600 "$tmp" 2>/dev/null
            mv -f "$tmp" "$capture" 2>/dev/null || rm -f "$tmp" 2>/dev/null
        else
            rm -f "$tmp" 2>/dev/null
        fi
    fi
fi

if [ "$#" -gt 0 ]; then
    printf '%s\n' "$input" | exec "$@"
fi

delegate="${FLARE_AGY_STATUSLINE_DELEGATE:-}"
if [ -n "$delegate" ] && [ -r "$delegate" ]; then
    printf '%s\n' "$input" | exec bash "$delegate"
elif [ -n "$delegate" ]; then
    printf '%s\n' "$input" | exec sh -c "$delegate"
fi

exit 0
