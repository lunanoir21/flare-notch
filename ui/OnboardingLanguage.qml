import QtQuick
import QtQuick.Layouts

// The setup's language question. Writes ui.language, the same key the Look
// page's segmented control writes, so answering here and answering there are
// the same answer.
Item {
    id: screen

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        Text {
            Layout.fillWidth: true
            text: Strings.languageLabel
            color: Theme.sheetText
            font.pixelSize: 26
            font.weight: Font.Bold
            font.letterSpacing: -0.4
        }

        Text {
            Layout.fillWidth: true
            Layout.maximumWidth: 520
            Layout.alignment: Qt.AlignLeft
            text: Strings.languageStepHint
            color: Theme.sheetSubtext
            font.pixelSize: 14
            lineHeight: 1.35
            wrapMode: Text.WordWrap
        }

        Item {
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Repeater {
                model: [
                    {
                        value: "en",
                        label: "English",
                        hint: Strings.languageEnglish,
                        mark: "EN"
                    },
                    {
                        value: "tr",
                        label: "Türkçe",
                        hint: Strings.languageTurkish,
                        mark: "TR"
                    }
                ]

                SettingsChoiceCard {
                    id: choice

                    required property var modelData

                    Layout.preferredHeight: 168
                    label: modelData.label
                    hint: modelData.hint
                    selected: FlareData.language === modelData.value
                    onPicked: FlareData.set("ui.language", modelData.value)

                    // The card's drawing slot, spelled out rather than drawn:
                    // two letters, and the language the rest of the widget will
                    // be in once this is picked.
                    Text {
                        anchors.fill: parent
                        text: choice.modelData.mark
                        color: choice.selected ? Theme.sheetText : Theme.sheetMuted
                        font.pixelSize: 28
                        font.weight: Font.Bold
                        font.letterSpacing: 3
                        font.family: Theme.mono
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
