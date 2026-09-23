import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Flickable {
    id: page

    readonly property var presets: ["#D97757", "#E0A458", "#7FB77E", "#3DD6C6", "#6E7BFF", "#B08CFF", "#E06C9F", "#C9CED6"]

    // Which login a card is, for a provider with more than one: the account's
    // email where the reading has it, else where the login came from.
    function loginLine(id) {
        if (FlareData.loginsOf(FlareData.kindOf(id)).length < 2)
            return "";
        const snapshot = FlareData.providers.find(p => p.provider === id);
        if (snapshot && snapshot.account)
            return snapshot.account;
        const login = FlareData.accountFor(id);
        return !login || login.origin === "default" ? Strings.defaultLogin
            : login.origin === "found" ? Strings.loginFound : Strings.loginFromConfig;
    }

    function summary(id, enabledHere) {
        if (!enabledHere)
            return Strings.hiddenLabel;
        const snapshot = FlareData.providers.find(p => p.provider === id);
        if (!snapshot)
            return Strings.checking;
        if (snapshot.status === "absent")
            return Strings.notInstalled;
        const cell = FlareData.cellFor(id);
        if (!cell)
            return Strings.status(snapshot.status) || Strings.noReading;
        if (!cell.metered)
            return cell.todayText;
        if (cell.head && cell.used !== null)
            return cell.label + " · " + Strings.windowLabel(cell.head.label);
        return Strings.status(cell.status) || Strings.noReading;
    }

    contentHeight: column.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: column

        width: page.width
        spacing: 12

        SettingsCard {
            title: Strings.accountsTitle

            SettingsRow {
                label: Strings.findAccounts
                hint: Strings.findAccountsHint

                SettingsToggle {
                    checked: FlareData.findAccounts
                    Accessible.name: Strings.findAccounts
                    onToggled: FlareData.set("providers.find_accounts", !FlareData.findAccounts)
                }
            }
        }

        SettingsCard {
            title: Strings.usagePanelTitle

            SettingsRow {
                label: Strings.usageAll
                hint: Strings.usageAllHint

                SettingsToggle {
                    checked: FlareData.usageAllProviders
                    Accessible.name: Strings.usageAll
                    onToggled: FlareData.set("usage.all_providers", !FlareData.usageAllProviders)
                }
            }
        }

        Repeater {
            model: FlareData.allIds()

            Rectangle {
                id: card

                required property string modelData
                required property int index

                readonly property bool enabledHere: !FlareData.isOff(modelData)
                readonly property bool otherLogin: FlareData.accountOf(modelData) !== ""
                readonly property string login: page.loginLine(modelData)
                readonly property color tint: FlareData.auraColour(modelData)
                readonly property string tintText: tint.toString().toUpperCase()
                readonly property bool last: index === FlareData.allIds().length - 1

                Layout.fillWidth: true
                implicitHeight: body.implicitHeight + 32
                radius: 16
                color: Theme.sheetRaised
                border.color: Theme.sheetLine

                ColumnLayout {
                    id: body

                    x: 16
                    y: 16
                    width: card.width - 32
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            radius: 12
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Theme.sheetLine
                            opacity: card.enabledHere ? 1 : 0.45

                            Image {
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                source: Theme.logo(card.modelData)
                                sourceSize: Qt.size(48, 48)
                                fillMode: Image.PreserveAspectFit
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: -3
                                width: 13
                                height: 13
                                radius: 6.5
                                visible: card.enabledHere && !card.otherLogin
                                color: card.tint
                                border.width: 2
                                border.color: Theme.sheetRaised
                            }

                            AccountBadge {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: -4
                                provider: card.modelData
                                size: 17
                                fill: card.enabledHere ? card.tint : Theme.sheetRaised
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                text: FlareData.nameOf(card.modelData)
                                color: card.enabledHere ? Theme.sheetText : Theme.sheetSubtext
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: card.login !== ""
                                text: card.login
                                color: Theme.sheetSubtext
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                            }

                            Text {
                                Layout.fillWidth: true
                                text: page.summary(card.modelData, card.enabledHere)
                                color: Theme.sheetMuted
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        SettingsButton {
                            text: "↑"
                            enabled: card.index > 0
                            opacity: enabled ? 1 : 0.3
                            Accessible.name: Strings.moveUp
                            onClicked: FlareData.move(card.modelData, -1)
                        }

                        SettingsButton {
                            text: "↓"
                            enabled: !card.last
                            opacity: enabled ? 1 : 0.3
                            Accessible.name: Strings.moveDown
                            onClicked: FlareData.move(card.modelData, 1)
                        }

                        SettingsToggle {
                            checked: card.enabledHere
                            Accessible.name: Strings.show + " " + FlareData.nameOf(card.modelData)
                            onToggled: FlareData.setShown(card.modelData, !card.enabledHere)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: card.enabledHere && card.otherLogin
                        text: Strings.colourFromConfig
                        color: Theme.sheetMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: card.enabledHere && !card.otherLogin
                        spacing: 5

                        Text {
                            text: Strings.colour
                            color: Theme.sheetSubtext
                            font.pixelSize: 12
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Repeater {
                            model: page.presets

                            Rectangle {
                                id: swatch

                                required property string modelData
                                readonly property bool chosen: card.tintText === modelData.toUpperCase()

                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                radius: 8
                                color: modelData
                                border.width: chosen ? 2 : 0
                                border.color: Theme.sheetText
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData
                                Accessible.checked: chosen

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 6
                                    height: 6
                                    radius: 3
                                    visible: swatch.chosen
                                    color: Theme.sheet
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    onClicked: FlareData.set("aura." + card.modelData, swatch.modelData)
                                }
                            }
                        }

                        TextField {
                            id: hexField

                            Layout.preferredWidth: 78
                            Layout.preferredHeight: 28
                            text: card.tintText
                            color: Theme.sheetText
                            font.pixelSize: 12
                            font.family: Theme.mono
                            horizontalAlignment: TextInput.AlignHCenter
                            maximumLength: 7
                            validator: RegularExpressionValidator {
                                regularExpression: /#[0-9A-Fa-f]{6}/
                            }
                            background: Rectangle {
                                radius: 8
                                color: Theme.sheet
                                border.color: hexField.activeFocus ? Theme.sheetSubtext : Theme.sheetLine
                            }
                            Accessible.name: Strings.colour + " " + FlareData.nameOf(card.modelData)
                            onEditingFinished: {
                                if (acceptableInput && text.toUpperCase() !== card.tintText)
                                    FlareData.set("aura." + card.modelData, text.toUpperCase());
                            }
                        }
                    }
                }
            }
        }
    }
}
