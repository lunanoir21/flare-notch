import QtQuick
import QtQuick.Layouts

// The setup's provider question: which of flare's providers the notch should
// draw. The same card PageProviders draws — logo, name, status, switch — with
// the reorder arrows and the colour row left out: this screen only asks which
// ones to keep, and the same switch writes providers.<id> through
// `flare config set`, so the settings page already shows the answer.
Item {
    id: screen

    // Installed here or not, said from the reading that is already on hand —
    // no second look at the machine.
    function installedLabel(id) {
        const snapshot = FlareData.providers.find(p => p.provider === id);
        if (!snapshot)
            return Strings.checking;
        return snapshot.status === "absent" ? Strings.notInstalled : Strings.installed;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Text {
            Layout.fillWidth: true
            text: Strings.providersStepTitle
            color: Theme.sheetText
            font.pixelSize: 26
            font.weight: Font.Bold
            font.letterSpacing: -0.4
        }

        Text {
            Layout.fillWidth: true
            Layout.maximumWidth: 560
            Layout.alignment: Qt.AlignLeft
            text: Strings.providersStepHint
            color: Theme.sheetSubtext
            font.pixelSize: 14
            lineHeight: 1.35
            wrapMode: Text.WordWrap
        }

        Flickable {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: column

                width: list.width
                spacing: 6

                Repeater {
                    model: FlareData.allIds()

                    Rectangle {
                        id: card

                        required property string modelData

                        readonly property bool enabledHere: !FlareData.isOff(modelData)
                        readonly property bool otherLogin: FlareData.accountOf(modelData) !== ""
                        readonly property color tint: FlareData.auraColour(modelData)

                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: 14
                        color: Theme.sheetRaised
                        border.color: Theme.sheetLine

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 16
                            spacing: 14

                            Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                radius: 10
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: Theme.sheetLine
                                opacity: card.enabledHere ? 1 : 0.45

                                Image {
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    source: Theme.logo(card.modelData)
                                    sourceSize: Qt.size(48, 48)
                                    fillMode: Image.PreserveAspectFit
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: -3
                                    width: 11
                                    height: 11
                                    radius: 5.5
                                    visible: card.enabledHere && !card.otherLogin
                                    color: card.tint
                                    border.width: 2
                                    border.color: Theme.sheetRaised
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: FlareData.nameOf(card.modelData)
                                    color: card.enabledHere ? Theme.sheetText : Theme.sheetSubtext
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: screen.installedLabel(card.modelData)
                                    color: Theme.sheetMuted
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            SettingsToggle {
                                Layout.alignment: Qt.AlignVCenter
                                checked: card.enabledHere
                                Accessible.name: Strings.show + " " + FlareData.nameOf(card.modelData)
                                onToggled: FlareData.setShown(card.modelData, !card.enabledHere)
                            }
                        }
                    }
                }
            }
        }
    }
}
