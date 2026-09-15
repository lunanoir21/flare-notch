import QtQuick

Rectangle {
    id: button

    required property string text
    property bool primary: false

    signal clicked

    implicitWidth: Math.max(34, label.implicitWidth + 28)
    implicitHeight: 34
    radius: height / 2
    color: primary ? Theme.sheetText : (hover.hovered ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.04))
    border.color: primary ? "transparent" : (button.activeFocus ? Theme.sheetSubtext : Theme.sheetLine)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Keys.onSpacePressed: clicked()
    Keys.onReturnPressed: clicked()

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: button.primary ? Theme.sheet : Theme.sheetText
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -3
        onClicked: button.clicked()
    }
}
