import QtQuick

// The widget as it is set up now, drawn with the real views and real numbers
// on a sliver of desktop.
Rectangle {
    id: preview

    readonly property bool compact: FlareData.style === "compact"
    readonly property string edge: compact ? FlareData.compactEdge : FlareData.notchEdge
    readonly property real size: compact ? 0.56 : 0.84

    radius: 16
    border.color: Theme.sheetLine
    clip: true
    gradient: Gradient {
        GradientStop {
            position: 0
            color: "#17252E"
        }
        GradientStop {
            position: 0.55
            color: "#0E1216"
        }
        GradientStop {
            position: 1
            color: "#241810"
        }
    }

    NotchShape {
        readonly property real stripDepth: body.item ? body.item.bodyDepth : 0
        readonly property real stripReach: stripDepth + Math.min(18 * preview.size, stripDepth)

        visible: FlareData.mount === "flush" && body.item !== null
        edge: preview.edge
        mount: "flush"
        depth: stripDepth
        length: preview.compact ? preview.width : preview.height
        flare: 18 * preview.size
        tint: FlareData.style === "aura" && FlareData.focusedCell ? FlareData.focusedCell.aura : "transparent"
        tintStrength: FlareData.style === "aura" ? 0.36 : 0
        width: preview.compact ? preview.width : stripReach
        height: preview.compact ? stripReach : preview.height
        x: !preview.compact && preview.edge === "right" ? preview.width - width : 0
        y: preview.compact && preview.edge === "bottom" ? preview.height - height : 0
    }

    Loader {
        id: body

        sourceComponent: preview.compact ? compactView : (FlareData.style === "aura" ? auraView : classicView)
        x: preview.compact ? (preview.width - width) / 2 : (preview.edge === "right" ? preview.width - width : 0)
        y: preview.compact ? (preview.edge === "bottom" ? preview.height - height : 0) : (preview.height - height) / 2
    }

    Component {
        id: classicView

        ClassicView {
            edge: preview.edge
            size: preview.size
            mount: FlareData.mount
            edgeGap: FlareData.gap * preview.size
        }
    }

    Component {
        id: auraView

        AuraView {
            edge: preview.edge
            size: preview.size
            mount: FlareData.mount
            edgeGap: FlareData.gap * preview.size
        }
    }

    Component {
        id: compactView

        CompactView {
            edge: preview.edge
            size: preview.size
            mount: FlareData.mount
            edgeGap: FlareData.gap * preview.size
        }
    }
}
