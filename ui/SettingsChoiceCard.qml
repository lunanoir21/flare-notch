import QtQuick
import QtQuick.Layouts

// A selectable tile: a small drawing of the choice, its name, a line on it.
// In a row, tiles share the width equally.
Rectangle {
    id: tile

    required property string label
    property string hint: ""
    property bool selected: false
    default property alias art: artArea.data

    signal picked

    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.minimumWidth: 96
    implicitWidth: 140
    implicitHeight: 146
    radius: 14
    color: selected ? Qt.rgba(1, 1, 1, 0.06) : (hover.hovered ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
    border.width: selected ? 2 : 1
    border.color: selected ? Theme.sheetText : (activeFocus ? Theme.sheetSubtext : Theme.sheetLine)
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: label
    Accessible.checked: selected
    Keys.onSpacePressed: picked()
    Keys.onReturnPressed: picked()

    Behavior on color {
        ColorAnimation {
            duration: 140
        }
    }

    Item {
        id: artArea
        x: 10
        y: 10
        width: tile.width - 20
        height: 74
    }

    Text {
        x: 12
        y: 94
        width: tile.width - 24
        text: tile.label
        color: Theme.sheetText
        font.pixelSize: 13
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    Text {
        x: 12
        y: 113
        width: tile.width - 24
        text: tile.hint
        color: Theme.sheetMuted
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        onClicked: tile.picked()
    }
}
