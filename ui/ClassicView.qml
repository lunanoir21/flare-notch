import QtQuick

// Codenotch's notch: every provider as a ring, stacked along the edge.
// Measurements are the design frame's, in its pixels, scaled so a 117px ring
// is 44px across.
Item {
    id: view

    required property string edge
    required property real size

    signal cellHovered(string id, bool inside)

    readonly property real u: 44 / 117 * size
    readonly property real ring: 117 * u
    readonly property real track: 15.5 * u
    readonly property real arc: 8 * u
    readonly property real logo: 52 * u
    readonly property real gap: 26.9 * u
    readonly property int fontPx: Math.max(9, Math.round(27 * u / 0.714))
    readonly property real flare: 103 * u
    readonly property real corner: 78.8 * u
    readonly property real padLead: 69.5 * u
    readonly property real padTrail: 50.1 * u
    readonly property real spacing: 83.5 * u
    readonly property real depth: 186 * u
    readonly property real cellHeight: ring + gap + metrics.height
    readonly property int count: FlareData.cells.length
    readonly property real length: 2 * flare + padLead + count * cellHeight + Math.max(0, count - 1) * spacing + padTrail

    implicitWidth: depth
    implicitHeight: length

    function cellCenter(id) {
        const index = FlareData.cells.findIndex(c => c.id === id);
        return index < 0 ? length / 2 : flare + padLead + index * (cellHeight + spacing) + ring / 2;
    }

    FontMetrics {
        id: metrics
        font.pixelSize: view.fontPx
        font.weight: Font.Medium
    }

    NotchShape {
        anchors.fill: parent
        edge: view.edge
        depth: view.depth
        length: view.length
        flare: view.flare
        corner: view.corner
    }

    Column {
        x: (view.depth - view.ring) / 2
        y: view.flare + view.padLead
        spacing: view.spacing

        Repeater {
            model: FlareData.cells

            Item {
                id: cell

                required property var modelData

                width: view.ring
                height: view.cellHeight
                scale: hover.hovered ? 1.06 : 1
                Accessible.role: Accessible.ProgressBar
                Accessible.name: modelData.name + ": " + modelData.label

                Behavior on scale {
                    ScaleAnimator {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                ProviderRing {
                    id: ringItem
                    anchors.horizontalCenter: parent.horizontalCenter
                    diameter: view.ring
                    trackWidth: view.track
                    arcWidth: view.arc
                    logoSize: view.logo
                    fraction: cell.modelData.fraction
                    arcColor: cell.modelData.arcColor
                    provider: cell.modelData.id
                    dimmed: cell.modelData.dimmed
                    exhausted: cell.modelData.exhausted
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: ringItem.height + view.gap
                    text: cell.modelData.label
                    color: cell.modelData.dimmed ? Theme.textSecondary : Theme.textPrimary
                    font.pixelSize: view.fontPx
                    font.weight: Font.Medium
                    font.features: {
                        "tnum": 1
                    }
                    Accessible.ignored: true
                }

                HoverHandler {
                    id: hover
                    onHoveredChanged: view.cellHovered(cell.modelData.id, hovered)
                }

                TapHandler {
                    onTapped: FlareData.openUsagePage(cell.modelData.id)
                }
            }
        }
    }
}
