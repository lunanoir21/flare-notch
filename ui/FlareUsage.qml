import QtQuick
import Quickshell
import Quickshell.Wayland

// The usage panel's surface, opened from the hover card or `qs ipc call flare usage`.
PanelWindow {
    id: win

    visible: FlareData.usageOpen || closing.running
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.namespace: "flare-usage"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    implicitWidth: Math.min(1100, (screen ? screen.width : 1400) - 80)
    implicitHeight: Math.min(sheet.implicitHeight + 20, (screen ? screen.height : 900) - 80)

    Connections {
        target: FlareData

        function onUsageOpenChanged() {
            if (FlareData.usageOpen) {
                closing.stop();
                opening.restart();
            } else {
                opening.stop();
                closing.restart();
            }
        }
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
            duration: 260
            easing.type: Easing.OutCubic
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
            to: 0.97
            duration: 140
            easing.type: Easing.InCubic
        }
    }

    UsageSheet {
        id: sheet
        anchors.fill: parent
        anchors.margins: 10
        opacity: 0
        scale: 0.97
        onCloseRequested: FlareData.usageOpen = false
    }
}
