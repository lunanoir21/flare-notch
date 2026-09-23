#!/bin/sh
# Opens flare's settings page in whichever Quickshell instance has flare loaded,
# starting the widget on its own first when none does. install.sh fills in @UI_DIR@.
ui_dir="@UI_DIR@"

qs_bin=$(command -v qs || command -v quickshell) || {
    echo "flare-settings: Quickshell (qs) is not installed" >&2
    exit 1
}

open_in_running() {
    for pid in $("$qs_bin" list --all --json 2>/dev/null | grep -o '"pid": *[0-9]*' | grep -o '[0-9]*$'); do
        if "$qs_bin" ipc --pid "$pid" show 2>/dev/null | grep -q '^target flare$'; then
            "$qs_bin" ipc --pid "$pid" call flare openSettings >/dev/null 2>&1 && return 0
        fi
    done
    return 1
}

open_in_running && exit 0

setsid -f "$qs_bin" -p "$ui_dir" >/dev/null 2>&1
i=0
while [ "$i" -lt 50 ]; do
    sleep 0.1
    open_in_running && exit 0
    i=$((i + 1))
done
echo "flare-settings: the widget did not start; try: $qs_bin -p $ui_dir" >&2
exit 1
