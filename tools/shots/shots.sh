#!/bin/sh
# The one way flare's screenshots are made.
#
# A made-up world (world.py: two Claude logins, Codex, OpenCode, a week of
# use, open sessions) is drawn by flare's own QML with no compositor at all
# (harness/, Qt's offscreen platform, at 2x), once in each theme, and framed
# (compose.py) into docs/cover.png and docs/screenshots/.
#
# Nothing on the desktop, in your config or in your real usage is read or
# touched, so the pictures never show a real project, email or number, and
# the result is the same on any machine.
#
#   tools/shots/shots.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/flare-shots"
work=$(mktemp -d)
pids=""

cleanup() {
    [ -n "$pids" ] && kill $pids 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT

for tool in qs python3 rsvg-convert curl; do
    command -v "$tool" >/dev/null 2>&1 || { echo "shots.sh: $tool is needed" >&2; exit 1; }
done
python3 -c "import PIL, numpy" 2>/dev/null || { echo "shots.sh: python3 needs Pillow and numpy" >&2; exit 1; }

[ -x "$repo/target/release/flare" ] || cargo build --release --manifest-path "$repo/Cargo.toml"

# The site's typefaces, for the cover and the captions.
mkdir -p "$cache"
fetch() {
    [ -s "$cache/$1" ] || curl -fsSL -o "$cache/$1" "https://cdn.jsdelivr.net/fontsource/fonts/$2"
}
fetch funnel-600.ttf funnel-display@latest/latin-600-normal.ttf
fetch geist-400.ttf geist-sans@latest/latin-400-normal.ttf
fetch mono-400.ttf jetbrains-mono@latest/latin-400-normal.ttf
fetch mono-500.ttf jetbrains-mono@latest/latin-500-normal.ttf
rsvg-convert -w 512 -h 512 "$repo/docs/assets/flare.svg" -o "$cache/flare-512.png"

for theme in black white; do
    world="$work/world-$theme"
    mkdir -p "$work/out/$theme"
    pids="$pids $(python3 "$here/world.py" "$world" "$theme")"
    printf '[flare]\nbinary_path = "%s/target/release/flare"\n' "$repo" >>"$world/cfg/flare/config.toml"
    (
        cd "$here/harness"
        export HOME="$world/home" XDG_CONFIG_HOME="$world/cfg" XDG_STATE_HOME="$world/state" XDG_DATA_HOME="$world/data"
        # Off Hyprland every open session counts, window or not.
        unset CLAUDE_CONFIG_DIR CODEX_HOME HYPRLAND_INSTANCE_SIGNATURE
        OUT="$work/out/$theme" QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR=2 timeout 150 qs -p "$here/harness/shell.qml"
    ) >"$work/$theme.log" 2>&1 || true
    count=$(find "$work/out/$theme" -name '*.png' | wc -l)
    if [ "$count" -lt 9 ]; then
        cat "$work/$theme.log" >&2
        echo "shots.sh: only $count of 9 $theme shots were drawn" >&2
        exit 1
    fi
done

SHOTS_CACHE="$cache" python3 "$here/compose.py" "$work/out" "$repo/docs"
