import QtQuick

// A thin strip welded to the top or bottom edge. A tap (or hover, if set)
// grows it into a panel with one row per provider.
Item {
    id: view

    required property string edge
    required property real size
    property string mount: "bridge"
    property real edgeGap: 0

    readonly property bool open: FlareData.compactOpen
    readonly property bool atTop: edge !== "bottom"
    readonly property real stripHeight: 34 * size
    readonly property real flare: 16 * size
    readonly property real corner: 14 * size
    readonly property real sidePad: 22 * size
    readonly property real inset: mount === "floating" ? edgeGap : 0
    readonly property real ends: mount === "bridge" ? flare : 0
    readonly property real length: Math.max(strip.implicitWidth, panel.width) + 2 * ends + 2 * sidePad
    readonly property real fullDepth: stripHeight + panel.implicitHeight + 8 * size
    // The session lists at their open height, not their animated one.
    readonly property real sessionsSlack: {
        let slack = 0;
        for (let i = 0; i < sessionLists.count; i++) {
            const item = sessionLists.itemAt(i);
            if (item)
                slack += item.expandedHeight - item.height;
        }
        return slack;
    }
    // What the surface has to hold when open: the gap, a flush strip's flare,
    // and room for every session list fully open. Reserving that up front
    // keeps the layer surface from resizing on every frame of a fold.
    readonly property real fullReach: fullDepth + sessionsSlack + inset + (mount === "flush" ? 18 * size : 0)
    readonly property real bodyDepth: depth
    // Only opening and closing animate here. Once open, the body follows
    // fullDepth directly, so the session list's own fold is the one
    // animation instead of the body chasing it a step behind.
    property real progress: open ? 1 : 0
    readonly property real depth: stripHeight + (fullDepth - stripHeight) * progress

    Behavior on progress {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    implicitWidth: length
    implicitHeight: depth + inset
    // The panel is laid out at full size and revealed as the body grows.
    clip: true

    NotchShape {
        anchors.fill: parent
        visible: view.mount !== "flush"
        edge: view.edge
        mount: view.mount
        depth: view.depth
        length: view.length
        gap: view.inset
        flare: view.flare
        corner: view.mount === "floating" ? 17 * view.size : view.corner
    }

    Row {
        id: strip

        anchors.horizontalCenter: parent.horizontalCenter
        y: view.atTop ? view.inset : view.depth - view.stripHeight
        height: view.stripHeight
        spacing: 14 * view.size

        Repeater {
            model: FlareData.cells

            Row {
                id: chip

                required property var modelData

                anchors.verticalCenter: parent.verticalCenter
                spacing: 6 * view.size
                Accessible.role: Accessible.StaticText
                Accessible.name: modelData.name + ": " + modelData.label

                ProviderRing {
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 18 * view.size
                    trackWidth: 2.5 * view.size
                    arcWidth: 2.5 * view.size
                    logoSize: 10 * view.size
                    fraction: chip.modelData.fraction
                    arcColor: chip.modelData.arcColor
                    provider: chip.modelData.id
                    dimmed: chip.modelData.dimmed
                    exhausted: chip.modelData.exhausted
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const main = Strings.ringMain(chip.modelData, FlareData.ringLabel, FlareData.now);
                        const sub = Strings.ringSub(chip.modelData, FlareData.ringLabel, FlareData.now);
                        return sub ? main + " · " + sub : main;
                    }
                    color: chip.modelData.dimmed ? Theme.textSecondary : Theme.textPrimary
                    font.pixelSize: Math.max(9, Math.round(12.5 * view.size))
                    font.weight: Font.Medium
                    font.features: {
                        "tnum": 1
                    }
                }
            }
        }

        TapHandler {
            enabled: FlareData.openOn === "click"
            onTapped: FlareData.toggleCompact()
        }
    }

    Column {
        id: panel

        anchors.horizontalCenter: parent.horizontalCenter
        y: view.atTop ? view.inset + view.stripHeight : view.depth - view.stripHeight - implicitHeight - 8 * view.size
        width: 292 * view.size
        opacity: view.open ? 1 : 0
        visible: view.depth > view.stripHeight + 1

        Behavior on opacity {
            OpacityAnimator {
                duration: 140
            }
        }

        Repeater {
            model: FlareData.cells

            Item {
                id: row

                required property var modelData
                required property int index

                width: panel.width
                height: 50 * view.size
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name + ": " + modelData.label

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.06)
                    visible: row.index > 0
                }

                Image {
                    x: 6 * view.size
                    y: 10 * view.size
                    width: 16 * view.size
                    height: 16 * view.size
                    source: Theme.logo(row.modelData.id)
                    sourceSize: Qt.size(Math.ceil(32 * view.size), Math.ceil(32 * view.size))
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Text {
                    x: 32 * view.size
                    y: 9 * view.size
                    text: row.modelData.name
                    color: Theme.textPrimary
                    font.pixelSize: Math.max(9, Math.round(13 * view.size))
                    font.weight: Font.Medium
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 6 * view.size
                    y: 9 * view.size
                    text: row.modelData.label
                    color: row.modelData.dimmed ? Theme.textSecondary : Theme.textPrimary
                    font.pixelSize: Math.max(9, Math.round(13 * view.size))
                    font.weight: Font.Medium
                    font.features: {
                        "tnum": 1
                    }
                }

                Rectangle {
                    x: 32 * view.size
                    y: 30 * view.size
                    width: parent.width - 38 * view.size
                    height: 4 * view.size
                    radius: height / 2
                    color: Theme.barTrack
                    visible: row.modelData.metered

                    Rectangle {
                        width: parent.width * (row.modelData.used || 0)
                        height: parent.height
                        radius: parent.radius
                        color: row.modelData.arcColor
                    }
                }

                Text {
                    x: 32 * view.size
                    y: row.modelData.metered ? 37 * view.size : 30 * view.size
                    text: {
                        const cell = row.modelData;
                        if (!cell.metered)
                            return cell.todayText;
                        if (!cell.head)
                            return Strings.status(cell.status) || Strings.noReading;
                        return Strings.windowLabel(cell.head.label) + " · " + Strings.resetText(cell.head.resets_at, FlareData.now, cell.head.reset_elapsed);
                    }
                    color: Theme.textSecondary
                    font.pixelSize: Math.max(8, Math.round(10.5 * view.size))
                }

                TapHandler {
                    onTapped: FlareData.openUsagePage(row.modelData.id)
                }
            }
        }

        Repeater {
            id: sessionLists

            model: FlareData.cells.filter(c => c.sessions && c.sessions.length > 0)

            SessionList {
                required property var modelData

                width: panel.width
                sessions: modelData.sessions
                provider: modelData.id
                label: sessionLists.count > 1 ? Strings.sessionsOf(modelData.name) : Strings.sessions
                s: view.size
                live: view.open
            }
        }
    }

    HoverHandler {
        enabled: FlareData.openOn === "hover"
        onHoveredChanged: {
            if (hovered) {
                closeTimer.stop();
                FlareData.compactOpen = true;
            } else {
                closeTimer.restart();
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 250
        onTriggered: FlareData.compactOpen = false
    }
}
