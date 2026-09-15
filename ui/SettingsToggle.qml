import QtQuick

Item {
    id: toggle

    property bool checked: false

    signal toggled

    implicitWidth: 42
    implicitHeight: 24
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.checked: checked
    Keys.onSpacePressed: toggled()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: toggle.checked ? Theme.sheetText : Qt.rgba(1, 1, 1, 0.10)
        border.color: toggle.activeFocus ? Theme.sheetText : Theme.sheetLine

        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }

        Rectangle {
            width: 18
            height: 18
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: toggle.checked ? parent.width - width - 3 : 3
            color: toggle.checked ? Theme.sheet : Theme.sheetSubtext

            Behavior on x {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        onClicked: toggle.toggled()
    }
}
