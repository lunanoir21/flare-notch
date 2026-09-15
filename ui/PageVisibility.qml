import QtQuick
import QtQuick.Layouts

Flickable {
    id: page

    contentHeight: column.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    component ShortcutLine: RowLayout {
        id: line

        required property string label
        required property var keys

        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: line.label
            color: Theme.sheetText
            font.pixelSize: 13
        }

        Repeater {
            model: line.keys

            Kbd {
                required property string modelData
                text: modelData
            }
        }
    }

    ColumnLayout {
        id: column

        width: page.width
        spacing: 14

        SettingsCard {
            title: Strings.reveal

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        {
                            value: "always",
                            label: Strings.always,
                            hint: Strings.alwaysShort
                        },
                        {
                            value: "hover",
                            label: Strings.hover,
                            hint: Strings.hoverShort
                        },
                        {
                            value: "shortcut",
                            label: Strings.shortcut,
                            hint: Strings.shortcutShort
                        }
                    ]

                    SettingsChoiceCard {
                        id: choice

                        required property var modelData

                        label: modelData.label
                        hint: modelData.hint
                        selected: FlareData.reveal === modelData.value
                        onPicked: FlareData.set("notch.reveal", modelData.value)

                        SettingsArt {
                            anchors.fill: parent
                            kind: choice.modelData.value
                        }
                    }
                }
            }

            SettingsRow {
                visible: FlareData.reveal === "hover"
                label: Strings.revealDelay + " · " + Math.round(revealSlider.value) + " ms"
                hint: Strings.revealDelayHint

                SettingsSlider {
                    id: revealSlider
                    width: 200
                    from: 0
                    to: 1000
                    stepSize: 10
                    value: FlareData.revealDelay
                    onPressedChanged: {
                        if (!pressed)
                            FlareData.set("notch.reveal_delay_ms", Math.round(value));
                    }
                }
            }

            SettingsRow {
                visible: FlareData.reveal === "hover"
                label: Strings.hideDelay + " · " + Math.round(hideSlider.value) + " ms"
                hint: Strings.hideDelayHint

                SettingsSlider {
                    id: hideSlider
                    width: 200
                    from: 0
                    to: 2000
                    stepSize: 10
                    value: FlareData.hideDelay
                    onPressedChanged: {
                        if (!pressed)
                            FlareData.set("notch.hide_delay_ms", Math.round(value));
                    }
                }
            }
        }

        SettingsCard {
            title: Strings.compactTitle

            SettingsRow {
                label: Strings.opens
                hint: Strings.opensHint

                SettingsSegmented {
                    options: [
                        {
                            value: "click",
                            label: Strings.tapToOpen
                        },
                        {
                            value: "hover",
                            label: Strings.hoverToOpen
                        }
                    ]
                    currentValue: FlareData.openOn
                    onPicked: value => FlareData.set("compact.open_on", value)
                }
            }
        }

        SettingsCard {
            title: Strings.shortcuts

            ShortcutLine {
                label: Strings.kbVisible
                keys: ["Super", "Shift", "U"]
            }

            ShortcutLine {
                label: Strings.kbCompact
                keys: ["Super", "U"]
            }

            ShortcutLine {
                label: Strings.kbAura
                keys: ["Super", "←", "→"]
            }

            Text {
                Layout.fillWidth: true
                text: Strings.shortcutsHint
                color: Theme.sheetMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }
}
