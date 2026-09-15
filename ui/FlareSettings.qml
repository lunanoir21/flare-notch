import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland

// flare's own settings page. Every change goes through `flare config set`, so
// it lands in the same config.toml a terminal would edit.
PanelWindow {
    id: win

    visible: FlareData.settingsOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "flare-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    implicitWidth: 400
    implicitHeight: Math.min(content.implicitHeight + 2, (screen ? screen.height : 900) - 96)

    readonly property bool compact: FlareData.style === "compact"

    component SectionLabel: Text {
        color: "#8A919A"
        font.pixelSize: 11
        font.weight: Font.Medium
        font.letterSpacing: 0.9
        font.capitalization: Font.AllUppercase
    }

    component Help: Text {
        width: parent ? parent.width : 0
        color: "#5B626B"
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    component Choice: Rectangle {
        id: choice

        required property string text
        property bool selected: false
        signal picked

        implicitWidth: label.implicitWidth + 22
        implicitHeight: 30
        radius: 7
        color: selected ? "#262B32" : (hover.hovered ? "#1B1F24" : "#171B20")
        border.color: selected ? "#3A414A" : "#242930"
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.checked: selected
        Keys.onSpacePressed: picked()
        Keys.onReturnPressed: picked()

        Text {
            id: label
            anchors.centerIn: parent
            text: choice.text
            color: choice.selected ? "#E8EAED" : "#8A919A"
            font.pixelSize: 13
        }

        HoverHandler {
            id: hover
        }

        TapHandler {
            onTapped: choice.picked()
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: FlareData.settingsOpen = false
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: "#111418"
        border.color: "#242930"

        Flickable {
            anchors.fill: parent
            anchors.margins: 1
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: content

                width: parent.width
                padding: 20
                spacing: 22

                Item {
                    width: content.width - 40
                    height: 30

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "flare · " + Strings.settingsTitle
                        color: "#E8EAED"
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }

                    Choice {
                        anchors.right: parent.right
                        text: Strings.close
                        onPicked: FlareData.settingsOpen = false
                    }
                }

                Column {
                    width: content.width - 40
                    spacing: 10

                    SectionLabel {
                        text: Strings.look
                    }

                    Row {
                        spacing: 8

                        Repeater {
                            model: [["classic", Strings.classic], ["aura", Strings.aura], ["compact", Strings.compact]]

                            Choice {
                                required property var modelData
                                text: modelData[1]
                                selected: FlareData.style === modelData[0]
                                onPicked: FlareData.set("notch.style", modelData[0])
                            }
                        }
                    }
                }

                Column {
                    width: content.width - 40
                    spacing: 10

                    SectionLabel {
                        text: Strings.position
                    }

                    Row {
                        spacing: 8

                        Repeater {
                            model: win.compact ? [["top", Strings.top], ["bottom", Strings.bottom]] : [["left", Strings.left], ["right", Strings.right]]

                            Choice {
                                required property var modelData
                                text: modelData[1]
                                selected: (win.compact ? FlareData.compactEdge : FlareData.notchEdge) === modelData[0]
                                onPicked: FlareData.set(win.compact ? "compact.edge" : "notch.edge", modelData[0])
                            }
                        }

                        Choice {
                            text: Strings.centre
                            onPicked: FlareData.set(win.compact ? "compact.offset" : "notch.offset", 0)
                        }
                    }

                    Text {
                        text: Strings.slide + "  ·  " + Math.round(offsetSlider.value) + " px"
                        color: "#E8EAED"
                        font.pixelSize: 13
                    }

                    Slider {
                        id: offsetSlider
                        width: parent.width
                        from: -700
                        to: 700
                        stepSize: 1
                        value: isNaN(FlareData.previewOffset) ? (win.compact ? FlareData.compactOffset : FlareData.notchOffset) : FlareData.previewOffset
                        onMoved: FlareData.previewOffset = value
                        onPressedChanged: {
                            if (!pressed)
                                FlareData.set(win.compact ? "compact.offset" : "notch.offset", Math.round(value));
                        }
                    }

                    Text {
                        text: Strings.size + "  ·  %" + Math.round(scaleSlider.value * 100)
                        color: "#E8EAED"
                        font.pixelSize: 13
                    }

                    Slider {
                        id: scaleSlider
                        width: parent.width
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

                    Help {
                        text: Strings.dragHint
                    }
                }

                Column {
                    width: content.width - 40
                    spacing: 8

                    SectionLabel {
                        text: Strings.providers
                    }

                    Repeater {
                        model: FlareData.allIds()

                        Rectangle {
                            id: providerRow

                            required property string modelData
                            required property int index

                            readonly property bool enabledHere: FlareData.section("providers")[modelData] !== false

                            width: parent.width
                            height: 44
                            radius: 9
                            color: "#171B20"
                            border.color: FlareData.style === "aura" && FlareData.focusedCell && FlareData.focusedCell.id === modelData ? FlareData.auraColour(modelData) : "#242930"

                            Text {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: providerRow.index + 1
                                color: "#8A919A"
                                font.pixelSize: 12
                                font.family: "monospace"
                            }

                            Image {
                                x: 34
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                source: Theme.logo(providerRow.modelData)
                                sourceSize: Qt.size(36, 36)
                                opacity: providerRow.enabledHere ? 1 : 0.4
                            }

                            Text {
                                x: 62
                                anchors.verticalCenter: parent.verticalCenter
                                text: FlareData.names[providerRow.modelData]
                                color: providerRow.enabledHere ? "#E8EAED" : "#5B626B"
                                font.pixelSize: 13
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                TextField {
                                    id: colourField
                                    width: 84
                                    height: 28
                                    text: FlareData.auraColour(providerRow.modelData)
                                    color: "#E8EAED"
                                    font.pixelSize: 12
                                    font.family: "monospace"
                                    leftPadding: 24
                                    maximumLength: 7
                                    validator: RegularExpressionValidator {
                                        regularExpression: /#[0-9A-Fa-f]{6}/
                                    }
                                    background: Rectangle {
                                        radius: 6
                                        color: "#0B0D10"
                                        border.color: colourField.activeFocus ? "#3A414A" : "#242930"

                                        Rectangle {
                                            x: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 12
                                            height: 12
                                            radius: 3
                                            color: FlareData.auraColour(providerRow.modelData)
                                        }
                                    }
                                    Accessible.name: FlareData.names[providerRow.modelData] + " aura"
                                    onAccepted: FlareData.set("aura." + providerRow.modelData, text)
                                    onEditingFinished: {
                                        if (acceptableInput && text !== FlareData.auraColour(providerRow.modelData))
                                            FlareData.set("aura." + providerRow.modelData, text);
                                    }
                                }

                                Choice {
                                    text: providerRow.enabledHere ? "✓" : "–"
                                    selected: providerRow.enabledHere
                                    implicitWidth: 28
                                    onPicked: FlareData.set("providers." + providerRow.modelData, !providerRow.enabledHere)
                                }

                                Choice {
                                    text: "▲"
                                    implicitWidth: 28
                                    opacity: providerRow.index === 0 ? 0.3 : 1
                                    onPicked: FlareData.move(providerRow.modelData, -1)
                                }

                                Choice {
                                    text: "▼"
                                    implicitWidth: 28
                                    opacity: providerRow.index === 3 ? 0.3 : 1
                                    onPicked: FlareData.move(providerRow.modelData, 1)
                                }
                            }
                        }
                    }

                    Help {
                        text: Strings.auraHint
                    }
                }

                Column {
                    width: content.width - 40
                    spacing: 10
                    visible: win.compact

                    SectionLabel {
                        text: Strings.compact + " · " + Strings.opens
                    }

                    Row {
                        spacing: 8

                        Repeater {
                            model: [["click", Strings.onTap], ["hover", Strings.onHover]]

                            Choice {
                                required property var modelData
                                text: modelData[1]
                                selected: FlareData.openOn === modelData[0]
                                onPicked: FlareData.set("compact.open_on", modelData[0])
                            }
                        }
                    }
                }

                Column {
                    width: content.width - 40
                    spacing: 10

                    SectionLabel {
                        text: Strings.data
                    }

                    Row {
                        spacing: 8

                        Repeater {
                            model: [["official", Strings.official], ["local", Strings.localOnly]]

                            Choice {
                                required property var modelData
                                text: modelData[1]
                                selected: FlareData.dataMode === modelData[0]
                                onPicked: {
                                    FlareData.set("data.mode", modelData[0]);
                                    FlareData.refresh(true);
                                }
                            }
                        }
                    }

                    Help {
                        text: FlareData.dataMode === "local" ? Strings.localHint : Strings.officialHint
                    }
                }

                Column {
                    width: content.width - 40
                    spacing: 10

                    SectionLabel {
                        text: Strings.screen
                    }

                    Flow {
                        width: parent.width
                        spacing: 8

                        Choice {
                            text: Strings.allScreens
                            selected: FlareData.screen === ""
                            onPicked: FlareData.set("notch.screen", "")
                        }

                        Repeater {
                            model: Quickshell.screens

                            Choice {
                                required property ShellScreen modelData
                                text: modelData.name
                                selected: FlareData.screen === modelData.name
                                onPicked: FlareData.set("notch.screen", modelData.name)
                            }
                        }
                    }
                }

                Column {
                    width: content.width - 40
                    spacing: 8

                    Choice {
                        text: Strings.refreshNow
                        onPicked: FlareData.refresh(true)
                    }

                    Text {
                        width: parent.width
                        text: Strings.file + ": " + FlareData.configPath
                        color: "#5B626B"
                        font.pixelSize: 11
                        font.family: "monospace"
                        wrapMode: Text.WrapAnywhere
                    }

                    Text {
                        width: parent.width
                        visible: FlareData.configProblem !== ""
                        text: FlareData.configProblem
                        color: Theme.critical
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
