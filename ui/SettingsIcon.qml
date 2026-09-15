import QtQuick
import QtQuick.Shapes

// Line icons drawn as paths on a 24px grid, so they need no icon font.
Item {
    id: icon

    required property string name
    property color color: Theme.sheetSubtext
    // Fixed rather than read back from the item: a Shape sizes itself from its
    // path, so a scale taken from that size would chase its own tail.
    property real size: 18

    readonly property var paths: ({
            look: "M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v11a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 17.5zM9 8v8",
            placement: "M12 3v4M12 17v4M3 12h4M17 12h4M12 9a3 3 0 1 1 0 6a3 3 0 1 1 0-6",
            visibility: "M2.5 12s3.5-6.5 9.5-6.5S21.5 12 21.5 12s-3.5 6.5-9.5 6.5S2.5 12 2.5 12zM12 9.5a2.5 2.5 0 1 1 0 5a2.5 2.5 0 1 1 0-5",
            providers: "M4.5 4.5h6v6h-6zM13.5 4.5h6v6h-6zM4.5 13.5h6v6h-6zM13.5 13.5h6v6h-6z",
            data: "M7 4v15M3.5 15.5L7 19l3.5-3.5M17 20V5M13.5 8.5L17 5l3.5 3.5",
            about: "M12 3a9 9 0 1 1 0 18a9 9 0 1 1 0-18M12 11v5.5M12 7.6v.2"
        })

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: icon.size
        height: icon.size
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: icon.color
            strokeWidth: 1.7
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            scale: Qt.size(icon.size / 24, icon.size / 24)

            PathSvg {
                path: icon.paths[icon.name] || ""
            }
        }
    }
}
