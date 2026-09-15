import QtQuick
import Quickshell
import Quickshell.Wayland

// The settings surface. Everything it changes goes through `flare config set`,
// so it lands in the same config.toml a terminal would edit.
PanelWindow {
    id: win

    visible: FlareData.settingsOpen || closing.running
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "flare-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    implicitWidth: 1000
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
    }

    SettingsSheet {
        id: sheet
        anchors.fill: parent
        anchors.margins: 10
        opacity: 0
        scale: 0.96
        onCloseRequested: FlareData.settingsOpen = false
    }
}
