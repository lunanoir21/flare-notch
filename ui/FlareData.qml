pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Runs the flare binary for readings and for the config, writes the config
// through `flare config set`, and turns the JSON into what the views draw.
Singleton {
    id: root

    // Both halves, once, regardless of whether anything is on screen yet —
    // the poll timer below only keeps usage current after this; it does not
    // replace this first read, or a hover reveal's first paint would be
    // empty.
    Component.onCompleted: root.refresh(false)

    property var providers: []
    property var config: null
    property var order: ["claude", "codex", "opencode", "cursor"]
    property string configPath: ""
    property string configProblem: ""
    property string lastError: ""
    property bool ready: false

    property string focusId: ""
    property bool compactOpen: false
    property bool settingsOpen: false
    // Live values while a settings slider is being dragged; NaN when not.
    property real previewOffset: NaN
    property real previewScale: NaN
    property real previewGap: NaN

    property real now: Date.now() / 1000

    readonly property var section: name => root.config && root.config[name] ? root.config[name] : ({})
    readonly property string themeMode: section("theme").mode || "black"
    readonly property string ringColorMode: section("theme").ring_color || "monochrome"
    readonly property string style: section("notch").style || "classic"
    readonly property string notchEdge: section("notch").edge || "left"
    readonly property real notchOffset: section("notch").offset || 0
    readonly property real scale: isNaN(previewScale) ? (section("notch").scale || 1) : previewScale
    readonly property string screen: section("notch").screen || ""
    readonly property string compactEdge: section("compact").edge || "top"
    readonly property real compactOffset: section("compact").offset || 0
    readonly property string openOn: section("compact").open_on || "click"
    readonly property string mount: section("notch").mount || "bridge"
    readonly property real gap: isNaN(previewGap) ? (section("notch").gap ?? 8) : previewGap
    readonly property string reveal: section("notch").reveal || "always"
    readonly property int revealDelay: section("notch").reveal_delay_ms ?? 80
    readonly property int hideDelay: section("notch").hide_delay_ms ?? 400
    // Brought on screen by a shortcut (every screen at once); hover reveals
    // are kept per screen by the host.
    property bool shown: false
    // Set by a manual hide while the pointer is still at the edge, so the same
    // pointer does not bring it straight back.
    property bool hoverSuppressed: false

    // How many of the per-screen windows currently have their body on
    // screen (hover reveals are decided per screen, in the host). The poll
    // timer above reads this; each window syncs it through noteVisible().
    property int visibleWindows: 0

    function noteVisible(visible) {
        root.visibleWindows += visible ? 1 : -1;
    }

    onRevealChanged: {
        shown = false;
        hoverSuppressed = false;
    }
    readonly property string dataMode: section("data").mode || "official"
    readonly property int pollMs: Math.max(5, section("poll").interval_secs || 30) * 1000

    readonly property var names: ({
            claude: "Claude",
            codex: "Codex",
            cursor: "Cursor",
            opencode: "OpenCode"
        })
    readonly property var defaultColours: ({
            claude: "#D97757",
            codex: "#6E7BFF",
            cursor: "#3DD6C6",
            opencode: "#C9CED6"
        })
    readonly property var usagePages: ({
            claude: "https://claude.ai/settings/usage",
            codex: "https://chatgpt.com/codex/settings/usage",
            cursor: "https://cursor.com/dashboard?tab=usage"
        })

    // One entry per drawn provider, everything a delegate needs precomputed.
    readonly property var cells: {
        const out = [];
        for (const id of root.order) {
            // Switched off counts at once, not at the next reading.
            if (root.section("providers")[id] === false)
                continue;
            const p = root.providers.find(entry => entry.provider === id);
            if (!p || p.status === "absent")
                continue;
            const head = p.windows.find(w => w.id === p.headline) || p.windows[0] || null;
            const blocked = p.status === "needs_auth" || p.status === "error" || p.status === "backoff" || p.status === "needs_consent";
            const used = head && !blocked ? head.used : null;
            let label = "—";
            if (!p.metered)
                label = Strings.tokens(p.tokens_today);
            else if (used !== null)
                label = Strings.percent(used);
            out.push({
                id: id,
                name: root.names[id] || id,
                metered: p.metered,
                used: used,
                head: head,
                windows: p.windows,
                status: p.status,
                note: p.note || "",
                plan: p.plan || "",
                tokens: p.tokens_today,
                fetchedAt: p.fetched_at,
                fraction: p.metered ? (used === null ? 0 : used) : 1,
                arcColor: p.metered
                    ? Theme.ringColor(used === null ? 0 : used, used !== null && used >= 1, root.auraColour(id))
                    : Theme.textSecondary,
                exhausted: used !== null && used >= 1,
                dimmed: p.metered && (used === null || p.status === "stale" || (head !== null && head.reset_elapsed)),
                label: label,
                aura: root.auraColour(id)
            });
        }
        return out;
    }

    readonly property var focusedCell: cells.find(c => c.id === focusId) || cells[0] || null

    // A provider whose official-mode read needs a one-time yes before it
    // happens (Cursor's live session cookie, so far the only one). Surfaced
    // once; declining or granting clears it for good.
    readonly property var consentCell: cells.find(c => c.status === "needs_consent") || null

    function cellFor(id) {
        return cells.find(c => c.id === id) || null;
    }

    function auraColour(id) {
        const colours = section("aura");
        return colours[id] || defaultColours[id] || "#808080";
    }

    function step(direction) {
        if (cells.length === 0)
            return;
        const index = Math.max(0, cells.findIndex(c => focusedCell && c.id === focusedCell.id));
        focusId = cells[(index + direction + cells.length) % cells.length].id;
    }

    function focusOn(id) {
        focusId = id;
    }

    function toggleCompact() {
        compactOpen = !compactOpen;
    }

    // Nothing to bring back in "always", so it stays put there.
    function toggleVisible() {
        if (reveal === "always")
            return;
        if (shown)
            hideWidget();
        else
            shown = true;
    }

    function hideWidget() {
        if (reveal === "always")
            return;
        if (reveal === "hover")
            hoverSuppressed = true;
        shown = false;
    }

    function openUsagePage(id) {
        if (usagePages[id])
            Qt.openUrlExternally(usagePages[id]);
    }

    // Every provider id, in order, including disabled ones, for the settings page.
    function allIds() {
        const out = order.slice();
        for (const id of ["claude", "codex", "opencode", "cursor"])
            if (out.indexOf(id) < 0)
                out.push(id);
        return out;
    }

    function move(id, direction) {
        const ids = allIds();
        const index = ids.indexOf(id), other = index + direction;
        if (index < 0 || other < 0 || other >= ids.length)
            return;
        [ids[index], ids[other]] = [ids[other], ids[index]];
        set("providers.order", ids);
    }

    // ---------------- running flare ----------------

    readonly property string moduleDir: {
        const dir = decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""));
        return dir.endsWith("/") ? dir : dir + "/";
    }
    readonly property string homeDir: Quickshell.env("HOME") || ""

    // Quickshell started by the compositor may not inherit the login shell's
    // PATH, so the build beside this module and the usual install directories
    // are tried as well as a PATH lookup.
    readonly property var candidates: {
        const list = [];
        const override = section("flare").binary_path;
        if (override)
            list.push(override);
        list.push(root.moduleDir + "../target/release/flare", "flare", root.homeDir + "/.local/bin/flare", root.homeDir + "/.cargo/bin/flare");
        return list;
    }

    // One shell resolves the binary: a Process whose program is missing never
    // reports an exit code, so there would be nothing to fall back from.
    readonly property string resolver: 'mode=$1; key=$2; value=$3; shift 3; '
        + 'for c in "$@"; do '
        + '  case $c in */*) [ -x "$c" ] || continue ;; *) command -v "$c" >/dev/null 2>&1 || continue ;; esac; '
        + '  case $mode in '
        + '    config) exec "$c" config get ;; '
        + '    set) exec "$c" config set "$key" "$value" ;; '
        + '    *) exec "$c" --provider all --format json ${key:+"$key"} ;; '
        + '  esac; '
        + 'done; exit 127'

    function command(mode, key, value) {
        return ["sh", "-c", root.resolver, "sh", mode, key || "", value || ""].concat(root.candidates);
    }

    function refreshConfig() {
        if (!configReader.running) {
            configReader.command = command("config");
            configReader.running = true;
        }
    }

    property real lastUsageAt: 0

    function refreshUsage(force) {
        if (!usageReader.running) {
            root.lastUsageAt = Date.now();
            usageReader.command = command("usage", force ? "--refresh" : "");
            usageReader.running = true;
        }
    }

    // Both at once — a config change can also mean different providers or a
    // different data.mode, so a manual "read now" (the IPC call, the
    // settings page's button) still wants both. The poll timer and the
    // config file watcher below each want only their own half.
    function refresh(force) {
        refreshConfig();
        refreshUsage(force);
    }

    property var pending: []
    // A provider switched back on has no reading yet: read once the write lands.
    property bool refreshAfterSet: false

    // Applied at once so the widget answers immediately, then written through
    // `flare config set`, whose reply becomes the truth.
    function set(key, value) {
        applyLocal(key, value);
        if (key.startsWith("providers."))
            refreshAfterSet = true;
        const text = Array.isArray(value) ? value.join(",") : String(value);
        pending = pending.filter(item => item[0] !== key).concat([[key, text]]);
        pump();
    }

    function applyLocal(key, value) {
        if (!config)
            return;
        const parts = key.split(".");
        const next = JSON.parse(JSON.stringify(config));
        next[parts[0]] = next[parts[0]] || {};
        next[parts[0]][parts[1]] = value;
        config = next;
        if (key === "providers.order")
            order = value;
    }

    function pump() {
        if (setter.running || pending.length === 0)
            return;
        const [key, value] = pending[0];
        pending = pending.slice(1);
        setter.command = command("set", key, value);
        setter.running = true;
    }

    function takeConfig(text) {
        const answer = JSON.parse(text);
        root.config = answer.config;
        root.order = answer.order;
        root.configPath = answer.path;
        root.configProblem = answer.problem || "";
    }

    Process {
        id: usageReader

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "")
                    return;
                try {
                    root.providers = JSON.parse(text);
                    root.lastError = "";
                    root.ready = true;
                } catch (e) {
                    root.lastError = "The program that answered is not flare.";
                }
            }
        }
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode === 127) {
                root.lastError = "flare was not found. Build it with cargo build --release.";
                console.warn("flare:", root.lastError);
            }
        }
    }

    Process {
        id: configReader

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && root.pending.length === 0 && !setter.running) {
                    try {
                        root.takeConfig(text);
                    } catch (e) {
                        root.configProblem = "Could not read the effective config.";
                    }
                }
            }
        }
        stderr: StdioCollector {}
    }

    Process {
        id: setter

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "")
                    return;
                try {
                    root.takeConfig(text);
                } catch (e) {}
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message !== "") {
                    root.configProblem = message.replace(/^Error:\s*/, "");
                    console.warn("flare config:", message);
                }
            }
        }
        onExited: {
            root.previewOffset = NaN;
            root.previewScale = NaN;
            root.previewGap = NaN;
            if (root.refreshAfterSet && root.pending.length === 0) {
                root.refreshAfterSet = false;
                root.refreshUsage(false);
            }
            root.pump();
        }
    }

    FileView {
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: root.refreshConfig()
    }

    // Quiet while nothing is on screen to show a fresh number for: every
    // tick otherwise spawns a flare process (and, for providers with no
    // caching of their own, real file/database reads) whether or not
    // anyone is looking. "always" is always on screen by definition;
    // "shortcut" and "hover" register through noteVisible() below.
    // Turning running back on fires immediately (triggeredOnStart), but
    // only reads if the last reading is at least an interval old — so
    // hovering in and out every few seconds doesn't spawn a read (or, in
    // official mode, an API call) each time.
    Timer {
        interval: root.pollMs
        running: root.reveal === "always" || root.visibleWindows > 0 || root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (Date.now() - root.lastUsageAt >= root.pollMs - 1000)
                root.refreshUsage(false);
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.now = Date.now() / 1000
    }
}
