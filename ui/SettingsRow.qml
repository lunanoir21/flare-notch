import QtQuick
import QtQuick.Layouts

// Label and hint on the left, one control on the right.
RowLayout {
    id: row

    property string label: ""
    property string hint: ""
    default property alias control: holder.data

    Layout.fillWidth: true
    spacing: 16

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: row.label
            color: Theme.sheetText
            font.pixelSize: 13
        }

        Text {
            Layout.fillWidth: true
            visible: row.hint !== ""
            text: row.hint
            color: Theme.sheetMuted
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }

    Item {
        id: holder
        Layout.preferredWidth: childrenRect.width
        Layout.preferredHeight: childrenRect.height
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
    }
}
