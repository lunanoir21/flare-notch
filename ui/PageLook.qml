import QtQuick
import QtQuick.Layouts

Flickable {
    id: page

    contentHeight: column.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: column

        width: page.width
        spacing: 14

        SettingsCard {
            title: Strings.styleTitle

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        {
                            value: "classic",
                            label: Strings.classic,
                            hint: Strings.classicShort
                        },
                        {
                            value: "aura",
                            label: Strings.aura,
                            hint: Strings.auraShort
                        },
                        {
                            value: "compact",
                            label: Strings.compact,
                            hint: Strings.compactShort
                        }
                    ]

                    SettingsChoiceCard {
                        id: choice

                        required property var modelData

                        label: modelData.label
                        hint: modelData.hint
                        selected: FlareData.style === modelData.value
                        onPicked: FlareData.set("notch.style", modelData.value)

                        SettingsArt {
                            anchors.fill: parent
                            kind: choice.modelData.value
                        }
                    }
                }
            }
        }

        SettingsCard {
            title: Strings.colorTitle

            SettingsRow {
                label: Strings.themeModeLabel

                SettingsSegmented {
                    options: [
                        { value: "black", label: Strings.black },
                        { value: "white", label: Strings.white },
                        { value: "auto", label: Strings.auto }
                    ]
                    currentValue: FlareData.themeMode
                    onPicked: value => FlareData.set("theme.mode", value)
                }
            }

            SettingsRow {
                label: Strings.ringLabelTitle
                hint: Strings.ringLabelHint

                SettingsSegmented {
                    options: [
                        { value: "percent", label: Strings.labelPercent },
                        { value: "time", label: Strings.labelTime },
                        { value: "both", label: Strings.labelBoth }
                    ]
                    currentValue: FlareData.ringLabel
                    onPicked: value => FlareData.set("notch.label", value)
                }
            }

            SettingsRow {
                label: Strings.languageLabel

                SettingsSegmented {
                    options: [
                        { value: "auto", label: Strings.auto },
                        { value: "en", label: "English" },
                        { value: "tr", label: "Türkçe" }
                    ]
                    currentValue: FlareData.language
                    onPicked: value => FlareData.set("ui.language", value)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10

                Repeater {
                    model: [
                        {
                            value: "monochrome",
                            label: Strings.monochrome,
                            hint: Strings.monochromeShort
                        },
                        {
                            value: "provider",
                            label: Strings.provider,
                            hint: Strings.providerShort
                        }
                    ]

                    SettingsChoiceCard {
                        id: colorChoice

                        required property var modelData

                        label: modelData.label
                        hint: modelData.hint
                        selected: FlareData.ringColorMode === modelData.value
                        onPicked: FlareData.set("theme.ring_color", modelData.value)

                        SettingsArt {
                            anchors.fill: parent
                            kind: colorChoice.modelData.value
                        }
                    }
                }
            }
        }

        SettingsCard {
            title: Strings.mount

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        {
                            value: "bridge",
                            label: Strings.bridge,
                            hint: Strings.bridgeShort
                        },
                        {
                            value: "floating",
                            label: Strings.floating,
                            hint: Strings.floatingShort
                        },
                        {
                            value: "flush",
                            label: Strings.flush,
                            hint: Strings.flushShort
                        }
                    ]

                    SettingsChoiceCard {
                        id: choice

                        required property var modelData

                        label: modelData.label
                        hint: modelData.hint
                        selected: FlareData.mount === modelData.value
                        onPicked: FlareData.set("notch.mount", modelData.value)

                        SettingsArt {
                            anchors.fill: parent
                            kind: choice.modelData.value
                        }
                    }
                }
            }

            SettingsRow {
                visible: FlareData.mount === "floating"
                label: Strings.edgeGap + " · " + Math.round(gapSlider.value) + " px"

                SettingsSlider {
                    id: gapSlider
                    width: 200
                    from: 0
                    to: 48
                    stepSize: 1
                    value: FlareData.gap
                    onMoved: FlareData.previewGap = value
                    onPressedChanged: {
                        if (!pressed)
                            FlareData.set("notch.gap", Math.round(value));
                    }
                }
            }
        }

        SettingsCard {
            title: Strings.size

            SettingsRow {
                label: "%" + Math.round(scaleSlider.value * 100)
                hint: Strings.sizeHint

                SettingsSlider {
                    id: scaleSlider
                    width: 200
                    from: 0.5
                    to: 2
                    stepSize: 0.05
                    value: FlareData.scale
                    onMoved: FlareData.previewScale = value
                    onPressedChanged: {
                        if (!pressed)
                            FlareData.set("notch.scale", Math.round(value * 100) / 100);
                    }
                }
            }
        }
    }
}
