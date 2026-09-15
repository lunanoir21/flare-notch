pragma Singleton

import QtQuick
import Quickshell

// Colours sampled from Codenotch's design frame, which wins over the hexes in
// its written spec.
Singleton {
    id: theme

    readonly property color notch: "#000000"
    readonly property color edgeLine: Qt.rgba(1, 1, 1, 0.07)
    readonly property color ringTrack: Qt.rgba(1, 1, 1, 0.188)
    readonly property color barTrack: "#2d2d2d"
    readonly property color card: "#0a0a0a"
    readonly property color ample: "#00FF88"
    readonly property color watch: "#F2FF00"
    readonly property color critical: "#FF3F00"
    readonly property color textPrimary: "#FFFFFF"
    readonly property color textSecondary: "#808080"
    readonly property color textSoft: "#C8C8C8"

    // The settings page: near-black and monochrome, colour only in the small
    // things that are colour (a provider's tint, a ring).
    readonly property color sheet: "#0A0B0D"
    readonly property color sheetRaised: "#121417"
    readonly property color sheetLine: Qt.rgba(1, 1, 1, 0.08)
    readonly property color sheetText: "#F2F3F5"
    readonly property color sheetSubtext: "#A3A8AF"
    readonly property color sheetMuted: "#6B7078"
    readonly property string mono: "JetBrains Mono"

    // The frame shows 21% green, 52% yellow and 73% orange, so yellow ends at
    // 70, not at the spec table's 80.
    function bandColor(usedFraction) {
        if (usedFraction < 0.5)
            return theme.ample;
        if (usedFraction < 0.7)
            return theme.watch;
        return theme.critical;
    }

    function logo(provider) {
        return provider ? Qt.resolvedUrl("assets/logos/" + provider + ".svg") : "";
    }
}
