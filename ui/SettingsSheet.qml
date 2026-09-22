import QtQuick
import QtQuick.Layouts

// Section list on the left, one focused page in the middle, the widget itself
// on the right, live.
Rectangle {
    id: sheet

    signal closeRequested

    property string section: "look"

    readonly property var sections: [
        {
            key: "look",
            label: Strings.navLook,
            hint: Strings.navLookHint,
            page: Strings.pageLookHint
        },
        {
            key: "placement",
            label: Strings.navPlacement,
            hint: Strings.navPlacementHint,
            page: Strings.pagePlacementHint
        },
        {
            key: "visibility",
            label: Strings.navVisibility,
            hint: Strings.navVisibilityHint,
            page: Strings.pageVisibilityHint
        },
        {
            key: "providers",
            label: Strings.navProviders,
            hint: Strings.navProvidersHint,
            page: Strings.pageProvidersHint
        },
        {
            key: "alerts",
            label: Strings.navAlerts,
            hint: Strings.navAlertsHint,
            page: Strings.pageAlertsHint
        },
        {
            key: "data",
            label: Strings.navData,
            hint: Strings.navDataHint,
            page: Strings.pageDataHint
        },
        {
            key: "about",
            label: Strings.navAbout,
            hint: Strings.navAboutHint,
            page: Strings.pageAboutHint
        }
    ]
    readonly property int sectionIndex: Math.max(0, sections.findIndex(s => s.key === section))
    readonly property var current: sections[sectionIndex]

    function open(key) {
        if (key === section)
            return;
        pageShift.y = sections.findIndex(s => s.key === key) > sectionIndex ? 12 : -12;
        page.opacity = 0;
        section = key;
        enter.restart();
    }

    radius: 20
    color: Theme.sheet
    border.color: Theme.sheetLine
    focus: true
    Keys.onEscapePressed: sheet.closeRequested()

    ParallelAnimation {
        id: enter
        NumberAnimation {
            target: page
            property: "opacity"
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pageShift
            property: "y"
            to: 0
            duration: 260
            easing.type: Easing.OutCubic
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 0

        ColumnLayout {
            Layout.preferredWidth: 212
            Layout.minimumWidth: 212
            Layout.maximumWidth: 212
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.bottomMargin: 18
                Layout.topMargin: 4
                spacing: 12

                NotchShape {
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 34
                    edge: "left"
                    depth: 14
                    length: 34
                    flare: 7
                    corner: 6
                    tint: FlareData.focusedCell ? FlareData.focusedCell.aura : "transparent"
                    tintStrength: 0.9
                }

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: "flare"
                        color: Theme.sheetText
                        font.pixelSize: 19
                        font.weight: Font.Bold
                        font.letterSpacing: -0.3
                    }

                    Text {
                        text: Strings.settingsTitle
                        color: Theme.sheetMuted
                        font.pixelSize: 12
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: nav.implicitHeight

                Rectangle {
                    width: parent.width
                    height: 48
                    y: sheet.sectionIndex * (height + nav.spacing)
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.06)

                    Behavior on y {
                        NumberAnimation {
                            duration: 260
                            easing.type: Easing.OutCubic
                        }
                    }

                    Rectangle {
                        x: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 18
                        radius: 1.5
                        color: Theme.sheetText
                    }
                }

                Column {
                    id: nav

                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: sheet.sections

                        SettingsNavRow {
                            required property var modelData

                            width: nav.width
                            icon: modelData.key
                            label: modelData.label
                            hint: modelData.hint
                            current: sheet.section === modelData.key
                            onActivated: sheet.open(modelData.key)
                        }
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }

            Text {
                Layout.leftMargin: 8
                text: Strings.escHint
                color: Theme.sheetMuted
                font.pixelSize: 11
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            Layout.topMargin: 18
            Layout.bottomMargin: 18
            color: Theme.sheetLine
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 22
            Layout.bottomMargin: 8
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        text: sheet.current.label
                        color: Theme.sheetText
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        font.letterSpacing: -0.4
                    }

                    Text {
                        Layout.fillWidth: true
                        text: sheet.current.page
                        color: Theme.sheetSubtext
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }

                SettingsButton {
                    Layout.alignment: Qt.AlignTop
                    text: Strings.close
                    onClicked: sheet.closeRequested()
                }
            }

            Loader {
                id: page

                Layout.fillWidth: true
                Layout.fillHeight: true
                transform: Translate {
                    id: pageShift
                }
                sourceComponent: {
                    switch (sheet.section) {
                    case "placement":
                        return placementPage;
                    case "visibility":
                        return visibilityPage;
                    case "providers":
                        return providersPage;
                    case "alerts":
                        return alertsPage;
                    case "data":
                        return dataPage;
                    case "about":
                        return aboutPage;
                    }
                    return lookPage;
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            Layout.topMargin: 18
            Layout.bottomMargin: 18
            color: Theme.sheetLine
        }

        ColumnLayout {
            Layout.preferredWidth: 244
            Layout.minimumWidth: 244
            Layout.maximumWidth: 244
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 10

            Text {
                text: Strings.preview
                color: Theme.sheetMuted
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 0.9
                font.capitalization: Font.AllUppercase
            }

            LivePreview {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            Text {
                Layout.fillWidth: true
                text: Strings.previewHint
                color: Theme.sheetMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }

    Component {
        id: lookPage
        PageLook {}
    }
    Component {
        id: placementPage
        PagePlacement {}
    }
    Component {
        id: visibilityPage
        PageVisibility {}
    }
    Component {
        id: providersPage
        PageProviders {}
    }
    Component {
        id: alertsPage
        PageAlerts {}
    }
    Component {
        id: dataPage
        PageData {}
    }
    Component {
        id: aboutPage
        PageAbout {}
    }
}
