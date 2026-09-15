import QtQuick

// Pill-shaped exclusive choice; one thumb slides under the current segment.
// Options are [{ value, label }].
Item {
    id: root

    property var options: []
    property var currentValue: null

    signal picked(var value)

    readonly property int currentIndex: options.findIndex(option => option.value === currentValue)
    // The Repeater announces its count before the items exist; counting them
    // as they arrive re-runs the thumb's lookup until the current one is there.
    property int builtItems: 0
    // The first placement is a jump; later changes slide.
    property bool settled: false

    // Measured from the labels up front, so a row laying this out never sees
    // it at the width it had before its segments were built.
    implicitWidth: options.reduce((sum, option) => sum + root.segmentWidth(option.label), 0) + Math.max(0, options.length - 1) * layout.spacing + 8
    implicitHeight: 34
    Component.onCompleted: Qt.callLater(() => root.settled = true)

    function segmentWidth(text) {
        return Math.ceil(metrics.advanceWidth(text)) + 26;
    }

    FontMetrics {
        id: metrics
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.04)
        border.color: Theme.sheetLine
    }

    Rectangle {
        id: thumb

        readonly property Item target: root.currentIndex >= 0 && root.builtItems > root.currentIndex ? segments.itemAt(root.currentIndex) : null

        visible: target !== null
        x: layout.x + (target ? target.x : 0)
        y: layout.y
        width: target ? target.width : 0
        height: layout.height
        radius: height / 2
        color: Theme.sheetText

        Behavior on x {
            enabled: root.settled
            NumberAnimation {
                duration: 240
                easing.type: Easing.OutCubic
            }
        }
        Behavior on width {
            enabled: root.settled
            NumberAnimation {
                duration: 240
                easing.type: Easing.OutCubic
            }
        }
    }

    Row {
        id: layout

        anchors.centerIn: parent
        spacing: 2

        Repeater {
            id: segments

            model: root.options
            onItemAdded: root.builtItems += 1
            onItemRemoved: root.builtItems = Math.max(0, root.builtItems - 1)

            Item {
                id: segment

                required property var modelData
                required property int index
                readonly property bool current: index === root.currentIndex

                width: root.segmentWidth(modelData.label)
                height: 28
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.label
                Accessible.checked: current
                Keys.onSpacePressed: root.picked(modelData.value)

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "transparent"
                    border.color: segment.activeFocus && !segment.current ? Theme.sheetSubtext : "transparent"
                }

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: segment.modelData.label
                    color: segment.current ? Theme.sheet : (hover.hovered ? Theme.sheetText : Theme.sheetSubtext)
                    font.pixelSize: 12
                    font.weight: segment.current ? Font.DemiBold : Font.Normal
                }

                HoverHandler {
                    id: hover
                }

                // A MouseArea with room to spare, not a TapHandler: a TapHandler
                // drops a tap whose release lands a pixel outside a small target.
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: root.picked(segment.modelData.value)
                }
            }
        }
    }
}
