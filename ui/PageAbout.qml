import QtQuick
import QtQuick.Layouts
import Quickshell

Flickable {
    id: page

    property bool copied: false

    contentHeight: column.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Timer {
        id: copiedTimer
        interval: 1600
        onTriggered: page.copied = false
    }

    ColumnLayout {
        id: column

        width: page.width
        spacing: 14

        SettingsCard {
            title: "flare"

            Text {
                Layout.fillWidth: true
                text: Strings.aboutText
                color: Theme.sheetText
                font.pixelSize: 13
                lineHeight: 1.35
                wrapMode: Text.WordWrap
            }

            RowLayout {
                spacing: 8

                SettingsButton {
                    text: Strings.openGithub
                    primary: true
                    onClicked: Qt.openUrlExternally("https://github.com/lunanoir21/flare-notch")
                }

                SettingsButton {
                    text: "Codenotch"
                    onClicked: Qt.openUrlExternally("https://github.com/vinzdg/codenotch")
                }
            }
        }

        SettingsCard {
            title: Strings.file

            Text {
                Layout.fillWidth: true
                text: FlareData.configPath
                color: Theme.sheetSubtext
                font.pixelSize: 12
                font.family: Theme.mono
                wrapMode: Text.WrapAnywhere
            }

            SettingsButton {
                text: page.copied ? Strings.copied : Strings.copyPath
                onClicked: {
                    Quickshell.clipboardText = FlareData.configPath;
                    page.copied = true;
                    copiedTimer.restart();
                }
            }

            Text {
                Layout.fillWidth: true
                visible: FlareData.configProblem !== ""
                text: FlareData.configProblem
                color: Theme.critical
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        SettingsCard {
            title: Strings.credits

            Text {
                Layout.fillWidth: true
                text: Strings.creditsText
                color: Theme.sheetSubtext
                font.pixelSize: 12
                lineHeight: 1.35
                wrapMode: Text.WordWrap
            }
        }
    }
}
