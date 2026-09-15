import QtQuick

Rectangle {
    id: key

    required property string text

    implicitWidth: Math.max(26, label.implicitWidth + 16)
    implicitHeight: 26
    radius: 7
    color: Qt.rgba(1, 1, 1, 0.06)
    border.color: Theme.sheetLine

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 4
        height: 2
        radius: 1
        color: Qt.rgba(1, 1, 1, 0.06)
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: key.text
        color: Theme.sheetText
        font.pixelSize: 11
        font.family: Theme.mono
    }
}
