import QtQuick
import QtQuick.Shapes

// A grey track with a coloured arc from 12 o'clock, clockwise, by the
// fraction used, and the provider's logo in the middle; another login of a
// provider wears its initial on the ring.
Item {
    id: ring

    required property real diameter
    required property real trackWidth
    required property real arcWidth
    required property real logoSize
    required property real fraction
    required property color arcColor
    required property string provider
    property bool dimmed: false
    property bool exhausted: false

    readonly property real centre: diameter / 2
    readonly property real radius: (diameter - trackWidth) / 2
    property real sweep: Math.max(0, Math.min(1, fraction)) * 360
    property color shownColor: arcColor

    Behavior on sweep {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }
    Behavior on shownColor {
        ColorAnimation {
            duration: 300
        }
    }

    implicitWidth: diameter
    implicitHeight: diameter
    opacity: dimmed ? 0.45 : 1

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Theme.ringTrack
            strokeWidth: ring.trackWidth
            fillColor: "transparent"

            PathAngleArc {
                centerX: ring.centre
                centerY: ring.centre
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: 0
                sweepAngle: 360
            }
        }

        ShapePath {
            // A zero-length arc with round caps would still draw a dot.
            strokeColor: ring.sweep > 0.5 ? ring.shownColor : "transparent"
            strokeWidth: ring.arcWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.centre
                centerY: ring.centre
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: -90
                sweepAngle: ring.sweep
            }
        }
    }

    Image {
        anchors.centerIn: parent
        width: ring.logoSize
        height: ring.logoSize
        visible: ring.provider !== ""
        source: Theme.logo(ring.provider)
        sourceSize: Qt.size(Math.ceil(ring.logoSize * 2), Math.ceil(ring.logoSize * 2))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        // A spent limit dims its logo so the ring reads as waiting.
        opacity: ring.exhausted ? 0.35 : 1
        Accessible.ignored: true
    }

    AccountBadge {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -size * 0.12
        anchors.bottomMargin: -size * 0.12
        provider: ring.provider
        size: Math.max(9, Math.round(ring.diameter * 0.4))
    }
}
