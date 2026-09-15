import QtQuick

// A thin strip welded to the top or bottom edge. A tap (or hover, if set)
// grows it into a panel with one row per provider.
Item {
    id: view

    required property string edge
    required property real size

    readonly property bool open: FlareData.compactOpen
    readonly property bool atTop: edge !== "bottom"
    readonly property real stripHeight: 34 * size
    readonly property real flare: 16 * size
    readonly property real corner: 14 * size
    readonly property real sidePad: 22 * size
    readonly property real length: Math.max(strip.implicitWidth, panel.width) + 2 * flare + 2 * sidePad
    readonly property real fullDepth: stripHeight + panel.implicitHeight + 8 * size
    property real depth: open ? fullDepth : stripHeight

    Behavior on depth {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }
    }

    implicitWidth: length
    implicitHeight: depth
    // The panel is laid out at full size and revealed as the body grows.
    clip: true

    NotchShape {
        anchors.fill: parent
        edge: view.edge
        depth: view.depth
        length: view.length
        flare: view.flare
        corner: view.corner
    }

    Row {
        id: strip

        anchors.horizontalCenter: parent.horizontalCenter
        y: view.atTop ? 0 : view.depth - view.stripHeight
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
                    text: chip.modelData.label
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
        y: view.atTop ? view.stripHeight : view.depth - view.stripHeight - implicitHeight - 8 * view.size
        width: 292 * view.size
        opacity: view.open ? 1 : 0
        visible: view.depth > view.stripHeight + 1

        Behavior on opacity {
            OpacityAnimator {
                duration: 180
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
                            return Strings.tokensToday(cell.tokens);
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
