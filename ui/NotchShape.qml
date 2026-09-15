import QtQuick
import QtQuick.Shapes

// Codenotch's SideNotchShape: a body welded to one edge, with inverse rounded
// corners flaring back out to the bezel. Written once for the right edge
// (bezel at x = depth) and turned onto whichever edge it is on.
Item {
    id: root

    required property string edge
    required property real depth
    required property real length
    required property real flare
    required property real corner
    property color tint: "transparent"
    property real tintStrength: 0

    readonly property bool vertical: edge === "left" || edge === "right"

    // The corner is claimed first, out of half the depth, and the flare takes
    // what is left; the other order squares the corners off on a shallow body.
    readonly property string outline: {
        const wanted = Math.max(0, Math.min(corner, depth / 2));
        const c = Math.max(0, Math.min(flare, length / 2, depth - wanted));
        const r = Math.max(0, Math.min(wanted, (length - 2 * c) / 2));
        const w = depth, h = length;
        return "M" + w + " 0 A" + c + " " + c + " 0 0 1 " + (w - c) + " " + c
            + " L" + r + " " + c + " A" + r + " " + r + " 0 0 0 0 " + (c + r)
            + " L0 " + (h - c - r) + " A" + r + " " + r + " 0 0 0 " + r + " " + (h - c)
            + " L" + (w - c) + " " + (h - c) + " A" + c + " " + c + " 0 0 1 " + w + " " + h + " Z";
    }

    implicitWidth: vertical ? depth : length
    implicitHeight: vertical ? length : depth

    Item {
        width: root.depth
        height: root.length
        anchors.centerIn: parent
        rotation: root.edge === "top" ? -90 : root.edge === "bottom" ? 90 : 0
        transform: Scale {
            origin.x: root.depth / 2
            xScale: root.edge === "left" ? -1 : 1
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Theme.notch
                strokeColor: Theme.edgeLine
                strokeWidth: 1

                PathSvg {
                    path: root.outline
                }
            }

            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillGradient: LinearGradient {
                    x1: root.depth
                    y1: 0
                    x2: 0
                    y2: 0

                    GradientStop {
                        position: 0
                        color: Qt.alpha(root.tint, root.tintStrength)
                    }
                    GradientStop {
                        position: 0.6
                        color: Qt.alpha(root.tint, root.tintStrength * 0.17)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(root.tint, 0)
                    }
                }

                PathSvg {
                    path: root.outline
                }
            }
        }
    }
}
