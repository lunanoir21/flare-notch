import QtQuick

// One provider at a time, tinted with its colour. The others wait below as a
// logo and a number; Super + ← / → (or a tap on one) moves the focus.
Item {
    id: view

    required property string edge
    required property real size
    property string mount: "bridge"
    property real edgeGap: 0

    readonly property var cell: FlareData.focusedCell
    readonly property var others: FlareData.cells.filter(c => view.cell && c.id !== view.cell.id)
    readonly property bool blocked: cell !== null && (cell.status === "needs_auth" || cell.status === "error" || cell.status === "backoff" || cell.status === "needs_consent")
    readonly property real flare: 46 * size
    readonly property real corner: 34 * size
    readonly property real pad: 26 * size
    readonly property real depth: 96 * size
    readonly property real bodyDepth: depth
    readonly property real inset: mount === "floating" ? edgeGap : 0
    readonly property real ends: mount === "bridge" ? flare : 0
    property color tint: cell ? cell.aura : Theme.textSecondary
    readonly property var sessions: cell && cell.sessions ? cell.sessions : []
    readonly property real ringDiameter: 68 * size

    // The same hover card as classic, opened from the one big ring.
    signal cellHovered(string id, bool inside)

    function cellCenter(id) {
        return view.ends + view.pad + view.ringDiameter / 2;
    }

    Behavior on tint {
        ColorAnimation {
            duration: 450
            easing.type: Easing.OutCubic
        }
    }

    implicitWidth: depth + inset
    implicitHeight: 2 * ends + 2 * pad + column.implicitHeight

    // A flush strip is drawn by the host. The panel itself no longer tints —
    // the ring alone carries the provider's colour; one animated surface,
    // not two.
    NotchShape {
        anchors.fill: parent
        visible: view.mount !== "flush"
        edge: view.edge
        mount: view.mount
        depth: view.depth
        length: view.implicitHeight
        gap: view.inset
        flare: view.flare
        corner: view.mount === "floating" ? 24 * view.size : view.corner
    }

    Column {
        id: column

        x: view.edge === "left" ? view.inset : 0
        width: view.depth
        y: view.ends + view.pad
        visible: view.cell !== null

        ProviderRing {
            anchors.horizontalCenter: parent.horizontalCenter
            diameter: view.ringDiameter
            trackWidth: 5 * view.size
            arcWidth: 5 * view.size
            logoSize: 28 * view.size
            fraction: view.cell ? view.cell.fraction : 0
            arcColor: view.cell && view.cell.metered ? view.tint : Theme.textSecondary
            provider: view.cell ? view.cell.id : ""
            dimmed: view.cell ? view.cell.dimmed : true
            exhausted: view.cell ? view.cell.exhausted : false
            Accessible.role: Accessible.ProgressBar
            Accessible.name: view.cell ? view.cell.name + ": " + view.cell.label : ""

            TapHandler {
                onTapped: FlareData.openUsagePage(view.cell.id)
            }

            HoverHandler {
                onHoveredChanged: {
                    if (view.cell)
                        view.cellHovered(view.cell.id, hovered);
                }
            }
        }

        Item {
            width: 1
            height: 12 * view.size
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.cell ? view.cell.label : ""
            color: Theme.textPrimary
            font.pixelSize: Math.round(24 * view.size)
            font.weight: Font.DemiBold
            font.letterSpacing: -0.5
            font.features: {
                "tnum": 1
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 5 * view.size
            text: {
                if (!view.cell)
                    return "";
                if (!view.cell.metered)
                    return Strings.today;
                if (view.blocked || !view.cell.head)
                    return Strings.status(view.cell.status) || Strings.noReading;
                return Strings.timeLeft(view.cell.head.resets_at, FlareData.now);
            }
            // The ring itself carries the critical accent now (Theme.ringColor);
            // a second, independently-thresholded red here would just repeat it.
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: Math.max(9, Math.round(11 * view.size))
        }

        // One dot per open session, in its state's colour; the hover card
        // lists them.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 10 * view.size
            spacing: 5 * view.size
            visible: view.sessions.length > 0
            Accessible.role: Accessible.StaticText
            Accessible.name: Strings.sessions + ": " + view.sessions.length

            Repeater {
                model: view.sessions.slice(0, 6)

                Rectangle {
                    required property var modelData

                    width: 6 * view.size
                    height: width
                    radius: width / 2
                    color: modelData.state === "busy" ? Theme.barLow : modelData.state === "waiting" ? Theme.barMid : Theme.textSecondary
                }
            }
        }

        Item {
            width: 1
            height: 22 * view.size
            visible: view.others.length > 0
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 56 * view.size
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
            visible: view.others.length > 0
        }

        Item {
            width: 1
            height: 16 * view.size
            visible: view.others.length > 0
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10 * view.size

            // Who else is here, and a tap moves the focus — the name itself
            // is already showing above for whichever one is focused, so an
            // icon says enough.
            Repeater {
                model: view.others

                Item {
                    id: mini

                    required property var modelData

                    width: 28 * view.size
                    height: 28 * view.size
                    opacity: miniHover.hovered ? 1 : 0.6
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name + ": " + modelData.label

                    Image {
                        anchors.centerIn: parent
                        width: 18 * view.size
                        height: 18 * view.size
                        source: Theme.logo(mini.modelData.id)
                        sourceSize: Qt.size(Math.ceil(36 * view.size), Math.ceil(36 * view.size))
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    HoverHandler {
                        id: miniHover
                    }

                    TapHandler {
                        onTapped: FlareData.focusOn(mini.modelData.id)
                    }
                }
            }
        }
    }
}
