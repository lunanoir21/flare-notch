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
            title: Strings.dataSource

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        {
                            value: "official",
                            label: Strings.official,
                            hint: Strings.officialShort
                        },
                        {
                            value: "local",
                            label: Strings.localOnly,
                            hint: Strings.localShort
                        }
                    ]

                    SettingsChoiceCard {
                        id: choice

                        required property var modelData

                        label: modelData.label
                        hint: modelData.hint
                        selected: FlareData.dataMode === modelData.value
                        onPicked: {
                            FlareData.set("data.mode", modelData.value);
                            FlareData.refresh(true);
                        }

                        SettingsArt {
                            anchors.fill: parent
                            kind: choice.modelData.value
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: FlareData.dataMode === "local" ? Strings.localHint : Strings.officialHint
                color: Theme.sheetSubtext
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        SettingsCard {
            title: Strings.readings

            Repeater {
                model: FlareData.providers.filter(p => p.status !== "absent")

                RowLayout {
                    id: reading

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 12

                    Image {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        source: Theme.logo(reading.modelData.provider)
                        sourceSize: Qt.size(36, 36)
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        Layout.fillWidth: true
                        text: FlareData.names[reading.modelData.provider] || reading.modelData.provider
                        color: Theme.sheetText
                        font.pixelSize: 13
                    }

                    Text {
                        text: {
                            const p = reading.modelData;
                            const parts = [p.source === "official" ? Strings.official : Strings.localOnly];
                            const status = Strings.status(p.status);
                            if (status)
                                parts.push(status);
                            if (p.fetched_at)
                                parts.push(Strings.ago(FlareData.now - p.fetched_at));
                            return parts.join(" · ");
                        }
                        color: Theme.sheetMuted
                        font.pixelSize: 12
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.sheetLine
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    Layout.fillWidth: true
                    text: Strings.doctorHint
                    color: Theme.sheetMuted
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                SettingsButton {
                    text: Strings.refreshNow
                    primary: true
                    onClicked: FlareData.refresh(true)
                }
            }
        }
    }
}
