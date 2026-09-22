import QtQuick
import QtQuick.Shapes

// The hover card's folding list of open sessions. Clicking a row brings its
// terminal to the front.
Column {
    id: list

    required property var sessions
    required property string provider
    required property real s
    // Whether the card is on screen at all: nothing animates otherwise.
    property bool live: true

    readonly property bool open: FlareData.sessionsOpen
    readonly property int waiting: sessions.filter(session => session.state === "waiting").length
    // Its height with the list open, whatever it is now: a host whose own
    // surface must fit it can reserve this once instead of resizing per frame.
    readonly property real expandedHeight: 1 + header.height + rows.implicitHeight + 4 * s

    spacing: 0

    Rectangle {
        width: list.width
        height: 1
        color: Theme.divider
    }

    Item {
        id: header

        width: list.width
        height: 34 * list.s

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -6 * list.s
            anchors.rightMargin: -6 * list.s
            anchors.topMargin: 4 * list.s
            radius: 8 * list.s
            color: headerHover.hovered ? Theme.rowHover : "transparent"
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2 * list.s
            spacing: 8 * list.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Strings.sessions
                color: Theme.textPrimary
                font.pixelSize: Math.round(13 * list.s)
                font.weight: Font.Medium
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                height: 18 * list.s
                width: Math.max(height, countText.implicitWidth + 12 * list.s)
                radius: height / 2
                color: list.waiting > 0 ? Qt.rgba(Theme.barMid.r, Theme.barMid.g, Theme.barMid.b, 0.18) : Theme.chip

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: list.sessions.length
                    color: list.waiting > 0 ? Theme.barMid : Theme.textSoft
                    font.pixelSize: Math.round(11 * list.s)
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
        }

        Shape {
            id: chevron

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2 * list.s
            width: 10 * list.s
            height: 10 * list.s
            rotation: list.open ? 90 : 0
            preferredRendererType: Shape.CurveRenderer
            Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            ShapePath {
                strokeColor: Theme.textSecondary
                strokeWidth: 1.6 * list.s
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: chevron.width * 0.35; startY: chevron.height * 0.15
                PathLine { x: chevron.width * 0.7; y: chevron.height * 0.5 }
                PathLine { x: chevron.width * 0.35; y: chevron.height * 0.85 }
            }
        }

        HoverHandler {
            id: headerHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: FlareData.toggleSessions()
        }
    }

    // Folds by height, clipped, so the card grows and shrinks with it.
    Item {
        width: list.width
        height: list.open ? rows.implicitHeight + 4 * list.s : 0
        clip: true
        opacity: list.open ? 1 : 0

        Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Column {
            id: rows

            y: 2 * list.s
            width: parent.width
            spacing: 2 * list.s

            Repeater {
                model: list.sessions

                Item {
                    id: row

                    required property var modelData
                    readonly property string phase: modelData.state

                    width: rows.width
                    height: 44 * list.s

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: -6 * list.s
                        anchors.rightMargin: -6 * list.s
                        radius: 10 * list.s
                        color: rowHover.hovered ? Theme.rowHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    Item {
                        id: dotBox

                        anchors.verticalCenter: parent.verticalCenter
                        width: 8 * list.s
                        height: width

                        readonly property color tone: row.phase === "busy" ? Theme.barLow
                            : row.phase === "waiting" ? Theme.barMid : Theme.textSecondary

                        // A soft ring that widens and fades out behind a
                        // working session's dot; the dot itself stays still.
                        Rectangle {
                            id: halo

                            anchors.centerIn: parent
                            width: parent.width
                            height: width
                            radius: width / 2
                            color: dotBox.tone
                            opacity: 0
                            visible: row.phase === "busy"

                            ParallelAnimation {
                                running: halo.visible && list.live && list.open
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) { halo.scale = 1; halo.opacity = 0; }
                                NumberAnimation { target: halo; property: "scale"; from: 1; to: 2.6; duration: 1600; easing.type: Easing.OutCubic }
                                NumberAnimation { target: halo; property: "opacity"; from: 0.45; to: 0; duration: 1600; easing.type: Easing.OutCubic }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: dotBox.tone
                            Behavior on color { ColorAnimation { duration: 240 } }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        x: dotBox.width + 12 * list.s
                        width: parent.width - x - side.width - 10 * list.s
                        spacing: 2 * list.s

                        Text {
                            width: parent.width
                            text: row.modelData.name
                            color: Theme.textPrimary
                            font.pixelSize: Math.round(13 * list.s)
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: {
                                const parts = [];
                                if (row.modelData.project && row.modelData.project !== row.modelData.name)
                                    parts.push(row.modelData.project);
                                if (row.modelData.started_at)
                                    parts.push(Strings.duration(FlareData.now - row.modelData.started_at));
                                return parts.join(" · ");
                            }
                            color: Theme.textSecondary
                            font.pixelSize: Math.max(8, Math.round(11 * list.s))
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        id: side

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(stateText.implicitWidth, arrow.width)
                        height: stateText.implicitHeight

                        // The state gives way to an arrow on hover: the row
                        // is a way to the terminal.
                        Text {
                            id: stateText
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: Strings.sessionState(row.phase, row.modelData.waiting_for)
                            color: row.phase === "waiting" ? Theme.barMid : Theme.textSecondary
                            font.pixelSize: Math.max(8, Math.round(11 * list.s))
                            opacity: rowHover.hovered ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        Shape {
                            id: arrow

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenterOffset: 0
                            width: 11 * list.s
                            height: 11 * list.s
                            opacity: rowHover.hovered ? 1 : 0
                            transform: Translate { x: rowHover.hovered ? 0 : -4 * list.s; Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                            preferredRendererType: Shape.CurveRenderer
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            ShapePath {
                                strokeColor: Theme.textPrimary
                                strokeWidth: 1.6 * list.s
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                joinStyle: ShapePath.RoundJoin
                                startX: arrow.width * 0.2; startY: arrow.height * 0.8
                                PathLine { x: arrow.width * 0.8; y: arrow.height * 0.2 }
                                PathMove { x: arrow.width * 0.35; y: arrow.height * 0.2 }
                                PathLine { x: arrow.width * 0.8; y: arrow.height * 0.2 }
                                PathLine { x: arrow.width * 0.8; y: arrow.height * 0.65 }
                            }
                        }
                    }

                    HoverHandler {
                        id: rowHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: FlareData.focusSession(list.provider, row.modelData.pid)
                    }
                }
            }
        }
    }
}
