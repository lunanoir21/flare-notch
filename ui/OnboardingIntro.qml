import QtQuick
import QtQuick.Layouts

// The first-run setup's opening screens: what flare is, how the notch is used,
// and where the numbers come from. One component for all three — the screens
// differ only in their words and in the little drawing beside them.
Item {
    id: screen

    // Which of the opening screens to draw, 0 to 2.
    required property int which

    readonly property var pages: [
        {
            art: "classic",
            title: Strings.introWhatTitle,
            lines: [Strings.introWhatRing, Strings.introWhatEdge]
        },
        {
            art: "hover",
            title: Strings.introUseTitle,
            lines: [Strings.introUseHover, Strings.introUsePanel, Strings.introUseSettings]
        },
        {
            art: "official",
            title: Strings.introNumbersTitle,
            lines: [Strings.introNumbersOfficial, Strings.introNumbersLocal, Strings.introNumbersSafe]
        }
    ]

    readonly property var page: pages[Math.max(0, Math.min(pages.length - 1, screen.which))]

    RowLayout {
        anchors.fill: parent
        spacing: 40

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 18

            Text {
                Layout.fillWidth: true
                text: screen.page.title
                color: Theme.sheetText
                font.pixelSize: 26
                font.weight: Font.Bold
                font.letterSpacing: -0.4
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: screen.page.lines

                Text {
                    required property string modelData

                    Layout.fillWidth: true
                    Layout.maximumWidth: 460
                    Layout.alignment: Qt.AlignLeft
                    text: modelData
                    color: Theme.sheetSubtext
                    font.pixelSize: 14
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item {
            Layout.preferredWidth: 300
            Layout.fillHeight: true

            // The settings page's own drawings, a little larger: the notch with
            // a ring per provider, a pointer reaching for it, a globe for the
            // usage endpoints.
            SettingsArt {
                anchors.centerIn: parent
                width: 130
                height: 80
                scale: 1.7
                kind: screen.page.art
            }
        }
    }
}
