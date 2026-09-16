import QtQuick
import QtQuick.Layouts

// A one-time question, asked before official mode ever reads Cursor's live
// session cookie out of the editor's own state (see Consent in config.rs).
// Positioned the same way DetailCard sits beside the body — this is not a
// hover popup, so it stays up until answered.
Item {
    id: card

    required property string side
    signal allowed()
    signal declined()

    readonly property real s: FlareData.scale

    width: 264 * s
    implicitHeight: column.implicitHeight + 32 * s
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: 16 * card.s
        color: Theme.card
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
    }

    ColumnLayout {
        id: column
        x: 18 * card.s
        y: 16 * card.s
        width: card.width - 36 * card.s
        spacing: 10 * card.s

        Text {
            Layout.fillWidth: true
            text: Strings.cursorConsentTitle
            color: Theme.textPrimary
            font.pixelSize: Math.round(13 * card.s)
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: Strings.cursorConsentBody
            color: Theme.textSecondary
            font.pixelSize: Math.max(8, Math.round(11 * card.s))
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4 * card.s
            spacing: 8 * card.s

            Item {
                Layout.fillWidth: true
            }

            SettingsButton {
                text: Strings.decline
                onClicked: card.declined()
            }

            SettingsButton {
                text: Strings.allow
                primary: true
                onClicked: card.allowed()
            }
        }
    }

    Keys.onEscapePressed: card.declined()
}
