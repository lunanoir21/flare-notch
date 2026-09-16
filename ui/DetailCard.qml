import QtQuick
import QtQuick.Shapes

// The hover card: one block per limit window, a tail pointing at the ring.
Item {
    id: card

    required property var cell
    // The edge the notch is on; the tail points back toward it.
    required property string side
    property real tailY: height / 2

    readonly property real s: FlareData.scale
    readonly property var windows: cell && cell.windows ? cell.windows : []

    width: 258 * s
    implicitHeight: body.implicitHeight + 32 * s
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: 16 * card.s
        color: Theme.card
    }

    Shape {
        width: 26 * card.s
        height: 36 * card.s
        x: card.side === "right" ? card.width - 2 * card.s : -24 * card.s
        y: Math.max(14 * card.s, Math.min(card.height - 50 * card.s, card.tailY - 18 * card.s))
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Theme.card
            strokeWidth: 0
            strokeColor: "transparent"
            scale: Qt.size(card.s, card.s)

            PathSvg {
                // Codenotch's curved wedge: its shoulders meet the card tangent
                // to its edge, so the two read as one shape.
                path: card.side === "right" ? "M0 0C0 9 13.4 13.7 26 18C13.4 22.3 0 27 0 36Z" : "M26 0C26 9 12.6 13.7 0 18C12.6 22.3 26 27 26 36Z"
            }
        }
    }

    Column {
        id: body

        x: 16 * card.s
        y: 16 * card.s
        width: card.width - 32 * card.s
        spacing: 10 * card.s

        Row {
            spacing: 8 * card.s

            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * card.s
                height: 16 * card.s
                source: Theme.logo(card.cell ? card.cell.id : "")
                sourceSize: Qt.size(Math.ceil(32 * card.s), Math.ceil(32 * card.s))
                fillMode: Image.PreserveAspectFit
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.cell ? Strings.title(card.cell.name) : ""
                color: Theme.textPrimary
                font.pixelSize: Math.round(14 * card.s)
                font.weight: Font.DemiBold
            }
        }

        Text {
            width: body.width
            visible: text !== ""
            text: {
                if (!card.cell)
                    return "";
                const parts = [];
                if (card.cell.plan)
                    parts.push(card.cell.plan.charAt(0).toUpperCase() + card.cell.plan.slice(1));
                const status = Strings.status(card.cell.status);
                if (status)
                    parts.push(status);
                if (card.cell.status === "stale" && card.cell.fetchedAt)
                    parts.push(Strings.ago(FlareData.now - card.cell.fetchedAt));
                return parts.join(" · ");
            }
            color: Theme.textSecondary
            font.pixelSize: Math.max(8, Math.round(11 * card.s))
            elide: Text.ElideRight
        }

        Repeater {
            model: card.windows

            Column {
                id: block

                required property var modelData
                required property int index

                readonly property bool opensGroup: modelData.group && (index === 0 || card.windows[index - 1].group !== modelData.group)

                width: body.width
                spacing: 5 * card.s

                Text {
                    visible: block.opensGroup
                    topPadding: 4 * card.s
                    text: Strings.windowLabel(block.modelData.group || "")
                    color: Theme.textSoft
                    font.pixelSize: Math.round(12 * card.s)
                    font.weight: Font.DemiBold
                }

                Item {
                    width: parent.width
                    height: labelText.implicitHeight

                    Text {
                        id: labelText
                        width: parent.width - resetText.implicitWidth - 8 * card.s
                        text: Strings.windowLabel(block.modelData.label)
                        color: Theme.textPrimary
                        font.pixelSize: Math.round(12 * card.s)
                        elide: Text.ElideRight
                    }

                    Text {
                        id: resetText
                        anchors.right: parent.right
                        text: Strings.resetText(block.modelData.resets_at, FlareData.now, block.modelData.reset_elapsed)
                        color: Theme.textSecondary
                        font.pixelSize: Math.max(8, Math.round(11 * card.s))
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 4 * card.s
                    radius: height / 2
                    color: Theme.barTrack

                    Rectangle {
                        width: parent.width * Math.min(1, block.modelData.used)
                        height: parent.height
                        radius: parent.radius
                        color: Theme.ringColor(block.modelData.used, block.modelData.used >= 1, card.cell ? card.cell.aura : "")
                    }
                }

                Text {
                    text: Strings.usedLine(block.modelData.used)
                    color: Theme.textSecondary
                    font.pixelSize: Math.max(8, Math.round(11 * card.s))
                    font.features: {
                        "tnum": 1
                    }
                }
            }
        }

        Text {
            width: body.width
            visible: card.cell !== null && !card.cell.metered
            text: card.cell ? Strings.tokensToday(card.cell.tokens) : ""
            color: Theme.textSoft
            font.pixelSize: Math.round(12 * card.s)
            wrapMode: Text.WordWrap
        }

        Text {
            width: body.width
            visible: text !== ""
            text: card.cell ? Strings.note(card.cell.note) : ""
            color: Theme.textSoft
            font.pixelSize: Math.round(12 * card.s)
            lineHeight: 1.3
            wrapMode: Text.WordWrap
        }
    }
}
