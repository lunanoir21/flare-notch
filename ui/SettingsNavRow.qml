import QtQuick

Item {
    id: row

    required property string icon
    required property string label
    required property string hint
    property bool current: false

    signal activated

    implicitHeight: 48
    activeFocusOnTab: true
    Accessible.role: Accessible.PageTab
    Accessible.name: label
    Keys.onSpacePressed: activated()
    Keys.onReturnPressed: activated()

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: hover.hovered && !row.current ? Qt.rgba(1, 1, 1, 0.03) : "transparent"
        border.color: row.activeFocus ? Theme.sheetSubtext : "transparent"
    }

    SettingsIcon {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        name: row.icon
        color: row.current ? Theme.sheetText : Theme.sheetMuted
    }

    Column {
        x: 46
        width: row.width - 54
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: row.label
            color: row.current ? Theme.sheetText : Theme.sheetSubtext
            font.pixelSize: 13
            font.weight: row.current ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: row.hint
            color: Theme.sheetMuted
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        onClicked: row.activated()
    }
}
