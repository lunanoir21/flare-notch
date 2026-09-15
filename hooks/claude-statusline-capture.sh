#!/usr/bin/env bash
# flare: persist the status line payload that Claude Code pipes on stdin.
#
# Claude Code keeps its 5-hour and 7-day rate-limit percentages in memory and
# hands them to the status line command; no file under ~/.claude carries them.
# This wrapper writes that payload to the flare state directory and then
# delegates to the real status line command unchanged.
#
# Constraints this script honors:
#   - no network access
#   - never writes to Claude Code's own files
#   - a capture failure must never break or delay the status line
#   - stdout carries only what the delegate prints
#
# The delegate is, in order of precedence:
#   1. the arguments to this script, run as a command:
#        claude-statusline-capture.sh npx -y @owloops/claude-powerline@latest
#   2. $FLARE_STATUSLINE_DELEGATE, a file run with bash or a shell command
#   3. ~/.claude/statusline-command.sh, if it exists
# With none of them, the capture happens and nothing is printed.

set -u

input=$(cat)

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/flare"
capture="$state_dir/claude-statusline.json"

# Best effort. Every failure path falls through to the delegate.
if mkdir -p "$state_dir" 2>/dev/null; then
    if tmp=$(mktemp "$state_dir/.claude-statusline.XXXXXX" 2>/dev/null); then
        if printf '%s\n' "$input" >"$tmp" 2>/dev/null; then
            chmod 600 "$tmp" 2>/dev/null
            mv -f "$tmp" "$capture" 2>/dev/null || rm -f "$tmp" 2>/dev/null
        else
            rm -f "$tmp" 2>/dev/null
        fi
    fi
fi

if [ "$#" -gt 0 ]; then
    exec "$@" <<EOF
$input
EOF
fi

delegate="${FLARE_STATUSLINE_DELEGATE:-$HOME/.claude/statusline-command.sh}"
if [ -r "$delegate" ]; then
    exec bash "$delegate" <<EOF
$input
EOF
elif [ -n "${FLARE_STATUSLINE_DELEGATE:-}" ]; then
    exec sh -c "$FLARE_STATUSLINE_DELEGATE" <<EOF
$input
EOF
fi

exit 0
