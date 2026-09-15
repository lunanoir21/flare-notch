import QtQuick
import QtQuick.Shapes

// The body's background, in edge space — u runs from the screen edge into the
// screen, v along it — mapped onto whichever edge it sits on. Right and top
// mirror that space, so their arcs sweep the other way.
//
//   bridge    Codenotch's SideNotchShape: welded to the edge, flaring back out
//   floating  a rounded panel held `gap` off the edge
//   flush     a strip along the whole length, flaring into the screen at both ends
Shape {
    id: root

    required property string edge
    property string mount: "bridge"
    // Body depth across the edge, not counting the gap or a flush flare.
    required property real depth
    required property real length
    property real flare: 0
    property real corner: 0
    property real gap: 0
    property color tint: "transparent"
    property real tintStrength: 0

    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property bool mirrored: edge === "right" || edge === "top"
    readonly property real flushFlare: Math.max(0, Math.min(flare, depth, length / 2))
    // How far from the edge the drawing reaches.
    readonly property real reach: mount === "floating" ? gap + depth : (mount === "flush" ? depth + flushFlare : depth)

    function point(u, v) {
        if (edge === "left")
            return u + "," + v;
        if (edge === "right")
            return (width - u) + "," + v;
        if (edge === "top")
            return v + "," + u;
        return v + "," + (height - u);
    }

    // A radius too small to draw is just a corner.
    function arc(r, sweep, u, v) {
        if (r < 0.5)
            return " L" + point(u, v);
        return " A" + r + "," + r + " 0 0 " + (mirrored ? 1 - sweep : sweep) + " " + point(u, v);
    }

    // The corner is claimed first, out of half the depth, and the flare takes
    // what is left; the other order squares the corners off on a shallow body.
    function bridgePath() {
        const d = depth, h = length;
        const wanted = Math.max(0, Math.min(corner, d / 2));
        const c = Math.max(0, Math.min(flare, h / 2, d - wanted));
        const r = Math.max(0, Math.min(wanted, (h - 2 * c) / 2));
        return "M" + point(0, 0) + arc(c, 0, c, c)
            + " L" + point(d - r, c) + arc(r, 1, d, c + r)
            + " L" + point(d, h - c - r) + arc(r, 1, d - r, h - c)
            + " L" + point(c, h - c) + arc(c, 0, 0, h) + " Z";
    }

    function floatingPath() {
        const u0 = gap, u1 = gap + depth, h = length;
        const r = Math.max(0, Math.min(corner, depth / 2, h / 2));
        return "M" + point(u0 + r, 0) + " L" + point(u1 - r, 0) + arc(r, 1, u1, r)
            + " L" + point(u1, h - r) + arc(r, 1, u1 - r, h)
            + " L" + point(u0 + r, h) + arc(r, 1, u0, h - r)
            + " L" + point(u0, r) + arc(r, 1, u0 + r, 0) + " Z";
    }

    function flushPath() {
        const d = depth, h = length, r = flushFlare;
        return "M" + point(0, 0) + " L" + point(d + r, 0) + arc(r, 0, d, r)
            + " L" + point(d, h - r) + arc(r, 0, d + r, h)
            + " L" + point(0, h) + " Z";
    }

    readonly property string outline: mount === "floating" ? floatingPath() : (mount === "flush" ? flushPath() : bridgePath())

    // No implicit size: the outline is drawn to the size it is given, so a size
    // taken from the outline would be a loop. Callers size it.
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: root.mount === "floating" ? Qt.alpha(Theme.notch, 0.92) : Theme.notch
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
            x1: root.vertical ? (root.edge === "left" ? 0 : root.width) : 0
            y1: root.vertical ? 0 : (root.edge === "top" ? 0 : root.height)
            x2: root.vertical ? (root.edge === "left" ? root.reach : root.width - root.reach) : 0
            y2: root.vertical ? 0 : (root.edge === "top" ? root.reach : root.height - root.reach)

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
