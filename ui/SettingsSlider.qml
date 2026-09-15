import QtQuick
import QtQuick.Controls.Basic

Slider {
    id: slider

    implicitWidth: 240
    implicitHeight: 24

    background: Rectangle {
        x: slider.leftPadding
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: slider.availableWidth
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.10)

        Rectangle {
            width: slider.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: Theme.sheetText
        }
    }

    handle: Rectangle {
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: 18
        height: 18
        radius: 9
        color: Theme.sheetText
        border.width: 4
        border.color: slider.pressed || slider.activeFocus ? Qt.rgba(1, 1, 1, 0.35) : Theme.sheetRaised
    }
}
