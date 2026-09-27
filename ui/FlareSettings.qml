import QtQuick
import Quickshell
import Quickshell.Wayland

// The settings surface, and the first-run setup that takes its place until it
// has been finished. Everything either of them changes goes through
// `flare config set`, so it lands in the same config.toml a terminal would
// edit.
PanelWindow {
    id: win

    visible: FlareData.settingsOpen || closing.running
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "flare-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // The setup is a narrower surface, and it holds that width while it fades
    // out: `onboarding` is only cleared once the closing animation is over.
    implicitWidth: FlareData.onboarding ? 720 : 1000
    implicitHeight: Math.min(660, (screen ? screen.height : 900) - 80)

    Connections {
        target: FlareData

        function onSettingsOpenChanged() {
            if (FlareData.settingsOpen) {
                closing.stop();
                opening.restart();
            } else {
                opening.stop();
                closing.restart();
            }
        }
    }

    Component.onCompleted: {
        if (FlareData.settingsOpen)
            opening.restart();
    }

    ParallelAnimation {
        id: opening
        NumberAnimation {
            target: sheet
            property: "opacity"
            to: 1
            duration: 200
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: sheet
            property: "scale"
            to: 1
            duration: 280
            easing.type: Easing.OutBack
            easing.overshoot: 1.1
        }
    }

    ParallelAnimation {
        id: closing
        NumberAnimation {
            target: sheet
            property: "opacity"
            to: 0
            duration: 140
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: sheet
            property: "scale"
            to: 0.96
            duration: 140
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: FlareData.onboardingClosed()
        }
    }

    // One surface or the other, never both: the settings page keeps its own
    // timers and its live preview, and there is no reason to run either while
    // the setup is up.
    Loader {
        id: sheet
        anchors.fill: parent
        anchors.margins: 10
        opacity: 0
        scale: 0.96
        sourceComponent: FlareData.onboarding ? setupSheet : settingsSheet
    }

    Component {
        id: settingsSheet

        SettingsSheet {
            onCloseRequested: FlareData.settingsOpen = false
        }
    }

    Component {
        id: setupSheet

        Onboarding {}
    }
}
