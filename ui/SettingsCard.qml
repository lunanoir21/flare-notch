import QtQuick
import QtQuick.Layouts

// A raised group with an optional small heading.
Rectangle {
    id: card

    property string title: ""
    default property alias content: column.data

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 36
    radius: 16
    color: Theme.sheetRaised
    border.color: Theme.sheetLine

    ColumnLayout {
        id: column

        x: 18
        y: 18
        width: card.width - 36
        spacing: 16

        Text {
            visible: card.title !== ""
            text: card.title
            color: Theme.sheetMuted
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 0.9
            font.capitalization: Font.AllUppercase
        }
    }
}
