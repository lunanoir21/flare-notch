pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// black or white, both deliberately monochrome; a ring's own colour is a
// choice (theme.ring_color), not a fixed part of the palette — see
// ringColor() below. auto follows the system the same way Quay's own theme
// does: xdg-desktop-portal is the only outside input, and only when asked.
Singleton {
    id: theme

    // org.freedesktop.appearance color-scheme: 1 prefers dark, 2 prefers
    // light, 0 has no preference and keeps flare's black.
    property bool systemDark: true

    readonly property bool light: FlareData.themeMode === "white"
        || (FlareData.themeMode === "auto" && !theme.systemDark)

    readonly property color notch: theme.light ? "#FFFFFF" : "#000000"
    readonly property color edgeLine: theme.light ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.07)
    readonly property color ringTrack: theme.light ? Qt.rgba(0, 0, 0, 0.16) : Qt.rgba(1, 1, 1, 0.188)
    readonly property color barTrack: theme.light ? "#E2E2E2" : "#2D2D2D"
    readonly property color card: theme.light ? "#F2F2F2" : "#000000"
    // Not a ring's default colour any more (see ringColor()) — critical is
    // still the one accent a ring can take on; ample/watch remain only as
    // decorative variety in the settings page's little preview art.
    readonly property color ample: "#00FF88"
    readonly property color watch: "#F2FF00"
    readonly property color critical: "#FF3F00"
    readonly property color textPrimary: theme.light ? "#0A0A0A" : "#FFFFFF"
    readonly property color textSecondary: theme.light ? "#5A5A5A" : "#808080"
    readonly property color textSoft: theme.light ? "#3A3A3A" : "#C8C8C8"

    // The settings page: near-monochrome, colour only in the small things
    // that are colour (a provider's tint, a ring).
    readonly property color sheet: theme.light ? "#F5F6F8" : "#0A0B0D"
    readonly property color sheetRaised: theme.light ? "#EBECEF" : "#121417"
    readonly property color sheetLine: theme.light ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.08)
    readonly property color sheetText: theme.light ? "#0D0E10" : "#F2F3F5"
    readonly property color sheetSubtext: theme.light ? "#5C6066" : "#A3A8AF"
    readonly property color sheetMuted: theme.light ? "#8B8F94" : "#6B7078"
    readonly property string mono: "JetBrains Mono"

    // How a ring's arc is coloured, given its usage fraction, whether it has
    // run out, and the provider's own [aura] colour. monochrome (the
    // default): contrast only, and the accent appears just for a critical
    // state — Quay's own rule, applied here. provider: each ring simply
    // takes its provider's colour, exactly as aura style already does.
    function ringColor(usedFraction, exhausted, auraColor) {
        if (FlareData.ringColorMode === "provider")
            return auraColor;
        if (exhausted || usedFraction >= 0.9)
            return theme.critical;
        return theme.textPrimary;
    }

    // The hover card's bars always read as a traffic light, whatever the
    // rings do: a fresh limit is green, one nearly spent is red.
    readonly property color barLow: "#2BD86B"
    readonly property color barMid: "#FFB020"
    readonly property color barHigh: "#F23A12"

    function usageColor(usedFraction, exhausted) {
        if (exhausted || usedFraction >= 0.7)
            return theme.barHigh;
        if (usedFraction >= 0.5)
            return theme.barMid;
        return theme.barLow;
    }

    function logo(provider) {
        return provider ? Qt.resolvedUrl("assets/logos/" + provider + ".svg") : "";
    }

    readonly property bool followingSystem: FlareData.themeMode === "auto"
    readonly property var portalCall: ["gdbus", "call", "--session",
        "--dest", "org.freedesktop.portal.Desktop",
        "--object-path", "/org/freedesktop/portal/desktop",
        "--method", "org.freedesktop.portal.Settings.ReadOne",
        "org.freedesktop.appearance", "color-scheme"]

    function applyScheme(text) {
        let match = String(text || "").match(/uint32 (\d)/);
        if (match) theme.systemDark = match[1] !== "2";
    }

    Process {
        running: theme.followingSystem
        command: theme.portalCall
        stdout: StdioCollector {
            onStreamFinished: theme.applyScheme(this.text)
        }
    }

    // Changes arrive as SettingChanged signals; only this key matters.
    Process {
        running: theme.followingSystem
        command: ["gdbus", "monitor", "--session",
            "--dest", "org.freedesktop.portal.Desktop",
            "--object-path", "/org/freedesktop/portal/desktop"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("'org.freedesktop.appearance', 'color-scheme'") !== -1)
                    theme.applyScheme(line);
            }
        }
    }
}
