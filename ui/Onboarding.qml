import QtQuick
import QtQuick.Layouts

// The first-run setup, in the settings page's own surface: the language
// first, then what flare is, then which providers to draw. One screen at a
// time, no way past it but forward — the last one writes ui.onboarded and
// the window closes as it does for the settings.
Rectangle {
    id: wizard

    property int step: 0
    // The language, three opening screens, then the providers.
    readonly property int steps: 5
    readonly property bool last: step === steps - 1

    function go(where) {
        if (where < 0 || where >= steps)
            return;
        page.opacity = 0;
        pageShift.y = where > step ? 14 : -14;
        step = where;
        enter.restart();
    }

    function forward() {
        if (last)
            FlareData.finishOnboarding();
        else
            go(step + 1);
    }

    radius: 20
    color: Theme.sheet
    border.color: Theme.sheetLine
    focus: true
    Keys.onReturnPressed: wizard.forward()

    Component.onCompleted: {
        page.opacity = 0;
        enter.restart();
    }

    // Each screen arrives the way the settings page's pages do: in from the
    // side it is coming from.
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 20
            Layout.bottomMargin: 16
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

            Text {
                text: "flare"
                color: Theme.sheetText
                font.pixelSize: 19
                font.weight: Font.Bold
                font.letterSpacing: -0.3
            }

            Text {
                text: Strings.onboardingTitle
                color: Theme.sheetMuted
                font.pixelSize: 12
            }

            Item {
                Layout.fillWidth: true
            }

            Row {
                id: dots

                spacing: 6

                Repeater {
                    model: wizard.steps

                    Rectangle {
                        required property int index

                        readonly property bool current: index === wizard.step

                        width: current ? 18 : 6
                        height: 6
                        radius: 3
                        color: current ? Theme.sheetText : Qt.rgba(1, 1, 1, 0.18)
                        Accessible.role: Accessible.Indicator
                        Accessible.name: Strings.stepOf(index + 1, wizard.steps)

                        Behavior on width {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            color: Theme.sheetLine
        }

        Loader {
            id: page

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 24
            transform: Translate {
                id: pageShift
            }
            sourceComponent: {
                switch (wizard.step) {
                case 1:
                    return openingWhat;
                case 2:
                    return openingUse;
                case 3:
                    return openingNumbers;
                case 4:
                    return providers;
                }
                return language;
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 8
            Layout.bottomMargin: 20
            spacing: 10

            SettingsButton {
                text: Strings.back
                enabled: wizard.step > 0
                opacity: enabled ? 1 : 0.3
                onClicked: wizard.go(wizard.step - 1)
            }

            Item {
                Layout.fillWidth: true
            }

            SettingsButton {
                text: wizard.last ? Strings.finish : Strings.next
                primary: true
                onClicked: wizard.forward()
            }
        }
    }

    Component {
        id: openingWhat

        OnboardingIntro {
            which: 0
        }
    }
    Component {
        id: openingUse

        OnboardingIntro {
            which: 1
        }
    }
    Component {
        id: openingNumbers

        OnboardingIntro {
            which: 2
        }
    }
    Component {
        id: language

        OnboardingLanguage {}
    }
    Component {
        id: providers

        OnboardingProviders {}
    }
}
