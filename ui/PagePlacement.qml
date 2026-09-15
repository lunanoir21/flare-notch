import QtQuick
import QtQuick.Layouts
import Quickshell

Flickable {
    id: page

    readonly property bool compact: FlareData.style === "compact"
    readonly property var screenOptions: {
        const out = [
            {
                value: "",
                label: Strings.allScreens
            }
        ];
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            out.push({
                value: screens[i].name,
                label: screens[i].name
            });
        return out;
    }

    contentHeight: column.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: column

        width: page.width
        spacing: 14

        SettingsCard {
            title: Strings.edge

            SettingsRow {
                label: Strings.edge
                hint: Strings.edgeHint

                SettingsSegmented {
                    options: page.compact ? [
                        {
                            value: "top",
                            label: Strings.top
                        },
                        {
                            value: "bottom",
                            label: Strings.bottom
                        }
                    ] : [
                        {
                            value: "left",
                            label: Strings.left
                        },
                        {
                            value: "right",
                            label: Strings.right
                        }
                    ]
                    currentValue: page.compact ? FlareData.compactEdge : FlareData.notchEdge
                    onPicked: value => FlareData.set(page.compact ? "compact.edge" : "notch.edge", value)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.sheetLine
            }

            SettingsRow {
                label: Strings.slide + " · " + Math.round(offsetSlider.value) + " px"
                hint: Strings.dragHint

                SettingsButton {
                    text: Strings.centre
                    onClicked: FlareData.set(page.compact ? "compact.offset" : "notch.offset", 0)
                }
            }

            SettingsSlider {
                id: offsetSlider
                Layout.fillWidth: true
                from: -700
                to: 700
                stepSize: 1
                value: isNaN(FlareData.previewOffset) ? (page.compact ? FlareData.compactOffset : FlareData.notchOffset) : FlareData.previewOffset
                onMoved: FlareData.previewOffset = value
                onPressedChanged: {
                    if (!pressed)
                        FlareData.set(page.compact ? "compact.offset" : "notch.offset", Math.round(value));
                }
            }
        }

        SettingsCard {
            title: Strings.screen

            SettingsRow {
                label: Strings.screen
                hint: Strings.screenHint

                SettingsSegmented {
                    options: page.screenOptions
                    currentValue: FlareData.screen
                    onPicked: value => FlareData.set("notch.screen", value)
                }
            }
        }
    }
}
